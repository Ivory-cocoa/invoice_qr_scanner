# -*- coding: utf-8 -*-
"""
Tests unitaires pour les utilitaires de scan (UUID, URL)
"""

from odoo.tests import TransactionCase, tagged


@tagged('post_install', '-at_install', 'invoice_qr_scanner', 'dgi')
class TestDGIExtraction(TransactionCase):
    """Tests pour les méthodes utilitaires du modèle invoice.scan.record."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.ScanRecord = cls.env['invoice.scan.record']

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
