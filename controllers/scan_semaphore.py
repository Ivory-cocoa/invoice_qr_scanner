# -*- coding: utf-8 -*-
"""
Sémaphore pour le contrôle de concurrence des scans de factures.

Limite le nombre de traitements lourds simultanés (fetch DGI, création factures)
pour éviter l'épuisement des ressources serveur (CPU, RAM, réseau) qui cause
des erreurs "Problème de serveur" côté mobile.

Fonctionne par worker Odoo (threading.Semaphore) :
- En mode multi-worker (prefork), chaque worker a son propre sémaphore
- Ex: 4 workers × 3 permits = max 12 traitements simultanés sur le serveur
"""

import threading
import logging
import time
from functools import wraps

_logger = logging.getLogger(__name__)

# ==================== CONFIGURATION ====================

# Nombre max de traitements lourds simultanés par worker
MAX_CONCURRENT_SCANS = 3

# Timeout d'attente pour acquérir le sémaphore (secondes)
# Au-delà, on retourne SERVER_BUSY au lieu de bloquer indéfiniment
SEMAPHORE_TIMEOUT = 30

# ==================== SÉMAPHORE GLOBAL ====================

_scan_semaphore = threading.Semaphore(MAX_CONCURRENT_SCANS)
_active_count_lock = threading.Lock()
_active_count = 0
_total_processed = 0
_total_rejected = 0


def get_semaphore_status():
    """Retourner l'état actuel du sémaphore pour le monitoring."""
    with _active_count_lock:
        return {
            'max_concurrent': MAX_CONCURRENT_SCANS,
            'active_scans': _active_count,
            'available_slots': MAX_CONCURRENT_SCANS - _active_count,
            'total_processed': _total_processed,
            'total_rejected': _total_rejected,
            'timeout_seconds': SEMAPHORE_TIMEOUT,
        }


def acquire_scan_slot(timeout=None):
    """Essayer d'acquérir un slot de traitement.
    
    Args:
        timeout: Temps max d'attente en secondes (défaut: SEMAPHORE_TIMEOUT)
        
    Returns:
        bool: True si le slot a été acquis, False si timeout
    """
    global _active_count, _total_rejected
    
    if timeout is None:
        timeout = SEMAPHORE_TIMEOUT
    
    acquired = _scan_semaphore.acquire(timeout=timeout)
    
    if acquired:
        with _active_count_lock:
            _active_count += 1
        _logger.debug(
            "Slot de scan acquis (actifs: %d/%d)",
            _active_count, MAX_CONCURRENT_SCANS
        )
    else:
        with _active_count_lock:
            _total_rejected += 1
        _logger.warning(
            "Sémaphore scan: timeout après %ds (actifs: %d/%d, rejetés total: %d)",
            timeout, _active_count, MAX_CONCURRENT_SCANS, _total_rejected
        )
    
    return acquired


def release_scan_slot():
    """Libérer un slot de traitement."""
    global _active_count, _total_processed
    
    _scan_semaphore.release()
    with _active_count_lock:
        _active_count = max(0, _active_count - 1)
        _total_processed += 1
    
    _logger.debug(
        "Slot de scan libéré (actifs: %d/%d)",
        _active_count, MAX_CONCURRENT_SCANS
    )


def with_scan_semaphore(timeout=None):
    """Décorateur pour protéger une fonction avec le sémaphore.
    
    Usage dans le contrôleur API:
        @with_scan_semaphore()
        def ma_fonction(self, ...):
            ...
    
    Si le sémaphore ne peut être acquis dans le timeout,
    retourne None (le code appelant doit gérer ce cas).
    """
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            if not acquire_scan_slot(timeout=timeout):
                return None  # Signal que le serveur est occupé
            try:
                return func(*args, **kwargs)
            finally:
                release_scan_slot()
        return wrapper
    return decorator
