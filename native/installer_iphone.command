#!/bin/bash
# Installe Khoutba sur un iPhone branché en USB.
# Double-clique ce fichier depuis le Finder, ou lance-le dans le Terminal.
#
# Le script vérifie tout ce qu'il faut, corrige ce qu'il peut, et explique
# précisément quoi faire quand une étape demande une action de ta part.

set -uo pipefail
cd "$(dirname "$0")" || exit 1

vert=$'\033[0;32m'; rouge=$'\033[0;31m'; jaune=$'\033[0;33m'; gras=$'\033[1m'; fin=$'\033[0m'
ok()      { echo "${vert}✓${fin} $1"; }
info()    { echo "${jaune}→${fin} $1"; }
erreur()  { echo "${rouge}✗${fin} $1"; }
titre()   { echo; echo "${gras}$1${fin}"; }

pause_finale() {
  echo
  echo "Appuie sur Entrée pour fermer cette fenêtre."
  read -r _
}

echec() {
  echo
  erreur "$1"
  [ $# -gt 1 ] && { echo; echo "$2"; }
  pause_finale
  exit 1
}

echo "${gras}🕌 Khoutba — installation sur iPhone${fin}"

# --------------------------------------------------------------- 1. la machine

titre "1. Vérifications"

[ "$(uname)" = "Darwin" ] || echec \
  "Ce script doit être lancé sur un Mac." \
  "La compilation d'une app iOS n'est possible que sur macOS (contrainte d'Apple)."
ok "macOS détecté"

if ! xcode-select -p >/dev/null 2>&1; then
  echec "Xcode n'est pas installé." \
"Installe Xcode depuis l'App Store (gratuit, ~7 Go), ouvre-le une fois pour
accepter la licence, puis relance ce script."
fi
ok "Xcode installé"

# Les outils en ligne de commande seuls ne suffisent pas pour compiler une app.
if [[ "$(xcode-select -p)" == *"CommandLineTools"* ]]; then
  info "Xcode complet non sélectionné, correction…"
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer 2>/dev/null || echec \
    "Impossible de sélectionner Xcode." \
    "Lance : sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  ok "Xcode sélectionné"
fi

sudo xcodebuild -license accept >/dev/null 2>&1 || true

# ----------------------------------------------------------------- 2. Flutter

titre "2. Flutter"

if ! command -v flutter >/dev/null 2>&1; then
  for essai in "$HOME/flutter/bin" "/opt/homebrew/bin" "/usr/local/bin"; do
    [ -x "$essai/flutter" ] && export PATH="$PATH:$essai" && break
  done
fi

if ! command -v flutter >/dev/null 2>&1; then
  info "Flutter n'est pas installé — installation dans ~/flutter (≈ 1 Go)…"
  git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$HOME/flutter" \
    || echec "Le téléchargement de Flutter a échoué." "Vérifie ta connexion internet."
  export PATH="$PATH:$HOME/flutter/bin"
  # Rendre flutter disponible dans les prochains terminaux
  for profil in "$HOME/.zshrc" "$HOME/.bash_profile"; do
    [ -f "$profil" ] && ! grep -q 'flutter/bin' "$profil" \
      && echo 'export PATH="$PATH:$HOME/flutter/bin"' >> "$profil"
  done
  ok "Flutter installé"
else
  ok "Flutter présent ($(flutter --version 2>/dev/null | head -1))"
fi

if ! command -v pod >/dev/null 2>&1; then
  info "Installation de CocoaPods (gestionnaire de bibliothèques iOS)…"
  if command -v brew >/dev/null 2>&1; then
    brew install cocoapods >/dev/null 2>&1 || true
  fi
  command -v pod >/dev/null 2>&1 || sudo gem install cocoapods || echec \
    "Installation de CocoaPods impossible." \
    "Essaie manuellement : sudo gem install cocoapods"
  ok "CocoaPods installé"
else
  ok "CocoaPods présent"
fi

titre "3. Préparation du projet"

sortie_pub=$(flutter pub get 2>&1)
if [ $? -ne 0 ]; then
  # Cause la plus fréquente : le Flutter local est plus ancien que ce que
  # demandent les dépendances. On propose la mise à jour plutôt que d'abandonner.
  if echo "$sortie_pub" | grep -qi "version solving failed\|requires SDK version"; then
    echo "$sortie_pub" | grep -i "requires SDK version\|current Dart SDK" | head -2
    info "Ton Flutter est trop ancien pour les dépendances du projet."
    read -r -p "Le mettre à jour maintenant (flutter upgrade) ? [O/n] " reponse
    if [[ "${reponse:-O}" =~ ^[OoYy]?$ ]]; then
      flutter upgrade --force || echec "La mise à jour de Flutter a échoué."
      flutter pub get >/dev/null || echec "Échec de « flutter pub get » après mise à jour."
    else
      echec "Dépendances non installées." "Relance le script après « flutter upgrade »."
    fi
  else
    echo "$sortie_pub" | tail -15
    echec "Échec de « flutter pub get »."
  fi
fi
ok "Dépendances récupérées"

# ------------------------------------------------- 4. certificat de signature

titre "4. Signature"

identites=$(security find-identity -v -p codesigning 2>/dev/null | grep -c "Apple Develop" || true)
if [ "${identites:-0}" -eq 0 ]; then
  echo
  erreur "Aucun certificat de développeur Apple sur ce Mac."
  cat <<'AIDE'

C'est une étape unique, à faire dans Xcode (5 minutes) :

  1. Xcode va s'ouvrir sur le projet
  2. Menu Xcode → Settings… → Accounts → « + » → Apple ID
     (ton compte Apple habituel suffit, aucun paiement)
  3. Dans la colonne de gauche, clique sur « Runner »
     puis l'onglet « Signing & Capabilities »
  4. Coche « Automatically manage signing »
  5. Dans « Team », choisis ton nom (Personal Team)
  6. Ferme Xcode et relance ce script

AIDE
  read -r -p "Ouvrir Xcode maintenant ? [O/n] " reponse
  [[ "${reponse:-O}" =~ ^[OoYy]?$ ]] && open ios/Runner.xcworkspace
  pause_finale
  exit 0
fi
ok "Certificat de développeur trouvé"

# ------------------------------------------------------------- 5. l'iPhone

titre "5. iPhone"

appareils=$(flutter devices --machine 2>/dev/null)
if ! echo "$appareils" | grep -q '"targetPlatform": *"ios"'; then
  echo
  erreur "Aucun iPhone détecté."
  cat <<'AIDE'

Vérifie que :
  • l'iPhone est branché en USB (un câble de charge simple suffit)
  • tu as répondu « Se fier » à la question affichée sur l'iPhone
  • l'iPhone est déverrouillé
  • le mode développeur est activé :
    Réglages → Confidentialité et sécurité → Mode développeur → activer,
    puis redémarrer l'iPhone (nécessaire depuis iOS 16)

Puis relance ce script.
AIDE
  pause_finale
  exit 1
fi

# On privilégie un iPhone réel : un simulateur ouvert ne doit pas être choisi.
lignes=$(echo "$appareils" | tr '{' '\n' | grep '"targetPlatform": *"ios"')
physique=$(echo "$lignes" | grep '"emulator": *false' | head -1)
choisi=${physique:-$(echo "$lignes" | head -1)}

identifiant=$(echo "$choisi" | sed -n 's/.*"id": *"\([^"]*\)".*/\1/p')
nom=$(echo "$choisi" | sed -n 's/.*"name": *"\([^"]*\)".*/\1/p')

if [ -z "$physique" ]; then
  info "Seul un simulateur est disponible — l'app y sera installée."
  info "Pour l'avoir sur ton vrai iPhone, branche-le en USB et relance."
fi
ok "Appareil : ${nom:-inconnu}"

# --------------------------------------------------------- 6. compilation

titre "6. Compilation et installation"
info "La première compilation prend 5 à 15 minutes. Laisse l'iPhone déverrouillé."
echo

if flutter run --release -d "$identifiant"; then
  echo
  ok "Khoutba est installée sur ton iPhone 🎉"
else
  code=$?
  echo
  erreur "La compilation a échoué (code $code)."
  cat <<'AIDE'

Les deux causes les plus fréquentes :

  • « Bundle identifier is not available » ou « ...is already in use »
    → l'identifiant com.adelhanifi.khoutba est déjà pris chez Apple.
      Ouvre ios/Runner.xcworkspace dans Xcode, onglet Signing & Capabilities,
      et remplace le Bundle Identifier par un identifiant à toi,
      par exemple com.tonprenom.khoutba2026 — puis relance ce script.

  • « Unable to install » / « The developer is not trusted »
    → sur l'iPhone : Réglages → Général → VPN et gestion de l'appareil
      → sélectionne ton compte → « Faire confiance ».

Copie-colle le message d'erreur complet ci-dessus si tu veux de l'aide.
AIDE
  pause_finale
  exit 1
fi

cat <<'SUITE'

Dernière étape sur l'iPhone, la première fois :
  Réglages → Général → VPN et gestion de l'appareil
  → ton compte → « Faire confiance »

Puis ouvre Khoutba, va dans ⚙️ Réglages et colle ta clé Gemini.

Bon vendredi 🕌
SUITE
pause_finale
