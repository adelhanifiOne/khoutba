// Décline le logo Khoutba sur tous les supports : iOS, Android, web.
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const { logo, page, geometrie, mesurerMetriques, mesurerRendu, FONDS, REPERE, BOITES } = require('./logo');

const RACINE = path.resolve(__dirname, '../..');
const NATIF = path.join(RACINE, 'native');

// ————— à modifier pour changer le logo —————
const FOND = 'prune';        // bleu nuit | prune | ardoise | brun cuir | vert (AdhanBox)
const LATIN = 'KHOUTBA';     // le mot arabe, lui, vient du motif d'AdhanBox
// ———————————————————————————————————————————

// Fond uni de l'icône adaptative Android : la teinte médiane du dégradé, la
// plus proche de l'impression d'ensemble une fois l'avant-plan posé dessus.
const FOND_UNI = FONDS[FOND][1];

async function rendre(p, options, taille, transparent = false) {
  await p.setViewportSize({ width: taille, height: taille });
  await p.setContent(page(logo({ ...options, taille }), taille, taille,
    'body{width:100%;height:100%;overflow:hidden}'));
  await p.evaluate(() => document.fonts.ready); // sans ça, le texte peut manquer
  return p.screenshot({
    clip: { x: 0, y: 0, width: taille, height: taille },
    omitBackground: transparent,
  });
}

const ecrire = (chemin, donnees) => {
  fs.mkdirSync(path.dirname(chemin), { recursive: true });
  fs.writeFileSync(chemin, donnees);
};

(async () => {
  // CHROMIUM_PATH permet d'utiliser un navigateur déjà installé ;
  // sinon Playwright prend le sien.
  const nav = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined });
  const p = await nav.newPage({ deviceScaleFactor: 1 });

  // Le mot latin est mesuré dans la police : taille et position en découlent,
  // donc le changer ne déplace ni ne fait déborder rien.
  const metriques = await mesurerMetriques(p, { latin: LATIN });
  console.log(`métriques — ${LATIN} : ${metriques.latin.largeurNue.toFixed(3)}× de large`
    + ` (hors interlettre), capitale ${metriques.latin.hauteur.toFixed(3)}×`);

  // Le canvas et le moteur de rendu ne s'accordent pas toujours au pixel près
  // sur la hauteur de l'encre. Plutôt que de corriger « à l'œil », on rend une
  // fois, on mesure l'écart et on le reporte : le calcul est linéaire, une
  // passe suffit.
  const base = { fond: FOND, latin: LATIN, metriques };
  {
    const T = 1024;
    const g = geometrie({ taille: T, metriques });
    const vu = await mesurerRendu(p, (await rendre(p, base, T)).toString('base64'), T);
    metriques.latin.hautInk += ((vu.latin.haut - REPERE.latin.haut) * T) / g.tailleLatin;
  }
  // Sous 64 px, « KHOUTBA » n'est plus lisible : on ne garde que le mot arabe.
  const pourTaille = (px) => ({ ...base, sansTexteLatin: px < 64 });

  // ---------------------------------------------------------------- iOS
  const iOS = {
    'Icon-App-20x20@1x.png': 20, 'Icon-App-20x20@2x.png': 40, 'Icon-App-20x20@3x.png': 60,
    'Icon-App-29x29@1x.png': 29, 'Icon-App-29x29@2x.png': 58, 'Icon-App-29x29@3x.png': 87,
    'Icon-App-40x40@1x.png': 40, 'Icon-App-40x40@2x.png': 80, 'Icon-App-40x40@3x.png': 120,
    'Icon-App-60x60@2x.png': 120, 'Icon-App-60x60@3x.png': 180,
    'Icon-App-76x76@1x.png': 76, 'Icon-App-76x76@2x.png': 152,
    'Icon-App-83.5x83.5@2x.png': 167,
    'Icon-App-1024x1024@1x.png': 1024,
  };
  for (const [nom, px] of Object.entries(iOS)) {
    ecrire(`${NATIF}/ios/Runner/Assets.xcassets/AppIcon.appiconset/${nom}`,
           await rendre(p, pourTaille(px), px));
  }
  console.log(`iOS : ${Object.keys(iOS).length} icônes`);

  // ------------------------------------------------------------ Android
  const densites = { mdpi: 48, hdpi: 72, xhdpi: 96, xxhdpi: 144, xxxhdpi: 192 };
  for (const [densite, px] of Object.entries(densites)) {
    const dossier = `${NATIF}/android/app/src/main/res/mipmap-${densite}`;
    ecrire(`${dossier}/ic_launcher.png`, await rendre(p, pourTaille(px), px));
    // Avant-plan adaptatif : cadre 108dp, contenu réduit pour survivre au
    // rognage rond des lanceurs récents.
    ecrire(`${dossier}/ic_launcher_foreground.png`,
           await rendre(p, { ...base, fond: null, echelle: 0.6 }, Math.round(px * 2.25), true));
  }
  ecrire(
    `${NATIF}/android/app/src/main/res/values/ic_launcher_background.xml`,
    `<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">${FOND_UNI}</color>
</resources>
`
  );
  console.log('Android : 5 densités + icône adaptative');

  // ---------------------------------------------------------------- web
  ecrire(`${RACINE}/icons/icon-512.png`, await rendre(p, base, 512));
  ecrire(`${RACINE}/icons/icon-192.png`, await rendre(p, base, 192));
  ecrire(`${RACINE}/icons/icon-maskable-512.png`,
         await rendre(p, { ...base, echelle: 0.72 }, 512));
  ecrire(`${RACINE}/icons/apple-touch-icon.png`, await rendre(p, base, 180));
  // Logo affiché dans l'en-tête de l'app native
  ecrire(`${NATIF}/assets/logo.png`, await rendre(p, base, 192));
  console.log('web + en-tête : 5 fichiers');

  // ------------------------------------------------- contrôle de conformité
  // Le logo est censé reprendre la géométrie d'AdhanBox : on relit l'image
  // produite et on compare, plutôt que de juger à l'œil.
  const rendu = await mesurerRendu(p, (await rendre(p, base, 1024)).toString('base64'), 1024);
  const ecarts = [
    ['largeur du mot arabe', rendu.arabe.largeur, BOITES.arabe.largeur],
    ['haut du mot arabe', rendu.arabe.haut, BOITES.arabe.haut],
    ['gauche du mot arabe', rendu.arabe.gauche, BOITES.arabe.gauche],
    ['largeur du filet', rendu.filet.largeur, BOITES.filet.largeur],
    ['haut du filet', rendu.filet.haut, BOITES.filet.haut],
    ['haut du mot latin', rendu.latin.haut, REPERE.latin.haut],
  ];
  console.log('\nconformité à la famille AdhanBox (fractions du cadre) :');
  let pire = 0;
  for (const [quoi, obtenu, vise] of ecarts) {
    const ecart = Math.abs(obtenu - vise);
    pire = Math.max(pire, ecart);
    console.log(`  ${ecart < 0.004 ? '✓' : '⚠'} ${quoi.padEnd(22)} ${obtenu.toFixed(4)}`
      + ` (visé ${vise.toFixed(4)}, écart ${(ecart * 1024).toFixed(1)} px sur 1024)`);
  }
  console.log(`  hauteur du mot latin : ${rendu.latin.hauteur.toFixed(4)}`
    + ` (« BOX » : ${REPERE.latin.hauteur.toFixed(4)} — plus petit car le mot est plus long)`);
  if (pire >= 0.004) process.exitCode = 1;

  await nav.close();
})();
