// Moteur d'enregistrement.
//
// - MediaRecorder mono à 32 kb/s (≈ 14 Mo/heure) : suffisant pour la voix,
//   et assez léger pour les API de transcription.
// - Chaque morceau de 5 s est écrit immédiatement dans IndexedDB : si le
//   téléphone se verrouille ou que l'app est tuée, on récupère tout au
//   prochain lancement.
// - Verrou d'écran (Wake Lock) : les navigateurs mobiles coupent le micro
//   quand l'écran s'éteint, donc on le garde allumé pendant la khoutba.

import { ajouterChunk, viderChunks } from './db.js';

const DUREE_MAX_S = 3 * 3600;      // arrêt automatique à 3 h
const TRANCHE_MS = 5000;           // écriture d'un chunk toutes les 5 s

export function mimeSupporte() {
  if (typeof MediaRecorder === 'undefined') return null;
  const candidats = ['audio/webm;codecs=opus', 'audio/mp4', 'audio/webm'];
  for (const m of candidats) {
    if (MediaRecorder.isTypeSupported(m)) return m;
  }
  return ''; // laisser le navigateur choisir
}

export class Enregistreur {
  constructor({ onTick, onNiveau, onErreur, onArretAuto } = {}) {
    this.onTick = onTick || (() => {});
    this.onNiveau = onNiveau || (() => {});
    this.onErreur = onErreur || (() => {});
    this.onArretAuto = onArretAuto || (() => {});
    this.id = null;
    this.mimeType = '';
    this.actif = false;
    this.enPause = false;
    this._chunks = [];
    this._idx = 0;
    this._debutSegment = 0;
    this._dureeCumulee = 0;   // secondes actives hors segment courant
    this._timer = null;
    this._wakeLock = null;
    this._raf = null;
  }

  async demarrer() {
    if (this.actif) return;
    const mime = mimeSupporte();
    if (mime === null) throw new Error("Ce navigateur ne sait pas enregistrer l'audio (MediaRecorder absent).");

    this._stream = await navigator.mediaDevices.getUserMedia({
      audio: {
        channelCount: 1,
        // La voix de l'imam vient de loin / des haut-parleurs : on laisse le
        // gain automatique mais on coupe les filtres pensés pour la visio,
        // qui dégradent la parole lointaine.
        echoCancellation: false,
        noiseSuppression: false,
        autoGainControl: true,
      },
    });

    this.id = (crypto.randomUUID && crypto.randomUUID()) || String(Date.now());
    this.mimeType = mime;
    this._chunks = [];
    this._idx = 0;
    this._dureeCumulee = 0;

    const options = { audioBitsPerSecond: 32000 };
    if (mime) options.mimeType = mime;
    this._rec = new MediaRecorder(this._stream, options);
    this.mimeType = this._rec.mimeType || mime || 'audio/webm';

    this._rec.ondataavailable = (e) => {
      if (!e.data || !e.data.size) return;
      this._chunks.push(e.data);
      const idx = this._idx++;
      // Filet de sécurité : écrit sans attendre, une erreur ne bloque pas l'enregistrement.
      ajouterChunk(this.id, idx, e.data, this.mimeType).catch(() => {});
    };
    this._rec.onerror = (e) => this.onErreur(e.error || new Error("Erreur d'enregistrement"));

    this._rec.start(TRANCHE_MS);
    this.actif = true;
    this.enPause = false;
    this._debutSegment = Date.now();

    this._demarrerVuMetre();
    await this._prendreWakeLock();
    this._surVisibilite = () => {
      // Le wake lock saute quand on change d'app : on le reprend au retour.
      if (document.visibilityState === 'visible' && this.actif) this._prendreWakeLock();
    };
    document.addEventListener('visibilitychange', this._surVisibilite);

    this._timer = setInterval(() => {
      const s = this.duree();
      this.onTick(s);
      if (s >= DUREE_MAX_S) { this.onArretAuto(); }
    }, 500);
  }

  duree() {
    let s = this._dureeCumulee;
    if (this.actif && !this.enPause) s += (Date.now() - this._debutSegment) / 1000;
    return s;
  }

  pause() {
    if (!this.actif || this.enPause) return;
    this._dureeCumulee = this.duree();
    this.enPause = true;
    try { this._rec.pause(); } catch { /* certains navigateurs ne gèrent pas pause() */ }
  }

  reprendre() {
    if (!this.actif || !this.enPause) return;
    this.enPause = false;
    this._debutSegment = Date.now();
    try { this._rec.resume(); } catch { }
  }

  // Termine et renvoie { id, blob, duree, mimeType }. Les chunks de secours
  // sont effacés par l'appelant une fois l'enregistrement sauvegardé.
  arreter() {
    if (!this.actif) return Promise.resolve(null);
    const duree = Math.round(this.duree());
    return new Promise((resolve) => {
      this._rec.onstop = () => {
        this._nettoyer();
        const blob = new Blob(this._chunks, { type: this.mimeType });
        resolve({ id: this.id, blob, duree, mimeType: this.mimeType });
      };
      try { this._rec.stop(); } catch {
        this._nettoyer();
        resolve({ id: this.id, blob: new Blob(this._chunks, { type: this.mimeType }), duree, mimeType: this.mimeType });
      }
    });
  }

  async annuler() {
    const id = this.id;
    try { await this.arreter(); } catch { }
    if (id) await viderChunks(id).catch(() => {});
  }

  _nettoyer() {
    this.actif = false;
    clearInterval(this._timer);
    cancelAnimationFrame(this._raf);
    document.removeEventListener('visibilitychange', this._surVisibilite || (() => {}));
    if (this._wakeLock) { this._wakeLock.release().catch(() => {}); this._wakeLock = null; }
    if (this._audioCtx) { this._audioCtx.close().catch(() => {}); this._audioCtx = null; }
    if (this._stream) { this._stream.getTracks().forEach(t => t.stop()); this._stream = null; }
  }

  async _prendreWakeLock() {
    try {
      if ('wakeLock' in navigator) this._wakeLock = await navigator.wakeLock.request('screen');
    } catch { /* pas bloquant */ }
  }

  _demarrerVuMetre() {
    try {
      const Ctx = window.AudioContext || window.webkitAudioContext;
      this._audioCtx = new Ctx();
      const source = this._audioCtx.createMediaStreamSource(this._stream);
      const analyseur = this._audioCtx.createAnalyser();
      analyseur.fftSize = 512;
      source.connect(analyseur);
      const donnees = new Uint8Array(analyseur.frequencyBinCount);
      const boucle = () => {
        if (!this.actif) return;
        analyseur.getByteTimeDomainData(donnees);
        let max = 0;
        for (let i = 0; i < donnees.length; i++) {
          const v = Math.abs(donnees[i] - 128) / 128;
          if (v > max) max = v;
        }
        this.onNiveau(this.enPause ? 0 : max);
        this._raf = requestAnimationFrame(boucle);
      };
      boucle();
    } catch { /* vu-mètre facultatif */ }
  }
}
