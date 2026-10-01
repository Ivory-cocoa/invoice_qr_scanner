# -*- coding: utf-8 -*-
"""
Modèle de token API pour l'authentification mobile
Module: invoice_qr_scanner
"""

import hashlib
import logging
import secrets
from datetime import timedelta

from odoo import api, fields, models, _
from odoo.exceptions import ValidationError

_logger = logging.getLogger(__name__)


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
    
    # Application émettrice. La table est partagée par plusieurs applications
    # mobiles (scanner de factures, scanner de connaissements du module
    # cacao…) : chaque API n'accepte QUE ses propres jetons, sinon un jeton
    # obtenu dans une application ouvrirait l'API de l'autre. Les modules
    # dépendants étendent la sélection (selection_add, ondelete='cascade').
    app = fields.Selection(
        [('invoice_scanner', "Scanner de factures")],
        string="Application",
        required=True,
        default='invoice_scanner',
        index=True,
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
    
    # ==================== ÉMISSION / VÉRIFICATION ====================

    @staticmethod
    def _hash_token(token):
        """Hash SHA-256 du jeton (seul le hash est stocké)."""
        return hashlib.sha256((token or '').encode()).hexdigest()

    @api.model
    def _issue_token(self, user, app, hours, device_info=None, ip_address=None):
        """Crée un jeton pour `user` dans l'application `app`.

        Retourne ``(jeton_en_clair, expires_at)`` : le jeton en clair n'est
        jamais stocké, l'appelant doit le transmettre tel quel au client.
        À appeler en sudo.
        """
        token = secrets.token_urlsafe(64)
        expires_at = fields.Datetime.now() + timedelta(hours=hours)
        self.create({
            'user_id': user.id,
            'app': app,
            'token_hash': self._hash_token(token),
            'expires_at': expires_at,
            'device_info': (device_info or '')[:200],
            'ip_address': ip_address or False,
        })
        return token, expires_at

    @api.model
    def _find_valid(self, token, app):
        """Jeton actif, non expiré, de l'application `app` et d'un utilisateur
        actif ; recordset vide sinon. À appeler en sudo."""
        if not token:
            return self.browse()
        record = self.search([
            ('token_hash', '=', self._hash_token(token)),
            ('app', '=', app),
            ('expires_at', '>', fields.Datetime.now()),
            ('is_active', '=', True),
        ], limit=1)
        if record and not record.user_id.active:
            return self.browse()
        return record

    def _touch(self):
        """Met à jour `last_used` au plus une fois par minute.

        Écriture isolée dans un savepoint : deux requêtes simultanées du même
        téléphone se disputeraient la ligne (« could not serialize access »)
        et la collision ne doit pas faire échouer la requête métier.
        """
        self.ensure_one()
        now = fields.Datetime.now()
        if self.last_used and (now - self.last_used).total_seconds() < 60:
            return
        try:
            with self.env.cr.savepoint():
                self.write({'last_used': now})
        except Exception as exc:  # noqa: BLE001 — trace d'usage, jamais bloquante
            _logger.debug("last_used non mis à jour (jeton %s) : %s", self.id, exc)

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
