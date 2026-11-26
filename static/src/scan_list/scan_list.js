/** @odoo-module **/

import { Component, useState } from "@odoo/owl";
import { registry } from "@web/core/registry";
import { standardFieldProps } from "@web/views/fields/standard_field_props";
import { ListRenderer } from "@web/views/list/list_renderer";
import { listView } from "@web/views/list/list_view";

/**
 * Liste des scans : une ligne dont la facture a été présentée plusieurs fois
 * (compteur de doublons > 0) reçoit une classe qui la met en couleur vive.
 * Les décorations natives d'Odoo ne colorent que le texte.
 */
export class InvoiceScanListRenderer extends ListRenderer {
    getRowClass(record) {
        const classNames = super.getRowClass(record);
        // Doublon : même QR-code présenté de nouveau, OU autre facture
        // enregistrée avec le même numéro.
        const duplicate =
            (record.data.duplicate_count || 0) > 0 ||
            (record.data.same_number_count || 0) > 0;
        return duplicate ? `${classNames} o_scan_row_duplicate` : classNames;
    }
}

export const invoiceScanListView = {
    ...listView,
    Renderer: InvoiceScanListRenderer,
};

registry.category("views").add("invoice_scan_list", invoiceScanListView);

/**
 * Aperçu de la facture scannée : la page publique de vérification de la DGI,
 * affichée dans un cadre isolé. Rien n'est enregistré dans Odoo : le
 * navigateur de l'utilisateur lit la page à la source.
 */
export class DgiInvoicePreview extends Component {
    static template = "invoice_qr_scanner.DgiInvoicePreview";
    static props = { ...standardFieldProps };

    setup() {
        this.state = useState({ loading: true });
    }

    /** Seule une adresse HTTPS est affichée (le serveur la reconstruit déjà). */
    get url() {
        const value = this.props.record.data[this.props.name];
        return typeof value === "string" && value.startsWith("https://") ? value : false;
    }

    onLoaded() {
        this.state.loading = false;
    }
}

registry.category("fields").add("dgi_invoice_preview", {
    component: DgiInvoicePreview,
    supportedTypes: ["char"],
});
