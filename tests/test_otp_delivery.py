# -*- coding: utf-8 -*-
"""Le code de connexion doit partir, quel que soit le mode de réception d'emails.

RÉGRESSION : ``ivorycocoa_notification_manager`` intercepte tous les emails
système dans ``mail.mail._send()`` et les regroupe dans un récapitulatif
quotidien pour les utilisateurs en mode digest — le mode par défaut. Le code
OTP, créé sans catégorie, était donc mis en file d'attente : l'API répondait
« code envoyé » et l'utilisateur ne recevait jamais rien.

Ces tests restent valides quand le gestionnaire de notifications n'est pas
installé (le contexte de catégorisation est alors simplement ignoré).
"""

from contextlib import contextmanager
from unittest.mock import patch

from odoo.exceptions import UserError
from odoo.tests import TransactionCase, tagged

SMTP_PATH = 'odoo.addons.base.models.ir_mail_server.IrMailServer'


@tagged('post_install', '-at_install', 'invoice_qr_scanner', 'api')
class TestOtpDelivery(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.user = cls.env['res.users'].with_context(
            no_reset_password=True).create({
                'name': 'OTP Delivery', 'login': 'iqs_otp_delivery',
                'email': 'iqs.otp@test.icp.ci',
            })
        cls.Otp = cls.env['invoice.scanner.login.otp'].sudo()

    @contextmanager
    def _mock_smtp(self):
        delivered = []

        def _send_email(self_srv, message, *args, **kwargs):
            delivered.append(message['To'])
            return '<mocked-by-test@icp>'

        with patch(SMTP_PATH + '.connect', lambda *a, **kw: None), \
                patch(SMTP_PATH + '.send_email', _send_email):
            yield delivered

    def _set_email_mode(self, mode):
        """Applique un mode de réception si le gestionnaire est installé."""
        if 'icp_email_mode' not in self.env['res.users']._fields:
            return False
        self.user.icp_email_mode = mode
        return True

    def test_otp_delivered_whatever_the_email_mode(self):
        for mode in ('realtime', 'digest_daily', 'digest_weekly', 'none'):
            if not self._set_email_mode(mode):
                self.skipTest("Gestionnaire de notifications ICP non installé.")
            otp = self.Otp._get_or_create(self.user)
            otp.write({'last_sent': False})  # neutralise l'anti-spam
            with self._mock_smtp() as delivered:
                otp.send_otp()
            self.assertTrue(
                delivered,
                "Le code doit partir immédiatement en mode « %s »" % mode)
            self.assertIn(self.user.email, delivered[0])

    def test_otp_send_failure_is_reported_not_swallowed(self):
        """Un code non délivré doit lever, pour ne pas mentir à l'application."""
        otp = self.Otp._get_or_create(self.user)
        otp.write({'last_sent': False})

        def _blocked(mail_self, *args, **kwargs):
            """Simule un filtrage tiers : mail annulé, sans exception."""
            mail_self.write({'state': 'cancel',
                             'failure_reason': 'Filtré par un test'})
            return True

        with patch('odoo.addons.mail.models.mail_mail.MailMail.send', _blocked):
            with self.assertRaises(UserError):
                otp.send_otp()
        # Le code est réarmé : l'utilisateur peut redemander immédiatement.
        self.assertFalse(otp.otp_hash)
        self.assertFalse(otp.last_sent)
