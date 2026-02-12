# -*- coding: utf-8 -*-
"""
Tests unitaires pour l'API mobile REST
"""

import json
from unittest.mock import patch, MagicMock
from datetime import datetime, timedelta

from odoo.tests import HttpCase, tagged
from odoo.http import Response


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

    def test_login_missing_credentials(self):
        """Test de login sans identifiants."""
        response = self._make_request(
            '/api/v1/invoice-scanner/auth/login',
            data={}
        )
        
        self.assertEqual(response.status_code, 400)
        data = json.loads(response.content)
        self.assertFalse(data.get('success'))
        self.assertEqual(data['error']['code'], 'VALIDATION_ERROR')

    def test_login_invalid_credentials(self):
        """Test de login avec identifiants invalides."""
        response = self._make_request(
            '/api/v1/invoice-scanner/auth/login',
            data={
                'login': 'nonexistent_user',
                'password': 'wrong_password'
            }
        )
        
        self.assertEqual(response.status_code, 401)
        data = json.loads(response.content)
        self.assertFalse(data.get('success'))
        self.assertEqual(data['error']['code'], 'AUTH_FAILED')

    def test_scan_without_auth(self):
        """Test de scan sans authentification."""
        response = self._make_request(
            '/api/v1/invoice-scanner/scan',
            data={'qr_url': self.valid_url}
        )
        
        self.assertEqual(response.status_code, 401)
        data = json.loads(response.content)
        self.assertFalse(data.get('success'))
        self.assertEqual(data['error']['code'], 'AUTH_REQUIRED')

    def test_history_without_auth(self):
        """Test de l'historique sans authentification."""
        response = self.url_open('/api/v1/invoice-scanner/history')
        
        self.assertEqual(response.status_code, 401)

    def test_stats_without_auth(self):
        """Test des statistiques sans authentification."""
        response = self.url_open('/api/v1/invoice-scanner/stats')
        
        self.assertEqual(response.status_code, 401)


@tagged('post_install', '-at_install', 'invoice_qr_scanner', 'api')
class TestAPIHelpers(HttpCase):
    """Tests pour les fonctions helper de l'API."""

    def test_api_response_format(self):
        """Test du format standard des réponses API."""
        response = self.url_open('/api/v1/invoice-scanner/health')
        data = json.loads(response.content)
        
        # Vérifier la structure de base
        self.assertIn('success', data)
        self.assertIn('api_version', data)
        self.assertIn('timestamp', data)

    def test_api_error_format(self):
        """Test du format des erreurs API."""
        response = self._make_request(
            '/api/v1/invoice-scanner/auth/login',
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


@tagged('post_install', '-at_install', 'invoice_qr_scanner', 'api')
class TestAPIValidation(HttpCase):
    """Tests de validation pour l'API."""

    def test_scan_invalid_url(self):
        """Test de scan avec URL invalide (format de test sans auth)."""
        response = self._make_request(
            '/api/v1/invoice-scanner/test-dgi',
            data={'qr_url': 'https://invalid-url.com'}
        )
        
        # L'endpoint test-dgi n'est pas protégé
        self.assertEqual(response.status_code, 200)
        data = json.loads(response.content)
        # Le résultat dépend de l'implémentation

    def test_scan_empty_url(self):
        """Test de scan avec URL vide."""
        response = self._make_request(
            '/api/v1/invoice-scanner/test-dgi',
            data={'qr_url': ''}
        )
        
        self.assertEqual(response.status_code, 400)
        data = json.loads(response.content)
        self.assertFalse(data.get('success'))

    def _make_request(self, url, method='POST', data=None, headers=None):
        """Helper pour faire des requêtes HTTP."""
        if headers is None:
            headers = {'Content-Type': 'application/json'}
        
        if data is not None:
            data = json.dumps(data)
        
        return self.url_open(url, data=data, headers=headers)
