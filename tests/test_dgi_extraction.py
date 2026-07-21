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
            # URLs sans UUID exploitable
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

    def test_extract_uuid_does_not_validate_domain(self):
        """L'extraction ne vérifie PAS que l'URL provient bien de la DGI.

        Ce test documente une LACUNE assumée, il ne valide pas un choix :
        `extract_uuid_from_url` cherche un motif d'UUID n'importe où dans la
        chaîne, sans contrôler le domaine. Une URL quelconque portant un UUID
        bien formé est donc acceptée.

        L'écart compte parce que la route publique `scan-with-data` reçoit
        `qr_url` du client. Les cas « invalides » du test ci-dessus renvoient
        None faute d'UUID, non parce que le domaine serait rejeté — on aurait
        tort d'y lire une validation d'origine.

        Si une validation de domaine est ajoutée un jour, ce test échouera :
        c'est voulu, il faudra alors le remplacer par son inverse.
        """
        uuid = '019bd62c-467e-7000-82ac-45c8389c7f05'

        self.assertEqual(
            self.ScanRecord.extract_uuid_from_url(f'https://exemple.invalid/{uuid}'),
            uuid,
            "Comportement actuel : aucun contrôle du domaine d'origine",
        )
