# Scanner QR Factures Fournisseur

Module Odoo 17 pour créer des factures fournisseur en scannant les QR-codes des factures certifiées DGI (Direction Générale des Impôts - Côte d'Ivoire).

## Fonctionnalités

### Module Odoo

- ✅ **Scan QR-code DGI** : Récupère automatiquement les données de la facture depuis le site DGI
- ✅ **Création automatique** : Crée la facture fournisseur avec les données récupérées
- ✅ **Détection doublons** : Empêche la création de factures en double grâce à l'UUID unique
- ✅ **Création fournisseur** : Crée automatiquement le fournisseur s'il n'existe pas
- ✅ **Configuration flexible** : Choix entre validation automatique ou manuelle des factures
- ✅ **API REST** : Endpoints pour l'application mobile Flutter
- ✅ **Traçabilité** : Historique complet des scans avec détails

### Application Mobile Flutter

- ✅ **Scanner QR** : Scan via la caméra du téléphone
- ✅ **Mode Offline/Online** : Fonctionne hors ligne et synchronise automatiquement
- ✅ **Historique** : Liste des factures scannées
- ✅ **Statistiques** : Tableau de bord avec métriques

## Installation

### 1. Module Odoo

```bash
# Depuis le répertoire Odoo
./odoo.sh install invoice_qr_scanner
```

### 2. Dépendances Python

Le module nécessite `beautifulsoup4` pour parser les données DGI :

```bash
pip install beautifulsoup4
```

### 3. Application Flutter

```bash
cd icp/invoice_qr_scanner/mobile_app/facture_scanner
flutter pub get
flutter run
```

## Configuration

### Paramètres du module

Allez dans **Scanner Factures > Configuration > Paramètres** pour :

- **Valider automatiquement les factures** : Si activé (par défaut), les factures sont validées automatiquement. Sinon, elles restent en brouillon.
- **Créer automatiquement le fournisseur** : Crée le partenaire s'il n'existe pas dans Odoo.
- **Compte de dépense par défaut** : Compte comptable pour les lignes de factures.

### Groupes de sécurité

| Groupe | Droits |
|--------|--------|
| Utilisateur Scanner | Peut scanner et créer des factures, voir son historique |
| Responsable Scanner | Accès complet : configuration, tout l'historique, suppression |

## Utilisation

### Via l'application mobile

1. Se connecter avec ses identifiants Odoo
2. Appuyer sur "Scanner"
3. Pointer la caméra vers le QR-code de la facture DGI
4. La facture est créée automatiquement

### Via Odoo (pour test)

Les scans sont visibles dans **Scanner Factures > Scans > Tous les scans**.

## API REST

### Authentification

```http
POST /api/v1/invoice-scanner/auth/login
Content-Type: application/json

{
  "jsonrpc": "2.0",
  "params": {
    "login": "admin",
    "password": "admin"
  }
}
```

Réponse :
```json
{
  "result": {
    "success": true,
    "data": {
      "token": "eyJ...",
      "user": {
        "id": 2,
        "name": "Administrator",
        "email": "admin@example.com"
      }
    }
  }
}
```

### Scanner un QR-code

```http
POST /api/v1/invoice-scanner/scan
Authorization: Bearer <token>
Content-Type: application/json

{
  "jsonrpc": "2.0",
  "params": {
    "qr_url": "https://www.services.fne.dgi.gouv.ci/fr/verification/019bd62c-467e-7000-82ac-45c8389c7f05"
  }
}
```

### Historique

```http
POST /api/v1/invoice-scanner/history
Authorization: Bearer <token>
Content-Type: application/json

{
  "jsonrpc": "2.0",
  "params": {
    "page": 1,
    "limit": 20
  }
}
```

## Structure des données

### Données extraites du QR-code DGI

| Champ | Description | Exemple |
|-------|-------------|---------|
| Fournisseur | Nom et code DGI | LOGIFRET INTERNATIONAL - 2502298K |
| Client | Nom et code DGI | IVORY COCOA PRODUCTS - 1100563G |
| N° Facture | Numéro attribué par DGI | 2502298K26000000003 |
| Date | Date de facturation | 19/01/2026 |
| Montant TTC | Montant en FCFA | 1 677 566 CFA |
| UUID | Identifiant unique | 019bd62c-467e-7000-82ac-45c8389c7f05 |

## Structure du module

```
invoice_qr_scanner/
├── __manifest__.py
├── __init__.py
├── models/
│   ├── __init__.py
│   ├── invoice_scan_record.py    # Modèle principal de scan
│   ├── invoice_scanner_api_token.py  # Tokens API
│   ├── account_move.py           # Extension factures
│   └── res_config_settings.py    # Configuration
├── controllers/
│   ├── __init__.py
│   └── mobile_api.py             # API REST
├── security/
│   ├── invoice_qr_scanner_security.xml
│   └── ir.model.access.csv
├── data/
│   └── ir_sequence_data.xml
├── views/
│   ├── invoice_scan_record_views.xml
│   ├── account_move_views.xml
│   ├── res_config_settings_views.xml
│   └── menu_views.xml
└── mobile_app/
    └── facture_scanner/          # Application Flutter
```

## Support

Ce module a été développé pour ICP (Ivory Cocoa Products) pour la gestion des factures fournisseur en Côte d'Ivoire.
