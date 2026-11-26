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
nouveau QR-code. Une carte peut porter un petit formulaire (``_desk_form``)
pour ce que le QR-code ne contient pas ; sa validation revient par
``desk_submit``.
"""

import logging

from odoo import _, api, fields, models
from odoo.exceptions import AccessError, UserError, ValidationError
from odoo.tools.misc import format_date, formatLang

from .scanner_input import (
    KEYBOARD_LAYOUT_WARNING, SCANNER_TEST_TEXT, check_scanner_test,
    clean_scan, parse_dgi_qr)

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
        ``allowed``, ``hint`` (ce que fait le scan) et ``modes`` : liste de
        ``{'key', 'label', 'hint'}`` quand un même QR-code sert à plusieurs
        gestes selon le profil (l'écran propose le choix s'il y en a
        plusieurs ; le premier est le mode par défaut).
        """
        modes = self._desk_dgi_modes()
        return [{
            'key': 'dgi',
            'label': _("Facture certifiée DGI"),
            'icon': 'fa-file-text-o',
            'allowed': bool(modes),
            'hint': modes[0]['hint'] if modes else '',
            'modes': modes,
        }]

    @api.model
    def _desk_handlers(self):
        """Fonctions de reconnaissance, essayées dans l'ordre.

        Chacune reçoit le texte lu et les options de l'écran (``modes`` :
        mode choisi par sorte de QR-code) ; elle renvoie une carte
        (``_desk_card``) si elle reconnaît le QR-code, ``None`` sinon.
        """
        return [self._desk_scan_test, self._desk_scan_dgi]

    @api.model
    def _desk_submitters(self):
        """Validation des formulaires de carte : ``{sorte: fonction}``.

        La fonction reçoit ``(payload, values)`` — le ``payload`` posé par
        ``_desk_form`` et les valeurs saisies — et renvoie une carte. Une
        ``UserError`` laisse le formulaire affiché, avec son message.
        """
        return {'dgi': self._desk_submit_dgi}

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
            # QR-code de contrôle affiché par « Tester la douchette »
            'test_text': SCANNER_TEST_TEXT,
        }

    @api.model
    def _desk_contained(self, function, raw=''):
        """Exécute ``function`` sans jamais laisser sortir d'exception.

        Renvoie ``(carte, message d'erreur métier)``. Une fenêtre d'erreur
        volerait le curseur au poste, et les lectures suivantes partiraient
        dans le vide. Point de sauvegarde : un traitement qui échoue à
        mi-chemin ne laisse rien derrière lui.
        """
        try:
            with self.env.cr.savepoint():
                return function(), None
        except (UserError, ValidationError, AccessError) as exc:
            return None, str(exc.args[0]) if exc.args else str(exc)
        except Exception:
            _logger.exception("Poste de scan : échec du traitement")
            return self._desk_card(
                False, 'error', _("Erreur inattendue"),
                message=_("Le scan n'a pas pu être traité. Scannez à "
                          "nouveau ; si l'erreur persiste, prévenez "
                          "l'administrateur."),
                raw=raw), None

    @api.model
    def desk_scan(self, raw, options=None):
        """Traite une lecture de la douchette et renvoie la carte à afficher.

        ``options`` : ``{'modes': {sorte: mode choisi à l'écran}}``.
        """
        text = clean_scan(raw if isinstance(raw, str) else '')
        options = options if isinstance(options, dict) else {}
        if not text:
            return self._desk_card(
                False, 'unknown', _("Lecture vide ou illisible"),
                message=_("Rien d'exploitable n'a été reçu. Scannez à "
                          "nouveau le QR-code."))
        for handler in self._desk_handlers():
            card, error = self._desk_contained(
                lambda: handler(text, options), raw=text)
            if error:
                return self._desk_card(
                    False, 'error', _("Scan refusé"), message=error, raw=text)
            if card:
                return card
        return self._desk_card(
            False, 'unknown', _("QR-code non reconnu"),
            message=_("Ce contenu n'est ni une facture certifiée par la DGI "
                      "ni un autre QR-code connu d'Odoo. S'il ressemble à "
                      "une suite de signes sans rapport avec le document, "
                      "la douchette est réglée sur un autre clavier que le "
                      "poste : utilisez « Tester la douchette »."),
            raw=text)

    @api.model
    def desk_submit(self, kind, payload, values):
        """Valide le formulaire d'une carte.

        Renvoie ``{'card': …}`` (la carte qui remplace le formulaire) ou
        ``{'error': message}`` (le formulaire reste affiché, à corriger).
        """
        submitter = self._desk_submitters().get(kind)
        if not submitter or not isinstance(payload, dict) \
                or not isinstance(values, dict):
            return {'error': _("Formulaire inconnu : scannez à nouveau.")}
        card, error = self._desk_contained(lambda: submitter(payload, values))
        return {'error': error} if error else {'card': card}

    @api.model
    def _desk_mode(self, kind, options):
        """Mode retenu pour une sorte de QR-code : celui choisi à l'écran
        s'il est permis à l'utilisateur, sinon le premier permis."""
        modes = next((k.get('modes') or [] for k in self._desk_kinds()
                      if k['key'] == kind), [])
        allowed = [mode['key'] for mode in modes]
        wanted = (options.get('modes') or {}).get(kind) if isinstance(
            options.get('modes'), dict) else None
        return wanted if wanted in allowed else (allowed[0] if allowed else None)

    # ------------------------------------------------------------------
    # Carte de résultat
    # ------------------------------------------------------------------

    @api.model
    def _desk_card(self, kind, status, title, message='', lines=None,
                   warnings=None, actions=None, raw='', form=None):
        """Résultat d'une lecture, affiché tel quel par l'écran.

        ``status`` : ``success`` (fait), ``pending`` (reconnu, une action
        reste à faire), ``duplicate``, ``error`` ou ``unknown``.
        ``lines`` : liste de ``(libellé, valeur)`` ; les valeurs vides sont
        retirées. ``actions`` : liste de ``{'label', 'action', 'primary'}``
        où ``action`` est une action Odoo ouverte au clic. ``form`` :
        formulaire à remplir (``_desk_form``).
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
            'form': form or False,
        }

    @api.model
    def _desk_form(self, payload, fields_spec, submit_label, intro=''):
        """Formulaire porté par une carte.

        ``payload`` : ce que le serveur doit retrouver à la validation (le
        texte du QR-code, jamais une valeur de confiance : tout est relu et
        recontrôlé par ``desk_submit``). ``fields_spec`` : liste de dicts
        ``name``, ``label``, ``type`` (``text``, ``integer``, ``float``,
        ``date`` ou ``selection``), et au besoin ``required``, ``value``,
        ``options`` (liste de ``[valeur, libellé]``) et ``help``.
        """
        return {
            'payload': payload,
            'submit_label': submit_label,
            'intro': intro,
            'fields': [dict({'required': False, 'value': '', 'options': [],
                             'help': ''}, **field) for field in fields_spec],
        }

    # ------------------------------------------------------------------
    # QR-code de contrôle (« Tester la douchette »)
    # ------------------------------------------------------------------

    @api.model
    def _desk_scan_test(self, text, options):
        verdict = check_scanner_test(text)
        if not verdict:
            return None
        if verdict == 'ok':
            return self._desk_card(
                False, 'success', _("Douchette bien réglée"),
                message=_("Tous les caractères du QR-code de contrôle sont "
                          "arrivés intacts : ce poste est prêt."))
        if verdict == 'caps':
            return self._desk_card(
                False, 'error', _("Verrouillage des majuscules actif"),
                message=_("Les majuscules et les minuscules sont inversées. "
                          "Désactivez la touche « Verr. Maj » du poste, "
                          "puis refaites le test."),
                raw=text)
        return self._desk_card(
            False, 'error', _("Douchette réglée en clavier anglais"),
            message=_("La douchette est en QWERTY alors que le poste est en "
                      "AZERTY. Odoo corrige les factures DGI et les "
                      "connaissements, mais réglez la douchette en clavier "
                      "français : scannez le code « clavier français / "
                      "AZERTY » de sa notice, puis refaites le test."),
            raw=text)

    # ------------------------------------------------------------------
    # Facture certifiée DGI
    # ------------------------------------------------------------------

    @api.model
    def _desk_dgi_modes(self):
        """Gestes permis sur une facture DGI, comme dans l'application.

        * ``create`` — enregistrer la facture : profils qui créent un scan
          (Vérificateur, Responsable) ;
        * ``process`` — marquer « traitée » une facture déjà scannée :
          profil Traiteur ;
        * ``lookup`` — savoir si une facture déjà enregistrée est liée à un
          OT : profil Gestionnaire OT. Ce geste ne crée JAMAIS de facture :
          une facture inconnue est renvoyée vers le secrétariat.
        """
        user = self.env.user
        modes = []
        if self.env['invoice.scan.record'].check_access_rights(
                'create', raise_exception=False):
            modes.append({
                'key': 'create',
                'label': _("Enregistrer la facture"),
                'hint': _("La facture fournisseur (ou l'avoir) est créée "
                          "aussitôt."),
            })
        if user.has_group('invoice_qr_scanner.group_invoice_scanner_traiteur'):
            modes.append({
                'key': 'process',
                'label': _("Marquer comme traitée"),
                'hint': _("La facture déjà scannée passe à « Traitée »."),
            })
        if user.has_group('invoice_qr_scanner.group_invoice_scanner_ot_manager'):
            modes.append({
                'key': 'lookup',
                'label': _("Vérifier le lien avec un OT"),
                'hint': _("Dit si la facture est liée à un OT. Rien n'est "
                          "créé : une facture inconnue est à transmettre au "
                          "secrétariat."),
            })
        return modes

    @api.model
    def _desk_scan_dgi(self, text, options):
        parsed = parse_dgi_qr(text)
        if not parsed:
            return None
        mode = self._desk_mode('dgi', options)
        if not mode:
            return self._desk_card(
                'dgi', 'error', _("Scan de facture non autorisé"),
                message=_("Le scan des factures DGI est réservé aux profils "
                          "du Scanner de factures (Vérificateur, Traiteur, "
                          "Gestionnaire OT, Responsable)."))
        warnings = [KEYBOARD_LAYOUT_WARNING] if parsed['layout_fixed'] else []
        if mode == 'process':
            return self._desk_dgi_process(parsed, warnings)
        if mode == 'lookup':
            return self._desk_dgi_lookup(parsed, warnings)
        qr_uuid = parsed['qr_uuid']
        FneApi = self.env['fne.api.client'].sudo()
        outcome = self.env['invoice.scan.record'].sudo()._process_qr_scan(
            self.env.user, parsed['qr_url'], qr_uuid,
            lambda: FneApi.fetch_invoice(qr_uuid), origin='douchette')
        return self._desk_dgi_outcome(outcome, parsed, warnings)

    @api.model
    def _desk_dgi_outcome(self, outcome, parsed, warnings):
        """Carte d'un passage par ``_process_qr_scan`` (scan ou saisie)."""
        if outcome['ok']:
            record = outcome['record']
            is_refund = record.document_type == 'refund'
            return self._desk_card(
                'dgi', 'success',
                _("Avoir enregistré") if is_refund else _("Facture créée"),
                lines=self._desk_dgi_lines(record),
                warnings=self._desk_same_number(record) + warnings,
                actions=self._desk_dgi_actions(record))

        code = outcome['error_code']
        if code == 'DUPLICATE':
            existing = outcome['existing']
            return self._desk_card(
                'dgi', 'duplicate', _("Déjà scannée"),
                message=_(
                    "Cette facture a déjà été scannée par %(user)s le "
                    "%(date)s. Rien n'a été créé.",
                    user=existing.scanned_by.name or _("un autre utilisateur"),
                    date=self._desk_day(existing.scan_date) or '?'),
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
        # Comme dans l'application, la saisie manuelle prend le relais.
        return self._desk_card(
            'dgi', 'error', _("La DGI n'a pas répondu"),
            message=_(
                "%(reason)s Rien n'a été enregistré. Scannez à nouveau dans "
                "un instant, ou recopiez la facture papier ci-dessous.",
                reason=outcome['message']),
            warnings=warnings,
            form=self._desk_dgi_manual_form(parsed))

    @api.model
    def _desk_day(self, moment):
        return format_date(self.env, fields.Datetime.context_timestamp(
            self, moment).date()) if moment else ''

    # -- Mode Traiteur --------------------------------------------------

    @api.model
    def _desk_dgi_process(self, parsed, warnings):
        outcome = self.env['invoice.scan.record'].sudo()._process_qr_treatment(
            self.env.user, parsed['qr_uuid'], _("depuis le poste de scan"))
        record = outcome['record']
        if outcome['ok']:
            return self._desk_card(
                'dgi', 'success', _("Facture marquée traitée"),
                lines=self._desk_dgi_lines(record),
                warnings=self._desk_same_number(record) + warnings,
                actions=self._desk_dgi_actions(record))
        if outcome['error_code'] == 'NOT_FOUND':
            return self._desk_card(
                'dgi', 'error', _("Facture pas encore scannée"),
                message=_("Aucune facture n'est enregistrée pour ce "
                          "QR-code : le Vérificateur doit d'abord la "
                          "scanner."),
                warnings=warnings)
        return self._desk_card(
            'dgi', 'duplicate', _("Déjà traitée"),
            message=_(
                "Cette facture a déjà été traitée par %(user)s le %(date)s "
                "(tentative n° %(count)s). Rien n'a été modifié.",
                user=record.processed_by.name or _("un utilisateur"),
                date=self._desk_day(record.processed_date) or '?',
                count=record.reprocess_attempt_count),
            lines=self._desk_dgi_lines(record), warnings=warnings,
            actions=self._desk_dgi_actions(record))

    @api.model
    def _desk_same_number(self, record):
        """Avertissement « même numéro de facture », en tête des autres."""
        warning = record._same_number_warning()
        return [warning] if warning else []

    @api.model
    def _desk_dgi_lookup(self, parsed, warnings):
        """Geste du Gestionnaire OT : la facture est-elle liée à un OT ?

        Lecture seule sur les scans : rien n'est créé, la DGI n'est pas
        interrogée, aucun doublon n'est compté. Une facture inconnue est
        notée dans « Factures à vérifier » pour le secrétariat.
        """
        Scan = self.env['invoice.scan.record'].sudo()
        records = Scan.search([
            ('qr_uuid', '=', parsed['qr_uuid']),
            ('company_id', '=', self.env.company.id),
        ], order='id desc')
        record = records.filtered(
            lambda r: r.state in ('done', 'processed'))[:1]
        if record:
            lines = self._desk_dgi_lines(record)
            # Champ apporté par potting_management, s'il est installé.
            if 'transit_order_refs' in record._fields:
                refs = record.transit_order_refs
                lines.append((_("OT liés"), refs or _("Aucun")))
                title = _("Facture liée à un OT") if refs else _(
                    "Facture non liée à un OT")
            else:
                title = _("Facture enregistrée")
            return self._desk_card(
                'dgi', 'success', title, lines=lines, warnings=warnings,
                actions=self._desk_dgi_actions(record))
        if records:
            return self._desk_card(
                'dgi', 'pending', _("Vérification non terminée"),
                message=_(
                    "Cette facture a été présentée au secrétariat mais son "
                    "enregistrement n'est pas terminé. Transmettez-la au "
                    "secrétariat pour qu'il termine sa vérification."),
                warnings=warnings)
        notified = self.env['invoice.scan.pending.invoice']._register_request(
            self.env.user, parsed['qr_uuid'], origin='douchette')
        message = _(
            "Rien n'a été créé. Transmettez-la au secrétariat pour "
            "vérification : elle y sera créée, ou signalée comme doublon si "
            "elle existe déjà.")
        if notified:
            message += ' ' + _(
                "Le secrétariat est prévenu (Scans ▸ Factures à vérifier).")
        return self._desk_card(
            'dgi', 'pending', _("Cette facture n'existe pas encore"),
            message=message, warnings=warnings)

    # -- Saisie manuelle (DGI injoignable) -------------------------------

    @api.model
    def _desk_dgi_manual_form(self, parsed):
        return self._desk_form(
            {'qr_url': parsed['qr_url']},
            [
                {'name': 'supplier_name', 'label': _("Fournisseur"),
                 'type': 'text', 'required': True},
                {'name': 'supplier_code_dgi', 'label': _("NCC du fournisseur"),
                 'type': 'text',
                 'help': _("7 chiffres et une lettre, ex. 2502298K")},
                {'name': 'invoice_number_dgi', 'label': _("N° de facture DGI"),
                 'type': 'text', 'required': True},
                {'name': 'invoice_date', 'label': _("Date de la facture"),
                 'type': 'date'},
                {'name': 'amount_ttc', 'label': _("Montant TTC"),
                 'type': 'float', 'required': True},
                {'name': 'document_type', 'label': _("Nature"),
                 'type': 'selection', 'required': True, 'value': 'invoice',
                 'options': [['invoice', _("Facture")],
                             ['refund', _("Avoir")]]},
            ],
            _("Enregistrer la saisie manuelle"),
            intro=_("Saisie manuelle : recopiez la facture papier. Le scan "
                    "sera marqué « saisie manuelle » et sa nature « à "
                    "confirmer »."))

    @api.model
    def _desk_submit_dgi(self, payload, values):
        # Rien n'est cru sur parole : le QR-code est relu, le droit revérifié.
        parsed = parse_dgi_qr(payload.get('qr_url') or '')
        if not parsed:
            raise UserError(_("QR-code illisible : scannez à nouveau."))
        if 'create' not in [m['key'] for m in self._desk_dgi_modes()]:
            raise UserError(_(
                "Votre profil ne permet pas d'enregistrer une facture."))

        def text(name):
            value = values.get(name)
            return value.strip() if isinstance(value, str) else ''

        supplier_name = text('supplier_name')
        invoice_number = text('invoice_number_dgi')
        if not supplier_name:
            raise UserError(_("Le nom du fournisseur est obligatoire."))
        if not invoice_number:
            raise UserError(_("Le numéro de facture DGI est obligatoire."))
        try:
            amount = float(str(values.get('amount_ttc') or '').replace(
                ' ', '').replace('\u00a0', '').replace('\u202f', '').replace(
                ',', '.'))
        except ValueError:
            amount = 0.0
        if not amount:
            raise UserError(_("Le montant TTC est obligatoire (un nombre)."))
        document_type = values.get('document_type')
        if document_type not in ('invoice', 'refund'):
            document_type = 'invoice'
        if amount < 0:
            # Un montant négatif est la signature d'un avoir
            document_type, amount = 'refund', abs(amount)
        try:
            invoice_date = fields.Date.to_date(text('invoice_date') or None)
        except ValueError:
            raise UserError(_("Date de facture illisible.")) from None

        outcome = self.env['invoice.scan.record'].sudo()._process_qr_scan(
            self.env.user, parsed['qr_url'], parsed['qr_uuid'], {
                'supplier_name': supplier_name,
                'supplier_code_dgi': text('supplier_code_dgi').upper() or False,
                'invoice_number_dgi': invoice_number,
                'invoice_date': invoice_date,
                'amount_ttc': amount,
                'document_type': document_type,
                # Nature déclarée, non confirmée par la DGI : le scan
                # remonte dans le filtre « Nature à confirmer ».
                'document_type_verified': False,
                'is_manual_entry': True,
            }, origin='douchette-saisie-manuelle')
        return self._desk_dgi_outcome(outcome, parsed, [])

    # -- Présentation ----------------------------------------------------

    @api.model
    def _desk_dgi_lines(self, record):
        nature = dict(record._fields['document_type']._description_selection(
            self.env)).get(record.document_type, '')
        state = dict(record._fields['state']._description_selection(
            self.env)).get(record.state, '')
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
            (_("État"), state),
        ]

    @api.model
    def _desk_dgi_actions(self, record):
        """Boutons de la carte, selon ce que l'utilisateur peut faire."""
        actions = []
        # Rattachement à un OT : opération ajoutée à l'assistant de
        # traitement groupé par potting_management, s'il est installé.
        Wizard = self.env['invoice.scan.bulk.process']
        can_link = 'link_ot' in dict(Wizard._selection_operation()) \
            and self.env.user.has_group(
                'invoice_qr_scanner.group_invoice_scanner_ot_manager') \
            and record.state in ('done', 'processed')
        if can_link:
            actions.append({
                'label': _("Rattacher à un OT"),
                'primary': True,
                'action': {
                    'type': 'ir.actions.act_window',
                    'name': _("Rattacher à un Ordre de Transit"),
                    'res_model': 'invoice.scan.bulk.process',
                    'views': [[False, 'form']],
                    'target': 'new',
                    'context': {
                        'active_model': 'invoice.scan.record',
                        'active_ids': [record.id],
                        'default_operation': 'link_ot',
                    },
                },
            })
        # Ouverture de la fiche, seulement si l'utilisateur peut la lire
        visible = self.env['invoice.scan.record'].search(
            [('id', '=', record.id)], limit=1)
        if visible:
            actions.append({
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
            })
        return actions
