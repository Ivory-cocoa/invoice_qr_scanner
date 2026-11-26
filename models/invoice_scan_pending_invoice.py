# -*- coding: utf-8 -*-
"""Factures à vérifier par le secrétariat.

Le Gestionnaire OT ne crée pas de facture : quand il scanne une facture qui
n'existe pas encore dans Odoo, il doit la transmettre au secrétariat, qui
vérifie toutes les factures FNE reçues. Ce modèle garde la trace de cette
attente — rien d'autre : ni scan, ni facture, ni donnée de la DGI.

Une ligne par QR-code. Elle se referme toute seule dès que le secrétariat
vérifie la facture (création du scan).
"""

import logging
import re

from odoo import _, api, fields, models

_logger = logging.getLogger(__name__)

UUID_PATTERN = re.compile(
    r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')


class InvoiceScanPendingInvoice(models.Model):
    _name = 'invoice.scan.pending.invoice'
    _description = "Facture à vérifier par le secrétariat"
    _order = 'last_request_date desc, id desc'
    _rec_name = 'qr_uuid'

    qr_uuid = fields.Char(
        string="Identifiant du QR-code", required=True, index=True, readonly=True)
    company_id = fields.Many2one(
        'res.company', string="Société", required=True, readonly=True,
        default=lambda self: self.env.company)
    state = fields.Selection([
        ('pending', "À vérifier"),
        ('done', "Vérifiée"),
        ('cancelled', "Sans suite"),
    ], string="État", default='pending', required=True, index=True, readonly=True)
    requested_by = fields.Many2one(
        'res.users', string="Demandée par", readonly=True,
        help="Dernier Gestionnaire OT à avoir présenté cette facture.")
    first_request_date = fields.Datetime(
        string="Première demande", readonly=True, default=fields.Datetime.now)
    last_request_date = fields.Datetime(
        string="Dernière demande", readonly=True, default=fields.Datetime.now)
    request_count = fields.Integer(
        string="Présentations", default=1, readonly=True,
        help="Nombre de fois où cette facture a été présentée par un "
             "Gestionnaire OT avant d'être vérifiée.")
    origin = fields.Selection([
        ('app', "Application mobile"),
        ('douchette', "Poste de scan"),
    ], string="Depuis", readonly=True)
    scan_record_id = fields.Many2one(
        'invoice.scan.record', string="Scan", readonly=True, ondelete='set null',
        help="Scan créé par la vérification du secrétariat.")
    verified_date = fields.Datetime(string="Vérifiée le", readonly=True)
    dgi_preview_url = fields.Char(
        string="Page de vérification DGI", compute='_compute_dgi_preview_url')

    _sql_constraints = [
        ('qr_uuid_company_unique', 'unique(qr_uuid, company_id)',
         "Cette facture est déjà dans la liste des factures à vérifier."),
    ]

    @api.depends('qr_uuid')
    def _compute_dgi_preview_url(self):
        site = self.env['fne.api.client']._get_public_site_url()
        for record in self:
            uuid = (record.qr_uuid or '').strip().lower()
            if site and UUID_PATTERN.fullmatch(uuid):
                record.dgi_preview_url = '%s/fr/verification/%s' % (site, uuid)
            else:
                record.dgi_preview_url = False

    # ------------------------------------------------------------------
    # Enregistrement d'une demande
    # ------------------------------------------------------------------

    @api.model
    def _register_request(self, user, qr_uuid, origin='app'):
        """Noter qu'un Gestionnaire OT attend la vérification d'une facture.

        Idempotent : une facture déjà en attente n'est pas dupliquée, son
        compteur avance. Le secrétariat n'est prévenu qu'à la première
        demande (ou à la reprise d'une demande classée), pas à chaque scan.

        Ne lève jamais : l'attente est un service rendu au secrétariat, elle
        ne doit pas faire échouer la consultation du Gestionnaire OT.

        Returns:
            bool: vrai si la demande est enregistrée (nouvelle ou déjà là).
        """
        qr_uuid = (qr_uuid or '').strip().lower()
        if not UUID_PATTERN.fullmatch(qr_uuid):
            return False
        Pending = self.sudo()
        company = user.company_id or self.env.company
        try:
            with self.env.cr.savepoint():
                now = fields.Datetime.now()
                pending = Pending.search([
                    ('qr_uuid', '=', qr_uuid), ('company_id', '=', company.id),
                ], limit=1)
                if pending:
                    reopened = pending.state != 'pending'
                    pending.write({
                        'state': 'pending',
                        'requested_by': user.id,
                        'last_request_date': now,
                        'request_count': pending.request_count + 1,
                        'origin': origin,
                        'scan_record_id': False,
                        'verified_date': False,
                    })
                else:
                    reopened = True
                    pending = Pending.create({
                        'qr_uuid': qr_uuid,
                        'company_id': company.id,
                        'requested_by': user.id,
                        'origin': origin,
                    })
                if reopened:
                    pending._notify_secretariat()
            return True
        except Exception:  # pylint: disable=broad-except
            _logger.exception(
                "Facture à vérifier : demande non enregistrée (%s)", qr_uuid)
            return False

    def _secretariat_users(self):
        """Utilisateurs qui vérifient les factures (Vérificateur, Responsable)."""
        group = self.env.ref(
            'invoice_qr_scanner.group_invoice_scanner_verificateur',
            raise_if_not_found=False)
        if not group:
            return self.env['res.users']
        return group.sudo().users.filtered(
            lambda u: u.active and not u.share
            and self.company_id in u.company_ids)

    def _notify_secretariat(self):
        """Message à l'écran des vérificateurs connectés. Pas d'e-mail : la
        liste « Factures à vérifier » reste la référence."""
        for pending in self:
            users = pending._secretariat_users() - pending.requested_by
            if not users:
                continue
            payload = {
                'type': 'warning',
                'sticky': True,
                'title': _("Facture à vérifier"),
                'message': _(
                    "%(user)s a présenté une facture qui n'existe pas encore "
                    "dans Odoo. Elle doit être transmise au secrétariat pour "
                    "vérification (menu Scans ▸ Factures à vérifier).",
                    user=pending.requested_by.name or _("Un Gestionnaire OT")),
            }
            self.env['bus.bus']._sendmany([
                (user.partner_id, 'simple_notification', payload)
                for user in users
            ])

    # ------------------------------------------------------------------
    # Clôture
    # ------------------------------------------------------------------

    @api.model
    def _close_for_scans(self, scans):
        """Refermer les demandes dont la facture vient d'être vérifiée."""
        scans = scans.sudo().filtered(
            lambda s: s.state in ('done', 'processed') and s.qr_uuid)
        if not scans:
            return
        pendings = self.sudo().search([
            ('state', '=', 'pending'),
            ('qr_uuid', 'in', scans.mapped('qr_uuid')),
        ])
        if not pendings:
            return
        by_key = {(s.qr_uuid, s.company_id.id): s for s in scans}
        now = fields.Datetime.now()
        for pending in pendings:
            scan = by_key.get((pending.qr_uuid, pending.company_id.id))
            if not scan:
                continue
            pending.write({
                'state': 'done', 'scan_record_id': scan.id, 'verified_date': now})
            requester = pending.requested_by
            if requester and requester.active:
                self.env['bus.bus']._sendone(
                    requester.partner_id, 'simple_notification', {
                        'type': 'success',
                        'sticky': True,
                        'title': _("Facture vérifiée"),
                        'message': _(
                            "La facture %(number)s que vous attendiez a été "
                            "vérifiée par le secrétariat : vous pouvez la "
                            "lier à un OT.",
                            number=scan.invoice_number_dgi or scan.reference),
                    })

    def action_cancel(self):
        """Classer sans suite (facture qui ne viendra pas, erreur de scan)."""
        self.filtered(lambda p: p.state == 'pending').write({'state': 'cancelled'})
        return True

    def action_reopen(self):
        self.filtered(lambda p: p.state == 'cancelled').write({'state': 'pending'})
        return True

    def action_open_dgi_page(self):
        self.ensure_one()
        if not self.dgi_preview_url:
            return False
        return {
            'type': 'ir.actions.act_url',
            'url': self.dgi_preview_url,
            'target': 'new',
        }

    def action_view_scan(self):
        self.ensure_one()
        if not self.scan_record_id:
            return False
        return self.scan_record_id.action_open_scan_form()
