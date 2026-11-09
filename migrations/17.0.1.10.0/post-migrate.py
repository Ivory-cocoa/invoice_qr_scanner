# -*- coding: utf-8 -*-
"""Fiches « Fournisseur DGI False » : renommées d'après leur facture.

Un scan sans nom ni code de fournisseur créait une fiche nommée
« Fournisseur DGI False » (32 en base le 2026-11-09). Ce sont autant de
fournisseurs DIFFÉRENTS : on ne les fusionne pas, on les rend
reconnaissables pour qu'on les identifie (nom réel, compte contribuable).
"""

import logging

_logger = logging.getLogger(__name__)


def migrate(cr, version):
    cr.execute("""
        SELECT p.id,
               (SELECT s.invoice_number_dgi FROM invoice_scan_record s
                 WHERE s.partner_id = p.id ORDER BY s.id LIMIT 1),
               (SELECT m.name FROM account_move m
                 WHERE m.partner_id = p.id ORDER BY m.id LIMIT 1)
          FROM res_partner p
         WHERE p.name IN ('Fournisseur DGI False', 'Fournisseur DGI None')
    """)
    rows = cr.fetchall()
    for partner_id, scan_number, move_name in rows:
        label = scan_number or move_name or '#%s' % partner_id
        cr.execute("UPDATE res_partner SET name = %s WHERE id = %s",
                   ('Fournisseur à identifier (facture %s)' % label,
                    partner_id))
    _logger.info("Fournisseurs « DGI False » renommés : %s", len(rows))
