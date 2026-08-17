// Logo Khoutba, membre de la famille AdhanBox / Adhan Hub : même mot arabe à
// la même taille, même filet doré, même rythme vertical. Seuls changent la
// couleur de fond et le mot latin.
//
// Les proportions ci-dessous ne sont pas inventées : elles ont été relevées au
// pixel sur l'icône AdhanBox (1024 px), puis ramenées en fraction du cadre.
// C'est ce qui fait que les trois icônes se ressemblent côte à côte sur
// l'écran d'accueil — la première version, ajustée « à l'œil », donnait un
// أذان trop gros, un filet deux fois trop épais et un or trop foncé.
const fs = require('fs');
const path = require('path');
const b64 = (f) => fs.readFileSync(path.join(__dirname, 'polices', f)).toString('base64');
const POLICES = `
  @font-face { font-family:'Cairo'; font-weight:700; font-display:block;
    src:url(data:font/woff2;base64,${b64('cairo_1.woff2')}) format('woff2');
    unicode-range: U+0600-06FF, U+0750-077F, U+FB50-FDFF, U+FE70-FEFF; }
  @font-face { font-family:'Cairo'; font-weight:700; font-display:block;
    src:url(data:font/woff2;base64,${b64('cairo_3.woff2')}) format('woff2'); }`;

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
const OR = '#F3D889';    // idem — nettement plus clair que l'or d'origine

/**
 * Géométrie relevée sur l'icône AdhanBox, en fraction du côté du cadre.
 * `haut` désigne le haut de l'encre, pas celui d'une boîte CSS.
 */
const REPERE = {
  arabe: { largeur: 0.591, haut: 0.171 },
  filet: { largeur: 0.3545, epaisseur: 0.0132, centre: 0.604 },
  latin: { hauteur: 0.1113, haut: 0.6885 }, // « BOX » : hauteur de capitale
  // Un mot latin plus long que « BOX » ne peut pas garder cette taille sans
  // toucher les bords : on borne sa largeur, la hauteur suit.
  latinLargeurMax: 0.64,
  // Sans mot latin (petites tailles), le mot arabe occupe davantage.
  arabeSeul: 0.78,
};

const INTERLETTRE_LATIN = 0.108; // en em

/**
 * Métriques de Cairo Bold pour les mots utilisés, en multiples de la taille de
 * police. `mesurerMetriques()` les recalcule à chaque génération : changer un
 * mot ou la police ne casse donc pas le placement. Ces valeurs ne servent que
 * de repli.
 */
const METRIQUES_DEFAUT = {
  arabe: { largeur: 2.343, hauteur: 0.955, hautInk: 0.024 },
  latin: { largeur: 4.857, hauteur: 0.714, hautInk: 0.185 },
};

/**
 * Tailles de police et positions, déduites des repères AdhanBox et des
 * métriques de la police. Isolé de `logo()` pour que la calibration puisse
 * refaire le même calcul sans le dupliquer.
 */
function geometrie({ taille: T, sansTexteLatin = false, metriques = METRIQUES_DEFAUT }) {
  // ---- mot arabe : même largeur d'encre que sur AdhanBox, donc même taille
  const partArabe = sansTexteLatin ? REPERE.arabeSeul : REPERE.arabe.largeur;
  const tailleArabe = (partArabe * T) / metriques.arabe.largeur;
  // Seul, le mot est centré dans le cadre ; sinon il garde sa place d'origine.
  const hautArabe = sansTexteLatin
    ? (T - metriques.arabe.hauteur * tailleArabe) / 2 - metriques.arabe.hautInk * tailleArabe
    : REPERE.arabe.haut * T - metriques.arabe.hautInk * tailleArabe;

  // ---- mot latin : hauteur de capitale de « BOX », sauf s'il déborde
  const tailleLatin = Math.min(
    (REPERE.latin.hauteur * T) / metriques.latin.hauteur,
    (REPERE.latinLargeurMax * T) / metriques.latin.largeur,
  );
  const epaisseur = REPERE.filet.epaisseur * T;
  return {
    tailleArabe,
    hautArabe,
    tailleLatin,
    hautLatin: REPERE.latin.haut * T - metriques.latin.hautInk * tailleLatin,
    epaisseur,
    largeurFilet: REPERE.filet.largeur * T,
    hautFilet: REPERE.filet.centre * T - epaisseur / 2,
  };
}

/**
 * Le logo complet, en HTML (rendu ensuite en PNG par Chromium).
 * - `sansTexteLatin` : sous 64 px le mot latin devient illisible ; on ne garde
 *   alors que le mot arabe, agrandi et centré.
 * - `echelle` : réduit le contenu sans toucher au cadre (icônes rognées en
 *   cercle sur Android, ou « maskable » du web).
 * - `fond: null` : sans fond, pour l'avant-plan des icônes adaptatives.
 */
function logo({
  fond = 'bleu nuit',
  arabe = 'أذان',
  latin = 'KHOUTBA',
  taille = 512,
  sansTexteLatin = false,
  echelle = 1,
  metriques = METRIQUES_DEFAUT,
} = {}) {
  const T = taille;
  const g = geometrie({ taille: T, sansTexteLatin, metriques });
  const degrade = fond
    ? `background:linear-gradient(160deg, ${FONDS[fond][0]} 0%, ${FONDS[fond][1]} 45%, ${FONDS[fond][2]} 100%);`
    : '';

  const commun = `position:absolute;left:0;right:0;text-align:center;white-space:nowrap;
                  font-family:Cairo,sans-serif;font-weight:700;color:${CREME};line-height:1;`;

  let corps = `<div style="${commun}top:${g.hautArabe}px;font-size:${g.tailleArabe}px;
                           direction:rtl;">${arabe}</div>`;

  if (!sansTexteLatin) {
    corps += `
      <div style="position:absolute;left:50%;transform:translateX(-50%);
                  top:${g.hautFilet}px;width:${g.largeurFilet}px;height:${g.epaisseur}px;
                  border-radius:${g.epaisseur}px;background:${OR};"></div>
      <div style="${commun}top:${g.hautLatin}px;font-size:${g.tailleLatin}px;
                  letter-spacing:${INTERLETTRE_LATIN}em;
                  text-indent:${INTERLETTRE_LATIN}em;">${latin}</div>`;
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
 * Mesure, pour une police de 1 px, la boîte d'encre de chaque mot : largeur,
 * hauteur, et distance entre le haut de la boîte CSS et le haut de l'encre.
 * Sans ces trois nombres, poser le texte à un endroit précis relève du
 * tâtonnement — et le réglage saute au premier changement de mot.
 */
async function mesurerMetriques(p, { arabe, latin }) {
  await p.setContent(page('<canvas id="c" width="10" height="10"></canvas>', 100, 100));
  await p.evaluate(() => document.fonts.ready);
  return p.evaluate(
    ({ arabe, latin, interlettre }) => {
      const ctx = document.getElementById('c').getContext('2d');
      const REF = 200; // taille de mesure : assez grande pour rester précise

      const mesurer = (texte, { rtl = false, espacement = 0 } = {}) => {
        ctx.font = `700 ${REF}px Cairo`;
        ctx.direction = rtl ? 'rtl' : 'ltr';
        ctx.textAlign = 'left';
        ctx.textBaseline = 'alphabetic';
        ctx.letterSpacing = `${espacement}em`;
        const m = ctx.measureText(texte);
        // Ligne de base d'une boîte CSS en line-height:1, depuis son haut.
        const base =
          (REF - (m.fontBoundingBoxAscent + m.fontBoundingBoxDescent)) / 2 +
          m.fontBoundingBoxAscent;
        return {
          largeur: (Math.abs(m.actualBoundingBoxLeft) + m.actualBoundingBoxRight) / REF,
          hauteur: (m.actualBoundingBoxAscent + m.actualBoundingBoxDescent) / REF,
          hautInk: (base - m.actualBoundingBoxAscent) / REF,
        };
      };

      return {
        arabe: mesurer(arabe, { rtl: true }),
        latin: mesurer(latin, { espacement: interlettre }),
      };
    },
    { arabe, latin, interlettre: INTERLETTRE_LATIN },
  );
}

/**
 * Relit une image rendue et renvoie les proportions réellement obtenues, pour
 * les comparer à `REPERE`. C'est la seule façon d'affirmer que le logo est
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
          largeur: f(ar.xmax - ar.xmin + 1),
          hauteur: f(ar.ymax - ar.ymin + 1),
          haut: f(ar.ymin),
        },
        filet: filet && {
          largeur: f(filet.xmax - filet.xmin + 1),
          centre: f((filet.ymin + filet.ymax) / 2),
          epaisseur: f(filet.ymax - filet.ymin + 1),
        },
        latin: la && {
          largeur: f(la.xmax - la.xmin + 1),
          hauteur: f(la.ymax - la.ymin + 1),
          haut: f(la.ymin),
        },
      };
    },
    { png: pngBase64, T: taille },
  );
}

module.exports = {
  logo, page, geometrie, mesurerMetriques, mesurerRendu,
  FONDS, CREME, OR, REPERE, METRIQUES_DEFAUT,
};
