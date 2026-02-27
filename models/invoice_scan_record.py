# -*- coding: utf-8 -*-
"""
Modèle pour enregistrer les scans de QR-code de factures
"""

import logging
import requests
from bs4 import BeautifulSoup
import re
from datetime import datetime

from odoo import api, fields, models, _
from odoo.exceptions import UserError, ValidationError

_logger = logging.getLogger(__name__)

# URL de base du service DGI
DGI_BASE_URL = "https://www.services.fne.dgi.gouv.ci/fr/verification/"


class InvoiceScanRecord(models.Model):
    """Enregistrement d'un scan de QR-code de facture DGI.
    
    Chaque scan crée un enregistrement qui stocke :
    - L'UUID de vérification (clé unique)
    - Les données récupérées du site DGI
    - La facture fournisseur créée
    """
    _name = 'invoice.scan.record'
    _description = "Enregistrement de scan QR facture"
    _inherit = ['mail.thread', 'mail.activity.mixin']
    _order = 'create_date desc'
    _rec_name = 'reference'

    # Champs d'identification
    reference = fields.Char(
        string="Référence",
        required=True,
        copy=False,
        readonly=True,
        default='/',
        index=True
    )
    
    qr_uuid = fields.Char(
        string="UUID Vérification",
        required=True,
        index=True,
        tracking=True,
        help="UUID extrait de l'URL du QR-code (identifiant unique DGI)"
    )
    
    qr_url = fields.Char(
        string="URL QR-code",
        required=True,
        tracking=True
    )
    
    # Données récupérées du site DGI
    supplier_name = fields.Char(
        string="Nom fournisseur (DGI)",
        tracking=True
    )
    
    supplier_code_dgi = fields.Char(
        string="Code DGI fournisseur",
        tracking=True,
        help="Code DGI du fournisseur (ex: 2502298K)"
    )
    
    customer_name = fields.Char(
        string="Nom client (DGI)",
        tracking=True
    )
    
    customer_code_dgi = fields.Char(
        string="Code DGI client",
        tracking=True
    )
    
    invoice_number_dgi = fields.Char(
        string="N° Facture DGI",
        tracking=True,
        help="Numéro de facture attribué par la DGI"
    )
    
    invoice_date = fields.Date(
        string="Date facturation",
        tracking=True
    )
    
    verification_id = fields.Char(
        string="ID Vérification DGI",
        tracking=True
    )
    
    amount_ttc = fields.Monetary(
        string="Montant TTC",
        currency_field='currency_id',
        tracking=True
    )
    
    currency_id = fields.Many2one(
        'res.currency',
        string="Devise",
        default=lambda self: self.env['res.currency'].search([('name', '=', 'XOF')], limit=1),
        required=True
    )
    
    # Relation avec la facture Odoo
    invoice_id = fields.Many2one(
        'account.move',
        string="Facture fournisseur",
        readonly=True,
        tracking=True
    )
    
    partner_id = fields.Many2one(
        'res.partner',
        string="Fournisseur",
        readonly=True,
        tracking=True
    )
    
    # État
    state = fields.Selection([
        ('draft', 'Brouillon'),
        ('done', 'Facture créée'),
        ('processed', 'Traité'),
        ('error', 'Erreur'),
    ], string="État", default='draft', tracking=True, index=True)
    
    error_message = fields.Text(
        string="Message d'erreur"
    )
    
    # Champs de traitement (marquage traité par le scanner)
    processed_by = fields.Many2one(
        'res.users',
        string="Traité par",
        readonly=True,
        tracking=True,
        help="Utilisateur ayant marqué ce scan comme traité"
    )
    
    processed_date = fields.Datetime(
        string="Date de traitement",
        readonly=True,
        tracking=True,
        help="Date/heure à laquelle le scan a été marqué comme traité"
    )
    
    is_processed = fields.Boolean(
        string="Traité",
        compute='_compute_is_processed',
        store=True,
        help="Indique si le scan a été marqué comme traité/enregistré"
    )
    
    # Compteur de doublons (au lieu de créer des enregistrements multiples)
    duplicate_count = fields.Integer(
        string="Tentatives de doublons",
        default=0,
        help="Nombre de fois que ce QR-code a été scanné après la première fois"
    )
    
    last_duplicate_attempt = fields.Datetime(
        string="Dernière tentative doublon",
        help="Date/heure de la dernière tentative de scan en doublon"
    )
    
    last_duplicate_user_id = fields.Many2one(
        'res.users',
        string="Dernier utilisateur doublon",
        help="Utilisateur ayant fait la dernière tentative de scan en doublon"
    )
    
    # Compteur de tentatives de retraitement (facture déjà traitée)
    reprocess_attempt_count = fields.Integer(
        string="Tentatives de retraitement",
        default=0,
        help="Nombre de fois qu'un utilisateur a tenté de traiter une facture déjà traitée"
    )
    
    last_reprocess_attempt = fields.Datetime(
        string="Dernière tentative de retraitement",
        help="Date/heure de la dernière tentative de retraitement"
    )
    
    last_reprocess_user_id = fields.Many2one(
        'res.users',
        string="Dernier utilisateur retraitement",
        help="Utilisateur ayant fait la dernière tentative de retraitement"
    )
    
    # Informations de scan
    scanned_by = fields.Many2one(
        'res.users',
        string="Scanné par",
        default=lambda self: self.env.user,
        readonly=True
    )
    
    scan_date = fields.Datetime(
        string="Date du scan",
        default=fields.Datetime.now,
        readonly=True
    )
    
    company_id = fields.Many2one(
        'res.company',
        string="Société",
        default=lambda self: self.env.company,
        required=True
    )
    
    raw_html = fields.Text(
        string="Données brutes HTML",
        help="HTML récupéré du site DGI pour débogage"
    )

    _sql_constraints = [
        ('qr_uuid_unique', 'unique(qr_uuid, company_id)', 
         'Ce QR-code a déjà été scanné pour cette société!')
    ]

    @api.depends('state')
    def _compute_is_processed(self):
        for record in self:
            record.is_processed = record.state == 'processed'

    @api.model_create_multi
    def create(self, vals_list):
        for vals in vals_list:
            if vals.get('reference', '/') == '/':
                vals['reference'] = self.env['ir.sequence'].next_by_code('invoice.scan.record') or '/'
        return super().create(vals_list)

    def action_mark_processed(self):
        """Marquer le(s) scan(s) comme traité(s)/enregistré(s)."""
        records = self.filtered(lambda r: r.state == 'done')
        if not records:
            raise UserError(_("Seuls les scans avec facture créée peuvent être marqués comme traités."))
        
        records.write({
            'state': 'processed',
            'processed_by': self.env.user.id,
            'processed_date': fields.Datetime.now(),
        })
        
        for record in records:
            record.message_post(
                body=_("Scan marqué comme traité par %s") % self.env.user.name,
                message_type='notification'
            )
        
        return True

    def action_mark_unprocessed(self):
        """Remettre le(s) scan(s) à l'état 'Facture créée' (non traité)."""
        records = self.filtered(lambda r: r.state == 'processed')
        if not records:
            raise UserError(_("Seuls les scans traités peuvent être remis à l'état 'Facture créée'."))
        
        records.write({
            'state': 'done',
            'processed_by': False,
            'processed_date': False,
        })
        
        for record in records:
            record.message_post(
                body=_("Scan remis à 'Facture créée' par %s") % self.env.user.name,
                message_type='notification'
            )
        
        return True

    @api.model
    def extract_uuid_from_url(self, url):
        """Extraire l'UUID de vérification de l'URL du QR-code.
        
        Args:
            url: URL du QR-code (ex: https://www.services.fne.dgi.gouv.ci/fr/verification/019bd62c-467e-7000-82ac-45c8389c7f05)
            
        Returns:
            str: UUID ou None
        """
        # Pattern UUID: 8-4-4-4-12 caractères hexadécimaux
        pattern = r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
        match = re.search(pattern, url, re.IGNORECASE)
        return match.group(0).lower() if match else None

    @api.model
    def _extract_dgi_data_from_text(self, text_content, raw_html=''):
        """Extraire les données de facture DGI depuis le texte rendu.
        
        Méthode utilitaire partagée entre l'approche Playwright et le fallback requests.
        
        Args:
            text_content: Texte brut de la page
            raw_html: HTML brut (optionnel, pour debug)
            
        Returns:
            dict: Données extraites de la facture
        """
        data = {
            'raw_html': raw_html[:5000] if raw_html else '',
            'text_content': text_content[:3000],
            'success': True,
        }
        
        # Fournisseur (format: "NOM - CODE" sur plusieurs lignes)
        supplier_match = re.search(
            r'FOURNISSEUR:\s*\n*\s*([A-Z0-9\s\-\.&\']+?)\s*-\s*([A-Z0-9]+)',
            text_content, re.IGNORECASE | re.MULTILINE
        )
        if supplier_match:
            data['supplier_name'] = supplier_match.group(1).strip()
            data['supplier_code_dgi'] = supplier_match.group(2).strip()
        
        # Client (format: "NOM - CODE")
        client_match = re.search(
            r'CLIENT:\s*\n*\s*([A-Z0-9\s\-\.&\']+?)\s*-\s*([A-Z0-9]+)',
            text_content, re.IGNORECASE | re.MULTILINE
        )
        if client_match:
            data['customer_name'] = client_match.group(1).strip()
            data['customer_code_dgi'] = client_match.group(2).strip()
        
        # Numéro de facture
        invoice_match = re.search(
            r'NUMERO DE FACTURE:\s*\n*\s*([A-Z0-9]+)',
            text_content, re.IGNORECASE | re.MULTILINE
        )
        if invoice_match:
            data['invoice_number_dgi'] = invoice_match.group(1).strip()
        
        # Date de facturation (format: DD/MM/YYYY)
        date_match = re.search(
            r'DATE DE FACTURATION:\s*\n*\s*(\d{2}/\d{2}/\d{4})',
            text_content, re.IGNORECASE | re.MULTILINE
        )
        if date_match:
            date_str = date_match.group(1)
            data['invoice_date'] = datetime.strptime(date_str, '%d/%m/%Y').date()
        
        # ID Vérification
        verif_match = re.search(
            r'ID VERIFICATION:\s*\n*\s*([A-Z0-9\-]+)',
            text_content, re.IGNORECASE | re.MULTILINE
        )
        if verif_match:
            data['verification_id'] = verif_match.group(1).strip()
        
        # Montant TTC (format: "1 677 566 CFA" ou "1 677 566 FCFA")
        amount_match = re.search(
            r'MONTANT TTC:\s*\n*\s*([\d\s]+)\s*(?:F?CFA)',
            text_content, re.IGNORECASE | re.MULTILINE
        )
        if amount_match:
            amount_str = amount_match.group(1).replace(' ', '').replace('\u00a0', '').strip()
            data['amount_ttc'] = float(amount_str)
        
        _logger.info(f"DGI Data extracted: supplier={data.get('supplier_name')}, "
                     f"amount={data.get('amount_ttc')}, invoice={data.get('invoice_number_dgi')}")
        
        return data

    @api.model
    def _fetch_dgi_with_requests(self, url):
        """Tentative de récupération des données DGI via requests (sans navigateur).
        
        Certaines pages DGI peuvent renvoyer les données directement dans le HTML
        ou via une API JSON interne. Cette méthode essaie d'abord sans Playwright.
        
        Args:
            url: URL complète de vérification DGI
            
        Returns:
            dict ou None: Données si trouvées, None si JS rendering nécessaire
        """
        try:
            headers = {
                'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
                              'AppleWebKit/537.36 (KHTML, like Gecko) '
                              'Chrome/120.0.0.0 Safari/537.36',
                'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                'Accept-Language': 'fr-FR,fr;q=0.9,en;q=0.8',
            }
            
            # Extraire l'UUID pour tenter l'API directe
            uuid = self.extract_uuid_from_url(url)
            
            # Tentative 1: API JSON directe (si le site expose une API)
            if uuid:
                api_urls = [
                    f"https://www.services.fne.dgi.gouv.ci/api/verification/{uuid}",
                    f"https://www.services.fne.dgi.gouv.ci/api/v1/verification/{uuid}",
                ]
                for api_url in api_urls:
                    try:
                        resp = requests.get(api_url, headers=headers, timeout=15, verify=True)
                        if resp.status_code == 200:
                            json_data = resp.json()
                            if json_data and isinstance(json_data, dict):
                                _logger.info(f"DGI API directe a retourné des données: {list(json_data.keys())}")
                                # Mapper les données JSON vers notre format
                                data = {'success': True, 'raw_html': '', 'text_content': str(json_data)[:3000]}
                                # Essayer de mapper les clés communes
                                for key in ['supplier_name', 'fournisseur', 'supplierName']:
                                    if key in json_data:
                                        data['supplier_name'] = json_data[key]
                                for key in ['amount_ttc', 'montantTtc', 'montant_ttc', 'totalAmount']:
                                    if key in json_data:
                                        data['amount_ttc'] = float(str(json_data[key]).replace(' ', ''))
                                for key in ['invoice_number', 'invoiceNumber', 'numero_facture']:
                                    if key in json_data:
                                        data['invoice_number_dgi'] = json_data[key]
                                if data.get('supplier_name') or data.get('amount_ttc'):
                                    return data
                    except (requests.exceptions.RequestException, ValueError):
                        continue
            
            # Tentative 2: HTML direct (SSR - Server Side Rendering)
            resp = requests.get(url, headers=headers, timeout=30, verify=True)
            if resp.status_code == 200:
                text_content = BeautifulSoup(resp.text, 'html.parser').get_text(separator='\n')
                if 'FOURNISSEUR' in text_content.upper() or 'NUMERO DE FACTURE' in text_content.upper():
                    _logger.info("DGI: Données trouvées via requests (SSR), Playwright non nécessaire")
                    return self._extract_dgi_data_from_text(text_content, resp.text)
            
            _logger.info("DGI: Données non trouvées via requests, Playwright nécessaire")
            return None
            
        except Exception as e:
            _logger.warning(f"Fallback requests DGI échoué (non bloquant): {e}")
            return None

    @api.model
    def _launch_playwright_browser(self, playwright_instance, max_retries=3):
        """Lancer le navigateur Playwright avec mécanisme de retry.
        
        Le navigateur Chromium peut crasher au lancement (SIGTRAP) en cas de
        pression mémoire sur le serveur. Cette méthode réessaie plusieurs fois
        avec un délai croissant entre chaque tentative.
        
        Args:
            playwright_instance: Instance Playwright (p)
            max_retries: Nombre maximum de tentatives (défaut: 3)
            
        Returns:
            Browser: Instance du navigateur lancé
            
        Raises:
            Exception: Si toutes les tentatives échouent
        """
        import time
        
        last_error = None
        for attempt in range(1, max_retries + 1):
            try:
                _logger.info(f"Lancement Chromium (tentative {attempt}/{max_retries})")
                browser = playwright_instance.chromium.launch(
                    headless=True,
                    args=[
                        '--no-sandbox',
                        '--disable-setuid-sandbox',
                        '--disable-dev-shm-usage',
                        '--disable-web-security',
                        '--disable-gpu',
                        '--disable-extensions',
                        '--disable-software-rasterizer',
                        '--disable-features=VizDisplayCompositor',
                    ]
                )
                _logger.info(f"Chromium lancé avec succès (tentative {attempt})")
                return browser
            except Exception as e:
                last_error = e
                error_msg = str(e)
                _logger.warning(
                    f"Échec lancement Chromium (tentative {attempt}/{max_retries}): {error_msg}"
                )
                if attempt < max_retries:
                    wait_time = attempt * 3  # 3s, 6s, 9s
                    _logger.info(f"Attente de {wait_time}s avant nouvelle tentative...")
                    time.sleep(wait_time)
        
        raise last_error

    @api.model
    def fetch_invoice_data_from_dgi(self, url):
        """Récupérer les données de la facture depuis le site DGI.
        
        Stratégie en 2 étapes:
        1. Essayer d'abord avec requests (rapide, sans navigateur)
        2. Si échec, utiliser Playwright avec retry (3 tentatives)
        
        Args:
            url: URL complète de vérification DGI
            
        Returns:
            dict: Données de la facture ou erreur
        """
        # Étape 1: Essayer sans Playwright (requests + BeautifulSoup)
        _logger.info(f"DGI: Tentative de récupération sans navigateur pour: {url}")
        requests_result = self._fetch_dgi_with_requests(url)
        if requests_result and requests_result.get('success'):
            return requests_result
        
        # Étape 2: Utiliser Playwright avec retry
        _logger.info(f"DGI: Utilisation de Playwright pour: {url}")
        browser = None
        context = None
        try:
            from playwright.sync_api import sync_playwright
            
            with sync_playwright() as p:
                # Lancement avec retry (3 tentatives)
                browser = self._launch_playwright_browser(p, max_retries=3)
                
                # Créer un contexte avec un User-Agent réel
                context = browser.new_context(
                    user_agent='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
                               'AppleWebKit/537.36 (KHTML, like Gecko) '
                               'Chrome/120.0.0.0 Safari/537.36',
                    viewport={'width': 1920, 'height': 1080},
                    locale='fr-FR',
                )
                page = context.new_page()
                
                # Charger la page et attendre le rendu JavaScript
                _logger.info(f"Chargement de l'URL DGI: {url}")
                page.goto(url, wait_until="networkidle", timeout=60000)
                
                # Attendre et vérifier si les données sont chargées
                max_attempts = 15
                text_content = ""
                for attempt in range(max_attempts):
                    page.wait_for_timeout(2000)  # Attendre 2s
                    text_content = page.inner_text("body")
                    if 'FOURNISSEUR' in text_content.upper() or 'NUMERO DE FACTURE' in text_content.upper():
                        _logger.info(f"Données DGI chargées après {(attempt + 1) * 2} secondes")
                        break
                    _logger.info(f"Tentative {attempt + 1}/{max_attempts} - Données non encore chargées. "
                                f"Texte: {text_content[:200]}")
                
                raw_html = page.content()[:5000]
                
                # Fermeture propre dans le bloc try
                try:
                    context.close()
                except Exception:
                    pass
                context = None
                try:
                    browser.close()
                except Exception:
                    pass
                browser = None
            
            return self._extract_dgi_data_from_text(text_content, raw_html)
            
        except ImportError:
            _logger.error("Playwright non installé. Installer avec: pip install playwright && playwright install chromium")
            return {'success': False, 'error': 'Playwright non installé sur le serveur'}
        except Exception as e:
            error_msg = str(e)
            _logger.error(f"Erreur lors de la récupération des données DGI: {error_msg}", exc_info=True)
            
            # Message d'erreur enrichi pour le diagnostic
            if 'Target page, context or browser has been closed' in error_msg or 'SIGTRAP' in error_msg:
                diagnostic = (
                    f"Erreur: Le navigateur Chromium a crashé sur le serveur. "
                    f"Causes possibles: mémoire insuffisante, /dev/shm trop petit "
                    f"(Docker: ajouter --shm-size=256m), ou binaire Chromium corrompu "
                    f"(réinstaller: playwright install chromium). Détail: {error_msg}"
                )
                _logger.error(diagnostic)
                return {'success': False, 'error': diagnostic}
            
            return {'success': False, 'error': f'Erreur: {error_msg}'}
        finally:
            # Nettoyage garanti même en cas d'exception
            try:
                if context:
                    context.close()
            except Exception:
                pass
            try:
                if browser:
                    browser.close()
            except Exception:
                pass

    @api.model
    def check_duplicate(self, qr_uuid):
        """Vérifier si ce QR-code a déjà été scanné avec succès (facture créée).
        
        Ne considère que les scans réussis (state='done' ou 'processed') pour détecter les doublons.
        Les enregistrements de type 'error' ne sont pas considérés.
        
        Returns:
            record: Enregistrement existant (done/processed) ou False
        """
        return self.search([
            ('qr_uuid', '=', qr_uuid),
            ('state', 'in', ['done', 'processed']),
            ('company_id', '=', self.env.company.id)
        ], limit=1)

    def _get_or_create_supplier(self):
        """Obtenir ou créer le fournisseur basé sur les données DGI."""
        self.ensure_one()
        Partner = self.env['res.partner']
        
        # Chercher par code DGI d'abord
        if self.supplier_code_dgi:
            partner = Partner.search([
                ('dgi_code', '=', self.supplier_code_dgi)
            ], limit=1)
            if partner:
                return partner
        
        # Chercher par nom
        if self.supplier_name:
            partner = Partner.search([
                ('name', 'ilike', self.supplier_name),
                ('supplier_rank', '>', 0)
            ], limit=1)
            if partner:
                # Mettre à jour le code DGI si absent
                if self.supplier_code_dgi and not partner.dgi_code:
                    partner.write({'dgi_code': self.supplier_code_dgi})
                return partner
        
        # Obtenir le compte payable par défaut
        payable_account = self.env['account.account'].search([
            ('account_type', '=', 'liability_payable'),
            ('company_id', '=', self.company_id.id),
        ], limit=1)
        
        # Obtenir le compte recevable par défaut
        receivable_account = self.env['account.account'].search([
            ('account_type', '=', 'asset_receivable'),
            ('company_id', '=', self.company_id.id),
        ], limit=1)
        
        # Créer le fournisseur avec les comptes comptables
        partner_vals = {
            'name': self.supplier_name or f"Fournisseur DGI {self.supplier_code_dgi}",
            'supplier_rank': 1,
            'is_company': True,
            'dgi_code': self.supplier_code_dgi,
        }
        
        if payable_account:
            partner_vals['property_account_payable_id'] = payable_account.id
        if receivable_account:
            partner_vals['property_account_receivable_id'] = receivable_account.id
        
        return Partner.create(partner_vals)

    def _get_or_create_purchase_journal(self):
        """Obtenir ou créer un journal d'achats."""
        Journal = self.env['account.journal']
        
        # Chercher un journal d'achats existant
        journal = Journal.search([
            ('type', '=', 'purchase'),
            ('company_id', '=', self.company_id.id),
        ], limit=1)
        
        if journal:
            return journal
        
        # Créer un journal d'achats
        journal_vals = {
            'name': 'Achats',
            'code': 'ACH',
            'type': 'purchase',
            'company_id': self.company_id.id,
        }
        
        return Journal.sudo().create(journal_vals)

    def _get_or_create_expense_account(self):
        """Obtenir ou créer un compte de dépense."""
        Account = self.env['account.account']
        
        # Chercher un compte de dépense existant
        expense_account = Account.search([
            ('account_type', '=', 'expense'),
            ('company_id', '=', self.company_id.id),
        ], limit=1)
        
        if expense_account:
            return expense_account
        
        # Essayer d'autres types de comptes de charge
        expense_account = Account.search([
            ('account_type', 'in', ['expense', 'expense_direct_cost', 'expense_depreciation']),
            ('company_id', '=', self.company_id.id),
        ], limit=1)
        
        if expense_account:
            return expense_account
        
        # Chercher par code (comptes de charges commencent souvent par 6)
        expense_account = Account.search([
            ('code', '=like', '6%'),
            ('company_id', '=', self.company_id.id),
        ], limit=1)
        
        if expense_account:
            return expense_account
        
        # Créer un compte de dépense par défaut
        account_vals = {
            'name': 'Achats de marchandises',
            'code': '607000',
            'account_type': 'expense',
            'company_id': self.company_id.id,
        }
        
        return Account.sudo().create(account_vals)

    def _create_invoice(self):
        """Créer la facture fournisseur."""
        self.ensure_one()
        
        # Vérifier si pas déjà fait
        if self.invoice_id:
            raise UserError(_("Une facture existe déjà pour ce scan."))
        
        # Obtenir le fournisseur
        partner = self._get_or_create_supplier()
        self.partner_id = partner
        
        # Obtenir ou créer le journal d'achats
        journal = self._get_or_create_purchase_journal()
        
        # Obtenir ou créer le compte de dépense
        expense_account = self._get_or_create_expense_account()
        
        # Configuration : valider automatiquement ou pas
        auto_validate = self.env['ir.config_parameter'].sudo().get_param(
            'invoice_qr_scanner.auto_validate_invoice', 'True'
        ) == 'True'
        
        # Créer la facture en deux étapes pour éviter les contraintes de ligne
        # Étape 1: Créer la facture sans lignes
        invoice = self.env['account.move'].create({
            'move_type': 'in_invoice',
            'journal_id': journal.id,
            'partner_id': partner.id,
            'invoice_date': self.invoice_date or fields.Date.today(),
            'ref': self.invoice_number_dgi,
            'qr_scan_uuid': self.qr_uuid,
            'qr_scan_record_id': self.id,
            'currency_id': self.currency_id.id,
        })
        
        # Étape 2: Ajouter la ligne de facture avec le bon contexte
        invoice.write({
            'invoice_line_ids': [(0, 0, {
                'name': f"Facture scannée - {self.invoice_number_dgi or self.qr_uuid}",
                'quantity': 1,
                'price_unit': self.amount_ttc or 0,
                'account_id': expense_account.id,
            })],
        })
        
        # Valider si configuré
        if auto_validate and invoice.state == 'draft':
            invoice.action_post()
        
        self.write({
            'invoice_id': invoice.id,
            'state': 'done',
        })
        
        return invoice

    @api.model
    def process_qr_scan(self, qr_url, user_id=None):
        """Traiter un scan de QR-code complet.
        
        Args:
            qr_url: URL scannée depuis le QR-code
            user_id: ID de l'utilisateur qui scanne (optionnel)
            
        Returns:
            dict: Résultat du traitement
        """
        # Extraire l'UUID
        qr_uuid = self.extract_uuid_from_url(qr_url)
        if not qr_uuid:
            return {
                'success': False,
                'error': 'URL invalide - Impossible d\'extraire l\'UUID',
                'error_code': 'INVALID_URL'
            }
        
        # Vérifier les doublons
        existing = self.check_duplicate(qr_uuid)
        if existing:
            # Incrémenter le compteur de doublons sur l'enregistrement original
            existing.write({
                'duplicate_count': existing.duplicate_count + 1,
                'last_duplicate_attempt': fields.Datetime.now(),
                'last_duplicate_user_id': user_id or self.env.user.id,
            })
            
            # Log pour traçabilité
            existing.message_post(
                body=f"Tentative de scan doublon #{existing.duplicate_count} par {self.env['res.users'].browse(user_id or self.env.user.id).name}",
                message_type='notification'
            )
            
            return {
                'success': False,
                'error': 'Cette facture a déjà été scannée',
                'error_code': 'DUPLICATE',
                'duplicate_count': existing.duplicate_count,
                'existing_record': {
                    'id': existing.id,
                    'reference': existing.reference,
                    'supplier_name': existing.supplier_name or '',
                    'supplier_code_dgi': existing.supplier_code_dgi or '',
                    'invoice_number_dgi': existing.invoice_number_dgi or '',
                    'amount_ttc': existing.amount_ttc or 0,
                    'invoice_id': existing.invoice_id.id if existing.invoice_id else None,
                    'invoice_name': existing.invoice_id.name if existing.invoice_id else None,
                    'scan_date': existing.scan_date.isoformat() if existing.scan_date else None,
                    'scanned_by': existing.scanned_by.name if existing.scanned_by else '',
                    'duplicate_count': existing.duplicate_count,
                    'last_duplicate_attempt': existing.last_duplicate_attempt.isoformat() if existing.last_duplicate_attempt else None,
                }
            }
        
        # Récupérer les données du site DGI
        dgi_data = self.fetch_invoice_data_from_dgi(qr_url)
        
        if not dgi_data.get('success'):
            # Créer un enregistrement d'erreur
            record = self.create({
                'qr_uuid': qr_uuid,
                'qr_url': qr_url,
                'state': 'error',
                'error_message': dgi_data.get('error', 'Erreur inconnue'),
                'scanned_by': user_id or self.env.user.id,
            })
            return {
                'success': False,
                'error': dgi_data.get('error'),
                'error_code': 'DGI_ERROR',
                'record_id': record.id,
            }
        
        # Créer l'enregistrement de scan
        record_vals = {
            'qr_uuid': qr_uuid,
            'qr_url': qr_url,
            'supplier_name': dgi_data.get('supplier_name'),
            'supplier_code_dgi': dgi_data.get('supplier_code_dgi'),
            'customer_name': dgi_data.get('customer_name'),
            'customer_code_dgi': dgi_data.get('customer_code_dgi'),
            'invoice_number_dgi': dgi_data.get('invoice_number_dgi'),
            'invoice_date': dgi_data.get('invoice_date'),
            'verification_id': dgi_data.get('verification_id'),
            'amount_ttc': dgi_data.get('amount_ttc', 0),
            'raw_html': dgi_data.get('raw_html'),
            'scanned_by': user_id or self.env.user.id,
            'state': 'draft',
        }
        
        record = self.create(record_vals)
        
        # Créer la facture
        try:
            invoice = record._create_invoice()
            return {
                'success': True,
                'message': 'Facture créée avec succès',
                'record': {
                    'id': record.id,
                    'reference': record.reference,
                },
                'invoice': {
                    'id': invoice.id,
                    'name': invoice.name,
                    'state': invoice.state,
                    'amount_total': invoice.amount_total,
                    'partner_name': invoice.partner_id.name,
                }
            }
        except Exception as e:
            record.write({
                'state': 'error',
                'error_message': str(e)
            })
            return {
                'success': False,
                'error': f'Erreur lors de la création de la facture: {str(e)}',
                'error_code': 'INVOICE_ERROR',
                'record_id': record.id,
            }

    def action_retry_create_invoice(self):
        """Réessayer de créer la facture après une erreur."""
        self.ensure_one()
        if self.state == 'error' and not self.invoice_id:
            try:
                self._create_invoice()
            except Exception as e:
                self.write({
                    'error_message': str(e)
                })
                raise UserError(_("Erreur: %s") % str(e))

    def action_view_invoice(self):
        """Ouvrir la facture associée."""
        self.ensure_one()
        if not self.invoice_id:
            raise UserError(_("Aucune facture associée."))
        
        return {
            'type': 'ir.actions.act_window',
            'name': _('Facture'),
            'res_model': 'account.move',
            'res_id': self.invoice_id.id,
            'view_mode': 'form',
            'target': 'current',
        }

    @api.model
    def get_dashboard_data(self, period='month'):
        """Récupérer les données pour le tableau de bord du Responsable.
        
        Args:
            period: Période d'analyse ('day', 'week', 'month', 'year')
            
        Returns:
            dict: Données du dashboard
        """
        import logging
        from datetime import datetime, timedelta
        
        _logger = logging.getLogger(__name__)
        
        try:
            company_id = self.env.company.id
            today = fields.Date.today()
            
            # Valider la période
            if period not in ('day', 'week', 'month', 'year'):
                period = 'month'
            
            # Calculer les dates selon la période
            if period == 'day':
                date_from = today
            elif period == 'week':
                date_from = today - timedelta(days=7)
            elif period == 'month':
                date_from = today - timedelta(days=30)
            else:  # year
                date_from = today - timedelta(days=365)
            
            # Domaine de base
            base_domain = [('company_id', '=', company_id)]
            date_from_dt = datetime.combine(date_from, datetime.min.time())
            period_domain = base_domain + [('scan_date', '>=', fields.Datetime.to_string(date_from_dt))]
            
            # Statistiques globales
            total_scans = self.search_count(period_domain)
            successful_scans = self.search_count(period_domain + [('state', 'in', ['done', 'processed'])])
            processed_scans = self.search_count(period_domain + [('state', '=', 'processed')])
            error_scans = self.search_count(period_domain + [('state', '=', 'error')])
            
            # Comptage des doublons (somme des duplicate_count)
            records_with_duplicates = self.search(period_domain + [('duplicate_count', '>', 0)])
            duplicate_attempts = sum(r.duplicate_count for r in records_with_duplicates)
            
            # Montant total des factures réussies
            successful_records = self.search(period_domain + [('state', 'in', ['done', 'processed'])])
            total_amount = sum(r.amount_ttc for r in successful_records)
            
            # Statistiques temporelles
            today_start = datetime.combine(today, datetime.min.time())
            week_start = today - timedelta(days=7)
            month_start = today - timedelta(days=30)
            
            today_scans = self.search_count(base_domain + [
                ('scan_date', '>=', fields.Datetime.to_string(today_start))
            ])
            week_scans = self.search_count(base_domain + [
                ('scan_date', '>=', fields.Datetime.to_string(datetime.combine(week_start, datetime.min.time())))
            ])
            month_scans = self.search_count(base_domain + [
                ('scan_date', '>=', fields.Datetime.to_string(datetime.combine(month_start, datetime.min.time())))
            ])
            
            # Scans récents (10 derniers)
            recent_scans = self.search(base_domain, limit=10, order='create_date desc')
            recent_scans_data = [{
                'id': r.id,
                'reference': r.reference or '',
                'supplier_name': r.supplier_name or '',
                'amount_ttc': r.amount_ttc or 0,
                'state': r.state or 'draft',
                'scan_date': r.scan_date.isoformat() if r.scan_date else None,
                'scanned_by_name': r.scanned_by.name if r.scanned_by else '',
            } for r in recent_scans]
            
            # Top utilisateurs (5 premiers)
            top_users = []
            try:
                self.env.cr.execute("""
                    SELECT u.id, COALESCE(rp.name, u.login) as name, COUNT(s.id) as scan_count
                    FROM invoice_scan_record s
                    JOIN res_users u ON s.scanned_by = u.id
                    LEFT JOIN res_partner rp ON u.partner_id = rp.id
                    WHERE s.company_id = %s
                    AND s.scan_date >= %s
                    GROUP BY u.id, rp.name, u.login
                    ORDER BY scan_count DESC
                    LIMIT 5
                """, (company_id, fields.Datetime.to_string(date_from_dt)))
                
                top_users = [{
                    'id': row[0],
                    'name': row[1] or 'Utilisateur',
                    'scan_count': row[2],
                } for row in self.env.cr.fetchall()]
            except Exception as e:
                _logger.warning(f"Erreur récupération top users: {e}")
            
            # Données pour graphiques (par jour sur la période)
            daily_data = []
            if period in ('week', 'month'):
                days = 7 if period == 'week' else 30
                for i in range(days, -1, -1):
                    day = today - timedelta(days=i)
                    day_start = datetime.combine(day, datetime.min.time())
                    day_end = datetime.combine(day, datetime.max.time())
                    count = self.search_count(base_domain + [
                        ('scan_date', '>=', fields.Datetime.to_string(day_start)),
                        ('scan_date', '<=', fields.Datetime.to_string(day_end)),
                    ])
                    daily_data.append({
                        'date': day.strftime('%d/%m'),
                        'count': count,
                    })
            
            return {
                'stats': {
                    'totalScans': total_scans,
                    'successfulScans': successful_scans,
                    'processedScans': processed_scans,
                    'duplicateAttempts': duplicate_attempts,
                    'recordsWithDuplicates': len(records_with_duplicates),
                    'errorScans': error_scans,
                    'totalAmount': total_amount,
                    'todayScans': today_scans,
                    'weekScans': week_scans,
                    'monthScans': month_scans,
                },
                'recent_scans': recent_scans_data,
                'top_users': top_users,
                'chart_data': {
                    'daily': daily_data,
                    'states': [
                        {'state': 'done', 'count': successful_scans},
                        {'state': 'duplicates', 'count': duplicate_attempts},
                        {'state': 'error', 'count': error_scans},
                    ],
                },
            }
        except Exception as e:
            _logger.error(f"Erreur get_dashboard_data: {e}")
            # Retourner des données vides en cas d'erreur
            return {
                'stats': {
                    'totalScans': 0,
                    'successfulScans': 0,
                    'duplicateAttempts': 0,
                    'recordsWithDuplicates': 0,
                    'errorScans': 0,
                    'totalAmount': 0,
                    'todayScans': 0,
                    'weekScans': 0,
                    'monthScans': 0,
                },
                'recent_scans': [],
                'top_users': [],
                'chart_data': {'daily': [], 'states': []},
            }
    @api.model
    def get_dashboard_stats(self, date_start=None, date_end=None, period='month'):
        """Récupérer les statistiques pour le dashboard OWL.
        
        Args:
            date_start: Date de début (format ISO)
            date_end: Date de fin (format ISO)
            period: Période d'analyse ('day', 'week', 'month', 'year')
            
        Returns:
            dict: Données formatées pour le dashboard OWL
        """
        import logging
        from datetime import datetime, timedelta
        
        _logger = logging.getLogger(__name__)
        
        try:
            company_id = self.env.company.id
            today = fields.Date.today()
            
            # Valider et convertir les dates
            if period not in ('day', 'week', 'month', 'year'):
                period = 'month'
            
            # Calculer les dates selon la période
            if period == 'day':
                date_from = today
            elif period == 'week':
                date_from = today - timedelta(days=7)
            elif period == 'month':
                date_from = today - timedelta(days=30)
            else:  # year
                date_from = today - timedelta(days=365)
            
            # Domaine de base
            base_domain = [('company_id', '=', company_id)]
            date_from_dt = datetime.combine(date_from, datetime.min.time())
            period_domain = base_domain + [('scan_date', '>=', fields.Datetime.to_string(date_from_dt))]
            
            # Statistiques de la période
            done_scans = self.search_count(period_domain + [('state', 'in', ['done', 'processed'])])
            processed_scans = self.search_count(period_domain + [('state', '=', 'processed')])
            pending_scans = self.search_count(period_domain + [('state', 'in', ['draft', 'pending'])])
            error_scans = self.search_count(period_domain + [('state', '=', 'error')])
            
            # Comptage des doublons de la période (somme des duplicate_count)
            records_with_duplicates = self.search(period_domain + [('duplicate_count', '>', 0)])
            duplicate_attempts = sum(r.duplicate_count for r in records_with_duplicates)
            
            # Total scans = Réussis + Doublons + Erreurs (représente toutes les actions de scan)
            total_scans = done_scans + duplicate_attempts + error_scans
            
            # === TOTAUX GLOBAUX (ALL-TIME) pour correspondre à l'application mobile ===
            all_time_done = self.search_count(base_domain + [('state', 'in', ['done', 'processed'])])
            all_time_processed = self.search_count(base_domain + [('state', '=', 'processed')])
            all_time_error = self.search_count(base_domain + [('state', '=', 'error')])
            all_time_records_with_dup = self.search(base_domain + [('duplicate_count', '>', 0)])
            all_time_duplicates = sum(r.duplicate_count for r in all_time_records_with_dup)
            # Total scans = Réussis + Doublons + Erreurs
            all_time_total = all_time_done + all_time_duplicates + all_time_error
            all_time_records = self.search(base_domain + [('state', 'in', ['done', 'processed'])])
            all_time_amount = sum(r.amount_ttc for r in all_time_records)
            
            # Montant total des factures réussies
            successful_records = self.search(period_domain + [('state', 'in', ['done', 'processed'])])
            total_amount = sum(r.amount_ttc for r in successful_records)
            
            # Scans récents (5 derniers)
            recent_scans = self.search(base_domain, limit=5, order='create_date desc')
            recent_scans_data = [{
                'id': r.id,
                'reference': r.reference or '',
                'nom_fournisseur': r.supplier_name or 'N/A',
                'montant_ttc': r.amount_ttc or 0,
                'state': 'processed' if r.state == 'processed' else ('verified' if r.state == 'done' else ('error' if r.state == 'error' else 'pending')),
                'duplicate_count': r.duplicate_count,
            } for r in recent_scans]
            
            # Top fournisseurs (5 premiers)
            top_suppliers = []
            try:
                self.env.cr.execute("""
                    SELECT supplier_name, COUNT(*) as scan_count
                    FROM invoice_scan_record
                    WHERE company_id = %s
                    AND supplier_name IS NOT NULL
                    AND supplier_name != ''
                    AND scan_date >= %s
                    GROUP BY supplier_name
                    ORDER BY scan_count DESC
                    LIMIT 5
                """, (company_id, fields.Datetime.to_string(date_from_dt)))
                
                top_suppliers = [{
                    'name': row[0] or 'Non défini',
                    'count': row[1],
                } for row in self.env.cr.fetchall()]
            except Exception as e:
                _logger.warning(f"Erreur récupération top suppliers: {e}")
            
            # Données pour graphique d'évolution
            chart_labels = []
            chart_scans = []
            chart_verified = []
            
            if period in ('week', 'month'):
                days = 7 if period == 'week' else 30
                for i in range(days, -1, -1):
                    day = today - timedelta(days=i)
                    day_start = datetime.combine(day, datetime.min.time())
                    day_end = datetime.combine(day, datetime.max.time())
                    
                    day_domain = base_domain + [
                        ('scan_date', '>=', fields.Datetime.to_string(day_start)),
                        ('scan_date', '<=', fields.Datetime.to_string(day_end)),
                    ]
                    
                    day_total = self.search_count(day_domain)
                    day_done = self.search_count(day_domain + [('state', '=', 'done')])
                    
                    chart_labels.append(day.strftime('%d/%m'))
                    chart_scans.append(day_total)
                    chart_verified.append(day_done)
            else:
                # Pour day et year, utiliser des données simplifiées
                chart_labels = ['Aujourd\'hui'] if period == 'day' else ['Jan', 'Fév', 'Mar', 'Avr', 'Mai', 'Jun', 'Jul', 'Aoû', 'Sep', 'Oct', 'Nov', 'Déc']
                chart_scans = [total_scans] if period == 'day' else [0] * 12
                chart_verified = [done_scans] if period == 'day' else [0] * 12
            
            return {
                'stats': {
                    'total_scans': total_scans,
                    'successful_scans': done_scans,
                    'processed_scans': processed_scans,
                    'duplicate_attempts': duplicate_attempts,
                    'records_with_duplicates': len(records_with_duplicates),
                    'error_scans': error_scans,
                    'total_amount': total_amount,
                },
                # Totaux globaux (all-time) pour correspondre à l'application mobile
                'all_time_stats': {
                    'total_scans': all_time_total,
                    'successful_scans': all_time_done,
                    'processed_scans': all_time_processed,
                    'duplicate_attempts': all_time_duplicates,
                    'records_with_duplicates': len(all_time_records_with_dup),
                    'error_scans': all_time_error,
                    'total_amount': all_time_amount,
                },
                'recent_scans': recent_scans_data,
                'top_suppliers': top_suppliers,
                'chart_data': {
                    'labels': chart_labels,
                    'scans': chart_scans,
                    'verified': chart_verified,
                },
            }
        except Exception as e:
            _logger.error(f"Erreur get_dashboard_stats: {e}")
            # Retourner des données vides en cas d'erreur
            empty_stats = {
                'total_scans': 0,
                'successful_scans': 0,
                'processed_scans': 0,
                'duplicate_attempts': 0,
                'records_with_duplicates': 0,
                'error_scans': 0,
                'total_amount': 0,
            }
            return {
                'stats': empty_stats,
                'all_time_stats': empty_stats,
                'recent_scans': [],
                'top_suppliers': [],
                'chart_data': {'labels': [], 'scans': [], 'verified': []},
            }

    @api.model
    def get_verificateur_dashboard_data(self, period='month'):
        """Récupérer les données pour le tableau de bord du Vérificateur.
        
        Le vérificateur voit ses propres scans, ses doublons détectés et ses factures créées.
        
        Args:
            period: Période d'analyse ('day', 'week', 'month', 'year')
            
        Returns:
            dict: Données du dashboard vérificateur
        """
        from datetime import datetime, timedelta
        
        try:
            company_id = self.env.company.id
            user_id = self.env.user.id
            today = fields.Date.today()
            
            if period not in ('day', 'week', 'month', 'year'):
                period = 'month'
            
            if period == 'day':
                date_from = today
            elif period == 'week':
                date_from = today - timedelta(days=7)
            elif period == 'month':
                date_from = today - timedelta(days=30)
            else:
                date_from = today - timedelta(days=365)
            
            base_domain = [('company_id', '=', company_id), ('scanned_by', '=', user_id)]
            date_from_dt = datetime.combine(date_from, datetime.min.time())
            period_domain = base_domain + [('scan_date', '>=', fields.Datetime.to_string(date_from_dt))]
            
            # Statistiques période
            total_scans_period = self.search_count(period_domain)
            successful_scans = self.search_count(period_domain + [('state', 'in', ['done', 'processed'])])
            error_scans = self.search_count(period_domain + [('state', '=', 'error')])
            
            # Doublons détectés par ce vérificateur
            records_with_dup = self.search(period_domain + [('duplicate_count', '>', 0)])
            duplicate_attempts = sum(r.duplicate_count for r in records_with_dup)
            
            # Doublons signalés par d'autres (ce vérificateur a scanné l'original)
            last_dup_by_others = self.search_count(period_domain + [
                ('last_duplicate_user_id', '!=', user_id),
                ('duplicate_count', '>', 0)
            ])
            
            total_scans = successful_scans + duplicate_attempts + error_scans
            
            # Montant total
            successful_records = self.search(period_domain + [('state', 'in', ['done', 'processed'])])
            total_amount = sum(r.amount_ttc for r in successful_records)
            
            # Stats globales (all-time)
            all_time_successful = self.search_count(base_domain + [('state', 'in', ['done', 'processed'])])
            all_time_error = self.search_count(base_domain + [('state', '=', 'error')])
            all_time_dup_records = self.search(base_domain + [('duplicate_count', '>', 0)])
            all_time_duplicates = sum(r.duplicate_count for r in all_time_dup_records)
            all_time_total = all_time_successful + all_time_duplicates + all_time_error
            all_time_records = self.search(base_domain + [('state', 'in', ['done', 'processed'])])
            all_time_amount = sum(r.amount_ttc for r in all_time_records)
            
            # Scans récents (5 derniers)
            recent_scans = self.search(base_domain, limit=5, order='create_date desc')
            recent_scans_data = [{
                'id': r.id,
                'reference': r.reference or '',
                'nom_fournisseur': r.supplier_name or 'N/A',
                'montant_ttc': r.amount_ttc or 0,
                'state': r.state,
                'duplicate_count': r.duplicate_count,
                'scan_date': r.scan_date.isoformat() if r.scan_date else None,
            } for r in recent_scans]
            
            # Graphique évolution
            chart_labels = []
            chart_scans = []
            chart_duplicates = []
            
            if period in ('week', 'month'):
                days = 7 if period == 'week' else 30
                for i in range(days, -1, -1):
                    day = today - timedelta(days=i)
                    day_start = datetime.combine(day, datetime.min.time())
                    day_end = datetime.combine(day, datetime.max.time())
                    day_domain = base_domain + [
                        ('scan_date', '>=', fields.Datetime.to_string(day_start)),
                        ('scan_date', '<=', fields.Datetime.to_string(day_end)),
                    ]
                    day_total = self.search_count(day_domain + [('state', 'in', ['done', 'processed'])])
                    day_dup_records = self.search(day_domain + [('duplicate_count', '>', 0)])
                    day_dup = sum(r.duplicate_count for r in day_dup_records)
                    chart_labels.append(day.strftime('%d/%m'))
                    chart_scans.append(day_total)
                    chart_duplicates.append(day_dup)
            
            # Top fournisseurs scannés par ce vérificateur
            top_suppliers = []
            try:
                self.env.cr.execute("""
                    SELECT supplier_name, COUNT(*) as scan_count, SUM(amount_ttc) as total_amount
                    FROM invoice_scan_record
                    WHERE company_id = %s AND scanned_by = %s
                    AND supplier_name IS NOT NULL AND supplier_name != ''
                    AND scan_date >= %s
                    GROUP BY supplier_name ORDER BY scan_count DESC LIMIT 5
                """, (company_id, user_id, fields.Datetime.to_string(date_from_dt)))
                top_suppliers = [{
                    'name': row[0] or 'Non défini',
                    'count': row[1],
                    'amount': row[2] or 0,
                } for row in self.env.cr.fetchall()]
            except Exception as e:
                _logger.warning(f"Erreur top suppliers vérificateur: {e}")
            
            return {
                'stats': {
                    'total_scans': total_scans,
                    'successful_scans': successful_scans,
                    'duplicate_attempts': duplicate_attempts,
                    'duplicates_by_others': last_dup_by_others,
                    'error_scans': error_scans,
                    'total_amount': total_amount,
                },
                'all_time_stats': {
                    'total_scans': all_time_total,
                    'successful_scans': all_time_successful,
                    'duplicate_attempts': all_time_duplicates,
                    'error_scans': all_time_error,
                    'total_amount': all_time_amount,
                },
                'recent_scans': recent_scans_data,
                'top_suppliers': top_suppliers,
                'chart_data': {
                    'labels': chart_labels,
                    'scans': chart_scans,
                    'duplicates': chart_duplicates,
                },
            }
        except Exception as e:
            _logger.error(f"Erreur get_verificateur_dashboard_data: {e}")
            empty = {'total_scans': 0, 'successful_scans': 0, 'duplicate_attempts': 0,
                     'duplicates_by_others': 0, 'error_scans': 0, 'total_amount': 0}
            return {'stats': empty, 'all_time_stats': empty, 'recent_scans': [],
                    'top_suppliers': [], 'chart_data': {'labels': [], 'scans': [], 'duplicates': []}}

    @api.model
    def get_traiteur_dashboard_data(self, period='month'):
        """Récupérer les données pour le tableau de bord du Traiteur.
        
        Le traiteur voit les factures qu'il a traitées et celles en attente de traitement.
        
        Args:
            period: Période d'analyse ('day', 'week', 'month', 'year')
            
        Returns:
            dict: Données du dashboard traiteur
        """
        from datetime import datetime, timedelta
        
        try:
            company_id = self.env.company.id
            user_id = self.env.user.id
            today = fields.Date.today()
            
            if period not in ('day', 'week', 'month', 'year'):
                period = 'month'
            
            if period == 'day':
                date_from = today
            elif period == 'week':
                date_from = today - timedelta(days=7)
            elif period == 'month':
                date_from = today - timedelta(days=30)
            else:
                date_from = today - timedelta(days=365)
            
            date_from_dt = datetime.combine(date_from, datetime.min.time())
            
            # Factures en attente de traitement (état 'done', non encore traitées)
            pending_domain = [
                ('company_id', '=', company_id),
                ('state', '=', 'done'),
                ('processed_by', '=', False),
            ]
            pending_count = self.search_count(pending_domain)
            pending_records = self.search(pending_domain)
            pending_amount = sum(r.amount_ttc for r in pending_records)
            
            # Factures traitées par ce traiteur (période)
            my_processed_domain = [
                ('company_id', '=', company_id),
                ('processed_by', '=', user_id),
                ('state', '=', 'processed'),
                ('processed_date', '>=', fields.Datetime.to_string(date_from_dt)),
            ]
            processed_period = self.search_count(my_processed_domain)
            processed_records_period = self.search(my_processed_domain)
            processed_amount_period = sum(r.amount_ttc for r in processed_records_period)
            
            # Factures traitées par ce traiteur (all-time)
            my_processed_all = [
                ('company_id', '=', company_id),
                ('processed_by', '=', user_id),
                ('state', '=', 'processed'),
            ]
            processed_all_time = self.search_count(my_processed_all)
            processed_all_records = self.search(my_processed_all)
            processed_all_amount = sum(r.amount_ttc for r in processed_all_records)
            
            # Total traités par tous les traiteurs (période) 
            all_processed_domain = [
                ('company_id', '=', company_id),
                ('state', '=', 'processed'),
                ('processed_date', '>=', fields.Datetime.to_string(date_from_dt)),
            ]
            all_processed_period = self.search_count(all_processed_domain)
            
            # Taux de traitement
            total_eligible = pending_count + processed_period
            processing_rate = round((processed_period / total_eligible * 100) if total_eligible > 0 else 0, 1)
            
            # Scans récemment traités par moi (5 derniers)
            recent_processed = self.search(my_processed_all, limit=5, order='processed_date desc')
            recent_processed_data = [{
                'id': r.id,
                'reference': r.reference or '',
                'nom_fournisseur': r.supplier_name or 'N/A',
                'montant_ttc': r.amount_ttc or 0,
                'state': r.state,
                'processed_date': r.processed_date.isoformat() if r.processed_date else None,
                'scanned_by_name': r.scanned_by.name if r.scanned_by else '',
            } for r in recent_processed]
            
            # Scans en attente (5 derniers)
            pending_scans = self.search(pending_domain, limit=5, order='scan_date desc')
            pending_scans_data = [{
                'id': r.id,
                'reference': r.reference or '',
                'nom_fournisseur': r.supplier_name or 'N/A',
                'montant_ttc': r.amount_ttc or 0,
                'state': r.state,
                'scan_date': r.scan_date.isoformat() if r.scan_date else None,
                'scanned_by_name': r.scanned_by.name if r.scanned_by else '',
            } for r in pending_scans]    
            
            # Graphique évolution traitement
            chart_labels = []
            chart_processed = []
            chart_pending = []
            
            if period in ('week', 'month'):
                days = 7 if period == 'week' else 30
                for i in range(days, -1, -1):
                    day = today - timedelta(days=i)
                    day_start = datetime.combine(day, datetime.min.time())
                    day_end = datetime.combine(day, datetime.max.time())
                    
                    day_processed = self.search_count([
                        ('company_id', '=', company_id),
                        ('processed_by', '=', user_id),
                        ('state', '=', 'processed'),
                        ('processed_date', '>=', fields.Datetime.to_string(day_start)),
                        ('processed_date', '<=', fields.Datetime.to_string(day_end)),
                    ])
                    
                    chart_labels.append(day.strftime('%d/%m'))
                    chart_processed.append(day_processed)
            
            return {
                'stats': {
                    'pending_count': pending_count,
                    'pending_amount': pending_amount,
                    'processed_period': processed_period,
                    'processed_amount_period': processed_amount_period,
                    'all_processed_period': all_processed_period,
                    'processing_rate': processing_rate,
                },
                'all_time_stats': {
                    'processed_all_time': processed_all_time,
                    'processed_all_amount': processed_all_amount,
                },
                'recent_processed': recent_processed_data,
                'pending_scans': pending_scans_data,
                'chart_data': {
                    'labels': chart_labels,
                    'processed': chart_processed,
                },
            }
        except Exception as e:
            _logger.error(f"Erreur get_traiteur_dashboard_data: {e}")
            return {
                'stats': {'pending_count': 0, 'pending_amount': 0, 'processed_period': 0,
                          'processed_amount_period': 0, 'all_processed_period': 0, 'processing_rate': 0},
                'all_time_stats': {'processed_all_time': 0, 'processed_all_amount': 0},
                'recent_processed': [], 'pending_scans': [],
                'chart_data': {'labels': [], 'processed': []},
            }