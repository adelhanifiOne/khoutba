// Extrait le motif « أذان + filet doré » de l'icône AdhanBox, en transparence.
//
// Pourquoi : le أذان d'AdhanBox n'est pas du texte, c'est un dessin. Aucune
// police ne le reproduit — le rendre en Cairo donnait un ن plus étroit et plus
// profond, et un filet parfaitement droit là où l'original ondule. Les trois
// icônes de la famille ne se ressemblaient donc pas vraiment.
//
// Le motif produit (`motif-adhan.png` + `motif-adhan.json`) est versionné :
// personne n'a besoin de relancer ce script, sauf si le logo d'AdhanBox change.
//
//   node extraire-motif.js /chemin/vers/adhanbox/.../app_logo.png
//
// Méthode : le fond est vert très sombre (rouge ≈ 12), le motif est crème
// (rouge ≈ 249) ou doré (rouge ≈ 243). Le canal rouge donne donc directement
// l'opacité de chaque pixel, bords antialiasés compris.
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const CREME = [249, 249, 247];
const OR = [243, 216, 137];
// Bornes verticales relevées sur l'icône : au-dessus, le mot arabe ; au
// milieu, le filet ; en dessous, « BOX » — que l'on ne reprend pas.
const BAS_ARABE = 590;
const BAS_FILET = 665;
const SEUIL_ALPHA = 0.08; // en dessous : halo flou de l'arrière-plan

(async () => {
  const source = process.argv[2];
  if (!source || !fs.existsSync(source)) {
    console.error('usage : node extraire-motif.js <icône AdhanBox 1024×1024 .png>');
    process.exit(1);
  }

  const nav = await chromium.launch({ executablePath: process.env.CHROMIUM_PATH || undefined });
  const p = await nav.newPage({ deviceScaleFactor: 1 });
  await p.setContent('<canvas id="c"></canvas>');

  const resultat = await p.evaluate(
    async ({ png, creme, or, basArabe, basFilet, seuil }) => {
      const img = new Image();
      img.src = `data:image/png;base64,${png}`;
      await img.decode();
      const T = img.width;
      const c = document.getElementById('c');
      c.width = c.height = T;
      const ctx = c.getContext('2d');
      ctx.drawImage(img, 0, 0);
      const src = ctx.getImageData(0, 0, T, T);
      const sortie = ctx.createImageData(T, T);

      const mediane = (v) => v.sort((a, b) => a - b)[v.length >> 1];
      for (let y = 0; y < Math.round((basFilet * T) / 1024); y++) {
        // Rouge du fond sur cette ligne : le dégradé varie, la médiane suit.
        const fond = [];
        for (let x = 0; x < T; x++) {
          const r = src.data[(y * T + x) * 4];
          if (r < 60) fond.push(r);
        }
        if (!fond.length) continue;
        const rFond = mediane(fond);
        const couleur = y < Math.round((basArabe * T) / 1024) ? creme : or;
        for (let x = 0; x < T; x++) {
          const i = (y * T + x) * 4;
          const a = (src.data[i] - rFond) / (couleur[0] - rFond);
          if (a < seuil) continue;
          sortie.data[i] = couleur[0];
          sortie.data[i + 1] = couleur[1];
          sortie.data[i + 2] = couleur[2];
          sortie.data[i + 3] = Math.round(Math.min(1, a) * 255);
        }
      }
      ctx.putImageData(sortie, 0, 0);

      // Boîtes utiles, en fraction du cadre : elles servent à recadrer le mot
      // arabe seul pour les très petites icônes.
      const boite = (y0, y1) => {
        let xmin = T, xmax = -1, ymin = T, ymax = -1;
        for (let y = y0; y < y1; y++) {
          for (let x = 0; x < T; x++) {
            if (sortie.data[(y * T + x) * 4 + 3] < 16) continue;
            if (x < xmin) xmin = x;
            if (x > xmax) xmax = x;
            if (y < ymin) ymin = y;
            if (y > ymax) ymax = y;
          }
        }
        return { gauche: xmin / T, haut: ymin / T, largeur: (xmax - xmin + 1) / T, hauteur: (ymax - ymin + 1) / T };
      };
      const coupe = Math.round((basArabe * T) / 1024);
      return {
        png: c.toDataURL('image/png').split(',')[1],
        taille: T,
        arabe: boite(0, coupe),
        filet: boite(coupe, T),
      };
    },
    {
      png: fs.readFileSync(source).toString('base64'),
      creme: CREME, or: OR,
      basArabe: BAS_ARABE, basFilet: BAS_FILET, seuil: SEUIL_ALPHA,
    },
  );

  const { png, ...boites } = resultat;
  fs.writeFileSync(path.join(__dirname, 'motif-adhan.png'), Buffer.from(png, 'base64'));
  fs.writeFileSync(path.join(__dirname, 'motif-adhan.json'), `${JSON.stringify(boites, null, 2)}\n`);
  console.log('motif-adhan.png écrit —', JSON.stringify(boites));
  await nav.close();
})();
