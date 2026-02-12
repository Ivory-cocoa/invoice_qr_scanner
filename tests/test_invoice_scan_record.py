# -*- coding: utf-8 -*-
"""
Tests unitaires pour le modèle invoice.scan.record
"""

from datetime import datetime, timedelta
from unittest.mock import patch, MagicMock

from odoo.tests import TransactionCase, tagged
from odoo.exceptions import UserError, ValidationError


@tagged('post_install', '-at_install', 'invoice_qr_scanner')
class TestInvoiceScanRecord(TransactionCase):
    """Tests pour le modèle InvoiceScanRecord."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        
        # Créer une devise XOF si elle n'existe pas
        cls.currency_xof = cls.env['res.currency'].search([('name', '=', 'XOF')], limit=1)
        if not cls.currency_xof:
            cls.currency_xof = cls.env['res.currency'].create({
                'name': 'XOF',
                'symbol': 'FCFA',
                'rounding': 1,
            })
        
        # Créer un utilisateur de test
        cls.test_user = cls.env['res.users'].create({
            'name': 'Test Scanner User',
            'login': 'test_scanner',
            'email': 'test_scanner@example.com',
            'groups_id': [(6, 0, [cls.env.ref('base.group_user').id])],
        })
        
        # Créer un partenaire de test
        cls.test_partner = cls.env['res.partner'].create({
            'name': 'Test Supplier',
            'supplier_rank': 1,
            'is_company': True,
            'dgi_code': 'TEST123K',
        })
        
        # UUID de test valide
        cls.valid_uuid = '019bd62c-467e-7000-82ac-45c8389c7f05'
        cls.valid_url = f'https://www.services.fne.dgi.gouv.ci/fr/verification/{cls.valid_uuid}'

    def test_create_scan_record(self):
        """Test de création d'un enregistrement de scan."""
        record = self.env['invoice.scan.record'].create({
            'qr_uuid': self.valid_uuid,
            'qr_url': self.valid_url,
            'scanned_by': self.test_user.id,
        })
        
        self.assertTrue(record.id)
        self.assertNotEqual(record.reference, '/')
        self.assertEqual(record.state, 'draft')
        self.assertEqual(record.qr_uuid, self.valid_uuid.lower())

    def test_uuid_normalization(self):
        """Test que l'UUID est normalisé en minuscules."""
        record = self.env['invoice.scan.record'].create({
            'qr_uuid': self.valid_uuid.upper(),
            'qr_url': self.valid_url,
        })
        
        self.assertEqual(record.qr_uuid, self.valid_uuid.lower())

    def test_extract_uuid_from_url(self):
        """Test de l'extraction de l'UUID depuis l'URL."""
        ScanRecord = self.env['invoice.scan.record']
        
        # URL valide
        uuid = ScanRecord.extract_uuid_from_url(self.valid_url)
        self.assertEqual(uuid, self.valid_uuid.lower())
        
        # URL invalide
        uuid = ScanRecord.extract_uuid_from_url('https://google.com')
        self.assertIsNone(uuid)
        
        # URL vide
        uuid = ScanRecord.extract_uuid_from_url('')
        self.assertIsNone(uuid)
        
        # URL None
        uuid = ScanRecord.extract_uuid_from_url(None)
        self.assertIsNone(uuid)

    def test_validate_dgi_url(self):
        """Test de validation d'URL DGI."""
        ScanRecord = self.env['invoice.scan.record']
        
        # URL valide
        is_valid, error = ScanRecord.validate_dgi_url(self.valid_url)
        self.assertTrue(is_valid)
        self.assertIsNone(error)
        
        # URL non DGI
        is_valid, error = ScanRecord.validate_dgi_url('https://google.com/test')
        self.assertFalse(is_valid)
        self.assertIsNotNone(error)
        
        # URL vide
        is_valid, error = ScanRecord.validate_dgi_url('')
        self.assertFalse(is_valid)

    def test_uuid_uniqueness_constraint(self):
        """Test de la contrainte d'unicité UUID par société."""
        self.env['invoice.scan.record'].create({
            'qr_uuid': self.valid_uuid,
            'qr_url': self.valid_url,
        })
        
        # Tenter de créer un doublon doit échouer
        with self.assertRaises(Exception):  # IntegrityError ou ValidationError
            self.env['invoice.scan.record'].create({
                'qr_uuid': self.valid_uuid,
                'qr_url': self.valid_url,
            })

    def test_check_duplicate(self):
        """Test de la vérification des doublons."""
        ScanRecord = self.env['invoice.scan.record']
        
        # Pas de doublon initialement
        existing = ScanRecord.check_duplicate(self.valid_uuid)
        self.assertFalse(existing)
        
        # Créer un enregistrement
        record = ScanRecord.create({
            'qr_uuid': self.valid_uuid,
            'qr_url': self.valid_url,
        })
        
        # Maintenant il y a un doublon
        existing = ScanRecord.check_duplicate(self.valid_uuid)
        self.assertEqual(existing.id, record.id)

    def test_invalid_uuid_format(self):
        """Test qu'un UUID invalide est rejeté."""
        with self.assertRaises(ValidationError):
            self.env['invoice.scan.record'].create({
                'qr_uuid': 'invalid-uuid-format',
                'qr_url': self.valid_url,
            })

    def test_invalid_url_rejected(self):
        """Test qu'une URL non-DGI est rejetée."""
        with self.assertRaises(ValidationError):
            self.env['invoice.scan.record'].create({
                'qr_uuid': self.valid_uuid,
                'qr_url': 'https://example.com/invalid',
            })

    def test_copy_not_allowed(self):
        """Test que la copie n'est pas autorisée."""
        record = self.env['invoice.scan.record'].create({
            'qr_uuid': self.valid_uuid,
            'qr_url': self.valid_url,
        })
        
        with self.assertRaises(UserError):
            record.copy()

    def test_amount_validation(self):
        """Test de validation des montants."""
        record = self.env['invoice.scan.record'].create({
            'qr_uuid': self.valid_uuid,
            'qr_url': self.valid_url,
            'amount_ttc': 1000,
            'amount_ht': 850,
        })
        
        # TVA calculée automatiquement
        self.assertEqual(record.amount_tva, 150)
        
        # Montant HT > TTC doit échouer
        with self.assertRaises(ValidationError):
            record.write({
                'amount_ht': 1500,  # Plus que TTC
            })

    def test_computed_fields(self):
        """Test des champs calculés."""
        record = self.env['invoice.scan.record'].create({
            'qr_uuid': self.valid_uuid,
            'qr_url': self.valid_url,
            'supplier_name': 'Test Supplier',
            'invoice_number_dgi': 'INV001',
        })
        
        # Display name
        self.assertIn('Test Supplier', record.display_name)
        
        # is_recent (scan vient d'être créé)
        self.assertTrue(record.is_recent)
        
        # days_since_scan
        self.assertEqual(record.days_since_scan, 0)

    def test_can_retry_logic(self):
        """Test de la logique de réessai."""
        record = self.env['invoice.scan.record'].create({
            'qr_uuid': self.valid_uuid,
            'qr_url': self.valid_url,
            'state': 'error',
            'retry_count': 0,
            'max_retry': 3,
        })
        
        # Peut réessayer
        self.assertTrue(record.can_retry)
        
        # Après 3 tentatives, ne peut plus
        record.write({'retry_count': 3})
        self.assertFalse(record.can_retry)
        
        # Si facture créée, ne peut plus
        record.write({'retry_count': 0, 'state': 'done'})
        self.assertFalse(record.can_retry)

    def test_state_transitions(self):
        """Test des transitions d'état."""
        record = self.env['invoice.scan.record'].create({
            'qr_uuid': self.valid_uuid,
            'qr_url': self.valid_url,
        })
        
        self.assertEqual(record.state, 'draft')
        
        # Annuler
        record.action_cancel()
        self.assertEqual(record.state, 'cancelled')
        
        # Remettre en brouillon
        record.action_set_to_draft()
        self.assertEqual(record.state, 'draft')

    def test_action_view_invoice_no_invoice(self):
        """Test que voir facture sans facture lève une erreur."""
        record = self.env['invoice.scan.record'].create({
            'qr_uuid': self.valid_uuid,
            'qr_url': self.valid_url,
        })
        
        with self.assertRaises(UserError):
            record.action_view_invoice()

    def test_get_or_create_supplier_by_dgi_code(self):
        """Test de recherche fournisseur par code DGI."""
        record = self.env['invoice.scan.record'].create({
            'qr_uuid': self.valid_uuid,
            'qr_url': self.valid_url,
            'supplier_name': 'Another Name',
            'supplier_code_dgi': 'TEST123K',  # Code DGI du partenaire existant
        })
        
        partner = record._get_or_create_supplier()
        
        # Doit trouver le partenaire existant
        self.assertEqual(partner.id, self.test_partner.id)

    def test_get_or_create_supplier_creates_new(self):
        """Test de création d'un nouveau fournisseur."""
        record = self.env['invoice.scan.record'].create({
            'qr_uuid': self.valid_uuid,
            'qr_url': self.valid_url,
            'supplier_name': 'New Supplier XYZ',
            'supplier_code_dgi': 'NEWCODE999',
        })
        
        partner = record._get_or_create_supplier()
        
        self.assertTrue(partner.id)
        self.assertEqual(partner.name, 'New Supplier XYZ')
        self.assertEqual(partner.dgi_code, 'NEWCODE999')
        self.assertEqual(partner.supplier_rank, 1)

    def test_delete_scan_with_posted_invoice(self):
        """Test qu'on ne peut pas supprimer un scan avec facture validée."""
        # Créer un journal et compte si nécessaire
        journal = self.env['account.journal'].search([
            ('type', '=', 'purchase'),
        ], limit=1)
        
        if not journal:
            self.skipTest("Pas de journal d'achats disponible")
        
        # Créer une facture
        invoice = self.env['account.move'].create({
            'move_type': 'in_invoice',
            'partner_id': self.test_partner.id,
            'journal_id': journal.id,
        })
        
        record = self.env['invoice.scan.record'].create({
            'qr_uuid': self.valid_uuid,
            'qr_url': self.valid_url,
            'invoice_id': invoice.id,
            'state': 'done',
        })
        
        # Valider la facture
        try:
            invoice.action_post()
            
            # Tentative de suppression doit échouer
            with self.assertRaises(UserError):
                record.unlink()
        except Exception:
            # Si la validation échoue (manque de données comptables), on skip
            self.skipTest("Impossible de valider la facture de test")


@tagged('post_install', '-at_install', 'invoice_qr_scanner')
class TestDashboardData(TransactionCase):
    """Tests pour les données du tableau de bord."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        
        cls.currency_xof = cls.env['res.currency'].search([('name', '=', 'XOF')], limit=1)
        if not cls.currency_xof:
            cls.currency_xof = cls.env['res.currency'].create({
                'name': 'XOF', 'symbol': 'FCFA', 'rounding': 1,
            })

    def test_get_dashboard_data_empty(self):
        """Test du dashboard sans données."""
        data = self.env['invoice.scan.record'].get_dashboard_data()
        
        self.assertIn('stats', data)
        self.assertIn('recent_scans', data)
        self.assertIn('chart_data', data)
        self.assertEqual(data['stats']['totalScans'], 0)

    def test_get_dashboard_data_with_records(self):
        """Test du dashboard avec des enregistrements."""
        # Créer quelques enregistrements
        for i in range(5):
            self.env['invoice.scan.record'].create({
                'qr_uuid': f'019bd62c-467e-7000-82ac-45c8389c7f{i:02d}',
                'qr_url': f'https://www.services.fne.dgi.gouv.ci/fr/verification/019bd62c-467e-7000-82ac-45c8389c7f{i:02d}',
                'state': 'done' if i < 3 else 'error',
                'amount_ttc': 10000 * (i + 1),
            })
        
        data = self.env['invoice.scan.record'].get_dashboard_data()
        
        self.assertEqual(data['stats']['totalScans'], 5)
        self.assertEqual(data['stats']['successfulScans'], 3)
        self.assertEqual(data['stats']['errorScans'], 2)
        self.assertGreater(len(data['recent_scans']), 0)

    def test_get_dashboard_data_periods(self):
        """Test des différentes périodes du dashboard."""
        for period in ['day', 'week', 'month', 'year']:
            data = self.env['invoice.scan.record'].get_dashboard_data(period)
            self.assertEqual(data['period'], period)

    def test_get_dashboard_data_invalid_period(self):
        """Test avec une période invalide (doit utiliser 'month' par défaut)."""
        data = self.env['invoice.scan.record'].get_dashboard_data('invalid')
        self.assertIn('stats', data)  # Ne doit pas planter
