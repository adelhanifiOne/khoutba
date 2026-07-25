// Logo Khoutba repris de celui d'AdhanBox : mot arabe, filet doré, mot latin.
// Seuls changent la couleur de fond et le texte.
const fs = require('fs');
const path = require('path');
const b64 = (f) => fs.readFileSync(path.join(__dirname, 'polices', f)).toString('base64');
const POLICES = `
  @font-face { font-family:'Cairo'; font-weight:700; font-display:block;
    src:url(data:font/woff2;base64,${b64('cairo_1.woff2')}) format('woff2');
    unicode-range: U+0600-06FF, U+0750-077F, U+FB50-FDFF, U+FE70-FEFF; }
  @font-face { font-family:'Cairo'; font-weight:700; font-display:block;
    src:url(data:font/woff2;base64,${b64('cairo_3.woff2')}) format('woff2'); }`;

// Fonds proposés : le vert est celui d'AdhanBox, gardé comme repère.
const FONDS = {
  'bleu nuit': ['#1E3A5F', '#0A1A2F'],
  prune: ['#4A2545', '#1F0E22'],
  ardoise: ['#33403F', '#111917'],
  'brun cuir': ['#5B3B22', '#26150A'],
  'vert (AdhanBox)': ['#1F7A5A', '#08381F'],
};

const CREME = '#F7F3EA';
const OR = '#D9B24C';

/**
 * Le logo complet, en HTML (rendu ensuite en PNG par Chromium).
 * - `sansTexteLatin` : sous 40 px le mot « KHOUTBA » devient illisible ;
 *    on ne garde alors que le mot arabe, agrandi.
 * - `echelle` : réduit le contenu sans toucher au cadre (icônes rognées
 *    en cercle sur Android, ou « maskable » du web).
 * - `fond: null` : sans fond, pour l'avant-plan des icônes adaptatives.
 */
// Part de la largeur du cadre occupée par le texte. Les tailles de police en
// découlent : elles ne sont jamais écrites en dur, sinon changer un mot fait
// déborder le dessin (chaque mot a sa propre largeur dans la police).
const OCCUPATION = { arabeSeul: 0.78, arabeAvecLatin: 0.69, latin: 0.72 };
const INTERLETTRE_LATIN = 0.108; // en em, pour que tout reste proportionnel

/**
 * `largeurs` : largeur des mots pour une police de 1 px, mesurée par
 * `mesurerLargeurs()`. C'est ce qui permet d'ajuster automatiquement.
 */
function logo({
  fond = 'bleu nuit',
  arabe = 'خطبة',
  latin = 'KHOUTBA',
  taille = 512,
  sansTexteLatin = false,
  echelle = 1,
  largeurs = { arabe: 2.343, latin: 4.857 },
} = {}) {
  const e = taille / 512; // tout est dessiné pour 512 puis mis à l'échelle
  const degrade = fond
    ? `background:linear-gradient(160deg, ${FONDS[fond][0]} 0%, ${FONDS[fond][1]} 100%);`
    : '';

  const part = sansTexteLatin ? OCCUPATION.arabeSeul : OCCUPATION.arabeAvecLatin;
  const tailleArabe = (512 * part) / largeurs.arabe;
  const tailleLatin = (512 * OCCUPATION.latin) / largeurs.latin;

  const contenu = `
    <div style="font-family:Cairo,sans-serif;font-weight:700;color:${CREME};
                font-size:${tailleArabe * e}px;line-height:1.25;direction:rtl;
                white-space:nowrap;">${arabe}</div>
    ${sansTexteLatin ? '' : `
    <div style="width:${200 * e}px;height:${9 * e}px;background:${OR};
                border-radius:${5 * e}px;margin:${20 * e}px 0 ${18 * e}px;"></div>
    <div style="font-family:Cairo,sans-serif;font-weight:700;color:${CREME};
                font-size:${tailleLatin * e}px;line-height:1.15;white-space:nowrap;
                letter-spacing:${INTERLETTRE_LATIN}em;
                text-indent:${INTERLETTRE_LATIN}em;">${latin}</div>`}`;

  return `
  <div style="width:${taille}px;height:${taille}px;position:relative;overflow:hidden;${degrade}
              display:flex;flex-direction:column;align-items:center;justify-content:center;">
    <div style="display:flex;flex-direction:column;align-items:center;
                transform:scale(${echelle});">${contenu}</div>
  </div>`;
}

const page = (contenu, largeur, hauteur, styleSupp = '') => `<!DOCTYPE html>
<html><head><meta charset="utf-8"><style>
  *{margin:0;padding:0;box-sizing:border-box}
  ${POLICES}
  ${styleSupp}
</style></head><body>${contenu}</body></html>`;

/**
 * Mesure la largeur des deux mots pour une police de 1 px. Indispensable :
 * chaque mot a sa propre largeur, et une taille écrite en dur déborde du
 * cadre dès qu'on change de texte.
 */
async function mesurerLargeurs(p, { arabe, latin }) {
  await p.setContent(page(
    `<span id="ar" style="font-family:Cairo;font-weight:700;font-size:100px;direction:rtl;white-space:nowrap">${arabe}</span>
     <span id="la" style="font-family:Cairo;font-weight:700;font-size:100px;white-space:nowrap;letter-spacing:${INTERLETTRE_LATIN}em">${latin}</span>`,
    900, 400, 'span{display:inline-block}'
  ));
  await p.evaluate(() => document.fonts.ready);
  return p.evaluate(() => ({
    arabe: document.getElementById('ar').getBoundingClientRect().width / 100,
    latin: document.getElementById('la').getBoundingClientRect().width / 100,
  }));
}

module.exports = { logo, page, mesurerLargeurs, FONDS, CREME, OR, OCCUPATION };
