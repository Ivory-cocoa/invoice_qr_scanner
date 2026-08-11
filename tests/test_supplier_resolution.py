# -*- coding: utf-8 -*-
"""Identification du fournisseur à partir des données DGI.

Ces tests figent la correction d'un défaut qui a réellement produit des
factures imputées au mauvais tiers : l'ancienne extraction découpait la ligne
« NOM - CODE » de la page DGI et, sur une raison sociale contenant un tiret
(TERMINAL DE SAN-PEDRO, TRANS-ROULEMENTS, 3D INFOPLUS-CI), enregistrait un
« code DGI » qui n'était qu'un morceau du nom. Combiné à une recherche par nom
PARTIELLE, cela rattachait les factures au premier partenaire venu.
"""

from odoo.tests import TransactionCase, tagged


@tagged('post_install', '-at_install', 'invoice_qr_scanner', 'supplier')
class TestSupplierResolution(TransactionCase):

    @classmethod
    def setUpClass(cls):
        super().setUpClass()
        cls.ScanRecord = cls.env['invoice.scan.record']
        cls.Partner = cls.env['res.partner']

    def _make_scan(self, **values):
        vals = {
            'qr_uuid': values.pop('qr_uuid', 'uuid-%s' % len(self.ScanRecord.search([]))),
            'qr_url': 'https://www.services.fne.dgi.gouv.ci/fr/verification/x',
            'invoice_number_dgi': 'FAC-1',
            'amount_ttc': 1000,
        }
        vals.update(values)
        return self.ScanRecord.create(vals)

    # ------------------------------------------------------------------
    # Format du code DGI
    # ------------------------------------------------------------------

    def test_valid_dgi_codes(self):
        for code in ('2502298K', '1100563G', '0194420S'):
            self.assertTrue(self.ScanRecord.is_valid_dgi_code(code), code)

    def test_invalid_dgi_codes_are_fragments_of_names(self):
        """Les valeurs relevées en production : des morceaux de raison sociale."""
        for code in ('PEDRO', 'ROULEMENTS', 'CI', 'SERVICES', 'SA',
                     'FOURNITURES', '', False, '250229K', '25022988'):
            self.assertFalse(self.ScanRecord.is_valid_dgi_code(code), repr(code))

    # ------------------------------------------------------------------
    # Identification du fournisseur
    # ------------------------------------------------------------------

    def test_valid_code_identifies_the_partner(self):
        partner = self.Partner.create({
            'name': 'TRANSITAIRE EXEMPLE', 'supplier_rank': 1,
            'dgi_code': '2502298K',
        })
        scan = self._make_scan(supplier_name='PEU IMPORTE',
                               supplier_code_dgi='2502298K')
        self.assertEqual(scan._get_or_create_supplier(), partner)

    def test_invalid_code_is_never_used_to_identify(self):
        """Le cœur du défaut : le code « CI » était partagé par 3 fournisseurs.

        Les factures de CIS et de LBTP se retrouvaient sur la fiche
        « 3D INFOPLUS-CI », parce que la recherche commençait par le code.
        """
        infoplus = self.Partner.create({
            'name': '3D INFOPLUS-CI', 'supplier_rank': 1, 'dgi_code': 'CI',
        })
        scan = self._make_scan(supplier_name='CIS', supplier_code_dgi='CI')

        partner = scan._get_or_create_supplier()

        self.assertNotEqual(partner, infoplus,
                            "un code non conforme ne doit désigner personne")
        self.assertEqual(partner.name, 'CIS')

    def test_partial_name_never_matches_another_supplier(self):
        """« TRANS » a désigné « CLIENT LOCAL TRANSCAO » via un `ilike`.

        Créer un fournisseur en double est anodin et se corrige ; imputer une
        facture au mauvais tiers ne se voit pas.
        """
        transcao = self.Partner.create({
            'name': 'CLIENT LOCAL TRANSCAO', 'supplier_rank': 1,
        })
        scan = self._make_scan(supplier_name='TRANS')

        partner = scan._get_or_create_supplier()

        self.assertNotEqual(partner, transcao)
        self.assertEqual(partner.name, 'TRANS')

    def test_exact_name_still_matches_ignoring_case(self):
        partner = self.Partner.create({
            'name': 'Le Solidaire', 'supplier_rank': 1,
        })
        scan = self._make_scan(supplier_name='LE SOLIDAIRE')
        self.assertEqual(scan._get_or_create_supplier(), partner)

    def test_invalid_code_is_not_written_on_the_partner(self):
        """Un faux code recopié sur une fiche rendait l'erreur permanente."""
        partner = self.Partner.create({
            'name': 'TERMINAL DE SAN', 'supplier_rank': 1,
        })
        scan = self._make_scan(supplier_name='TERMINAL DE SAN',
                               supplier_code_dgi='PEDRO')

        self.assertEqual(scan._get_or_create_supplier(), partner)
        self.assertFalse(partner.dgi_code)

    def test_valid_code_completes_an_existing_partner(self):
        partner = self.Partner.create({
            'name': 'MAERSK COTE D IVOIRE', 'supplier_rank': 1,
        })
        scan = self._make_scan(supplier_name='MAERSK COTE D IVOIRE',
                               supplier_code_dgi='8608277H')

        scan._get_or_create_supplier()

        self.assertEqual(partner.dgi_code, '8608277H')

    def test_created_partner_never_carries_an_invalid_code(self):
        scan = self._make_scan(supplier_name='NOUVEAU FOURNISSEUR',
                               supplier_code_dgi='SERVICES')
        partner = scan._get_or_create_supplier()
        self.assertEqual(partner.name, 'NOUVEAU FOURNISSEUR')
        self.assertFalse(partner.dgi_code)


@tagged('post_install', '-at_install', 'invoice_qr_scanner', 'supplier')
class TestRepairTooling(TransactionCase):
    """Nettoyage des codes DGI non conformes déjà posés sur les partenaires."""

    def test_repair_reports_before_it_writes(self):
        partner = self.env['res.partner'].create({
            'name': 'PARTENAIRE POLLUE', 'supplier_rank': 1, 'dgi_code': 'PEDRO',
        })

        report = self.env['invoice.scan.record']._repair_partner_dgi_codes(dry_run=True)

        self.assertIn(partner.id, [row['id'] for row in report['details']])
        self.assertEqual(partner.dgi_code, 'PEDRO',
                         "une simulation ne doit RIEN écrire")

        self.env['invoice.scan.record']._repair_partner_dgi_codes(dry_run=False)
        self.assertFalse(partner.dgi_code)

    def test_repair_keeps_valid_codes(self):
        partner = self.env['res.partner'].create({
            'name': 'PARTENAIRE SAIN', 'supplier_rank': 1, 'dgi_code': '2502298K',
        })
        self.env['invoice.scan.record']._repair_partner_dgi_codes(dry_run=False)
        self.assertEqual(partner.dgi_code, '2502298K')
