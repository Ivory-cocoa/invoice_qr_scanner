# -*- coding: utf-8 -*-
"""
Configuration du module Invoice QR Scanner
"""

from odoo import api, fields, models, _


class ResConfigSettings(models.TransientModel):
    """Configuration pour le module de scan QR de factures."""
    _inherit = 'res.config.settings'

    # =========================================================================
    # AUTO-VALIDATION DES FACTURES
    # =========================================================================
    
    invoice_qr_auto_validate = fields.Boolean(
        string="Valider automatiquement les factures",
        config_parameter='invoice_qr_scanner.auto_validate_invoice',
        default=True,
        help="Si activé, les factures créées par scan QR seront automatiquement validées. "
             "Sinon, elles resteront en brouillon pour validation manuelle."
    )
