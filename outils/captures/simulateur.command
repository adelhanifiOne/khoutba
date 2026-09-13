#!/bin/bash
# Prend les captures d'écran de l'App Store depuis le simulateur iOS.
#
# Pourquoi le simulateur plutôt qu'un vrai iPhone : il donne les dimensions
# exactes qu'Apple exige (1320×2868 pour la 6,9"), une barre d'état propre —
# 9:41, batterie pleine, pas de notification — et aucune donnée personnelle à
# l'écran. C'est la façon normale de produire ces images.
#
# Double-clique ce fichier, ou : cd outils/captures && ./simulateur.command

set -uo pipefail
cd "$(dirname "$0")" || exit 1
NATIF="../../native"

vert=$'\033[0;32m'; rouge=$'\033[0;31m'; jaune=$'\033[0;33m'; gras=$'\033[1m'; fin=$'\033[0m'
ok()     { echo "${vert}✓${fin} $1"; }
info()   { echo "${jaune}→${fin} $1"; }
erreur() { echo "${rouge}✗${fin} $1"; }
titre()  { echo; echo "${gras}$1${fin}"; }

pause_finale() { echo; echo "Appuie sur Entrée pour fermer."; read -r _; }
echec() { echo; erreur "$1"; [ $# -gt 1 ] && { echo; echo "$2"; }; pause_finale; exit 1; }

# Les noms de modèles changent à chaque version d'iOS — « iPhone 16 Pro Max »
# hier, « iPhone 17 Pro Max » aujourd'hui. Les coder en dur condamne le script
# à tomber en panne au prochain Xcode : on cherche donc par motif, du plus
# grand écran au plus petit.
#
# Le modèle exact importe peu : generer.js redimensionne de toute façon vers
# les formats des stores. Il ne joue que sur ce qui tient à l'écran.
PREFERENCES=("Pro Max" "Plus" "Pro" "iPhone")

ECRANS=(
  "1|Accueil — le gros bouton micro et la liste"
  "2|Fiche ouverte, onglet Résumé"
  "3|Le même, défilé jusqu'aux versets et hadiths cités"
  "4|Onglet Traduction"
  "5|Onglet النص العربي"
  "6|Écran de bienvenue (⚙️ ne sert pas : voir plus bas)"
)

echo "${gras}📸 Khoutba — captures depuis le simulateur${fin}"

# ------------------------------------------------------------------ 1. le Mac

titre "1. Vérifications"

[ "$(uname)" = "Darwin" ] || echec "Ce script demande un Mac." \
  "Le simulateur iOS n'existe que sur macOS."
xcrun simctl help >/dev/null 2>&1 || echec "Xcode n'est pas installé ou pas sélectionné." \
  "Installe Xcode, ouvre-le une fois, puis relance."
ok "Xcode présent"

if ! command -v flutter >/dev/null 2>&1; then
  for essai in "$HOME/flutter/bin" "/opt/homebrew/bin" "/usr/local/bin"; do
    [ -x "$essai/flutter" ] && export PATH="$PATH:$essai" && break
  done
fi
command -v flutter >/dev/null 2>&1 || echec "Flutter introuvable." \
  "Lance d'abord native/installer_iphone.command, qui l'installe."
ok "Flutter présent"

# ------------------------------------------------------------ 2. le simulateur

titre "2. Simulateur"

# « UDID|Nom » pour chaque iPhone déjà présent.
iphones=$(xcrun simctl list devices available \
  | sed -n 's/^[[:space:]]*\(iPhone [^(]*[^ (]\) (\([0-9A-F-]\{36\}\)).*/\2|\1/p')

choisi=""
for motif in "${PREFERENCES[@]}"; do
  choisi=$(echo "$iphones" | grep -i "$motif" | tail -1)
  [ -n "$choisi" ] && break
done

# Rien d'installé : le runtime peut être là sans qu'aucun appareil n'ait été
# créé — cas courant sur un Mac neuf. On en fabrique un.
if [ -z "$choisi" ]; then
  info "Aucun iPhone dans tes simulateurs, création…"
  type=$(xcrun simctl list devicetypes \
    | sed -n 's/^\(iPhone .*\) (\(com\.apple\.CoreSimulator\.SimDeviceType\.[^)]*\))$/\2|\1/p' \
    | grep -i "Pro Max" | tail -1 | cut -d'|' -f1)
  runtime=$(xcrun simctl list runtimes \
    | sed -n 's/^iOS .* - \(com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]*\)$/\1/p' | tail -1)
  [ -n "$type" ] && [ -n "$runtime" ] || echec \
    "Aucun runtime iOS installé." \
"Xcode → Settings → Components → installe « iOS Simulator », puis relance.
Si le runtime est déjà là, ouvre Window → Devices and Simulators et ajoute
n'importe quel iPhone : le script saura le trouver."
  nouveau=$(xcrun simctl create "Khoutba captures" "$type" "$runtime") || echec \
    "Création du simulateur impossible."
  choisi="$nouveau|Khoutba captures"
fi

udid="${choisi%%|*}"
appareil="${choisi#*|}"
ok "Appareil : $appareil"
xcrun simctl boot "$udid" 2>/dev/null
open -a Simulator
info "Démarrage du simulateur…"
until [ "$(xcrun simctl list devices | grep "$udid" | grep -c Booted)" -eq 1 ]; do sleep 1; done

# Barre d'état figée : 9:41, réseau plein, batterie à 100 %, aucune notification.
# Sans ça, l'heure et la batterie réelles se retrouvent sur les images publiées.
xcrun simctl status_bar "$udid" override \
  --time "9:41" --batteryState charged --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --wifiMode active --wifiBars 3 2>/dev/null
ok "Barre d'état figée sur 9:41"

# ------------------------------------------------------------ 3. l'application

titre "3. Installation"
info "Compilation pour le simulateur (quelques minutes la première fois)…"
( cd "$NATIF" && flutter build ios --simulator --debug ) || echec "La compilation a échoué."

app=$(find "$NATIF/build/ios/iphonesimulator" -maxdepth 1 -name "*.app" | head -1)
[ -n "$app" ] || echec "Application compilée introuvable."

# Désinstaller d'abord : l'écran de bienvenue et la khoutba d'exemple ne se
# montrent qu'au tout premier lancement.
xcrun simctl uninstall "$udid" com.adelhanifi.khoutba 2>/dev/null
xcrun simctl install "$udid" "$app" || echec "Installation dans le simulateur impossible."
xcrun simctl launch "$udid" com.adelhanifi.khoutba >/dev/null
ok "Khoutba lancée"

# --------------------------------------------------------------- 4. les prises

mkdir -p brutes
titre "4. Les six captures"
cat <<'AIDE'
Dans le simulateur, appuie sur « Voir un exemple » : une khoutba déjà traitée
s'ouvre, avec tout le contenu nécessaire. Aucune clé, aucune donnée réelle.

Pour chaque écran : place-toi dessus, reviens ici, appuie sur Entrée.
Entrée sans rien faire passe l'écran ; tu pourras le reprendre plus tard.
AIDE

for e in "${ECRANS[@]}"; do
  n="${e%%|*}"; libelle="${e#*|}"
  echo
  echo "  ${gras}$n/6${fin} — $libelle"
  read -r -p "     Entrée pour capturer (s = sauter) : " reponse
  [ "$reponse" = "s" ] && { info "sautée"; continue; }
  if xcrun simctl io "$udid" screenshot "brutes/$n.png" 2>/dev/null; then
    dims=$(sips -g pixelWidth -g pixelHeight "brutes/$n.png" 2>/dev/null \
      | awk '/pixelWidth/{l=$2} /pixelHeight/{h=$2} END{print l"×"h}')
    ok "brutes/$n.png ($dims — redimensionnée à l'habillage)"
  else
    erreur "capture impossible"
  fi
done

# L'écran de bienvenue ne revient qu'après une réinstallation : on le reprend
# à la fin plutôt que de casser la série au début.
if [ ! -f brutes/6.png ]; then
  echo
  read -r -p "Reprendre l'écran de bienvenue ? Réinstalle l'app. [O/n] " r
  if [[ "${r:-O}" =~ ^[OoYy]?$ ]]; then
    xcrun simctl uninstall "$udid" com.adelhanifi.khoutba 2>/dev/null
    xcrun simctl install "$udid" "$app" >/dev/null
    xcrun simctl launch "$udid" com.adelhanifi.khoutba >/dev/null
    read -r -p "     Entrée quand l'écran de bienvenue est affiché : " _
    xcrun simctl io "$udid" screenshot "brutes/6.png" 2>/dev/null && ok "brutes/6.png"
  fi
fi

xcrun simctl status_bar "$udid" clear 2>/dev/null

# ------------------------------------------------------------- 5. l'habillage

titre "5. Habillage"
if [ -d node_modules/playwright ] || [ -n "${NODE_PATH:-}" ]; then
  node generer.js
else
  info "Playwright absent : installation…"
  npm install playwright >/dev/null 2>&1 && node generer.js \
    || info "Installe-le à la main (npm install playwright), puis : node generer.js"
fi

echo
ok "Terminé. Les images sont dans store/captures/"
pause_finale
