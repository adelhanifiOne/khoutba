#!/bin/bash
# Télécharge la police Cairo (SIL Open Font License), utilisée pour le mot
# latin du logo. Le mot arabe, lui, vient du motif d'AdhanBox (motif-adhan.png).
# Les fichiers ne sont pas versionnés : ce script les récupère à la demande.
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p polices
UA="Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/120 Safari/537.36"

curl -fsSL -H "User-Agent: $UA" \
  "https://fonts.googleapis.com/css2?family=Cairo:wght@700&display=swap" \
  | sed -n 's/.*src: url(\([^)]*\)).*/\1/p' > /tmp/khoutba_polices.txt

n=0
while read -r url; do
  n=$((n + 1))
  curl -fsSL -o "polices/cairo_$n.woff2" "$url"
done < /tmp/khoutba_polices.txt
rm -f /tmp/khoutba_polices.txt

# cairo_3 = jeu latin (ordre renvoyé par Google Fonts) — le seul utilisé
if [ ! -s polices/cairo_3.woff2 ]; then
  echo "✗ Téléchargement incomplet — vérifie ta connexion." >&2
  exit 1
fi
echo "✓ Police Cairo récupérée ($n fichiers)"
