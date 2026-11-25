# -*- coding: utf-8 -*-
"""Poste de scan à la douchette.

Trois niveaux : la lecture du texte tapé par la douchette (fonction pure),
le traitement serveur d'une lecture (DGI simulée, jamais de réseau), puis
l'écran lui-même, piloté dans un navigateur avec de vraies frappes clavier.
"""

from unittest.mock import patch

import requests

from odoo.tests import HttpCase, TransactionCase, new_test_user, tagged

from ..models.scanner_input import (
    QWERTY_ON_AZERTY_MAC, QWERTY_ON_AZERTY_WINDOWS, clean_scan, parse_dgi_qr)
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
        cls.Desk = cls.env['invoice.scan.desk']
        cls.ScanRecord = cls.env['invoice.scan.record']

    def _scan(self, text, user=None, **response):
        with patch(REQUESTS_GET, return_value=_FakeResponse(**response)) as get:
            card = self.Desk.with_user(user or self.verifier).desk_scan(text)
        return card, get

    def _records(self, uuid=UUID):
        return self.ScanRecord.search([('qr_uuid', '=', uuid)])

    def test_init_lists_what_the_user_may_scan(self):
        init = self.Desk.with_user(self.verifier).desk_init()
        self.assertTrue(init['can_scan'])
        dgi = next(k for k in init['kinds'] if k['key'] == 'dgi')
        self.assertTrue(dgi['allowed'])
        init = self.Desk.with_user(self.processor).desk_init()
        dgi = next(k for k in init['kinds'] if k['key'] == 'dgi')
        self.assertFalse(dgi['allowed'])

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
        self.assertFalse(self._records())
        # … et le même QR repasse dès que la DGI répond
        card, _get = self._scan(URL)
        self.assertEqual(card['status'], 'success', card)

    def test_unknown_invoice_at_dgi(self):
        card, _get = self._scan(URL, status_code=404)
        self.assertEqual(card['status'], 'error', card)
        self.assertFalse(self._records())

    def test_profile_without_scan_right_is_refused(self):
        card, get = self._scan(URL, user=self.processor)
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

    def test_unknown_content_never_raises(self):
        for text in ('bonjour', 'https://example.com/x', '', None, 42,
                     'x' * 5000, '4006381333931'):
            card = self.Desk.with_user(self.verifier).desk_scan(text)
            self.assertEqual(card['status'], 'unknown', text)
        self.assertEqual(self.ScanRecord.search_count(
            [('scanned_by', '=', self.verifier.id)]), 0)

    def test_handler_crash_is_contained(self):
        def boom(_text):
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

    def test_menu_is_reserved_to_scanning_profiles(self):
        menu = self.env.ref('invoice_qr_scanner.menu_invoice_scan_desk')
        verifier = new_test_user(
            self.env, login='desk_menu_v', groups='base.group_user,'
            'invoice_qr_scanner.group_invoice_scanner_verificateur')
        processor = new_test_user(
            self.env, login='desk_menu_t', groups='base.group_user,'
            'invoice_qr_scanner.group_invoice_scanner_traiteur')
        Menu = self.env['ir.ui.menu']
        self.assertIn(menu.id, Menu.with_user(verifier)._visible_menu_ids())
        self.assertNotIn(menu.id, Menu.with_user(processor)._visible_menu_ids())
