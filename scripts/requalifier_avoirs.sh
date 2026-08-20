#!/usr/bin/env bash
#
# requalifier_avoirs.sh — Requalification des avoirs DGI enregistrés à tort en
#                         factures d'achat (module invoice_qr_scanner ≥ 17.0.1.5.0).
#
# ─────────────────────────────────────────────────────────────────────────────
# CE QUE FAIT CE SCRIPT
#
#   1. Vérifie que les conteneurs tournent et que le module est à la bonne
#      version (sans quoi `repair_refund_documents` n'existe pas).
#   2. Interroge la plateforme DGI scan par scan pour établir la NATURE réelle
#      de chaque document — aucune requalification n'est faite sur une
#      heuristique.
#   3. En mode simulation (LE DÉFAUT) : n'écrit rien, produit un rapport
#      lisible et un CSV pour la comptabilité.
#   4. En mode application (`--apply`) : sauvegarde la base, demande
#      confirmation, puis extourne la facture erronée, crée l'avoir, requalifie
#      le scan et inverse les lignes de coût d'OT concernées.
#
# ─────────────────────────────────────────────────────────────────────────────
# USAGE
#
#   ./requalifier_avoirs.sh                          # SIMULATION (défaut)
#   ./requalifier_avoirs.sh --apply                  # application
#   ./requalifier_avoirs.sh --apply --posting-date 2026-08-31
#   ./requalifier_avoirs.sh --scan-ids 2596,2595     # cibler des scans précis
#   ./requalifier_avoirs.sh --full                   # balayer TOUT le stock
#   ./requalifier_avoirs.sh --check                  # contrôles post-application
#
# Options :
#   --db NOM             Base de données (détectée automatiquement si unique)
#   --container NOM      Conteneur web (défaut : odoo17-web-prod)
#   --db-user NOM        Rôle PostgreSQL pour psql/pg_dump (défaut : odoo)
#   --apply              Écrire réellement. Sans cette option : rien n'est écrit.
#   --posting-date DATE  Imputer la correction sur cette date comptable
#                        (AAAA-MM-JJ). Sans elle, la correction retombe dans la
#                        PÉRIODE D'ORIGINE — voir l'avertissement affiché.
#   --scan-ids A,B,C     Ne traiter que ces scans (identifiants Odoo).
#   --full               Interroger la DGI pour TOUS les scans (long : ~40 min).
#   --no-backup          Ne pas sauvegarder avant application (DÉCONSEILLÉ).
#   --outdir CHEMIN      Où écrire journal, CSV et sauvegarde
#                        (défaut : ./rapports_avoirs à côté du script).
#   --yes                Ne pas demander de confirmation (usage non interactif).
#   --check              N'exécuter que les contrôles SQL post-application.
#   --help               Cette aide.
#
# Sorties : un journal complet et un CSV horodatés dans ./rapports_avoirs/
#
# ─────────────────────────────────────────────────────────────────────────────
# Ce script utilise des constructions propres à bash ([[ ]], tableaux,
# mapfile). Lancé avec `sh` — donc dash sur Debian/Ubuntu — il échoue sur des
# messages incompréhensibles (« [[: not found »). Plutôt que de laisser
# l'utilisateur deviner, on se relance nous-mêmes sous bash.
if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

set -euo pipefail

# ── Réglages par défaut ──────────────────────────────────────────────────────
CONTAINER="odoo17-web-prod"
DB=""
APPLY=0
POSTING_DATE=""
SCAN_IDS=""
ONLY_SUSPECT="True"
DO_BACKUP=1
ASSUME_YES=0
CHECK_ONLY=0
OUTDIR_OPT=""

# Utilisateur employé pour les commandes `psql` / `pg_dump` DANS le conteneur
# de base : l'authentification y est locale, aucun mot de passe n'est requis.
DB_USER="${RQ_DB_USER:-odoo}"

# ⚠️ AUCUN identifiant n'est passé à `odoo shell`. Le conteneur sait déjà
# joindre sa base — c'est ainsi que le serveur tourne. Les imposer en ligne de
# commande, c'est parier sur un mot de passe qu'on ne connaît pas : en
# production, `--db_password=odoo` a produit un « password authentication
# failed » alors que tout était correctement configuré côté conteneur.

ADDONS_PATH="/usr/lib/python3/dist-packages/odoo/addons,/mnt/extra-addons,/mnt/oca-addons"
MIN_VERSION="17.0.1.5.0"

# ── Présentation ─────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
  BLUE=$'\033[0;34m'; CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; NC=$'\033[0m'
else
  RED=""; GREEN=""; YELLOW=""; BLUE=""; CYAN=""; BOLD=""; NC=""
fi

info()  { printf '%s\n' "${CYAN}[·]${NC} $*"; }
ok()    { printf '%s\n' "${GREEN}[✓]${NC} $*"; }
warn()  { printf '%s\n' "${YELLOW}[!]${NC} $*"; }
fail()  { printf '%s\n' "${RED}[✗]${NC} $*" >&2; exit 1; }
title() {
  printf '\n%s\n' "${BOLD}${BLUE}══════════════════════════════════════════════════════════════${NC}"
  printf '%s\n'   "${BOLD}${BLUE}  $*${NC}"
  printf '%s\n\n' "${BOLD}${BLUE}══════════════════════════════════════════════════════════════${NC}"
}

usage() { sed -n '2,50p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

# ── Analyse des arguments ────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --db)            DB="${2:?--db attend un nom de base}"; shift 2 ;;
    --container)     CONTAINER="${2:?--container attend un nom}"; shift 2 ;;
    --apply)         APPLY=1; shift ;;
    --posting-date)  POSTING_DATE="${2:?--posting-date attend AAAA-MM-JJ}"; shift 2 ;;
    --scan-ids)      SCAN_IDS="${2:?--scan-ids attend une liste identifiants}"; shift 2 ;;
    --full)          ONLY_SUSPECT="False"; shift ;;
    --no-backup)     DO_BACKUP=0; shift ;;
    --yes|-y)        ASSUME_YES=1; shift ;;
    --db-user)       DB_USER="${2:?--db-user attend un nom}"; shift 2 ;;
    --outdir)        OUTDIR_OPT="${2:?--outdir attend un chemin}"; shift 2 ;;
    --check)         CHECK_ONLY=1; shift ;;
    --help|-h)       usage ;;
    *)               fail "Option inconnue : $1 (voir --help)" ;;
  esac
done

if [[ -n "$POSTING_DATE" && ! "$POSTING_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
  fail "--posting-date doit être au format AAAA-MM-JJ (reçu : $POSTING_DATE)"
fi
if [[ -n "$SCAN_IDS" && ! "$SCAN_IDS" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
  fail "--scan-ids attend des identifiants numériques séparés par des virgules"
fi

DB_CONTAINER="${CONTAINER/-web-/-db-}"

# ── Contrôles préalables ─────────────────────────────────────────────────────
title "Requalification des avoirs DGI"

command -v docker >/dev/null 2>&1 || fail "docker introuvable."

docker ps --format '{{.Names}}' | grep -qx "$CONTAINER" \
  || fail "Conteneur web « $CONTAINER » non démarré. (Option --container pour en viser un autre.)"
docker ps --format '{{.Names}}' | grep -qx "$DB_CONTAINER" \
  || fail "Conteneur base « $DB_CONTAINER » non démarré."

ok "Conteneurs : $CONTAINER / $DB_CONTAINER"

# Base de données : détectée si une seule base applicative existe.
if [[ -z "$DB" ]]; then
  mapfile -t DBS < <(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -lqtA -F'|' \
                     | cut -d'|' -f1 \
                     | grep -vE '^(postgres|template[01])$' \
                     | grep -v '^$' || true)
  if [[ ${#DBS[@]} -eq 1 ]]; then
    DB="${DBS[0]}"
    info "Base détectée automatiquement : ${BOLD}$DB${NC}"
  else
    printf '%s\n' "${YELLOW}Bases disponibles :${NC}"
    printf '   - %s\n' "${DBS[@]}"
    fail "Plusieurs bases : préciser laquelle avec --db."
  fi
fi

docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB" -c 'SELECT 1' >/dev/null 2>&1 \
  || fail "Base « $DB » injoignable."
ok "Base : $DB"

# Version du module : sans elle, la méthode de requalification n'existe pas.
MODULE_VERSION="$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB" -tAc \
  "SELECT latest_version FROM ir_module_module WHERE name='invoice_qr_scanner' AND state='installed'" \
  2>/dev/null || true)"
[[ -n "$MODULE_VERSION" ]] || fail "Module invoice_qr_scanner non installé sur « $DB »."

lowest="$(printf '%s\n%s\n' "$MIN_VERSION" "$MODULE_VERSION" | sort -V | head -1)"
[[ "$lowest" == "$MIN_VERSION" ]] \
  || fail "Module en $MODULE_VERSION — il faut au moins $MIN_VERSION. Faire le git pull et la mise à jour d'abord."
ok "Module invoice_qr_scanner $MODULE_VERSION"

STAMP="$(date +%Y%m%d_%H%M%S)"
# Journaux, CSV et sauvegarde. Par défaut à côté du script, pour être trouvés
# sans chercher ; `--outdir` permet de les envoyer ailleurs — utile si la
# partition du dépôt est à l'étroit, une sauvegarde pesant plusieurs centaines
# de mégaoctets.
OUTDIR="${OUTDIR_OPT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/rapports_avoirs}"
mkdir -p "$OUTDIR"
LOG="$OUTDIR/requalification_${STAMP}.log"
CSV="$OUTDIR/requalification_${STAMP}.csv"

# ── Mode --check : contrôles seuls ───────────────────────────────────────────
if [[ "$CHECK_ONLY" -eq 1 ]]; then
  title "Contrôles post-application"
  # `-i` indispensable : sans lui, docker ne transmet pas l'entrée standard au
  # conteneur, psql ne reçoit aucune requête et sort en silence avec 0.
  docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB" <<'SQL' | tee -a "$LOG"
\echo '── Pièces portées par les scans de nature AVOIR (attendu : in_refund / posted)'
SELECT m.move_type, m.state, count(*) AS nb, sum(m.amount_total) AS total
  FROM account_move m
  JOIN invoice_scan_record r ON r.invoice_id = m.id
 WHERE r.document_type = 'refund'
 GROUP BY 1, 2;

\echo '── Anciennes factures erronées (attendu : posted / reversed)'
SELECT m.state, m.payment_state, count(*) AS nb
  FROM account_move m
 WHERE m.id IN (SELECT reversed_entry_id FROM account_move
                 WHERE reversed_entry_id IS NOT NULL)
 GROUP BY 1, 2;

\echo '── Répartition des scans par nature'
SELECT document_type, count(*) AS nb,
       sum(amount_ttc)::bigint AS brut,
       sum(amount_signed)::bigint AS net
  FROM invoice_scan_record
 GROUP BY 1;

\echo '── Scans dont la nature reste à confirmer auprès de la DGI'
-- `IS NOT TRUE` et non `= false` : la colonne vaut NULL sur les lignes
-- antérieures au champ, et `= false` les manquerait toutes en silence.
SELECT count(*) AS a_confirmer
  FROM invoice_scan_record
 WHERE document_type_verified IS NOT TRUE AND state IN ('done', 'processed');
SQL
  ok "Contrôles écrits dans $LOG"
  exit 0
fi

# ── Récapitulatif et avertissements ──────────────────────────────────────────
if [[ "$APPLY" -eq 1 ]]; then
  MODE="${RED}${BOLD}APPLICATION (écritures réelles)${NC}"
else
  MODE="${GREEN}SIMULATION (aucune écriture)${NC}"
fi

printf '\n'
printf '  Mode        : %b\n' "$MODE"
printf '  Périmètre   : %s\n' \
  "$( [[ -n "$SCAN_IDS" ]] && echo "scans $SCAN_IDS" \
      || { [[ "$ONLY_SUSPECT" == "False" ]] && echo "TOUS les scans (long)" || echo "scans à référence d'avoir"; } )"
printf '  Imputation  : %s\n' \
  "$( [[ -n "$POSTING_DATE" ]] && echo "$POSTING_DATE" || echo "période d'origine (défaut)" )"
printf '  Journal     : %s\n' "$LOG"
printf '\n'

if [[ "$APPLY" -eq 1 && -z "$POSTING_DATE" ]]; then
  warn "Sans --posting-date, la correction s'impute dans la PÉRIODE D'ORIGINE :"
  warn "l'extourne à la date de la facture erronée, l'avoir à la date du document"
  warn "DGI. Des mois déjà déclarés seront donc modifiés."
  warn "Pour tout imputer sur la période ouverte : --posting-date AAAA-MM-JJ"
  printf '\n'
fi

if [[ "$ONLY_SUSPECT" == "False" ]]; then
  warn "--full interroge la DGI pour CHAQUE scan : comptez ~40 min pour 5 000 scans."
  printf '\n'
fi

confirm() {
  local prompt="$1" expected="$2" answer
  [[ "$ASSUME_YES" -eq 1 ]] && { info "Confirmation automatique (--yes) : $prompt"; return 0; }
  [[ -t 0 ]] || fail "Confirmation requise mais entrée non interactive. Utiliser --yes en connaissance de cause."
  printf '%s' "${YELLOW}${prompt}${NC} "
  read -r answer
  [[ "$answer" == "$expected" ]] || fail "Annulé."
}

# ── Sauvegarde avant écriture ────────────────────────────────────────────────
if [[ "$APPLY" -eq 1 ]]; then
  if [[ "$DO_BACKUP" -eq 1 ]]; then
    DUMP="$OUTDIR/avant_requalification_${DB}_${STAMP}.dump"
    REMOTE_DUMP="/tmp/avant_requalification_${STAMP}.dump"
    info "Sauvegarde de la base avant écriture…"

    # La sauvegarde est écrite DANS le conteneur puis relue par `pg_restore -l`
    # avant d'être rapatriée. Un `pg_dump > fichier` côté hôte peut produire un
    # fichier tronqué (disque plein, tuyau coupé) que seul un contrôle de
    # lisibilité détecte : un filet de sécurité qu'on n'a pas vérifié n'en est
    # pas un.
    docker exec "$DB_CONTAINER" pg_dump -U "$DB_USER" -Fc -f "$REMOTE_DUMP" "$DB" \
      || fail "Sauvegarde échouée — application interrompue."
    docker exec "$DB_CONTAINER" pg_restore -l "$REMOTE_DUMP" >/dev/null 2>&1 \
      || fail "Sauvegarde illisible (tronquée ?) — application interrompue."
    docker cp "$DB_CONTAINER:$REMOTE_DUMP" "$DUMP" \
      || fail "Rapatriement de la sauvegarde échoué — application interrompue."
    docker exec "$DB_CONTAINER" rm -f "$REMOTE_DUMP" || true
    [[ -s "$DUMP" ]] || fail "Sauvegarde vide — application interrompue."
    ok "Sauvegarde vérifiée : $DUMP ($(du -h "$DUMP" | cut -f1))"
    printf '     %s\n' "Restauration : pg_restore -U $DB_USER -d $DB -c '$DUMP'"
  else
    warn "Sauvegarde SAUTÉE (--no-backup). Les écritures comptabilisées ne se"
    warn "défont pas d'un clic : c'est votre seul filet qui disparaît."
    confirm "Confirmer l'absence de sauvegarde en tapant SANS-SAUVEGARDE :" "SANS-SAUVEGARDE"
  fi
  printf '\n'
  confirm "Écrire réellement dans « $DB » ? Tapez APPLIQUER pour continuer :" "APPLIQUER"
fi

# ── Exécution ────────────────────────────────────────────────────────────────
title "Interrogation de la plateforme DGI"
info "Un appel réseau par scan examiné — patientez."

RAW="$(mktemp)"
trap 'rm -f "$RAW"' EXIT

set +e
docker exec -i \
  -e RQ_APPLY="$APPLY" \
  -e RQ_POSTING_DATE="$POSTING_DATE" \
  -e RQ_SCAN_IDS="$SCAN_IDS" \
  -e RQ_ONLY_SUSPECT="$ONLY_SUSPECT" \
  "$CONTAINER" odoo shell \
    -d "$DB" \
    --addons-path="$ADDONS_PATH" \
    --no-http --log-level=warn <<'PYEOF' > "$RAW" 2>&1
import os
import traceback

MARK = '@@RQ@@'          # lignes destinées au script bash
CSV = '@@CSV@@'          # lignes destinées au fichier CSV


def emit(*parts):
    print(MARK + '|'.join(str(p) for p in parts), flush=True)


def csv_row(*parts):
    print(CSV + ';'.join(
        '"%s"' % str(p).replace('"', '""') for p in parts), flush=True)


try:
    apply_it = os.environ.get('RQ_APPLY') == '1'
    posting_date = os.environ.get('RQ_POSTING_DATE') or None
    only_suspect = os.environ.get('RQ_ONLY_SUSPECT', 'True') == 'True'
    raw_ids = os.environ.get('RQ_SCAN_IDS') or ''
    scan_ids = [int(i) for i in raw_ids.split(',') if i.strip()] or None

    res = env['invoice.scan.record'].repair_refund_documents(
        dry_run=not apply_it,
        only_suspect=only_suspect,
        scan_ids=scan_ids,
        posting_date=posting_date,
    )

    if apply_it:
        # Le shell Odoo ne committe pas de lui-même : sans ceci, tout le
        # travail serait perdu à la fermeture — silencieusement.
        env.cr.commit()

    emit('SUMMARY', res['examined'], res['confirmed_invoice'],
         res['already_refund'], res['requalified'], res['blocked'],
         res['unreachable'], res.get('posting_date') or '')

    csv_row('scan', 'numero_dgi', 'fournisseur', 'montant_ttc',
            'piece_erronee', 'etat_piece', 'extourne', 'avoir_cree',
            'facture_origine', 'lignes_ot')
    for c in res['changes']:
        emit('CHANGE', c['scan_reference'], c['invoice_number_dgi'] or '',
             (c['supplier'] or '')[:38], int(c['amount_ttc'] or 0),
             c['move_name'] or '', c.get('refund_move_name') or '',
             len(c['cost_lines']))
        csv_row(c['scan_reference'], c['invoice_number_dgi'] or '',
                c['supplier'] or '', int(c['amount_ttc'] or 0),
                c['move_name'] or '', c['move_state'] or '',
                c.get('reversal_name') or '', c.get('refund_move_name') or '',
                c.get('origin_invoice_number_dgi') or '',
                len(c['cost_lines']))

    for b in res['blocked_details']:
        emit('BLOCKED', b['scan_reference'], b['move_name'] or '',
             ', '.join(b['blockers']))
        csv_row(b['scan_reference'], b['invoice_number_dgi'] or '',
                b['supplier'] or '', int(b['amount_ttc'] or 0),
                b['move_name'] or '', b['move_state'] or '',
                'BLOQUÉ : ' + ', '.join(b['blockers']), '', '',
                len(b['cost_lines']))

    for line in res['cost_lines']:
        emit('COSTLINE', line['scan_reference'], line['ot'],
             int(line['before'] or 0), line['action'])

    emit('DONE', 'OK')
except Exception:
    print(traceback.format_exc(), flush=True)
    emit('DONE', 'ERREUR')
PYEOF
DOCKER_RC=$?
set -e

cp "$RAW" "$LOG"

# ── Restitution ──────────────────────────────────────────────────────────────
grep -a "^@@CSV@@" "$RAW" | sed 's/^@@CSV@@//' > "$CSV" || true

status="$(grep -a "^@@RQ@@DONE|" "$RAW" | tail -1 | cut -d'|' -f2 || true)"
if [[ "$status" != "OK" ]]; then
  printf '\n'
  grep -av "^@@RQ@@\|^@@CSV@@" "$RAW" | tail -30
  fail "Échec de l'exécution (code docker $DOCKER_RC). Journal complet : $LOG"
fi

summary="$(grep -a "^@@RQ@@SUMMARY|" "$RAW" | tail -1 | sed 's/^@@RQ@@SUMMARY|//')"
IFS='|' read -r EXAMINED CONFIRMED ALREADY REQUAL BLOCKED UNREACH USED_DATE <<< "$summary"

title "Résultat"
printf '  Scans examinés                         : %s\n' "$EXAMINED"
printf '  Confirmés FACTURES par la DGI          : %s\n' "$CONFIRMED"
printf '  Déjà enregistrés en avoir              : %s\n' "$ALREADY"
printf '  %sÀ requalifier (avoirs pris pour factures) : %s%s\n' "$BOLD" "$REQUAL" "$NC"
printf '  Bloqués (arbitrage comptable)          : %s\n' "$BLOCKED"
printf '  DGI injoignable                        : %s\n' "$UNREACH"
[[ -n "$USED_DATE" ]] && printf '  Imputation comptable                   : %s\n' "$USED_DATE"

if [[ "$REQUAL" != "0" ]]; then
  printf '\n%s\n' "${BOLD}  Documents concernés${NC}"
  printf '  %-16s %-22s %-30s %14s\n' "SCAN" "N° DGI" "FOURNISSEUR" "MONTANT"
  grep -a "^@@RQ@@CHANGE|" "$RAW" | sed 's/^@@RQ@@CHANGE|//' | while IFS='|' read -r s n f m old new ot; do
    printf '  %-16s %-22s %-30s %14s\n' "$s" "$n" "$f" "$m"
  done
fi

if [[ "$BLOCKED" != "0" ]]; then
  printf '\n%s\n' "${YELLOW}${BOLD}  Bloqués — à arbitrer avec la comptabilité${NC}"
  grep -a "^@@RQ@@BLOCKED|" "$RAW" | sed 's/^@@RQ@@BLOCKED|//' | while IFS='|' read -r s mv why; do
    printf '  %-16s %-22s %s\n' "$s" "$mv" "$why"
  done
fi

costlines="$(grep -ac "^@@RQ@@COSTLINE|" "$RAW" || true)"
if [[ "${costlines:-0}" != "0" ]]; then
  printf '\n%s\n' "${BOLD}  Lignes de coût d'OT${NC}"
  grep -a "^@@RQ@@COSTLINE|" "$RAW" | sed 's/^@@RQ@@COSTLINE|//' | while IFS='|' read -r s ot before action; do
    printf '  %-16s OT %-10s %14s  → %s\n' "$s" "$ot" "$before" "$action"
  done
fi

printf '\n'
ok "Journal : $LOG"
ok "CSV     : $CSV"

if [[ "$APPLY" -eq 1 ]]; then
  printf '\n'
  ok "Écritures comptabilisées et validées en base."
  info "Contrôles : $0 --db $DB --container $CONTAINER --check"
else
  printf '\n'
  warn "SIMULATION : rien n'a été écrit."
  info "Faire valider le CSV par la comptabilité, puis :"
  printf '     %s --apply%s\n' "$0" \
    "$( [[ -n "$POSTING_DATE" ]] && echo " --posting-date $POSTING_DATE" )"
fi
printf '\n'
