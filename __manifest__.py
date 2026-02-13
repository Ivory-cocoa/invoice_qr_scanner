# -*- coding: utf-8 -*-
{
    'name': 'Scanner QR Factures Fournisseur',
    'version': '17.0.1.2.0',
    'category': 'Accounting/Invoicing',
    'summary': 'Création de factures fournisseur par scan QR-code DGI',
    'description': """
        Module de scan de QR-code pour créer des factures fournisseur
        ============================================================
        
        Ce module permet de :
        - Scanner les QR-codes figurant sur les factures certifiées DGI
        - Créer automatiquement des factures fournisseur uniques
        - Éviter les doublons grâce à l'UUID de vérification
        - Créer automatiquement le fournisseur s'il n'existe pas
        - Tableau de bord OWL pour le Responsable Scanner
        
        API REST pour application mobile Flutter :
        - POST /api/v1/invoice-scanner/auth/login - Authentification
        - POST /api/v1/invoice-scanner/auth/logout - Déconnexion
        - POST /api/v1/invoice-scanner/scan - Scanner et créer facture
        - GET /api/v1/invoice-scanner/history - Historique des scans
        - GET /api/v1/invoice-scanner/stats - Statistiques
        - GET /api/v1/invoice-scanner/invoice/<id> - Détails facture
        
        Source des données : services.fne.dgi.gouv.ci (DGI Côte d'Ivoire)
    """,
    'author': 'ICP',
    'website': 'https://www.icp.com',
    'license': 'LGPL-3',
    'depends': [
        'base',
        'mail',
        'account',
        'web',
    ],
    'data': [
        # Security
        'security/invoice_qr_scanner_security.xml',
        'security/ir.model.access.csv',
        # Data
        'data/ir_sequence_data.xml',
        'data/res_users_data.xml',
        # Views
        'views/invoice_scan_record_views.xml',
        'views/account_move_views.xml',
        'views/res_config_settings_views.xml',
        'views/menu_views.xml',
        # Reports
        'reports/user_guide_report.xml',
    ],
    'assets': {
        'web.assets_backend': [
            'invoice_qr_scanner/static/src/js/clipboard_fix.js',
            'invoice_qr_scanner/static/src/js/invoice_scanner_dashboard_improved.js',
            'invoice_qr_scanner/static/src/xml/invoice_scanner_dashboard_improved.xml',
            'invoice_qr_scanner/static/src/css/invoice_scanner_dashboard_improved.css',
            'invoice_qr_scanner/static/src/js/verificateur_dashboard.js',
            'invoice_qr_scanner/static/src/xml/verificateur_dashboard.xml',
            'invoice_qr_scanner/static/src/js/traiteur_dashboard.js',
            'invoice_qr_scanner/static/src/xml/traiteur_dashboard.xml',
        ],
    },
    'installable': True,
    'application': True,
    'auto_install': False,
}
