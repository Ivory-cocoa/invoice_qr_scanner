# -*- coding: utf-8 -*-
"""Requalification des avoirs FNE enregistrés à tort en factures d'achat.

Ce qui s'est passé
==================
La plateforme FNE certifie deux natures de document sous un QR-code identique :
les factures (``subtype: "normal"``) et les **avoirs** (``subtype: "refund"``,
montants négatifs). Rien dans l'URL ne les distingue.

L'ancienne extraction lisait le montant sur le TEXTE de la page de vérification,
qui l'affiche en valeur absolue : un avoir de 250 000 F y ressemblait trait pour
trait à une facture de 250 000 F. Chaque avoir scanné devenait donc une facture
d'achat — une dette envers le fournisseur là où il fallait une créance.

L'extraction par l'API FNE, elle, voit le montant négatif. C'est ce qui a rendu
le défaut visible : elle refusait les avoirs au lieu de les enregistrer à
l'envers. Le refus était le symptôme ; la cause était en base depuis des mois.

Ce que ce module fait
=====================
Pour chaque scan candidat, il demande sa nature à la DGI — **jamais** de
requalification sur une heuristique — et, pour les avoirs comptabilisés en
factures :

1. extourne la facture d'achat erronée (écriture d'annulation, comptabilisée) ;
2. recrée la pièce dans le bon sens (avoir fournisseur ``in_refund``) ;
3. requalifie le scan et rétablit son état (« traité » le reste) ;
4. inverse le signe des lignes de coût d'OT dérivées de ce scan.

Trois pièces comptables subsistent donc : la fausse facture, son extourne, et
l'avoir. C'est voulu. Une correction comptable se lit dans le grand livre ; elle
ne s'y efface pas.

Ce que ce module NE fait PAS
============================
Il refuse de toucher une écriture qui a été **payée, rapprochée, ou qui tombe
dans une période verrouillée** : il la signale et s'arrête là. Ces cas relèvent
d'une décision comptable, pas d'un script.

Utilisation
===========
    # 1. Rapport, sans AUCUNE écriture (comportement par défaut)
    env['invoice.scan.record'].repair_refund_documents()

    # 2. Balayage exhaustif (interroge la DGI pour TOUS les scans : lent)
    env['invoice.scan.record'].repair_refund_documents(only_suspect=False)

    # 3. Appliquer réellement les corrections
    env['invoice.scan.record'].repair_refund_documents(dry_run=False)

    # 4. Se limiter à des scans précis
    env['invoice.scan.record'].repair_refund_documents(dry_run=False, scan_ids=[2596, 2595])

Chaque appel journalise un rapport et renvoie un dictionnaire de résultats.
"""

import logging
import re

from odoo import _, api, models

from .fne_api import FneApiError

_logger = logging.getLogger(__name__)

# Préfixe des références d'avoir observé sur la plateforme FNE : « A » suivi du
# NCC de l'émetteur (A7603114Y2600000393) là où une facture commence
# directement par le NCC (7603114Y26000010087).
#
# ⚠️ Cette expression ne DÉCIDE de rien. Elle sert uniquement à réduire le
# nombre de scans à soumettre à la DGI (24 appels au lieu de 4 962) : chaque
# candidat retenu est ensuite confirmé — ou infirmé — par la plateforme
# elle-même. `only_suspect=False` la contourne et interroge tout le stock.
REFUND_REFERENCE_PREFIX = re.compile(r'^A[0-9]{7}[A-Z]', re.IGNORECASE)


class InvoiceScanRefundRepair(models.Model):
    _inherit = 'invoice.scan.record'

    # ⚠️ Toutes les méthodes de ce fichier sont préfixées `_refund_` ou
    # suffixées explicitement. `invoice_scan_repair.py` étend le MÊME modèle :
    # une méthode privée nommée pareil (`_log_report`, par exemple) ne
    # surcharge pas l'autre, elle la REMPLACE — silencieusement, selon l'ordre
    # d'import. Le premier essai de ce module s'est planté ainsi.

    # ------------------------------------------------------------------
    # Point d'entrée
    # ------------------------------------------------------------------

    @api.model
    def repair_refund_documents(self, dry_run=True, only_suspect=True,
                                limit=None, scan_ids=None):
        """Requalifier les avoirs enregistrés en factures d'achat.

        Args:
            dry_run: si True (défaut), rien n'est écrit — seul le rapport sort.
            only_suspect: ne soumettre à la DGI que les scans dont la référence
                a la forme d'un avoir. À False, tout le stock est interrogé.
            limit: borne le nombre de scans examinés (essai).
            scan_ids: liste d'identifiants à traiter, court-circuitant la
                sélection automatique.

        Returns:
            dict: compteurs, détail des corrections et cas bloqués.
        """
        records = self._select_refund_repair_candidates(only_suspect, limit, scan_ids)

        result = {
            'dry_run': dry_run,
            'examined': len(records),
            'confirmed_invoice': 0,
            'already_refund': 0,
            'requalified': 0,
            'blocked': 0,
            'unreachable': 0,
            'changes': [],
            'blocked_details': [],
            'cost_lines': [],
        }

        FneApi = self.env['fne.api.client']

        for record in records:
            try:
                nature = FneApi.fetch_document_nature(record.qr_uuid)
            except FneApiError as exc:
                result['unreachable'] += 1
                _logger.info("Requalification : scan %s illisible côté DGI (%s)",
                             record.reference, exc.code)
                continue

            is_refund = nature['document_type'] == 'refund'

            if not is_refund:
                result['confirmed_invoice'] += 1
                if not dry_run and not record.document_type_verified:
                    record.write({'document_type_verified': True})
                continue

            if record.document_type == 'refund':
                result['already_refund'] += 1
                if not dry_run and not record.document_type_verified:
                    record.write({'document_type_verified': True})
                continue

            self._requalify_refund_scan(record, nature, dry_run, result)

        self._log_refund_repair_report(result)
        return result

    @api.model
    def _select_refund_repair_candidates(self, only_suspect, limit, scan_ids):
        """Scans à soumettre à la DGI."""
        if scan_ids:
            records = self.browse(scan_ids).exists()
        else:
            records = self.search(
                [('state', 'in', ['done', 'processed'])], order='id')
            if only_suspect:
                records = records.filtered(
                    lambda r: r.invoice_number_dgi
                    and REFUND_REFERENCE_PREFIX.match(r.invoice_number_dgi.strip()))
        if limit:
            records = records[:limit]
        return records

    # ------------------------------------------------------------------
    # Requalification d'un scan
    # ------------------------------------------------------------------

    @api.model
    def _requalify_refund_scan(self, record, nature, dry_run, result):
        """Traiter un avoir enregistré en facture."""
        move = record.invoice_id
        blockers = self._refund_reversal_blockers(move)

        entry = {
            'scan_id': record.id,
            'scan_reference': record.reference,
            'invoice_number_dgi': record.invoice_number_dgi,
            'supplier': record.supplier_name,
            'amount_ttc': record.amount_ttc,
            'origin_invoice_number_dgi': nature.get('origin_invoice_number_dgi'),
            'move_id': move.id if move else None,
            'move_name': move.name if move else None,
            'move_state': move.state if move else None,
            'cost_lines': self._refund_cost_line_summary(record),
        }

        if blockers:
            result['blocked'] += 1
            entry['blockers'] = blockers
            result['blocked_details'].append(entry)
            return

        result['requalified'] += 1
        result['changes'].append(entry)

        if dry_run:
            return

        previous_state = record.state
        previous_processed_by = record.processed_by
        previous_processed_date = record.processed_date

        reversal = self._reverse_wrong_invoice_move(record, move)
        entry['reversal_name'] = reversal.name if reversal else None

        # Détacher l'ancienne pièce AVANT de requalifier : `_create_invoice`
        # refuse de travailler sur un scan qui porte déjà une facture.
        record.with_context(allow_document_type_change=True).write({
            'document_type': 'refund',
            'document_type_verified': True,
            'origin_invoice_number_dgi': nature.get('origin_invoice_number_dgi') or False,
            'invoice_id': False,
            'state': 'draft',
        })

        refund_move = record._create_invoice()
        entry['refund_move_name'] = refund_move.name

        # Rétablir l'état antérieur : un scan « traité » l'était pour de bonnes
        # raisons, et la correction comptable ne le remet pas en attente.
        if previous_state == 'processed':
            record.write({
                'state': 'processed',
                'processed_by': previous_processed_by.id or False,
                'processed_date': previous_processed_date or False,
            })

        record.message_post(
            body=_(
                "REQUALIFICATION EN AVOIR — confirmé par la plateforme DGI.<br/>"
                "Facture erronée : %(wrong)s (extournée par %(reversal)s).<br/>"
                "Avoir créé : %(refund)s."
            ) % {
                'wrong': entry['move_name'] or _("aucune"),
                'reversal': entry.get('reversal_name') or _("aucune"),
                'refund': refund_move.name or '',
            },
            message_type='notification',
        )

        self._flip_refund_cost_lines(record, result, entry)

    @api.model
    def _reverse_wrong_invoice_move(self, record, move):
        """Extourner la facture d'achat créée à tort.

        `_reverse_moves(cancel=True)` comptabilise l'extourne et solde la pièce
        d'origine : le grand livre revient à zéro sur cette facture, sans que
        rien ne disparaisse. Une pièce en brouillon, elle, n'a jamais rien
        produit — on la supprime plutôt que de polluer la comptabilité d'une
        extourne à zéro.
        """
        if not move:
            return self.env['account.move']

        if move.state == 'draft':
            move.unlink()
            return self.env['account.move']

        return move._reverse_moves([{
            'ref': _("Extourne — avoir DGI enregistré à tort en facture (scan %s)")
                   % record.reference,
            'invoice_date': move.invoice_date,
            'date': move.date,
        }], cancel=True)

    @api.model
    def _refund_reversal_blockers(self, move):
        """Raisons de NE PAS toucher automatiquement à cette écriture.

        Un script n'a pas à défaire un règlement ni à écrire dans un exercice
        clos. Ces cas sont signalés pour arbitrage comptable, jamais corrigés
        en silence.
        """
        if not move:
            return []

        blockers = []
        if move.state == 'cancel':
            blockers.append(_("écriture annulée"))
        if move.payment_state not in ('not_paid', False):
            blockers.append(_("écriture réglée ou rapprochée (%s)") % move.payment_state)
        if move.reversed_entry_id or move.reversal_move_id:
            blockers.append(_("écriture déjà extournée"))

        lock_date = move.company_id.fiscalyear_lock_date
        if lock_date and move.date and move.date <= lock_date:
            blockers.append(_("période comptable verrouillée au %s") % lock_date)

        return blockers

    # ------------------------------------------------------------------
    # Lignes de coût d'OT
    # ------------------------------------------------------------------

    @api.model
    def _refund_cost_line_summary(self, record):
        """Lignes de coût d'OT adossées à ce scan (module potting_management)."""
        if 'potting.cost.line' not in self.env:
            return []
        lines = self.env['potting.cost.line'].sudo().search(
            [('scan_record_id', '=', record.id)])
        return [{
            'id': line.id,
            'ot': line.transit_order_id.display_name if line.transit_order_id else '',
            'amount': line.amount,
            'state': line.state,
        } for line in lines]

    @api.model
    def _flip_refund_cost_lines(self, record, result, entry):
        """Inverser le signe des lignes de coût dérivées d'un avoir.

        Une ligne de coût reprise d'un avoir doit RETRANCHER du coût de l'OT.
        On n'inverse que les lignes dont le montant correspond effectivement à
        celui du scan : une ligne saisie ou ventilée à la main relève de son
        auteur, pas d'un script. Les lignes déjà payées ne sont jamais touchées.
        """
        if 'potting.cost.line' not in self.env:
            return

        lines = self.env['potting.cost.line'].sudo().search(
            [('scan_record_id', '=', record.id)])
        for line in lines:
            item = {
                'scan_reference': record.reference,
                'cost_line_id': line.id,
                'ot': line.transit_order_id.display_name if line.transit_order_id else '',
                'before': line.amount,
            }
            if line.state == 'paid':
                item['action'] = 'ignorée (payée)'
            elif line.amount <= 0:
                item['action'] = 'ignorée (déjà négative)'
            elif abs(abs(line.amount) - abs(record.amount_ttc)) > 0.01:
                item['action'] = 'à revoir manuellement (montant ventilé)'
            else:
                line.write({'amount': -abs(line.amount)})
                item['action'] = 'signe inversé'
                item['after'] = line.amount
            result['cost_lines'].append(item)
            entry.setdefault('cost_line_actions', []).append(item)

    # ------------------------------------------------------------------
    # Rapport
    # ------------------------------------------------------------------

    @api.model
    def _log_refund_repair_report(self, result):
        mode = "SIMULATION (aucune écriture)" if result['dry_run'] else "APPLIQUÉ"
        _logger.info(
            "Requalification des avoirs — %s : %s scans examinés ; "
            "%s confirmés factures, %s déjà en avoir, %s requalifiés, "
            "%s bloqués (décision comptable), %s illisibles côté DGI",
            mode, result['examined'], result['confirmed_invoice'],
            result['already_refund'], result['requalified'],
            result['blocked'], result['unreachable'],
        )
        for change in result['changes']:
            _logger.info(
                "  %s %s — %s %s : facture %s → avoir%s",
                change['scan_reference'], change['invoice_number_dgi'] or '',
                change['supplier'] or '', change['amount_ttc'],
                change['move_name'] or '(aucune)',
                ' ' + (change.get('refund_move_name') or '') if not result['dry_run'] else '',
            )
        for blocked in result['blocked_details']:
            _logger.warning(
                "  BLOQUÉ %s (%s) : %s",
                blocked['scan_reference'], blocked['move_name'] or '(aucune)',
                ', '.join(blocked['blockers']),
            )
