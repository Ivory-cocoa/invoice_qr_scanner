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
    
    # =========================================================================
    # COMPTE DE DÉPENSE PAR DÉFAUT
    # =========================================================================
    
    invoice_qr_default_expense_account_id = fields.Many2one(
        'account.account',
        string="Compte de dépense par défaut",
        config_parameter='invoice_qr_scanner.default_expense_account_id',
        domain="[('account_type', 'in', ['expense', 'expense_direct_cost'])]",
        help="Compte comptable utilisé par défaut pour les lignes de factures scannées"
    )
    
    # =========================================================================
    # OPTIONS DE CRÉATION FOURNISSEUR
    # =========================================================================
    
    invoice_qr_auto_create_supplier = fields.Boolean(
        string="Créer automatiquement le fournisseur",
        config_parameter='invoice_qr_scanner.auto_create_supplier',
        default=True,
        help="Si activé, un nouveau fournisseur sera créé automatiquement s'il n'existe pas dans Odoo"
    )
