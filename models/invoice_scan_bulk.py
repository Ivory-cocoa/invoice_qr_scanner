# -*- coding: utf-8 -*-
"""Moteur de traitement groupé des scans de QR-code.

Point unique par lequel passent TOUS les chemins de traitement en lot :
l'assistant du back-office, les actions du menu ⚙️ de la liste et l'API
mobile (`/api/v1/invoice-scanner/bulk-mark-processed`). Chacun d'eux
réimplémentait auparavant sa propre boucle `write` + `message_post`, avec
des messages de chatter divergents et des règles d'éligibilité qui ne se
recoupaient pas tout à fait.

Deux principes gouvernent ce module :

1. **Rien n'est écrémé en silence.** Les méthodes ci-dessous ne filtrent
   jamais la sélection : elles rendent compte de CHAQUE enregistrement
   reçu, y compris de ceux qu'elles n'ont pas touchés et de la raison.
   Une action de masse qui traite 3 lignes sur 50 sans le dire est un
   piège : l'utilisateur croit son lot soldé.

2. **Un échec n'emporte pas le lot.** La création de pièce comptable
   s'exécute sous point de sauvegarde, enregistrement par enregistrement :
   une facture qui échoue laisse les autres acquises. Sans cela, la
   moindre erreur invalide la transaction entière — et l'utilisateur perd
   aussi les enregistrements qui, eux, étaient passés.
"""

import logging

from odoo import _, fields, models

_logger = logging.getLogger(__name__)

# Statuts d'une ligne de compte-rendu.
BULK_DONE = 'done'
BULK_SKIPPED = 'skipped'
BULK_ERROR = 'error'


class InvoiceScanRecordBulk(models.Model):
    _inherit = 'invoice.scan.record'

    # Garde-fou de volume pour les opérations qui interrogent la plateforme
    # DGI : une ligne = un appel réseau. Au-delà, la requête HTTP du navigateur
    # expire avant la fin du lot et l'utilisateur ne voit jamais le
    # compte-rendu. Attribut de classe — et non constante de module — pour
    # rester lisible depuis les autres fichiers du modèle sans import croisé :
    # importer `invoice_scan_bulk` depuis `invoice_scan_record` inverserait
    # l'ordre de définition des classes et Odoo refuserait de construire le
    # modèle (« Model does not exist in registry »).
    BULK_NETWORK_LIMIT = 200

    # =========================================================================
    # OUTILLAGE DU COMPTE-RENDU
    # =========================================================================
    def _bulk_result(self, results):
        """Ordonner les résultats selon la sélection reçue.

        `results` est un dict {id: (statut, message)}. On le restitue sous
        forme de liste, dans l'ordre du recordset, en marquant explicitement
        tout enregistrement qu'une opération aurait oublié de renseigner —
        un oubli doit se voir, pas disparaître.
        """
        entries = []
        for record in self:
            status, message = results.get(
                record.id,
                (BULK_SKIPPED, _("Aucune opération applicable.")),
            )
            entries.append({
                'scan_id': record.id,
                'reference': record.reference,
                'status': status,
                'message': message,
            })
        return entries

    @staticmethod
    def _bulk_counters(entries):
        """Compteurs synthétiques d'un compte-rendu."""
        return {
            'total': len(entries),
            BULK_DONE: sum(1 for e in entries if e['status'] == BULK_DONE),
            BULK_SKIPPED: sum(1 for e in entries if e['status'] == BULK_SKIPPED),
            BULK_ERROR: sum(1 for e in entries if e['status'] == BULK_ERROR),
        }

    def _bulk_state_label(self):
        self.ensure_one()
        return dict(self._fields['state'].selection).get(self.state, self.state)

    # =========================================================================
    # OPÉRATION — MARQUER TRAITÉ
    # =========================================================================
    def _bulk_mark_processed(self, user=None, origin=None):
        """Marquer en lot les scans comme traités.

        Args:
            user: utilisateur à inscrire comme traiteur (défaut : l'utilisateur
                courant). L'API mobile agit en `sudo` pour le compte d'un
                utilisateur authentifié : c'est LUI qui doit figurer dans
                `processed_by`, pas le compte technique.
            origin: mention libre ajoutée au chatter (« application mobile »…).

        Returns:
            list: compte-rendu, une entrée par enregistrement reçu.
        """
        user = user or self.env.user
        results = {}
        todo = self.browse()

        for record in self:
            if record.state == 'processed':
                results[record.id] = (BULK_SKIPPED, _(
                    "Déjà traité par %(user)s.",
                    user=record.processed_by.name or _("un utilisateur"),
                ))
            elif record.state != 'done':
                results[record.id] = (BULK_SKIPPED, _(
                    "État « %(state)s » : seuls les scans dont la pièce "
                    "comptable est créée peuvent être marqués traités.",
                    state=record._bulk_state_label(),
                ))
            else:
                todo |= record

        if todo:
            todo.write({
                'state': 'processed',
                'processed_by': user.id,
                'processed_date': fields.Datetime.now(),
            })
            body = _("Scan marqué comme traité par %(user)s (traitement groupé%(origin)s).",
                     user=user.name, origin=_(" — %s") % origin if origin else '')
            # `_message_log_batch` écrit les N messages en une passe : un
            # `message_post` par enregistrement rendait le marquage d'un lot
            # de 200 lignes perceptiblement lent.
            todo._message_log_batch(bodies={r.id: body for r in todo})
            for record in todo:
                results[record.id] = (BULK_DONE, _("Marqué comme traité."))

        return self._bulk_result(results)

    # =========================================================================
    # OPÉRATION — REMETTRE NON TRAITÉ
    # =========================================================================
    def _bulk_mark_unprocessed(self, origin=None):
        """Remettre en lot les scans à l'état « Facture créée »."""
        results = {}
        todo = self.browse()

        for record in self:
            if record.state != 'processed':
                results[record.id] = (BULK_SKIPPED, _(
                    "État « %(state)s » : seuls les scans traités peuvent "
                    "être remis à « Facture créée ».",
                    state=record._bulk_state_label(),
                ))
            else:
                todo |= record

        if todo:
            todo.write({
                'state': 'done',
                'processed_by': False,
                'processed_date': False,
            })
            body = _("Scan remis à « Facture créée » par %(user)s "
                     "(traitement groupé%(origin)s).",
                     user=self.env.user.name,
                     origin=_(" — %s") % origin if origin else '')
            todo._message_log_batch(bodies={r.id: body for r in todo})
            for record in todo:
                results[record.id] = (BULK_DONE, _("Remis à « Facture créée »."))

        return self._bulk_result(results)

    # =========================================================================
    # OPÉRATION — (RE)CRÉER LA PIÈCE COMPTABLE
    # =========================================================================
    def _bulk_create_invoice(self):
        """Créer en lot la pièce comptable des scans en brouillon ou en erreur.

        Chaque création s'exécute sous point de sauvegarde : l'échec de l'une
        n'annule pas celles qui l'ont précédée. `cr.savepoint()` vide aussi le
        cache de l'ORM en cas de retour arrière, sans quoi les valeurs écrites
        avant l'échec resteraient visibles en mémoire alors qu'elles ne sont
        plus en base.
        """
        results = {}

        for record in self:
            if record.invoice_id:
                results[record.id] = (BULK_SKIPPED, _(
                    "Pièce comptable déjà créée (%(move)s).",
                    move=record.invoice_id.name or record.invoice_id.display_name,
                ))
                continue
            if record.state not in ('draft', 'error'):
                results[record.id] = (BULK_SKIPPED, _(
                    "État « %(state)s » : rien à créer.",
                    state=record._bulk_state_label(),
                ))
                continue

            try:
                with self.env.cr.savepoint():
                    invoice = record._create_invoice()
            except Exception as exc:  # noqa: BLE001 - on rend compte de tout
                _logger.info("Création de pièce impossible pour le scan %s : %s",
                             record.reference, exc)
                # Écrit APRÈS le retour arrière du point de sauvegarde :
                # à l'intérieur, la trace de l'erreur serait annulée avec le
                # reste — c'est précisément ce que fait aujourd'hui
                # `action_retry_create_invoice`, dont le `error_message` ne
                # survit jamais au `UserError` qui suit.
                record.write({'state': 'error', 'error_message': str(exc)})
                results[record.id] = (BULK_ERROR, str(exc))
            else:
                results[record.id] = (BULK_DONE, _(
                    "Pièce comptable %(move)s créée.",
                    move=invoice.name or invoice.display_name,
                ))

        return self._bulk_result(results)

    # =========================================================================
    # OPÉRATION — VÉRIFIER LA NATURE AUPRÈS DE LA DGI
    # =========================================================================
    def _bulk_verify_document_type(self):
        """Confirmer en lot la nature (facture / avoir) auprès de la DGI.

        Reprend mot pour mot les règles de `action_verify_document_type` — dont
        la garde essentielle : un scan dont la pièce est déjà comptabilisée
        n'est JAMAIS requalifié à la volée, il est signalé pour réparation.
        """
        FneApi = self.env['fne.api.client']
        results = {}
        selection = dict(self._fields['document_type'].selection)

        for record in self:
            try:
                nature = FneApi.fetch_document_nature(record.qr_uuid)
            except Exception as exc:  # FneApiError et imprévus réseau
                _logger.info("Vérification de nature impossible pour %s (%s)",
                             record.reference, exc)
                results[record.id] = (BULK_ERROR, _("DGI injoignable : %s") % exc)
                continue

            values = {'document_type_verified': True}
            if nature.get('origin_invoice_number_dgi'):
                values['origin_invoice_number_dgi'] = nature['origin_invoice_number_dgi']

            if nature['document_type'] == record.document_type:
                record.write(values)
                results[record.id] = (BULK_DONE, _(
                    "Nature confirmée : %(nature)s.",
                    nature=selection.get(record.document_type, record.document_type),
                ))
                continue

            if record.invoice_id and record.invoice_id.state == 'posted':
                results[record.id] = (BULK_ERROR, _(
                    "ÉCART : la DGI déclare « %(dgi)s », la pièce est "
                    "comptabilisée. Requalification par la réparation dédiée.",
                    dgi=selection.get(nature['document_type'], nature['document_type']),
                ))
                record.message_post(
                    body=_(
                        "ÉCART DE NATURE : la DGI déclare « %(dgi)s » alors que "
                        "ce scan est enregistré en « %(local)s », et sa pièce "
                        "comptable est déjà comptabilisée. Requalification à "
                        "faire par la réparation dédiée.",
                        dgi=selection.get(nature['document_type'], nature['document_type']),
                        local=selection.get(record.document_type, record.document_type),
                    ),
                    message_type='notification',
                )
                continue

            values['document_type'] = nature['document_type']
            record.with_context(allow_document_type_change=True).write(values)
            results[record.id] = (BULK_DONE, _(
                "Requalifié en « %(nature)s ».",
                nature=selection.get(nature['document_type'], nature['document_type']),
            ))

        return self._bulk_result(results)

    # =========================================================================
    # ACTIONS DE MASSE — menu ⚙️ et boutons d'en-tête de la liste
    # =========================================================================
    def _bulk_notification(self, title, entries):
        """Notification de synthèse d'un traitement groupé.

        Les actions d'un clic ne renvoyaient rien : l'utilisateur ne savait
        pas combien de lignes avaient réellement bougé. On affiche donc
        toujours le décompte, et on rend la notification persistante dès
        qu'une ligne a été écartée ou a échoué — pour qu'elle soit lue.
        """
        counters = self._bulk_counters(entries)
        message = _(
            "%(done)s traité(s) · %(skipped)s ignoré(s) · %(error)s en erreur "
            "(sur %(total)s sélectionné(s)).",
            done=counters[BULK_DONE], skipped=counters[BULK_SKIPPED],
            error=counters[BULK_ERROR], total=counters['total'],
        )
        incomplete = counters[BULK_SKIPPED] or counters[BULK_ERROR]
        return {
            'type': 'ir.actions.client',
            'tag': 'display_notification',
            'params': {
                'title': title,
                'message': message,
                'type': 'danger' if counters[BULK_ERROR] else (
                    'warning' if incomplete else 'success'),
                'sticky': bool(incomplete),
                'next': {'type': 'ir.actions.act_window_close'},
            },
        }

    def action_open_bulk_process_wizard(self):
        """Ouvrir l'assistant de traitement groupé sur la sélection.

        Appelée par le bouton d'en-tête de la vue liste : `self` porte alors
        les enregistrements cochés. Le repli sur `active_ids` couvre les
        appels venus d'une action serveur.
        """
        scan_ids = self.ids or self.env.context.get('active_ids') or []
        return {
            'type': 'ir.actions.act_window',
            'name': _("Traitement groupé des scans"),
            'res_model': 'invoice.scan.bulk.process',
            'view_mode': 'form',
            'target': 'new',
            'context': dict(self.env.context, default_scan_ids=[(6, 0, list(scan_ids))]),
        }
