# -*- coding: utf-8 -*-
"""Traitement groupé des scans : ce que le lot doit garantir.

Trois promesses sont testées ici, parce que ce sont les trois façons dont une
action de masse trahit son utilisateur :

1. **Elle n'écrème pas en silence.** Toute ligne reçue figure au compte-rendu,
   traitée ou non, avec le motif.
2. **Un échec n'emporte pas le lot.** La création de pièce comptable est isolée
   par un point de sauvegarde : la facture qui passe reste acquise même si la
   suivante échoue.
3. **Le compte-rendu dit vrai.** Les compteurs de l'assistant correspondent
   aux lignes réellement écrites en base.
"""

from unittest.mock import patch

from odoo import fields
from odoo.exceptions import UserError
from odoo.tests import TransactionCase, tagged


@tagged('post_install', '-at_install', 'invoice_qr_scanner', 'bulk_process')
class TestBulkProcess(TransactionCase):

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
        cls.Wizard = cls.env['invoice.scan.bulk.process']
        cls.base_uuid = '01a0196f-7c15-7006-a5a7-8544bu1k00'

    def _make_scan(self, suffix, state='done', amount=250000, **kwargs):
        uuid = self.base_uuid + suffix
        values = {
            'qr_uuid': uuid,
            'qr_url': 'https://www.services.fne.dgi.gouv.ci/fr/verification/%s' % uuid,
            'supplier_name': 'PACKING SERVICE INTERNATIONAL',
            'supplier_code_dgi': '7603114Y',
            'invoice_number_dgi': '7603114Y2600001%s' % suffix,
            'invoice_date': fields.Date.today(),
            'amount_ttc': amount,
            'state': state,
        }
        values.update(kwargs)
        return self.ScanRecord.create(values)

    def _require_accounting(self):
        journal = self.env['account.journal'].search(
            [('type', '=', 'purchase')], limit=1)
        account = self.env['account.account'].search(
            [('account_type', '=', 'expense')], limit=1)
        self.assertTrue(journal, "Base de test sans journal d'achats")
        self.assertTrue(account, "Base de test sans compte de charge")

    def _wizard(self, scans, operation):
        return self.Wizard.create({
            'scan_ids': [(6, 0, scans.ids)],
            'operation': operation,
        })

    # ------------------------------------------------------------------
    # 1. Rien n'est écrémé en silence
    # ------------------------------------------------------------------

    def test_report_covers_every_selected_record(self):
        """Le compte-rendu a autant de lignes que la sélection.

        C'est le défaut d'origine : `filtered(state == 'done')` abandonnait le
        reste sans un mot. Sur cinquante scans dont trois éligibles,
        l'utilisateur repartait convaincu d'avoir soldé son lot.
        """
        eligible = self._make_scan('01', state='done')
        draft = self._make_scan('02', state='draft')
        already = self._make_scan('03', state='processed')
        scans = eligible + draft + already

        entries = scans._bulk_mark_processed()

        self.assertEqual(len(entries), 3)
        by_id = {e['scan_id']: e for e in entries}
        self.assertEqual(by_id[eligible.id]['status'], 'done')
        self.assertEqual(by_id[draft.id]['status'], 'skipped')
        self.assertEqual(by_id[already.id]['status'], 'skipped')
        # Le motif est explicite, pas un statut nu.
        self.assertTrue(by_id[draft.id]['message'])
        self.assertIn('Brouillon', by_id[draft.id]['message'])

    def test_mark_processed_writes_only_the_eligible_ones(self):
        eligible = self._make_scan('04', state='done')
        draft = self._make_scan('05', state='draft')

        (eligible + draft)._bulk_mark_processed()

        self.assertEqual(eligible.state, 'processed')
        self.assertEqual(eligible.processed_by, self.env.user)
        self.assertTrue(eligible.processed_date)
        self.assertEqual(draft.state, 'draft')
        self.assertFalse(draft.processed_by)

    def test_mark_processed_traces_each_scan_in_the_chatter(self):
        scans = self._make_scan('06') + self._make_scan('07')
        scans._bulk_mark_processed()
        for scan in scans:
            bodies = ' '.join(scan.message_ids.mapped('body'))
            self.assertIn('traité', bodies)

    def test_mass_action_raises_only_when_nothing_is_eligible(self):
        """L'erreur franche est réservée au lot entièrement inéligible.

        Un lot partiellement traitable doit AVANCER — et le dire — plutôt que
        de refuser en bloc.
        """
        draft = self._make_scan('08', state='draft')
        with self.assertRaises(UserError):
            draft.action_mark_processed()

        mixed = draft + self._make_scan('09', state='done')
        action = mixed.action_mark_processed()
        self.assertEqual(action['type'], 'ir.actions.client')
        self.assertEqual(action['tag'], 'display_notification')
        # Notification persistante : un lot partiel doit être lu.
        self.assertTrue(action['params']['sticky'])

    def test_mark_unprocessed_is_symmetric(self):
        processed = self._make_scan('10', state='processed')
        done = self._make_scan('11', state='done')

        entries = (processed + done)._bulk_mark_unprocessed()

        by_id = {e['scan_id']: e for e in entries}
        self.assertEqual(by_id[processed.id]['status'], 'done')
        self.assertEqual(by_id[done.id]['status'], 'skipped')
        self.assertEqual(processed.state, 'done')
        self.assertFalse(processed.processed_by)

    # ------------------------------------------------------------------
    # 2. Un échec n'emporte pas le lot
    # ------------------------------------------------------------------

    def test_one_failure_does_not_cancel_the_others(self):
        """Le point de sauvegarde par enregistrement, seule raison d'être du lot.

        Sans lui, la première exception invalide la transaction entière : les
        pièces déjà créées disparaissent avec elle et l'utilisateur ne sait
        même pas lesquelles étaient passées.
        """
        self._require_accounting()
        good = self._make_scan('12', state='error', amount=250000)
        # Montant nul : `_create_invoice` refuse — un cas d'échec réaliste,
        # produit par un QR-code mal extrait.
        bad = self._make_scan('13', state='error', amount=0)

        entries = (good + bad)._bulk_create_invoice()
        by_id = {e['scan_id']: e for e in entries}

        self.assertEqual(by_id[good.id]['status'], 'done')
        self.assertEqual(by_id[bad.id]['status'], 'error')
        self.assertTrue(good.invoice_id, "La pièce créée doit survivre à l'échec voisin")
        self.assertEqual(good.state, 'done')
        self.assertFalse(bad.invoice_id)
        self.assertEqual(bad.state, 'error')

    def test_failure_message_survives_the_rollback(self):
        """Le motif de l'échec est écrit APRÈS le retour arrière.

        Écrit à l'intérieur du point de sauvegarde, il serait annulé avec le
        reste — c'est le défaut de `action_retry_create_invoice`, dont le
        `error_message` ne survit jamais au `UserError` qui le suit.
        """
        self._require_accounting()
        bad = self._make_scan('14', state='error', amount=0)
        bad._bulk_create_invoice()
        self.assertTrue(bad.error_message)

    def test_scans_with_an_invoice_are_skipped(self):
        self._require_accounting()
        scan = self._make_scan('15', state='error', amount=250000)
        scan._bulk_create_invoice()
        first_invoice = scan.invoice_id

        entries = scan._bulk_create_invoice()
        self.assertEqual(entries[0]['status'], 'skipped')
        self.assertEqual(scan.invoice_id, first_invoice,
                         "Un second passage ne doit pas créer de doublon")

    # ------------------------------------------------------------------
    # 3. L'assistant dit vrai
    # ------------------------------------------------------------------

    def test_wizard_breaks_down_the_selection_before_acting(self):
        scans = (self._make_scan('16', state='done')
                 + self._make_scan('17', state='draft')
                 + self._make_scan('18', state='processed')
                 + self._make_scan('19', state='error'))

        wizard = self._wizard(scans, 'mark_processed')

        self.assertEqual(wizard.count_total, 4)
        self.assertEqual(wizard.count_done, 1)
        self.assertEqual(wizard.count_draft, 1)
        self.assertEqual(wizard.count_processed, 1)
        self.assertEqual(wizard.count_error, 1)
        self.assertEqual(wizard.count_eligible, 1,
                         "Seul le scan « facture créée » est concerné")
        self.assertIn('ignorés', wizard.eligibility_message)

    def test_wizard_eligibility_follows_the_operation(self):
        done = self._make_scan('20', state='done')
        error = self._make_scan('21', state='error')
        scans = done + error

        self.assertEqual(self._wizard(scans, 'mark_processed').count_eligible, 1)
        self.assertEqual(self._wizard(scans, 'create_invoice').count_eligible, 1)
        self.assertEqual(self._wizard(scans, 'verify_nature').count_eligible, 2)

    def test_wizard_reports_line_by_line(self):
        done = self._make_scan('22', state='done')
        draft = self._make_scan('23', state='draft')
        wizard = self._wizard(done + draft, 'mark_processed')

        action = wizard.action_apply()

        self.assertEqual(wizard.state, 'done')
        self.assertEqual(wizard.result_done, 1)
        self.assertEqual(wizard.result_skipped, 1)
        self.assertEqual(wizard.result_error, 0)
        self.assertEqual(len(wizard.line_ids), 2)
        self.assertEqual(
            wizard.line_ids.filtered(lambda l: l.scan_id == draft).status,
            'skipped')
        # L'assistant se rouvre sur son compte-rendu : renvoyer True le
        # fermerait, et le compte-rendu avec lui.
        self.assertEqual(action['res_model'], 'invoice.scan.bulk.process')
        self.assertEqual(action['res_id'], wizard.id)

    def test_wizard_refuses_an_empty_selection(self):
        wizard = self.Wizard.create({
            'scan_ids': [(6, 0, [])],
            'operation': 'mark_processed',
        })
        with self.assertRaises(UserError):
            wizard.action_apply()

    def test_wizard_caps_the_dgi_verification_volume(self):
        """Le garde-fou de volume protège d'un lot qui n'aboutira jamais.

        Une ligne = un appel réseau : au-delà de la borne, la requête du
        navigateur expire avant la fin et l'utilisateur ne voit aucun
        compte-rendu.
        """
        wizard = self._wizard(self._make_scan('24'), 'verify_nature')
        # On abaisse la borne plutôt que de créer 200 scans : c'est le
        # franchissement qui est testé, pas le nombre.
        with patch.object(type(self.ScanRecord), 'BULK_NETWORK_LIMIT', 0):
            with self.assertRaises(UserError):
                wizard.action_apply()
