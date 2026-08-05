# Khoutba — version native (Flutter)

Même app que la version web, avec **la fonction qui manquait : l'enregistrement continue écran éteint, téléphone rangé dans la poche.**

| | Version web (PWA) | Version native (ce dossier) |
|---|---|---|
| Enregistrer écran éteint | ❌ le navigateur coupe le micro | ✅ |
| Enregistrer app en arrière-plan | ❌ | ✅ |
| Installation | ouvrir un lien | passer par Xcode / Android Studio |
| Mise à jour | automatique | recompiler |

Tout le reste est identique : transcription arabe, traduction, résumé structuré (versets, hadiths, conseils, douas), stockage 100 % local, choix du service d'IA.

## Importer un fichier existant

Le bouton **« ou importer un audio / une vidéo »** propose deux sources, parce qu'elles ne donnent pas accès aux mêmes fichiers :

- **Fichiers** — mémos vocaux, audio WhatsApp, iCloud, « Sur mon iPhone »…
- **Galerie** — les vidéos filmées avec le téléphone, que le sélecteur de fichiers d'iOS ne montre pas.

Le fichier est recopié dans l'app : l'original peut ensuite être déplacé ou supprimé. La date affichée est celle du fichier, pas celle de l'import — une khoutba filmée la semaine dernière garde sa date.

### D'une vidéo, on ne garde que le son

Un prêche filmé de 11 min pèse ~700 Mo ; sa piste sonore, une dizaine de Mo. L'image ne sert à rien pour une transcription : à l'import, l'app **isole la piste audio dans un `.m4a`** avant tout envoi. C'est le système qui s'en charge, sans dépendance ajoutée :

- **iOS** : `AVAssetExportSession` (preset Apple M4A) ;
- **Android** : `MediaExtractor` + `MediaMuxer` — la piste est recopiée telle quelle, sans ré-encodage : quelques secondes de traitement, aucune perte de qualité.

Conséquences directes : l'envoi passe de plusieurs dizaines de minutes à moins d'une, la vidéo n'occupe plus la mémoire du téléphone, et **Whisper (OpenAI) redevient utilisable** — un `.m4a` d'une khoutba tient largement sous sa limite de 25 Mo, ce qu'une vidéo dépassait toujours.

Si le système n'y arrive pas (codec inhabituel), l'import n'échoue pas : la vidéo entière est conservée et envoyée, l'app le signale. Seul cas refusé : une vidéo **sans aucune piste sonore**, où il n'y a rien à transcrire.

Une vidéo déjà dans l'app — importée avant cette version, ou dont l'extraction avait échoué — est **rattrapée au moment de « Transcrire & traduire »** : la piste est isolée juste avant l'envoi et la vidéo effacée, ce qui rend au passage ses centaines de Mo au téléphone.

Les fichiers restants volumineux sont envoyés **par tranches de 8 Mo**, avec la progression affichée et quelques tentatives par tranche : charger un tel fichier d'un bloc en mémoire fait tuer l'app par iOS.

Formats acceptés : audio (m4a, mp3, wav, ogg, flac, amr…) et vidéo (mp4, mov, 3gp, mkv…).

## Comment l'enregistrement survit à l'écran éteint

- **Android** : un *service au premier plan* de type `microphone` (`flutter_foreground_task`) garde le processus vivant, avec une notification permanente pendant l'enregistrement. Déclaré dans `android/app/src/main/AndroidManifest.xml` — ce type est obligatoire depuis Android 14.
- **iOS** : le mode `audio` en arrière-plan (`UIBackgroundModes` dans `ios/Runner/Info.plist`) laisse la capture continuer écran verrouillé.
- **Filet de sécurité** : l'audio est écrit dans un `.m4a` au fil de l'enregistrement, et une trace de session est posée dans les préférences. Si l'app est tuée (batterie vide, système), le fichier est récupéré automatiquement au prochain lancement.

## Compiler et installer

Prérequis : [Flutter](https://docs.flutter.dev/get-started/install) installé (`flutter doctor` doit être vert).

```bash
cd native
flutter pub get
```

### Sur iPhone — le plus simple

Branche l'iPhone en USB, puis **double-clique `installer_iphone.command`** (dans le Finder, dossier `native`).

Le script vérifie Xcode, installe Flutter et CocoaPods si besoin, détecte ton iPhone, compile et installe l'app. Quand une étape demande une action de ta part (créer ton certificat la première fois, activer le mode développeur sur l'iPhone), il te dit exactement quoi faire.

> Si macOS refuse de lancer le fichier : clic droit → *Ouvrir* → *Ouvrir* (une seule fois).
> En ligne de commande : `cd native && ./installer_iphone.command`

### Sur iPhone — à la main (si tu préfères Xcode)

1. `open ios/Runner.xcworkspace` (Xcode)
2. Onglet **Signing & Capabilities** → coche *Automatically manage signing* → choisis ton **Team** (un compte Apple gratuit suffit)
3. Change le *Bundle Identifier* si Xcode le réclame (ex. `com.tonnom.khoutba`)
4. Branche l'iPhone, sélectionne-le en haut, appuie sur ▶
5. Sur l'iPhone : *Réglages → Général → VPN et gestion de l'appareil* → fais confiance à ton certificat de développeur

> Avec un compte Apple gratuit, l'app expire au bout de **7 jours** — il suffit de relancer ▶ depuis Xcode pour la réactiver. Un compte développeur payant porte ça à un an.

Ou en ligne de commande : `flutter run --release -d <ton-iphone>`

### Sur Android

```bash
flutter build apk --release
# le fichier est dans build/app/outputs/flutter-apk/app-release.apk
```
Copie l'APK sur le téléphone et installe-le (il faut autoriser les « sources inconnues »).

## Réglages au premier lancement

⚙️ → choisis les services IA et colle ta clé. Une **clé Gemini gratuite** ([aistudio.google.com/apikey](https://aistudio.google.com/apikey)) suffit pour la transcription *et* la traduction. Les clés sont rangées dans le trousseau iOS / keystore Android, jamais dans un fichier en clair.

Un **mode démo** permet de voir tout le fonctionnement sans aucune clé.

## Structure du code

```
lib/
  main.dart              démarrage, thème, locale française
  etat.dart              état global partagé (liste, traitement en cours)
  enregistreur.dart      capture audio + service premier plan + récupération
  fournisseurs.dart      Gemini / OpenAI / Claude + choix auto du modèle Gemini
  traitement.dart        chaîne transcription → traduction → synthèse (prompts)
  stockage.dart          index JSON + fichiers audio
  reglages.dart          préférences + clés API (stockage sécurisé)
  import_media.dart      import d'un audio/vidéo depuis Fichiers ou la galerie
  extraction_audio.dart  isole la piste sonore d'une vidéo (code natif iOS/Android)
  modeles.dart           structures de données
  theme.dart             couleurs, styles (clair/sombre, texte arabe)
  ecrans/                accueil, détail, réglages
test/khoutba_test.dart   34 tests (modèles Gemini, JSON, statuts, formats,
                         découpage, extraction audio, affichage)
```

Le modèle Gemini n'est pas codé en dur : l'app interroge la liste des modèles accessibles avec ta clé et bascule automatiquement si l'un est retiré (même logique que la version web).

## Vérifications faites

- `flutter analyze` : aucun problème
- `flutter test` : 34 tests au vert
- Cibles de compilation contrôlées : Android minSdk 24 (plugins : 21), iOS 13.0 (plugins : 12.0)

**Non vérifié dans l'environnement de développement** : la compilation finale, qui demande Xcode (Mac) ou le SDK Android. Le code Swift (`ios/Runner/ExtractionAudio.swift`) et Kotlin (`android/…/ExtractionAudio.kt`) de l'extraction audio n'y a donc jamais été compilé — seul son contrat côté Dart est couvert par les tests. La compilation est vérifiée par GitHub à chaque envoi de code — voir `.github/workflows/compilation.yml` : analyse, tests, APK Android et compilation iOS. L'APK produit est téléchargeable dans l'onglet **Actions** du dépôt (section *Artifacts*) et s'installe directement sur un téléphone Android.
