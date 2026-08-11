#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Build de la PWA « Facture Scanner », servie par Odoo sur /facture.
#
# Destinée aux utilisateurs sans téléphone Android (iPhone en particulier) :
# profils Gestionnaire OT et Traiteur. La sortie est copiée dans
# invoice_qr_scanner/static/pwa/ ; Odoo sert nativement /<module>/static/*,
# et le contrôleur /facture redirige vers l'index.
#
# ⚠️ La caméra (scan QR) exige un contexte sécurisé : la PWA n'est utilisable
#    qu'en HTTPS (https://odoo.ivorycocoa.ci) ou sur localhost. En HTTP simple,
#    le navigateur refuse l'accès à la caméra — la saisie manuelle reste
#    possible, mais le scan non.
#
# Usage :
#   ./build_web.sh            # build prod (même origine → pas de CORS)
#   ./build_web.sh --clean    # flutter clean avant le build
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"

# Servie sous /invoice_qr_scanner/static/pwa/ → base-href correspondante.
BASE_HREF="/invoice_qr_scanner/static/pwa/"
OUT="../../static/pwa"

if [[ "${1:-}" == "--clean" ]]; then
  flutter clean
fi

flutter pub get

# BASE_URL vide = MÊME ORIGINE : la PWA étant servie par Odoo, les appels
# /api/... visent le même hôte → aucun problème CORS, et la même build
# fonctionne en dev comme en production.
flutter build web --release \
  --base-href "$BASE_HREF" \
  --dart-define=BASE_URL=

rm -rf "$OUT"
mkdir -p "$OUT"
cp -R build/web/. "$OUT"/

echo
echo "── PWA construite ✅"
echo "   Sortie : invoice_qr_scanner/static/pwa/"
echo "   URL    : <base>/facture"
echo
echo "   Installation sur iPhone : ouvrir l'URL dans Safari,"
echo "   puis Partager → « Sur l'écran d'accueil »."
