# -*- coding: utf-8 -*-
"""
Modèle de token API pour l'authentification mobile
Module: invoice_qr_scanner
"""

from odoo import api, fields, models, _
from odoo.exceptions import ValidationError


class InvoiceScannerApiToken(models.Model):
    """Token d'authentification pour l'API mobile du scanner de factures.
    
    Stocke les tokens API générés lors de la connexion
    pour permettre l'authentification stateless.
    """
    _name = 'invoice.scanner.api.token'
    _description = "Token API Scanner Factures"
    _order = 'create_date desc'

    user_id = fields.Many2one(
        'res.users',
        string="Utilisateur",
        required=True,
        ondelete='cascade',
        index=True
    )
    
    token_hash = fields.Char(
        string="Hash du token",
        required=True,
        index=True,
        help="Hash SHA-256 du token (le token en clair n'est jamais stocké)"
    )
    
    expires_at = fields.Datetime(
        string="Expire le",
        required=True,
        index=True
    )
    
    is_active = fields.Boolean(
        string="Actif",
        default=True,
        index=True
    )
    
    last_used = fields.Datetime(
        string="Dernière utilisation"
    )
    
    device_info = fields.Char(
        string="Appareil",
        help="User-Agent de l'appareil"
    )
    
    ip_address = fields.Char(
        string="Adresse IP",
        help="Adresse IP lors de la connexion"
    )
    
    @api.model
    def cleanup_expired_tokens(self):
        """Nettoyer les tokens expirés (à appeler via cron)"""
        expired = self.search([
            '|',
            ('expires_at', '<', fields.Datetime.now()),
            ('is_active', '=', False)
        ])
        count = len(expired)
        expired.unlink()
        return count
    
    @api.model
    def deactivate_user_tokens(self, user_id):
        """Désactiver tous les tokens d'un utilisateur"""
        tokens = self.search([('user_id', '=', user_id), ('is_active', '=', True)])
        tokens.write({'is_active': False})
        return len(tokens)
