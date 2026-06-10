#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# verify_prod_api.sh — Teste l'API invoice_qr_scanner sur la production.
#
# Vérifie, dans l'ordre :
#   1. Odoo répond et résout bien UNE base (pas de redirection vers le sélecteur)
#   2. L'endpoint public /health renvoie 200 + JSON (routes du module montées)
#   3. Le login mobile /auth/login fonctionne (si identifiants fournis)
#
# Usage :
#   ./verify_prod_api.sh                       # health + résolution DB
#   ./verify_prod_api.sh user@exemple.ci 'MotDePasse'   # + test login
#
# Variables d'env optionnelles :
#   BASE_URL  (défaut: https://odoo.ivorycocoa.ci)
# ──────────────────────────────────────────────────────────────────────────────
set -u

BASE_URL="${BASE_URL:-https://odoo.ivorycocoa.ci}"
LOGIN="${1:-}"
PASSWORD="${2:-}"
TIMEOUT=20

GREEN=$'\033[0;32m'; RED=$'\033[0;31m'; YEL=$'\033[0;33m'; NC=$'\033[0m'
ok()   { echo "${GREEN}[OK]${NC}  $*"; }
ko()   { echo "${RED}[KO]${NC}  $*"; }
warn() { echo "${YEL}[!!]${NC}  $*"; }

fail=0

echo "════════════════════════════════════════════════════════════════"
echo " Vérification API production : $BASE_URL"
echo "════════════════════════════════════════════════════════════════"

# 1. Résolution de base de données -------------------------------------------
echo "--- [1] Résolution de la base de données (/web/login) ---"
login_hdr="$(curl -s -i -m "$TIMEOUT" "$BASE_URL/web/login" 2>/dev/null)"
http_code="$(printf '%s' "$login_hdr" | head -1 | awk '{print $2}')"
location="$(printf '%s' "$login_hdr" | grep -i '^location:' | tr -d '\r')"
if printf '%s' "$location" | grep -qi 'database/selector'; then
  ko "Odoo redirige vers le SÉLECTEUR de bases ($http_code) → le db-filter ne résout AUCUNE base."
  echo "      $location"
  echo "      => Corriger --db-filter / -d dans docker-compose.prod.yml (nom réel de la base)."
  fail=1
elif [ "$http_code" = "200" ]; then
  ok "Page de login servie (200) : une base est bien résolue."
else
  warn "Réponse inattendue sur /web/login : HTTP $http_code"
fi

# 2. Endpoint /health (public, sans auth) ------------------------------------
echo "--- [2] Endpoint public /health ---"
health_url="$BASE_URL/api/v1/invoice-scanner/health"
health_code="$(curl -s -o /tmp/_health_body -w '%{http_code}' -m "$TIMEOUT" "$health_url" 2>/dev/null)"
health_body="$(cat /tmp/_health_body 2>/dev/null)"
if [ "$health_code" = "200" ] && printf '%s' "$health_body" | grep -q '"status"'; then
  ok "Routes du module montées → $health_body"
else
  ko "/health renvoie HTTP $health_code (attendu 200 + JSON)."
  if printf '%s' "$health_body" | grep -qi '404 Not Found'; then
    echo "      => 404 Werkzeug : la base n'est pas résolue (voir [1]) OU le module"
    echo "         invoice_qr_scanner n'est pas installé sur la base résolue."
  fi
  fail=1
fi
rm -f /tmp/_health_body

# 3. Login mobile (optionnel) ------------------------------------------------
if [ -n "$LOGIN" ] && [ -n "$PASSWORD" ]; then
  echo "--- [3] Login mobile /auth/login (utilisateur: $LOGIN) ---"
  login_url="$BASE_URL/api/v1/invoice-scanner/auth/login"
  payload="$(printf '{"login":"%s","password":"%s"}' "$LOGIN" "$PASSWORD")"
  login_code="$(curl -s -o /tmp/_login_body -w '%{http_code}' -m "$TIMEOUT" \
    -X POST "$login_url" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json' \
    -d "$payload" 2>/dev/null)"
  login_body="$(cat /tmp/_login_body 2>/dev/null)"
  if [ "$login_code" = "200" ] && printf '%s' "$login_body" | grep -q '"token"'; then
    ok "Login réussi : token reçu, rôle = $(printf '%s' "$login_body" | grep -oE '"role"[^,]*' | head -1)"
  elif printf '%s' "$login_body" | grep -q '"success": *false'; then
    warn "API joignable mais login refusé (HTTP $login_code) : $(printf '%s' "$login_body" | head -c 200)"
    echo "      => Identifiants incorrects ou utilisateur sans rôle scanner (groupes)."
  else
    ko "Login en échec (HTTP $login_code) : $(printf '%s' "$login_body" | head -c 200)"
    fail=1
  fi
  rm -f /tmp/_login_body
else
  echo "--- [3] Login mobile : ignoré (passer login + mot de passe en arguments) ---"
fi

echo "════════════════════════════════════════════════════════════════"
if [ "$fail" -eq 0 ]; then
  ok "Tout est vert : l'API de production est opérationnelle."
else
  ko "Des problèmes subsistent (voir ci-dessus)."
fi
echo "════════════════════════════════════════════════════════════════"
exit "$fail"
