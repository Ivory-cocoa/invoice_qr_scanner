# -*- coding: utf-8 -*-
"""Profil « Gestionnaire OT » dans l'API de l'application mobile.

Il consulte les factures déjà scannées (pour les rattacher à des OT) ; il ne
vérifie pas les factures — ni création de scan, ni contrôle de doublon — et
ne les traite pas. La règle est tenue par le serveur, quel que soit l'APK.
"""

import json
from unittest.mock import patch

from odoo import fields
from odoo.tests import HttpCase, tagged

from .test_scan_desk import ensure_xof

UUID = '01a1fd85-6adb-7dd8-b0ee-55c5d0732ece'
URL = 'https://www.services.fne.dgi.gouv.ci/fr/verification/' + UUID
OTHER_URL = ('https://www.services.fne.dgi.gouv.ci/fr/verification/'
             '01a20922-f0bd-7000-bc4d-44aa101a80e1')
API = '/api/v1/invoice-scanner'


@tagged('post_install', '-at_install', 'invoice_qr_scanner')
class TestOtManagerProfile(HttpCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        ensure_xof(cls.env)
        cls.ot_manager = cls._user('ot_only', 'group_invoice_scanner_ot_manager')
        cls.verificateur = cls._user('verif_only', 'group_invoice_scanner_verificateur')
        cls.both = cls._user(
            'ot_and_verif', 'group_invoice_scanner_ot_manager',
            'group_invoice_scanner_verificateur')
        cls.scan = cls.env['invoice.scan.record'].create({
            'qr_uuid': UUID, 'qr_url': URL,
            'supplier_name': 'QUINCAILLERIE EXEMPLE',
            'invoice_number_dgi': '2603236T26000000174',
            'invoice_date': fields.Date.today(),
            'amount_ttc': 2183000, 'state': 'done', 'duplicate_count': 2,
            'scanned_by': cls.verificateur.id,
        })

    @classmethod
    def _user(cls, login, *groups):
        return cls.env['res.users'].create({
            'name': login, 'login': login, 'email': '%s@example.com' % login,
            'groups_id': [(6, 0, [cls.env.ref('base.group_user').id] + [
                cls.env.ref('invoice_qr_scanner.%s' % g).id for g in groups])],
        })

    def _token(self, user):
        """Jeton d'API obtenu par le parcours OTP réel."""
        Otp = self.env['invoice.scanner.login.otp'].sudo()
        sent = {}

        def _capture(self_otp, code, app_label=None):
            sent['code'] = code

        headers = {'Content-Type': 'application/json'}
        with patch.object(type(Otp), '_send_otp_email', _capture):
            self.url_open(API + '/auth/request-otp',
                          data=json.dumps({'login': user.login}), headers=headers)
        response = self.url_open(
            API + '/auth/verify-otp',
            data=json.dumps({'login': user.login, 'otp': sent['code']}),
            headers=headers)
        data = json.loads(response.content)['data']
        return data['token'], data

    def _post(self, token, path, body):
        response = self.url_open(
            API + path, data=json.dumps(body),
            headers={'Content-Type': 'application/json',
                     'Authorization': 'Bearer %s' % token})
        return response.status_code, json.loads(response.content)

    # ------------------------------------------------------------------

    def test_role_sent_to_the_application(self):
        _token, data = self._token(self.ot_manager)
        self.assertEqual(data['user']['role'], 'ot_manager')
        self.assertEqual(data['user']['role_label'], 'Gestionnaire OT')
        _token, data = self._token(self.both)
        self.assertEqual(data['user']['role'], 'verificateur')
        self.assertTrue(data['user']['is_ot_manager'])

    def test_ot_manager_cannot_verify_or_process(self):
        """Aucun chemin de vérification, de doublon ou de traitement."""
        token, _data = self._token(self.ot_manager)
        calls = [
            ('/scan', {'qr_url': OTHER_URL}),
            ('/scan-with-data', {'qr_url': OTHER_URL, 'supplier_name': 'X',
                                 'invoice_number_dgi': 'N1', 'amount_ttc': 1000}),
            ('/check', {'qr_url': URL}),
            ('/report-duplicate', {'qr_url': URL}),
            ('/sync', {'scans': [{'qr_url': OTHER_URL}]}),
            ('/sync-parsed', {'scans': [{'qr_url': OTHER_URL}]}),
            ('/errors/bulk-retry', {'record_ids': [self.scan.id]}),
            ('/errors/%s/retry' % self.scan.id, {}),
            ('/scan-to-process', {'qr_url': URL}),
            ('/mark-processed/%s' % self.scan.id, {}),
            ('/bulk-mark-processed', {'record_ids': [self.scan.id]}),
        ]
        before = self.env['invoice.scan.record'].search_count([])
        for path, body in calls:
            status, payload = self._post(token, path, body)
            self.assertEqual(status, 403, path)
            self.assertEqual(payload['error']['code'], 'ACCESS_DENIED', path)
        self.scan.invalidate_recordset()
        self.assertEqual(self.env['invoice.scan.record'].search_count([]), before)
        self.assertEqual(self.scan.duplicate_count, 2)
        self.assertEqual(self.scan.state, 'done')

    def test_lookup_finds_a_scanned_invoice_without_side_effect(self):
        token, _data = self._token(self.ot_manager)
        for text in (URL, URL.upper(), UUID, '  %s  ' % URL):
            status, payload = self._post(token, '/scan/lookup', {'qr_url': text})
            self.assertEqual(status, 200, text)
            data = payload['data']
            self.assertTrue(data['found'])
            self.assertEqual(data['record']['id'], self.scan.id)
            self.assertEqual(data['record']['invoice_number_dgi'], '2603236T26000000174')
            # Rien sur les doublons ne sort de cette route.
            self.assertFalse([k for k in data['record'] if 'duplicate' in k])
        self.scan.invalidate_recordset()
        self.assertEqual(self.scan.duplicate_count, 2)
        self.assertFalse(self.scan.last_duplicate_attempt)

    def test_lookup_of_an_invoice_never_scanned(self):
        token, _data = self._token(self.ot_manager)
        before = self.env['invoice.scan.record'].search_count([])
        with patch('odoo.addons.invoice_qr_scanner.models.fne_api.requests.get',
                   side_effect=AssertionError("La DGI ne doit pas être appelée")):
            status, payload = self._post(token, '/scan/lookup', {'qr_url': OTHER_URL})
        self.assertEqual(status, 200)
        self.assertFalse(payload['data']['found'])
        self.assertEqual(payload['data']['reason'], 'not_scanned')
        self.assertNotIn('record', payload['data'])
        # Le message dit que la facture n'existe pas et oriente vers le
        # secrétariat, qui la vérifiera.
        self.assertIn("n'existe pas encore", payload['message'])
        self.assertIn('secrétariat', payload['message'])
        # Le secrétariat est prévenu : une ligne, et une seule, l'attend.
        self.assertTrue(payload['data']['secretariat_notified'])
        Pending = self.env['invoice.scan.pending.invoice']
        other_uuid = OTHER_URL.rsplit('/', 1)[1]
        pending = Pending.search([('qr_uuid', '=', other_uuid)])
        self.assertEqual(len(pending), 1)
        self.assertEqual(pending.requested_by, self.ot_manager)
        self.assertEqual(pending.origin, 'app')
        self._post(token, '/scan/lookup', {'qr_url': OTHER_URL})
        pending.invalidate_recordset()
        self.assertEqual(Pending.search_count([('qr_uuid', '=', other_uuid)]), 1)
        self.assertEqual(pending.request_count, 2)
        self.assertEqual(self.env['invoice.scan.record'].search_count([]), before)

    def test_lookup_of_a_scan_in_error(self):
        self.scan.state = 'error'
        token, _data = self._token(self.ot_manager)
        status, payload = self._post(token, '/scan/lookup', {'qr_url': URL})
        self.assertEqual(status, 200)
        self.assertFalse(payload['data']['found'])
        self.assertEqual(payload['data']['reason'], 'not_ready')
        self.assertIn('secrétariat', payload['message'])
        self.scan.invalidate_recordset()
        self.assertEqual(self.scan.state, 'error')
        # Le secrétariat l'a déjà entre les mains : pas de nouvelle demande.
        self.assertFalse(payload['data']['secretariat_notified'])
        self.assertFalse(self.env['invoice.scan.pending.invoice'].search(
            [('qr_uuid', '=', UUID)]))

    def test_lookup_rejects_other_contents(self):
        token, _data = self._token(self.ot_manager)
        for body in ({'qr_url': 'ICP-OT:S95|abc'}, {'qr_url': ''}, {},
                     {'qr_url': None}, {'qr_url': 12345}):
            status, _payload = self._post(token, '/scan/lookup', body)
            self.assertEqual(status, 400, body)

    def test_lookup_is_reserved_to_ot_managers(self):
        token, _data = self._token(self.verificateur)
        status, _payload = self._post(token, '/scan/lookup', {'qr_url': URL})
        self.assertEqual(status, 403)

    def test_cumulated_profiles_keep_the_verifier_gestures(self):
        """Gestionnaire OT ET Vérificateur : le contrôle de doublon reste."""
        token, _data = self._token(self.both)
        status, payload = self._post(token, '/check', {'qr_url': URL})
        self.assertEqual(status, 200)
        self.assertTrue(payload['data']['exists'])
        status, payload = self._post(token, '/scan/lookup', {'qr_url': URL})
        self.assertEqual(status, 200)
        self.assertTrue(payload['data']['found'])

    def test_verifier_is_not_affected(self):
        token, _data = self._token(self.verificateur)
        status, payload = self._post(token, '/check', {'qr_url': URL})
        self.assertEqual(status, 200)
        self.assertTrue(payload['data']['exists'])

    def test_secretariat_label(self):
        """Vérifie ET traite, sans être Responsable : c'est le secrétariat."""
        secretary = self._user(
            'secretary', 'group_invoice_scanner_verificateur',
            'group_invoice_scanner_traiteur')
        _token, data = self._token(secretary)
        self.assertEqual(data['user']['role'], 'manager')
        self.assertEqual(data['user']['role_label'], 'Secrétariat')
        boss = self._user('boss', 'group_invoice_scanner_manager')
        _token, data = self._token(boss)
        self.assertEqual(data['user']['role_label'], 'Responsable')
