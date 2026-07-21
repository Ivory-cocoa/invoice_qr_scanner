# -*- coding: utf-8 -*-
"""
Tests unitaires pour le modèle invoice.scan.record
"""

from unittest.mock import patch

from psycopg2 import IntegrityError

from odoo import fields
from odoo.tests import TransactionCase, tagged
from odoo.tools import mute_logger
from odoo.exceptions import UserError


@tagged('post_install', '-at_install', 'invoice_qr_scanner')
class TestInvoiceScanRecord(TransactionCase):
    """Tests pour le modèle InvoiceScanRecord."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        
        # Récupérer la devise XOF.
        # Odoo livre la quasi-totalité des devises INACTIVES : un `search`
        # ordinaire (active_test=True) ne les voit pas, et l'ancien code
        # enchaînait donc sur un `create` refusé par la contrainte d'unicité
        # sur `name`. La classe de tests entière échouait au setUpClass sur
        # toute base fraîche.
        Currency = cls.env['res.currency'].with_context(active_test=False)
        cls.currency_xof = Currency.search([('name', '=', 'XOF')], limit=1)
        if cls.currency_xof:
            cls.currency_xof.active = True
        else:
            cls.currency_xof = Currency.create({
                'name': 'XOF',
                'symbol': 'FCFA',
                'rounding': 1,
            })
        
        # Créer un utilisateur de test
        cls.test_user = cls.env['res.users'].create({
            'name': 'Test Scanner User',
            'login': 'test_scanner',
            'email': 'test_scanner@example.com',
            'groups_id': [(6, 0, [cls.env.ref('base.group_user').id])],
        })
        
        # Créer un partenaire de test
        cls.test_partner = cls.env['res.partner'].create({
            'name': 'Test Supplier',
            'supplier_rank': 1,
            'is_company': True,
            'dgi_code': 'TEST123K',
        })
        
        # UUID de test valide
        cls.valid_uuid = '019bd62c-467e-7000-82ac-45c8389c7f05'
        cls.valid_url = f'https://www.services.fne.dgi.gouv.ci/fr/verification/{cls.valid_uuid}'

    def test_create_scan_record(self):
        """Test de création d'un enregistrement de scan."""
        record = self.env['invoice.scan.record'].create({
            'qr_uuid': self.valid_uuid,
            'qr_url': self.valid_url,
            'scanned_by': self.test_user.id,
        })
        
        self.assertTrue(record.id)
        self.assertNotEqual(record.reference, '/')
        self.assertEqual(record.state, 'draft')
        self.assertEqual(record.qr_uuid, self.valid_uuid.lower())

    def test_uuid_normalization(self):
        """Test que l'UUID est normalisé en minuscules."""
        record = self.env['invoice.scan.record'].create({
            'qr_uuid': self.valid_uuid.upper(),
            'qr_url': self.valid_url,
        })
        
        self.assertEqual(record.qr_uuid, self.valid_uuid.lower())

    def test_extract_uuid_from_url(self):
        """Test de l'extraction de l'UUID depuis l'URL."""
        ScanRecord = self.env['invoice.scan.record']
        
        # URL valide
        uuid = ScanRecord.extract_uuid_from_url(self.valid_url)
        self.assertEqual(uuid, self.valid_uuid.lower())
        
        # URL invalide
        uuid = ScanRecord.extract_uuid_from_url('https://google.com')
        self.assertIsNone(uuid)
        
        # URL vide
        uuid = ScanRecord.extract_uuid_from_url('')
        self.assertIsNone(uuid)
        
        # URL None
        uuid = ScanRecord.extract_uuid_from_url(None)
        self.assertIsNone(uuid)

    def test_uuid_uniqueness_constraint(self):
        """La contrainte SQL d'unicité (qr_uuid, company_id) est bien active.

        On attend précisément une `IntegrityError` : `assertRaises(Exception)`
        aurait aussi accepté une faute de frappe ou une `AttributeError`, et
        le test serait passé au vert sans que la contrainte existe.

        Le savepoint isole l'échec SQL : sans lui, la transaction est rompue
        et les assertions suivantes deviennent impossibles.
        """
        self.env['invoice.scan.record'].create({
            'qr_uuid': self.valid_uuid,
            'qr_url': self.valid_url,
        })

        with self.assertRaises(IntegrityError), mute_logger('odoo.sql_db'):
            with self.env.cr.savepoint():
                self.env['invoice.scan.record'].create({
                    'qr_uuid': self.valid_uuid,
                    'qr_url': self.valid_url,
                })

        # La transaction reste exploitable grâce au savepoint.
        self.assertEqual(
            self.env['invoice.scan.record'].search_count(
                [('qr_uuid', '=', self.valid_uuid)]), 1)

    # NOTE — Tests retirés lors du tri du 2026-07-21.
    #
    # Ces tests visaient une API qui n'existe pas (ou plus) sur
    # `invoice.scan.record` : `action_cancel` / `action_set_to_draft` et l'état
    # `cancelled`, `can_retry` / `retry_count` / `max_retry`, `amount_tva`,
    # `is_recent` / `days_since_scan`, une surcharge de `copy()`, et des
    # contraintes de validation sur le format d'UUID et le domaine de l'URL.
    #
    # Ils ne signalaient donc PAS des régressions : ils décrivaient un modèle
    # qui n'a jamais été livré. Ils n'ont jamais pu s'exécuter, le `setUpClass`
    # de cette classe échouant depuis toujours (devise XOF inactive), ce qui a
    # masqué l'écart. Les rétablir supposerait d'abord de décider si ces
    # fonctionnalités sont souhaitées — c'est une décision produit, pas une
    # correction de test.

    def test_check_duplicate(self):
        """La détection de doublon ne retient que les scans aboutis."""
        ScanRecord = self.env['invoice.scan.record']

        # Pas de doublon initialement
        self.assertFalse(ScanRecord.check_duplicate(self.valid_uuid))

        # Un scan en brouillon n'est PAS un doublon : seuls comptent les scans
        # ayant abouti à une facture (done/processed).
        record = ScanRecord.create({
            'qr_uuid': self.valid_uuid,
            'qr_url': self.valid_url,
        })
        self.assertFalse(ScanRecord.check_duplicate(self.valid_uuid),
                         "Un scan en brouillon ne doit pas bloquer un rescan")

        record.state = 'done'
        self.assertEqual(ScanRecord.check_duplicate(self.valid_uuid).id,
                         record.id)

    def test_check_duplicate_is_case_insensitive(self):
        """Un même QR en casse différente doit être vu comme un doublon.

        Régression protégée : la contrainte SQL et les recherches `=` sont
        sensibles à la casse. Sans normalisation, un client envoyant un
        `qr_uuid` en majuscules créait une SECONDE facture fournisseur pour
        la même facture DGI.
        """
        ScanRecord = self.env['invoice.scan.record']
        record = ScanRecord.create({
            'qr_uuid': self.valid_uuid,
            'qr_url': self.valid_url,
            'state': 'done',
        })

        found = ScanRecord.check_duplicate(self.valid_uuid.upper())
        self.assertEqual(found.id, record.id,
                         "La recherche de doublon doit ignorer la casse")

    def test_qr_uuid_normalized_on_write(self):
        """L'écriture normalise aussi, pas seulement la création."""
        record = self.env['invoice.scan.record'].create({
            'qr_uuid': self.valid_uuid,
            'qr_url': self.valid_url,
        })

        other = '019BD62C-467E-7000-82AC-000000000003'
        record.write({'qr_uuid': other})
        self.assertEqual(record.qr_uuid, other.lower())

    def test_action_view_invoice_no_invoice(self):
        """Test que voir facture sans facture lève une erreur."""
        record = self.env['invoice.scan.record'].create({
            'qr_uuid': self.valid_uuid,
            'qr_url': self.valid_url,
        })
        
        with self.assertRaises(UserError):
            record.action_view_invoice()

    def test_get_or_create_supplier_by_dgi_code(self):
        """Test de recherche fournisseur par code DGI."""
        record = self.env['invoice.scan.record'].create({
            'qr_uuid': self.valid_uuid,
            'qr_url': self.valid_url,
            'supplier_name': 'Another Name',
            'supplier_code_dgi': 'TEST123K',  # Code DGI du partenaire existant
        })
        
        partner = record._get_or_create_supplier()
        
        # Doit trouver le partenaire existant
        self.assertEqual(partner.id, self.test_partner.id)

    def test_get_or_create_supplier_creates_new(self):
        """Un fournisseur inconnu est bien CRÉÉ, et non simplement retrouvé.

        Les assertions sur les champs ne suffisaient pas à le prouver : la
        recherche par nom (`ilike`) peut renvoyer un partenaire préexistant,
        auquel `_get_or_create_supplier` écrit ensuite le `dgi_code` — toutes
        les égalités étaient donc satisfaites sans qu'aucune création n'ait
        lieu. On compare l'ensemble des partenaires avant et après.
        """
        Partner = self.env['res.partner']
        before = set(Partner.search([]).ids)

        record = self.env['invoice.scan.record'].create({
            'qr_uuid': self.valid_uuid,
            'qr_url': self.valid_url,
            'supplier_name': 'New Supplier XYZ',
            'supplier_code_dgi': 'NEWCODE999',
        })

        partner = record._get_or_create_supplier()

        self.assertNotIn(partner.id, before,
                         "Le fournisseur aurait dû être créé, pas réutilisé")
        self.assertEqual(partner.name, 'New Supplier XYZ')
        self.assertEqual(partner.dgi_code, 'NEWCODE999')
        self.assertEqual(partner.supplier_rank, 1)

    def _make_scan(self, state='done', uuid=None):
        """Créer un scan dans l'état demandé."""
        return self.env['invoice.scan.record'].create({
            'qr_uuid': uuid or self.valid_uuid,
            'qr_url': self.valid_url,
            'state': state,
        })

    def _make_posted_invoice(self):
        """Créer et comptabiliser une facture fournisseur de test.

        Volontairement SANS try/except : si la comptabilité de la base de test
        est inutilisable, ce test doit ÉCHOUER bruyamment. L'ancienne version
        enveloppait tout dans un `except Exception: skipTest`, ce qui
        transformait n'importe quel échec — y compris celui de l'assertion —
        en test ignoré.
        """
        journal = self.env['account.journal'].search(
            [('type', '=', 'purchase')], limit=1)
        account = self.env['account.account'].search(
            [('account_type', '=', 'expense')], limit=1)
        self.assertTrue(journal, "Base de test sans journal d'achats")
        self.assertTrue(account, "Base de test sans compte de charge")

        invoice = self.env['account.move'].create({
            'move_type': 'in_invoice',
            'partner_id': self.test_partner.id,
            'journal_id': journal.id,
            'invoice_date': fields.Date.today(),
            'invoice_line_ids': [(0, 0, {
                'name': 'Ligne de test',
                'quantity': 1,
                'price_unit': 1000,
                'account_id': account.id,
            })],
        })
        invoice.action_post()
        self.assertEqual(invoice.state, 'posted')
        return invoice

    def test_cannot_delete_scan_with_posted_invoice(self):
        """Un scan justifiant une facture COMPTABILISÉE ne peut être supprimé.

        Axe distinct de l'état « traité » : le scan ci-dessous est en `done`,
        donc non protégé à ce titre — c'est bien la facture comptabilisée qui
        déclenche le refus.
        """
        invoice = self._make_posted_invoice()
        record = self.env['invoice.scan.record'].create({
            'qr_uuid': self.valid_uuid,
            'qr_url': self.valid_url,
            'invoice_id': invoice.id,
            'state': 'done',
        })

        with self.assertRaises(UserError):
            record.unlink()

        self.assertTrue(record.exists())

    def test_can_delete_scan_with_draft_invoice(self):
        """Une facture en BROUILLON n'a pas d'existence comptable : suppression permise."""
        journal = self.env['account.journal'].search(
            [('type', '=', 'purchase')], limit=1)
        # Sur recordset vide, `journal.id` vaut False et la facture serait
        # créée sur un journal arbitraire : asserter comme le fait
        # `_make_posted_invoice`.
        self.assertTrue(journal, "Base de test sans journal d'achats")

        invoice = self.env['account.move'].create({
            'move_type': 'in_invoice',
            'partner_id': self.test_partner.id,
            'journal_id': journal.id,
        })
        self.assertEqual(invoice.state, 'draft')

        record = self.env['invoice.scan.record'].create({
            'qr_uuid': self.valid_uuid,
            'qr_url': self.valid_url,
            'invoice_id': invoice.id,
            'state': 'done',
        })

        record.unlink()
        self.assertFalse(record.exists())

    def test_copy_not_allowed(self):
        """La duplication est refusée par un message clair, pas une IntegrityError.

        L'unicité SQL refusait déjà la copie, mais sous forme d'erreur brute
        qui invalidait la transaction. On vérifie donc le type d'exception,
        et non seulement le fait qu'elle échoue.
        """
        record = self.env['invoice.scan.record'].create({
            'qr_uuid': self.valid_uuid,
            'qr_url': self.valid_url,
        })

        with self.assertRaises(UserError):
            record.copy()

        # La transaction reste utilisable : une IntegrityError l'aurait rompue.
        self.assertEqual(
            self.env['invoice.scan.record'].search_count(
                [('qr_uuid', '=', self.valid_uuid)]), 1)

    def test_cannot_delete_processed_scan(self):
        """Un scan traité est une pièce justificative : suppression refusée."""
        record = self._make_scan(state='processed')

        with self.assertRaises(UserError):
            record.unlink()

        self.assertTrue(record.exists(), "Le scan traité doit subsister")

    def test_can_delete_non_processed_scan(self):
        """La protection ne vise QUE les scans traités.

        Un scan en brouillon, en erreur ou simplement « facture créée » reste
        supprimable : bloquer tout empêcherait de nettoyer les scans ratés.
        """
        for state in ('draft', 'error', 'done'):
            record = self._make_scan(state=state)
            record.unlink()
            self.assertFalse(record.exists(),
                             "Un scan '%s' doit rester supprimable" % state)

    def test_unmark_then_delete_is_allowed(self):
        """L'échappatoire documentée : retirer l'état « Traité » puis supprimer.

        La protection n'est pas un mur définitif — elle impose un geste
        explicite, tracé dans le chatter par `action_mark_unprocessed`.
        """
        record = self._make_scan(state='processed')

        record.action_mark_unprocessed()
        self.assertEqual(record.state, 'done')

        record.unlink()
        self.assertFalse(record.exists())

    def test_batch_delete_blocked_by_single_processed_scan(self):
        """Un lot contenant UN scan traité est refusé en entier.

        Point important : la suppression est atomique. Sans cela, une
        suppression de masse depuis la vue liste effacerait les scans
        supprimables et échouerait ensuite, laissant un état partiel.
        """
        deletable = self._make_scan(state='done')
        protected = self._make_scan(
            state='processed', uuid='019bd62c-467e-7000-82ac-000000000002')

        with self.assertRaises(UserError):
            (deletable | protected).unlink()

        self.assertTrue(deletable.exists(),
                        "Aucun scan du lot ne doit avoir été supprimé")
        self.assertTrue(protected.exists())


@tagged('post_install', '-at_install', 'invoice_qr_scanner')
class TestDashboardData(TransactionCase):
    """Tests pour les données du tableau de bord."""

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        
        # Cf. TestInvoiceScanRecord.setUpClass : les devises Odoo sont
        # livrées inactives, il faut donc désactiver `active_test`.
        Currency = cls.env['res.currency'].with_context(active_test=False)
        cls.currency_xof = Currency.search([('name', '=', 'XOF')], limit=1)
        if cls.currency_xof:
            cls.currency_xof.active = True
        else:
            cls.currency_xof = Currency.create({
                'name': 'XOF', 'symbol': 'FCFA', 'rounding': 1,
            })

    def test_get_dashboard_data_empty(self):
        """Dashboard sans données : zéros LÉGITIMES, pas un repli d'erreur.

        `assertFalse(data['error'])` est ici l'assertion essentielle : le
        `except` de `get_dashboard_data` renvoie une structure de même forme,
        avec les mêmes clés et les mêmes zéros. Sans ce contrôle, ce test
        passait au vert alors que la méthode plantait intégralement — ce qui
        s'est effectivement produit pendant longtemps.
        """
        data = self.env['invoice.scan.record'].get_dashboard_data()

        self.assertFalse(data['error'], "Le calcul ne doit pas être en échec")
        self.assertIn('stats', data)
        self.assertIn('recent_scans', data)
        self.assertIn('chart_data', data)
        self.assertEqual(data['stats']['totalScans'], 0)

    def test_get_dashboard_data_reports_failure(self):
        """Un calcul en échec est SIGNALÉ, il ne se déguise pas en zéros.

        On force l'exception pour vérifier le repli lui-même, plutôt que de
        laisser trois autres tests le valider par accident.
        """
        ScanRecord = self.env['invoice.scan.record']

        with patch.object(type(ScanRecord), 'search_count',
                          side_effect=RuntimeError('panne simulée')):
            data = ScanRecord.get_dashboard_data('week')

        self.assertTrue(data['error'],
                        "Le repli doit être explicitement signalé au client")
        self.assertEqual(data['stats']['totalScans'], 0)
        self.assertEqual(data['period'], 'week')

    def test_get_dashboard_data_with_records(self):
        """Test du dashboard avec des enregistrements."""
        # Créer quelques enregistrements
        for i in range(5):
            self.env['invoice.scan.record'].create({
                'qr_uuid': f'019bd62c-467e-7000-82ac-45c8389c7f{i:02d}',
                'qr_url': f'https://www.services.fne.dgi.gouv.ci/fr/verification/019bd62c-467e-7000-82ac-45c8389c7f{i:02d}',
                'state': 'done' if i < 3 else 'error',
                'amount_ttc': 10000 * (i + 1),
            })
        
        data = self.env['invoice.scan.record'].get_dashboard_data()

        self.assertFalse(data['error'])
        self.assertEqual(data['stats']['totalScans'], 5)
        self.assertEqual(data['stats']['successfulScans'], 3)
        self.assertEqual(data['stats']['errorScans'], 2)
        self.assertGreater(len(data['recent_scans']), 0)

    def test_get_dashboard_data_periods(self):
        """Chaque période est acceptée et renvoyée telle quelle.

        `assertFalse(data['error'])` est indispensable : le repli d'erreur
        renvoie l'argument `period` reçu, donc l'égalité sur `period` seule
        était satisfaite même quand la méthode plantait de bout en bout.
        """
        for period in ['day', 'week', 'month', 'year']:
            data = self.env['invoice.scan.record'].get_dashboard_data(period)
            self.assertFalse(data['error'],
                             "Période '%s' : calcul en échec" % period)
            self.assertEqual(data['period'], period)

    def test_get_dashboard_data_invalid_period(self):
        """Une période invalide retombe sur 'month', et le fait savoir.

        L'ancien test se contentait de `assertIn('stats', data)` — vrai dans
        les deux branches, et muet sur la normalisation qu'il prétendait
        vérifier.
        """
        data = self.env['invoice.scan.record'].get_dashboard_data('invalid')

        self.assertFalse(data['error'])
        self.assertEqual(data['period'], 'month',
                         "Une période invalide doit être ramenée à 'month'")
