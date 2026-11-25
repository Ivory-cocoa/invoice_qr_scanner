# -*- coding: utf-8 -*-
"""Cœur du scan d'une facture DGI : dédoublonnage, enregistrement, facture.

Ce code vivait dans le contrôleur de l'API mobile (`_process_scan`). Il est
ici, dans le modèle, pour que TOUTES les portes d'entrée le partagent :
application mobile, PWA, synchronisation hors ligne et poste de scan à la
douchette. Une divergence entre deux entrées signifierait des factures
fournisseur en double, ce que ce module existe pour empêcher.
"""

import logging

from odoo import api, fields, models

from .fne_api import FneApiError

_logger = logging.getLogger(__name__)


class InvoiceScanRecordProcess(models.Model):
    _inherit = 'invoice.scan.record'

    @api.model
    def _process_qr_scan(self, user, qr_url, qr_uuid, values, origin='scan'):
        """Créer l'enregistrement de scan puis la facture fournisseur.

        À appeler sur un jeu d'enregistrements en ``sudo()`` : l'appelant a
        déjà vérifié que ``user`` a le droit de scanner.

        Args:
            user: utilisateur qui scanne (``res.users``).
            values: dict des valeurs DGI, OU fonction sans argument le
                renvoyant. La forme fonction est résolue APRÈS le contrôle de
                doublon, pour ne pas interroger la DGI quand la facture est
                déjà connue.
            origin: porte d'entrée, pour les journaux et le fil de discussion.

        Returns:
            dict: ``{'ok': True, 'record': …, 'invoice': …}`` ou
            ``{'ok': False, 'error_code': …, 'message': …}`` complété, selon
            le cas, de ``existing`` (doublon), ``manual_entry_suggested``
            (DGI injoignable), ``record`` et ``exception`` (facture non
            créée) ou ``details`` (serveur occupé). Des enregistrements, pas
            une réponse HTTP : chaque porte d'entrée met en forme à sa façon.
        """
        # Import tardif : `controllers` importe déjà `models`.
        from ..controllers.scan_semaphore import (
            acquire_scan_slot, get_semaphore_status, release_scan_slot)

        # Vérifier les doublons
        existing = self.check_duplicate(qr_uuid)
        if existing:
            existing.write({
                'duplicate_count': existing.duplicate_count + 1,
                'last_duplicate_attempt': fields.Datetime.now(),
                'last_duplicate_user_id': user.id,
            })
            existing.message_post(
                body=f"Tentative de scan doublon #{existing.duplicate_count} par {user.name} ({origin})",
                message_type='notification'
            )
            return {
                'ok': False,
                'error_code': 'DUPLICATE',
                'message': 'Cette facture a déjà été scannée',
                'existing': existing,
            }

        # Extraction DGI côté serveur, seulement maintenant : inutile d'appeler
        # la DGI pour une facture déjà enregistrée.
        if callable(values):
            try:
                values = values()
            except FneApiError as exc:
                return {
                    'ok': False,
                    'error_code': exc.code,
                    'message': exc.message,
                    # Le client bascule alors sur la saisie manuelle, qui
                    # reste le filet de sécurité si la DGI change ou tombe.
                    'manual_entry_suggested': True,
                }

        # Vérifier s'il existe un enregistrement en erreur
        existing_error = self.search([
            ('qr_uuid', '=', qr_uuid),
            ('state', '=', 'error'),
            ('company_id', '=', self.env.company.id)
        ], limit=1)

        record_vals = dict(values)
        record_vals.update({
            'qr_url': qr_url,
            'scanned_by': user.id,
            'state': 'draft',
            'error_message': False,
        })

        if existing_error:
            existing_error.write(record_vals)
            record = existing_error
        else:
            record_vals['qr_uuid'] = qr_uuid
            record = self.create(record_vals)

        # Acquérir un slot du sémaphore pour la création de facture
        if not acquire_scan_slot():
            _logger.warning("%s rejeté (serveur occupé) pour user=%s", origin, user.id)
            return {
                'ok': False,
                'error_code': 'SERVER_BUSY',
                'message': 'Le serveur traite actuellement plusieurs requêtes. Veuillez réessayer dans quelques secondes.',
                'details': get_semaphore_status(),
            }

        # Créer la facture
        try:
            invoice = record._create_invoice()
            return {'ok': True, 'record': record, 'invoice': invoice}
        except Exception as e:
            _logger.error("Erreur création facture (%s): %s", origin, e)
            record.write({
                'state': 'error',
                'error_message': str(e),
            })
            return {
                'ok': False,
                'error_code': 'INVOICE_ERROR',
                'message': 'Erreur lors de la création de la facture',
                'record': record,
                'exception': e,
            }
        finally:
            release_scan_slot()

    @api.model
    def _process_qr_treatment(self, user, qr_uuid, origin_label):
        """Marquer « traitée » la facture d'un QR-code (profil Traiteur).

        Cœur commun à l'application mobile (`scan-to-process`) et au poste de
        scan à la douchette. À appeler en ``sudo()``, droit déjà vérifié.

        Returns:
            dict: ``{'ok': True, 'record': …}`` ou ``{'ok': False,
            'error_code': 'NOT_FOUND' | 'ALREADY_PROCESSED', 'record': …}``.
        """
        existing = self.search([
            ('qr_uuid', '=', self._normalize_qr_uuid(qr_uuid)),
            ('state', 'in', ['done', 'processed']),
            ('company_id', '=', self.env.company.id)
        ], limit=1)

        if not existing:
            return {'ok': False, 'error_code': 'NOT_FOUND', 'record': existing}

        if existing.state == 'processed':
            # Incrémenter le compteur de tentatives de retraitement
            existing.write({
                'reprocess_attempt_count': existing.reprocess_attempt_count + 1,
                'last_reprocess_attempt': fields.Datetime.now(),
                'last_reprocess_user_id': user.id,
            })
            existing.message_post(
                body=f"Tentative de retraitement #{existing.reprocess_attempt_count} par {user.name} "
                     f"(facture déjà traitée par {existing.processed_by.name or 'N/A'})",
                message_type='notification'
            )
            return {'ok': False, 'error_code': 'ALREADY_PROCESSED',
                    'record': existing}

        # Marquer comme traité
        existing.write({
            'state': 'processed',
            'processed_by': user.id,
            'processed_date': fields.Datetime.now(),
        })
        existing.message_post(
            body=f"Facture traitée par {user.name} (profil Traiteur, {origin_label})",
            message_type='notification'
        )
        return {'ok': True, 'record': existing}
