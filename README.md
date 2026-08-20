# Scanner QR Factures Fournisseur

Module Odoo 17 pour créer des factures fournisseur en scannant les QR-codes des factures certifiées DGI (Direction Générale des Impôts - Côte d'Ivoire).

## Fonctionnalités

### Module Odoo

- ✅ **Scan QR-code DGI** : Récupère automatiquement les données de la facture depuis le site DGI
- ✅ **Factures ET avoirs** : Distingue les deux natures de document certifiées par la DGI
- ✅ **Création automatique** : Crée la facture fournisseur (ou l'avoir) avec les données récupérées
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

### Application web installable (PWA)

Pour les utilisateurs **sans téléphone Android** (iPhone notamment). Même code
Flutter, servi par Odoo sur `/facture`.

- Profils couverts : **Gestionnaire OT** et **Traiteur**.
- **En ligne uniquement** : pas de base locale ni de synchronisation différée
  (`sqflite` et WorkManager n'existent pas dans un navigateur).
- La vérification DGI est faite **par le serveur** (voir plus bas) : un
  navigateur ne peut pas lire la page de vérification de la DGI.
- La caméra exige **HTTPS** (ou `localhost`) : en HTTP simple, le scan est
  impossible — la saisie manuelle reste disponible.

**Construire et déployer**

```bash
cd mobile_app/facture_scanner
./build_web.sh           # sortie : invoice_qr_scanner/static/pwa/
```

Le dossier `static/pwa/` est **généré au déploiement** et n'est pas versionné :
tant qu'il n'existe pas, `/facture` affiche un message d'explication.

**Installer sur iPhone** : ouvrir `https://<serveur>/facture` dans **Safari**,
puis **Partager → « Sur l'écran d'accueil »**. iOS ne propose pas d'invite
automatique d'installation.

## Installation

### 1. Module Odoo

```bash
# Depuis le répertoire Odoo
./odoo.sh install invoice_qr_scanner
```

### 2. Application Flutter

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
- **Interroger la DGI depuis le serveur** (par défaut activé) : le serveur
  récupère lui-même les données de la facture auprès de la plateforme FNE.
  Indispensable à la PWA. Décoché, tous les clients basculent sur la saisie
  manuelle.
- **URL de l'API FNE** : à ne modifier que si la DGI change l'adresse de son
  service (défaut : `https://www.services.fne.dgi.gouv.ci/ws`).

### Vérification auprès de la DGI

La page publique de vérification est une application JavaScript : son HTML ne
contient aucune donnée. Le module interroge donc directement le service REST
qu'utilise cette page (`/ws/invoices/qr/<uuid>`).

⚠️ **Confidentialité.** Cette réponse publique contient aussi des données
sensibles du fournisseur (clé d'API, référence bancaire). Le module applique une
**liste blanche** stricte (`models/fne_api.py`) : le payload brut n'est ni
stocké ni journalisé. Cette faiblesse de la plateforme FNE a été documentée pour
signalement à la DGI (`docs/signalement_dgi_fne.md`). Ne pas alimenter
`raw_html` depuis cette source.

⚠️ **Endpoint non contractuel.** Il n'est pas documenté publiquement et peut
changer sans préavis ; c'est pourquoi la saisie manuelle reste le filet de
sécurité et l'URL de base est un paramètre.

### Identification du fournisseur

Le fournisseur est identifié **par son NCC** (format `1234567K` : 7 chiffres et
une lettre), puis, à défaut, par son **nom exact**.

⚠️ Ne pas réintroduire de recherche par nom partielle (`ilike`). Elle a
réellement imputé des factures au mauvais tiers : un nom tronqué en « TRANS »
désignait « CLIENT LOCAL TRANSCAO ». Créer un fournisseur en double est anodin
et se corrige ; imputer une facture au mauvais tiers ne se voit pas.

Un code DGI non conforme n'est jamais utilisé pour identifier un partenaire, ni
recopié sur sa fiche.

### Factures et avoirs

La plateforme FNE certifie deux natures de document sous un QR-code de forme
identique : les **factures** (`subtype: normal`) et les **avoirs**
(`subtype: refund`, montants négatifs). Rien dans l'URL scannée ne les
distingue.

Le module porte donc une nature explicite sur chaque scan
(`document_type`), et en tire tout le reste :

| | Facture | Avoir |
|---|---|---|
| Pièce Odoo créée | `in_invoice` (facture d'achat) | `in_refund` (avoir fournisseur) |
| Sens | dette envers le fournisseur | créance sur le fournisseur |
| `amount_ttc` | positif | positif (valeur absolue) |
| `amount_signed` | positif | **négatif** |
| Coût d'OT | s'ajoute | **se retranche** |

Deux règles à retenir :

1. **`amount_ttc` est toujours positif.** Le sens est porté par la nature, pas
   par le signe. Le seul montant qu'il soit juste d'additionner est
   `amount_signed` — tous les cumuls (tableaux de bord, statistiques mobiles,
   coûts d'OT) passent par lui.
2. **La nature vient de la DGI, jamais d'une déduction.** Quand la plateforme
   n'a pas pu la confirmer (hors ligne, saisie manuelle),
   `document_type_verified` reste faux et le scan remonte dans le filtre
   « Nature à confirmer ». Le bouton « Vérifier la nature auprès de la DGI »
   du formulaire tranche a posteriori.

**Rattachement d'un avoir à un OT.** Le montant se saisit toujours en valeur
absolue — le champ de l'application n'accepte même pas le signe moins — et
c'est `potting.cost.line` qui applique le signe d'après la nature du scan
rattaché : un avoir vient donc en DÉDUCTION du coût de l'OT. Cette
normalisation vit dans le `create`/`write` du modèle, seul endroit que tous les
chemins traversent (API mobile, assistant, formulaire, import). Une ligne sans
scan rattaché garde en revanche le signe voulu par son auteur.

**Un avoir ne se règle pas.** Une ligne de coût négative ne peut être ni
rattachée à un chèque, ni passée en « Payé »/« Paiement en attente » : le
refus arrive dès l'ouverture de l'assistant, et une contrainte du modèle sert
de filet pour les autres chemins. La raison n'est pas seulement conceptuelle :
la capacité d'un chèque se contrôle par `Σ coûts ≤ montant du chèque`, et un
montant négatif y ferait de la place au lieu d'en consommer — on émettrait un
chèque pour un montant non dû. La compensation réelle se fait en comptabilité,
par lettrage de l'avoir fournisseur avec les factures du même tiers.

Un avoir porte en outre la référence de la facture qu'il corrige
(`origin_invoice_number_dgi`, champ `parentReference` de la DGI) et se
rattache automatiquement au scan de cette facture — quel que soit l'ordre dans
lequel les deux ont été scannés.

### Requalifier les avoirs enregistrés en factures

Le plus simple est le script `scripts/requalifier_avoirs.sh`, qui simule par
défaut, sauvegarde et vérifie la sauvegarde avant toute écriture, et produit un
CSV pour la comptabilité :

```bash
./scripts/requalifier_avoirs.sh --db <base>            # simulation
./scripts/requalifier_avoirs.sh --db <base> --apply    # application
./scripts/requalifier_avoirs.sh --db <base> --check    # contrôles
```

Mode opératoire complet : `docs/requalification_avoirs.md`. En direct depuis un
shell Odoo :

Avant la version 17.0.1.5.0, l'extraction lisait le montant sur le texte de la
page DGI, qui affiche les avoirs en valeur absolue : chaque avoir scanné
devenait une facture d'achat. L'outil de requalification interroge la DGI puis
extourne et recrée les pièces concernées :

```python
# 1. Rapport, sans AUCUNE écriture (comportement par défaut)
env['invoice.scan.record'].repair_refund_documents()

# 2. Balayage exhaustif (interroge la DGI pour tous les scans : lent)
env['invoice.scan.record'].repair_refund_documents(only_suspect=False)

# 3. Application — la correction retombe dans la PÉRIODE D'ORIGINE
env['invoice.scan.record'].repair_refund_documents(dry_run=False)

# 3 bis. …ou imputée sur une période ouverte, sans toucher à la date du
#        document (qui reste celle de la DGI)
env['invoice.scan.record'].repair_refund_documents(
    dry_run=False, posting_date='2026-08-31')
```

Pour chaque avoir confirmé par la DGI, il extourne la facture erronée, recrée
un avoir fournisseur, rétablit l'état du scan et inverse le signe des lignes de
coût d'OT dérivées. Trois pièces comptables subsistent — la fausse facture, son
extourne, l'avoir : une correction comptable se lit dans le grand livre, elle
ne s'y efface pas.

Il **refuse** de toucher une écriture payée, rapprochée ou dans une période
verrouillée : ces cas sont signalés pour arbitrage comptable.

### Réparer les données antérieures

Les scans réalisés avant la version 17.0.1.4.0 peuvent porter un nom tronqué et
un faux code DGI (ancien découpage « NOM - CODE »). L'outil de réparation
compare l'existant à la source DGI :

```python
# Rapport, sans aucune écriture
env['invoice.scan.record'].repair_dgi_data(only_invalid_code=True)

# Application des corrections
env['invoice.scan.record'].repair_dgi_data(only_invalid_code=True, dry_run=False)
```

Il corrige les scans et nettoie les codes DGI non conformes des fiches
partenaires. Il **ne réimpute jamais une facture** : les écarts de tiers sont
seulement listés, classés `libelle` (même tiers, nom abrégé) ou `conflit`
(tiers différent) — la décision appartient à la comptabilité.

### Groupes de sécurité

| Groupe | Droits |
|--------|--------|
| Utilisateur Scanner | Peut scanner et créer des factures, voir son historique |
| Responsable Scanner | Accès complet : configuration, tout l'historique, suppression |

### Protection des scans contre la suppression

Un scan est une **pièce justificative** dès lors qu'il atteste l'origine DGI
d'une facture. Deux garde-fous s'appliquent donc à **tous les profils, y
compris Responsable** — les droits de suppression du groupe ne les lèvent pas.

| Situation | Suppression | Comment procéder malgré tout |
|---|---|---|
| Scan à l'état **Traité** | refusée | retirer l'état avec « ↩ Remettre non traité » — l'opération est tracée dans le chatter |
| Facture liée **comptabilisée** | refusée | annuler d'abord la facture (opération comptable) |
| Brouillon, erreur, facture non validée | autorisée | — |

La suppression est **atomique** : un lot contenant un seul scan protégé est
refusé en entier, afin qu'une suppression de masse ne laisse pas un état
partiel.

La **duplication** d'un scan est également refusée : chaque enregistrement
correspond à un QR-code DGI unique.

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

L'authentification mobile se fait par **code à usage unique (OTP) envoyé par
email**, en deux appels. Il n'y a pas de mot de passe : l'accès à la boîte mail
professionnelle fait foi.

**Étape 1 — demander un code**

```http
POST /api/v1/invoice-scanner/auth/request-otp
Content-Type: application/json

{
  "login": "jdupont"
}
```

La réponse est volontairement identique que le compte existe ou non (protection
contre l'énumération des identifiants) : un succès ne garantit donc pas qu'un
email est parti. Un compte inconnu, désactivé, sans droit sur le module ou sans
adresse email reçoit la même réponse, sans qu'aucun email ne soit envoyé.

Le code comporte 6 chiffres, expire au bout de **10 minutes**, tolère **5
saisies erronées**, et ne peut être redemandé qu'après **60 secondes**
(erreur `OTP_TOO_SOON` sinon). Seul son hash SHA-256 est stocké en base.

Les deux routes sont protégées par un rate-limit adossé à PostgreSQL
(`invoice.scanner.rate.limit`, verrou `SELECT ... FOR UPDATE`), donc **commun à
tous les workers** — un compteur en mémoire aurait été multiplié par leur
nombre. Quotas, sous la forme *(requêtes, fenêtre, blocage)* :

| Clé | Envoi de code | Vérification |
|---|---|---|
| par IP | 30 / 1 h → 10 min | 60 / 5 min → 5 min |
| par compte | 5 / 5 min → 5 min | 10 / 5 min → 5 min |

Les quotas par IP sont larges à dessein : tous les téléphones d'un site
sortent derrière la même IP publique, un quota serré bloquerait l'entrepôt
entier. Dépassement → HTTP 429 `TOO_MANY_ATTEMPTS`.

**Étape 2 — échanger le code contre un token**

```http
POST /api/v1/invoice-scanner/auth/verify-otp
Content-Type: application/json

{
  "login": "jdupont",
  "otp": "482913"
}
```

Le token retourné vaut **7 jours**. La réponse porte `expires_at` au format
ISO 8601 **suffixé `Z`** : `fields.Datetime` étant de l'UTC naïf, un client qui
parserait la date sans marqueur l'interpréterait en heure locale — décalage
invisible en Côte d'Ivoire (UTC+0), bien réel ailleurs. L'application mobile
persiste cette date et invalide la session au démarrage plutôt que d'attendre
un 401 sur le premier appel métier.

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

Le corps est un objet JSON **simple** (pas d'enveloppe `jsonrpc`/`params` : ces
routes sont de type `http`, pas `json`).

```http
POST /api/v1/invoice-scanner/scan
Authorization: Bearer <token>
Content-Type: application/json

{
  "qr_url": "https://www.services.fne.dgi.gouv.ci/fr/verification/019bd62c-467e-7000-82ac-45c8389c7f05"
}
```

Le **serveur** interroge lui-même la plateforme FNE, crée l'enregistrement de
scan et la facture fournisseur. C'est la route utilisée par la PWA, qui ne peut
pas lire une page servie par un autre domaine.

En cas d'indisponibilité de la DGI, la réponse porte un code `FNE_*` et
`"manual_entry_suggested": true` : l'application bascule alors sur la saisie
manuelle.

| Code | Signification | Statut HTTP |
|------|---------------|-------------|
| `FNE_NOT_FOUND` | Aucune facture certifiée pour ce QR-code | 404 |
| `FNE_INCOMPLETE_DATA` | Réponse DGI inexploitable (fournisseur/numéro/montant) | 422 |
| `FNE_DISABLED` | Vérification automatique désactivée dans les réglages | 503 |
| `FNE_TIMEOUT`, `FNE_UNREACHABLE`, `FNE_HTTP_ERROR`, `FNE_INVALID_RESPONSE` | Panne côté DGI | 502 |

`POST /api/v1/invoice-scanner/scan-with-data` reste disponible et inchangée :
elle reçoit des données déjà extraites (saisie manuelle, ou extraction par
WebView des APK Android déjà déployés).

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
| Montant TTC | Montant en FCFA (valeur absolue) | 1 677 566 CFA |
| Nature | Facture ou avoir (`subtype` DGI) | refund |
| Facture d'origine | Référence corrigée par un avoir (`parentReference`) | 7603114Y26000010087 |
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
