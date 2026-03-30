#!/usr/bin/env python3
"""Daemon Playwright persistant pour le fetch DGI.

Architecture queue-based:
- Le thread principal gère Playwright (sync API avec greenlets)
- Le serveur HTTP tourne dans un thread séparé
- Les requêtes HTTP sont transmises au thread principal via une queue
- Ceci évite le problème "Cannot switch to a different thread" des greenlets

Avantages:
- Chromium lancé UNE SEULE FOIS (pas de crash SIGTRAP à chaque scan)
- N'hérite PAS des limites mémoire d'Odoo (RLIMIT_AS)
- Réponse rapide (pas de temps de lancement navigateur)
- Auto-restart du navigateur en cas de crash

Usage:
    python3 playwright_daemon.py              # Lancement normal
"""

import json
import logging
import os
import queue
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

# Mots-clés DGI attendus (FR + EN)
DGI_KEYWORDS = ['FOURNISSEUR', 'NUMERO DE FACTURE', 'SUPPLIER', 'INVOICE NUMBER']

# État global
_browser = None
_playwright = None
_semaphore = threading.Semaphore(MAX_CONCURRENT)
_request_queue = queue.Queue()
_stats = {
    'total_requests': 0,
    'successful': 0,
    'failed': 0,
    'browser_restarts': 0,
    'start_time': None,
}


def _normalize_dgi_url(url):
    """Convertir l'URL DGI en version française pour que les labels soient en français."""
    if '/en/verification/' in url:
        url = url.replace('/en/verification/', '/fr/verification/')
        logger.info(f"URL normalisée en français: {url}")
    return url


def _launch_browser():
    """Lance ou relance le navigateur Chromium (MUST run on main thread)."""
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
    logger.info("Chromium lancé avec succès")
    return _browser


def _ensure_browser():
    """S'assure que le navigateur est disponible (MUST run on main thread)."""
    global _browser
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
    """Fetch une page DGI et retourne le texte + HTML (MUST run on main thread)."""
    url = _normalize_dgi_url(url)
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
            if any(kw in upper_text for kw in DGI_KEYWORDS):
                logger.info(f"Données trouvées après {(attempt + 1) * 2}s")
                data_found = True
                break

        raw_html = page.content()[:5000]

        if not data_found:
            logger.warning(f"Données non trouvées après {MAX_POLL_ATTEMPTS * 2}s. "
                          f"Texte début: {text_content[:500]}")

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
    """Handler HTTP — transmet les requêtes au thread principal via queue."""

    def log_message(self, format, *args):
        logger.debug(f"HTTP: {format % args}")

    def do_GET(self):
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
        if self.path != '/fetch':
            self._send_json(404, {'error': 'Not found'})
            return

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
            # Transmettre au thread principal via queue (évite greenlet crash)
            result_event = threading.Event()
            result_holder = {}
            _request_queue.put((url, result_holder, result_event))

            # Attendre le résultat (timeout 120s)
            if not result_event.wait(timeout=120):
                _stats['failed'] += 1
                self._send_json(504, {
                    'success': False,
                    'error': 'Timeout: le traitement a pris trop de temps',
                })
                return

            result = result_holder.get('data', {'success': False, 'error': 'No result'})
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
        body = json.dumps(data, default=str).encode('utf-8')
        self.send_response(status_code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def _run_http_server(port):
    """Lancer le serveur HTTP dans un thread séparé."""
    server = HTTPServer(('127.0.0.1', port), DGIHandler)
    server.allow_reuse_address = True
    server.serve_forever()


def main():
    """Point d'entrée principal — queue-based architecture.

    Le thread principal possède le contexte greenlet de Playwright.
    Les requêtes HTTP arrivent via un thread séparé et sont relayées
    au thread principal via une queue pour exécution.
    """
    port = DAEMON_PORT

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

    # Lancer le navigateur sur le thread principal (greenlet context)
    try:
        _launch_browser()
    except Exception as e:
        logger.error(f"Impossible de lancer Chromium: {e}")
        logger.error("Vérifiez: pip install playwright && playwright install chromium")
        sys.exit(1)

    _stats['start_time'] = time.time()

    # Démarrer le serveur HTTP dans un thread séparé
    server_thread = threading.Thread(target=_run_http_server, args=(port,), daemon=True)
    server_thread.start()

    logger.info(f"Daemon Playwright démarré sur http://127.0.0.1:{port}")
    logger.info(f"  - Max concurrent: {MAX_CONCURRENT}")
    logger.info(f"  - Health check: GET /health")
    logger.info(f"  - Fetch DGI: POST /fetch {{\"url\": \"...\"}}")

    # Boucle principale: traite les requêtes Playwright sur le thread principal
    # (seul le thread principal peut utiliser le sync API / greenlets de Playwright)
    while True:
        try:
            url, result_holder, result_event = _request_queue.get(timeout=1)
            try:
                result = fetch_dgi_page(url)
                result_holder['data'] = result
            except Exception as e:
                logger.error(f"Erreur traitement requête: {e}")
                result_holder['data'] = {'success': False, 'error': str(e)}
            finally:
                result_event.set()
        except queue.Empty:
            continue
        except KeyboardInterrupt:
            signal_handler(None, None)


if __name__ == '__main__':
    main()
