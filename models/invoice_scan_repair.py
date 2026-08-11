# -*- coding: utf-8 -*-
"""Réparation des données de scan altérées par l'ancienne extraction.

Contexte
========
Jusqu'à la version 17.0.1.3.0, les données DGI étaient extraites du TEXTE de la
page de vérification, en découpant la ligne « NOM - CODE ». Quand la raison
sociale contenait elle-même un tiret (TERMINAL DE SAN-PEDRO, TRANS-ROULEMENTS,
3D INFOPLUS-CI), la coupure tombait au mauvais endroit : nom tronqué, et
« code DGI » valant en réalité un morceau du nom (PEDRO, ROULEMENTS, CI…).

L'API FNE, elle, renvoie le nom et le NCC comme deux champs distincts : les
données correctes sont donc récupérables facture par facture.

Ce module compare l'existant à la source et corrige — ou se contente de dire ce
qu'il corrigerait.

Ce qu'il fait, ce qu'il ne fait pas
==================================
- Il corrige les champs DGI des scans (nom, code, client, date, message).
- Il nettoie les codes DGI non conformes posés sur les fiches partenaires.
- Il **signale** les factures imputées à un autre partenaire que le fournisseur
  réel, mais ne les repointe JAMAIS : ce sont des écritures comptables, souvent
  déjà comptabilisées. La décision appartient à la comptabilité.

Utilisation
===========
    # Rapport, sans aucune écriture (par défaut)
    env['invoice.scan.record'].repair_dgi_data()

    # Restreindre aux scans manifestement faux (recommandé pour un premier jet)
    env['invoice.scan.record'].repair_dgi_data(only_invalid_code=True)

    # Appliquer réellement les corrections
    env['invoice.scan.record'].repair_dgi_data(dry_run=False)

Chaque appel journalise un rapport et renvoie un dictionnaire de résultats.
"""

import logging

from odoo import api, models

from .fne_api import FneApiError

_logger = logging.getLogger(__name__)

# Champs repris de la source FNE. `amount_ttc` est volontairement EXCLU : le
# montant conditionne des factures déjà comptabilisées, on ne le réécrit pas
# au fil d'un correctif de libellés.
REPAIRABLE_FIELDS = (
    'supplier_name',
    'supplier_code_dgi',
    'customer_name',
    'customer_code_dgi',
    'invoice_number_dgi',
    'invoice_date',
    'commercial_message',
)


class InvoiceScanRecordRepair(models.Model):
    _inherit = 'invoice.scan.record'

    @api.model
    def repair_dgi_data(self, dry_run=True, only_invalid_code=False, limit=None):
        """Comparer les scans à la source DGI et corriger les champs altérés.

        Args:
            dry_run: si True (défaut), rien n'est écrit — seul le rapport est produit.
            only_invalid_code: ne traiter que les scans dont le code DGI est non
                conforme (les cas certains), plutôt que l'ensemble des scans.
            limit: borne le nombre de scans traités (utile pour un essai).

        Returns:
            dict: compteurs, corrections détaillées et factures à ré-imputer.
        """
        domain = [('state', 'in', ['done', 'processed'])]
        records = self.search(domain, order='id')
        if only_invalid_code:
            records = records.filtered(
                lambda r: r.supplier_code_dgi and not self.is_valid_dgi_code(r.supplier_code_dgi))
        if limit:
            records = records[:limit]

        FneApi = self.env['fne.api.client']
        result = {
            'dry_run': dry_run,
            'scanned': len(records),
            'fixed': 0,
            'unchanged': 0,
            'unreachable': 0,
            'changes': [],
            'invoices_to_review': [],
        }

        for record in records:
            try:
                values = FneApi.fetch_invoice(record.qr_uuid)
            except FneApiError as exc:
                result['unreachable'] += 1
                _logger.info("Réparation : scan %s illisible côté DGI (%s)",
                             record.reference, exc.code)
                continue

            diff = {
                field: values[field]
                for field in REPAIRABLE_FIELDS
                if field in values and values[field] and values[field] != record[field]
            }

            if not diff:
                result['unchanged'] += 1
                continue

            result['fixed'] += 1
            result['changes'].append({
                'id': record.id,
                'reference': record.reference,
                'before': {field: record[field] for field in diff},
                'after': diff,
            })

            # La facture pointe-t-elle sur un autre tiers que le fournisseur réel ?
            self._collect_invoice_to_review(record, values, result)

            if not dry_run:
                record.write(diff)
                record.message_post(
                    body="Données DGI corrigées depuis la plateforme FNE : %s" % ', '.join(
                        sorted(diff)),
                    message_type='notification',
                )

        result['partners'] = self._repair_partner_dgi_codes(dry_run=dry_run)
        self._log_report(result)
        return result

    @staticmethod
    def _normalize_name(name):
        """Nom comparable : majuscules, sans ponctuation ni espaces multiples."""
        cleaned = ''.join(c if c.isalnum() else ' ' for c in (name or '').upper())
        return ' '.join(cleaned.split())

    @api.model
    def _collect_invoice_to_review(self, record, values, result):
        """Classer l'écart entre le tiers de la facture et le fournisseur réel.

        Deux situations très différentes se cachent derrière « les noms ne
        correspondent pas », et les confondre noierait les vrais problèmes :

        - `libelle` : le tiers est le bon, son nom est seulement tronqué ou
          ponctué autrement (SPD → SPD-SAN PEDRO DIESEL, TERMINAL DE SAN PEDRO
          → TERMINAL DE SAN-PEDRO). Rien à réimputer ; tout au plus renommer.
        - `conflit` : le tiers est une AUTRE entreprise (TRANS-ROULEMENTS
          imputé à « CLIENT LOCAL TRANSCAO », CIS imputé à « 3D INFOPLUS-CI »).
          Là, une écriture comptable porte le mauvais fournisseur.
        """
        invoice = record.invoice_id
        partner = invoice.partner_id if invoice else record.partner_id
        if not invoice or not partner:
            return

        real_code = (values.get('supplier_code_dgi') or '').strip().upper()
        partner_code = (partner.dgi_code or '').strip().upper()
        real_name = self._normalize_name(values.get('supplier_name'))
        partner_name = self._normalize_name(partner.name)

        # Même NCC ou même nom normalisé : aucun écart réel.
        if real_code and partner_code and real_code == partner_code:
            return
        if real_name and real_name == partner_name:
            return

        # Nom actuel tronqué au début du nom réel : même tiers, libellé abrégé.
        # C'est exactement la signature de l'ancienne extraction.
        if real_name and partner_name and real_name.startswith(partner_name):
            severity = 'libelle'
        elif partner_code and real_code and partner_code != real_code:
            # Deux NCC différents : ce sont deux entreprises distinctes.
            severity = 'conflit'
        else:
            severity = 'conflit'

        result['invoices_to_review'].append({
            'severity': severity,
            'scan_id': record.id,
            'scan_reference': record.reference,
            'invoice_id': invoice.id,
            'invoice_name': invoice.name,
            'invoice_state': invoice.state,
            'current_partner_id': partner.id,
            'current_partner': partner.name,
            'real_supplier': values.get('supplier_name'),
            'real_supplier_code': values.get('supplier_code_dgi'),
        })

    @api.model
    def _repair_partner_dgi_codes(self, dry_run=True):
        """Vider les codes DGI non conformes posés sur les fiches partenaires.

        Un code invalide sur un partenaire est pire qu'un code absent : la
        recherche par code passant en premier, il capte tous les scans portant
        le même fragment. Effacé, l'identification retombe sur le nom exact.
        """
        Partner = self.env['res.partner']
        partners = Partner.search([('dgi_code', '!=', False)])
        wrong = partners.filtered(lambda p: not self.is_valid_dgi_code(p.dgi_code))

        report = [{'id': p.id, 'name': p.name, 'dgi_code': p.dgi_code} for p in wrong]

        if not dry_run and wrong:
            wrong.write({'dgi_code': False})

        return {'cleared': len(wrong), 'details': report}

    @api.model
    def _log_report(self, result):
        mode = "SIMULATION (aucune écriture)" if result['dry_run'] else "APPLIQUÉ"
        conflicts = [r for r in result['invoices_to_review'] if r['severity'] == 'conflit']
        labels = [r for r in result['invoices_to_review'] if r['severity'] == 'libelle']
        _logger.info(
            "Réparation DGI — %s : %s scans examinés, %s corrigés, %s inchangés, "
            "%s illisibles ; %s codes partenaires effacés ; "
            "%s factures sur un AUTRE tiers (décision comptable), "
            "%s simples écarts de libellé",
            mode, result['scanned'], result['fixed'], result['unchanged'],
            result['unreachable'], result['partners']['cleared'],
            len(conflicts), len(labels),
        )
