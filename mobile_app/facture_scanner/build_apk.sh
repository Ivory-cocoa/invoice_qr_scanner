#!/usr/bin/env bash
#
# build_apk.sh — Reconstruit l'APK release de l'application « Facture Scanner ».
#
# Étapes :
#   1. Vérifie que la configuration pointe bien vers la PRODUCTION
#      (https://odoo.ivorycocoa.ci).
#   2. Récupère les dépendances (flutter pub get).
#   3. Analyse statique (flutter analyze) — bloque sur erreur.
#   4. Tests unitaires (flutter test) — bloque sur échec.
#   5. Construit l'APK release (flutter build apk --release).
#   6. Copie l'APK horodaté dans ./dist/ et affiche le chemin + la taille.
#
# Usage :
#   ./build_apk.sh              # build complet (analyse + tests + APK)
#   ./build_apk.sh --skip-tests # saute analyse + tests (build rapide)
#
set -euo pipefail

# Racine du projet Flutter = dossier de ce script.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

SKIP_TESTS=0
if [[ "${1:-}" == "--skip-tests" ]]; then
  SKIP_TESTS=1
fi

log()  { printf '\033[1;34m[build]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[ ok ]\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; exit 1; }

# --- 0. Prérequis --------------------------------------------------------------
command -v flutter >/dev/null 2>&1 || fail "flutter introuvable dans le PATH."

# --- 1. Vérification de la configuration production ----------------------------
ENV_FILE="lib/core/config/environment.dart"
[[ -f "$ENV_FILE" ]] || fail "Configuration introuvable : $ENV_FILE"

if grep -q "currentEnvironment = Environment.production" "$ENV_FILE"; then
  ok "Configuration = PRODUCTION (https://odoo.ivorycocoa.ci)."
else
  CURRENT_ENV="$(grep -oE "currentEnvironment = Environment\.[a-zA-Z]+" "$ENV_FILE" || true)"
  fail "Environnement non-production détecté : ${CURRENT_ENV:-inconnu}. \
Modifier $ENV_FILE avant de builder pour la production."
fi

# --- 2. Dépendances ------------------------------------------------------------
log "Récupération des dépendances (flutter pub get)…"
flutter pub get
ok "Dépendances à jour."

# --- 3. Analyse statique -------------------------------------------------------
if [[ "$SKIP_TESTS" -eq 0 ]]; then
  log "Analyse statique (flutter analyze)…"
  # On échoue uniquement sur les ERREURS, pas sur les infos/warnings de lint.
  if ! flutter analyze 2>&1 | tee /tmp/facture_scanner_analyze.log | grep -qE "error •"; then
    ok "Aucune erreur d'analyse."
  else
    grep -E "error •" /tmp/facture_scanner_analyze.log || true
    fail "Des erreurs d'analyse ont été détectées (voir ci-dessus)."
  fi

  # --- 4. Tests unitaires ------------------------------------------------------
  log "Tests unitaires (flutter test)…"
  flutter test
  ok "Tous les tests unitaires passent."
else
  log "Analyse et tests ignorés (--skip-tests)."
fi

# --- 5. Build APK release ------------------------------------------------------
log "Construction de l'APK release…"
flutter build apk --release
APK_SRC="build/app/outputs/flutter-apk/app-release.apk"
[[ -f "$APK_SRC" ]] || fail "APK introuvable après le build : $APK_SRC"

# --- 6. Copie horodatée --------------------------------------------------------
mkdir -p dist
STAMP="$(date +%Y%m%d_%H%M%S)"
APK_DST="dist/facture_scanner_prod_${STAMP}.apk"
cp "$APK_SRC" "$APK_DST"

SIZE="$(du -h "$APK_DST" | cut -f1)"
ok "APK généré : $APK_DST ($SIZE)"
ok "APK source : $APK_SRC"
log "Terminé."
