/** @odoo-module **/

import { ErrorDialog, RPCErrorDialog } from "@web/core/errors/error_dialogs";
import { patch } from "@web/core/utils/patch";
import { browser } from "@web/core/browser/browser";

/**
 * Corrige l'erreur "Cannot read properties of undefined (reading 'writeText')"
 * qui survient quand navigator.clipboard n'est pas disponible (contexte HTTP non sécurisé).
 */
patch(ErrorDialog.prototype, {
    onClickClipboard() {
        const text = `${this.props.name}\n${this.props.message}\n${this.props.traceback}`;
        if (browser.navigator.clipboard && browser.navigator.clipboard.writeText) {
            browser.navigator.clipboard.writeText(text);
        } else {
            // Fallback pour contexte HTTP non sécurisé
            const textarea = document.createElement('textarea');
            textarea.value = text;
            textarea.style.position = 'fixed';
            textarea.style.opacity = '0';
            document.body.appendChild(textarea);
            textarea.select();
            try {
                document.execCommand('copy');
            } catch (e) {
                console.warn('Impossible de copier dans le presse-papier:', e);
            }
            document.body.removeChild(textarea);
        }
    },
});

patch(RPCErrorDialog.prototype, {
    onClickClipboard() {
        const text = `${this.props.name}\n${this.props.message}\n${this.traceback}`;
        if (browser.navigator.clipboard && browser.navigator.clipboard.writeText) {
            browser.navigator.clipboard.writeText(text);
        } else {
            // Fallback pour contexte HTTP non sécurisé
            const textarea = document.createElement('textarea');
            textarea.value = text;
            textarea.style.position = 'fixed';
            textarea.style.opacity = '0';
            document.body.appendChild(textarea);
            textarea.select();
            try {
                document.execCommand('copy');
            } catch (e) {
                console.warn('Impossible de copier dans le presse-papier:', e);
            }
            document.body.removeChild(textarea);
        }
    },
});
