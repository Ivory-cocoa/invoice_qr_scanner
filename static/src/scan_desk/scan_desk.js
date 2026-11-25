/** @odoo-module **/

import { browser } from "@web/core/browser/browser";
import { registry } from "@web/core/registry";
import { useService } from "@web/core/utils/hooks";
import { _t } from "@web/core/l10n/translation";
import { Component, onMounted, onWillStart, onWillUnmount, useRef, useState } from "@odoo/owl";

// Une douchette sans suffixe « Entrée » : la lecture est considérée finie
// après ce silence. Un humain ne tape pas hors d'un champ de saisie.
const IDLE_SUBMIT_MS = 400;
const MIN_IDLE_LENGTH = 8;
// La même étiquette relue par rebond dans ce délai est ignorée.
const REBOUND_MS = 3000;
const HISTORY_SIZE = 30;
const HISTORY_KEY = "invoice_qr_scanner.scan_desk.history";
const MAX_LENGTH = 2000;

const STATUS = {
    success: { css: "success", icon: "fa-check-circle", tone: [880, 1320] },
    pending: { css: "info", icon: "fa-arrow-circle-right", tone: [880, 1100] },
    duplicate: { css: "warning", icon: "fa-clone", tone: [440, 440] },
    error: { css: "danger", icon: "fa-times-circle", tone: [220, 180] },
    unknown: { css: "secondary", icon: "fa-question-circle", tone: [220, 180] },
};

/**
 * Assemble les frappes d'une douchette en lectures complètes.
 *
 * La douchette « tape » le contenu du QR-code puis, selon son réglage, Entrée
 * ou Tabulation. Sans suffixe, un silence de IDLE_SUBMIT_MS clôt la lecture.
 */
export class ScanBuffer {
    constructor(onScan) {
        this.onScan = onScan;
        this.text = "";
        this.timer = null;
    }

    /** Renvoie true si la frappe a été prise (à ne pas laisser au navigateur). */
    handleKey(ev) {
        const key = ev.key;
        if (key === "Enter" || key === "Tab") {
            if (!this.text) {
                return false;
            }
            this.flush();
            return true;
        }
        // AltGr (Ctrl+Alt sous Windows) produit des caractères ; Ctrl ou Cmd
        // seuls sont des raccourcis du navigateur.
        if ((ev.ctrlKey || ev.metaKey) && !ev.altKey) {
            return false;
        }
        if (!key || key.length !== 1) {
            return false; // Shift, touches mortes, flèches, F5…
        }
        if (this.text.length < MAX_LENGTH) {
            this.text += key;
        }
        browser.clearTimeout(this.timer);
        this.timer = browser.setTimeout(() => {
            if (this.text.length >= MIN_IDLE_LENGTH) {
                this.flush();
            } else {
                this.text = ""; // frappe isolée : pas une lecture
            }
        }, IDLE_SUBMIT_MS);
        return true;
    }

    flush() {
        browser.clearTimeout(this.timer);
        const text = this.text.trim();
        this.text = "";
        if (text) {
            this.onScan(text);
        }
    }

    destroy() {
        browser.clearTimeout(this.timer);
        this.text = "";
    }
}

/** La frappe vise-t-elle un champ où l'utilisateur écrit lui-même ? */
function isTypingTarget(target) {
    if (!target || !target.closest) {
        return false;
    }
    return Boolean(
        target.closest("input, textarea, select, [contenteditable='true'], .modal")
    );
}

/**
 * Poste de scan à la douchette. L'écran écoute le clavier de toute la page :
 * l'utilisateur n'a aucun champ à cliquer avant de scanner. Le serveur
 * (invoice.scan.desk) reconnaît le QR-code et renvoie la carte à afficher.
 */
export class InvoiceScanDesk extends Component {
    static template = "invoice_qr_scanner.ScanDesk";
    static props = { "*": true };

    setup() {
        this.orm = useService("orm");
        this.action = useService("action");
        this.manualInput = useRef("manualInput");
        this.state = useState({
            ready: false,
            kinds: [],
            canScan: false,
            focused: document.hasFocus(),
            busy: false,
            queued: 0,
            sound: true,
            current: null,
            history: this.loadHistory(),
            manual: "",
            showManual: false,
        });
        this.queue = [];
        this.lastText = "";
        this.lastTime = 0;
        this.buffer = new ScanBuffer((text) => this.enqueue(text));

        this.onKeydown = (ev) => {
            if (!this.state.canScan || isTypingTarget(ev.target)) {
                return;
            }
            if (this.buffer.handleKey(ev)) {
                ev.preventDefault();
                ev.stopPropagation();
            }
        };
        this.onFocus = () => (this.state.focused = true);
        this.onBlur = () => {
            this.state.focused = false;
            this.buffer.destroy();
        };

        onWillStart(async () => {
            const init = await this.orm.call("invoice.scan.desk", "desk_init", []);
            this.state.kinds = init.kinds;
            this.state.canScan = init.can_scan;
            this.state.ready = true;
        });
        onMounted(() => {
            // Phase de capture : avant les raccourcis clavier d'Odoo.
            window.addEventListener("keydown", this.onKeydown, true);
            window.addEventListener("focus", this.onFocus);
            window.addEventListener("blur", this.onBlur);
        });
        onWillUnmount(() => {
            window.removeEventListener("keydown", this.onKeydown, true);
            window.removeEventListener("focus", this.onFocus);
            window.removeEventListener("blur", this.onBlur);
            this.buffer.destroy();
        });
    }

    // ------------------------------------------------------------------
    // File d'attente : aucune lecture n'est perdue ni traitée en parallèle
    // ------------------------------------------------------------------

    enqueue(text) {
        const now = Date.now();
        if (text === this.lastText && now - this.lastTime < REBOUND_MS) {
            this.lastTime = now;
            return; // même étiquette relue par rebond
        }
        this.lastText = text;
        this.lastTime = now;
        this.queue.push(text);
        this.state.queued = this.queue.length;
        this.processQueue();
    }

    async processQueue() {
        if (this.state.busy) {
            return;
        }
        this.state.busy = true;
        while (this.queue.length) {
            const text = this.queue.shift();
            this.state.queued = this.queue.length;
            let card;
            try {
                card = await this.orm.silent.call("invoice.scan.desk", "desk_scan", [text]);
            } catch {
                card = {
                    kind: false,
                    kind_label: "",
                    status: "error",
                    title: _t("Serveur injoignable"),
                    message: _t(
                        "Le scan n'est pas parti (réseau coupé ou session expirée). " +
                            "Vérifiez la connexion puis scannez à nouveau."
                    ),
                    lines: [],
                    warnings: [],
                    actions: [],
                    raw: text.slice(0, 200),
                };
                // Rejouable aussitôt : ce n'est pas un rebond.
                this.lastText = "";
            }
            this.show(card);
        }
        this.state.busy = false;
    }

    show(card) {
        card.time = new Date().toLocaleTimeString("fr-FR");
        this.state.current = card;
        this.state.history.unshift(card);
        this.state.history.splice(HISTORY_SIZE);
        this.saveHistory();
        this.beep(card.status);
    }

    // ------------------------------------------------------------------
    // Historique de la séance (conservé si l'on ouvre une fiche puis revient)
    // ------------------------------------------------------------------

    loadHistory() {
        try {
            const stored = JSON.parse(browser.sessionStorage.getItem(HISTORY_KEY) || "[]");
            return Array.isArray(stored) ? stored.slice(0, HISTORY_SIZE) : [];
        } catch {
            return [];
        }
    }

    saveHistory() {
        try {
            browser.sessionStorage.setItem(HISTORY_KEY, JSON.stringify(this.state.history));
        } catch {
            // stockage plein ou interdit : l'historique reste en mémoire
        }
    }

    clearHistory() {
        this.state.history.splice(0);
        this.state.current = null;
        this.saveHistory();
    }

    get counters() {
        const count = (status) => this.state.history.filter((c) => c.status === status).length;
        return {
            success: count("success") + count("pending"),
            duplicate: count("duplicate"),
            error: count("error") + count("unknown"),
        };
    }

    // ------------------------------------------------------------------
    // Présentation
    // ------------------------------------------------------------------

    statusOf(card) {
        return STATUS[card.status] || STATUS.unknown;
    }

    beep(status) {
        if (!this.state.sound) {
            return;
        }
        try {
            const Ctx = window.AudioContext || window.webkitAudioContext;
            this.audio = this.audio || new Ctx();
            const tones = (STATUS[status] || STATUS.unknown).tone;
            tones.forEach((frequency, index) => {
                const start = this.audio.currentTime + index * 0.16;
                const oscillator = this.audio.createOscillator();
                const gain = this.audio.createGain();
                oscillator.frequency.value = frequency;
                gain.gain.setValueAtTime(0.15, start);
                gain.gain.exponentialRampToValueAtTime(0.001, start + 0.14);
                oscillator.connect(gain).connect(this.audio.destination);
                oscillator.start(start);
                oscillator.stop(start + 0.15);
            });
        } catch {
            // pas de son sur ce poste : l'écran suffit
        }
    }

    toggleSound() {
        this.state.sound = !this.state.sound;
    }

    openAction(item) {
        this.action.doAction(item.action);
    }

    // ------------------------------------------------------------------
    // Saisie au clavier (QR-code copié depuis un autre outil, essai)
    // ------------------------------------------------------------------

    toggleManual() {
        this.state.showManual = !this.state.showManual;
        if (this.state.showManual) {
            browser.setTimeout(() => this.manualInput.el && this.manualInput.el.focus());
        }
    }

    onManualKeydown(ev) {
        if (ev.key === "Enter") {
            ev.preventDefault();
            this.submitManual();
        }
    }

    submitManual() {
        const text = (this.state.manual || "").trim();
        if (!text) {
            return;
        }
        this.state.manual = "";
        this.lastText = ""; // une saisie volontaire n'est jamais un rebond
        this.enqueue(text);
        if (this.manualInput.el) {
            this.manualInput.el.blur(); // rend le clavier à la douchette
        }
    }
}

registry.category("actions").add("invoice_scan_desk", InvoiceScanDesk);
