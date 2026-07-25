# Khoutba — version native (Flutter)

Même app que la version web, avec **la fonction qui manquait : l'enregistrement continue écran éteint, téléphone rangé dans la poche.**

| | Version web (PWA) | Version native (ce dossier) |
|---|---|---|
| Enregistrer écran éteint | ❌ le navigateur coupe le micro | ✅ |
| Enregistrer app en arrière-plan | ❌ | ✅ |
| Installation | ouvrir un lien | passer par Xcode / Android Studio |
| Mise à jour | automatique | recompiler |

Tout le reste est identique : transcription arabe, traduction, résumé structuré (versets, hadiths, conseils, douas), stockage 100 % local, choix du service d'IA.

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

### Sur iPhone (depuis un Mac)

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
  main.dart            démarrage, thème, locale française
  etat.dart            état global partagé (liste, traitement en cours)
  enregistreur.dart    capture audio + service premier plan + récupération
  fournisseurs.dart    Gemini / OpenAI / Claude + choix auto du modèle Gemini
  traitement.dart      chaîne transcription → traduction → synthèse (prompts)
  stockage.dart        index JSON + fichiers audio
  reglages.dart        préférences + clés API (stockage sécurisé)
  modeles.dart         structures de données
  theme.dart           couleurs, styles (clair/sombre, texte arabe)
  ecrans/              accueil, détail, réglages
test/khoutba_test.dart 16 tests (classement des modèles, JSON, statuts, affichage)
```

Le modèle Gemini n'est pas codé en dur : l'app interroge la liste des modèles accessibles avec ta clé et bascule automatiquement si l'un est retiré (même logique que la version web).

## Vérifications faites

- `flutter analyze` : aucun problème
- `flutter test` : 16 tests au vert
- Cibles de compilation contrôlées : Android minSdk 24 (plugins : 21), iOS 13.0 (plugins : 12.0)

**Non vérifié ici** : la compilation finale sur appareil — elle demande Xcode (Mac) ou le SDK Android, absents de l'environnement de développement. C'est l'étape que tu fais toi-même.
