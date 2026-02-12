# -*- coding: utf-8 -*-
"""
API REST Mobile pour le Scanner de Factures QR
Module: invoice_qr_scanner
Version: 1.0.0

Cette API permet de:
- S'authentifier depuis l'application mobile
- Scanner des QR-codes et créer des factures fournisseur
- Consulter l'historique des scans

Endpoints:
- POST /api/v1/invoice-scanner/auth/login - Authentification
- POST /api/v1/invoice-scanner/auth/logout - Déconnexion
- POST /api/v1/invoice-scanner/scan - Scanner et créer facture
- GET /api/v1/invoice-scanner/history - Historique des scans
- GET /api/v1/invoice-scanner/invoice/<id> - Détails d'une facture
- GET /api/v1/invoice-scanner/health - État de l'API
"""

import logging
import hashlib
import secrets
from datetime import datetime, timedelta
from functools import wraps

from odoo import http, _, fields
from odoo.http import request, Response
import json

_logger = logging.getLogger(__name__)

# Configuration
API_VERSION = "1.0.0"
TOKEN_EXPIRY_HOURS = 24 * 7  # 7 jours
MAX_LOGIN_ATTEMPTS = 5


# ==================== HELPERS ====================

def api_response(data=None, message=None, success=True, status=200):
    """Générer une réponse API standardisée."""
    response_data = {
        'success': success,
        'api_version': API_VERSION,
        'timestamp': datetime.now().isoformat(),
    }
    if message:
        response_data['message'] = message
    if data is not None:
        response_data['data'] = data
    
    return Response(
        json.dumps(response_data, default=str, ensure_ascii=False),
        status=status,
        headers={'Content-Type': 'application/json; charset=utf-8'}
    )


def api_error(error_code, message, status=400, details=None, data=None):
    """Générer une réponse d'erreur API."""
    response_data = {
        'success': False,
        'error': {
            'code': error_code,
            'message': message,
        },
        'api_version': API_VERSION,
        'timestamp': datetime.now().isoformat(),
    }
    if details:
        response_data['error']['details'] = details
    if data is not None:
        response_data['data'] = data
    
    return Response(
        json.dumps(response_data, default=str, ensure_ascii=False),
        status=status,
        headers={'Content-Type': 'application/json; charset=utf-8'}
    )


def get_client_ip():
    """Obtenir l'adresse IP du client."""
    if request.httprequest.environ.get('HTTP_X_FORWARDED_FOR'):
        return request.httprequest.environ['HTTP_X_FORWARDED_FOR'].split(',')[0].strip()
    return request.httprequest.environ.get('REMOTE_ADDR', 'unknown')


def get_json_body():
    """Parser le corps JSON de la requête."""
    try:
        data = request.httprequest.get_data(as_text=True)
        if data:
            return json.loads(data)
        return {}
    except json.JSONDecodeError:
        return {}


def api_exception_handler(func):
    """Décorateur pour gérer les exceptions API."""
    @wraps(func)
    def wrapper(*args, **kwargs):
        try:
            return func(*args, **kwargs)
        except Exception as e:
            _logger.error(f"Erreur API invoice-scanner: {e}", exc_info=True)
            return api_error(
                'INTERNAL_ERROR',
                "Une erreur interne s'est produite",
                status=500
            )
    return wrapper


def require_auth(func):
    """Décorateur pour vérifier l'authentification."""
    @wraps(func)
    def wrapper(self, *args, **kwargs):
        auth_header = request.httprequest.headers.get('Authorization', '')
        
        if not auth_header.startswith('Bearer '):
            return api_error('AUTH_REQUIRED', "Token d'authentification requis", status=401)
        
        token = auth_header[7:]
        user = self._verify_api_token(token)
        
        if not user:
            return api_error('AUTH_INVALID', "Token invalide ou expiré", status=401)
        
        # Injecter l'utilisateur dans le contexte (Odoo 17+)
        request.update_env(user=user.id)
        return func(self, user=user, *args, **kwargs)
    
    return wrapper


# ==================== CONTRÔLEUR API ====================

class InvoiceScannerMobileAPI(http.Controller):
    """Contrôleur API REST pour l'application mobile Flutter de scan de factures."""

    # ==================== UTILITAIRES INTERNES ====================

    def _generate_api_token(self):
        """Générer un token API sécurisé."""
        return secrets.token_urlsafe(64)

    def _hash_token(self, token):
        """Hasher un token pour le stockage."""
        return hashlib.sha256(token.encode()).hexdigest()

    def _verify_api_token(self, token):
        """Vérifier un token API et retourner l'utilisateur associé."""
        try:
            token_hash = self._hash_token(token)
            
            ApiToken = request.env['invoice.scanner.api.token'].sudo()
            token_record = ApiToken.search([
                ('token_hash', '=', token_hash),
                ('expires_at', '>', fields.Datetime.now()),
                ('is_active', '=', True)
            ], limit=1)
            
            if token_record and token_record.user_id.active:
                token_record.write({'last_used': fields.Datetime.now()})
                return token_record.user_id
            
            return False
        except Exception as e:
            _logger.error(f"Erreur vérification token: {e}")
            return False

    def _format_scan_record(self, record):
        """Formater un enregistrement de scan pour l'API."""
        return {
            'id': record.id,
            'reference': record.reference,
            'qr_uuid': record.qr_uuid,
            'supplier_name': record.supplier_name or '',
            'supplier_code_dgi': record.supplier_code_dgi or '',
            'invoice_number_dgi': record.invoice_number_dgi or '',
            'invoice_date': record.invoice_date.isoformat() if record.invoice_date else None,
            'amount_ttc': record.amount_ttc,
            'currency': record.currency_id.name if record.currency_id else 'XOF',
            'state': record.state,
            'state_label': dict(record._fields['state'].selection).get(record.state, ''),
            'is_processed': record.state == 'processed',
            'processed_by': record.processed_by.name if record.processed_by else None,
            'processed_by_id': record.processed_by.id if record.processed_by else None,
            'processed_date': record.processed_date.isoformat() if record.processed_date else None,
            'invoice_id': record.invoice_id.id if record.invoice_id else None,
            'invoice_name': record.invoice_id.name if record.invoice_id else None,
            'invoice_state': record.invoice_id.state if record.invoice_id else None,
            'scan_date': record.scan_date.isoformat() if record.scan_date else None,
            'scanned_by': record.scanned_by.name if record.scanned_by else '',
            'error_message': record.error_message or '',
            # Champs pour le suivi des doublons
            'duplicate_count': record.duplicate_count,
            'last_duplicate_attempt': record.last_duplicate_attempt.isoformat() if record.last_duplicate_attempt else None,
            'last_duplicate_user': record.last_duplicate_user_id.name if record.last_duplicate_user_id else '',
        }

    def _format_invoice(self, invoice):
        """Formater une facture pour l'API."""
        return {
            'id': invoice.id,
            'name': invoice.name,
            'ref': invoice.ref or '',
            'partner_id': invoice.partner_id.id,
            'partner_name': invoice.partner_id.name,
            'invoice_date': invoice.invoice_date.isoformat() if invoice.invoice_date else None,
            'amount_total': invoice.amount_total,
            'amount_residual': invoice.amount_residual,
            'currency': invoice.currency_id.name,
            'state': invoice.state,
            'state_label': dict(invoice._fields['state'].selection).get(invoice.state, ''),
            'is_from_qr_scan': invoice.is_from_qr_scan,
            'qr_scan_uuid': invoice.qr_scan_uuid or '',
        }

    # ==================== ENDPOINTS AUTH ====================

    @http.route('/api/v1/invoice-scanner/auth/login', type='http', auth='none', 
                methods=['POST', 'OPTIONS'], csrf=False, cors='*')
    @api_exception_handler
    def login(self, **kw):
        """Authentifier un utilisateur.
        
        Body JSON:
        - login: Email ou identifiant
        - password: Mot de passe
        
        Returns:
        - token: Token d'authentification
        - user: Données utilisateur
        """
        # Handle CORS preflight
        if request.httprequest.method == 'OPTIONS':
            return Response(status=200)
            
        data = get_json_body()
        login = data.get('login', '').strip()
        password = data.get('password', '')
        
        if not login or not password:
            return api_error('VALIDATION_ERROR', 'Login et mot de passe requis', status=400)
        
        # Authentification Odoo
        try:
            uid = request.session.authenticate(
                request.env.cr.dbname,
                login,
                password
            )
        except Exception as e:
            _logger.warning(f"Échec authentification pour {login}: {e}")
            uid = False
        
        if not uid:
            return api_error('AUTH_FAILED', 'Identifiants incorrects', status=401)
        
        user = request.env['res.users'].sudo().browse(uid)
        
        if not user.active:
            return api_error('USER_INACTIVE', 'Compte désactivé', status=403)
        
        # Vérifier le droit d'accès au module
        has_access = user.has_group('invoice_qr_scanner.group_invoice_scanner_user')
        if not has_access:
            return api_error('ACCESS_DENIED', 'Accès non autorisé au scanner de factures', status=403)
        
        # Générer le token
        token = self._generate_api_token()
        token_hash = self._hash_token(token)
        expires_at = fields.Datetime.now() + timedelta(hours=TOKEN_EXPIRY_HOURS)
        
        # Sauvegarder le token
        request.env['invoice.scanner.api.token'].sudo().create({
            'user_id': uid,
            'token_hash': token_hash,
            'expires_at': expires_at,
            'device_info': request.httprequest.headers.get('User-Agent', '')[:200],
            'ip_address': get_client_ip(),
        })
        
        return api_response({
            'token': token,
            'expires_at': expires_at.isoformat(),
            'user': {
                'id': user.id,
                'name': user.name,
                'email': user.email or '',
                'login': user.login,
            }
        })

    @http.route('/api/v1/invoice-scanner/auth/logout', type='http', auth='none',
                methods=['POST', 'OPTIONS'], csrf=False, cors='*')
    @api_exception_handler
    def logout(self, **kw):
        """Déconnecter l'utilisateur en désactivant son token."""
        if request.httprequest.method == 'OPTIONS':
            return Response(status=200)
            
        auth_header = request.httprequest.headers.get('Authorization', '')
        
        if auth_header.startswith('Bearer '):
            token = auth_header[7:]
            token_hash = self._hash_token(token)
            
            request.env['invoice.scanner.api.token'].sudo().search([
                ('token_hash', '=', token_hash)
            ]).write({'is_active': False})
        
        return api_response(message='Déconnexion réussie')

    # ==================== ENDPOINTS SCAN ====================

    @http.route('/api/v1/invoice-scanner/scan', type='http', auth='none',
                methods=['POST', 'OPTIONS'], csrf=False, cors='*')
    @api_exception_handler
    @require_auth
    def scan_qr_code(self, user=None, **kw):
        """Scanner un QR-code et créer une facture.
        
        Body JSON:
        - qr_url: URL extraite du QR-code
        
        Returns:
        - scan_record: Enregistrement du scan
        - invoice: Facture créée (si succès)
        """
        if request.httprequest.method == 'OPTIONS':
            return Response(status=200)
            
        data = get_json_body()
        qr_url = data.get('qr_url', '').strip()
        
        if not qr_url:
            return api_error('VALIDATION_ERROR', 'URL du QR-code requise', status=400)
        
        # Vérifier que l'URL est valide (DGI)
        if 'services.fne.dgi.gouv.ci' not in qr_url:
            return api_error('INVALID_URL', 'URL non reconnue. Seules les factures DGI sont supportées.', status=400)
        
        # Traiter le scan
        ScanRecord = request.env['invoice.scan.record'].sudo()
        result = ScanRecord.process_qr_scan(qr_url, user_id=user.id)
        
        if result.get('success'):
            return api_response(result)
        else:
            # Pour les doublons, inclure les données de l'enregistrement existant
            error_data = None
            if result.get('error_code') == 'DUPLICATE' and result.get('existing_record'):
                error_data = {
                    'existing_record': result.get('existing_record'),
                    'duplicate_count': result.get('duplicate_count', 0),
                }
            
            return api_error(
                result.get('error_code', 'INVOICE_ERROR'),
                result.get('error', 'Erreur lors du scan'),
                status=400,
                data=error_data
            )

    @http.route('/api/v1/invoice-scanner/check', type='http', auth='none',
                methods=['POST', 'OPTIONS'], csrf=False, cors='*')
    @api_exception_handler
    @require_auth
    def check_qr_code(self, user=None, **kw):
        """Vérifier si un QR-code a déjà été scanné (sans créer de facture).
        
        Body JSON:
        - qr_url: URL extraite du QR-code
        
        Returns:
        - exists: Boolean
        - scan_record: Enregistrement existant si présent
        """
        if request.httprequest.method == 'OPTIONS':
            return Response(status=200)
            
        data = get_json_body()
        qr_url = data.get('qr_url', '').strip()
        
        if not qr_url:
            return api_error('VALIDATION_ERROR', 'URL du QR-code requise', status=400)
        
        ScanRecord = request.env['invoice.scan.record'].sudo()
        qr_uuid = ScanRecord.extract_uuid_from_url(qr_url)
        
        if not qr_uuid:
            return api_error('INVALID_URL', 'URL invalide - UUID non trouvé', status=400)
        
        existing = ScanRecord.check_duplicate(qr_uuid)
        
        if existing:
            return api_response({
                'exists': True,
                'scan_record': self._format_scan_record(existing)
            })
        
        return api_response({
            'exists': False,
            'qr_uuid': qr_uuid
        })

    @http.route('/api/v1/invoice-scanner/report-duplicate', type='http', auth='none',
                methods=['POST', 'OPTIONS'], csrf=False, cors='*')
    @api_exception_handler
    @require_auth
    def report_duplicate(self, user=None, **kw):
        """Signaler une tentative de scan doublon détectée côté client.
        
        Cet endpoint est appelé quand le client détecte un doublon dans son cache local.
        Il incrémente le compteur duplicate_count côté serveur pour maintenir la cohérence.
        
        Body JSON:
        - qr_url: URL extraite du QR-code
        
        Returns:
        - success: Boolean
        - record: Enregistrement mis à jour avec le nouveau compteur
        """
        if request.httprequest.method == 'OPTIONS':
            return Response(status=200)
            
        data = get_json_body()
        qr_url = data.get('qr_url', '').strip()
        
        if not qr_url:
            return api_error('VALIDATION_ERROR', 'URL du QR-code requise', status=400)
        
        ScanRecord = request.env['invoice.scan.record'].sudo()
        qr_uuid = ScanRecord.extract_uuid_from_url(qr_url)
        
        if not qr_uuid:
            return api_error('INVALID_URL', 'URL invalide - UUID non trouvé', status=400)
        
        existing = ScanRecord.check_duplicate(qr_uuid)
        
        if not existing:
            return api_error('NOT_FOUND', 'Enregistrement non trouvé', status=404)
        
        # Incrémenter le compteur de doublons
        existing.write({
            'duplicate_count': existing.duplicate_count + 1,
            'last_duplicate_attempt': fields.Datetime.now(),
            'last_duplicate_user_id': user.id,
        })
        
        # Log pour traçabilité
        existing.message_post(
            body=f"Tentative de scan doublon #{existing.duplicate_count} signalée par {user.name} (depuis le cache local)",
            message_type='notification'
        )
        
        return api_response({
            'success': True,
            'message': 'Doublon signalé avec succès',
            'duplicate_count': existing.duplicate_count,
            'record': {
                'id': existing.id,
                'reference': existing.reference,
                'supplier_name': existing.supplier_name or '',
                'supplier_code_dgi': existing.supplier_code_dgi or '',
                'invoice_number_dgi': existing.invoice_number_dgi or '',
                'amount_ttc': existing.amount_ttc or 0,
                'state': existing.state,
                'state_label': dict(existing._fields['state'].selection).get(existing.state, ''),
                'invoice_id': existing.invoice_id.id if existing.invoice_id else None,
                'invoice_name': existing.invoice_id.name if existing.invoice_id else None,
                'scan_date': existing.scan_date.isoformat() if existing.scan_date else None,
                'scanned_by': existing.scanned_by.name if existing.scanned_by else '',
                'duplicate_count': existing.duplicate_count,
                'last_duplicate_attempt': existing.last_duplicate_attempt.isoformat() if existing.last_duplicate_attempt else None,
                'last_duplicate_user': user.name,
            }
        })

    # ==================== ENDPOINTS TRAITEMENT (MARQUAGE TRAITÉ) ====================

    @http.route('/api/v1/invoice-scanner/mark-processed/<int:record_id>', type='http', auth='none',
                methods=['POST', 'OPTIONS'], csrf=False, cors='*')
    @api_exception_handler
    @require_auth
    def mark_processed(self, record_id, user=None, **kw):
        """Marquer un scan comme traité/enregistré.
        
        Returns:
        - success: Boolean
        - record: Enregistrement mis à jour
        """
        if request.httprequest.method == 'OPTIONS':
            return Response(status=200)
            
        ScanRecord = request.env['invoice.scan.record'].sudo()
        record = ScanRecord.browse(record_id)
        
        if not record.exists():
            return api_error('NOT_FOUND', 'Enregistrement non trouvé', status=404)
        
        if record.state not in ('done',):
            return api_error(
                'INVALID_STATE',
                f"Seuls les scans avec facture créée peuvent être marqués comme traités (état actuel: {record.state})",
                status=400
            )
        
        record.write({
            'state': 'processed',
            'processed_by': user.id,
            'processed_date': fields.Datetime.now(),
        })
        
        record.message_post(
            body=f"Scan marqué comme traité par {user.name} (depuis l'application mobile)",
            message_type='notification'
        )
        
        return api_response({
            'success': True,
            'message': 'Scan marqué comme traité',
            'record': self._format_scan_record(record),
        })

    @http.route('/api/v1/invoice-scanner/mark-unprocessed/<int:record_id>', type='http', auth='none',
                methods=['POST', 'OPTIONS'], csrf=False, cors='*')
    @api_exception_handler
    @require_auth
    def mark_unprocessed(self, record_id, user=None, **kw):
        """Remettre un scan à l'état 'Facture créée' (non traité).
        
        Returns:
        - success: Boolean
        - record: Enregistrement mis à jour
        """
        if request.httprequest.method == 'OPTIONS':
            return Response(status=200)
            
        ScanRecord = request.env['invoice.scan.record'].sudo()
        record = ScanRecord.browse(record_id)
        
        if not record.exists():
            return api_error('NOT_FOUND', 'Enregistrement non trouvé', status=404)
        
        if record.state != 'processed':
            return api_error(
                'INVALID_STATE',
                f"Seuls les scans traités peuvent être remis à 'Facture créée' (état actuel: {record.state})",
                status=400
            )
        
        record.write({
            'state': 'done',
            'processed_by': False,
            'processed_date': False,
        })
        
        record.message_post(
            body=f"Scan remis à 'Facture créée' par {user.name} (depuis l'application mobile)",
            message_type='notification'
        )
        
        return api_response({
            'success': True,
            'message': 'Scan remis à l\'état non traité',
            'record': self._format_scan_record(record),
        })

    @http.route('/api/v1/invoice-scanner/bulk-mark-processed', type='http', auth='none',
                methods=['POST', 'OPTIONS'], csrf=False, cors='*')
    @api_exception_handler
    @require_auth
    def bulk_mark_processed(self, user=None, **kw):
        """Marquer plusieurs scans comme traités en masse.
        
        Body JSON:
        - record_ids: Liste des IDs à marquer (optionnel, sinon tous les 'done' éligibles)
        - max_records: Nombre maximum à traiter (défaut: 50, max: 200)
        
        Returns:
        - results: Résultat pour chaque enregistrement
        - summary: Résumé des résultats
        """
        if request.httprequest.method == 'OPTIONS':
            return Response(status=200)
            
        data = get_json_body()
        record_ids = data.get('record_ids', [])
        max_records = min(200, max(1, int(data.get('max_records', 50))))
        
        ScanRecord = request.env['invoice.scan.record'].sudo()
        
        # Construire le domaine
        domain = [
            ('company_id', '=', request.env.company.id),
            ('state', '=', 'done'),
        ]
        
        if record_ids:
            domain.append(('id', 'in', record_ids))
        
        records = ScanRecord.search(domain, limit=max_records, order='scan_date asc')
        
        results = []
        now = fields.Datetime.now()
        
        for record in records:
            try:
                record.write({
                    'state': 'processed',
                    'processed_by': user.id,
                    'processed_date': now,
                })
                record.message_post(
                    body=f"Scan marqué comme traité par {user.name} (marquage en masse depuis l'application mobile)",
                    message_type='notification'
                )
                results.append({
                    'record_id': record.id,
                    'reference': record.reference,
                    'success': True,
                })
            except Exception as e:
                results.append({
                    'record_id': record.id,
                    'reference': record.reference,
                    'success': False,
                    'error': str(e),
                })
        
        successful = sum(1 for r in results if r.get('success'))
        
        return api_response({
            'results': results,
            'summary': {
                'total_processed': len(results),
                'successful': successful,
                'failed': len(results) - successful,
            }
        })

    # ==================== ENDPOINTS HISTORIQUE ====================

    @http.route('/api/v1/invoice-scanner/history', type='http', auth='none',
                methods=['GET', 'POST', 'OPTIONS'], csrf=False, cors='*')
    @api_exception_handler
    @require_auth
    def get_history(self, user=None, **kw):
        """Obtenir l'historique des scans.
        
        Query params ou Body JSON (optionnel):
        - page: Numéro de page (défaut: 1)
        - limit: Nombre par page (défaut: 20, max: 100)
        - state: Filtrer par état (draft, done, duplicate, error)
        
        Returns:
        - records: Liste des scans
        - pagination: Informations de pagination
        """
        if request.httprequest.method == 'OPTIONS':
            return Response(status=200)
            
        # Accepter les paramètres en GET ou POST
        if request.httprequest.method == 'POST':
            data = get_json_body()
        else:
            data = dict(request.httprequest.args)
        
        page = max(1, int(data.get('page', 1)))
        limit = min(100, max(1, int(data.get('limit', 20))))
        state = data.get('state')
        
        ScanRecord = request.env['invoice.scan.record'].sudo()
        
        # Construire le domaine
        domain = [('company_id', '=', request.env.company.id)]
        if state:
            domain.append(('state', '=', state))
        
        # Comptage total
        total_count = ScanRecord.search_count(domain)
        
        # Récupérer les enregistrements
        offset = (page - 1) * limit
        records = ScanRecord.search(domain, limit=limit, offset=offset, order='create_date desc')
        
        return api_response({
            'records': [self._format_scan_record(r) for r in records],
            'pagination': {
                'page': page,
                'limit': limit,
                'total_count': total_count,
                'total_pages': (total_count + limit - 1) // limit,
                'has_next': offset + limit < total_count,
                'has_previous': page > 1,
            }
        })

    @http.route('/api/v1/invoice-scanner/invoice/<int:invoice_id>', type='http', auth='none',
                methods=['GET', 'OPTIONS'], csrf=False, cors='*')
    @api_exception_handler
    @require_auth
    def get_invoice_details(self, invoice_id, user=None, **kw):
        """Obtenir les détails d'une facture.
        
        Returns:
        - invoice: Détails de la facture
        """
        if request.httprequest.method == 'OPTIONS':
            return Response(status=200)
            
        invoice = request.env['account.move'].sudo().browse(invoice_id)
        
        if not invoice.exists():
            return api_error('NOT_FOUND', 'Facture non trouvée', status=404)
        
        return api_response(self._format_invoice(invoice))

    # ==================== ENDPOINTS UTILITAIRES ====================

    @http.route('/api/v1/invoice-scanner/health', type='http', auth='none',
                methods=['GET', 'OPTIONS'], csrf=False, cors='*')
    def health_check(self, **kw):
        """Vérifier l'état de l'API."""
        if request.httprequest.method == 'OPTIONS':
            return Response(status=200)
            
        return api_response({
            'status': 'healthy',
            'api_version': API_VERSION,
            'module': 'invoice_qr_scanner',
        })

    @http.route('/api/v1/invoice-scanner/test-dgi', type='http', auth='none',
                methods=['POST', 'OPTIONS'], csrf=False, cors='*')
    @api_exception_handler
    def test_dgi_extraction(self, **kw):
        """Endpoint de test pour vérifier l'extraction DGI (sans auth pour debug).
        
        Body JSON:
        - qr_url: URL de vérification DGI
        """
        if request.httprequest.method == 'OPTIONS':
            return Response(status=200)
            
        data = get_json_body()
        qr_url = data.get('qr_url', '').strip() or data.get('qr_content', '').strip()
        
        if not qr_url:
            return api_error('VALIDATION_ERROR', 'URL du QR-code requise (qr_url)', status=400)
        
        # Appeler la méthode d'extraction
        ScanRecord = request.env['invoice.scan.record'].sudo()
        dgi_data = ScanRecord.fetch_invoice_data_from_dgi(qr_url)
        
        return api_response({
            'qr_url': qr_url,
            'extraction_result': dgi_data
        })

    @http.route('/api/v1/invoice-scanner/stats', type='http', auth='none',
                methods=['GET', 'POST', 'OPTIONS'], csrf=False, cors='*')
    @api_exception_handler
    @require_auth
    def get_stats(self, user=None, **kw):
        """Obtenir les statistiques de scan."""
        if request.httprequest.method == 'OPTIONS':
            return Response(status=200)
            
        ScanRecord = request.env['invoice.scan.record'].sudo()
        company_id = request.env.company.id
        
        # Statistiques des enregistrements
        successful_scans = ScanRecord.search_count([
            ('company_id', '=', company_id),
            ('state', 'in', ['done', 'processed'])
        ])
        processed_scans = ScanRecord.search_count([
            ('company_id', '=', company_id),
            ('state', '=', 'processed')
        ])
        unprocessed_scans = ScanRecord.search_count([
            ('company_id', '=', company_id),
            ('state', '=', 'done')
        ])
        error_scans = ScanRecord.search_count([
            ('company_id', '=', company_id),
            ('state', '=', 'error')
        ])
        
        # Comptage total des tentatives de doublons (somme des duplicate_count)
        records_with_duplicates = ScanRecord.search([
            ('company_id', '=', company_id),
            ('duplicate_count', '>', 0)
        ])
        total_duplicate_attempts = sum(r.duplicate_count for r in records_with_duplicates)
        
        # Total scans = Réussis + Doublons + Erreurs (toutes les actions de scan)
        total_scans = successful_scans + total_duplicate_attempts + error_scans
        
        # Montant total des factures scannées
        records = ScanRecord.search([
            ('company_id', '=', company_id),
            ('state', 'in', ['done', 'processed'])
        ])
        total_amount = sum(r.amount_ttc for r in records)
        
        return api_response({
            'total_scans': total_scans,
            'successful_scans': successful_scans,
            'processed_scans': processed_scans,
            'unprocessed_scans': unprocessed_scans,
            'error_scans': error_scans,
            'duplicate_attempts': total_duplicate_attempts,
            'records_with_duplicates': len(records_with_duplicates),
            'total_amount': total_amount,
            'currency': 'XOF',
        })

    # ==================== ENDPOINT SYNC OFFLINE ====================

    @http.route('/api/v1/invoice-scanner/sync', type='http', auth='none',
                methods=['POST', 'OPTIONS'], csrf=False, cors='*')
    @api_exception_handler
    @require_auth
    def sync_offline_scans(self, user=None, **kw):
        """Synchroniser les scans effectués hors ligne.
        
        Body JSON:
        - scans: Liste des scans à synchroniser
            - qr_url: URL du QR-code
            - scanned_at: Date/heure du scan (ISO format)
        
        Returns:
        - results: Résultat pour chaque scan
        """
        if request.httprequest.method == 'OPTIONS':
            return Response(status=200)
            
        data = get_json_body()
        scans = data.get('scans', [])
        
        if not scans:
            return api_error('VALIDATION_ERROR', 'Liste de scans vide', status=400)
        
        if len(scans) > 50:
            return api_error('LIMIT_EXCEEDED', 'Maximum 50 scans par synchronisation', status=400)
        
        ScanRecord = request.env['invoice.scan.record'].sudo()
        results = []
        
        for scan in scans:
            qr_url = scan.get('qr_url', '').strip()
            scanned_at = scan.get('scanned_at')
            
            if not qr_url:
                results.append({
                    'qr_url': qr_url,
                    'success': False,
                    'error': 'URL manquante'
                })
                continue
            
            # Traiter le scan
            result = ScanRecord.process_qr_scan(qr_url, user_id=user.id)
            result['qr_url'] = qr_url
            result['scanned_at'] = scanned_at
            results.append(result)
        
        # Résumé
        successful = sum(1 for r in results if r.get('success'))
        duplicates = sum(1 for r in results if r.get('error_code') == 'DUPLICATE')
        errors = len(results) - successful - duplicates
        
        return api_response({
            'results': results,
            'summary': {
                'total': len(results),
                'successful': successful,
                'duplicates': duplicates,
                'errors': errors,
            }
        })

    # ==================== ENDPOINT ERREURS ====================

    @http.route('/api/v1/invoice-scanner/errors', type='http', auth='none',
                methods=['GET', 'POST', 'OPTIONS'], csrf=False, cors='*')
    @api_exception_handler
    @require_auth
    def get_errors(self, user=None, **kw):
        """Obtenir la liste des scans en erreur avec détails.
        
        Query params ou Body JSON (optionnel):
        - page: Numéro de page (défaut: 1)
        - limit: Nombre par page (défaut: 20, max: 100)
        - date_from: Date de début (format YYYY-MM-DD)
        - date_to: Date de fin (format YYYY-MM-DD)
        - retry_possible: Filtrer les erreurs pouvant être réessayées (true/false)
        
        Returns:
        - errors: Liste des scans en erreur avec détails
        - pagination: Informations de pagination
        - summary: Résumé des erreurs
        """
        if request.httprequest.method == 'OPTIONS':
            return Response(status=200)
            
        # Accepter les paramètres en GET ou POST
        if request.httprequest.method == 'POST':
            data = get_json_body()
        else:
            data = dict(request.httprequest.args)
        
        page = max(1, int(data.get('page', 1)))
        limit = min(100, max(1, int(data.get('limit', 20))))
        date_from = data.get('date_from')
        date_to = data.get('date_to')
        retry_possible = data.get('retry_possible')
        
        ScanRecord = request.env['invoice.scan.record'].sudo()
        
        # Construire le domaine
        domain = [
            ('company_id', '=', request.env.company.id),
            ('state', '=', 'error')
        ]
        
        # Filtres optionnels
        if date_from:
            domain.append(('scan_date', '>=', f'{date_from} 00:00:00'))
        if date_to:
            domain.append(('scan_date', '<=', f'{date_to} 23:59:59'))
        if retry_possible == 'true':
            domain.append(('invoice_id', '=', False))
        
        # Comptage total
        total_count = ScanRecord.search_count(domain)
        
        # Récupérer les enregistrements
        offset = (page - 1) * limit
        records = ScanRecord.search(domain, limit=limit, offset=offset, order='scan_date desc')
        
        # Formater les erreurs avec plus de détails
        errors_data = []
        for r in records:
            errors_data.append({
                'id': r.id,
                'reference': r.reference,
                'qr_uuid': r.qr_uuid,
                'qr_url': r.qr_url,
                'supplier_name': r.supplier_name or '',
                'invoice_number_dgi': r.invoice_number_dgi or '',
                'amount_ttc': r.amount_ttc,
                'error_message': r.error_message or 'Erreur inconnue',
                'error_type': self._classify_error(r.error_message),
                'scan_date': r.scan_date.isoformat() if r.scan_date else None,
                'scanned_by': r.scanned_by.name if r.scanned_by else '',
                'scanned_by_id': r.scanned_by.id if r.scanned_by else None,
                'can_retry': not r.invoice_id,  # Peut réessayer si pas de facture créée
                'retry_count': r.duplicate_count,  # Réutiliser pour compter les tentatives
            })
        
        # Résumé des types d'erreurs
        all_errors = ScanRecord.search([
            ('company_id', '=', request.env.company.id),
            ('state', '=', 'error')
        ])
        
        error_summary = {
            'total': len(all_errors),
            'dgi_errors': len(all_errors.filtered(lambda r: 'DGI' in (r.error_message or '').upper())),
            'network_errors': len(all_errors.filtered(lambda r: any(k in (r.error_message or '').lower() for k in ['timeout', 'connection', 'network', 'réseau']))),
            'parsing_errors': len(all_errors.filtered(lambda r: any(k in (r.error_message or '').lower() for k in ['parse', 'extract', 'format']))),
            'invoice_errors': len(all_errors.filtered(lambda r: any(k in (r.error_message or '').lower() for k in ['facture', 'invoice', 'compte', 'journal']))),
            'can_retry': len(all_errors.filtered(lambda r: not r.invoice_id)),
        }
        
        return api_response({
            'errors': errors_data,
            'pagination': {
                'page': page,
                'limit': limit,
                'total_count': total_count,
                'total_pages': (total_count + limit - 1) // limit,
                'has_next': offset + limit < total_count,
                'has_previous': page > 1,
            },
            'summary': error_summary,
        })

    def _classify_error(self, error_message):
        """Classifier le type d'erreur pour faciliter le filtrage."""
        if not error_message:
            return 'unknown'
        
        msg_lower = error_message.lower()
        
        if 'dgi' in msg_lower or 'fne' in msg_lower:
            return 'dgi_service'
        elif any(k in msg_lower for k in ['timeout', 'connection', 'network', 'réseau', 'connexion']):
            return 'network'
        elif any(k in msg_lower for k in ['parse', 'extract', 'format', 'uuid', 'url']):
            return 'parsing'
        elif any(k in msg_lower for k in ['facture', 'invoice', 'compte', 'journal', 'partner']):
            return 'invoice_creation'
        elif 'playwright' in msg_lower:
            return 'browser'
        else:
            return 'other'

    @http.route('/api/v1/invoice-scanner/errors/<int:record_id>/retry', type='http', auth='none',
                methods=['POST', 'OPTIONS'], csrf=False, cors='*')
    @api_exception_handler
    @require_auth
    def retry_error(self, record_id, user=None, **kw):
        """Réessayer la création de facture pour un scan en erreur.
        
        Returns:
        - success: Boolean
        - record: Enregistrement mis à jour
        - invoice: Facture créée (si succès)
        """
        if request.httprequest.method == 'OPTIONS':
            return Response(status=200)
            
        ScanRecord = request.env['invoice.scan.record'].sudo()
        record = ScanRecord.browse(record_id)
        
        if not record.exists():
            return api_error('NOT_FOUND', 'Enregistrement non trouvé', status=404)
        
        if record.state != 'error':
            return api_error('INVALID_STATE', f'L\'enregistrement n\'est pas en erreur (état: {record.state})', status=400)
        
        if record.invoice_id:
            return api_error('ALREADY_PROCESSED', 'Une facture existe déjà pour ce scan', status=400)
        
        # Réessayer la création de facture
        try:
            invoice = record._create_invoice()
            return api_response({
                'success': True,
                'message': 'Facture créée avec succès',
                'record': self._format_scan_record(record),
                'invoice': {
                    'id': invoice.id,
                    'name': invoice.name,
                    'state': invoice.state,
                    'amount_total': invoice.amount_total,
                    'partner_name': invoice.partner_id.name,
                }
            })
        except Exception as e:
            # Mettre à jour le message d'erreur
            record.write({
                'error_message': f'Nouvelle tentative échouée: {str(e)}'
            })
            return api_error(
                'RETRY_FAILED',
                f'Échec de la nouvelle tentative: {str(e)}',
                status=400
            )

    @http.route('/api/v1/invoice-scanner/errors/bulk-retry', type='http', auth='none',
                methods=['POST', 'OPTIONS'], csrf=False, cors='*')
    @api_exception_handler
    @require_auth
    def bulk_retry_errors(self, user=None, **kw):
        """Réessayer en masse les scans en erreur.
        
        Body JSON:
        - record_ids: Liste des IDs à réessayer (optionnel, sinon tous les éligibles)
        - max_records: Nombre maximum à traiter (défaut: 10, max: 50)
        
        Returns:
        - results: Résultat pour chaque enregistrement
        - summary: Résumé des résultats
        """
        if request.httprequest.method == 'OPTIONS':
            return Response(status=200)
            
        data = get_json_body()
        record_ids = data.get('record_ids', [])
        max_records = min(50, max(1, int(data.get('max_records', 10))))
        
        ScanRecord = request.env['invoice.scan.record'].sudo()
        
        # Construire le domaine
        domain = [
            ('company_id', '=', request.env.company.id),
            ('state', '=', 'error'),
            ('invoice_id', '=', False)  # Seulement ceux sans facture
        ]
        
        if record_ids:
            domain.append(('id', 'in', record_ids))
        
        records = ScanRecord.search(domain, limit=max_records, order='scan_date asc')
        
        results = []
        for record in records:
            try:
                invoice = record._create_invoice()
                results.append({
                    'record_id': record.id,
                    'reference': record.reference,
                    'success': True,
                    'invoice_id': invoice.id,
                    'invoice_name': invoice.name,
                })
            except Exception as e:
                record.write({
                    'error_message': f'Tentative groupée échouée: {str(e)}'
                })
                results.append({
                    'record_id': record.id,
                    'reference': record.reference,
                    'success': False,
                    'error': str(e),
                })
        
        successful = sum(1 for r in results if r.get('success'))
        
        return api_response({
            'results': results,
            'summary': {
                'total_processed': len(results),
                'successful': successful,
                'failed': len(results) - successful,
            }
        })
