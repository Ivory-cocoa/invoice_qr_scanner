# -*- coding: utf-8 -*-
"""Lecture de ce qu'une douchette (lecteur de codes USB ou Bluetooth) « tape ».

Une douchette n'envoie pas un texte : elle appuie sur des TOUCHES, comme un
clavier. Le poste relit ces touches selon SA disposition de clavier. Une
douchette réglée en clavier anglais (QWERTY US, le réglage d'usine) sur un
poste en clavier français (AZERTY) déforme donc tout : l'adresse

    https://www.services.fne.dgi.gouv.ci/fr/verification/019bd62c-…

arrive sous la forme

    httpsM!!zzz:services:fne:dgi:gouv:ci!fr!verificqtion!à&çbd-éc)…

La déformation est réversible caractère par caractère. Ce fichier la défait
pour le QR-code des factures certifiées par la DGI.

Garde-fou : une table n'est JAMAIS appliquée « à l'aveugle ». Un texte corrigé
n'est retenu que s'il contient à la fois le domaine de la DGI et un UUID
valide ; sinon il est rejeté. Une table fausse ne peut donc pas fabriquer une
facture : elle ne reconnaît simplement rien.

Aucune dépendance Odoo : testable seul.
"""

import re

DGI_DOMAIN = 'fne.dgi.gouv.ci'
DGI_VERIFICATION_URL = 'https://www.services.fne.dgi.gouv.ci/fr/verification/%s'

# Une lecture ne dépasse jamais quelques centaines de caractères ; au-delà,
# ce n'est pas un QR-code (collage accidentel d'un document, par exemple).
MAX_SCAN_LENGTH = 2000

_UUID = re.compile(
    r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
    re.IGNORECASE)
# Caractères de contrôle qu'une douchette ajoute en préfixe ou suffixe
# (retour chariot, tabulation, séparateurs GS/RS des codes GS1…).
_CONTROL = re.compile(r'[\x00-\x1f\x7f]')

# Douchette QWERTY US sur poste AZERTY Windows : caractère reçu → voulu.
# Même correspondance que celle du QR des connaissements
# (cocoa_bean_management/models/bill_qr.py), constatée sur un poste réel.
QWERTY_ON_AZERTY_WINDOWS = {
    '&': '1', 'é': '2', '"': '3', "'": '4', '(': '5',
    '-': '6', 'è': '7', '_': '8', 'ç': '9', 'à': '0',
    ')': '-', '°': '_', '!': '/', ';': ',', ':': '.',
    'q': 'a', 'a': 'q', 'z': 'w', 'w': 'z',
    'Q': 'A', 'A': 'Q', 'Z': 'W', 'W': 'Z',
    ',': 'm', '?': 'M', 'm': ';', 'M': ':',
}
# Même situation sur un Mac en clavier français : trois touches diffèrent
# (6 → « § », 8 → « ! », « / » → « = »). Table établie d'après la disposition
# AZERTY d'Apple ; le garde-fou décrit en tête de fichier la rend sans risque.
QWERTY_ON_AZERTY_MAC = dict(
    QWERTY_ON_AZERTY_WINDOWS, **{'§': '6', '!': '8', '=': '/'})
QWERTY_ON_AZERTY_MAC.pop('-')
QWERTY_ON_AZERTY_MAC.pop('_')

_LAYOUT_TABLES = (
    str.maketrans(QWERTY_ON_AZERTY_WINDOWS),
    str.maketrans(QWERTY_ON_AZERTY_MAC),
)

KEYBOARD_LAYOUT_WARNING = (
    "Douchette réglée en clavier anglais (QWERTY) : le contenu a été corrigé "
    "automatiquement. Réglez la douchette en clavier français (AZERTY).")


def clean_scan(raw):
    """Texte lu, débarrassé des caractères de contrôle et des espaces de bord.

    Renvoie '' pour une lecture vide ou démesurée.
    """
    text = _CONTROL.sub('', raw or '').strip()
    return text if len(text) <= MAX_SCAN_LENGTH else ''


def _dgi_uuid(text):
    """UUID d'une adresse de vérification DGI, ou None."""
    if DGI_DOMAIN not in text.lower():
        return None
    match = _UUID.search(text)
    return match.group(0).lower() if match else None


def parse_dgi_qr(raw):
    """Reconnaît le QR-code d'une facture certifiée par la DGI.

    Renvoie ``None`` si le texte n'en est pas un, sinon un dict :
    ``qr_uuid`` (minuscules), ``qr_url`` (adresse lue, corrigée au besoin) et
    ``layout_fixed`` (vrai si la douchette était en QWERTY).
    """
    text = clean_scan(raw)
    if not text:
        return None
    uuid = _dgi_uuid(text)
    if uuid:
        return {'qr_uuid': uuid, 'qr_url': text, 'layout_fixed': False}
    for table in _LAYOUT_TABLES:
        fixed = text.translate(table)
        uuid = _dgi_uuid(fixed)
        if uuid:
            return {'qr_uuid': uuid, 'qr_url': fixed, 'layout_fixed': True}
    return None
