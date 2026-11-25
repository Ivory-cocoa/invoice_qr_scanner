# -*- coding: utf-8 -*-
"""Poste de scan à la douchette : un seul écran, plusieurs sortes de QR-codes.

Une douchette USB ou Bluetooth se comporte comme un clavier : aucun programme
n'est à installer sur le poste. L'écran « Poste de scan » (client action
``invoice_scan_desk``) recueille ce qu'elle tape et l'envoie à ``desk_scan``,
qui reconnaît la nature du QR-code et fait le travail :

* facture ou avoir certifié par la DGI → même traitement que l'application
  mobile (``invoice.scan.record._process_qr_scan``) ;
* les autres modules ajoutent leurs propres QR-codes en surchargeant
  ``_desk_kinds`` et ``_desk_handlers`` (cocoa_bean_management : le
  connaissement CCC).

Chaque lecture renvoie une « carte » que l'écran affiche telle quelle
(``_desk_card``) : aucun module n'a de JavaScript à écrire pour brancher un
nouveau QR-code.
"""

import logging

from odoo import _, api, fields, models
from odoo.exceptions import AccessError, UserError, ValidationError
from odoo.tools.misc import format_date, formatLang

from .scanner_input import KEYBOARD_LAYOUT_WARNING, clean_scan, parse_dgi_qr

_logger = logging.getLogger(__name__)

# Longueur du texte lu renvoyé à l'écran quand rien n'est reconnu.
RAW_PREVIEW_LENGTH = 200


class InvoiceScanDesk(models.AbstractModel):
    _name = 'invoice.scan.desk'
    _description = "Poste de scan à la douchette"

    # ------------------------------------------------------------------
    # Points d'extension
    # ------------------------------------------------------------------

    @api.model
    def _desk_kinds(self):
        """QR-codes que le poste sait lire, avec le droit de l'utilisateur.

        Liste de dicts ``key``, ``label``, ``icon`` (Font Awesome),
        ``allowed`` et ``hint`` (ce que fait le scan).
        """
        return [{
            'key': 'dgi',
            'label': _("Facture certifiée DGI"),
            'icon': 'fa-file-text-o',
            'allowed': self._desk_can_scan_dgi(),
            'hint': _("La facture fournisseur (ou l'avoir) est créée "
                      "aussitôt."),
        }]

    @api.model
    def _desk_handlers(self):
        """Fonctions de reconnaissance, essayées dans l'ordre.

        Chacune reçoit le texte lu et renvoie une carte (``_desk_card``) si
        elle reconnaît le QR-code, ``None`` sinon.
        """
        return [self._desk_scan_dgi]

    # ------------------------------------------------------------------
    # Appels de l'écran
    # ------------------------------------------------------------------

    @api.model
    def desk_init(self):
        kinds = self._desk_kinds()
        return {
            'kinds': kinds,
            'can_scan': any(kind['allowed'] for kind in kinds),
            'user_name': self.env.user.name,
        }

    @api.model
    def desk_scan(self, raw):
        """Traite une lecture de la douchette et renvoie la carte à afficher.

        Ne lève jamais d'exception : une fenêtre d'erreur volerait le curseur
        au poste, et les lectures suivantes partiraient dans le vide.
        """
        text = clean_scan(raw if isinstance(raw, str) else '')
        if not text:
            return self._desk_card(
                False, 'unknown', _("Lecture vide ou illisible"),
                message=_("Rien d'exploitable n'a été reçu. Scannez à "
                          "nouveau le QR-code."))
        for handler in self._desk_handlers():
            try:
                # Point de sauvegarde : un traitement qui échoue à mi-chemin
                # ne laisse rien derrière lui.
                with self.env.cr.savepoint():
                    card = handler(text)
            except (UserError, ValidationError, AccessError) as exc:
                return self._desk_card(
                    False, 'error', _("Scan refusé"),
                    message=str(exc.args[0]) if exc.args else str(exc),
                    raw=text)
            except Exception:
                _logger.exception("Poste de scan : échec du traitement")
                return self._desk_card(
                    False, 'error', _("Erreur inattendue"),
                    message=_("Le scan n'a pas pu être traité. Scannez à "
                              "nouveau ; si l'erreur persiste, prévenez "
                              "l'administrateur."),
                    raw=text)
            if card:
                return card
        return self._desk_card(
            False, 'unknown', _("QR-code non reconnu"),
            message=_("Ce contenu n'est ni une facture certifiée par la DGI "
                      "ni un autre QR-code connu d'Odoo. S'il ressemble à "
                      "une suite de signes sans rapport avec le document, "
                      "la douchette est réglée sur un autre clavier que le "
                      "poste."),
            raw=text)

    # ------------------------------------------------------------------
    # Carte de résultat
    # ------------------------------------------------------------------

    @api.model
    def _desk_card(self, kind, status, title, message='', lines=None,
                   warnings=None, actions=None, raw=''):
        """Résultat d'une lecture, affiché tel quel par l'écran.

        ``status`` : ``success`` (fait), ``pending`` (reconnu, une action
        reste à faire), ``duplicate``, ``error`` ou ``unknown``.
        ``lines`` : liste de ``(libellé, valeur)`` ; les valeurs vides sont
        retirées. ``actions`` : liste de ``{'label', 'action', 'primary'}``
        où ``action`` est une action Odoo ouverte au clic.
        """
        labels = {kind['key']: kind['label'] for kind in self._desk_kinds()}
        return {
            'kind': kind or False,
            'kind_label': labels.get(kind, ''),
            'status': status,
            'title': title,
            'message': message or '',
            'lines': [{'label': label, 'value': str(value)}
                      for label, value in (lines or []) if value],
            'warnings': list(warnings or []),
            'actions': list(actions or []),
            'raw': (raw or '')[:RAW_PREVIEW_LENGTH],
        }

    # ------------------------------------------------------------------
    # Facture certifiée DGI
    # ------------------------------------------------------------------

    @api.model
    def _desk_can_scan_dgi(self):
        """Mêmes profils que ceux qui peuvent créer un scan (Vérificateur,
        Responsable)."""
        return self.env['invoice.scan.record'].check_access_rights(
            'create', raise_exception=False)

    @api.model
    def _desk_scan_dgi(self, text):
        parsed = parse_dgi_qr(text)
        if not parsed:
            return None
        if not self._desk_can_scan_dgi():
            return self._desk_card(
                'dgi', 'error', _("Scan de facture non autorisé"),
                message=_("Le scan des factures DGI est réservé aux profils "
                          "Vérificateur et Responsable Scanner."))
        warnings = [KEYBOARD_LAYOUT_WARNING] if parsed['layout_fixed'] else []
        qr_uuid = parsed['qr_uuid']
        ScanRecord = self.env['invoice.scan.record'].sudo()
        FneApi = self.env['fne.api.client'].sudo()
        outcome = ScanRecord._process_qr_scan(
            self.env.user, parsed['qr_url'], qr_uuid,
            lambda: FneApi.fetch_invoice(qr_uuid), origin='douchette')

        if outcome['ok']:
            record = outcome['record']
            is_refund = record.document_type == 'refund'
            return self._desk_card(
                'dgi', 'success',
                _("Avoir enregistré") if is_refund else _("Facture créée"),
                lines=self._desk_dgi_lines(record), warnings=warnings,
                actions=self._desk_dgi_actions(record))

        code = outcome['error_code']
        if code == 'DUPLICATE':
            existing = outcome['existing']
            scanned_on = format_date(self.env, fields.Datetime.context_timestamp(
                self, existing.scan_date).date()) if existing.scan_date else ''
            return self._desk_card(
                'dgi', 'duplicate', _("Déjà scannée"),
                message=_(
                    "Cette facture a déjà été scannée par %(user)s le "
                    "%(date)s. Rien n'a été créé.",
                    user=existing.scanned_by.name or _("un autre utilisateur"),
                    date=scanned_on or '?'),
                lines=self._desk_dgi_lines(existing), warnings=warnings,
                actions=self._desk_dgi_actions(existing))
        if code == 'INVOICE_ERROR':
            record = outcome['record']
            exc = outcome['exception']
            detail = str(exc.args[0]) if isinstance(
                exc, (UserError, ValidationError)) and exc.args else _(
                "erreur interne, prévenez l'administrateur")
            return self._desk_card(
                'dgi', 'error', _("Facture non créée"),
                message=_(
                    "Le scan %(ref)s est enregistré en erreur : %(detail)s. "
                    "Corrigez la cause puis relancez-le depuis sa fiche.",
                    ref=record.reference, detail=detail),
                lines=self._desk_dgi_lines(record), warnings=warnings,
                actions=self._desk_dgi_actions(record))
        if code == 'SERVER_BUSY':
            return self._desk_card(
                'dgi', 'error', _("Serveur occupé"),
                message=_("Le serveur traite déjà plusieurs scans. Scannez "
                          "à nouveau dans quelques secondes."),
                warnings=warnings)
        # Échec d'interrogation de la DGI (FNE_*) : rien n'a été enregistré.
        return self._desk_card(
            'dgi', 'error', _("La DGI n'a pas répondu"),
            message=_(
                "%(reason)s Rien n'a été enregistré : scannez à nouveau "
                "dans un instant. Si le problème dure, la facture peut être "
                "saisie depuis l'application mobile (saisie manuelle).",
                reason=outcome['message']),
            warnings=warnings)

    @api.model
    def _desk_dgi_lines(self, record):
        nature = dict(record._fields['document_type']._description_selection(
            self.env)).get(record.document_type, '')
        return [
            (_("Scan"), record.reference),
            (_("Nature"), nature),
            (_("Fournisseur"), record.supplier_name),
            (_("N° DGI"), record.invoice_number_dgi),
            (_("Date"), format_date(self.env, record.invoice_date)
             if record.invoice_date else ''),
            (_("Montant TTC"), formatLang(
                self.env, record.amount_ttc,
                currency_obj=record.currency_id)),
            (_("Pièce comptable"), record.invoice_id.name
             if record.invoice_id and record.invoice_id.name != '/' else ''),
        ]

    @api.model
    def _desk_dgi_actions(self, record):
        """Bouton d'ouverture, seulement si l'utilisateur peut lire la fiche
        (un Vérificateur ne voit que ses propres scans)."""
        visible = self.env['invoice.scan.record'].search(
            [('id', '=', record.id)], limit=1)
        if not visible:
            return []
        return [{
            'label': _("Ouvrir le scan"),
            'primary': False,
            'action': {
                'type': 'ir.actions.act_window',
                'name': record.reference,
                'res_model': 'invoice.scan.record',
                'res_id': record.id,
                'views': [[False, 'form']],
                'target': 'current',
            },
        }]
