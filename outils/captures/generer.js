// Habille les captures d'écran brutes pour l'App Store et Google Play.
//
// Les captures viennent du téléphone — ce sont les seules authentiques, et
// Apple demande l'app « en cours d'utilisation ». Ce script ne fabrique donc
// aucun écran : il pose chaque capture sur un fond prune, ajoute l'accroche,
// et sort les dimensions exactes exigées par les stores.
//
//   node generer.js            # habille outils/captures/brutes/*.png
//   node generer.js --exemple  # remplit brutes/ de repères, pour essayer
//
// Les captures brutes se prennent en mode démo (⚙️ Réglages → Mode démo) :
// le contenu affiché est fictif, donc aucune vraie khoutba ni aucune clé ne
// se retrouve sur une image publique.
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const ICI = __dirname;
const BRUTES = path.join(ICI, 'brutes');
const SORTIE = path.resolve(ICI, '../../store/captures');
const POLICE = path.resolve(ICI, '../logo/polices/cairo_3.woff2');

// Ordre imposé : les deux premières sont les seules que la plupart des gens
// verront dans la liste des résultats.
const CAPTURES = [
  { fichier: '1', accroche: 'Enregistre le prêche,\nrange ton téléphone' },
  { fichier: '2', accroche: 'Retrouve-le en français,\nchez toi' },
  { fichier: '3', accroche: 'Les versets cités,\navec leur référence' },
  { fichier: '4', accroche: 'La traduction intégrale,\nà ton rythme' },
  { fichier: '5', accroche: 'Et le texte arabe\ncomplet' },
  { fichier: '6', accroche: 'Tout reste\nsur ton téléphone' },
];

// Tailles réclamées par les stores. La 6,9" est obligatoire chez Apple ;
// la 6,5" reste demandée pour les anciens modèles.
const FORMATS = {
  '6.9': { largeur: 1320, hauteur: 2868 },
  '6.5': { largeur: 1242, hauteur: 2688 },
  play: { largeur: 1080, hauteur: 1920 },
};

const FOND = ['#4A2545', '#3A1B39', '#1F0E22']; // même dégradé que l'icône
const CREME = '#F9F9F7';
const OR = '#F3D889';

const enBase64 = (f) => fs.readFileSync(f).toString('base64');

/**
 * Une image de store : accroche en haut, capture dessous, débordant du bas.
 * Tout est exprimé en fraction de la hauteur pour que les trois formats
 * rendent la même composition.
 */
function page({ accroche, captureBase64, largeur, hauteur, police }) {
  const u = hauteur / 100; // 1 % de hauteur, unité de travail
  return `<!DOCTYPE html><html><head><meta charset="utf-8"><style>
    *{margin:0;padding:0;box-sizing:border-box}
    ${police ? `@font-face{font-family:'Cairo';font-weight:700;font-display:block;
       src:url(data:font/woff2;base64,${police}) format('woff2')}` : ''}
    body{width:${largeur}px;height:${hauteur}px;overflow:hidden}
    .cadre{width:${largeur}px;height:${hauteur}px;position:relative;overflow:hidden;
      background:linear-gradient(160deg,${FOND[0]} 0%,${FOND[1]} 45%,${FOND[2]} 100%);
      display:flex;flex-direction:column;align-items:center}
    .accroche{margin-top:${u * 7}px;padding:0 ${largeur * 0.08}px;text-align:center;
      font-family:Cairo,-apple-system,'Segoe UI',sans-serif;font-weight:700;
      color:${CREME};font-size:${u * 3.6}px;line-height:1.32;white-space:pre-line;
      letter-spacing:-0.01em}
    .filet{width:${largeur * 0.14}px;height:${u * 0.42}px;background:${OR};
      border-radius:${u}px;margin-top:${u * 2.4}px}
    .telephone{margin-top:${u * 4}px;width:${largeur * 0.76}px;height:${u * 82}px;
      border-radius:${largeur * 0.055}px;overflow:hidden;
      border:${Math.max(2, largeur * 0.0035)}px solid rgba(249,249,247,0.22);
      box-shadow:0 ${u * 1.6}px ${u * 4}px rgba(0,0,0,0.45);
      background:url(data:image/png;base64,${captureBase64}) top center/100% auto no-repeat;
      background-color:#FAF7F5}
  </style></head><body>
    <div class="cadre">
      <div class="accroche">${accroche}</div>
      <div class="filet"></div>
      <div class="telephone"></div>
    </div>
  </body></html>`;
}

/** Repères colorés, pour vérifier la mise en page sans capture réelle. */
function fabriquerExemples() {
  fs.mkdirSync(BRUTES, { recursive: true });
  const svg = (n) => `<svg xmlns="http://www.w3.org/2000/svg" width="1206" height="2622">
    <rect width="100%" height="100%" fill="#FAF7F5"/>
    <rect y="0" width="100%" height="240" fill="#5E2751"/>
    <text x="603" y="1300" text-anchor="middle" font-family="sans-serif"
          font-size="220" fill="#5E2751">${n}</text>
    <text x="603" y="1480" text-anchor="middle" font-family="sans-serif"
          font-size="72" fill="#6B5A66">capture à remplacer</text>
  </svg>`;
  return CAPTURES.map((c, i) => ({ ...c, svg: svg(i + 1) }));
}

(async () => {
  const exemple = process.argv.includes('--exemple');
  const police = fs.existsSync(POLICE) ? enBase64(POLICE) : null;
  if (!police) {
    console.log('→ police Cairo absente, repli sur la police système');
    console.log('  Pour l’accroche dans la police du logo : bash ../logo/polices.sh');
  }

  let nav;
  try {
    nav = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined });
  } catch (e) {
    // « npm install playwright » pose la bibliothèque, pas le navigateur :
    // le message brut de Playwright noie cette nuance dans une pile d'appels.
    console.error('✗ Le navigateur de Playwright n’est pas installé.');
    console.error('  Lance : npx playwright install chromium');
    process.exitCode = 1;
    return;
  }
  const p = await nav.newPage({ deviceScaleFactor: 1 });

  // Les repères sont rendus une fois en PNG, puis traités comme des captures.
  let sources = [];
  if (exemple) {
    for (const c of fabriquerExemples()) {
      await p.setViewportSize({ width: 1206, height: 2622 });
      await p.setContent(c.svg);
      const png = await p.screenshot({ clip: { x: 0, y: 0, width: 1206, height: 2622 } });
      fs.writeFileSync(path.join(BRUTES, `${c.fichier}.png`), png);
    }
    console.log(`repères écrits dans ${path.relative(process.cwd(), BRUTES)}/`);
  }

  sources = CAPTURES.map((c) => {
    const trouve = ['png', 'PNG', 'jpg', 'jpeg']
      .map((e) => path.join(BRUTES, `${c.fichier}.${e}`))
      .find(fs.existsSync);
    return { ...c, chemin: trouve };
  });

  const manquantes = sources.filter((s) => !s.chemin);
  if (manquantes.length === CAPTURES.length) {
    console.error(`✗ Aucune capture dans ${BRUTES}/`);
    console.error('  Prends-les sur le téléphone (mode démo), nomme-les 1.png à 6.png,');
    console.error('  ou lance « node generer.js --exemple » pour voir le rendu.');
    await nav.close();
    process.exitCode = 1;
    return;
  }
  for (const m of manquantes) console.log(`→ ${m.fichier}.png absente, ignorée`);

  for (const [nomFormat, dim] of Object.entries(FORMATS)) {
    const dossier = path.join(SORTIE, nomFormat);
    fs.mkdirSync(dossier, { recursive: true });
    await p.setViewportSize({ width: dim.largeur, height: dim.hauteur });
    for (const s of sources.filter((s) => s.chemin)) {
      await p.setContent(page({
        accroche: s.accroche,
        captureBase64: enBase64(s.chemin),
        largeur: dim.largeur,
        hauteur: dim.hauteur,
        police,
      }));
      await p.evaluate(() => document.fonts.ready);
      const png = await p.screenshot({
        clip: { x: 0, y: 0, width: dim.largeur, height: dim.hauteur },
      });
      fs.writeFileSync(path.join(dossier, `${s.fichier.padStart(2, '0')}.png`), png);
    }
    console.log(`${nomFormat} : ${sources.filter((s) => s.chemin).length} images `
      + `(${dim.largeur}×${dim.hauteur}) → ${path.relative(process.cwd(), dossier)}/`);
  }

  await nav.close();
})();
