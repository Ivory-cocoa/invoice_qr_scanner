# -*- coding: utf-8 -*-
"""Poste de scan à la douchette.

Trois niveaux : la lecture du texte tapé par la douchette (fonction pure),
le traitement serveur d'une lecture (DGI simulée, jamais de réseau), puis
l'écran lui-même, piloté dans un navigateur avec de vraies frappes clavier.
"""

from unittest.mock import patch

import requests

from odoo.tests import HttpCase, TransactionCase, new_test_user, tagged

from ..models.fne_api import FneApiError
from ..models.scanner_input import (
    QWERTY_ON_AZERTY_MAC, QWERTY_ON_AZERTY_WINDOWS, SCANNER_TEST_TEXT,
    check_scanner_test, clean_scan, parse_dgi_qr)
from .test_fne_api import FNE_PAYLOAD, FNE_REFUND_PAYLOAD, _FakeResponse

UUID = '019bd62c-467e-7000-82ac-45c8389c7f05'
URL = 'https://www.services.fne.dgi.gouv.ci/fr/verification/' + UUID
REQUESTS_GET = 'odoo.addons.invoice_qr_scanner.models.fne_api.requests.get'


def typed_on_azerty(text, table):
    """Ce que le poste reçoit quand une douchette QWERTY « tape » ``text``."""
    typed = {wanted: received for received, wanted in table.items()}
    return ''.join(typed.get(char, char) for char in text)


def ensure_xof(env):
    Currency = env['res.currency'].with_context(active_test=False)
    xof = Currency.search([('name', '=', 'XOF')], limit=1)
    if xof:
        xof.active = True
    else:
        Currency.create({'name': 'XOF', 'symbol': 'FCFA', 'rounding': 1})


@tagged('post_install', '-at_install', 'invoice_qr_scanner', 'scan_desk')
class TestScannerInput(TransactionCase):
    """Lecture du texte tapé par la douchette (sans base)."""

    def test_plain_url(self):
        self.assertEqual(parse_dgi_qr(URL), {
            'qr_uuid': UUID, 'qr_url': URL, 'layout_fixed': False})

    def test_suffixes_and_case(self):
        """Retour chariot, tabulation, majuscules (verrouillage) : tolérés."""
        parsed = parse_dgi_qr('\x02' + URL.upper() + '\r\n\t')
        self.assertEqual(parsed['qr_uuid'], UUID)
        self.assertFalse(parsed['layout_fixed'])

    def test_qwerty_scanner_on_azerty_windows(self):
        mangled = typed_on_azerty(URL, QWERTY_ON_AZERTY_WINDOWS)
        self.assertNotIn('fne.dgi', mangled)
        self.assertEqual(parse_dgi_qr(mangled), {
            'qr_uuid': UUID, 'qr_url': URL, 'layout_fixed': True})

    def test_qwerty_scanner_on_azerty_mac(self):
        mangled = typed_on_azerty(URL, QWERTY_ON_AZERTY_MAC)
        self.assertIn('§', mangled)
        self.assertEqual(parse_dgi_qr(mangled), {
            'qr_uuid': UUID, 'qr_url': URL, 'layout_fixed': True})

    def test_not_a_dgi_qr(self):
        for text in (
                '', '   ', UUID,  # un UUID seul ne prouve rien
                'https://example.com/fr/verification/' + UUID,
                'https://www.services.fne.dgi.gouv.ci/fr/verification/abc',
                'SC082343-2024-2-149/2/25/2/SC082343/BAKOUBLY/M08/x/y/z/a/327/36500',
                URL + 'x' * 2000):
            self.assertIsNone(parse_dgi_qr(text), text[:60])

    def test_scanner_test_qr(self):
        self.assertEqual(check_scanner_test(SCANNER_TEST_TEXT + '\r'), 'ok')
        self.assertEqual(check_scanner_test(SCANNER_TEST_TEXT.swapcase()),
                         'caps')
        for table in (QWERTY_ON_AZERTY_WINDOWS, QWERTY_ON_AZERTY_MAC):
            mangled = typed_on_azerty(SCANNER_TEST_TEXT, table)
            self.assertNotEqual(mangled, SCANNER_TEST_TEXT)
            self.assertEqual(check_scanner_test(mangled), 'qwerty')
        self.assertIsNone(check_scanner_test('autre chose'))
        self.assertIsNone(check_scanner_test(URL))

    def test_clean_scan(self):
        self.assertEqual(clean_scan('\x1d abc\r\n'), 'abc')
        self.assertEqual(clean_scan(None), '')
        self.assertEqual(clean_scan('x' * 2001), '')


@tagged('post_install', '-at_install', 'invoice_qr_scanner', 'scan_desk')
class TestScanDesk(TransactionCase):
    """Traitement serveur d'une lecture."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        ensure_xof(cls.env)
        cls.verifier = new_test_user(
            cls.env, login='desk_verifier', groups='base.group_user,'
            'invoice_qr_scanner.group_invoice_scanner_verificateur')
        cls.other_verifier = new_test_user(
            cls.env, login='desk_verifier_2', groups='base.group_user,'
            'invoice_qr_scanner.group_invoice_scanner_verificateur')
        cls.processor = new_test_user(
            cls.env, login='desk_processor', groups='base.group_user,'
            'invoice_qr_scanner.group_invoice_scanner_traiteur')
        cls.ot_manager = new_test_user(
            cls.env, login='desk_ot_manager', groups='base.group_user,'
            'invoice_qr_scanner.group_invoice_scanner_ot_manager')
        cls.manager = new_test_user(
            cls.env, login='desk_manager', groups='base.group_user,'
            'invoice_qr_scanner.group_invoice_scanner_manager')
        cls.reader = new_test_user(
            cls.env, login='desk_reader', groups='base.group_user,'
            'invoice_qr_scanner.group_invoice_scanner_user')
        cls.Desk = cls.env['invoice.scan.desk']
        cls.ScanRecord = cls.env['invoice.scan.record']

    def _scan(self, text, user=None, mode=None, **response):
        options = {'modes': {'dgi': mode}} if mode else None
        with patch(REQUESTS_GET, return_value=_FakeResponse(**response)) as get:
            card = self.Desk.with_user(user or self.verifier).desk_scan(
                text, options)
        return card, get

    def _modes(self, user):
        init = self.Desk.with_user(user).desk_init()
        dgi = next(k for k in init['kinds'] if k['key'] == 'dgi')
        self.assertEqual(dgi['allowed'], bool(dgi['modes']))
        return [mode['key'] for mode in dgi['modes']]

    def _records(self, uuid=UUID):
        return self.ScanRecord.search([('qr_uuid', '=', uuid)])

    def test_modes_follow_the_profile(self):
        """Même geste que dans l'application, profil par profil."""
        self.assertEqual(self._modes(self.verifier), ['create'])
        self.assertEqual(self._modes(self.ot_manager), ['lookup'])
        self.assertEqual(self._modes(self.processor), ['process'])
        self.assertEqual(self._modes(self.manager), ['create', 'process', 'lookup'])
        self.assertEqual(self._modes(self.reader), [])
        self.assertFalse(self.Desk.with_user(self.reader).desk_init()['can_scan'])

    def test_scan_creates_the_invoice(self):
        card, get = self._scan(URL + '\r')
        self.assertEqual(card['status'], 'success', card)
        self.assertEqual(card['kind'], 'dgi')
        self.assertEqual(get.call_count, 1)
        record = self._records()
        self.assertEqual(len(record), 1)
        self.assertEqual(record.state, 'done')
        self.assertEqual(record.scanned_by, self.verifier)
        self.assertEqual(record.supplier_name, 'TRANSITAIRE EXEMPLE')
        self.assertTrue(record.invoice_id)
        self.assertEqual(record.invoice_id.move_type, 'in_invoice')
        values = {line['label']: line['value'] for line in card['lines']}
        self.assertEqual(values['Fournisseur'], 'TRANSITAIRE EXEMPLE')
        self.assertEqual(values['N° DGI'], '2502298K26000000003')
        self.assertIn('1', values['Montant TTC'])
        # Le Vérificateur peut ouvrir son propre scan
        self.assertEqual(card['actions'][0]['action']['res_id'], record.id)
        self.assertFalse(card['warnings'])

    def test_refund_is_recorded_as_a_refund(self):
        uuid = FNE_REFUND_PAYLOAD['token']
        card, _get = self._scan(URL.replace(UUID, uuid),
                                payload=FNE_REFUND_PAYLOAD)
        self.assertEqual(card['status'], 'success', card)
        self.assertEqual(card['title'], "Avoir enregistré")
        record = self._records(uuid)
        self.assertEqual(record.document_type, 'refund')
        self.assertEqual(record.invoice_id.move_type, 'in_refund')

    def test_second_scan_is_a_duplicate_and_creates_nothing(self):
        self._scan(URL)
        card, get = self._scan(URL.upper(), user=self.other_verifier)
        self.assertEqual(card['status'], 'duplicate', card)
        # La DGI n'est pas interrogée pour une facture déjà connue
        self.assertEqual(get.call_count, 0)
        record = self._records()
        self.assertEqual(len(record), 1)
        self.assertEqual(record.duplicate_count, 1)
        self.assertEqual(record.last_duplicate_user_id, self.other_verifier)
        self.assertIn(self.verifier.name, card['message'])
        # Le bouton d'ouverture suit le droit de lecture réel de la fiche
        readable = self.ScanRecord.with_user(self.other_verifier).search(
            [('id', '=', record.id)])
        self.assertEqual(bool(card['actions']), bool(readable))

    def test_qwerty_scanner_is_fixed_and_reported(self):
        card, _get = self._scan(
            typed_on_azerty(URL, QWERTY_ON_AZERTY_WINDOWS))
        self.assertEqual(card['status'], 'success', card)
        self.assertTrue(card['warnings'])
        self.assertEqual(self._records().qr_url, URL)

    def test_dgi_down_records_nothing(self):
        with patch(REQUESTS_GET, side_effect=requests.exceptions.Timeout()):
            card = self.Desk.with_user(self.verifier).desk_scan(URL)
        self.assertEqual(card['status'], 'error', card)
        self.assertEqual(card['kind'], 'dgi')
        self.assertTrue(card['form'])
        self.assertFalse(self._records())
        # … et le même QR repasse dès que la DGI répond
        card, _get = self._scan(URL)
        self.assertEqual(card['status'], 'success', card)

    def test_unknown_invoice_at_dgi(self):
        card, _get = self._scan(URL, status_code=404)
        self.assertEqual(card['status'], 'error', card)
        self.assertFalse(self._records())

    def test_profile_without_scan_right_is_refused(self):
        card, get = self._scan(URL, user=self.reader, mode='create')
        self.assertEqual(card['status'], 'error', card)
        self.assertEqual(get.call_count, 0)
        self.assertFalse(self._records())

    def test_invoice_failure_keeps_the_scan_in_error(self):
        with patch.object(type(self.ScanRecord), '_create_invoice',
                          side_effect=ValueError('détail interne')):
            card, _get = self._scan(URL)
        self.assertEqual(card['status'], 'error', card)
        self.assertNotIn('détail interne', card['message'])
        record = self._records()
        self.assertEqual(record.state, 'error')
        # Relecture du même QR : le scan en erreur est repris, pas doublé
        card, _get = self._scan(URL)
        self.assertEqual(card['status'], 'success', card)
        self.assertEqual(self._records(), record)
        self.assertEqual(record.state, 'done')

    # -- Gestionnaire OT, Traiteur, cumul --------------------------------

    def test_ot_manager_never_creates_an_invoice(self):
        """Facture inconnue : rien n'est créé, renvoi vers le secrétariat,
        qui la trouve dans « Factures à vérifier »."""
        Pending = self.env['invoice.scan.pending.invoice']
        card, get = self._scan(URL, user=self.ot_manager)
        self.assertEqual(card['status'], 'pending', card)
        self.assertEqual(card['title'], "Cette facture n'existe pas encore")
        self.assertIn('secrétariat', card['message'])
        self.assertEqual(get.call_count, 0)
        self.assertFalse(self._records())
        pending = Pending.search([('qr_uuid', '=', UUID)])
        self.assertEqual(len(pending), 1)
        self.assertEqual(pending.state, 'pending')
        self.assertEqual(pending.requested_by, self.ot_manager)
        self.assertEqual(pending.origin, 'douchette')

        # Présentée une seconde fois : toujours une seule ligne.
        self._scan(URL, user=self.ot_manager)
        self.assertEqual(Pending.search_count([('qr_uuid', '=', UUID)]), 1)
        self.assertEqual(pending.request_count, 2)

        # Le secrétariat la vérifie : la demande se referme seule.
        self._scan(URL)
        record = self._records()
        self.assertEqual(pending.state, 'done')
        self.assertEqual(pending.scan_record_id, record)

        # Le Gestionnaire OT la retrouve, sans doublon compté.
        card, get = self._scan(URL, user=self.ot_manager)
        self.assertEqual(card['status'], 'success', card)
        self.assertEqual(get.call_count, 0)
        self.assertEqual(record.duplicate_count, 0)
        Wizard = self.env['invoice.scan.bulk.process']
        labels = [action['label'] for action in card['actions']]
        self.assertEqual(
            "Rattacher à un OT" in labels,
            'link_ot' in dict(Wizard._selection_operation()))

    def test_secretariat_is_warned_at_scan_time(self):
        """Une autre facture enregistrée porte ce numéro : la carte du scan
        le dit tout de suite, et la facture reste enregistrée."""
        other = self.ScanRecord.create({
            'qr_uuid': '019bd62c-467e-7000-82ac-45c8389c0001',
            'qr_url': URL[:-4] + '0001',
            'supplier_name': 'TRANSITAIRE EXEMPLE',
            'supplier_code_dgi': FNE_PAYLOAD['company']['ncc'],
            'invoice_number_dgi': '2502298K26000000003',
            'amount_ttc': 1000, 'state': 'done',
        })
        card, _get = self._scan(URL)
        self.assertEqual(card['status'], 'success', card)
        self.assertTrue(card['warnings'])
        self.assertIn('même numéro', card['warnings'][0])
        self.assertIn(other.reference, card['warnings'][0])
        record = self.ScanRecord.search([('qr_uuid', '=', UUID)])
        self.assertEqual(record.state, 'done')
        self.assertTrue(record.invoice_id)

    def test_ot_manager_cannot_submit_a_manual_entry(self):
        from odoo.exceptions import UserError
        with self.assertRaises(UserError):
            self.Desk.with_user(self.ot_manager)._desk_submit_dgi(
                {'qr_url': URL},
                {'supplier_name': 'X', 'invoice_number_dgi': 'N1',
                 'amount_ttc': 1000})
        self.assertFalse(self._records())

    def test_processor_marks_the_invoice_processed(self):
        # Pas encore scannée : rien à traiter, et surtout rien de créé
        card, get = self._scan(URL, user=self.processor)
        self.assertEqual(card['status'], 'error', card)
        self.assertEqual(get.call_count, 0)
        self.assertFalse(self._records())

        self._scan(URL)
        record = self._records()
        card, get = self._scan(URL, user=self.processor)
        self.assertEqual(card['status'], 'success', card)
        self.assertEqual(card['title'], "Facture marquée traitée")
        self.assertEqual(get.call_count, 0)
        self.assertEqual(record.state, 'processed')
        self.assertEqual(record.processed_by, self.processor)
        self.assertEqual(record.duplicate_count, 0)

        # Relecture : signalée, comptée, rien de modifié
        card, _get = self._scan(URL, user=self.processor)
        self.assertEqual(card['status'], 'duplicate', card)
        self.assertEqual(record.reprocess_attempt_count, 1)
        self.assertEqual(record.processed_by, self.processor)

    def test_manager_chooses_the_mode(self):
        card, _get = self._scan(URL, user=self.manager)  # défaut : créer
        self.assertEqual(card['title'], "Facture créée")
        card, _get = self._scan(URL, user=self.manager, mode='process')
        self.assertEqual(card['title'], "Facture marquée traitée")
        self.assertEqual(self._records().duplicate_count, 0)

    def test_forbidden_mode_falls_back_to_the_allowed_one(self):
        """Un mode demandé sans le profil n'ouvre aucun droit."""
        self._scan(URL)
        card, _get = self._scan(URL, user=self.verifier, mode='process')
        self.assertEqual(card['status'], 'duplicate', card)
        self.assertEqual(self._records().state, 'done')
        card, _get = self._scan(URL, user=self.processor, mode='create')
        self.assertEqual(card['title'], "Facture marquée traitée")

    # -- Saisie manuelle quand la DGI ne répond pas ----------------------

    MANUAL = {
        'supplier_name': ' TRANSPORT DU SUD ', 'supplier_code_dgi': '2502298k',
        'invoice_number_dgi': '2502298K26000000777',
        'invoice_date': '2026-11-20', 'amount_ttc': '1 250 000,00',
        'document_type': 'invoice',
    }

    def _down_card(self, user=None):
        with patch(REQUESTS_GET, side_effect=requests.exceptions.Timeout()):
            return self.Desk.with_user(user or self.verifier).desk_scan(URL)

    def _submit(self, card, values, user=None):
        with patch(REQUESTS_GET, side_effect=requests.exceptions.Timeout()):
            return self.Desk.with_user(user or self.verifier).desk_submit(
                card['kind'], card['form']['payload'], values)

    def test_manual_entry_when_dgi_is_down(self):
        card = self._down_card()
        self.assertEqual(card['status'], 'error')
        names = [field['name'] for field in card['form']['fields']]
        self.assertEqual(names, [
            'supplier_name', 'supplier_code_dgi', 'invoice_number_dgi',
            'invoice_date', 'amount_ttc', 'document_type'])
        result = self._submit(card, self.MANUAL)
        self.assertNotIn('error', result)
        self.assertEqual(result['card']['status'], 'success', result)
        record = self._records()
        self.assertEqual(record.state, 'done')
        self.assertTrue(record.is_manual_entry)
        self.assertFalse(record.document_type_verified)
        self.assertEqual(record.supplier_name, 'TRANSPORT DU SUD')
        self.assertEqual(record.supplier_code_dgi, '2502298K')
        self.assertEqual(record.amount_ttc, 1250000)
        self.assertEqual(str(record.invoice_date), '2026-11-20')
        self.assertEqual(record.qr_url, URL)
        self.assertTrue(record.invoice_id)
        # Valider deux fois (double clic, réseau lent) : doublon, pas 2 pièces
        result = self._submit(card, self.MANUAL)
        self.assertEqual(result['card']['status'], 'duplicate')
        self.assertEqual(len(self._records()), 1)

    def test_manual_entry_negative_amount_is_a_refund(self):
        card = self._down_card()
        result = self._submit(card, dict(self.MANUAL, amount_ttc='-5000'))
        self.assertEqual(result['card']['title'], "Avoir enregistré")
        record = self._records()
        self.assertEqual(record.document_type, 'refund')
        self.assertEqual(record.amount_ttc, 5000)

    def test_manual_entry_errors_keep_the_form(self):
        card = self._down_card()
        for patch_values in ({'supplier_name': '  '},
                             {'invoice_number_dgi': ''},
                             {'amount_ttc': 'beaucoup'},
                             {'amount_ttc': ''},
                             {'invoice_date': '20/11'}):
            result = self._submit(card, dict(self.MANUAL, **patch_values))
            self.assertTrue(result.get('error'), patch_values)
            self.assertNotIn('card', result)
        self.assertFalse(self._records())

    def test_manual_entry_is_rechecked_by_the_server(self):
        card = self._down_card()
        # Profil sans droit d'enregistrer
        result = self._submit(card, self.MANUAL, user=self.processor)
        self.assertTrue(result.get('error'))
        # Formulaire trafiqué
        Desk = self.Desk.with_user(self.verifier)
        for kind, payload, values in (
                ('dgi', {'qr_url': 'https://example.com/x'}, self.MANUAL),
                ('dgi', 'pas un dict', self.MANUAL),
                ('dgi', card['form']['payload'], None),
                ('inconnu', card['form']['payload'], self.MANUAL)):
            self.assertTrue(Desk.desk_submit(kind, payload, values).get('error'))
        self.assertFalse(self._records())

    def test_scanner_test_card(self):
        Desk = self.Desk.with_user(self.reader)  # ouvert à tous : diagnostic
        card = Desk.desk_scan(SCANNER_TEST_TEXT)
        self.assertEqual((card['status'], card['title']),
                         ('success', "Douchette bien réglée"))
        card = Desk.desk_scan(
            typed_on_azerty(SCANNER_TEST_TEXT, QWERTY_ON_AZERTY_WINDOWS))
        self.assertEqual(card['status'], 'error')
        self.assertIn('QWERTY', card['message'])
        card = Desk.desk_scan(SCANNER_TEST_TEXT.swapcase())
        self.assertIn('majuscules', card['title'])

    def test_unknown_content_never_raises(self):
        for text in ('bonjour', 'https://example.com/x', '', None, 42,
                     'x' * 5000, '4006381333931'):
            card = self.Desk.with_user(self.verifier).desk_scan(text)
            self.assertEqual(card['status'], 'unknown', text)
        self.assertEqual(self.ScanRecord.search_count(
            [('scanned_by', '=', self.verifier.id)]), 0)

    def test_handler_crash_is_contained(self):
        def boom(_text, _options):
            self.ScanRecord.sudo().create({
                'qr_uuid': UUID, 'qr_url': URL, 'supplier_name': 'X',
                'invoice_number_dgi': 'N', 'amount_ttc': 1})
            raise RuntimeError('panne')

        with patch.object(type(self.Desk), '_desk_handlers',
                          lambda self_desk: [boom]):
            card = self.Desk.with_user(self.verifier).desk_scan(URL)
        self.assertEqual(card['status'], 'error')
        self.assertNotIn('panne', card['message'])
        # Le point de sauvegarde a tout annulé
        self.assertFalse(self._records())


@tagged('post_install', '-at_install', 'invoice_qr_scanner', 'scan_desk')
class TestScanDeskTour(HttpCase):
    """L'écran, avec de vraies frappes clavier (comme une douchette)."""

    def test_scan_desk_tour(self):
        ensure_xof(self.env)
        user = new_test_user(
            self.env, login='desk_tour', password='desk_tour',
            groups='base.group_user,'
            'invoice_qr_scanner.group_invoice_scanner_verificateur')
        # Le serveur de test tourne dans un autre fil : la DGI est simulée
        # au niveau de la classe, pas d'un objet.
        FneApi = type(self.env['fne.api.client'])
        with patch.object(
                FneApi, '_fetch_payload',
                lambda self_api, qr_uuid: dict(FNE_PAYLOAD, token=qr_uuid)):
            self.start_tour(
                '/web#action=invoice_qr_scanner.action_invoice_scan_desk',
                'invoice_scan_desk_tour', login='desk_tour')
        record = self.env['invoice.scan.record'].search(
            [('qr_uuid', '=', UUID)])
        self.assertEqual(len(record), 1)
        self.assertEqual(record.state, 'done')
        self.assertEqual(record.scanned_by, user)
        self.assertEqual(record.duplicate_count, 1)
        self.assertTrue(record.invoice_id)

    def test_manual_entry_tour(self):
        """DGI injoignable : formulaire sur la carte, scan refusé tant qu'il
        attend, validation, puis poste de nouveau prêt."""
        ensure_xof(self.env)
        new_test_user(
            self.env, login='desk_tour_manual', password='desk_tour_manual',
            groups='base.group_user,'
            'invoice_qr_scanner.group_invoice_scanner_manager')

        def _down(self_api, qr_uuid):
            raise FneApiError('FNE_TIMEOUT', "La DGI ne répond pas.")

        with patch.object(type(self.env['fne.api.client']),
                          '_fetch_payload', _down):
            self.start_tour(
                '/web#action=invoice_qr_scanner.action_invoice_scan_desk',
                'invoice_scan_desk_manual_tour', login='desk_tour_manual')
        record = self.env['invoice.scan.record'].search(
            [('qr_uuid', '=', UUID)])
        self.assertEqual(len(record), 1)
        self.assertEqual(record.state, 'processed')
        self.assertTrue(record.is_manual_entry)
        self.assertEqual(record.supplier_name, 'TRANSPORT DU SUD')
        self.assertEqual(record.amount_ttc, 125000)

    def test_menu_is_reserved_to_scanning_profiles(self):
        menu = self.env.ref('invoice_qr_scanner.menu_invoice_scan_desk')
        Menu = self.env['ir.ui.menu']
        for group, visible in (('verificateur', True), ('traiteur', True),
                               ('ot_manager', True), ('user', False)):
            user = new_test_user(
                self.env, login='desk_menu_%s' % group,
                groups='base.group_user,'
                'invoice_qr_scanner.group_invoice_scanner_%s' % group)
            self.assertEqual(
                menu.id in Menu.with_user(user)._visible_menu_ids(), visible,
                group)


@tagged('post_install', '-at_install', 'invoice_qr_scanner', 'scan_rules')
class TestScanRecordVisibility(TransactionCase):
    """Cloisonnement des scans par profil (17.0.1.12.1).

    La règle multi-société était posée sur « Utilisateur interne » : les
    règles de groupe s'additionnant, chacun voyait tout. Elle est globale.
    """

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        ensure_xof(cls.env)

        def user(login, group):
            return new_test_user(
                cls.env, login=login, groups='base.group_user,'
                'invoice_qr_scanner.group_invoice_scanner_%s' % group)

        cls.alice = user('rule_alice', 'verificateur')
        cls.bob = user('rule_bob', 'verificateur')
        cls.processor = user('rule_processor', 'traiteur')
        cls.other_processor = user('rule_processor_2', 'traiteur')
        cls.ot_manager = user('rule_ot', 'ot_manager')
        cls.manager = user('rule_manager', 'manager')
        cls.ScanRecord = cls.env['invoice.scan.record']

        def scan(index, scanned_by, **values):
            uuid = '019bd62c-467e-7000-82ac-45c8389c7f%02d' % index
            return cls.ScanRecord.create(dict({
                'qr_uuid': uuid,
                'qr_url': URL.replace(UUID, uuid),
                'supplier_name': 'FOURNISSEUR %s' % index,
                'invoice_number_dgi': 'N%s' % index,
                'amount_ttc': 1000, 'scanned_by': scanned_by.id,
                'state': 'done',
            }, **values))

        cls.alice_done = scan(1, cls.alice)
        cls.bob_done = scan(2, cls.bob)
        cls.bob_error = scan(3, cls.bob, state='error')
        cls.processed = scan(4, cls.bob, state='processed',
                             processed_by=cls.processor.id)
        cls.all = (cls.alice_done | cls.bob_done | cls.bob_error
                   | cls.processed)

    def _seen(self, user):
        return self.ScanRecord.with_user(user).search(
            [('id', 'in', self.all.ids)])

    def test_rule_is_global(self):
        rule = self.env.ref(
            'invoice_qr_scanner.rule_invoice_scan_record_company')
        self.assertFalse(rule.groups)

    def test_verifier_sees_only_own_scans(self):
        self.assertEqual(self._seen(self.alice), self.alice_done)
        self.assertEqual(self._seen(self.bob),
                         self.bob_done | self.bob_error | self.processed)

    def test_processor_sees_pending_and_own_work(self):
        self.assertEqual(self._seen(self.processor),
                         self.alice_done | self.bob_done | self.processed)
        self.assertEqual(self._seen(self.other_processor),
                         self.alice_done | self.bob_done)

    def test_managers_see_everything(self):
        self.assertEqual(self._seen(self.manager), self.all)
        self.assertEqual(self._seen(self.ot_manager), self.all)

    def test_duplicates_are_still_caught_across_users(self):
        """Le cloisonnement ne doit JAMAIS affaiblir le dédoublonnage : il
        passe par sudo, au poste de scan comme dans l'API."""
        card = self.env['invoice.scan.desk'].with_user(self.alice).desk_scan(
            self.bob_done.qr_url)
        self.assertEqual(card['status'], 'duplicate', card)
        self.assertEqual(self.bob_done.duplicate_count, 1)
        # … sans bouton vers une fiche qu'Alice ne peut pas lire
        self.assertFalse(card['actions'])

    def test_processor_marks_processed_at_the_desk(self):
        card = self.env['invoice.scan.desk'].with_user(
            self.other_processor).desk_scan(self.alice_done.qr_url)
        self.assertEqual(card['status'], 'success', card)
        self.assertEqual(self.alice_done.processed_by, self.other_processor)
