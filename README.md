# 🕌 Khoutba

**Enregistre le prêche du vendredi à la mosquée, et retrouve-le chez toi en français : transcription arabe, traduction complète et résumé clair — style Plaud.**

Tu es à la mosquée, l'imam parle en arabe et tu ne comprends pas tout ? Lance l'enregistrement, pose le téléphone, écoute. De retour à la maison, appuie sur « Transcrire & traduire » : l'app te donne le texte arabe, la traduction française fidèle, un résumé, les points clés, les versets et hadiths cités avec leurs références, et les conseils pratiques de l'imam.

## Comment ça marche

0. **Tu as déjà un fichier ?** — le bouton d'import prend un audio **ou une vidéo** déjà sur le téléphone (mémo vocal, WhatsApp, vidéo filmée du prêche) et le traite de la même façon.
1. **À la mosquée** — bouton micro, l'enregistrement démarre. Tout est stocké **sur ton téléphone** (ça marche sans internet). L'audio est sauvegardé toutes les 5 secondes : même si l'app se ferme, rien n'est perdu.
2. **À la maison** — ouvre l'enregistrement, appuie sur **Transcrire & traduire**. L'app envoie l'audio au service d'IA que tu as choisi, puis affiche :
   - **Résumé** : thème, résumé fidèle, points clés, versets & hadiths cités (arabe + traduction + référence), conseils pratiques, douas ;
   - **Traduction** : le prêche complet en français ;
   - **النص العربي** : la transcription arabe intégrale.
3. **Garde et partage** — exporte en Markdown, partage le résumé, réécoute l'audio.

## Installation

C'est une **PWA** : un site web qui s'installe comme une app.

### Option A — GitHub Pages (recommandé, gratuit)

1. Sur GitHub : **Settings → Pages → Source : Deploy from a branch → Branch : `main` / `(root)` → Save**.
2. Quelques minutes plus tard, l'app est en ligne sur `https://<ton-compte>.github.io/khoutba/`.
3. Ouvre cette adresse sur ton téléphone (Chrome sur Android, Safari sur iPhone) → menu → **« Ajouter à l'écran d'accueil »**.

> ⚠️ Si le dépôt est privé, GitHub Pages nécessite un compte payant — passe le dépôt en public (Settings → General → Danger Zone → Change visibility), il ne contient aucun secret.

### Option B — en local

```bash
npx serve .
# puis ouvrir http://localhost:3000
```

(Le micro exige HTTPS ou localhost — ne pas ouvrir `index.html` directement en `file://`.)

## Clés API (une seule suffit)

L'app n'a **pas de serveur** : elle appelle directement le service d'IA avec **ta** clé, stockée uniquement sur ton téléphone (réglages ⚙️).

| Service | Sert à | Où obtenir la clé | Prix |
|---|---|---|---|
| **Gemini** (Google) | Transcription **et** traduction/résumé | [aistudio.google.com/apikey](https://aistudio.google.com/apikey) | **Offre gratuite** largement suffisante pour un usage hebdomadaire |
| **OpenAI** | Transcription (Whisper, très bon en arabe) et/ou traduction | [platform.openai.com/api-keys](https://platform.openai.com/api-keys) | ≈ 0,20 $ par khoutba de 30 min (Whisper) |
| **Claude** (Anthropic) | Traduction & résumé haut de gamme | [console.anthropic.com](https://console.anthropic.com) | ≈ 0,20–0,50 $ par khoutba selon le modèle |

**Pour commencer simplement : crée une clé Gemini (gratuite), et choisis Gemini pour les deux étapes dans les réglages.** Tu pourras affiner ensuite (par ex. Whisper pour la transcription + Claude pour la traduction, la combinaison la plus qualitative).

Un **mode démo** (réglages) permet d'essayer toute l'app sans aucune clé, avec des textes fictifs.

## Deux versions

| | Version web (ce dossier) | [Version native](native/) (Flutter) |
|---|---|---|
| Installation | ouvrir un lien, « ajouter à l'écran d'accueil » | compiler avec Xcode / Android Studio |
| Enregistrer **écran éteint** | ❌ (limite des navigateurs) | ✅ |
| Mise à jour | automatique | recompiler |

Même fonctionnement, mêmes prompts, mêmes services d'IA. Commence par la version web ; passe au natif si l'écran allumé pendant tout le prêche te gêne.

## Limites à connaître

- **Garde l'écran allumé pendant l'enregistrement** (l'app s'en occupe via le verrou d'écran). Les navigateurs coupent le micro quand le téléphone se verrouille — c'est LA limite des web apps, et la raison d'être de la [version native](native/). Autre solution : enregistre avec le **dictaphone** du téléphone (qui marche écran éteint), puis **importe le fichier** dans Khoutba pour le traitement.
- **Transcriptions longues** : Whisper (OpenAI) est limité à 25 Mo (≈ 2 h à notre débit d'enregistrement). Gemini accepte des fichiers bien plus longs.
- **Vérifie les références** : l'IA identifie les versets et hadiths cités, mais peut se tromper de référence — les citations importantes méritent une vérification.
- L'arabe algérien (darija) mélangé au littéraire est bien géré, mais la qualité dépend du placement du téléphone : près d'un haut-parleur de la salle = résultat nettement meilleur.

## Vie privée

- Enregistrements, textes et clés restent **sur ton appareil** (IndexedDB / localStorage). Pas de serveur, pas de compte, pas de statistiques.
- Au moment du traitement uniquement, l'audio (puis le texte) est envoyé au fournisseur d'IA choisi, sous **ta** clé et leurs conditions d'utilisation.
- Par respect, évite d'enregistrer les conversations privées ; le prêche est un discours public, mais en cas de doute demande l'avis de la mosquée.

## Technique

- PWA sans framework ni build : HTML/CSS/JS (modules), Service Worker, IndexedDB.
- Enregistrement : MediaRecorder mono 32 kb/s (webm/opus sur Android, mp4/AAC sur iPhone), ≈ 14 Mo/heure.
- Fournisseurs : Gemini (audio natif + API Files pour les gros fichiers), OpenAI (`whisper-1`, `gpt-4o-mini`), Anthropic (`claude-opus-4-8` par défaut, appel direct navigateur).
- **Le modèle Gemini n'est pas codé en dur** : Google retire régulièrement d'anciens modèles (« no longer available to new users »). L'app interroge `ListModels` avec ta clé, classe les modèles disponibles (multimodal, récent, économique) et bascule automatiquement sur le suivant si l'un disparaît. Choix manuel possible dans les réglages.
- Mise à jour : incrémenter `CACHE` dans `sw.js` à chaque mise en ligne — les apps déjà installées se rechargent alors toutes seules.
- La synthèse est produite en JSON structuré (schéma strict côté OpenAI/Claude).

## Idées pour la suite

- Détection automatique du vendredi + rappel.
- Bibliothèque des khoutbas par thème, recherche plein texte.
- Partage familial d'un résumé hebdomadaire.

---

*Fait avec ❤️ pour mieux comprendre le minbar. Qu'Allah agrée vos vendredis.*
