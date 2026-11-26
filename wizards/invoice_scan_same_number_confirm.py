# -*- coding: utf-8 -*-
"""Confirmation avant de marquer « traitée » une facture dont le numéro est
déjà porté par une autre facture enregistrée.

Second filet avant le paiement : l'avertissement est donné au scan ; ici, il
faut le confirmer au moment de transmettre à la comptabilité.
"""

from odoo import _, api, fields, models


class InvoiceScanSameNumberConfirm(models.TransientModel):
    _name = 'invoice.scan.same.number.confirm'
    _description = "Confirmation : même numéro de facture déjà enregistré"

    scan_ids = fields.Many2many(
        'invoice.scan.record', 'invoice_scan_same_number_confirm_scan_rel',
        'wizard_id', 'scan_id', string="Scans sélectionnés", readonly=True)
    twin_ids = fields.Many2many(
        'invoice.scan.record', 'invoice_scan_same_number_confirm_twin_rel',
        'wizard_id', 'scan_id', string="Factures de même numéro", readonly=True)
    twin_count = fields.Integer(compute='_compute_counts')
    other_count = fields.Integer(compute='_compute_counts')

    @api.depends('scan_ids', 'twin_ids')
    def _compute_counts(self):
        for wizard in self:
            wizard.twin_count = len(wizard.twin_ids)
            wizard.other_count = len(wizard.scan_ids - wizard.twin_ids)

    @api.model
    def _open_for(self, scans, twins):
        wizard = self.create({
            'scan_ids': [(6, 0, scans.ids)],
            'twin_ids': [(6, 0, twins.ids)],
        })
        return {
            'type': 'ir.actions.act_window',
            'name': _("Même numéro de facture déjà enregistré"),
            'res_model': self._name,
            'res_id': wizard.id,
            'view_mode': 'form',
            'target': 'new',
        }

    def action_confirm_all(self):
        """Transmettre quand même : toute la sélection est traitée."""
        self.ensure_one()
        return self.scan_ids.with_context(
            same_number_confirmed=True).action_mark_processed()

    def action_only_others(self):
        """Laisser de côté les factures de même numéro, traiter les autres."""
        self.ensure_one()
        others = self.scan_ids - self.twin_ids
        if not others:
            return {'type': 'ir.actions.act_window_close'}
        return others.action_mark_processed()
