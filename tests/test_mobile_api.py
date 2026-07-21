# -*- coding: utf-8 -*-
"""
Tests unitaires pour l'API mobile REST
"""

import json
from unittest.mock import patch
from datetime import timedelta

from odoo import fields
from odoo.exceptions import UserError
from odoo.tests import HttpCase, tagged

from odoo.addons.invoice_qr_scanner.controllers import mobile_api


@tagged('post_install', '-at_install', 'invoice_qr_scanner', 'api')
class TestMobileAPI(HttpCase):
    """Tests pour l'API REST mobile."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        
        # Créer un groupe de sécurité si nécessaire
        cls.scanner_group = cls.env.ref('invoice_qr_scanner.group_invoice_scanner_user', raise_if_not_found=False)
        
        # Créer un utilisateur de test avec accès au scanner
        groups = [cls.env.ref('base.group_user').id]
        if cls.scanner_group:
            groups.append(cls.scanner_group.id)
        
        cls.test_user = cls.env['res.users'].create({
            'name': 'API Test User',
            'login': 'api_test_user',
            'password': 'test_password',
            'email': 'api_test@example.com',
            'groups_id': [(6, 0, groups)],
        })
        
        cls.valid_uuid = '019bd62c-467e-7000-82ac-45c8389c7f05'
        cls.valid_url = f'https://www.services.fne.dgi.gouv.ci/fr/verification/{cls.valid_uuid}'

    def _make_request(self, url, method='POST', data=None, headers=None):
        """Helper pour faire des requêtes HTTP."""
        if headers is None:
            headers = {'Content-Type': 'application/json'}
        
        if data is not None:
            data = json.dumps(data)
        
        if method == 'POST':
            return self.url_open(url, data=data, headers=headers)
        else:
            return self.url_open(url, headers=headers)

    def test_health_check(self):
        """Test de l'endpoint de santé."""
        response = self.url_open('/api/v1/invoice-scanner/health')
        
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.content)
        self.assertTrue(data.get('success'))
        self.assertEqual(data['data']['status'], 'healthy')

    def setUp(self):
        super().setUp()
        # Les compteurs de rate-limit vivent désormais en base. En mode test,
        # les requêtes HTTP partagent le curseur du test : les compteurs sont
        # donc annulés avec lui. On repart tout de même d'une table vide pour
        # qu'un résidu ne puisse pas provoquer un 429 sans rapport.
        self.env['invoice.scanner.rate.limit'].sudo().search([]).unlink()

        # Une base de test neuve n'a NI email de société, NI `mail.default.from`,
        # NI serveur d'envoi : l'expéditeur des OTP serait alors introuvable.
        # Les tests dédiés à la résolution de l'expéditeur écrasent ce réglage.
        self.env['ir.config_parameter'].sudo().set_param(
            'mail.default.from', 'no-reply@example.com')

    def test_request_otp_missing_login(self):
        """Demande de code sans identifiant."""
        response = self._make_request(
            '/api/v1/invoice-scanner/auth/request-otp',
            data={}
        )

        self.assertEqual(response.status_code, 400)
        data = json.loads(response.content)
        self.assertFalse(data.get('success'))
        self.assertEqual(data['error']['code'], 'VALIDATION_ERROR')

    def test_request_otp_unknown_account_is_indistinguishable(self):
        """Un compte inconnu reçoit la MÊME réponse qu'un compte valide.

        C'est la protection anti-énumération : la réponse ne doit pas révéler
        l'existence d'un identifiant. Aucun email ne doit partir.
        """
        with patch.object(
            type(self.env['invoice.scanner.login.otp']), '_send_otp_email'
        ) as send_mail:
            response = self._make_request(
                '/api/v1/invoice-scanner/auth/request-otp',
                data={'login': 'nonexistent_user'}
            )

        self.assertEqual(response.status_code, 200)
        data = json.loads(response.content)
        self.assertTrue(data.get('success'))
        send_mail.assert_not_called()

    def test_verify_otp_invalid_code(self):
        """Un code erroné est refusé."""
        response = self._make_request(
            '/api/v1/invoice-scanner/auth/verify-otp',
            data={'login': self.test_user.login, 'otp': '000000'}
        )

        self.assertEqual(response.status_code, 401)
        data = json.loads(response.content)
        self.assertFalse(data.get('success'))
        self.assertEqual(data['error']['code'], 'AUTH_FAILED')

    def test_otp_full_flow_returns_token(self):
        """Parcours complet : demande de code, saisie, obtention du token."""
        Otp = self.env['invoice.scanner.login.otp'].sudo()

        # Intercepter l'envoi pour récupérer le code en clair (il n'existe
        # qu'à cet instant : la base ne stocke que son hash).
        sent = {}

        def _capture(self_otp, code):
            sent['code'] = code

        with patch.object(type(Otp), '_send_otp_email', _capture):
            response = self._make_request(
                '/api/v1/invoice-scanner/auth/request-otp',
                data={'login': self.test_user.login}
            )
        self.assertEqual(response.status_code, 200)
        self.assertIn('code', sent, "Le code aurait dû être envoyé")

        response = self._make_request(
            '/api/v1/invoice-scanner/auth/verify-otp',
            data={'login': self.test_user.login, 'otp': sent['code']}
        )

        self.assertEqual(response.status_code, 200)
        data = json.loads(response.content)
        self.assertTrue(data.get('success'))
        self.assertTrue(data['data'].get('token'))
        self.assertEqual(data['data']['user']['login'], self.test_user.login)

    def test_otp_email_bypasses_digest_routing(self):
        """L'email d'OTP est marqué pour échapper au routage des notifications.

        Régression protégée, constatée en production : tous les utilisateurs
        du parc étant en mode « digest quotidien »,
        `ivorycocoa_notification_manager` retirait le destinataire de l'email
        et mettait le code en file d'attente. Le code, valable 10 minutes,
        n'arrivait que dans le récapitulatif du lendemain — donc jamais à
        temps. Plus personne ne pouvait se connecter.

        Ces champs viennent de modules optionnels : on ne vérifie que ceux
        réellement présents dans le registre.
        """
        Otp = self.env['invoice.scanner.login.otp'].sudo()
        otp = Otp._get_or_create(self.test_user)

        # Neutraliser l'envoi SMTP : c'est le MARQUAGE qu'on éprouve ici.
        with patch.object(type(self.env['mail.mail']), 'send'):
            otp._send_otp_email('123456')

        mail = self.env['mail.mail'].sudo().search(
            [('email_to', '=', self.test_user.email)], order='id desc', limit=1)
        self.assertTrue(mail, "L'email d'OTP doit avoir été créé")

        fields_ = self.env['mail.mail']._fields
        if 'force_send_to_blocked' in fields_:
            self.assertTrue(
                mail.force_send_to_blocked,
                "L'OTP doit forcer l'envoi : c'est un identifiant, pas une "
                "notification dont on peut se désabonner")
        if 'notification_category' in fields_:
            self.assertEqual(mail.notification_category, 'validation')

    def test_otp_sender_falls_back_when_company_email_missing(self):
        """L'expéditeur est résolu même sans email de société ni paramètre.

        Reproduit la panne de production : `mail.default.from` absent ET email
        de société vide. `_otp_email_from` renvoyait alors `False`, et Odoo
        échouait très en aval sur l'assertion de `build_email` — message
        cryptique, sans indiquer l'email fautif.
        """
        icp = self.env['ir.config_parameter'].sudo()
        icp.set_param('mail.default.from', '')
        self.env.company.sudo().email = False
        icp.set_param('mail.force.smtp.from', 'expediteur@ivorycocoa.ci')

        Otp = self.env['invoice.scanner.login.otp'].sudo()
        sender = Otp._get_or_create(self.test_user)._otp_email_from()

        self.assertEqual(sender, 'expediteur@ivorycocoa.ci',
                         "La convention du parc doit servir de repli")

    def test_otp_sender_missing_raises_actionable_error(self):
        """Sans AUCUNE adresse disponible, l'erreur doit être exploitable.

        Mieux vaut un message qui nomme le réglage à corriger qu'un
        `AssertionError` surgi des entrailles du serveur de mail.
        """
        icp = self.env['ir.config_parameter'].sudo()
        icp.set_param('mail.default.from', '')
        icp.set_param('mail.force.smtp.from', '')
        self.env.company.sudo().email = False
        self.env['ir.mail_server'].sudo().search([]).unlink()

        Otp = self.env['invoice.scanner.login.otp'].sudo()
        otp = Otp._get_or_create(self.test_user)

        with self.assertRaises(UserError) as ctx:
            otp._otp_email_from()

        self.assertIn('mail.default.from', str(ctx.exception),
                      "L'erreur doit nommer le réglage à renseigner")

    def test_otp_is_single_use(self):
        """Un code déjà consommé ne peut pas resservir."""
        Otp = self.env['invoice.scanner.login.otp'].sudo()
        otp = Otp._get_or_create(self.test_user)

        with patch.object(type(Otp), '_send_otp_email'):
            otp.send_otp()
        # Rejouer la génération pour connaître le code : on écrit le hash d'un
        # code choisi, ce que seule la base sait vérifier.
        otp.write({'otp_hash': Otp._hash('123456')})

        self.assertTrue(otp.verify_otp('123456'))
        self.assertFalse(otp.verify_otp('123456'))

    def test_rate_limit_state_lives_in_database(self):
        """Le compteur est persisté en base, et non en mémoire du processus.

        C'est tout l'intérêt du portage : l'ancien compteur était un dict de
        module, donc propre à chaque worker — un quota de 5 en autorisait
        réellement 5 × N. Un état stocké en base est par construction partagé
        par tous les workers, qui lisent la même ligne sous verrou.

        (Ce test ne peut pas lancer de vrais workers concurrents ; il vérifie
        la propriété qui rend le partage possible : la persistance.)
        """
        RateLimit = self.env['invoice.scanner.rate.limit'].sudo()
        key = 'test:persisted:counter'

        for i in range(3):
            limited, _ = RateLimit.check_and_record(key, 3, 300, 300)
            self.assertFalse(limited, "Requête %s refusée à tort" % i)

        # Les hits sont bien en base, relisibles par n'importe quel processus.
        # `check_and_record` écrit en SQL brut (pour le verrou FOR UPDATE) :
        # le cache ORM doit être invalidé avant toute relecture.
        self.env.invalidate_all()
        bucket = RateLimit.search([('key', '=', key)], limit=1)
        self.assertTrue(bucket, "Le compteur doit exister en base")
        self.assertEqual(len(json.loads(bucket.events_json)), 3)

        # Le 4e hit dépasse le quota et pose un blocage, lui aussi persisté.
        limited, remaining = RateLimit.check_and_record(key, 3, 300, 300)
        self.assertTrue(limited)
        # `remaining` vaut la durée de blocage demandée : l'asserter > 0
        # reviendrait à écrire `assertGreater(300, 0)`.
        self.assertEqual(remaining, 300)
        self.env.invalidate_all()
        self.assertTrue(bucket.blocked_until, "Le blocage doit être persisté")

    def test_rate_limit_window_slides(self):
        """Les hits sortis de la fenêtre ne comptent plus.

        Deux précautions indispensables, sans lesquelles ce test ne peut PAS
        échouer :

        1. On injecte AUTANT d'horodatages périmés que le quota (2 pour 2).
           Avec un seul, la condition du modèle (`len(events) >= max_requests`)
           reste fausse même si le filtrage de fenêtre était entièrement
           supprimé — le test serait vert sur du code cassé.
        2. On force l'écriture ORM en base (`flush_recordset`) : le modèle
           relit `events_json` en SQL BRUT, et une écriture ORM différée ne
           serait pas encore visible. Le code testé lirait alors l'état
           d'avant, et les deux défauts se masqueraient mutuellement.
        """
        RateLimit = self.env['invoice.scanner.rate.limit'].sudo()
        key = 'test:sliding:window'

        limited, _ = RateLimit.check_and_record(key, 2, 300, 300)
        self.assertFalse(limited)

        # Vieillir artificiellement DEUX hits au-delà de la fenêtre : sans le
        # filtrage, le quota serait atteint et la requête suivante refusée.
        bucket = RateLimit.search([('key', '=', key)], limit=1)
        old = (fields.Datetime.now() - timedelta(seconds=3600)).isoformat()
        bucket.write({'events_json': json.dumps([old, old])})
        bucket.flush_recordset(['events_json'])

        limited, _ = RateLimit.check_and_record(key, 2, 300, 300)
        self.assertFalse(limited, "Un hit expiré ne doit plus compter")

        # Et le compteur ne conserve que le hit récent : la purge a bien eu lieu.
        self.env.invalidate_all()
        self.assertEqual(len(json.loads(bucket.events_json)), 1)

    def test_otp_request_blocked_after_quota(self):
        """Au-delà du quota par compte, la demande de code est refusée en 429."""
        Otp = self.env['invoice.scanner.login.otp'].sudo()
        max_requests = mobile_api.RL_OTP_REQUEST_LOGIN[0]

        with patch.object(type(Otp), '_send_otp_email'):
            for i in range(max_requests):
                # Neutraliser l'anti-spam des 60 s pour n'éprouver que le quota.
                Otp.search([('user_id', '=', self.test_user.id)]).write(
                    {'last_sent': False})
                allowed = self._make_request(
                    '/api/v1/invoice-scanner/auth/request-otp',
                    data={'login': self.test_user.login}
                )
                # Vérifier chaque requête du quota : le rate-limit est appliqué
                # AVANT la résolution du compte, donc un endpoint entièrement
                # en panne (500 à chaque appel) compterait quand même ses hits
                # et la requête suivante renverrait bien 429 — ce test serait
                # vert sur un parcours OTP totalement cassé.
                self.assertEqual(allowed.status_code, 200,
                                 "Requête %s du quota refusée à tort" % i)

            response = self._make_request(
                '/api/v1/invoice-scanner/auth/request-otp',
                data={'login': self.test_user.login}
            )

        self.assertEqual(response.status_code, 429)
        data = json.loads(response.content)
        self.assertEqual(data['error']['code'], 'TOO_MANY_ATTEMPTS')

    def test_otp_attempts_are_capped(self):
        """Au-delà du quota de tentatives, le code est mort."""
        Otp = self.env['invoice.scanner.login.otp'].sudo()
        otp = Otp._get_or_create(self.test_user)

        with patch.object(type(Otp), '_send_otp_email'):
            otp.send_otp()
        otp.write({'otp_hash': Otp._hash('123456')})

        for _ in range(Otp.OTP_MAX_ATTEMPTS):
            self.assertFalse(otp.verify_otp('999999'))

        # Même le BON code est désormais refusé.
        self.assertFalse(otp.verify_otp('123456'))

    def test_scan_without_auth(self):
        """Test de scan sans authentification."""
        # La route s'appelle `scan-with-data` : `/scan` n'a jamais existé et
        # renvoyait un 404, ce qui masquait le fait que ce test ne vérifiait
        # rien de l'authentification.
        response = self._make_request(
            '/api/v1/invoice-scanner/scan-with-data',
            data={'qr_url': self.valid_url}
        )
        
        self.assertEqual(response.status_code, 401)
        data = json.loads(response.content)
        self.assertFalse(data.get('success'))
        self.assertEqual(data['error']['code'], 'AUTH_REQUIRED')

    def _assert_auth_required(self, url):
        """Vérifier qu'une route GET exige bien un token.

        Le seul code HTTP ne suffit pas : un 401 émis par le framework, ou
        pour un autre motif (`AUTH_INVALID`), satisferait l'assertion. On
        contrôle donc aussi le code d'erreur applicatif.
        """
        response = self.url_open(url)

        self.assertEqual(response.status_code, 401)
        data = json.loads(response.content)
        self.assertFalse(data.get('success'))
        self.assertEqual(data['error']['code'], 'AUTH_REQUIRED')

    def test_history_without_auth(self):
        """L'historique exige une authentification."""
        self._assert_auth_required('/api/v1/invoice-scanner/history')

    def test_stats_without_auth(self):
        """Les statistiques exigent une authentification."""
        self._assert_auth_required('/api/v1/invoice-scanner/stats')


@tagged('post_install', '-at_install', 'invoice_qr_scanner', 'api')
class TestAPIHelpers(HttpCase):
    """Tests pour les fonctions helper de l'API."""

    def test_api_response_format(self):
        """Format standard des réponses : structure ET valeurs.

        La seule présence des clés ne prouve rien — une réponse d'échec porte
        exactement les mêmes. On vérifie donc le code HTTP et la valeur de
        `success`.
        """
        response = self.url_open('/api/v1/invoice-scanner/health')

        self.assertEqual(response.status_code, 200)
        data = json.loads(response.content)
        self.assertTrue(data['success'])
        self.assertIn('api_version', data)
        self.assertIn('timestamp', data)

    def test_api_error_format(self):
        """Test du format des erreurs API."""
        response = self._make_request(
            '/api/v1/invoice-scanner/auth/request-otp',
            data={}
        )
        data = json.loads(response.content)

        # Vérifier la structure d'erreur
        self.assertIn('success', data)
        self.assertFalse(data['success'])
        self.assertIn('error', data)
        self.assertIn('code', data['error'])
        self.assertIn('message', data['error'])

    def _make_request(self, url, method='POST', data=None, headers=None):
        """Helper pour faire des requêtes HTTP."""
        if headers is None:
            headers = {'Content-Type': 'application/json'}
        
        if data is not None:
            data = json.dumps(data)
        
        return self.url_open(url, data=data, headers=headers)


# NOTE — La classe `TestAPIValidation` a été retirée le 2026-07-21.
#
# Ses deux tests interrogeaient `/api/v1/invoice-scanner/test-dgi`, une route
# qui n'existe pas : ils recevaient un 404 et interprétaient la réponse comme
# significative. L'un d'eux n'affirmait d'ailleurs rien (« le résultat dépend
# de l'implémentation »).
#
# Un test de remplacement vérifiant qu'une route inconnue renvoie 404 a été
# écrit puis retiré à son tour : il éprouvait le routeur d'Odoo, pas ce module,
# et ne pouvait donc signaler aucune régression ici.
#
# La validation des entrées est couverte là où elle porte sur du code de ce
# module : `TestMobileAPI.test_request_otp_missing_login` (400 sur champ
# manquant), `TestAPIHelpers.test_api_error_format` (forme des erreurs), et
# `TestDGIExtraction` pour l'extraction d'UUID — y compris
# `test_extract_uuid_does_not_validate_domain`, qui documente l'absence de
# contrôle du domaine d'origine.
