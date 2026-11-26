/** @odoo-module **/

import { registry } from "@web/core/registry";

const DUPLICATE = "2603236T26000000174";
const SINGLE = "2134788Y26000000024";
const UUID = "01a1fd85-6adb-7dd8-b0ee-55c5d0732ece";

function fail(message) {
    throw new Error(message);
}

/**
 * Liste des scans : doublon en couleur vive, colonne des doublons visible
 * sans réglage, recherche par une partie du numéro, aperçu depuis la ligne.
 * Lancé par tests/test_scan_list.py.
 */
registry.category("web_tour.tours").add("invoice_scan_list_tour", {
    test: true,
    steps: () => [
        {
            content: "La colonne des doublons est affichée d'office",
            trigger: ".o_list_view th[data-name=duplicate_count]",
            run: () => {},
        },
        {
            content: "La ligne en doublon porte la couleur vive",
            trigger: `.o_data_row.o_scan_row_duplicate:contains('${DUPLICATE}')`,
            run: () => {
                const row = document.querySelector(".o_data_row.o_scan_row_duplicate");
                const plain = [...document.querySelectorAll(".o_data_row")].find(
                    (el) => el.textContent.includes(SINGLE)
                );
                if (!plain || plain.classList.contains("o_scan_row_duplicate")) {
                    fail("Une ligne sans doublon ne doit pas être colorée");
                }
                const colored = getComputedStyle(row.querySelector("td.o_data_cell"));
                const normal = getComputedStyle(plain.querySelector("td.o_data_cell"));
                // Fond réellement peint (ni transparent, ni celui des autres).
                const painted = !/^rgba\(.*,\s*0\)$|^transparent$/.test(
                    colored.backgroundColor
                );
                if (!painted || colored.backgroundColor === normal.backgroundColor) {
                    fail(
                        "La ligne en doublon n'est pas en couleur : " +
                            colored.backgroundColor
                    );
                }
            },
        },
        {
            content: "Chaque ligne a son bouton d'aperçu",
            trigger: ".o_data_row:not(.o_scan_row_duplicate) .o_scan_preview_button",
            run: () => {
                const rows = document.querySelectorAll(".o_data_row").length;
                const buttons = document.querySelectorAll(
                    ".o_data_row .o_scan_preview_button"
                ).length;
                if (rows !== 2 || buttons !== 2) {
                    fail(`Attendu 2 lignes et 2 boutons, obtenu ${rows} et ${buttons}`);
                }
            },
        },
        {
            content: "Taper la fin d'un numéro",
            trigger: ".o_searchview_input",
            run: "text 0000174",
        },
        {
            content: "La première proposition est la recherche par numéro",
            trigger: ".o_searchview_autocomplete .o_menu_item:first-child:contains('Numéro')",
            run: "click",
        },
        {
            content: "Seule la facture cherchée reste",
            // L'autre facture a disparu de la liste, celle cherchée y est.
            trigger: `.o_list_view:not(:has(.o_data_row:contains('${SINGLE}'))) .o_data_row:contains('${DUPLICATE}')`,
            extra_trigger: ".o_searchview_facet:contains('0000174')",
            run: () => {
                const rows = document.querySelectorAll(".o_data_row").length;
                if (rows !== 1) {
                    fail(`Une seule ligne attendue, ${rows} affichées`);
                }
            },
        },
        {
            content: "Ouvrir l'aperçu depuis la ligne",
            trigger: ".o_data_row .o_scan_preview_button",
            run: "click",
        },
        {
            content: "L'aperçu signale le doublon",
            trigger: ".o_scan_preview_duplicate:contains('DOUBLON')",
            run: () => {},
        },
        {
            content: "L'aperçu affiche la page de la DGI de cette facture",
            trigger: `.o_dgi_preview iframe[src='https://fne.invalid/fr/verification/${UUID}']`,
            run: () => {
                const frame = document.querySelector(".modal .o_dgi_preview iframe");
                const sandbox = frame.getAttribute("sandbox") || "";
                if (!sandbox || sandbox.includes("allow-top-navigation")) {
                    fail("Le cadre de la DGI doit rester isolé d'Odoo");
                }
                if (document.querySelector(".modal .o_form_button_save")) {
                    fail("L'aperçu ne doit rien permettre de modifier");
                }
            },
        },
        {
            content: "Fermer l'aperçu : la liste est toujours là",
            trigger: ".modal-footer button:contains('Fermer')",
            run: "click",
        },
        {
            content: "Retour à la liste filtrée",
            trigger: `body:not(.modal-open) .o_data_row:contains('${DUPLICATE}')`,
            run: () => {},
        },
    ],
});
