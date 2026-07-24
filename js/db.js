// Stockage local (IndexedDB) — tout reste sur le téléphone.
//
// Deux magasins :
//  - recordings : l'enregistrement final + textes (transcription, traduction, synthèse)
//  - chunks     : morceaux audio écrits toutes les 5 s PENDANT l'enregistrement,
//                 pour ne rien perdre si l'app est fermée en pleine khoutba.

const DB_NAME = 'khoutba';
const DB_VERSION = 1;

let _db = null;

function ouvrirDB() {
  if (_db) return Promise.resolve(_db);
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION);
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains('recordings')) {
        const store = db.createObjectStore('recordings', { keyPath: 'id' });
        store.createIndex('createdAt', 'createdAt');
      }
      if (!db.objectStoreNames.contains('chunks')) {
        const store = db.createObjectStore('chunks', { keyPath: ['recId', 'idx'] });
        store.createIndex('recId', 'recId');
      }
    };
    req.onsuccess = () => { _db = req.result; resolve(_db); };
    req.onerror = () => reject(req.error);
  });
}

function transaction(nom, mode, fn) {
  return ouvrirDB().then(db => new Promise((resolve, reject) => {
    const tx = db.transaction(nom, mode);
    const store = tx.objectStore(nom);
    let resultat;
    try { resultat = fn(store); } catch (e) { reject(e); return; }
    tx.oncomplete = () => resolve(resultat && 'result' in resultat ? resultat.result : undefined);
    tx.onerror = () => reject(tx.error);
    tx.onabort = () => reject(tx.error || new Error('Transaction annulée'));
  }));
}

// --- Enregistrements ---

export function sauverEnregistrement(rec) {
  rec.updatedAt = new Date().toISOString();
  return transaction('recordings', 'readwrite', s => s.put(rec)).then(() => rec);
}

export function lireEnregistrement(id) {
  return transaction('recordings', 'readonly', s => s.get(id));
}

export async function supprimerEnregistrement(id) {
  await viderChunks(id);
  return transaction('recordings', 'readwrite', s => s.delete(id));
}

export async function listerEnregistrements() {
  const tous = await transaction('recordings', 'readonly', s => s.getAll());
  return (tous || []).sort((a, b) => (b.createdAt || '').localeCompare(a.createdAt || ''));
}

// --- Chunks (filet de sécurité pendant l'enregistrement) ---

export function ajouterChunk(recId, idx, blob, mimeType) {
  return transaction('chunks', 'readwrite', s => s.put({ recId, idx, blob, mimeType }));
}

export async function lireChunks(recId) {
  const db = await ouvrirDB();
  return new Promise((resolve, reject) => {
    const tx = db.transaction('chunks', 'readonly');
    const req = tx.objectStore('chunks').index('recId').getAll(IDBKeyRange.only(recId));
    req.onsuccess = () => resolve((req.result || []).sort((a, b) => a.idx - b.idx));
    req.onerror = () => reject(req.error);
  });
}

export async function viderChunks(recId) {
  const morceaux = await lireChunks(recId);
  if (!morceaux.length) return;
  return transaction('chunks', 'readwrite', s => {
    for (const m of morceaux) s.delete([m.recId, m.idx]);
  });
}

// IDs d'enregistrements ayant encore des chunks (app fermée en cours de route)
export async function idsChunksOrphelins() {
  const db = await ouvrirDB();
  return new Promise((resolve, reject) => {
    const ids = new Set();
    const tx = db.transaction('chunks', 'readonly');
    const req = tx.objectStore('chunks').openCursor();
    req.onsuccess = () => {
      const cur = req.result;
      if (cur) { ids.add(cur.value.recId); cur.continue(); }
      else resolve([...ids]);
    };
    req.onerror = () => reject(req.error);
  });
}
