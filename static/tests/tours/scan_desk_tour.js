/** @odoo-module **/

import { registry } from "@web/core/registry";

const UUID = "019bd62c-467e-7000-82ac-45c8389c7f05";
const URL = "https://www.services.fne.dgi.gouv.ci/fr/verification/" + UUID;

/** Tape `text` comme une douchette : une frappe par caractère, hors de tout champ. */
function type(text, suffix) {
    for (const key of [...text, ...(suffix ? [suffix] : [])]) {
        document.body.dispatchEvent(
            new KeyboardEvent("keydown", { key, bubbles: true, cancelable: true })
        );
    }
}

/**
 * Poste de scan à la douchette : facture créée, doublon refusé, contenu
 * inconnu, saisie au clavier, défilement de l'écran.
 * Lancé par tests/test_scan_desk.py.
 */
registry.category("web_tour.tours").add("invoice_scan_desk_tour", {
    test: true,
    steps: () => [
        {
            content: "L'écran explique ce qu'il sait lire",
            trigger: ".o_scan_desk_help:contains('Facture certifiée DGI')",
            run: () => type(URL, "Enter"),
        },
        {
            content: "Facture créée",
            trigger: ".o_scan_desk_card[data-status=success][data-kind=dgi]:contains('TRANSITAIRE EXEMPLE')",
            // Douchette sans suffixe « Entrée » : le silence clôt la lecture.
            // Texte différent du précédent (majuscules), sinon c'est un rebond.
            run: () => type(URL.toUpperCase()),
        },
        {
            content: "Deuxième lecture : doublon, rien de créé",
            trigger: ".o_scan_desk_card[data-status=duplicate]:contains('déjà été scannée')",
            run: () => type("4006381333931", "Tab"),
        },
        {
            content: "Contenu inconnu : le texte reçu est montré",
            trigger: ".o_scan_desk_card[data-status=unknown] .o_scan_desk_raw:contains('4006381333931')",
            run: () => {},
        },
        {
            content: "Une réussie, un doublon, un échec au compteur",
            trigger: ".o_scan_desk_count_success:contains('1 réussie')",
            run: () => {},
        },
        {
            content: "Trois lignes d'historique",
            trigger: ".o_scan_desk_history_row:nth-child(3)",
            run: () => {},
        },
        {
            content: "Ouvrir la saisie au clavier",
            trigger: ".o_scan_desk_manual_toggle",
            run: "click",
        },
        {
            content: "Taper dans le champ ne déclenche pas de scan parasite",
            trigger: "input.o_scan_desk_manual",
            run: "text bonjour le poste",
        },
        {
            content: "Valider",
            trigger: ".o_scan_desk_manual_submit",
            run: "click",
        },
        {
            content: "La saisie est traitée comme une lecture",
            trigger: ".o_scan_desk_card[data-status=unknown] .o_scan_desk_raw:contains('bonjour le poste')",
            run: () => {},
        },
        {
            content: "L'écran défile de lui-même (rien n'est coupé en bas)",
            trigger: ".o_scan_desk",
            run: () => {
                const desk = document.querySelector(".o_scan_desk");
                const overflow = getComputedStyle(desk).overflowY;
                if (!["auto", "scroll"].includes(overflow)) {
                    throw new Error("Le poste de scan ne défile pas : overflow-y = " + overflow);
                }
                if (desk.clientHeight > window.innerHeight) {
                    throw new Error("Le poste de scan dépasse la fenêtre");
                }
            },
        },
    ],
});
