# -*- coding: utf-8 -*-
"""
Configuration du module Invoice QR Scanner
"""

from odoo import api, fields, models, _

from .fne_api import DEFAULT_BASE_URL, PARAM_BASE_URL, PARAM_ENABLED


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
    # VÉRIFICATION AUPRÈS DE LA DGI (plateforme FNE)
    # =========================================================================

    invoice_qr_fne_api_enabled = fields.Boolean(
        string="Vérification automatique auprès de la DGI",
        help="Si activé, le serveur récupère lui-même les données de la facture "
             "auprès de la plateforme FNE à partir du QR-code. Si désactivé (ou "
             "si la DGI est injoignable), l'application bascule sur la saisie "
             "manuelle.",
    )

    invoice_qr_fne_api_base_url = fields.Char(
        string="URL de l'API FNE",
        config_parameter=PARAM_BASE_URL,
        help="Racine de l'API de vérification de la plateforme FNE. "
             "Laisser vide pour utiliser %s." % DEFAULT_BASE_URL,
    )

    # `invoice_qr_fne_api_enabled` n'utilise volontairement PAS `config_parameter` :
    # pour un booléen dont le défaut est VRAI, le mécanisme standard est un piège.
    # Décocher la case écrit une valeur vide, ce qui SUPPRIME le paramètre — et
    # `get_param(clé, 'True')` renvoie alors de nouveau True. La case ne se
    # décocherait jamais. On stocke donc explicitement 'True'/'False'.

    @api.model
    def get_values(self):
        res = super().get_values()
        res['invoice_qr_fne_api_enabled'] = self.env['fne.api.client']._is_enabled()
        return res

    def set_values(self):
        super().set_values()
        self.env['ir.config_parameter'].sudo().set_param(
            PARAM_ENABLED, 'True' if self.invoice_qr_fne_api_enabled else 'False')
