# Générateur du logo

Le logo de Khoutba appartient à la famille AdhanBox / Adhan Hub : le mot arabe **أذان**, un filet doré, puis **KHOUTBA** — sur un fond prune.

Toutes les icônes (iOS, Android, web) sont produites depuis ce seul script : pas de fichier binaire à retoucher à la main.

## Le mot arabe est un dessin, pas du texte

Le أذان d'AdhanBox n'a pas été composé dans une police : c'est un logotype dessiné. Le rejouer en Cairo donnait un ن plus étroit et plus profond, un ذ décalé, et un filet parfaitement droit là où l'original ondule — de loin, les trois icônes de la famille ne se ressemblaient pas.

Il est donc **repris tel quel**. `extraire-motif.js` le détache de l'icône AdhanBox en transparence :

```bash
node extraire-motif.js /chemin/vers/adhanbox/flutter_app/assets/images/app_logo.png
```

Le fond est vert très sombre (rouge ≈ 12) et le motif crème (249) ou doré (243) : le canal rouge donne directement l'opacité de chaque pixel, bords antialiasés compris. Le résultat (`motif-adhan.png` + les boîtes utiles dans `motif-adhan.json`) est versionné — inutile de relancer le script, sauf si le logo d'AdhanBox change.

Recouvrement obtenu avec l'original : **100 %** du mot arabe.

## Ce qui reste composé

Seul « KHOUTBA » est du texte, en Cairo Bold — vérifié en superposant les lettres de « BOX » d'AdhanBox, qui coïncident. Sa taille et sa position sont calculées, jamais écrites en dur :

1. `mesurerMetriques()` mesure sa boîte d'encre dans la police (largeur hors interlettre, hauteur de capitale, décalage sous le haut de la ligne) ;
2. une première image est rendue, relue, et l'écart résiduel entre métriques et rendu réel est reporté ;
3. `mesurerRendu()` relit l'image finale et **compare aux repères** : le script affiche l'écart en pixels et sort en erreur au-delà de 4 ‰ du cadre.

Deux différences assumées avec « BOX », toutes deux dues à sa longueur — sept lettres contre trois :

- **il est plus petit.** À la hauteur de capitale de la famille, le mot ferait 97 % de la largeur du cadre. Sa largeur est donc bornée (`latinLargeurMax`) et sa hauteur suit.
- **il est moins espacé.** « BOX » est tracké à 0,307 em ; garder cette respiration rétrécirait encore les lettres. Au-delà d'une certaine longueur, l'interlettre se resserre à 0,12 em pour privilégier la taille des lettres, plus visible sur l'écran d'accueil.

## Régénérer

```bash
cd outils/logo
./polices.sh          # télécharge la police Cairo (une fois)
npm install playwright
node generer.js
```

Cela écrit :
- `native/ios/Runner/Assets.xcassets/AppIcon.appiconset/` — 15 tailles, sans transparence (exigence d'iOS)
- `native/android/app/src/main/res/mipmap-*/` — 5 densités + avant-plan de l'icône adaptative
- `native/assets/logo.png` — logo affiché dans l'en-tête de l'app
- `icons/` — icônes de la version web (dont la version « maskable »)

## Modifier

Tout se règle en haut de `generer.js` :

```js
const FOND = 'prune';       // ou bleu nuit, ardoise, brun cuir, vert (AdhanBox)
const ARABE = 'أذان';
const LATIN = 'KHOUTBA';
```

Les fonds disponibles sont définis dans `logo.js` (`FONDS`) — ajoutes-en un en donnant deux teintes, claire puis sombre, pour le dégradé.

## Deux détails qui comptent

- **Sous 64 px**, le mot « KHOUTBA » devient illisible : le script ne garde alors que le mot arabe, agrandi. C'est ce qui rend l'icône nette dans les Réglages et Spotlight.
- **Les tailles de texte sont mesurées à chaque exécution**, jamais écrites en dur. Chaque mot a sa propre largeur dans la police (« أذان » fait 1,82 fois la taille de police, « خطبة » 2,34, « KHOUTBA » 5,05) : une taille figée déborde du cadre dès qu'on change de texte. Le script mesure puis calcule — tu peux donc changer de mot sans rien recalculer.

La police [Cairo](https://fonts.google.com/specimen/Cairo) est sous licence SIL Open Font ; elle est téléchargée à la demande plutôt que stockée ici.
