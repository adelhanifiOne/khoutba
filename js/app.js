// Khoutba — interface principale.
// Application 100% locale : enregistrements et clés API restent sur l'appareil.

import {
  listerEnregistrements, lireEnregistrement, sauverEnregistrement,
  supprimerEnregistrement, lireChunks, viderChunks, idsChunksOrphelins,
} from './db.js';
import { Enregistreur, mimeSupporte } from './recorder.js';
import { traiterEnregistrement, traitementEnCours, statutStable } from './pipeline.js';
import {
  CHOIX_MODELES_CLAUDE, MODELES,
  geminiListerModeles, modeleGeminiRetenu, reinitialiserModelesGemini,
} from './providers.js';

const VERSION_APP = '1.0.1';

// ------------------------------------------------------------------ réglages

const REGLAGES_DEFAUT = {
  stt: '',                    // '' | 'gemini' | 'openai'
  llm: '',                    // '' | 'gemini' | 'openai' | 'anthropic'
  modeleClaude: MODELES.claudeParDefaut,
  modeleGemini: '',           // '' = choix automatique du meilleur disponible
  cles: { gemini: '', openai: '', anthropic: '' },
  langue: 'fr',
  demo: false,
};

function lireReglages() {
  try {
    const brut = JSON.parse(localStorage.getItem('khoutba.reglages') || '{}');
    return { ...REGLAGES_DEFAUT, ...brut, cles: { ...REGLAGES_DEFAUT.cles, ...(brut.cles || {}) } };
  } catch { return { ...REGLAGES_DEFAUT }; }
}

function ecrireReglages(r) {
  localStorage.setItem('khoutba.reglages', JSON.stringify(r));
}

// ----------------------------------------------------------------- utilitaires

const $ = (sel, racine = document) => racine.querySelector(sel);

function echap(s) {
  return String(s ?? '').replace(/[&<>"']/g, c => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]
  ));
}

function fmtDuree(s) {
  s = Math.max(0, Math.round(s || 0));
  const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60;
  const mm = String(m).padStart(2, '0'), ss = String(sec).padStart(2, '0');
  return h ? `${h}:${mm}:${ss}` : `${m}:${ss}`;
}

function fmtDate(iso, opts) {
  try {
    return new Intl.DateTimeFormat('fr-FR', opts || { weekday: 'long', day: 'numeric', month: 'long', hour: '2-digit', minute: '2-digit' }).format(new Date(iso));
  } catch { return iso; }
}

function majuscule(s) { return s ? s.charAt(0).toUpperCase() + s.slice(1) : s; }

function toast(message, duree = 2600) {
  const el = $('#toast');
  el.textContent = message;
  el.classList.add('visible');
  clearTimeout(toast._t);
  toast._t = setTimeout(() => el.classList.remove('visible'), duree);
}

const LIBELLES_STATUT = {
  pret: ['À traiter', 'badge-neutre'],
  transcription: ['Transcription…', 'badge-actif'],
  transcrit: ['Transcrit', 'badge-etape'],
  traduction: ['Traduction…', 'badge-actif'],
  traduit: ['Traduit', 'badge-etape'],
  synthese: ['Synthèse…', 'badge-actif'],
  termine: ['Terminé', 'badge-ok'],
  erreur: ['Erreur', 'badge-erreur'],
};

function badgeStatut(statut) {
  const [libelle, classe] = LIBELLES_STATUT[statut] || [statut, 'badge-neutre'];
  return `<span class="badge ${classe}">${echap(libelle)}</span>`;
}

function titreParDefaut(dateIso) {
  return majuscule(`khoutba du ${fmtDate(dateIso, { weekday: 'long', day: 'numeric', month: 'long' })}`);
}

// Durée d'un blob audio via un élément <audio> (gère les webm sans en-tête de durée)
function sonderDuree(blob) {
  return new Promise((resolve) => {
    const url = URL.createObjectURL(blob);
    const audio = new Audio();
    const fini = (d) => { URL.revokeObjectURL(url); resolve(Number.isFinite(d) && d > 0 ? Math.round(d) : 0); };
    const minuterie = setTimeout(() => fini(0), 5000);
    audio.addEventListener('loadedmetadata', () => {
      if (Number.isFinite(audio.duration)) { clearTimeout(minuterie); fini(audio.duration); }
      else {
        // Astuce Chrome pour les webm : forcer le calcul de la durée
        audio.currentTime = 1e10;
        audio.addEventListener('durationchange', () => {
          if (Number.isFinite(audio.duration)) { clearTimeout(minuterie); fini(audio.duration); }
        }, { once: true });
      }
    });
    audio.addEventListener('error', () => { clearTimeout(minuterie); fini(0); });
    audio.src = url;
  });
}

// --------------------------------------------------------------------- état

let reglages = lireReglages();
let enregistreur = null;
let urlAudioCourante = null;
let statutTraitement = null;   // { recId, phase, partiel }

// ------------------------------------------------------------------- routage

function route() {
  const h = location.hash;
  if (h.startsWith('#rec/')) return { vue: 'detail', id: decodeURIComponent(h.slice(5)) };
  if (h === '#reglages') return { vue: 'reglages' };
  return { vue: 'accueil' };
}

async function rendre() {
  if (urlAudioCourante) { URL.revokeObjectURL(urlAudioCourante); urlAudioCourante = null; }
  const r = route();
  const vues = { accueil: rendreAccueil, detail: rendreDetail, reglages: rendreReglages };
  await (vues[r.vue] || rendreAccueil)(r);
  window.scrollTo(0, 0);
}

window.addEventListener('hashchange', rendre);

// ------------------------------------------------------------------- accueil

async function rendreAccueil() {
  const recs = await listerEnregistrements();
  const principal = $('#app');

  const cartes = recs.map(rec => `
    <a class="carte" href="#rec/${encodeURIComponent(rec.id)}">
      <div class="carte-texte">
        <div class="carte-titre">${echap(rec.titre || titreParDefaut(rec.createdAt))}</div>
        <div class="carte-sous">${echap(majuscule(fmtDate(rec.createdAt)))} · ${fmtDuree(rec.duree)}</div>
      </div>
      ${badgeStatut(rec.statut)}
    </a>`).join('');

  principal.innerHTML = `
    <header class="entete">
      <div class="marque">
        <img src="icons/icon.svg" alt="" class="logo"/>
        <div><h1>Khoutba</h1><p class="devise">Enregistre, comprends, retiens.</p></div>
      </div>
      <a class="bouton-icone" href="#reglages" aria-label="Réglages" title="Réglages">⚙️</a>
    </header>

    ${reglages.demo ? `<div class="bandeau">Mode démo actif — les textes générés sont fictifs. <a href="#reglages">Réglages</a></div>` : ''}

    <section class="zone-enregistrer">
      <button id="btn-enregistrer" class="btn-micro" aria-label="Enregistrer">
        <svg viewBox="0 0 24 24" width="34" height="34" fill="currentColor" aria-hidden="true"><path d="M12 14a3 3 0 0 0 3-3V6a3 3 0 1 0-6 0v5a3 3 0 0 0 3 3Zm5-3a5 5 0 0 1-10 0H5a7 7 0 0 0 6 6.92V21h2v-3.08A7 7 0 0 0 19 11h-2Z"/></svg>
      </button>
      <p class="aide-micro">Appuie pour enregistrer le prêche</p>
      <button id="btn-importer" class="lien">ou importer un fichier audio</button>
      <input type="file" id="input-import" accept="audio/*,video/mp4" hidden />
    </section>

    <section class="liste">
      <h2>Mes khoutbas</h2>
      ${cartes || `<p class="vide">Aucun enregistrement pour l'instant.<br/>Vendredi prochain, in cha Allah 🌙</p>`}
    </section>

    <footer class="pied">Tout reste sur ton téléphone. L'audio n'est envoyé qu'au service d'IA que tu choisis, au moment du traitement.</footer>
  `;

  $('#btn-enregistrer').addEventListener('click', demarrerEnregistrement);
  $('#btn-importer').addEventListener('click', () => $('#input-import').click());
  $('#input-import').addEventListener('change', importerFichier);
}

// -------------------------------------------------------------- enregistrement

async function demarrerEnregistrement() {
  if (enregistreur?.actif) return;
  if (!navigator.mediaDevices?.getUserMedia) {
    toast("Ce navigateur ne permet pas d'accéder au micro."); return;
  }
  if (mimeSupporte() === null) {
    toast("Enregistrement non pris en charge par ce navigateur."); return;
  }

  navigator.storage?.persist?.().catch(() => {});

  enregistreur = new Enregistreur({
    onTick: (s) => { const el = $('#chrono'); if (el) el.textContent = fmtDuree(s); },
    onNiveau: dessinerNiveau,
    onErreur: (e) => toast(`Erreur d'enregistrement : ${e.message || e}`),
    onArretAuto: () => terminerEnregistrement(),
  });

  try {
    await enregistreur.demarrer();
  } catch (e) {
    enregistreur = null;
    if (e && (e.name === 'NotAllowedError' || e.name === 'SecurityError')) {
      toast("Accès au micro refusé. Autorise le micro pour l'app dans les réglages du téléphone.", 4200);
    } else if (e && e.name === 'NotFoundError') {
      toast('Aucun micro détecté.');
    } else {
      toast(`Impossible de démarrer : ${e.message || e}`, 4000);
    }
    return;
  }

  $('#voile-enregistrement').classList.add('visible');
  $('#btn-pause').textContent = 'Pause';
  $('#chrono').textContent = '0:00';
}

function dessinerNiveau(niveau) {
  const canevas = $('#vumetre');
  if (!canevas) return;
  const ctx = canevas.getContext('2d');
  const { width: L, height: H } = canevas;
  ctx.clearRect(0, 0, L, H);
  dessinerNiveau._hist = dessinerNiveau._hist || new Array(48).fill(0.02);
  dessinerNiveau._hist.push(Math.min(1, niveau * 1.6));
  dessinerNiveau._hist.shift();
  const larg = L / 48;
  ctx.fillStyle = getComputedStyle(document.documentElement).getPropertyValue('--accent').trim() || '#0f6b4f';
  dessinerNiveau._hist.forEach((v, i) => {
    const h = Math.max(3, v * H);
    ctx.beginPath();
    ctx.roundRect(i * larg + larg * 0.2, (H - h) / 2, larg * 0.6, h, 2);
    ctx.fill();
  });
}

async function terminerEnregistrement() {
  if (!enregistreur?.actif) return;
  const resultat = await enregistreur.arreter();
  enregistreur = null;
  $('#voile-enregistrement').classList.remove('visible');
  if (!resultat || !resultat.blob.size) { toast('Enregistrement vide.'); return; }

  const rec = {
    id: resultat.id,
    titre: '',
    titrePerso: false,
    createdAt: new Date().toISOString(),
    duree: resultat.duree,
    mimeType: resultat.mimeType,
    audio: resultat.blob,
    statut: 'pret',
    transcript: null, traduction: null, synthese: null, erreur: null,
  };
  rec.titre = titreParDefaut(rec.createdAt);
  await sauverEnregistrement(rec);
  await viderChunks(rec.id).catch(() => {});
  toast('Enregistrement sauvegardé ✓');
  location.hash = `#rec/${rec.id}`;
}

async function annulerEnregistrement() {
  if (!enregistreur) return;
  if (!confirm("Abandonner cet enregistrement ?")) return;
  await enregistreur.annuler();
  enregistreur = null;
  $('#voile-enregistrement').classList.remove('visible');
}

function basculerPause() {
  if (!enregistreur) return;
  if (enregistreur.enPause) { enregistreur.reprendre(); $('#btn-pause').textContent = 'Pause'; }
  else { enregistreur.pause(); $('#btn-pause').textContent = 'Reprendre'; }
}

async function importerFichier(ev) {
  const fichier = ev.target.files?.[0];
  ev.target.value = '';
  if (!fichier) return;
  if (!/^(audio\/|video\/mp4)/.test(fichier.type || '')) { toast('Choisis un fichier audio.'); return; }

  const duree = await sonderDuree(fichier);
  const rec = {
    id: (crypto.randomUUID && crypto.randomUUID()) || String(Date.now()),
    titre: fichier.name.replace(/\.[^.]+$/, ''),
    titrePerso: false,
    createdAt: new Date().toISOString(),
    duree,
    mimeType: fichier.type || 'audio/mpeg',
    audio: fichier,
    statut: 'pret',
    transcript: null, traduction: null, synthese: null, erreur: null,
  };
  await sauverEnregistrement(rec);
  toast('Audio importé ✓');
  location.hash = `#rec/${rec.id}`;
}

// Récupère les enregistrements interrompus (app fermée pendant la khoutba)
async function recupererOrphelins() {
  const ids = await idsChunksOrphelins().catch(() => []);
  for (const id of ids) {
    const existant = await lireEnregistrement(id);
    if (existant) { await viderChunks(id).catch(() => {}); continue; }
    const morceaux = await lireChunks(id);
    if (!morceaux.length) continue;
    const mime = morceaux[0].mimeType || 'audio/webm';
    const blob = new Blob(morceaux.map(m => m.blob), { type: mime });
    if (!blob.size) { await viderChunks(id); continue; }
    const duree = await sonderDuree(blob);
    const rec = {
      id,
      titre: '⚠️ Enregistrement récupéré',
      titrePerso: true,
      createdAt: new Date().toISOString(),
      duree, mimeType: mime, audio: blob,
      statut: 'pret', transcript: null, traduction: null, synthese: null, erreur: null,
    };
    await sauverEnregistrement(rec);
    await viderChunks(id).catch(() => {});
    toast('Un enregistrement interrompu a été récupéré ✓', 4000);
  }
}

// -------------------------------------------------------------------- détail

function texteProgression(s) {
  if (!s) return '';
  if (s.phase === 'transcription') return 'Transcription de l’arabe en cours… (peut prendre quelques minutes)';
  if (s.phase === 'traduction') {
    const n = s.partiel ? ` — ${s.partiel.length.toLocaleString('fr-FR')} caractères` : '';
    return `Traduction en cours…${n}`;
  }
  if (s.phase === 'synthese') return 'Rédaction du résumé et des points clés…';
  return '';
}

async function rendreDetail({ id }) {
  const rec = await lireEnregistrement(id);
  if (!rec) { location.hash = ''; return; }

  const enTraitement = statutTraitement?.recId === id;
  const ongletDefaut = rec.synthese ? 'resume' : (rec.traduction ? 'traduction' : (rec.transcript ? 'arabe' : 'resume'));
  const libelleTraiter = rec.statut === 'erreur' ? 'Réessayer'
    : rec.statut === 'termine' ? 'Retraiter'
    : rec.transcript ? 'Continuer le traitement' : 'Transcrire & traduire';

  urlAudioCourante = URL.createObjectURL(rec.audio);

  $('#app').innerHTML = `
    <header class="entete">
      <a class="bouton-icone" href="#" aria-label="Retour">←</a>
      <input id="champ-titre" class="champ-titre" value="${echap(rec.titre || '')}" aria-label="Titre" />
      <button class="bouton-icone" id="btn-supprimer" aria-label="Supprimer" title="Supprimer">🗑</button>
    </header>

    <div class="meta-detail">${echap(majuscule(fmtDate(rec.createdAt)))} · ${fmtDuree(rec.duree)} ${badgeStatut(rec.statut)}</div>

    <audio controls preload="metadata" src="${urlAudioCourante}" class="lecteur"></audio>

    <div class="actions">
      <button id="btn-traiter" class="btn-principal" ${enTraitement ? 'disabled' : ''}>${echap(libelleTraiter)}</button>
      <button id="btn-exporter" class="btn-secondaire" ${rec.transcript ? '' : 'disabled'}>Exporter</button>
      <button id="btn-partager" class="btn-secondaire" ${rec.synthese || rec.traduction ? '' : 'disabled'}>Partager</button>
    </div>

    <div id="progression" class="progression ${enTraitement ? 'visible' : ''}">
      <span class="spinner"></span><span id="texte-progression">${echap(texteProgression(statutTraitement))}</span>
    </div>

    ${rec.erreur && !enTraitement ? `<div class="encart-erreur">${echap(rec.erreur)}</div>` : ''}

    <nav class="onglets" role="tablist">
      <button class="onglet" data-onglet="resume" role="tab">Résumé</button>
      <button class="onglet" data-onglet="traduction" role="tab">Traduction</button>
      <button class="onglet" data-onglet="arabe" role="tab">النص العربي</button>
    </nav>
    <section id="contenu-onglet" class="contenu-onglet"></section>
  `;

  const afficherOnglet = (nom) => {
    document.querySelectorAll('.onglet').forEach(b => b.classList.toggle('actif', b.dataset.onglet === nom));
    $('#contenu-onglet').innerHTML = contenuOnglet(rec, nom);
  };
  document.querySelectorAll('.onglet').forEach(b =>
    b.addEventListener('click', () => afficherOnglet(b.dataset.onglet)));
  afficherOnglet(ongletDefaut);

  // Titre modifiable
  const champTitre = $('#champ-titre');
  champTitre.addEventListener('change', async () => {
    rec.titre = champTitre.value.trim() || titreParDefaut(rec.createdAt);
    rec.titrePerso = true;
    await sauverEnregistrement(rec);
    toast('Titre enregistré ✓');
  });

  $('#btn-supprimer').addEventListener('click', async () => {
    if (!confirm('Supprimer cet enregistrement et ses textes ? Cette action est définitive.')) return;
    await supprimerEnregistrement(rec.id);
    toast('Supprimé.');
    location.hash = '';
  });

  $('#btn-exporter').addEventListener('click', () => exporterMarkdown(rec));
  $('#btn-partager').addEventListener('click', () => partager(rec));

  $('#btn-traiter').addEventListener('click', async () => {
    if (traitementEnCours()) { toast('Un traitement est déjà en cours.'); return; }
    if (!reglages.demo && (!reglages.stt || !reglages.llm)) {
      toast('Configure d’abord les fournisseurs IA dans les réglages.', 3800);
      location.hash = '#reglages';
      return;
    }
    const forcer = rec.statut === 'termine';
    if (forcer && !confirm('Relancer tout le traitement (transcription comprise) ?')) return;

    statutTraitement = { recId: rec.id, phase: 'transcription' };
    try {
      await traiterEnregistrement(rec, reglages, (s) => {
        statutTraitement = { recId: rec.id, ...s };
        if (route().vue === 'detail' && route().id === rec.id) {
          const zone = $('#progression'), texte = $('#texte-progression');
          if (zone && texte) { zone.classList.add('visible'); texte.textContent = texteProgression(s); }
        }
      }, { forcer });
      toast('Traitement terminé ✓');
    } catch (e) {
      toast(`Échec : ${e.message || e}`, 5000);
    } finally {
      statutTraitement = null;
      if (route().vue === 'detail' && route().id === rec.id) rendre();
    }
  });
}

function contenuOnglet(rec, nom) {
  if (nom === 'arabe') {
    if (!rec.transcript) return videOnglet('La transcription arabe apparaîtra ici après le traitement.');
    return `<article class="texte-arabe" dir="rtl" lang="ar">${paragraphes(rec.transcript)}</article>`;
  }
  if (nom === 'traduction') {
    if (!rec.traduction) return videOnglet('La traduction apparaîtra ici après le traitement.');
    return `<article class="texte-traduction">${paragraphes(rec.traduction)}</article>`;
  }
  // Résumé
  const s = rec.synthese;
  if (!s) return videOnglet('Le résumé, les points clés et les citations apparaîtront ici après le traitement.');
  const citations = (s.citations || []).map(c => `
    <div class="citation">
      <div class="citation-arabe" dir="rtl" lang="ar">${echap(c.texte_arabe)}</div>
      <div class="citation-trad">${echap(c.traduction)}</div>
      <div class="citation-ref">${echap(c.type === 'coran' ? '📖' : c.type === 'hadith' ? '💬' : '•')} ${echap(c.reference)}</div>
    </div>`).join('');
  return `
    <article class="synthese">
      <p class="theme">${echap(s.theme || '')}</p>
      <h3>Résumé</h3>
      ${paragraphes(s.resume || '')}
      ${lg(s.points_cles) ? `<h3>Points clés</h3><ul>${s.points_cles.map(p => `<li>${echap(p)}</li>`).join('')}</ul>` : ''}
      ${citations ? `<h3>Versets & hadiths cités</h3>${citations}` : ''}
      ${lg(s.conseils) ? `<h3>Conseils pratiques</h3><ul>${s.conseils.map(c => `<li>${echap(c)}</li>`).join('')}</ul>` : ''}
      ${lg(s.douas) ? `<h3>Douas</h3><ul>${s.douas.map(d => `<li>${echap(d)}</li>`).join('')}</ul>` : ''}
    </article>`;
}

function lg(a) { return Array.isArray(a) && a.length; }
function videOnglet(msg) { return `<p class="vide">${echap(msg)}</p>`; }
function paragraphes(texte) {
  return String(texte).split(/\n{2,}|\r\n{2,}/).map(p => `<p>${echap(p.trim()).replace(/\n/g, '<br/>')}</p>`).join('');
}

// ----------------------------------------------------------- export & partage

function markdownDe(rec) {
  const s = rec.synthese || {};
  const l = [];
  l.push(`# ${rec.titre || titreParDefaut(rec.createdAt)}`);
  l.push(`\n*${majuscule(fmtDate(rec.createdAt))} · ${fmtDuree(rec.duree)}*\n`);
  if (s.theme) l.push(`**Thème :** ${s.theme}\n`);
  if (s.resume) l.push(`## Résumé\n\n${s.resume}\n`);
  if (lg(s.points_cles)) l.push(`## Points clés\n\n${s.points_cles.map(p => `- ${p}`).join('\n')}\n`);
  if (lg(s.citations)) {
    l.push('## Versets & hadiths cités\n');
    for (const c of s.citations) l.push(`> ${c.texte_arabe}\n>\n> ${c.traduction}\n> — *${c.reference}*\n`);
  }
  if (lg(s.conseils)) l.push(`## Conseils pratiques\n\n${s.conseils.map(c => `- ${c}`).join('\n')}\n`);
  if (lg(s.douas)) l.push(`## Douas\n\n${s.douas.map(d => `- ${d}`).join('\n')}\n`);
  if (rec.traduction) l.push(`## Traduction complète\n\n${rec.traduction}\n`);
  if (rec.transcript) l.push(`## النص العربي\n\n${rec.transcript}\n`);
  return l.join('\n');
}

function exporterMarkdown(rec) {
  const blob = new Blob([markdownDe(rec)], { type: 'text/markdown;charset=utf-8' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = `khoutba-${(rec.createdAt || '').slice(0, 10)}.md`;
  document.body.appendChild(a);
  a.click();
  setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1000);
}

async function partager(rec) {
  const s = rec.synthese;
  const texte = s
    ? `${rec.titre}\n\n${s.theme}\n\n${s.resume}\n\nPoints clés :\n${(s.points_cles || []).map(p => `• ${p}`).join('\n')}`
    : (rec.traduction || '').slice(0, 4000);
  if (navigator.share) {
    try { await navigator.share({ title: rec.titre, text: texte }); return; } catch { /* annulé */ }
  } else {
    try { await navigator.clipboard.writeText(texte); toast('Résumé copié ✓'); }
    catch { toast('Impossible de copier.'); }
  }
}

// ------------------------------------------------------------------- réglages

async function rendreReglages() {
  const r = reglages;
  const opt = (val, courant, libelle) => `<option value="${val}" ${val === courant ? 'selected' : ''}>${libelle}</option>`;

  let stockage = '';
  try {
    const est = await navigator.storage?.estimate?.();
    if (est?.usage != null) stockage = `${(est.usage / 1048576).toFixed(1)} Mo utilisés`;
  } catch { }

  $('#app').innerHTML = `
    <header class="entete">
      <a class="bouton-icone" href="#" aria-label="Retour">←</a>
      <h1 class="titre-page">Réglages</h1>
      <span class="bouton-icone" aria-hidden="true"></span>
    </header>

    <section class="bloc-reglage">
      <h2>Fournisseurs IA</h2>
      <p class="explication">L'audio est envoyé au fournisseur choisi uniquement quand tu lances le traitement. Une seule clé Gemini suffit pour tout (offre gratuite). Voir le guide dans le README du projet.</p>

      <label class="ligne-reglage">
        <span>Transcription (audio → arabe)</span>
        <select id="sel-stt">
          ${opt('', r.stt, '— choisir —')}
          ${opt('gemini', r.stt, 'Gemini (clé gratuite)')}
          ${opt('openai', r.stt, 'OpenAI Whisper')}
        </select>
      </label>

      <label class="ligne-reglage">
        <span>Traduction & résumé</span>
        <select id="sel-llm">
          ${opt('', r.llm, '— choisir —')}
          ${opt('gemini', r.llm, 'Gemini (clé gratuite)')}
          ${opt('anthropic', r.llm, 'Claude (Anthropic)')}
          ${opt('openai', r.llm, 'OpenAI (GPT)')}
        </select>
      </label>

      <label class="ligne-reglage ${r.llm === 'anthropic' ? '' : 'cache'}" id="ligne-modele-claude">
        <span>Modèle Claude</span>
        <select id="sel-claude">
          ${CHOIX_MODELES_CLAUDE.map(m => opt(m.id, r.modeleClaude, m.label)).join('')}
        </select>
      </label>

      <label class="ligne-reglage ${r.stt === 'gemini' || r.llm === 'gemini' ? '' : 'cache'}" id="ligne-modele-gemini">
        <span>Modèle Gemini</span>
        <select id="sel-gemini">
          <option value="">${echap(modeleGeminiRetenu() ? `Automatique (${modeleGeminiRetenu()})` : 'Automatique (recommandé)')}</option>
          ${r.modeleGemini ? `<option value="${echap(r.modeleGemini)}" selected>${echap(r.modeleGemini)}</option>` : ''}
        </select>
      </label>

      <label class="ligne-reglage">
        <span>Langue des résultats</span>
        <select id="sel-langue">
          ${opt('fr', r.langue, 'Français')}
          ${opt('en', r.langue, 'English')}
        </select>
      </label>
    </section>

    <section class="bloc-reglage">
      <h2>Clés API</h2>
      <p class="explication">Stockées uniquement sur cet appareil.</p>
      ${champCle('gemini', 'Clé Gemini', r.cles.gemini, 'aistudio.google.com/apikey')}
      ${champCle('openai', 'Clé OpenAI', r.cles.openai, 'platform.openai.com/api-keys')}
      ${champCle('anthropic', 'Clé Anthropic', r.cles.anthropic, 'console.anthropic.com')}
    </section>

    <section class="bloc-reglage">
      <h2>Divers</h2>
      <label class="ligne-reglage">
        <span>Mode démo (sans clé, textes fictifs)</span>
        <input type="checkbox" id="chk-demo" ${r.demo ? 'checked' : ''} />
      </label>
      <div class="ligne-reglage"><span>Stockage local</span><span class="valeur-douce">${echap(stockage || '—')}</span></div>
      <button id="btn-tout-effacer" class="btn-danger">Supprimer tous les enregistrements</button>
    </section>

    <footer class="pied">Khoutba v${VERSION_APP} — app locale, aucun serveur. Qu'Allah agrée vos vendredis 🤲</footer>
  `;

  const sauver = () => { ecrireReglages(reglages); toast('Réglages enregistrés ✓', 1400); };

  const majLigneGemini = () =>
    $('#ligne-modele-gemini').classList.toggle('cache', reglages.stt !== 'gemini' && reglages.llm !== 'gemini');

  $('#sel-stt').addEventListener('change', e => { reglages.stt = e.target.value; sauver(); majLigneGemini(); });
  $('#sel-llm').addEventListener('change', e => {
    reglages.llm = e.target.value; sauver();
    $('#ligne-modele-claude').classList.toggle('cache', reglages.llm !== 'anthropic');
    majLigneGemini();
  });
  $('#sel-claude').addEventListener('change', e => { reglages.modeleClaude = e.target.value; sauver(); });
  $('#sel-gemini').addEventListener('change', e => { reglages.modeleGemini = e.target.value; sauver(); });
  $('#sel-langue').addEventListener('change', e => { reglages.langue = e.target.value; sauver(); });
  $('#chk-demo').addEventListener('change', e => { reglages.demo = e.target.checked; sauver(); });

  // Liste des modèles Gemini réellement disponibles avec la clé saisie
  chargerModelesGemini();

  for (const nom of ['gemini', 'openai', 'anthropic']) {
    $(`#cle-${nom}`).addEventListener('change', e => {
      reglages.cles[nom] = e.target.value.trim();
      sauver();
      if (nom === 'gemini') { reinitialiserModelesGemini(); chargerModelesGemini(); }
    });
    $(`#voir-${nom}`).addEventListener('click', () => {
      const champ = $(`#cle-${nom}`);
      champ.type = champ.type === 'password' ? 'text' : 'password';
    });
  }

  $('#btn-tout-effacer').addEventListener('click', async () => {
    if (!confirm('Supprimer TOUS les enregistrements et textes ? Cette action est définitive.')) return;
    const recs = await listerEnregistrements();
    for (const rec of recs) await supprimerEnregistrement(rec.id);
    toast('Tout a été supprimé.');
  });
}

// Remplit le menu « Modèle Gemini » avec ce que la clé permet réellement.
async function chargerModelesGemini() {
  const select = $('#sel-gemini');
  const cle = reglages.cles.gemini;
  if (!select || !cle) return;
  let modeles;
  try { modeles = await geminiListerModeles(cle); }
  catch { return; } // silencieux : le mode automatique fonctionne quand même
  if (!$('#sel-gemini') || !modeles.length) return;
  const choisi = reglages.modeleGemini;
  $('#sel-gemini').innerHTML =
    `<option value="">Automatique — ${echap(modeles[0].id)}</option>` +
    modeles.map(m => `<option value="${echap(m.id)}" ${m.id === choisi ? 'selected' : ''}>${echap(m.id)}</option>`).join('');
}

function champCle(nom, libelle, valeur, aide) {
  return `
    <div class="ligne-cle">
      <label for="cle-${nom}">${libelle} <span class="aide-cle">${echap(aide)}</span></label>
      <div class="groupe-cle">
        <input id="cle-${nom}" type="password" value="${echap(valeur)}" autocomplete="off" spellcheck="false" placeholder="—" />
        <button id="voir-${nom}" class="bouton-icone" type="button" aria-label="Afficher la clé">👁</button>
      </div>
    </div>`;
}

// ----------------------------------------------------------------- démarrage

async function init() {
  // Statuts « en cours » orphelins après une fermeture pendant traitement
  try {
    for (const rec of await listerEnregistrements()) {
      const stable = statutStable(rec);
      if (stable !== rec.statut) { rec.statut = stable; await sauverEnregistrement(rec); }
    }
  } catch { }

  await recupererOrphelins().catch(() => {});
  await rendre();

  $('#btn-stop').addEventListener('click', terminerEnregistrement);
  $('#btn-pause').addEventListener('click', basculerPause);
  $('#btn-annuler').addEventListener('click', annulerEnregistrement);

  // Quitter la page pendant un enregistrement = risque de perte
  window.addEventListener('beforeunload', (e) => {
    if (enregistreur?.actif) { e.preventDefault(); e.returnValue = ''; }
  });

  if ('serviceWorker' in navigator) {
    // Une nouvelle version prend la main : on recharge pour l'appliquer tout de
    // suite (sinon l'app installée resterait sur les fichiers en cache).
    // Jamais pendant un enregistrement.
    const avaitControleur = !!navigator.serviceWorker.controller;
    navigator.serviceWorker.addEventListener('controllerchange', () => {
      if (!avaitControleur || enregistreur?.actif || rechargementFait) return;
      rechargementFait = true;
      location.reload();
    });
    navigator.serviceWorker.register('sw.js').catch(() => {});
  }
}

let rechargementFait = false;

init();
