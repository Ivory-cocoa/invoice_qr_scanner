# -*- coding: utf-8 -*-
"""Avoirs FNE : nature du document, comptabilisation, requalification.

Ce que ces tests protègent
==========================
La plateforme FNE certifie les avoirs sous un QR-code de forme identique à
celui des factures. Confondre les deux enregistre une créance en dette : c'est
arrivé 24 fois, pour 167,9 M FCFA, avant que la nature du document n'existe
comme champ.

Chaque test ci-dessous fixe un maillon de la chaîne qui rend cette confusion
impossible : la nature est portée par un champ, le montant reste positif, le
signe vient du type, la pièce comptable est un `in_refund`, et une
requalification tardive extourne l'écriture au lieu de la réécrire en douce.
"""

from unittest.mock import patch

from odoo import fields
from odoo.exceptions import UserError, ValidationError
from odoo.tests import TransactionCase, tagged


@tagged('post_install', '-at_install', 'invoice_qr_scanner', 'refund')
class TestRefundDocuments(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()

        Currency = cls.env['res.currency'].with_context(active_test=False)
        cls.currency_xof = Currency.search([('name', '=', 'XOF')], limit=1)
        if cls.currency_xof:
            cls.currency_xof.active = True
        else:
            cls.currency_xof = Currency.create({
                'name': 'XOF', 'symbol': 'FCFA', 'rounding': 1,
            })

        cls.ScanRecord = cls.env['invoice.scan.record']
        cls.base_uuid = '01a0196f-7c15-7006-a5a7-85443a22c9'

    def _url(self, uuid):
        return 'https://www.services.fne.dgi.gouv.ci/fr/verification/%s' % uuid

    def _make_scan(self, uuid_suffix='29', document_type='invoice',
                   amount=250000, number='7603114Y26000010087', **kwargs):
        uuid = self.base_uuid + uuid_suffix
        values = {
            'qr_uuid': uuid,
            'qr_url': self._url(uuid),
            'supplier_name': 'PACKING SERVICE INTERNATIONAL',
            'supplier_code_dgi': '7603114Y',
            'invoice_number_dgi': number,
            'invoice_date': fields.Date.today(),
            'amount_ttc': amount,
            'document_type': document_type,
        }
        values.update(kwargs)
        return self.ScanRecord.create(values)

    # ------------------------------------------------------------------
    # Montant signé
    # ------------------------------------------------------------------

    def test_invoice_amount_is_positive(self):
        scan = self._make_scan(document_type='invoice')
        self.assertEqual(scan.amount_signed, 250000)

    def test_refund_amount_is_negative_but_stored_positive(self):
        """Le signe vient du TYPE, jamais du stockage.

        `amount_ttc` reste positif : la contrainte de montant, les vues et les
        cumuls historiques en dépendent. C'est `amount_signed` qui porte le
        sens, et lui seul qu'il est juste d'additionner.
        """
        scan = self._make_scan(document_type='refund')
        self.assertEqual(scan.amount_ttc, 250000)
        self.assertEqual(scan.amount_signed, -250000)

    def test_negative_amount_is_still_refused(self):
        """Un montant négatif reste une erreur de saisie, pas un avoir.

        Accepter les deux conventions (type OU signe) rouvrirait la porte à
        des doubles négations : un avoir de −250 000 valant +250 000.
        """
        with self.assertRaises(ValidationError):
            self._make_scan(document_type='refund', amount=-250000)

    def test_sum_of_invoice_and_refund_is_net(self):
        invoice = self._make_scan(uuid_suffix='01', document_type='invoice',
                                  amount=1000000)
        refund = self._make_scan(uuid_suffix='02', document_type='refund',
                                 amount=250000)
        self.assertEqual(
            sum((invoice | refund).mapped('amount_signed')), 750000)

    # ------------------------------------------------------------------
    # Pièce comptable
    # ------------------------------------------------------------------

    @staticmethod
    def _post(move):
        """Comptabiliser la pièce si elle ne l'est pas déjà.

        `_create_invoice` comptabilise TOUT SEUL quand le paramètre
        `auto_validate_invoice` est actif — ce qui est le défaut. Reposter
        derrière lève « must be in draft » : le test doit s'adapter au
        comportement réel, pas l'inverse.
        """
        if move.state == 'draft':
            move.action_post()
        return move

    def _require_accounting(self):
        journal = self.env['account.journal'].search(
            [('type', '=', 'purchase')], limit=1)
        account = self.env['account.account'].search(
            [('account_type', '=', 'expense')], limit=1)
        self.assertTrue(journal, "Base de test sans journal d'achats")
        self.assertTrue(account, "Base de test sans compte de charge")

    def test_invoice_creates_a_vendor_bill(self):
        self._require_accounting()
        scan = self._make_scan(document_type='invoice')
        move = scan._create_invoice()
        self.assertEqual(move.move_type, 'in_invoice')

    def test_refund_creates_a_vendor_credit_note(self):
        """LE test central : un avoir produit un `in_refund`, pas une facture.

        C'est exactement ce qui manquait : `_create_invoice` forçait
        `in_invoice` quel que soit le document, transformant chaque avoir en
        dette fournisseur.
        """
        self._require_accounting()
        scan = self._make_scan(document_type='refund')
        move = scan._create_invoice()

        self.assertEqual(move.move_type, 'in_refund')
        # Odoo attend un montant POSITIF sur un avoir : le sens est porté par
        # `move_type`, pas par le signe des lignes.
        self.assertEqual(move.amount_total, 250000)

    def test_refund_creation_is_traced_in_the_chatter(self):
        self._require_accounting()
        scan = self._make_scan(document_type='refund')
        scan._create_invoice()
        bodies = ' '.join(scan.message_ids.mapped('body'))
        self.assertIn('AVOIR', bodies)

    # ------------------------------------------------------------------
    # Rattachement avoir → facture d'origine
    # ------------------------------------------------------------------

    def test_refund_links_to_an_already_scanned_invoice(self):
        origin = self._make_scan(uuid_suffix='11', document_type='invoice',
                                 number='7603114Y26000010087')
        refund = self._make_scan(
            uuid_suffix='12', document_type='refund',
            number='A7603114Y2600000393',
            origin_invoice_number_dgi='7603114Y26000010087')
        self.assertEqual(refund.origin_scan_id, origin)
        self.assertEqual(origin.refund_count, 1)

    def test_refund_links_when_the_invoice_is_scanned_later(self):
        """L'ordre des scans n'est pas garanti.

        On scanne parfois l'avoir avant sa facture. Un simple champ calculé ne
        se recalculerait jamais à l'arrivée tardive de la facture : le
        rattachement est donc refait explicitement à chaque création.
        """
        refund = self._make_scan(
            uuid_suffix='21', document_type='refund',
            number='A7603114Y2600000393',
            origin_invoice_number_dgi='7603114Y26000010087')
        self.assertFalse(refund.origin_scan_id)

        origin = self._make_scan(uuid_suffix='22', document_type='invoice',
                                 number='7603114Y26000010087')
        self.assertEqual(refund.origin_scan_id, origin)

    # ------------------------------------------------------------------
    # Garde-fou de requalification
    # ------------------------------------------------------------------

    def test_cannot_requalify_a_posted_document(self):
        """Changer la nature ne change pas l'écriture : c'est donc refusé.

        Sans ce garde-fou, on obtiendrait un scan affichant « Avoir » au-dessus
        d'une facture d'achat bien vivante — une incohérence invisible.
        """
        self._require_accounting()
        scan = self._make_scan(document_type='invoice')
        move = self._post(scan._create_invoice())
        self.assertEqual(move.state, 'posted')

        with self.assertRaises(UserError):
            scan.write({'document_type': 'refund'})

    def test_requalification_is_possible_with_the_explicit_context(self):
        """La réparation, elle, sait ce qu'elle fait : elle passe le contexte."""
        self._require_accounting()
        scan = self._make_scan(document_type='invoice')
        self._post(scan._create_invoice())

        scan.with_context(allow_document_type_change=True).write(
            {'document_type': 'refund'})
        self.assertEqual(scan.document_type, 'refund')

    def test_requalification_of_a_draft_document_is_free(self):
        scan = self._make_scan(document_type='invoice')
        scan.write({'document_type': 'refund'})
        self.assertEqual(scan.document_type, 'refund')


@tagged('post_install', '-at_install', 'invoice_qr_scanner', 'refund')
class TestRefundRepair(TransactionCase):
    """Requalification des avoirs déjà comptabilisés en factures.

    Le réseau est simulé : la DGI est un tiers, et un test qui en dépend
    échouerait au gré de sa disponibilité.
    """

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        Currency = cls.env['res.currency'].with_context(active_test=False)
        xof = Currency.search([('name', '=', 'XOF')], limit=1)
        if xof:
            xof.active = True
        cls.ScanRecord = cls.env['invoice.scan.record']
        cls.uuid = '019d9a95-2158-7002-815a-a21287cc65b4'

    def _make_wrong_scan(self, post=True):
        """Un avoir enregistré comme une facture : l'état des 24 cas réels."""
        journal = self.env['account.journal'].search(
            [('type', '=', 'purchase')], limit=1)
        account = self.env['account.account'].search(
            [('account_type', '=', 'expense')], limit=1)
        self.assertTrue(journal, "Base de test sans journal d'achats")
        self.assertTrue(account, "Base de test sans compte de charge")

        scan = self.ScanRecord.create({
            'qr_uuid': self.uuid,
            'qr_url': 'https://www.services.fne.dgi.gouv.ci/fr/verification/%s'
                      % self.uuid,
            'supplier_name': 'SOCIETE DE TEST',
            'supplier_code_dgi': '1532352Y',
            'invoice_number_dgi': 'A1532352Y2600000001',
            'invoice_date': fields.Date.today(),
            'amount_ttc': 250000,
            'document_type': 'invoice',
        })
        move = scan._create_invoice()
        if post and move.state == 'draft':
            move.action_post()
        return scan, move

    def _patch_nature(self, document_type='refund',
                      origin='7603114Y26000010087'):
        return patch.object(
            type(self.env['fne.api.client']),
            'fetch_document_nature',
            return_value={
                'document_type': document_type,
                'origin_invoice_number_dgi': origin,
            },
        )

    def test_dry_run_writes_nothing(self):
        """Le mode par défaut ne doit RIEN écrire. C'est tout son intérêt."""
        scan, move = self._make_wrong_scan()

        with self._patch_nature():
            result = self.ScanRecord.repair_refund_documents(
                scan_ids=scan.ids)

        self.assertEqual(result['requalified'], 1)
        self.assertTrue(result['dry_run'])
        self.assertEqual(scan.document_type, 'invoice')
        self.assertEqual(scan.invoice_id, move)
        self.assertEqual(move.state, 'posted')

    def test_apply_reverses_and_recreates(self):
        """La correction laisse TROIS pièces, et c'est voulu.

        La fausse facture, son extourne, et l'avoir. Une correction comptable
        se lit dans le grand livre ; elle ne s'y efface pas.
        """
        scan, wrong_move = self._make_wrong_scan()

        with self._patch_nature():
            result = self.ScanRecord.repair_refund_documents(
                scan_ids=scan.ids, dry_run=False)

        self.assertEqual(result['requalified'], 1)
        self.assertEqual(scan.document_type, 'refund')
        self.assertTrue(scan.document_type_verified)
        self.assertEqual(scan.origin_invoice_number_dgi,
                         '7603114Y26000010087')

        # La pièce erronée est extournée, la nouvelle est un avoir.
        self.assertTrue(wrong_move.reversal_move_id)
        self.assertNotEqual(scan.invoice_id, wrong_move)
        self.assertEqual(scan.invoice_id.move_type, 'in_refund')
        self.assertEqual(scan.invoice_id.amount_total, 250000)

    def test_apply_restores_the_processed_state(self):
        """Un scan « traité » l'était pour de bonnes raisons."""
        scan, _move = self._make_wrong_scan()
        scan.action_mark_processed()
        self.assertEqual(scan.state, 'processed')

        with self._patch_nature():
            self.ScanRecord.repair_refund_documents(
                scan_ids=scan.ids, dry_run=False)

        self.assertEqual(scan.state, 'processed')

    def test_a_paid_document_is_reported_not_touched(self):
        """Un script n'a pas à défaire un règlement."""
        scan, move = self._make_wrong_scan()

        with patch.object(type(move), 'payment_state', 'paid', create=False), \
                self._patch_nature():
            result = self.ScanRecord.repair_refund_documents(
                scan_ids=scan.ids, dry_run=False)

        self.assertEqual(result['blocked'], 1)
        self.assertEqual(result['requalified'], 0)
        self.assertEqual(scan.document_type, 'invoice')

    def test_a_confirmed_invoice_is_left_alone(self):
        """La DGI dit « facture » : on ne touche à rien, on marque vérifié."""
        scan, move = self._make_wrong_scan()

        with self._patch_nature(document_type='invoice', origin=False):
            result = self.ScanRecord.repair_refund_documents(
                scan_ids=scan.ids, dry_run=False)

        self.assertEqual(result['confirmed_invoice'], 1)
        self.assertEqual(result['requalified'], 0)
        self.assertEqual(scan.document_type, 'invoice')
        self.assertTrue(scan.document_type_verified)
        self.assertEqual(scan.invoice_id, move)

    def test_candidate_selection_is_only_a_shortlist(self):
        """Le préfixe « A » présélectionne, il ne décide de rien.

        Un scan retenu par l'heuristique mais démenti par la DGI doit rester
        une facture — sans quoi l'heuristique déciderait, et l'on reproduirait
        à grande échelle l'erreur que ce correctif corrige.
        """
        scan, _move = self._make_wrong_scan()
        candidates = self.ScanRecord._select_refund_repair_candidates(
            only_suspect=True, limit=None, scan_ids=None)
        self.assertIn(scan, candidates)

        with self._patch_nature(document_type='invoice', origin=False):
            self.ScanRecord.repair_refund_documents(
                scan_ids=scan.ids, dry_run=False)
        self.assertEqual(scan.document_type, 'invoice')
