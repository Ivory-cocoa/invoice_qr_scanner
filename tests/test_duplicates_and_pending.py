# -*- coding: utf-8 -*-
"""Doublons de numéro de facture, et factures à vérifier par le secrétariat."""

from lxml import etree

from odoo import fields
from odoo.exceptions import AccessError, UserError
from odoo.tests import TransactionCase, new_test_user, tagged

from .test_scan_desk import ensure_xof

BASE = '01a1fd85-6adb-7dd8-b0ee-55c5d07%05d'


def make_scan(env, index, number, **kwargs):
    uuid = BASE % index
    values = {
        'qr_uuid': uuid,
        'qr_url': 'https://www.services.fne.dgi.gouv.ci/fr/verification/' + uuid,
        'supplier_name': 'QUINCAILLERIE EXEMPLE',
        'supplier_code_dgi': '2603236T',
        'invoice_number_dgi': number,
        'invoice_date': fields.Date.today(),
        'amount_ttc': 100000,
        'state': 'done',
    }
    values.update(kwargs)
    return env['invoice.scan.record'].create(values)


@tagged('post_install', '-at_install', 'invoice_qr_scanner')
class TestSameInvoiceNumber(TransactionCase):
    """Deux scans différents, un même numéro de facture, un même fournisseur."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        ensure_xof(cls.env)
        cls.Scan = cls.env['invoice.scan.record']
        cls.first = make_scan(cls.env, 1, '2603236T26000000174')
        cls.twin = make_scan(cls.env, 2, '2603236T26000000174')
        cls.alone = make_scan(cls.env, 3, '2603236T26000000175')

    def _refresh(self, records):
        records.invalidate_recordset(['same_number_count', 'same_number_refs'])

    def test_both_scans_are_flagged(self):
        self.assertEqual(self.first.same_number_count, 1)
        self.assertEqual(self.twin.same_number_count, 1)
        self.assertEqual(self.first.same_number_refs, self.twin.reference)
        self.assertEqual(self.alone.same_number_count, 0)
        self.assertFalse(self.alone.same_number_refs)

    def test_number_written_differently(self):
        other = make_scan(self.env, 4, ' 2603236t-26 000000175 ')
        self._refresh(self.alone)
        self.assertEqual(self.alone.same_number_count, 1)
        self.assertEqual(other.same_number_count, 1)

    def test_same_number_at_another_supplier_is_not_a_duplicate(self):
        a = make_scan(self.env, 5, '935', supplier_code_dgi='1111111A',
                      supplier_name='FOURNISSEUR A')
        b = make_scan(self.env, 6, '935', supplier_code_dgi='2222222B',
                      supplier_name='FOURNISSEUR B')
        self.assertEqual(a.same_number_count, 0)
        self.assertEqual(b.same_number_count, 0)

    def test_supplier_without_code_is_compared_by_name(self):
        a = make_scan(self.env, 7, '936', supplier_code_dgi=False,
                      supplier_name='Chimtec S.A')
        b = make_scan(self.env, 8, '936', supplier_code_dgi='3333333C',
                      supplier_name='CHIMTEC SA')
        c = make_scan(self.env, 9, '936', supplier_code_dgi=False,
                      supplier_name='AUTRE MAISON')
        self.assertEqual(a.same_number_count, 1)
        self.assertEqual(b.same_number_count, 1)
        self.assertEqual(c.same_number_count, 0)

    def test_only_recorded_invoices_count_as_the_other_one(self):
        """Un scan en erreur ne fait pas de l'autre un doublon, mais il est
        lui-même signalé : c'est lui qu'il ne faut pas reprendre."""
        failed = make_scan(self.env, 10, '2603236T26000000175', state='error')
        self._refresh(self.alone)
        self.assertEqual(self.alone.same_number_count, 0)
        self.assertEqual(failed.same_number_count, 1)

    def test_empty_number_is_never_a_duplicate(self):
        a = make_scan(self.env, 11, False)
        b = make_scan(self.env, 12, '')
        self.assertEqual(a.same_number_count, 0)
        self.assertEqual(b.same_number_count, 0)

    def test_filter(self):
        ours = self.first | self.twin | self.alone
        found = self.Scan.search(
            [('same_number_count', '>', 0), ('id', 'in', ours.ids)])
        self.assertEqual(found, self.first | self.twin)
        found = self.Scan.search(
            [('same_number_count', '=', 0), ('id', 'in', ours.ids)])
        self.assertEqual(found, self.alone)
        with self.assertRaises(UserError):
            self.Scan.search([('same_number_count', '>', 3)])

    def test_duplicates_filter_covers_both_kinds(self):
        self.alone.duplicate_count = 2
        ours = self.first | self.twin | self.alone
        found = self.Scan.search([
            '|', ('duplicate_count', '>', 0), ('same_number_count', '>', 0),
            ('id', 'in', ours.ids)])
        self.assertEqual(found, ours)

    def test_a_verifier_sees_the_duplicate_made_by_someone_else(self):
        """Le double créé par un collègue est celui qu'il faut voir, même si
        son scan reste hors de portée."""
        user = new_test_user(
            self.env, login='verif_twin', groups='base.group_user,'
            'invoice_qr_scanner.group_invoice_scanner_verificateur')
        self.first.scanned_by = user
        mine = self.Scan.with_user(user).search(
            [('invoice_number_dgi', '=', '2603236T26000000174')])
        self.assertEqual(mine, self.first)
        self.assertEqual(mine.same_number_count, 1)
        self.assertEqual(mine.same_number_refs, self.twin.reference)
        with self.assertRaises(AccessError):
            self.twin.with_user(user).read(['supplier_name'])

    def test_warning_text(self):
        warning = self.twin._same_number_warning()
        self.assertIn('même numéro', warning)
        self.assertIn('2603236T26000000174', warning)
        self.assertIn(self.first.reference, warning)
        self.assertIn('comptabilité', warning)
        self.assertFalse(self.alone._same_number_warning())

    def test_warning_is_logged_when_the_invoice_is_recorded(self):
        late = make_scan(self.env, 20, '2603236T26000000175', state='draft')
        self.assertFalse(late.message_ids.filtered(
            lambda m: 'même numéro' in (m.body or '')))
        late.state = 'done'
        notes = late.message_ids.filtered(
            lambda m: 'même numéro' in (m.body or ''))
        self.assertEqual(len(notes), 1)
        self.assertIn(self.alone.reference, notes.body)
        # Rien dans le fil d'une facture sans double.
        single = make_scan(self.env, 21, '2603236T26000000999', state='draft')
        single.state = 'done'
        self.assertFalse(single.message_ids.filtered(
            lambda m: 'même numéro' in (m.body or '')))

    def test_list_view(self):
        tree = etree.fromstring(self.Scan.get_view(False, 'tree')['arch'])
        for name in ('same_number_count', 'duplicate_count', 'invoice_number_dgi'):
            column = tree.xpath("//field[@name='%s']" % name)
            self.assertEqual(len(column), 1, name)
            self.assertFalse(column[0].get('optional'), name)

    def test_all_scans_open_on_the_whole_history(self):
        """Un numéro tapé dans la recherche est cherché partout : plus de
        filtre « Aujourd'hui » posé d'office."""
        action = self.env.ref('invoice_qr_scanner.action_invoice_scan_record')
        self.assertNotIn('search_default', action.context or '')


@tagged('post_install', '-at_install', 'invoice_qr_scanner')
class TestPendingInvoice(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        ensure_xof(cls.env)
        cls.Pending = cls.env['invoice.scan.pending.invoice']
        cls.ot_manager = new_test_user(
            cls.env, login='pending_ot', groups='base.group_user,'
            'invoice_qr_scanner.group_invoice_scanner_ot_manager')
        cls.secretary = new_test_user(
            cls.env, login='pending_secretary', groups='base.group_user,'
            'invoice_qr_scanner.group_invoice_scanner_verificateur,'
            'invoice_qr_scanner.group_invoice_scanner_traiteur')
        cls.uuid = BASE % 50

    def _pending(self):
        return self.Pending.search([('qr_uuid', '=', self.uuid)])

    def test_register_once(self):
        self.assertTrue(self.Pending._register_request(self.ot_manager, self.uuid.upper()))
        self.assertTrue(self.Pending._register_request(self.ot_manager, self.uuid))
        pending = self._pending()
        self.assertEqual(len(pending), 1)
        self.assertEqual(pending.request_count, 2)
        self.assertEqual(pending.state, 'pending')
        self.assertIn(self.uuid, pending.dgi_preview_url)

    def test_invalid_identifier_is_ignored(self):
        for value in ('', None, 'pas-un-uuid', self.uuid + '/x'):
            self.assertFalse(self.Pending._register_request(self.ot_manager, value))
        self.assertFalse(self.Pending.search([('requested_by', '=', self.ot_manager.id)]))

    def test_secretariat_is_told_once(self):
        sent = []
        Bus = type(self.env['bus.bus'])
        original = Bus._sendmany

        def _capture(self_bus, notifications):
            sent.extend(notifications)
            return original(self_bus, notifications)

        from unittest.mock import patch
        with patch.object(Bus, '_sendmany', _capture):
            self.Pending._register_request(self.ot_manager, self.uuid)
            first = len(sent)
            self.Pending._register_request(self.ot_manager, self.uuid)
        self.assertTrue(first)
        self.assertEqual(len(sent), first)
        partners = [target for target, _type, _payload in sent]
        self.assertIn(self.secretary.partner_id, partners)
        self.assertNotIn(self.ot_manager.partner_id, partners)

    def test_verification_closes_the_request(self):
        self.Pending._register_request(self.ot_manager, self.uuid)
        scan = make_scan(self.env, 50, '2603236T26000000900', state='draft')
        self.assertEqual(self._pending().state, 'pending')
        scan.state = 'done'
        pending = self._pending()
        self.assertEqual(pending.state, 'done')
        self.assertEqual(pending.scan_record_id, scan)
        self.assertTrue(pending.verified_date)

    def test_scan_created_directly_done_closes_the_request(self):
        self.Pending._register_request(self.ot_manager, self.uuid)
        scan = make_scan(self.env, 50, '2603236T26000000900')
        self.assertEqual(self._pending().scan_record_id, scan)

    def test_scan_in_error_keeps_the_request_open(self):
        self.Pending._register_request(self.ot_manager, self.uuid)
        make_scan(self.env, 50, '2603236T26000000900', state='error')
        self.assertEqual(self._pending().state, 'pending')

    def test_cancel_and_ask_again(self):
        self.Pending._register_request(self.ot_manager, self.uuid)
        pending = self._pending()
        pending.with_user(self.secretary).action_cancel()
        self.assertEqual(pending.state, 'cancelled')
        self.Pending._register_request(self.ot_manager, self.uuid)
        self.assertEqual(pending.state, 'pending')
        self.assertEqual(len(self._pending()), 1)

    def test_access(self):
        self.Pending._register_request(self.ot_manager, self.uuid)
        self.assertEqual(
            self.Pending.with_user(self.secretary).search_count(
                [('qr_uuid', '=', self.uuid)]), 1)
        with self.assertRaises(AccessError):
            self.Pending.with_user(self.ot_manager).search([])
        with self.assertRaises(AccessError):
            self.Pending.with_user(self.secretary).create({'qr_uuid': BASE % 51})
        menu = self.env.ref('invoice_qr_scanner.menu_invoice_scan_pending_invoice')
        Menu = self.env['ir.ui.menu']
        self.assertIn(menu.id, Menu.with_user(self.secretary)._visible_menu_ids())
        self.assertNotIn(menu.id, Menu.with_user(self.ot_manager)._visible_menu_ids())
