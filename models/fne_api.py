# -*- coding: utf-8 -*-
"""Client de l'API publique de vérification de la plateforme FNE (DGI).

Pourquoi ce module existe
=========================
La page publique ``/fr/verification/<uuid>`` du site FNE est une application
Next.js : son HTML ne contient que les libellés, jamais les valeurs. C'est ce
qui avait imposé, côté application mobile, une extraction par WebView invisible
(chargement de la page, attente du rendu JS, lecture du texte) — mécanisme
impossible à porter sur le web, et donc bloquant pour une PWA.

Or cette page appelle simplement une API REST :

    GET https://www.services.fne.dgi.gouv.ci/ws/invoices/qr/<uuid>  →  JSON

sans authentification. Ce module l'interroge directement : plus de WebView, plus
de navigateur sans interface côté serveur, et le mode hors ligne redevient
synchronisable puisque le serveur peut retrouver lui-même les données à partir
de la seule URL du QR-code.

⚠️ Confidentialité — à ne pas contourner
========================================
La réponse de cette API expose bien plus que la facture : elle contient la fiche
complète de l'entreprise émettrice, **dont sa clé d'API** (``company.apiKey``) et
sa référence bancaire. C'est une faiblesse de la plateforme FNE, signalée à la
DGI (cf. ``docs/signalement_dgi_fne.md``).

Conséquence pour ce code : le payload brut n'est **jamais** stocké ni
journalisé. ``_normalize_payload`` applique une liste blanche explicite et ne
retourne que les champs nécessaires à la facture. Le champ ``raw_html`` du
modèle de scan ne doit pas non plus être alimenté depuis cette source.

⚠️ Endpoint non contractuel
===========================
Cet endpoint est celui du site public, il n'est pas documenté. Il peut changer
sans préavis : toutes les erreurs sont donc typées et remontées proprement à
l'application, qui bascule sur la saisie manuelle (parcours déjà en place).
L'URL de base est un paramètre système, modifiable sans redéploiement.
"""

import logging
from datetime import datetime

import requests

from odoo import api, models

_logger = logging.getLogger(__name__)

# Paramètres système (Réglages → Scanner Factures)
PARAM_ENABLED = 'invoice_qr_scanner.fne_api_enabled'
PARAM_BASE_URL = 'invoice_qr_scanner.fne_api_base_url'

DEFAULT_BASE_URL = 'https://www.services.fne.dgi.gouv.ci/ws'

# Le scan est une opération interactive : l'utilisateur attend devant son
# téléphone. Au-delà, mieux vaut basculer sur la saisie manuelle que faire
# patienter — et que bloquer un slot du sémaphore de scan.
TIMEOUT_CONNECT = 5
TIMEOUT_READ = 12


class FneApiError(Exception):
    """Échec d'interrogation de l'API FNE, avec un code exploitable par l'API mobile.

    Codes : FNE_DISABLED, FNE_TIMEOUT, FNE_UNREACHABLE, FNE_NOT_FOUND,
    FNE_HTTP_ERROR, FNE_INVALID_RESPONSE, FNE_INCOMPLETE_DATA.
    """

    def __init__(self, code, message):
        super().__init__(message)
        self.code = code
        self.message = message


class FneApiClient(models.AbstractModel):
    _name = 'fne.api.client'
    _description = "Client API de vérification FNE (DGI)"

    # ------------------------------------------------------------------
    # Configuration
    # ------------------------------------------------------------------

    @api.model
    def _is_enabled(self):
        """L'extraction côté serveur est-elle active ?

        Défaut : activée. Le paramètre permet de la couper immédiatement si la
        DGI change ou ferme l'endpoint, sans redéploiement : l'application
        rebascule alors sur la saisie manuelle.
        """
        param = self.env['ir.config_parameter'].sudo().get_param(PARAM_ENABLED, 'True')
        return str(param).strip().lower() not in ('false', '0', '')

    @api.model
    def _get_base_url(self):
        base = self.env['ir.config_parameter'].sudo().get_param(PARAM_BASE_URL) or DEFAULT_BASE_URL
        return base.rstrip('/')

    # ------------------------------------------------------------------
    # Appel réseau
    # ------------------------------------------------------------------

    @api.model
    def fetch_invoice(self, qr_uuid):
        """Récupérer et normaliser les données d'une facture certifiée FNE.

        Args:
            qr_uuid: UUID de vérification (déjà normalisé en minuscules).

        Returns:
            dict: valeurs prêtes pour ``invoice.scan.record`` (liste blanche).

        Raises:
            FneApiError: avec un ``code`` exploitable par l'API mobile.
        """
        if not qr_uuid:
            raise FneApiError('FNE_INVALID_RESPONSE', "UUID de vérification manquant")

        if not self._is_enabled():
            raise FneApiError(
                'FNE_DISABLED',
                "La vérification automatique auprès de la DGI est désactivée.",
            )

        url = '%s/invoices/qr/%s' % (self._get_base_url(), qr_uuid)

        try:
            response = requests.get(
                url,
                timeout=(TIMEOUT_CONNECT, TIMEOUT_READ),
                headers={'Accept': 'application/json'},
            )
        except requests.Timeout as exc:
            _logger.warning("FNE: délai dépassé pour %s (%s)", qr_uuid, exc)
            raise FneApiError(
                'FNE_TIMEOUT',
                "La plateforme DGI n'a pas répondu dans le délai imparti.",
            ) from exc
        except requests.RequestException as exc:
            # Ne journaliser que le type d'erreur : l'exception `requests` peut
            # contenir l'URL complète, et donc l'UUID de la facture.
            _logger.warning("FNE: échec réseau pour %s (%s)", qr_uuid, type(exc).__name__)
            raise FneApiError(
                'FNE_UNREACHABLE',
                "Impossible de joindre la plateforme DGI.",
            ) from exc

        if response.status_code == 404:
            raise FneApiError(
                'FNE_NOT_FOUND',
                "Aucune facture certifiée ne correspond à ce QR-code.",
            )

        if response.status_code != 200:
            _logger.warning("FNE: statut HTTP %s pour %s", response.status_code, qr_uuid)
            raise FneApiError(
                'FNE_HTTP_ERROR',
                "La plateforme DGI a renvoyé une erreur (HTTP %s)." % response.status_code,
            )

        try:
            payload = response.json()
        except ValueError as exc:
            raise FneApiError(
                'FNE_INVALID_RESPONSE',
                "Réponse illisible de la plateforme DGI.",
            ) from exc

        if not isinstance(payload, dict):
            raise FneApiError(
                'FNE_INVALID_RESPONSE',
                "Réponse inattendue de la plateforme DGI.",
            )

        return self._normalize_payload(payload)

    # ------------------------------------------------------------------
    # Normalisation (fonction pure — testée sans réseau)
    # ------------------------------------------------------------------

    @api.model
    def _normalize_payload(self, payload):
        """Extraire de la réponse FNE les seuls champs utiles à la facture.

        LISTE BLANCHE VOLONTAIRE : le payload contient des données sensibles du
        fournisseur (clé d'API, référence bancaire, email, soldes). Rien d'autre
        que les champs ci-dessous ne doit ressortir de cette méthode, ni être
        journalisé, ni être stocké.

        Correspondances (côté FNE → côté Odoo) :
            company.name         → supplier_name
            company.ncc          → supplier_code_dgi
            clientCompanyName    → customer_name
            clientNcc            → customer_code_dgi
            reference            → invoice_number_dgi
            date                 → invoice_date
            totalDue / totalAfterTaxes / amount → amount_ttc
            token                → verification_id
            commercialMessage    → commercial_message (peut porter la réf. d'OT)
        """
        company = payload.get('company')
        if not isinstance(company, dict):
            company = {}

        values = {
            'supplier_name': self._clean_text(company.get('name')),
            'supplier_code_dgi': self._clean_text(company.get('ncc')),
            'customer_name': self._clean_text(payload.get('clientCompanyName')),
            'customer_code_dgi': self._clean_text(payload.get('clientNcc')),
            'invoice_number_dgi': self._clean_text(payload.get('reference')),
            'invoice_date': self._parse_date(payload.get('date')),
            'amount_ttc': self._parse_amount(payload),
            'verification_id': self._clean_text(payload.get('token')),
            'commercial_message': self._clean_text(payload.get('commercialMessage'), limit=512),
        }

        # Mêmes exigences que la saisie manuelle : sans fournisseur, numéro et
        # montant, la facture fournisseur ne peut pas être créée.
        missing = [
            label
            for key, label in (
                ('supplier_name', 'fournisseur'),
                ('invoice_number_dgi', 'numéro de facture'),
            )
            if not values.get(key)
        ]
        if values['amount_ttc'] is None:
            missing.append('montant TTC')

        if missing:
            raise FneApiError(
                'FNE_INCOMPLETE_DATA',
                "Données incomplètes renvoyées par la DGI (%s)." % ', '.join(missing),
            )

        return values

    @api.model
    def _clean_text(self, value, limit=256):
        """Normaliser une valeur texte du payload (et borner sa longueur)."""
        if value is None or isinstance(value, (dict, list, bool)):
            return False
        text = ' '.join(str(value).split())
        return text[:limit] if text else False

    @api.model
    def _parse_date(self, value):
        """Convertir la date FNE (ISO 8601 UTC, ex. 2026-01-19T12:09:56.508Z).

        Seule la partie date est conservée : ``invoice_date`` est un champ Date,
        et la date de facturation affichée par la DGI est la date calendaire.
        """
        if not value or not isinstance(value, str):
            return False
        text = value.strip().replace('Z', '+00:00')
        try:
            return datetime.fromisoformat(text).date()
        except ValueError:
            pass
        try:
            return datetime.strptime(text[:10], '%Y-%m-%d').date()
        except (ValueError, TypeError):
            _logger.info("FNE: date non exploitable (%r)", value[:32])
            return False

    @api.model
    def _parse_amount(self, payload):
        """Montant TTC, par ordre de préférence des champs FNE.

        ``totalDue`` est le net à payer affiché comme « Montant TTC » sur la page
        de vérification ; ``totalAfterTaxes`` et ``amount`` servent de repli si
        la plateforme cesse de le renseigner.
        """
        for key in ('totalDue', 'totalAfterTaxes', 'amount'):
            value = payload.get(key)
            if value is None or isinstance(value, bool):
                continue
            try:
                amount = float(value)
            except (TypeError, ValueError):
                continue
            if amount >= 0:
                return amount
        return None
