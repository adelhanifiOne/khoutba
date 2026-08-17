// Logo Khoutba, membre de la famille AdhanBox / Adhan Hub : le mot arabe
// **أذان** et son filet doré, puis **KHOUTBA** — sur un fond prune.
//
// Le أذان n'est pas du texte : c'est un dessin, celui d'AdhanBox. Le rendre en
// Cairo donnait un ن plus étroit et plus profond, et un filet parfaitement
// droit là où l'original ondule — les trois icônes ne se ressemblaient donc
// pas vraiment côte à côte. Le motif est maintenant repris tel quel, extrait
// en transparence par `extraire-motif.js`.
//
// Seul le mot latin est composé : « BOX » est bien du Cairo Bold, vérifié en
// superposant les lettres.
const fs = require('fs');
const path = require('path');
const b64 = (f) => fs.readFileSync(path.join(__dirname, f)).toString('base64');
const POLICES = `
  @font-face { font-family:'Cairo'; font-weight:700; font-display:block;
    src:url(data:font/woff2;base64,${b64('polices/cairo_3.woff2')}) format('woff2'); }`;

const MOTIF = `data:image/png;base64,${b64('motif-adhan.png')}`;
const BOITES = JSON.parse(fs.readFileSync(path.join(__dirname, 'motif-adhan.json'), 'utf8'));

// Dégradé en trois arrêts comme AdhanBox : la teinte médiane à 45 % garde la
// moitié haute lumineuse. À deux arrêts, l'icône s'assombrit trop tôt et
// paraît terne à côté des deux autres.
const FONDS = {
  'bleu nuit': ['#1E3A5F', '#16304F', '#0A1A2F'],
  prune: ['#4A2545', '#3A1B39', '#1F0E22'],
  ardoise: ['#33403F', '#25302E', '#111917'],
  'brun cuir': ['#5B3B22', '#452A16', '#26150A'],
  'vert (AdhanBox)': ['#1F7A5A', '#125C41', '#08381F'],
};

const CREME = '#F9F9F7'; // relevé sur l'icône AdhanBox

/**
 * Géométrie du mot latin relevée sur « BOX » de l'icône AdhanBox, en fraction
 * du côté du cadre. `haut` désigne le haut de l'encre, pas d'une boîte CSS.
 */
const REPERE = {
  latin: { hauteur: 0.1113, haut: 0.6885 }, // hauteur de capitale de « BOX »
  // Un mot latin plus long que « BOX » ne peut pas tenir à cette taille sans
  // toucher les bords : sa largeur est bornée, sa hauteur suit.
  latinLargeurMax: 0.64,
  // Sans mot latin (petites tailles), le mot arabe seul occupe cette part.
  arabeSeul: 0.78,
};

// Interlettre relevée sur « BOX » : très aérée. Un mot long ne peut pas garder
// à la fois cette respiration et la hauteur de capitale de la famille ; on
// privilégie alors la taille des lettres, plus visible sur l'écran d'accueil.
const INTERLETTRE_FAMILLE = 0.307;
const INTERLETTRE_SERREE = 0.12;

/**
 * Métriques de Cairo Bold pour le mot latin, en multiples de la taille de
 * police, interlettre exclue. `mesurerMetriques()` les recalcule à chaque
 * génération ; ces valeurs ne servent que de repli.
 */
const METRIQUES_DEFAUT = { latin: { largeurNue: 5.12, hauteur: 0.708, hautInk: 0.185, lettres: 7 } };

/**
 * Taille, interlettre et position du mot latin. Isolé pour que la calibration
 * refasse le même calcul sans le dupliquer.
 */
function geometrie({ taille: T, metriques = METRIQUES_DEFAUT }) {
  const m = metriques.latin;
  const largeur = (esp, taille) => (m.largeurNue + (m.lettres - 1) * esp) * taille;

  const tailleFamille = (REPERE.latin.hauteur * T) / m.hauteur;
  let interlettre = INTERLETTRE_FAMILLE;
  let tailleLatin = tailleFamille;
  if (largeur(interlettre, tailleFamille) > REPERE.latinLargeurMax * T) {
    interlettre = INTERLETTRE_SERREE;
    tailleLatin = Math.min(
      tailleFamille,
      (REPERE.latinLargeurMax * T) / (m.largeurNue + (m.lettres - 1) * interlettre),
    );
  }
  return {
    tailleLatin,
    interlettre,
    hautLatin: REPERE.latin.haut * T - m.hautInk * tailleLatin,
  };
}

/**
 * Le logo complet, en HTML (rendu ensuite en PNG par Chromium).
 * - `sansTexteLatin` : sous 64 px le mot latin devient illisible ; on ne garde
 *   alors que le mot arabe, recadré, agrandi et centré.
 * - `echelle` : réduit le contenu sans toucher au cadre (icônes rognées en
 *   cercle sur Android, ou « maskable » du web).
 * - `fond: null` : sans fond, pour l'avant-plan des icônes adaptatives.
 */
function logo({
  fond = 'bleu nuit',
  latin = 'KHOUTBA',
  taille = 512,
  sansTexteLatin = false,
  echelle = 1,
  metriques = METRIQUES_DEFAUT,
} = {}) {
  const T = taille;
  const degrade = fond
    ? `background:linear-gradient(160deg, ${FONDS[fond][0]} 0%, ${FONDS[fond][1]} 45%, ${FONDS[fond][2]} 100%);`
    : '';
  const motif = `background:url(${MOTIF}) 0 0/100% 100% no-repeat;`;

  let corps;
  if (sansTexteLatin) {
    // Recadrage sur le seul mot arabe : le motif est agrandi, puis découpé à
    // sa boîte utile par le conteneur.
    const ar = BOITES.arabe;
    const cadre = (REPERE.arabeSeul * T) / ar.largeur; // taille du motif entier
    corps = `
      <div style="position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);
                  width:${ar.largeur * cadre}px;height:${ar.hauteur * cadre}px;overflow:hidden;">
        <div style="position:absolute;left:${-ar.gauche * cadre}px;top:${-ar.haut * cadre}px;
                    width:${cadre}px;height:${cadre}px;${motif}"></div>
      </div>`;
  } else {
    const g = geometrie({ taille: T, metriques });
    corps = `
      <div style="position:absolute;inset:0;${motif}"></div>
      <div style="position:absolute;left:0;right:0;text-align:center;white-space:nowrap;
                  font-family:Cairo,sans-serif;font-weight:700;color:${CREME};line-height:1;
                  top:${g.hautLatin}px;font-size:${g.tailleLatin}px;
                  letter-spacing:${g.interlettre}em;
                  text-indent:${g.interlettre}em;">${latin}</div>`;
  }

  return `
  <div style="width:${T}px;height:${T}px;position:relative;overflow:hidden;${degrade}">
    <div style="position:absolute;inset:0;transform:scale(${echelle});
                transform-origin:center;">${corps}</div>
  </div>`;
}

const page = (contenu, largeur, hauteur, styleSupp = '') => `<!DOCTYPE html>
<html><head><meta charset="utf-8"><style>
  *{margin:0;padding:0;box-sizing:border-box}
  ${POLICES}
  ${styleSupp}
</style></head><body>${contenu}</body></html>`;

/**
 * Mesure la boîte d'encre du mot latin pour une police de 1 px, interlettre
 * exclue : largeur, hauteur de capitale, et distance entre le haut de la boîte
 * CSS et le haut de l'encre. Sans ces trois nombres, poser le texte à un
 * endroit précis relève du tâtonnement — et le réglage saute au premier
 * changement de mot.
 */
async function mesurerMetriques(p, { latin }) {
  await p.setContent(page('<canvas id="c" width="10" height="10"></canvas>', 100, 100));
  await p.evaluate(() => document.fonts.ready);
  return p.evaluate(({ latin }) => {
    const ctx = document.getElementById('c').getContext('2d');
    const REF = 200; // taille de mesure : assez grande pour rester précise
    ctx.font = `700 ${REF}px Cairo`;
    ctx.textAlign = 'left';
    ctx.textBaseline = 'alphabetic';
    ctx.letterSpacing = '0em';
    const m = ctx.measureText(latin);
    // Ligne de base d'une boîte CSS en line-height:1, depuis son haut.
    const base =
      (REF - (m.fontBoundingBoxAscent + m.fontBoundingBoxDescent)) / 2 + m.fontBoundingBoxAscent;
    return {
      latin: {
        largeurNue: (Math.abs(m.actualBoundingBoxLeft) + m.actualBoundingBoxRight) / REF,
        hauteur: (m.actualBoundingBoxAscent + m.actualBoundingBoxDescent) / REF,
        hautInk: (base - m.actualBoundingBoxAscent) / REF,
        lettres: latin.length,
      },
    };
  }, { latin });
}

/**
 * Relit une image rendue et renvoie les proportions réellement obtenues, pour
 * les comparer aux repères. C'est la seule façon d'affirmer que le logo est
 * conforme à la famille autrement qu'à l'œil.
 */
async function mesurerRendu(p, pngBase64, taille) {
  await p.setContent('<canvas id="c"></canvas>');
  return p.evaluate(
    async ({ png, T }) => {
      const img = new Image();
      img.src = `data:image/png;base64,${png}`;
      await img.decode();
      const c = document.getElementById('c');
      c.width = c.height = T;
      const ctx = c.getContext('2d');
      ctx.drawImage(img, 0, 0);
      const d = ctx.getImageData(0, 0, T, T).data;

      const lire = (x, y) => {
        const i = (y * T + x) * 4;
        return [d[i], d[i + 1], d[i + 2]];
      };
      const creme = ([r, g, b]) => r > 225 && g > 225 && b > 215 && Math.abs(r - b) < 25;
      const dore = ([r, g, b]) => r > 225 && g > 190 && g < 240 && b > 100 && b < 190 && r - b > 60;

      const boite = (test, y0, y1) => {
        let xmin = T, xmax = -1, ymin = T, ymax = -1;
        for (let y = y0; y < y1; y++) {
          for (let x = 0; x < T; x++) {
            if (!test(lire(x, y))) continue;
            if (x < xmin) xmin = x;
            if (x > xmax) xmax = x;
            if (y < ymin) ymin = y;
            if (y > ymax) ymax = y;
          }
        }
        return xmax < 0 ? null : { xmin, xmax, ymin, ymax };
      };

      const f = (v) => v / T;
      const filet = boite(dore, 0, T);
      // Le mot arabe est au-dessus du filet, le mot latin en dessous.
      const ar = boite(creme, 0, filet ? filet.ymin : T);
      const la = filet ? boite(creme, filet.ymax + 1, T) : null;
      return {
        arabe: ar && {
          gauche: f(ar.xmin), haut: f(ar.ymin),
          largeur: f(ar.xmax - ar.xmin + 1), hauteur: f(ar.ymax - ar.ymin + 1),
        },
        filet: filet && {
          gauche: f(filet.xmin), haut: f(filet.ymin),
          largeur: f(filet.xmax - filet.xmin + 1), hauteur: f(filet.ymax - filet.ymin + 1),
        },
        latin: la && {
          largeur: f(la.xmax - la.xmin + 1), hauteur: f(la.ymax - la.ymin + 1), haut: f(la.ymin),
        },
      };
    },
    { png: pngBase64, T: taille },
  );
}

module.exports = {
  logo, page, geometrie, mesurerMetriques, mesurerRendu,
  FONDS, CREME, REPERE, BOITES, METRIQUES_DEFAUT,
};
