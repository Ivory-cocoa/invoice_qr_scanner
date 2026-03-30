#!/usr/bin/env python3
"""Daemon Playwright persistant pour le fetch DGI.

Ce script tourne en arrière-plan comme un service séparé, gardant
une instance Chromium en vie. Odoo communique avec lui via HTTP
sur un socket local (port 9222).

Avantages:
- Chromium lancé UNE SEULE FOIS (pas de crash SIGTRAP à chaque scan)
- N'hérite PAS des limites mémoire d'Odoo (RLIMIT_AS)
- Réponse rapide (pas de temps de lancement navigateur)
- Auto-restart du navigateur en cas de crash

Usage:
    python3 playwright_daemon.py              # Lancement normal
    python3 playwright_daemon.py --port 9222  # Port personnalisé
"""

import json
import logging
import os
import resource
import signal
import sys
import threading
import time
from http.server import HTTPServer, BaseHTTPRequestHandler

# Lever les limites mémoire héritées
try:
    resource.setrlimit(resource.RLIMIT_AS, (resource.RLIM_INFINITY, resource.RLIM_INFINITY))
except Exception:
    pass

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [playwright-daemon] %(levelname)s: %(message)s',
    stream=sys.stdout,
)
logger = logging.getLogger('playwright-daemon')

# Configuration
DAEMON_PORT = int(os.environ.get('PLAYWRIGHT_DAEMON_PORT', '9222'))
MAX_CONCURRENT = int(os.environ.get('PLAYWRIGHT_MAX_CONCURRENT', '3'))
PAGE_TIMEOUT = 60000  # 60s pour page.goto
POLL_INTERVAL = 2000  # 2s entre chaque vérification
MAX_POLL_ATTEMPTS = 20  # 40s max de polling
BROWSER_RESTART_DELAY = 5  # 5s avant restart

# État global
_browser = None
_playwright = None
_lock = threading.Lock()
_semaphore = threading.Semaphore(MAX_CONCURRENT)
_stats = {
    'total_requests': 0,
    'successful': 0,
    'failed': 0,
    'browser_restarts': 0,
    'start_time': None,
}


def _launch_browser():
    """Lance ou relance le navigateur Chromium."""
    global _browser, _playwright

    from playwright.sync_api import sync_playwright

    if _playwright is None:
        _playwright = sync_playwright().start()

    logger.info("Lancement de Chromium...")
    _browser = _playwright.chromium.launch(
        headless=True,
        args=[
            '--no-sandbox',
            '--disable-setuid-sandbox',
            '--disable-dev-shm-usage',
            '--disable-gpu',
            '--disable-extensions',
            '--disable-software-rasterizer',
            '--disable-features=VizDisplayCompositor',
            '--disable-background-networking',
            '--disable-default-apps',
            '--disable-sync',
            '--disable-translate',
            '--metrics-recording-only',
            '--no-first-run',
            '--single-process',
        ]
    )
    logger.info(f"Chromium lancé avec succès (PID: {_browser.contexts})")
    return _browser


def _ensure_browser():
    """S'assure que le navigateur est disponible, le relance si nécessaire."""
    global _browser
    with _lock:
        if _browser is None or not _browser.is_connected():
            try:
                if _browser:
                    try:
                        _browser.close()
                    except Exception:
                        pass
                _browser = None
                _launch_browser()
                _stats['browser_restarts'] += 1
            except Exception as e:
                logger.error(f"Échec lancement navigateur: {e}")
                raise
    return _browser


def fetch_dgi_page(url):
    """Fetch une page DGI et retourne le texte + HTML."""
    browser = _ensure_browser()

    context = None
    page = None
    try:
        context = browser.new_context(
            user_agent=(
                'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
                'AppleWebKit/537.36 (KHTML, like Gecko) '
                'Chrome/120.0.0.0 Safari/537.36'
            ),
            viewport={'width': 1920, 'height': 1080},
            locale='fr-FR',
        )
        page = context.new_page()

        logger.info(f"Chargement de: {url}")
        page.goto(url, wait_until="networkidle", timeout=PAGE_TIMEOUT)

        # Polling pour attendre les données
        text_content = ""
        data_found = False
        for attempt in range(MAX_POLL_ATTEMPTS):
            page.wait_for_timeout(POLL_INTERVAL)
            text_content = page.inner_text("body")
            upper_text = text_content.upper()
            if 'FOURNISSEUR' in upper_text or 'NUMERO DE FACTURE' in upper_text:
                logger.info(f"Données trouvées après {(attempt + 1) * 2}s")
                data_found = True
                break

        raw_html = page.content()[:5000]

        if not data_found:
            logger.warning(f"Données non trouvées après {MAX_POLL_ATTEMPTS * 2}s de polling")

        return {
            'success': True,
            'text_content': text_content,
            'raw_html': raw_html,
            'data_found': data_found,
        }

    except Exception as e:
        error_msg = str(e)
        logger.error(f"Erreur fetch DGI: {error_msg}")

        # Si le navigateur a crashé, le marquer pour restart
        if 'closed' in error_msg.lower() or 'crash' in error_msg.lower():
            global _browser
            with _lock:
                _browser = None

        return {
            'success': False,
            'error': error_msg,
        }
    finally:
        try:
            if page:
                page.close()
        except Exception:
            pass
        try:
            if context:
                context.close()
        except Exception:
            pass


class DGIHandler(BaseHTTPRequestHandler):
    """Handler HTTP pour les requêtes du module Odoo."""

    def log_message(self, format, *args):
        """Redirige les logs vers le logger."""
        logger.debug(f"HTTP: {format % args}")

    def do_GET(self):
        """Health check."""
        if self.path == '/health':
            uptime = time.time() - _stats['start_time'] if _stats['start_time'] else 0
            response = {
                'status': 'ok',
                'browser_connected': _browser is not None and _browser.is_connected() if _browser else False,
                'stats': _stats,
                'uptime_seconds': int(uptime),
            }
            self._send_json(200, response)
        else:
            self._send_json(404, {'error': 'Not found'})

    def do_POST(self):
        """Traite une requête de fetch DGI."""
        if self.path != '/fetch':
            self._send_json(404, {'error': 'Not found'})
            return

        # Lire le body
        content_length = int(self.headers.get('Content-Length', 0))
        if content_length == 0:
            self._send_json(400, {'error': 'Missing body'})
            return

        body = self.rfile.read(content_length)
        try:
            data = json.loads(body)
        except json.JSONDecodeError:
            self._send_json(400, {'error': 'Invalid JSON'})
            return

        url = data.get('url')
        if not url:
            self._send_json(400, {'error': 'Missing url'})
            return

        # Limiter les requêtes concurrentes
        if not _semaphore.acquire(timeout=30):
            self._send_json(503, {
                'success': False,
                'error': 'Trop de scans en cours. Veuillez patienter.',
            })
            return

        _stats['total_requests'] += 1
        try:
            result = fetch_dgi_page(url)
            if result.get('success'):
                _stats['successful'] += 1
            else:
                _stats['failed'] += 1
            self._send_json(200, result)
        except Exception as e:
            _stats['failed'] += 1
            self._send_json(500, {'success': False, 'error': str(e)})
        finally:
            _semaphore.release()

    def _send_json(self, status_code, data):
        """Envoie une réponse JSON."""
        body = json.dumps(data, default=str).encode('utf-8')
        self.send_response(status_code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)


class ThreadedHTTPServer(HTTPServer):
    """Serveur HTTP multi-threadé pour gérer les requêtes concurrentes."""
    allow_reuse_address = True

    def process_request(self, request, client_address):
        """Traite chaque requête dans un thread séparé."""
        thread = threading.Thread(target=self._handle_request, args=(request, client_address))
        thread.daemon = True
        thread.start()

    def _handle_request(self, request, client_address):
        try:
            self.finish_request(request, client_address)
        except Exception:
            self.handle_error(request, client_address)
        finally:
            self.shutdown_request(request)


def main():
    """Point d'entrée principal."""
    port = DAEMON_PORT

    # Gestion du signal d'arrêt
    def signal_handler(sig, frame):
        logger.info("Arrêt du daemon...")
        if _browser:
            try:
                _browser.close()
            except Exception:
                pass
        if _playwright:
            try:
                _playwright.stop()
            except Exception:
                pass
        sys.exit(0)

    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)

    # Lancer le navigateur
    try:
        _launch_browser()
    except Exception as e:
        logger.error(f"Impossible de lancer Chromium: {e}")
        logger.error("Vérifiez que Playwright est installé: pip install playwright && playwright install chromium")
        sys.exit(1)

    _stats['start_time'] = time.time()

    # Démarrer le serveur HTTP
    server = ThreadedHTTPServer(('127.0.0.1', port), DGIHandler)
    logger.info(f"Daemon Playwright démarré sur http://127.0.0.1:{port}")
    logger.info(f"  - Max concurrent: {MAX_CONCURRENT}")
    logger.info(f"  - Health check: GET /health")
    logger.info(f"  - Fetch DGI: POST /fetch {{\"url\": \"...\"}}")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        signal_handler(None, None)


if __name__ == '__main__':
    main()
