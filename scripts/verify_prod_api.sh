#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# verify_prod_api.sh — Teste l'API invoice_qr_scanner sur la production.
#
# Vérifie, dans l'ordre :
#   1. Odoo répond et résout bien UNE base (pas de redirection vers le sélecteur)
#   2. L'endpoint public /health renvoie 200 + JSON (routes du module montées)
#   3. L'envoi de code /auth/request-otp répond (si un identifiant est fourni)
#
# La connexion mobile se fait par code à usage unique envoyé par email : ce
# script ne peut donc pas aller jusqu'au token sans intervention humaine. Il
# vérifie que l'endpoint d'envoi répond, et — si l'identifiant existe — qu'un
# email part réellement (à confirmer dans la boîte de réception).
#
# Usage :
#   ./verify_prod_api.sh                       # health + résolution DB
#   ./verify_prod_api.sh user@exemple.ci       # + test d'envoi de code
#
# Variables d'env optionnelles :
#   BASE_URL  (défaut: https://odoo.ivorycocoa.ci)
# ──────────────────────────────────────────────────────────────────────────────
set -u

BASE_URL="${BASE_URL:-https://odoo.ivorycocoa.ci}"
LOGIN="${1:-}"
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

# 3. Envoi de code de connexion (optionnel) -----------------------------------
if [ -n "$LOGIN" ]; then
  echo "--- [3] Envoi de code /auth/request-otp (utilisateur: $LOGIN) ---"
  otp_url="$BASE_URL/api/v1/invoice-scanner/auth/request-otp"
  payload="$(printf '{"login":"%s"}' "$LOGIN")"
  otp_code="$(curl -s -o /tmp/_otp_body -w '%{http_code}' -m "$TIMEOUT" \
    -X POST "$otp_url" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json' \
    -d "$payload" 2>/dev/null)"
  otp_body="$(cat /tmp/_otp_body 2>/dev/null)"
  if [ "$otp_code" = "200" ]; then
    ok "Endpoint d'envoi opérationnel (HTTP 200)."
    echo "      => La réponse est identique que le compte existe ou non"
    echo "         (anti-énumération) : vérifiez la boîte mail de $LOGIN pour"
    echo "         confirmer que le code est bien parti."
  elif printf '%s' "$otp_body" | grep -q 'OTP_SEND_FAILED'; then
    ko "Le compte existe mais l'email n'a PAS pu être envoyé (SMTP)."
    echo "      => Vérifiez le serveur de courrier sortant et mail.default.from."
    fail=1
  elif printf '%s' "$otp_body" | grep -q 'OTP_TOO_SOON'; then
    warn "Un code vient déjà d'être envoyé pour ce compte (anti-spam 60 s)."
  elif printf '%s' "$otp_body" | grep -q 'TOO_MANY_ATTEMPTS'; then
    warn "Quota de demandes atteint (HTTP $otp_code) : réessayez plus tard."
  else
    ko "Envoi de code en échec (HTTP $otp_code) : $(printf '%s' "$otp_body" | head -c 200)"
    fail=1
  fi
  rm -f /tmp/_otp_body
else
  echo "--- [3] Envoi de code : ignoré (passer un identifiant en argument) ---"
fi

echo "════════════════════════════════════════════════════════════════"
if [ "$fail" -eq 0 ]; then
  ok "Tout est vert : l'API de production est opérationnelle."
else
  ko "Des problèmes subsistent (voir ci-dessus)."
fi
echo "════════════════════════════════════════════════════════════════"
exit "$fail"
