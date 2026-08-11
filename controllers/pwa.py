# -*- coding: utf-8 -*-
"""Sert la PWA « Facture Scanner » sur /facture.

Destinée aux utilisateurs sans téléphone Android (iPhone en particulier). La
PWA est servie PAR Odoo, donc à la MÊME ORIGINE que l'API : aucun problème de
CORS, et aucune adresse de serveur à configurer dans l'application.

Le build (`mobile_app/facture_scanner/build_web.sh`) dépose la sortie Flutter
dans `invoice_qr_scanner/static/pwa/`. Ce dossier est GÉNÉRÉ au déploiement et
n'est pas versionné : tant qu'il n'a pas été construit, /facture renvoie une
explication plutôt qu'une erreur 404 incompréhensible.
"""

import os

from odoo import http
from odoo.http import request

PWA_INDEX = '/invoice_qr_scanner/static/pwa/index.html'


class InvoiceScannerPWAController(http.Controller):

    @http.route(['/facture', '/facture/'], type='http', auth='public', csrf=False)
    def facture_pwa(self, **kwargs):
        """Redirige vers l'index de la PWA (fichiers servis en statique)."""
        index_path = os.path.join(
            os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
            'static', 'pwa', 'index.html',
        )
        if not os.path.exists(index_path):
            return request.make_response(
                "<h1>Application web non déployée</h1>"
                "<p>Le build de la PWA est absent de ce serveur. Exécutez "
                "<code>mobile_app/facture_scanner/build_web.sh</code> puis "
                "redéployez le module.</p>",
                headers=[('Content-Type', 'text/html; charset=utf-8')],
            )
        return request.redirect(PWA_INDEX, local=True)
