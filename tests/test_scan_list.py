# -*- coding: utf-8 -*-
"""Liste des scans : recherche par numéro, aperçu, doublons mis en évidence.

Trois niveaux : la recherche (domaine construit côté serveur), l'adresse de
l'aperçu (jamais autre chose que le site de la DGI), puis la liste elle-même
dans un navigateur.
"""

from lxml import etree

from odoo import fields
from odoo.tests import HttpCase, TransactionCase, new_test_user, tagged

from ..models.fne_api import PARAM_BASE_URL
from .test_scan_desk import ensure_xof

UUID_A = '01a1fd85-6adb-7dd8-b0ee-55c5d0732ece'
UUID_B = '01a20922-f0bd-7000-bc4d-44aa101a80e1'
UUID_C = '01a1f2ed-6a7f-7000-8ca7-0e0dca4f5ab7'
DGI_SITE = 'https://www.services.fne.dgi.gouv.ci'


def make_scan(env, uuid, number, **kwargs):
    values = {
        'qr_uuid': uuid,
        'qr_url': '%s/fr/verification/%s' % (DGI_SITE, uuid),
        'supplier_name': 'QUINCAILLERIE EXEMPLE',
        'supplier_code_dgi': number[:8],
        'invoice_number_dgi': number,
        'invoice_date': fields.Date.today(),
        'amount_ttc': 2183000,
        'state': 'done',
    }
    values.update(kwargs)
    return env['invoice.scan.record'].create(values)


@tagged('post_install', '-at_install', 'invoice_qr_scanner')
class TestScanNumberSearch(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        ensure_xof(cls.env)
        cls.Scan = cls.env['invoice.scan.record']
        cls.scan_a = make_scan(cls.env, UUID_A, '2603236T26000000174')
        cls.scan_b = make_scan(cls.env, UUID_B, '2134788Y26000000024',
                               verification_id='D76A8C03-BBA0-46F1-ADB0-4CA8753F1365')
        cls.refund = make_scan(
            cls.env, UUID_C, 'A2603236T2600000003', document_type='refund',
            origin_invoice_number_dgi='2603236T26000000174')
        cls.ours = cls.scan_a | cls.scan_b | cls.refund

    def _find(self, text, operator='ilike'):
        return self.Scan.search(
            [('number_search', operator, text), ('id', 'in', self.ours.ids)])

    def test_partial_invoice_number(self):
        """Les derniers chiffres suffisent ; l'avoir de la facture suit."""
        self.assertEqual(self._find('0000174'), self.scan_a | self.refund)
        self.assertEqual(self._find('00000024'), self.scan_b)

    def test_case_is_ignored(self):
        self.assertEqual(self._find('2134788y26'), self.scan_b)

    def test_scan_reference(self):
        self.assertEqual(self._find(self.scan_b.reference), self.scan_b)
        self.assertEqual(self._find(self.scan_b.reference.lower()), self.scan_b)

    def test_verification_identifiers(self):
        self.assertEqual(self._find('d76a8c03-bba0'), self.scan_b)
        self.assertEqual(self._find(UUID_A.upper()), self.scan_a)

    def test_several_numbers(self):
        """Virgule, point-virgule ou espace : l'un OU l'autre."""
        for text in ('2134788Y26000000024, A2603236T2600000003',
                     '2134788Y26000000024;A2603236T2600000003',
                     ' 2134788Y26000000024   A2603236T2600000003 '):
            self.assertEqual(self._find(text), self.scan_b | self.refund, text)

    def test_copied_with_separators(self):
        """Un numéro recopié avec tirets ou points est retrouvé."""
        self.assertEqual(self._find('2134788Y-26-000000024'), self.scan_b)
        self.assertEqual(self._find('2134788Y.26.000000024'), self.scan_b)

    def test_exact_and_negative_operators(self):
        self.assertEqual(self._find('2134788Y26000000024', '='), self.scan_b)
        self.assertFalse(self._find('000000024', '='))
        self.assertEqual(self._find('2134788Y26000000024', 'not ilike'),
                         self.scan_a | self.refund)
        self.assertEqual(self._find('2134788Y26000000024', '!='),
                         self.scan_a | self.refund)

    def test_wildcards_are_literal_on_exact_search(self):
        self.assertFalse(self._find('2134788Y2600000002_', '='))
        self.assertFalse(self._find('%', '='))

    def test_empty_search_keeps_everything(self):
        for text in ('', '   ', ' , ; ', False):
            self.assertEqual(self._find(text), self.ours, repr(text))
        self.assertFalse(self._find('', 'not ilike'))

    def test_unknown_number(self):
        self.assertFalse(self._find('9999999Z99000000999'))

    def test_too_many_numbers_are_bounded(self):
        text = ','.join('N%04d' % i for i in range(500))
        domain = self.Scan._search_number_search('ilike', text)
        leaves = [leaf for leaf in domain if isinstance(leaf, (list, tuple))]
        self.assertLessEqual(
            len(leaves),
            self.Scan.NUMBER_SEARCH_MAX_TERMS * len(self.Scan._number_search_fields()))
        self.Scan.search(domain)

    def test_user_without_accounting_rights(self):
        """Un vérificateur ne lit pas les pièces : sa recherche n'est pas
        refusée, elle laisse seulement le numéro de pièce de côté."""
        user = new_test_user(
            self.env, login='verif_search',
            groups='base.group_user,'
            'invoice_qr_scanner.group_invoice_scanner_verificateur')
        self.scan_b.scanned_by = user
        Scan = self.Scan.with_user(user)
        self.assertNotIn('invoice_id.name', Scan._number_search_fields())
        self.assertEqual(
            Scan.search([('number_search', 'ilike', '00000024')]), self.scan_b)
        # Le cloisonnement reste entier : la facture d'un autre est invisible.
        self.assertFalse(Scan.search([('number_search', 'ilike', '0000174')]))

    def test_accounting_user_searches_the_move_number(self):
        self.assertIn('invoice_id.name', self.Scan._number_search_fields())
        partner = self.env['res.partner'].create({'name': 'QUINCAILLERIE EXEMPLE'})
        journal = self.Scan._get_or_create_purchase_journal()
        move = self.env['account.move'].create({
            'move_type': 'in_invoice', 'partner_id': partner.id,
            'journal_id': journal.id, 'name': 'FACTU/2099/11/0329',
        })
        self.scan_a.invoice_id = move
        self.assertEqual(self._find('FACTU/2099/11/0329'), self.scan_a)
        self.assertEqual(self._find('2099/11/0329'), self.scan_a)

    def test_name_search_by_invoice_number(self):
        names = self.Scan.name_search('2134788Y26000000024')
        self.assertEqual([res[0] for res in names], self.scan_b.ids)


@tagged('post_install', '-at_install', 'invoice_qr_scanner')
class TestScanPreview(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        ensure_xof(cls.env)
        cls.Scan = cls.env['invoice.scan.record']
        cls.scan = make_scan(cls.env, UUID_A, '2603236T26000000174')
        cls.params = cls.env['ir.config_parameter'].sudo()

    def _url(self):
        self.scan.invalidate_recordset(['dgi_preview_url'])
        return self.scan.dgi_preview_url

    def test_url_is_the_dgi_page(self):
        self.assertEqual(self._url(), '%s/fr/verification/%s' % (DGI_SITE, UUID_A))

    def test_url_ignores_the_scanned_address(self):
        """`qr_url` vient du papier présenté : l'aperçu ne s'y fie pas."""
        self.scan.qr_url = 'https://exemple-malveillant.test/fr/verification/%s' % UUID_A
        self.assertEqual(self._url(), '%s/fr/verification/%s' % (DGI_SITE, UUID_A))

    def test_no_url_without_a_valid_identifier(self):
        for value in ('pas-un-uuid', UUID_A + '/../x', 'javascript:alert(1)',
                      UUID_A + '?x=1'):
            self.scan.qr_uuid = value
            self.assertFalse(self._url(), value)

    def test_url_follows_the_configured_site(self):
        self.params.set_param(PARAM_BASE_URL, 'https://nouveau.dgi.example/ws/')
        self.assertEqual(
            self._url(), 'https://nouveau.dgi.example/fr/verification/%s' % UUID_A)

    def test_unsafe_configured_site_falls_back(self):
        """Ni HTTP, ni identifiants dans l'adresse, ni adresse illisible."""
        for base in ('http://dgi.example/ws', 'https://user:pass@dgi.example/ws',
                     'ftp://dgi.example', 'n importe quoi', 'https://[::1/ws'):
            self.params.set_param(PARAM_BASE_URL, base)
            self.assertEqual(
                self._url(), '%s/fr/verification/%s' % (DGI_SITE, UUID_A), base)

    def test_preview_action(self):
        action = self.scan.action_preview_scan()
        view = self.env.ref('invoice_qr_scanner.view_invoice_scan_record_preview_form')
        self.assertEqual(action['target'], 'new')
        self.assertEqual(action['res_id'], self.scan.id)
        self.assertEqual(action['views'], [(view.id, 'form')])
        self.assertIn('2603236T26000000174', action['name'])
        self.assertEqual(self.scan.action_open_scan_form()['target'], 'current')

    def test_preview_is_read_only_and_never_the_default_form(self):
        view = self.env.ref('invoice_qr_scanner.view_invoice_scan_record_preview_form')
        form = etree.fromstring(self.Scan.get_view(view.id, 'form')['arch'])
        self.assertEqual(form.get('edit'), '0')
        self.assertEqual(form.get('create'), '0')
        default = etree.fromstring(self.Scan.get_view(False, 'form')['arch'])
        self.assertFalse(default.xpath("//field[@name='dgi_preview_url']"))
        self.assertTrue(default.xpath("//button[@name='action_preview_scan']"))

    def test_read_only_user_can_preview(self):
        user = new_test_user(
            self.env, login='scan_reader',
            groups='base.group_user,'
            'invoice_qr_scanner.group_invoice_scanner_verificateur')
        self.scan.scanned_by = user
        scan = self.scan.with_user(user)
        self.assertEqual(scan.action_preview_scan()['res_id'], self.scan.id)
        self.assertTrue(scan.dgi_preview_url)

    def test_list_shows_duplicates_to_everyone(self):
        """Colonne des doublons : ni masquable, ni réservée à un groupe ; le
        bouton d'aperçu est sur chaque ligne."""
        user = new_test_user(
            self.env, login='scan_plain_user',
            groups='base.group_user,invoice_qr_scanner.group_invoice_scanner_user')
        tree = etree.fromstring(
            self.Scan.with_user(user).get_view(False, 'tree')['arch'])
        self.assertEqual(tree.get('js_class'), 'invoice_scan_list')
        column = tree.xpath("//field[@name='duplicate_count']")
        self.assertEqual(len(column), 1)
        self.assertFalse(column[0].get('optional'))
        self.assertFalse(column[0].get('column_invisible'))
        self.assertFalse(column[0].get('invisible'))
        self.assertTrue(tree.xpath("//button[@name='action_preview_scan']"))


@tagged('post_install', '-at_install', 'invoice_qr_scanner')
class TestScanListTour(HttpCase):
    """La liste dans un navigateur : couleur, colonne, recherche, aperçu."""

    def test_scan_list_tour(self):
        ensure_xof(self.env)
        # Aucun appel à la DGI pendant le test : le cadre de l'aperçu pointe
        # vers un domaine réservé, qui n'existe pas.
        self.env['ir.config_parameter'].sudo().set_param(
            PARAM_BASE_URL, 'https://fne.invalid/ws')
        user = new_test_user(
            self.env, login='list_tour', password='list_tour',
            groups='base.group_user,'
            'invoice_qr_scanner.group_invoice_scanner_verificateur')
        make_scan(self.env, UUID_A, '2603236T26000000174', scanned_by=user.id,
                  duplicate_count=3,
                  last_duplicate_attempt=fields.Datetime.now(),
                  last_duplicate_user_id=user.id)
        make_scan(self.env, UUID_B, '2134788Y26000000024', scanned_by=user.id)
        self.start_tour(
            '/web#action=invoice_qr_scanner.action_invoice_scan_record',
            'invoice_scan_list_tour', login='list_tour')
