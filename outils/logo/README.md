# Générateur du logo

Le logo de Khoutba appartient à la famille AdhanBox / Adhan Hub : le mot arabe **أذان**, un filet doré, puis **KHOUTBA** — sur un fond prune.

Toutes les icônes (iOS, Android, web) sont produites depuis ce seul script : pas de fichier binaire à retoucher à la main.

## Pourquoi ces proportions

Les repères de `logo.js` (`REPERE`) ont été **relevés au pixel sur l'icône AdhanBox** puis ramenés en fraction du cadre : largeur du mot arabe, largeur et épaisseur du filet, hauteur des capitales latines, position verticale de chacun. C'est ce qui fait que les trois icônes se ressemblent côte à côte sur l'écran d'accueil.

Rien n'est réglé à l'œil :

1. `mesurerMetriques()` mesure la boîte d'encre de chaque mot dans la police — largeur, hauteur, décalage sous le haut de la ligne. Changer un mot ne casse donc pas le placement.
2. Une première image est rendue, relue, et l'écart résiduel entre les métriques de la police et le rendu réel est reporté (la hamza au-dessus du أ ne tombe pas là où le canvas l'annonce).
3. `mesurerRendu()` relit l'image finale et **compare à `REPERE`** : le script affiche l'écart en pixels et sort en erreur au-delà de 4 ‰ du cadre.

Seule différence assumée avec AdhanBox : « KHOUTBA » fait sept lettres contre trois à « BOX ». Garder la même taille de capitale le ferait toucher les bords, donc sa largeur est bornée (`latinLargeurMax`) et sa hauteur suit.

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
