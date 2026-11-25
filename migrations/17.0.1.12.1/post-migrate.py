# -*- coding: utf-8 -*-
"""Règle multi-société des scans : de « Utilisateur interne » à globale.

Le fichier de sécurité est en ``noupdate`` : la correction du XML ne touche
que les nouvelles bases. Ici, on retire le groupe de la règle sur les bases
existantes, pour que les règles « un Vérificateur ne voit que ses propres
scans » et « un Traiteur ne voit que ses traitements et les factures à
traiter » prennent enfin effet (elles étaient additionnées à une règle qui
montrait tout).
"""

import logging

from odoo import SUPERUSER_ID, api

_logger = logging.getLogger(__name__)


def migrate(cr, version):
    env = api.Environment(cr, SUPERUSER_ID, {})
    rule = env.ref('invoice_qr_scanner.rule_invoice_scan_record_company',
                   raise_if_not_found=False)
    if rule and rule.groups:
        rule.groups = [(5, 0, 0)]
        _logger.info(
            "invoice_qr_scanner : règle multi-société des scans rendue "
            "globale (cloisonnement Vérificateur / Traiteur actif)")
