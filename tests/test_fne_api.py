# -*- coding: utf-8 -*-
"""Tests du client d'API FNE (extraction DGI côté serveur).

Aucun test n'appelle le réseau : la plateforme DGI est un tiers, un test qui en
dépend échouerait au gré de sa disponibilité. Les appels HTTP sont simulés, et
la normalisation — la seule logique qui nous appartient vraiment — est testée
sur un payload figé, calqué sur une réponse réelle.
"""

from unittest.mock import patch

import requests

from odoo.tests import TransactionCase, tagged

from ..models.fne_api import PARAM_BASE_URL, PARAM_ENABLED, FneApiError

# Payload calqué sur une réponse réelle de /ws/invoices/qr/<uuid>, réduit aux
# champs que nous lisons + ceux, sensibles, qui NE DOIVENT PAS ressortir.
FNE_PAYLOAD = {
    'token': '019bd62c-467e-7000-82ac-45c8389c7f05',
    'reference': '2502298K26000000003',
    'type': 'invoice',
    'date': '2026-01-19T12:09:56.508Z',
    'amount': 1677566,
    'totalAfterTaxes': 1677566,
    'totalDue': 1677566,
    'clientNcc': '1100563G',
    'clientCompanyName': 'IVORY COCOA PRODUCTS',
    'subtype': 'normal',
    'clientEmail': 'compta@example.ci',
    'commercialMessage': 'OT GSR 001/26 - LTA n°: 078 8534 7083',
    'company': {
        'name': 'TRANSITAIRE EXEMPLE',
        'ncc': '2502298K',
        'apiKey': 'CLE-API-SENSIBLE-A-NE-PAS-STOCKER',
        'bankReference': 'BANQUE: CI93CI26007201801009823',
        'email': 'contact@example.ci',
    },
}


# Avoir réel : la plateforme le sert sous le MÊME endpoint, avec un `subtype`
# différent, des montants négatifs et la référence de la facture d'origine.
FNE_REFUND_PAYLOAD = dict(
    FNE_PAYLOAD,
    token='01a0196f-7c15-7006-a5a7-85443a22c929',
    reference='A7603114Y2600000393',
    subtype='refund',
    parentReference='7603114Y26000010087',
    amount=-250000,
    totalAfterTaxes=-250000,
    totalDue=-250000,
)


@tagged('post_install', '-at_install', 'invoice_qr_scanner', 'fne')
class TestFneApiNormalization(TransactionCase):
    """Normalisation du payload FNE (fonction pure, sans réseau)."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.FneApi = cls.env['fne.api.client']

    def test_normalize_maps_all_fields(self):
        values = self.FneApi._normalize_payload(FNE_PAYLOAD)

        self.assertEqual(values['supplier_name'], 'TRANSITAIRE EXEMPLE')
        self.assertEqual(values['supplier_code_dgi'], '2502298K')
        self.assertEqual(values['customer_name'], 'IVORY COCOA PRODUCTS')
        self.assertEqual(values['customer_code_dgi'], '1100563G')
        self.assertEqual(values['invoice_number_dgi'], '2502298K26000000003')
        self.assertEqual(values['amount_ttc'], 1677566)
        self.assertEqual(values['verification_id'], FNE_PAYLOAD['token'])
        self.assertEqual(values['invoice_date'].isoformat(), '2026-01-19')
        self.assertIn('OT GSR 001/26', values['commercial_message'])

    def test_normalize_never_leaks_sensitive_supplier_data(self):
        """La liste blanche est une exigence de confidentialité, pas un détail.

        La réponse publique de la DGI contient la clé d'API du fournisseur et
        sa référence bancaire (faiblesse signalée à la DGI). Rien de tout cela
        ne doit pouvoir se retrouver en base ni dans un journal.
        """
        values = self.FneApi._normalize_payload(FNE_PAYLOAD)

        expected_keys = {
            'supplier_name', 'supplier_code_dgi', 'customer_name',
            'customer_code_dgi', 'invoice_number_dgi', 'invoice_date',
            'amount_ttc', 'verification_id', 'commercial_message',
            'document_type', 'document_type_verified',
            'origin_invoice_number_dgi',
        }
        self.assertEqual(set(values), expected_keys)

        serialized = str(values)
        for secret in ('CLE-API-SENSIBLE', 'CI93CI26007201801009823',
                       'contact@example.ci', 'compta@example.ci'):
            self.assertNotIn(secret, serialized)

    def test_normalize_requires_supplier_number_and_amount(self):
        for missing in ('company', 'reference'):
            payload = dict(FNE_PAYLOAD)
            payload.pop(missing)
            with self.assertRaises(FneApiError) as ctx:
                self.FneApi._normalize_payload(payload)
            self.assertEqual(ctx.exception.code, 'FNE_INCOMPLETE_DATA')

        payload = dict(FNE_PAYLOAD)
        for key in ('totalDue', 'totalAfterTaxes', 'amount'):
            payload.pop(key)
        with self.assertRaises(FneApiError) as ctx:
            self.FneApi._normalize_payload(payload)
        self.assertEqual(ctx.exception.code, 'FNE_INCOMPLETE_DATA')

    def test_amount_falls_back_when_total_due_missing(self):
        """Un montant à 0 est légitime : il ne doit pas déclencher le repli."""
        payload = dict(FNE_PAYLOAD, totalDue=0)
        self.assertEqual(self.FneApi._normalize_payload(payload)['amount_ttc'], 0)

        payload = dict(FNE_PAYLOAD)
        payload.pop('totalDue')
        payload['totalAfterTaxes'] = 1000
        self.assertEqual(self.FneApi._normalize_payload(payload)['amount_ttc'], 1000)

    def test_unparsable_date_does_not_block_the_invoice(self):
        """La date est secondaire : sans elle, la facture reste créable."""
        payload = dict(FNE_PAYLOAD, date='pas une date')
        self.assertFalse(self.FneApi._normalize_payload(payload)['invoice_date'])

    def test_clean_text_normalizes_whitespace(self):
        payload = dict(FNE_PAYLOAD, clientCompanyName='  IVORY   COCOA\nPRODUCTS ')
        values = self.FneApi._normalize_payload(payload)
        self.assertEqual(values['customer_name'], 'IVORY COCOA PRODUCTS')


@tagged('post_install', '-at_install', 'invoice_qr_scanner', 'fne')
class TestFneApiRefunds(TransactionCase):
    """Avoirs : la nature du document et le signe du montant.

    C'est le cœur du correctif. La plateforme FNE certifie les avoirs sous le
    même QR-code que les factures ; l'ancienne normalisation les rejetait
    (montant négatif écarté), et l'extraction encore plus ancienne les
    enregistrait à l'envers. Ces tests fixent le contrat : nature explicite,
    montant en valeur absolue.
    """

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.FneApi = cls.env['fne.api.client']

    def test_invoice_is_typed_as_invoice(self):
        values = self.FneApi._normalize_payload(FNE_PAYLOAD)
        self.assertEqual(values['document_type'], 'invoice')
        self.assertEqual(values['amount_ttc'], 1677566)
        self.assertFalse(values['origin_invoice_number_dgi'])

    def test_refund_is_typed_and_amount_made_absolute(self):
        """Un avoir doit ressortir typé, avec un montant POSITIF.

        Le signe appartient à la nature du document, pas au montant : c'est
        `invoice.scan.record.amount_signed` qui le rétablit. Stocker un négatif
        casserait la contrainte de montant et tous les cumuls existants.
        """
        values = self.FneApi._normalize_payload(FNE_REFUND_PAYLOAD)

        self.assertEqual(values['document_type'], 'refund')
        self.assertEqual(values['amount_ttc'], 250000)
        self.assertEqual(values['invoice_number_dgi'], 'A7603114Y2600000393')
        self.assertEqual(values['origin_invoice_number_dgi'],
                         '7603114Y26000010087')

    def test_refund_no_longer_raises_incomplete_data(self):
        """La régression d'origine : l'avoir était refusé faute de montant.

        `_parse_amount` n'acceptait que les montants >= 0 ; les trois champs
        de montant d'un avoir étant négatifs, il renvoyait None et la
        normalisation levait FNE_INCOMPLETE_DATA. L'utilisateur voyait
        « données non extraites » sur un QR-code parfaitement valide.
        """
        values = self.FneApi._normalize_payload(FNE_REFUND_PAYLOAD)
        self.assertTrue(values['amount_ttc'])

    def test_negative_amount_alone_implies_refund(self):
        """Sans `subtype`, le signe du montant suffit à conclure."""
        payload = dict(FNE_PAYLOAD, totalDue=-1000, totalAfterTaxes=-1000,
                       amount=-1000)
        payload.pop('subtype')
        values = self.FneApi._normalize_payload(payload)
        self.assertEqual(values['document_type'], 'refund')
        self.assertEqual(values['amount_ttc'], 1000)

    def test_refund_subtype_alone_implies_refund(self):
        """Et inversement : un `subtype` d'avoir prime sur un montant positif.

        Redondance volontaire : l'endpoint n'est pas contractuel, un émetteur
        peut très bien produire un avoir à montant positif.
        """
        payload = dict(FNE_PAYLOAD, subtype='refund')
        values = self.FneApi._normalize_payload(payload)
        self.assertEqual(values['document_type'], 'refund')
        self.assertEqual(values['amount_ttc'], 1677566)

    def test_values_from_the_platform_are_marked_verified(self):
        values = self.FneApi._normalize_payload(FNE_REFUND_PAYLOAD)
        self.assertTrue(values['document_type_verified'])

    def test_fetch_document_nature_tolerates_incomplete_payloads(self):
        """La nature se lit même sur un payload amputé.

        `fetch_document_nature` sert à rattraper les clients qui n'envoient pas
        le type : exiger un fournisseur ou un numéro les priverait justement du
        rattrapage.
        """
        payload = dict(FNE_REFUND_PAYLOAD)
        payload.pop('company')
        payload.pop('reference')
        with patch('odoo.addons.invoice_qr_scanner.models.fne_api.requests.get',
                   return_value=_FakeResponse(payload=payload)):
            nature = self.FneApi.fetch_document_nature(
                '01a0196f-7c15-7006-a5a7-85443a22c929')
        self.assertEqual(nature['document_type'], 'refund')
        self.assertEqual(nature['origin_invoice_number_dgi'],
                         '7603114Y26000010087')


class _FakeResponse:
    def __init__(self, status_code=200, payload=None, invalid_json=False):
        self.status_code = status_code
        self._payload = payload if payload is not None else FNE_PAYLOAD
        self._invalid_json = invalid_json

    def json(self):
        if self._invalid_json:
            raise ValueError('pas du JSON')
        return self._payload


@tagged('post_install', '-at_install', 'invoice_qr_scanner', 'fne')
class TestFneApiFetch(TransactionCase):
    """Interrogation de l'API FNE : erreurs typées et configuration."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.FneApi = cls.env['fne.api.client']
        cls.uuid = '019bd62c-467e-7000-82ac-45c8389c7f05'

    def _patch_get(self, **kwargs):
        return patch('odoo.addons.invoice_qr_scanner.models.fne_api.requests.get', **kwargs)

    def test_fetch_returns_normalized_values(self):
        with self._patch_get(return_value=_FakeResponse()) as mocked:
            values = self.FneApi.fetch_invoice(self.uuid)
        self.assertEqual(values['supplier_code_dgi'], '2502298K')
        called_url = mocked.call_args[0][0]
        self.assertTrue(called_url.endswith('/invoices/qr/%s' % self.uuid))

    def test_http_errors_are_typed(self):
        cases = [
            (_FakeResponse(status_code=404), 'FNE_NOT_FOUND'),
            (_FakeResponse(status_code=500), 'FNE_HTTP_ERROR'),
            (_FakeResponse(invalid_json=True), 'FNE_INVALID_RESPONSE'),
            (_FakeResponse(payload=['inattendu']), 'FNE_INVALID_RESPONSE'),
        ]
        for response, expected_code in cases:
            with self._patch_get(return_value=response):
                with self.assertRaises(FneApiError) as ctx:
                    self.FneApi.fetch_invoice(self.uuid)
            self.assertEqual(ctx.exception.code, expected_code)

    def test_network_errors_are_typed(self):
        for exception, expected_code in (
            (requests.Timeout('trop long'), 'FNE_TIMEOUT'),
            (requests.ConnectionError('injoignable'), 'FNE_UNREACHABLE'),
        ):
            with self._patch_get(side_effect=exception):
                with self.assertRaises(FneApiError) as ctx:
                    self.FneApi.fetch_invoice(self.uuid)
            self.assertEqual(ctx.exception.code, expected_code)

    def test_disabled_setting_prevents_any_call(self):
        self.env['ir.config_parameter'].sudo().set_param(PARAM_ENABLED, 'False')
        with self._patch_get() as mocked:
            with self.assertRaises(FneApiError) as ctx:
                self.FneApi.fetch_invoice(self.uuid)
        self.assertEqual(ctx.exception.code, 'FNE_DISABLED')
        mocked.assert_not_called()

    def test_enabled_by_default_and_reactivable(self):
        """Piège connu : pour un booléen dont le défaut est VRAI, une valeur
        vide doit compter comme VRAI, et 'False' comme FAUX."""
        ICP = self.env['ir.config_parameter'].sudo()
        self.assertTrue(self.FneApi._is_enabled())

        ICP.set_param(PARAM_ENABLED, 'False')
        self.assertFalse(self.FneApi._is_enabled())

        ICP.set_param(PARAM_ENABLED, 'True')
        self.assertTrue(self.FneApi._is_enabled())

    def test_base_url_is_configurable(self):
        self.env['ir.config_parameter'].sudo().set_param(
            PARAM_BASE_URL, 'https://exemple.test/ws/')
        with self._patch_get(return_value=_FakeResponse()) as mocked:
            self.FneApi.fetch_invoice(self.uuid)
        self.assertEqual(
            mocked.call_args[0][0],
            'https://exemple.test/ws/invoices/qr/%s' % self.uuid)

    def test_settings_roundtrip_keeps_the_box_unchecked(self):
        """Décocher la case doit tenir : c'est exactement ce que le mécanisme
        `config_parameter` standard ne fait pas pour un défaut à VRAI."""
        settings = self.env['res.config.settings'].create({
            'invoice_qr_fne_api_enabled': False,
        })
        settings.set_values()
        self.assertFalse(self.FneApi._is_enabled())
        self.assertFalse(
            self.env['res.config.settings'].get_values()['invoice_qr_fne_api_enabled'])
