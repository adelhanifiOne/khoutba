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

Les fichiers restants volumineux sont envoyés **par tranches de 8 Mo**, avec les mégaoctets transférés affichés et quelques tentatives par tranche : charger un tel fichier d'un bloc en mémoire fait tuer l'app par iOS. Un pourcentage seul serait trompeur — sur 1,2 Go, une tranche ne le fait bouger que de 0,65 %, et l'envoi a l'air figé alors qu'il avance.

### Place sur le téléphone

Une vidéo passe par plusieurs copies avant d'arriver dans l'app, et un import qui échoue en laisse derrière lui. Trois garde-fous :

- **Vérification avant d'écrire** — s'il n'y a pas la place, l'app le dit (« il faut 1,2 Go, il n'en reste que 240 Mo ») au lieu de s'arrêter au milieu sur un `errno = 28` illisible ;
- **Ménage au lancement** — les fichiers audio que plus aucune fiche ne référence et les copies laissées par les sélecteurs dans le dossier temporaire sont effacés, et l'app annonce ce qu'elle a rendu ;
- **Copie temporaire supprimée** dès l'import terminé — le sélecteur en fabrique une, de la taille de la vidéo.

Les réglages affichent la place occupée **et** la place restante.

Formats acceptés : audio (m4a, mp3, wav, ogg, flac, amr…) et vidéo (mp4, mov, 3gp, mkv…).

## Réécouter en lisant la traduction

Le lecteur reste en haut de la fiche pendant que les onglets défilent : on suit le prêche à
l'oreille, la traduction sous les yeux. Trois commandes servent vraiment à ça :

- **− 10 s** — le geste le plus fréquent, pour reprendre un passage mal saisi ;
- **+ 30 s** — passer une invocation ou une redite ;
- **la vitesse** (1× → 0,75× → 1,25× → 1,5×) — ralentir aide plus que tout à raccrocher l'arabe
  au texte français quand on l'apprend encore.

Reculer avant le début ou avancer au-delà de la fin ne produit rien de fâcheux : la position est
bornée, y compris quand la durée du fichier est inconnue — cas d'un enregistrement récupéré après
un arrêt brutal, où borner à zéro interdirait toute avance.

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

Le script **récupère d'abord la dernière version du code**, puis vérifie Xcode, installe Flutter et CocoaPods si besoin, détecte ton iPhone, compile et installe l'app. Quand une étape demande une action de ta part (créer ton certificat la première fois, activer le mode développeur sur l'iPhone), il te dit exactement quoi faire.

Il affiche le commit qu'il compile (`Version compilée : 21b3750 — …`), et l'app affiche la sienne dans ⚙️ **Réglages → Version installée** : les deux doivent concorder après une réinstallation. Sans ce repère, deux versions successives sont indiscernables et on réinstalle à l'aveugle. Et quand la mise à jour touche au logo, il nettoie le cache de compilation — sinon Xcode réutilise l'ancien catalogue d'icônes et l'iPhone garde l'ancienne icône.

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

## Premier lancement

L'app s'ouvre sur un écran qui propose deux chemins :

- **Voir un exemple** — crée une khoutba **déjà traitée** et l'ouvre : résumé, versets cités, traduction et texte arabe, immédiatement lisibles, sans clé ni attente. Le bouton se contentait d'activer le mode démo et renvoyait sur une liste vide — le premier écran de quiconque découvrait l'app, testeur de l'App Store compris, à qui l'on demandait de juger sur rien. C'est aussi ce qui satisfait la règle 4.2 (« minimum functionality »).
- **Commencer pour de vrai** — explique en trois phrases à quoi sert la clé Gemini, ouvre la bonne page Google d'un bouton, et **vérifie la forme de ce qui est collé** avant de l'accepter.

Cette dernière vérification ne porte **jamais sur le préfixe attendu**, et c'est une leçon payée cash : les clés Gemini ont commencé par `AIza`, puis Google est passé à `AQ.` — la vérification, censée aider, refusait alors des clés parfaitement valides et bloquait l'app au premier écran.

Ne sont donc refusées que les saisies qui ne peuvent pas être des clés : champ trop court, espaces, adresse e-mail, URL de la page, et surtout une clé **recopiée depuis l'écran plutôt que par le bouton Copier** — Google n'y affiche qu'une version abrégée, terminée par des points de suspension. C'est l'erreur la plus fréquente, et la seule que le contrôle attrape vraiment. Une clé au format inconnu passe, avec un simple avertissement.

Une seule clé Gemini couvre la transcription *et* la traduction, et l'écran la configure pour les deux — l'utilisateur n'a pas à comprendre la différence. Les clés sont rangées dans le trousseau iOS / keystore Android, jamais dans un fichier en clair.

Les mêmes commodités (bouton « Obtenir une clé », contrôle de forme) sont disponibles dans ⚙️ Réglages pour les trois services.

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
  cle_api.dart           obtention et contrôle de forme des clés API
  exemple.dart           la khoutba de démonstration, déjà traitée
  import_media.dart      import d'un audio/vidéo depuis Fichiers ou la galerie
  version.dart           version affichée dans les réglages (repère de mise à jour)
  extraction_audio.dart  isole la piste sonore d'une vidéo (code natif iOS/Android)
  modeles.dart           structures de données
  theme.dart             couleurs, styles (clair/sombre, texte arabe)
  ecrans/                bienvenue, accueil, détail, réglages
test/khoutba_test.dart   63 tests (modèles Gemini, JSON, statuts, formats, découpage,
                         extraction audio, espace disque, reprises, clés,
                         bienvenue, exemple, réécoute, citations, affichage)
```

Le modèle Gemini n'est pas codé en dur : l'app interroge la liste des modèles accessibles avec ta clé et bascule automatiquement si l'un est retiré (même logique que la version web).

## Quand le service d'IA flanche

Google répond parfois « This model is currently experiencing high demand. Please try again later. » (erreur 503). C'est une saturation passagère : l'app **attend et réessaie elle-même** — 3 s, 8 s, 20 s — puis passe au modèle suivant de la liste, souvent moins demandé. L'utilisateur n'a rien à faire.

Sont traités de la même façon : 500, 502, 504, et 429 quand c'est une rafale de requêtes. En revanche un **quota épuisé** porte aussi le code 429 et n'est pas rejoué : insister n'y changerait rien, l'app dit d'attendre la remise à zéro ou de changer de clé. Une clé invalide ou un contenu refusé échouent immédiatement, sans harceler le service.

Les messages sont réécrits en français : « le service est saturé en ce moment — ça vient de chez eux, pas de toi », au lieu de recopier l'anglais de l'API.

## Vérifications faites

- `flutter analyze` : aucun problème
- `flutter test` : 73 tests au vert
- Cibles de compilation contrôlées : Android minSdk 24 (plugins : 21), **iOS 15.0**

> Le plancher iOS est fixé à 15.0 dans `ios/Podfile` et dans les trois configurations du
> projet Xcode. Xcode 26 refuse de compiler en dessous, et chaque greffon apporte sa propre
> cible — 12.0 pour certains. Le `post_install` du Podfile remonte celles qui traînent, sans
> jamais abaisser celles qui exigent davantage. Le Podfile est suivi par git précisément pour
> que ce réglage ne se reperde pas au prochain `pod install`.

**Non vérifié dans l'environnement de développement** : la compilation finale, qui demande Xcode (Mac) ou le SDK Android. Le code Swift (`ios/Runner/ExtractionAudio.swift`) et Kotlin (`android/…/ExtractionAudio.kt`) de l'extraction audio n'y a donc jamais été compilé — seul son contrat côté Dart est couvert par les tests. La compilation est vérifiée par GitHub à chaque envoi de code — voir `.github/workflows/compilation.yml` : analyse, tests, APK Android et compilation iOS. L'APK produit est téléchargeable dans l'onglet **Actions** du dépôt (section *Artifacts*) et s'installe directement sur un téléphone Android.
