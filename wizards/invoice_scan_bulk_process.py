# -*- coding: utf-8 -*-
"""Assistant de traitement groupé des scans de QR-code.

Il se veut l'inverse d'une action de masse muette : il montre d'abord la
VENTILATION de la sélection (combien de scans sont réellement concernés par
l'opération choisie, et pourquoi les autres ne le sont pas), puis exécute,
puis rend un compte-rendu ligne à ligne.

L'assistant ne porte aucune règle métier : tout est délégué au moteur
`invoice.scan.record._bulk_*`, partagé avec les actions de la liste et
l'API mobile. Ajouter une opération se fait en deux points seulement —
`_selection_operation` et `_bulk_execute` — ce que fait par exemple
`potting_management` pour le rattachement aux Ordres de Transit.
"""

from odoo import _, api, fields, models
from odoo.exceptions import UserError

from ..models.invoice_scan_bulk import BULK_DONE, BULK_ERROR, BULK_SKIPPED


class InvoiceScanBulkProcess(models.TransientModel):
    _name = 'invoice.scan.bulk.process'
    _description = "Traitement groupé des scans de factures"

    # Opérations qui interrogent la plateforme DGI (un appel réseau par scan).
    NETWORK_OPERATIONS = ('verify_nature',)

    state = fields.Selection([
        ('draft', "Sélection"),
        ('done', "Compte-rendu"),
    ], default='draft', required=True)

    scan_ids = fields.Many2many(
        'invoice.scan.record',
        string="Scans sélectionnés",
        required=True,
    )
    operation = fields.Selection(
        selection='_selection_operation',
        string="Opération",
        required=True,
        default='mark_processed',
        help="Opération à appliquer à l'ensemble de la sélection.",
    )

    # --- Ventilation de la sélection (avant exécution) --------------------
    count_total = fields.Integer(string="Sélectionnés", compute='_compute_counts')
    count_draft = fields.Integer(string="Brouillons", compute='_compute_counts')
    count_done = fields.Integer(string="Facture créée", compute='_compute_counts')
    count_processed = fields.Integer(string="Déjà traités", compute='_compute_counts')
    count_error = fields.Integer(string="Sélection en erreur", compute='_compute_counts')
    count_eligible = fields.Integer(
        string="Concernés par l'opération", compute='_compute_eligibility')
    eligibility_message = fields.Char(compute='_compute_eligibility')

    # --- Compte-rendu (après exécution) -----------------------------------
    line_ids = fields.One2many(
        'invoice.scan.bulk.process.line', 'wizard_id',
        string="Compte-rendu", readonly=True,
    )
    result_done = fields.Integer(string="Traités", readonly=True)
    result_skipped = fields.Integer(string="Ignorés", readonly=True)
    result_error = fields.Integer(string="En erreur", readonly=True)

    # =========================================================================
    # SÉLECTION DES OPÉRATIONS — point d'extension
    # =========================================================================
    @api.model
    def _selection_operation(self):
        """Opérations disponibles.

        Sélection dynamique (et non `selection_add`) pour qu'un module tiers
        puisse en ajouter une par simple surcharge, sans avoir à déclarer de
        politique `ondelete` sur un champ d'assistant.
        """
        return [
            ('mark_processed', _("Marquer comme traité(s)")),
            ('mark_unprocessed', _("Remettre non traité(s)")),
            ('create_invoice', _("Créer la pièce comptable manquante")),
            ('verify_nature', _("Vérifier la nature auprès de la DGI")),
        ]

    @api.model
    def default_get(self, fields_list):
        res = super().default_get(fields_list)
        if 'scan_ids' in fields_list and not res.get('scan_ids'):
            active_ids = self.env.context.get('active_ids')
            if active_ids and self.env.context.get('active_model') == 'invoice.scan.record':
                res['scan_ids'] = [(6, 0, list(active_ids))]
        return res

    # =========================================================================
    # CALCULS
    # =========================================================================
    @api.depends('scan_ids.state')
    def _compute_counts(self):
        for wiz in self:
            states = wiz.scan_ids.mapped('state')
            wiz.count_total = len(states)
            wiz.count_draft = states.count('draft')
            wiz.count_done = states.count('done')
            wiz.count_processed = states.count('processed')
            wiz.count_error = states.count('error')

    def _eligible_scans(self):
        """Scans que l'opération choisie va réellement toucher.

        Miroir des règles du moteur — volontairement redondant : c'est ce qui
        permet d'annoncer AVANT d'agir. Le moteur reste seul juge à
        l'exécution ; en cas de divergence, c'est le compte-rendu qui fait foi.
        """
        self.ensure_one()
        scans = self.scan_ids
        if self.operation == 'mark_processed':
            return scans.filtered(lambda s: s.state == 'done')
        if self.operation == 'mark_unprocessed':
            return scans.filtered(lambda s: s.state == 'processed')
        if self.operation == 'create_invoice':
            return scans.filtered(
                lambda s: not s.invoice_id and s.state in ('draft', 'error'))
        if self.operation == 'verify_nature':
            return scans
        return scans

    @api.depends('scan_ids.state', 'scan_ids.invoice_id', 'operation')
    def _compute_eligibility(self):
        for wiz in self:
            eligible = wiz._eligible_scans() if wiz.operation else wiz.browse()
            wiz.count_eligible = len(eligible)
            ignored = wiz.count_total - wiz.count_eligible
            if not wiz.count_total:
                wiz.eligibility_message = _("Aucun scan sélectionné.")
            elif not wiz.count_eligible:
                wiz.eligibility_message = _(
                    "Aucun des %s scan(s) sélectionné(s) n'est concerné par "
                    "cette opération.", wiz.count_total)
            elif ignored:
                wiz.eligibility_message = _(
                    "%(ok)s scan(s) sur %(total)s seront traités ; "
                    "%(ko)s seront ignorés (le compte-rendu dira pourquoi).",
                    ok=wiz.count_eligible, total=wiz.count_total, ko=ignored)
            else:
                wiz.eligibility_message = _(
                    "Les %s scan(s) sélectionné(s) sont tous concernés.",
                    wiz.count_total)

    # =========================================================================
    # EXÉCUTION
    # =========================================================================
    def _bulk_execute(self):
        """Exécuter l'opération choisie et renvoyer le compte-rendu.

        Point d'extension : un module tiers surcharge cette méthode pour son
        opération et délègue le reste à `super()`.
        """
        self.ensure_one()
        scans = self.scan_ids
        if self.operation == 'mark_processed':
            return scans._bulk_mark_processed(origin=_("assistant"))
        if self.operation == 'mark_unprocessed':
            return scans._bulk_mark_unprocessed(origin=_("assistant"))
        if self.operation == 'create_invoice':
            return scans._bulk_create_invoice()
        if self.operation == 'verify_nature':
            return scans._bulk_verify_document_type()
        raise UserError(_("Opération inconnue : %s", self.operation))

    def action_apply(self):
        self.ensure_one()
        if not self.scan_ids:
            raise UserError(_("Sélectionnez au moins un scan."))

        limit = self.env['invoice.scan.record'].BULK_NETWORK_LIMIT
        if self.operation in self.NETWORK_OPERATIONS and len(self.scan_ids) > limit:
            raise UserError(_(
                "Cette opération interroge la DGI une fois par scan : "
                "%(count)s dépasse la limite de %(limit)s par lot. "
                "Réduisez la sélection.",
                count=len(self.scan_ids), limit=limit))

        entries = self._bulk_execute()
        counters = self.env['invoice.scan.record']._bulk_counters(entries)

        self.write({
            'state': 'done',
            'result_done': counters[BULK_DONE],
            'result_skipped': counters[BULK_SKIPPED],
            'result_error': counters[BULK_ERROR],
            'line_ids': [(5, 0, 0)] + [
                (0, 0, {
                    'scan_id': entry['scan_id'],
                    'status': entry['status'],
                    'message': entry['message'],
                })
                for entry in entries
            ],
        })

        # On rouvre le MÊME assistant, en mode compte-rendu. Renvoyer `True`
        # fermerait la fenêtre — et le compte-rendu avec elle.
        return {
            'type': 'ir.actions.act_window',
            'name': _("Traitement groupé — compte-rendu"),
            'res_model': self._name,
            'res_id': self.id,
            'view_mode': 'form',
            'target': 'new',
            'context': self.env.context,
        }

    def action_view_scans(self):
        """Ouvrir la liste des scans du compte-rendu (toutes lignes)."""
        self.ensure_one()
        return {
            'type': 'ir.actions.act_window',
            'name': _("Scans du traitement groupé"),
            'res_model': 'invoice.scan.record',
            'view_mode': 'tree,form',
            'domain': [('id', 'in', self.scan_ids.ids)],
            'target': 'current',
        }

    def action_close(self):
        return {'type': 'ir.actions.act_window_close'}


class InvoiceScanBulkProcessLine(models.TransientModel):
    _name = 'invoice.scan.bulk.process.line'
    _description = "Ligne de compte-rendu du traitement groupé"
    _order = 'status, id'

    wizard_id = fields.Many2one(
        'invoice.scan.bulk.process', required=True, ondelete='cascade')
    scan_id = fields.Many2one('invoice.scan.record', string="Scan", readonly=True)
    reference = fields.Char(related='scan_id.reference', string="Référence", readonly=True)
    supplier_name = fields.Char(related='scan_id.supplier_name', string="Fournisseur", readonly=True)
    amount_signed = fields.Monetary(
        related='scan_id.amount_signed', string="Montant", readonly=True,
        currency_field='currency_id')
    currency_id = fields.Many2one(related='scan_id.currency_id', readonly=True)
    status = fields.Selection([
        (BULK_DONE, "Traité"),
        (BULK_SKIPPED, "Ignoré"),
        (BULK_ERROR, "Erreur"),
    ], string="Résultat", readonly=True, required=True)
    message = fields.Char(string="Détail", readonly=True)
