# -*- coding: utf-8 -*-
"""
Tests unitaires pour l'extraction des données DGI
"""

from unittest.mock import patch, MagicMock
from datetime import datetime

from odoo.tests import TransactionCase, tagged


@tagged('post_install', '-at_install', 'invoice_qr_scanner', 'dgi')
class TestDGIExtraction(TransactionCase):
    """Tests pour les méthodes d'extraction de données DGI."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.ScanRecord = cls.env['invoice.scan.record']
        
        # Contenu simulé d'une page DGI
        cls.sample_dgi_content = """
        VERIFICATION DE FACTURE
        
        FOURNISSEUR:
        SOCIETE ABC SARL - 2502298K
        
        CLIENT:
        ICP SA - 1234567M
        
        NUMERO DE FACTURE:
        FAC2024001234
        
        DATE DE FACTURATION:
        15/01/2024
        
        ID VERIFICATION:
        VER-2024-001234
        
        MONTANT TTC:
        1 677 566 FCFA
        """
        
        cls.sample_html = "<html><body>Test</body></html>"

    def test_parse_dgi_content_full(self):
        """Test du parsing complet du contenu DGI."""
        data = self.ScanRecord._parse_dgi_content(
            self.sample_dgi_content, 
            self.sample_html
        )
        
        self.assertTrue(data['success'])
        self.assertEqual(data['supplier_name'], 'SOCIETE ABC SARL')
        self.assertEqual(data['supplier_code_dgi'], '2502298K')
        self.assertEqual(data['customer_name'], 'ICP SA')
        self.assertEqual(data['customer_code_dgi'], '1234567M')
        self.assertEqual(data['invoice_number_dgi'], 'FAC2024001234')
        self.assertEqual(data['verification_id'], 'VER-2024-001234')
        self.assertEqual(data['amount_ttc'], 1677566.0)
        self.assertEqual(data['invoice_date'], datetime(2024, 1, 15).date())

    def test_parse_dgi_content_partial(self):
        """Test du parsing avec données partielles."""
        partial_content = """
        FOURNISSEUR:
        TEST COMPANY - TESTCODE
        
        MONTANT TTC:
        500 000 CFA
        """
        
        data = self.ScanRecord._parse_dgi_content(partial_content, "")
        
        self.assertTrue(data['success'])
        self.assertEqual(data['supplier_name'], 'TEST COMPANY')
        self.assertEqual(data['supplier_code_dgi'], 'TESTCODE')
        self.assertEqual(data['amount_ttc'], 500000.0)
        self.assertIsNone(data.get('invoice_date'))

    def test_parse_dgi_content_different_amount_formats(self):
        """Test du parsing de différents formats de montant."""
        test_cases = [
            ("MONTANT TTC:\n1000000 FCFA", 1000000.0),
            ("MONTANT TTC:\n1 000 000 CFA", 1000000.0),
            ("MONTANT TTC:\n1\u00a0000\u00a0000 FCFA", 1000000.0),  # Espaces insécables
            ("MONTANT TTC:\n500000 CFA", 500000.0),
        ]
        
        for content, expected in test_cases:
            data = self.ScanRecord._parse_dgi_content(content, "")
            self.assertEqual(
                data.get('amount_ttc'), 
                expected, 
                f"Échec pour: {content}"
            )

    def test_parse_dgi_content_different_date_formats(self):
        """Test du parsing des dates."""
        test_cases = [
            ("DATE DE FACTURATION:\n01/01/2024", datetime(2024, 1, 1).date()),
            ("DATE DE FACTURATION:\n31/12/2023", datetime(2023, 12, 31).date()),
            ("DATE DE FACTURATION:\n15/06/2024", datetime(2024, 6, 15).date()),
        ]
        
        for content, expected in test_cases:
            data = self.ScanRecord._parse_dgi_content(content, "")
            self.assertEqual(
                data.get('invoice_date'), 
                expected, 
                f"Échec pour: {content}"
            )

    def test_parse_dgi_content_empty(self):
        """Test du parsing avec contenu vide."""
        data = self.ScanRecord._parse_dgi_content("", "")
        
        self.assertTrue(data['success'])
        self.assertIsNone(data.get('supplier_name'))
        self.assertIsNone(data.get('amount_ttc'))

    def test_parse_dgi_content_malformed(self):
        """Test du parsing avec contenu mal formaté."""
        malformed_content = """
        FOURNISSEUR sans deux-points
        CLIENT aussi sans format
        """
        
        data = self.ScanRecord._parse_dgi_content(malformed_content, "")
        
        # Ne doit pas planter
        self.assertTrue(data['success'])
        self.assertIsNone(data.get('supplier_name'))

    def test_clean_text(self):
        """Test du nettoyage de texte."""
        test_cases = [
            ("  Test  ", "Test"),
            ("Multiple   spaces", "Multiple spaces"),
            ("  Leading and trailing  ", "Leading and trailing"),
            ("", ""),
            (None, ""),
        ]
        
        for input_text, expected in test_cases:
            result = self.ScanRecord._clean_text(input_text)
            self.assertEqual(result, expected)

    def test_extract_uuid_various_formats(self):
        """Test d'extraction UUID avec différents formats d'URL."""
        test_cases = [
            # URLs valides
            (
                "https://www.services.fne.dgi.gouv.ci/fr/verification/019bd62c-467e-7000-82ac-45c8389c7f05",
                "019bd62c-467e-7000-82ac-45c8389c7f05"
            ),
            (
                "https://services.fne.dgi.gouv.ci/verification/019BD62C-467E-7000-82AC-45C8389C7F05",
                "019bd62c-467e-7000-82ac-45c8389c7f05"  # Normalisé en minuscules
            ),
            (
                "http://www.services.fne.dgi.gouv.ci/fr/verification/abcdef12-3456-7890-abcd-ef1234567890",
                "abcdef12-3456-7890-abcd-ef1234567890"
            ),
            # URLs invalides
            ("https://google.com", None),
            ("", None),
            (None, None),
            ("not-a-url", None),
        ]
        
        for url, expected in test_cases:
            result = self.ScanRecord.extract_uuid_from_url(url)
            self.assertEqual(
                result, 
                expected, 
                f"Échec pour URL: {url}"
            )

    @patch('odoo.addons.invoice_qr_scanner.models.invoice_scan_record.sync_playwright')
    def test_fetch_invoice_data_playwright_not_installed(self, mock_playwright):
        """Test quand Playwright n'est pas installé."""
        mock_playwright.side_effect = ImportError("No module named 'playwright'")
        
        # Simuler l'absence de playwright
        with patch.dict('sys.modules', {'playwright': None}):
            result = self.ScanRecord.fetch_invoice_data_from_dgi(
                "https://www.services.fne.dgi.gouv.ci/fr/verification/019bd62c-467e-7000-82ac-45c8389c7f05"
            )
        
        # Doit retourner une erreur propre
        self.assertFalse(result.get('success', True))

    def test_validate_dgi_url_edge_cases(self):
        """Test de validation d'URL avec cas limites."""
        test_cases = [
            # Valides
            (
                "https://www.services.fne.dgi.gouv.ci/fr/verification/019bd62c-467e-7000-82ac-45c8389c7f05",
                True
            ),
            (
                "https://services.fne.dgi.gouv.ci/verification/019bd62c-467e-7000-82ac-45c8389c7f05",
                True
            ),
            # Invalides
            ("https://fake-services.fne.dgi.gouv.ci/test", False),
            ("https://google.com", False),
            ("", False),
            (None, False),
            ("   ", False),  # Espaces seuls
        ]
        
        for url, expected_valid in test_cases:
            is_valid, _ = self.ScanRecord.validate_dgi_url(url)
            self.assertEqual(
                is_valid, 
                expected_valid, 
                f"Validation incorrecte pour: {url}"
            )


@tagged('post_install', '-at_install', 'invoice_qr_scanner', 'dgi')
class TestDGIContentVariations(TransactionCase):
    """Tests pour différentes variations de contenu DGI."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.ScanRecord = cls.env['invoice.scan.record']

    def test_supplier_name_with_special_chars(self):
        """Test du parsing avec caractères spéciaux dans le nom."""
        content = """
        FOURNISSEUR:
        SOCIÉTÉ D'IMPORT-EXPORT & CIE - ABC123K
        """
        
        data = self.ScanRecord._parse_dgi_content(content, "")
        
        self.assertIn('IMPORT', data.get('supplier_name', '').upper())
        self.assertEqual(data.get('supplier_code_dgi'), 'ABC123K')

    def test_amount_with_ht(self):
        """Test du parsing avec montant HT."""
        content = """
        MONTANT HT:
        1 000 000 FCFA
        
        MONTANT TTC:
        1 180 000 FCFA
        """
        
        data = self.ScanRecord._parse_dgi_content(content, "")
        
        self.assertEqual(data.get('amount_ht'), 1000000.0)
        self.assertEqual(data.get('amount_ttc'), 1180000.0)

    def test_multiline_content(self):
        """Test avec contenu sur plusieurs lignes."""
        content = """FOURNISSEUR:

ENTREPRISE TEST

-

CODE12345"""
        
        # Ce format peut ne pas être parsé correctement,
        # mais ne doit pas planter
        data = self.ScanRecord._parse_dgi_content(content, "")
        self.assertTrue(data['success'])

    def test_invoice_number_formats(self):
        """Test de différents formats de numéro de facture."""
        test_cases = [
            ("NUMERO DE FACTURE:\nFAC2024/001234", "FAC2024/001234"),
            ("NUMERO DE FACTURE:\nINV-2024-001", "INV-2024-001"),
            ("NUMERO DE FACTURE:\n123456789", "123456789"),
        ]
        
        for content, expected in test_cases:
            data = self.ScanRecord._parse_dgi_content(content, "")
            self.assertEqual(
                data.get('invoice_number_dgi'), 
                expected,
                f"Échec pour: {content}"
            )
