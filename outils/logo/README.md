# Générateur du logo

Le logo de Khoutba est repris de celui d'AdhanBox : le mot arabe **أذان**, un filet doré, puis **KHOUTBA** — sur un fond prune.

Toutes les icônes (iOS, Android, web) sont produites depuis ce seul script : pas de fichier binaire à retoucher à la main.

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
