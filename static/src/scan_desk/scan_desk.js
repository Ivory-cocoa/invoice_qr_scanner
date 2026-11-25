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
const MODES_KEY = "invoice_qr_scanner.scan_desk.modes";
const MAX_LENGTH = 2000;
// Dans un champ de formulaire, une rafale de frappes plus rapide que cela,
// close par Entrée, vient de la douchette et non des doigts de l'utilisateur.
const BURST_GAP_MS = 80;
const BURST_KEY_MS = 35;
const BURST_MIN_LENGTH = 12;

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
    // Une fenêtre ouverte par-dessus le poste (assistant, confirmation) :
    // le clavier lui appartient.
    if (document.querySelector(".modal.show, .o_dialog .modal")) {
        return true;
    }
    if (!target || !target.closest) {
        return false;
    }
    return Boolean(target.closest("input, textarea, select, [contenteditable='true']"));
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
            showTest: false,
            testText: "",
            modes: this.loadModes(),
            submitting: false,
            formBlocked: false,
        });
        this.burst = null;
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
            this.state.testText = init.test_text;
            for (const kind of init.kinds) {
                const keys = (kind.modes || []).map((mode) => mode.key);
                if (keys.length && !keys.includes(this.state.modes[kind.key])) {
                    this.state.modes[kind.key] = keys[0];
                }
            }
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
        // Un formulaire attend : le scan suivant l'effacerait. Il est refusé,
        // bruyamment, tant que le formulaire n'est ni validé ni abandonné.
        if (this.state.current && this.state.current.form) {
            this.state.formBlocked = true;
            this.beep("error");
            return;
        }
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
                card = await this.orm.silent.call("invoice.scan.desk", "desk_scan", [
                    text,
                    { modes: { ...this.state.modes } },
                ]);
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
                    form: false,
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
        this.state.history.unshift(card);
        this.state.history.splice(HISTORY_SIZE);
        // Par l'état réactif : c'est LA même carte dans l'historique et à
        // l'affiche (un formulaire validé met à jour les deux).
        this.state.current = this.state.history[0];
        this.saveHistory();
        this.beep(card.status);
    }

    // ------------------------------------------------------------------
    // Mode de scan (un même QR-code, plusieurs gestes selon le profil)
    // ------------------------------------------------------------------

    loadModes() {
        try {
            const stored = JSON.parse(browser.localStorage.getItem(MODES_KEY) || "{}");
            return stored && typeof stored === "object" ? stored : {};
        } catch {
            return {};
        }
    }

    setMode(kind, mode) {
        this.state.modes[kind] = mode;
        // Rescanner le même QR-code dans un autre mode n'est pas un rebond.
        this.lastText = "";
        try {
            browser.localStorage.setItem(MODES_KEY, JSON.stringify(this.state.modes));
        } catch {
            // stockage interdit : le choix vaut pour la séance
        }
    }

    get modeChoices() {
        return this.state.kinds.filter((kind) => kind.allowed && (kind.modes || []).length > 1);
    }

    // ------------------------------------------------------------------
    // Formulaire d'une carte (ce que le QR-code ne contient pas)
    // ------------------------------------------------------------------

    /**
     * Une douchette déclenchée pendant que le curseur est dans un champ du
     * formulaire y taperait le QR-code suivant. La rafale est reconnue à sa
     * vitesse : le champ est remis en l'état et la lecture mise en file.
     */
    onFormKeydown(ev) {
        const now = performance.now();
        const el = ev.target;
        if (!this.burst || this.burst.el !== el || now - this.burst.last > BURST_GAP_MS) {
            this.burst = { el, before: el.value, text: "", start: now, last: now };
        }
        const burst = this.burst;
        burst.last = now;
        if (ev.key === "Enter") {
            const perKey = (now - burst.start) / Math.max(burst.text.length, 1);
            this.burst = null;
            if (burst.text.length >= BURST_MIN_LENGTH && perKey < BURST_KEY_MS) {
                ev.preventDefault();
                ev.stopPropagation();
                const text = burst.text;
                // Après les frappes déjà parties dans le champ
                browser.setTimeout(() => {
                    el.value = burst.before;
                    el.dispatchEvent(new Event("input", { bubbles: true }));
                    el.blur();
                });
                this.enqueue(text);
            }
            return;
        }
        if (ev.key && ev.key.length === 1) {
            burst.text += ev.key;
        }
    }

    abandonForm(card) {
        card.form = false;
        card.status = "unknown";
        card.title = _t("%s (abandonné)", card.title);
        card.message = _t("Formulaire abandonné : rien n'a été enregistré.");
        this.state.formBlocked = false;
        this.lastText = "";
        this.saveHistory();
    }

    async submitForm(card) {
        if (this.state.submitting || !card.form) {
            return;
        }
        const values = {};
        for (const field of card.form.fields) {
            const value = typeof field.value === "string" ? field.value.trim() : field.value;
            if (field.required && (value === "" || value === null || value === undefined)) {
                card.form.error = _t("À remplir : %s", field.label);
                return;
            }
            values[field.name] = value;
        }
        this.state.submitting = true;
        card.form.error = "";
        let result;
        try {
            result = await this.orm.silent.call("invoice.scan.desk", "desk_submit", [
                card.kind,
                card.form.payload,
                values,
            ]);
        } catch {
            result = {
                error: _t(
                    "Le serveur n'a pas répondu (réseau coupé ou session expirée). " +
                        "Rien n'est perdu : validez à nouveau."
                ),
            };
        }
        this.state.submitting = false;
        if (result.error || !result.card) {
            card.form.error = result.error || _t("Validation impossible, recommencez.");
            this.saveHistory();
            return;
        }
        this.state.formBlocked = false;
        this.lastText = ""; // le même QR-code peut être relu aussitôt
        // La carte du formulaire devient la carte du résultat, à la même place.
        const done = Object.assign(result.card, { time: card.time });
        const index = this.state.history.indexOf(card);
        if (index >= 0) {
            this.state.history[index] = done;
        }
        if (this.state.current === card) {
            this.state.current = done;
        }
        this.saveHistory();
        this.beep(done.status);
    }

    // ------------------------------------------------------------------
    // Test de la douchette (QR-code de contrôle affiché à l'écran)
    // ------------------------------------------------------------------

    toggleTest() {
        this.state.showTest = !this.state.showTest;
    }

    get testQrUrl() {
        const value = encodeURIComponent(this.state.testText);
        return `/report/barcode/?barcode_type=QR&value=${value}&width=260&height=260`;
    }

    // ------------------------------------------------------------------
    // Historique de la séance (conservé si l'on ouvre une fiche puis revient)
    // ------------------------------------------------------------------

    loadHistory() {
        try {
            const stored = JSON.parse(browser.sessionStorage.getItem(HISTORY_KEY) || "[]");
            if (!Array.isArray(stored)) {
                return [];
            }
            // Un formulaire resté ouvert n'est pas repris : son QR-code est
            // à rescanner (les contrôles du serveur ont pu changer).
            return stored.slice(0, HISTORY_SIZE).map((card) => ({ ...card, form: false }));
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
