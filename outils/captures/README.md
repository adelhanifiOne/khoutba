# Captures d'écran pour les stores

Ce script **n'invente aucun écran**. Il habille les captures prises sur le téléphone :
fond prune, accroche, filet doré, et les dimensions exactes réclamées par Apple et Google.

Les captures doivent venir de l'app réelle — Apple demande l'application « en cours
d'utilisation », et une image reconstituée qui dérive de l'app est un motif de rejet.

## Le plus simple : le simulateur

```bash
cd outils/captures && ./simulateur.command
```

Le script démarre un iPhone Pro Max, **fige la barre d'état sur 9:41** (batterie pleine, aucune
notification), installe l'app fraîchement compilée, et capture à chaque fois que tu appuies sur
Entrée. Les images sortent aux dimensions exactes d'Apple, sans retouche et sans donnée
personnelle à l'écran. Il lance l'habillage tout seul à la fin.

Dans le simulateur, appuie sur **« Voir un exemple »** : une khoutba déjà traitée s'ouvre, avec
tout le contenu nécessaire aux six captures.

## Ou à la main, depuis ton téléphone

**Active d'abord le mode démo** : ⚙️ Réglages → *Mode démo*. Le contenu affiché devient fictif :
aucune vraie khoutba, aucune clé API ne se retrouve sur une image publique.

Capture ensuite dans cet ordre :

| Fichier | Écran à capturer |
|---------|------------------|
| `1.png` | Accueil, avec le gros bouton micro et la liste des khoutbas |
| `2.png` | Onglet **Résumé** rempli — thème, points clés |
| `3.png` | Le même, défilé jusqu'aux **versets et hadiths cités** |
| `4.png` | Onglet **Traduction** |
| `5.png` | Onglet **النص العربي** |
| `6.png` | L'écran de bienvenue (visible après une réinstallation) |

Sur iPhone : bouton latéral + volume haut. Récupère les fichiers par AirDrop ou iCloud, et
range-les dans `outils/captures/brutes/` sous ces noms exacts.

> La barre d'état est conservée telle quelle. Apple l'accepte ; évite simplement une capture
> avec 3 % de batterie ou une notification en haut de l'écran.

## Produire les images (si tu as capturé à la main)

```bash
cd outils/captures
npm install playwright        # une fois
node generer.js
```

Résultat dans `store/captures/` :

| Dossier | Dimensions | Où l'utiliser |
|---------|-----------|----------------|
| `6.9/` | 1320 × 2868 | App Store — **obligatoire** |
| `6.5/` | 1242 × 2688 | App Store — anciens modèles |
| `play/` | 1080 × 1920 | Google Play |

Une capture manquante est simplement ignorée : on peut commencer avec deux ou trois images et
compléter plus tard.

Pour voir la mise en page sans avoir encore les vraies captures :

```bash
node generer.js --exemple     # remplit brutes/ de repères numérotés
```

## Modifier les accroches

Elles sont en haut de `generer.js`, dans `CAPTURES`. Le `\n` force le retour à la ligne — deux
lignes courtes se lisent mieux qu'une longue dans une liste de résultats.

L'ordre compte : sur l'App Store, la plupart des gens ne voient que **les deux premières**.

## Ce qui n'est pas versionné

Ni `brutes/` ni `store/captures/` : ce sont vos captures d'un côté, des fichiers reconstructibles
de l'autre. Un coup de `node generer.js` les refait à l'identique.
