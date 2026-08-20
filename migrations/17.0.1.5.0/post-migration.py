# -*- coding: utf-8 -*-
"""Arrivée du champ « Nature du document » (facture / avoir).

Cette migration n'écrit AUCUNE nature. C'est délibéré.

La forme d'une référence (« A » + NCC) est un indice très fiable d'avoir, mais
un indice reste un indice : requalifier 4 962 scans sur une expression
régulière, c'est reproduire à plus grande échelle exactement le genre d'erreur
que ce champ existe pour corriger. Seule la plateforme DGI fait foi, et c'est
`repair_refund_documents()` qui va l'interroger, scan par scan, avant de
toucher à quoi que ce soit.

Tous les scans existants héritent donc de la valeur par défaut « Facture »,
avec « Nature confirmée » à faux — visible dans le filtre « Nature à confirmer »
du back-office. Ce journal indique combien d'entre eux méritent un examen.
"""

import logging

_logger = logging.getLogger(__name__)


def migrate(cr, version):
    if not version:
        return

    cr.execute("""
        SELECT count(*)
          FROM invoice_scan_record
         WHERE state IN ('done', 'processed')
           AND invoice_number_dgi ~ '^A[0-9]{7}[A-Z]'
    """)
    suspects = cr.fetchone()[0]

    cr.execute("SELECT count(*) FROM invoice_scan_record")
    total = cr.fetchone()[0]

    _logger.info(
        "Scanner QR — nature des documents : %s scans en base, dont %s dont la "
        "référence a la forme d'un AVOIR. Aucune requalification automatique "
        "n'a été faite. Pour la lancer, exécuter d'abord en simulation :\n"
        "    env['invoice.scan.record'].repair_refund_documents()\n"
        "puis, après lecture du rapport :\n"
        "    env['invoice.scan.record'].repair_refund_documents(dry_run=False)",
        total, suspects,
    )
