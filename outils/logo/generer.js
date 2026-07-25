// Décline le logo Khoutba sur tous les supports : iOS, Android, web.
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const { logo, page, mesurerLargeurs, FONDS } = require('./logo');

const RACINE = path.resolve(__dirname, '../..');
const NATIF = path.join(RACINE, 'native');

// ————— à modifier pour changer le logo —————
const FOND = 'prune';        // bleu nuit | prune | ardoise | brun cuir | vert (AdhanBox)
const ARABE = 'أذان';        // le mot arabe affiché au-dessus du filet doré
const LATIN = 'KHOUTBA';
// ———————————————————————————————————————————

const FOND_UNI = FONDS[FOND][1]; // teinte sombre, pour l'icône adaptative Android

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

  // On mesure les mots réellement utilisés : les tailles de police en
  // découlent, donc changer de texte ne fait jamais déborder le dessin.
  const largeurs = await mesurerLargeurs(p, { arabe: ARABE, latin: LATIN });
  console.log(`largeurs mesurées — ${ARABE} : ${largeurs.arabe.toFixed(2)}×,`
    + ` ${LATIN} : ${largeurs.latin.toFixed(2)}× la taille de police`);

  const base = { fond: FOND, arabe: ARABE, latin: LATIN, largeurs };
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

  await nav.close();
})();
