# Générateur du logo

Le logo de Khoutba est repris de celui d'AdhanBox : le mot arabe **خطبة**, un filet doré, puis **KHOUTBA** — sur un fond bleu nuit.

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
const FOND = 'bleu nuit';   // ou prune, ardoise, brun cuir, vert (AdhanBox)
const ARABE = 'خطبة';
```

Les fonds disponibles sont définis dans `logo.js` (`FONDS`) — ajoutes-en un en donnant deux teintes, claire puis sombre, pour le dégradé.

## Deux détails qui comptent

- **Sous 64 px**, le mot « KHOUTBA » devient illisible : le script ne garde alors que le mot arabe, agrandi. C'est ce qui rend l'icône nette dans les Réglages et Spotlight.
- **Les tailles de texte sont calculées**, pas devinées : dans la police Cairo, « خطبة » mesure 2,34 fois la taille de police et « KHOUTBA » 4,86 fois. Si tu changes de mot ou de police, remesure avant d'ajuster (sinon le texte déborde du cadre).

La police [Cairo](https://fonts.google.com/specimen/Cairo) est sous licence SIL Open Font ; elle est téléchargée à la demande plutôt que stockée ici.
