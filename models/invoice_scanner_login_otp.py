# -*- coding: utf-8 -*-
"""
Code de connexion à usage unique (OTP) pour l'API mobile
Module: invoice_qr_scanner
"""

import hashlib
import logging
import secrets
import string
from datetime import timedelta

from odoo import _, api, fields, models
from odoo.exceptions import UserError

_logger = logging.getLogger(__name__)


class InvoiceScannerLoginOtp(models.Model):
    """Code à usage unique envoyé par email pour authentifier l'app mobile.

    Remplace le mot de passe dans le parcours de connexion mobile : l'app
    demande un code, l'utilisateur le lit dans sa boîte mail, et le code
    échangé donne un `invoice.scanner.api.token`.

    Comme pour le token API, seul le HASH du code est stocké : le code en
    clair n'existe qu'entre sa génération et son envoi par email.

    Une seule ligne par utilisateur (contrainte d'unicité) : demander un
    nouveau code écrase le précédent, ce qui invalide de fait tout code
    encore en circulation.
    """
    _name = 'invoice.scanner.login.otp'
    _description = "Code de connexion mobile (OTP)"
    _order = 'create_date desc'
    _rec_name = 'user_id'

    # Durée de validité d'un code. Assez court pour limiter la fenêtre
    # d'exploitation d'une boîte mail compromise, assez long pour laisser le
    # temps de basculer d'application sur le téléphone.
    OTP_TTL_MINUTES = 10

    # Tentatives de saisie autorisées pour un même code. Au-delà, le code est
    # mort : il faut en redemander un (ce qui repasse par la boîte mail).
    OTP_MAX_ATTEMPTS = 5

    # Anti-spam : délai minimal entre deux envois pour un même utilisateur.
    # Aligné sur le compte à rebours affiché côté mobile.
    OTP_RESEND_SECONDS = 60

    user_id = fields.Many2one(
        'res.users',
        string="Utilisateur",
        required=True,
        ondelete='cascade',
        index=True,
    )

    otp_hash = fields.Char(
        string="Hash du code",
        help="Hash SHA-256 du code (le code en clair n'est jamais stocké)",
    )

    expires_at = fields.Datetime(
        string="Expire le",
        index=True,
    )

    attempts = fields.Integer(
        string="Tentatives",
        default=0,
        help="Nombre de saisies erronées pour le code courant",
    )

    last_sent = fields.Datetime(
        string="Dernier envoi",
        help="Sert à l'anti-spam (un code toutes les %d s)" % OTP_RESEND_SECONDS,
    )

    ip_address = fields.Char(
        string="Adresse IP",
        help="Adresse IP à l'origine de la dernière demande de code",
    )

    _sql_constraints = [
        ('user_uniq', 'UNIQUE(user_id)',
         "Un seul code de connexion en cours par utilisateur."),
    ]

    # ==================== UTILITAIRES ====================

    @staticmethod
    def _hash(code):
        """Hash SHA-256 du code, identique au procédé utilisé pour les tokens."""
        return hashlib.sha256((code or '').encode()).hexdigest()

    @api.model
    def _get_or_create(self, user):
        """Retourne la ligne OTP de `user`, en la créant au besoin.

        À appeler en sudo : le modèle n'est pas accessible aux utilisateurs
        finaux (cf. ir.model.access.csv).
        """
        record = self.search([('user_id', '=', user.id)], limit=1)
        if not record:
            record = self.create({'user_id': user.id})
        return record

    def _can_resend(self):
        """False si un code vient d'être envoyé (fenêtre anti-spam)."""
        self.ensure_one()
        if not self.last_sent:
            return True
        elapsed = fields.Datetime.now() - self.last_sent
        return elapsed >= timedelta(seconds=self.OTP_RESEND_SECONDS)

    # ==================== ENVOI ====================

    def send_otp(self, ip_address=None):
        """Génère un code à 6 chiffres, le stocke haché et l'envoie par email.

        Lève une exception si le SMTP échoue : l'appelant doit pouvoir dire à
        l'utilisateur que le code n'est PAS parti, plutôt que de le laisser
        attendre un email fantôme. Dans ce cas le code et l'anti-spam sont
        réarmés pour autoriser une nouvelle tentative immédiate.
        """
        self.ensure_one()
        code = ''.join(secrets.choice(string.digits) for _ in range(6))
        self.write({
            'otp_hash': self._hash(code),
            'expires_at': fields.Datetime.now() + timedelta(minutes=self.OTP_TTL_MINUTES),
            'attempts': 0,
            'last_sent': fields.Datetime.now(),
            'ip_address': ip_address or False,
        })
        try:
            self._send_otp_email(code)
        except Exception:
            # Le code n'est pas parti : ne pas le laisser « actif » en base,
            # et réarmer l'anti-spam pour permettre un nouvel essai tout de suite.
            self.write({'otp_hash': False, 'expires_at': False, 'last_sent': False})
            raise

    def _otp_email_from(self):
        """Expéditeur des emails OTP, déterministe.

        Sans `email_from` explicite, Odoo exige le couple `mail.catchall.domain`
        + `mail.default.from`, et échoue sinon — mais très en aval, sur un
        `assert` de `ir_mail_server.build_email` dont le message n'indique pas
        quel email a échoué. Constaté en production : cette méthode renvoyait
        `False` (ni paramètre, ni email de société renseignés) et l'envoi
        cassait dans les entrailles d'Odoo.

        On élargit donc la chaîne de repli aux conventions réellement en
        vigueur sur ce parc, et on échoue avec un message ACTIONNABLE si
        vraiment aucune adresse n'est disponible.
        """
        icp = self.env['ir.config_parameter'].sudo()

        def _usable(value):
            """Une adresse d'expéditeur n'a de sens que si elle contient '@'."""
            return value if value and '@' in value else False

        candidate = (
            # 1. Paramètre standard Odoo.
            _usable(icp.get_param('mail.default.from'))
            # 2. Email de la société courante.
            or _usable(self.env.company.sudo().email_formatted)
            # 3. Convention du parc (module `mail_force_smtp_from`) : c'est
            #    l'adresse réellement utilisée pour tous les envois sortants.
            or _usable(icp.get_param('mail.force.smtp.from'))
        )

        # 4. Dernier recours : le compte du serveur d'envoi configuré.
        if not candidate:
            server = self.env['ir.mail_server'].sudo().search(
                [], order='sequence, id', limit=1)
            candidate = _usable(server.smtp_user)

        if not candidate:
            raise UserError(_(
                "Aucune adresse d'expéditeur n'est configurée : impossible "
                "d'envoyer les codes de connexion.\n\n"
                "Renseignez l'une de ces valeurs :\n"
                "• l'email de la société (Paramètres → Sociétés), ou\n"
                "• le paramètre système « mail.default.from »."
            ))

        return candidate

    def _send_otp_email(self, code):
        """Envoie le code par email. L'échec SMTP remonte (raise_exception)."""
        self.ensure_one()
        email_to = self.user_id.email or self.user_id.login
        body = (
            "<p>Bonjour %s,</p>"
            "<p>Votre code de connexion à l'application Scanner de factures est :</p>"
            "<p style=\"font-size:28px;font-weight:bold;letter-spacing:4px\">%s</p>"
            "<p>Ce code expire dans %d minutes. Si vous n'êtes pas à l'origine "
            "de cette demande, ignorez cet email et signalez-le à votre "
            "administrateur.</p>"
        ) % (self.user_id.name or '', code, self.OTP_TTL_MINUTES)
        values = {
            'subject': "Votre code de connexion — Scanner de factures",
            'email_from': self._otp_email_from(),
            'email_to': email_to,
            'body_html': body,
            'auto_delete': True,
        }

        # Un code de connexion doit partir IMMÉDIATEMENT, sans exception.
        #
        # Deux modules du parc détournent l'envoi des emails :
        #   - `ivorycocoa_notification_manager` route selon la préférence du
        #     destinataire : en mode « digest », l'email est mis en file et
        #     agrégé dans un récapitulatif quotidien ; en mode « aucun email »,
        #     il est purement supprimé.
        #   - `mail_force_smtp_from` retire les destinataires ayant coupé les
        #     emails du système.
        #
        # Un OTP expire en quelques minutes : digéré, il arrive périmé ; supprimé,
        # l'utilisateur ne peut plus se connecter du tout. Ce n'est pas une
        # notification dont on peut se désabonner, c'est un identifiant.
        #
        # `force_send_to_blocked` est l'échappatoire prévue par ces modules
        # pour les envois prioritaires, et il court-circuite les deux routages.
        # La catégorie « validation » est posée en complément (elle maintient
        # le temps réel pour les destinataires en digest).
        #
        # Ces deux modules sont OPTIONNELS du point de vue du scanner : on ne
        # pose les champs que s'ils existent réellement dans le registre.
        MailMail = self.env['mail.mail'].sudo()
        if 'force_send_to_blocked' in MailMail._fields:
            values['force_send_to_blocked'] = True
        if 'notification_category' in MailMail._fields:
            values['notification_category'] = 'validation'

        mail = MailMail.create(values)
        # raise_exception : l'échec SMTP doit remonter immédiatement, sinon
        # l'API répondrait « code envoyé » à tort.
        mail.send(raise_exception=True)

    # ==================== VÉRIFICATION ====================

    def verify_otp(self, code):
        """Valide un code. Retourne True et consomme le code, sinon False.

        Le code est consommé (effacé) dès qu'il est validé : il ne peut donc
        pas servir deux fois.
        """
        self.ensure_one()
        if not self.otp_hash or not self.expires_at:
            return False
        if fields.Datetime.now() > self.expires_at:
            return False
        if self.attempts >= self.OTP_MAX_ATTEMPTS:
            return False
        if not secrets.compare_digest(self._hash(code), self.otp_hash):
            # Incrément non transactionnel volontaire : même si la requête
            # échoue plus loin, la tentative doit être comptée.
            self.attempts += 1
            return False
        self.write({'otp_hash': False, 'expires_at': False, 'attempts': 0})
        return True

    # ==================== MAINTENANCE ====================

    @api.model
    def cleanup_expired_otps(self):
        """Purge les lignes dormantes (cron).

        On ne supprime que les lignes sans code actif ET dont le dernier envoi
        est ancien : supprimer une ligne fraîchement consommée effacerait
        `last_sent`, et l'anti-spam serait contourné en redemandant un code
        juste après s'être connecté.
        """
        cutoff = fields.Datetime.now() - timedelta(days=1)
        expired = self.search([
            '|',
            ('expires_at', '<', fields.Datetime.now()),
            ('otp_hash', '=', False),
            ('last_sent', '<', cutoff),
        ])
        count = len(expired)
        expired.unlink()
        return count
