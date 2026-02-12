# -*- coding: utf-8 -*-
"""
Extension du modèle account.move pour les factures scannées
"""

from odoo import api, fields, models, _


class AccountMove(models.Model):
    """Extension de account.move pour tracer les factures scannées."""
    _inherit = 'account.move'

    qr_scan_uuid = fields.Char(
        string="UUID Scan QR",
        index=True,
        help="UUID de vérification DGI si la facture a été créée par scan QR"
    )
    
    qr_scan_record_id = fields.Many2one(
        'invoice.scan.record',
        string="Enregistrement scan",
        readonly=True,
        help="Lien vers l'enregistrement du scan QR"
    )
    
    is_from_qr_scan = fields.Boolean(
        string="Créée par scan QR",
        compute='_compute_is_from_qr_scan',
        store=True
    )

    @api.depends('qr_scan_uuid')
    def _compute_is_from_qr_scan(self):
        for move in self:
            move.is_from_qr_scan = bool(move.qr_scan_uuid)


class ResPartner(models.Model):
    """Extension de res.partner pour stocker le code DGI."""
    _inherit = 'res.partner'

    dgi_code = fields.Char(
        string="Code DGI",
        index=True,
        help="Code d'identification fiscale DGI (ex: 2502298K)"
    )
