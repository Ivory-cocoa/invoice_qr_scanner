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

/** Même rafale, mais le curseur est dans un champ (douchette déclenchée trop tôt). */
function typeInto(selector, text) {
    const el = document.querySelector(selector);
    for (const key of [...text, "Enter"]) {
        el.dispatchEvent(new KeyboardEvent("keydown", { key, bubbles: true, cancelable: true }));
    }
}

const FORM = ".o_scan_desk_form";

/**
 * DGI injoignable : saisie manuelle sur la carte, scan refusé tant que le
 * formulaire attend, puis mode Traiteur et test de la douchette.
 * Lancé par tests/test_scan_desk.py (profil Responsable : les deux modes).
 */
registry.category("web_tour.tours").add("invoice_scan_desk_manual_tour", {
    test: true,
    steps: () => [
        {
            content: "Le Responsable a le choix du geste, « Enregistrer » par défaut",
            trigger: ".o_scan_desk_modes[data-kind=dgi] button[data-mode=create].btn-primary",
            run: () => type(URL, "Enter"),
        },
        {
            content: "La DGI ne répond pas : la carte propose la saisie manuelle",
            trigger: `.o_scan_desk_card[data-status=error] ${FORM} input[data-field=supplier_name]`,
            run: () => typeInto(`${FORM} input[data-field=supplier_name]`, URL),
        },
        {
            content: "Scan pendant la saisie : refusé et signalé, le champ reste vide",
            trigger: ".o_scan_desk_form_blocked",
            run: () => {
                const value = document.querySelector(`${FORM} input[data-field=supplier_name]`).value;
                if (value) {
                    throw new Error("Le QR-code scanné est resté dans le champ : " + value);
                }
            },
        },
        {
            content: "Valider sans rien remplir : le champ manquant est nommé",
            trigger: ".o_scan_desk_form_submit",
            run: "click",
        },
        {
            content: "Erreur affichée, formulaire conservé",
            trigger: ".o_scan_desk_form_error:contains('Fournisseur')",
            run: () => {},
        },
        {
            content: "Fournisseur",
            trigger: `${FORM} input[data-field=supplier_name]`,
            run: "text TRANSPORT DU SUD",
        },
        {
            content: "N° de facture",
            trigger: `${FORM} input[data-field=invoice_number_dgi]`,
            run: "text 2502298K26000000777",
        },
        {
            content: "Montant",
            trigger: `${FORM} input[data-field=amount_ttc]`,
            run: "text 125 000",
        },
        {
            content: "Enregistrer la saisie manuelle",
            trigger: ".o_scan_desk_form_submit",
            run: "click",
        },
        {
            content: "Facture créée, formulaire refermé",
            trigger: ".o_scan_desk_card[data-status=success]:contains('TRANSPORT DU SUD'):not(:has(.o_scan_desk_form))",
            run: () => {},
        },
        {
            content: "Passer en mode Traiteur",
            trigger: ".o_scan_desk_modes[data-kind=dgi] button[data-mode=process]",
            run: "click",
        },
        {
            content: "Mode retenu : le même QR-code marque la facture traitée",
            trigger: ".o_scan_desk_modes button[data-mode=process].btn-primary",
            run: () => type(URL, "Enter"),
        },
        {
            content: "Facture marquée traitée",
            trigger: ".o_scan_desk_card[data-status=success]:contains('Facture marquée traitée')",
            run: () => {},
        },
        {
            content: "Ouvrir le test de la douchette",
            trigger: ".o_scan_desk_test_toggle",
            run: "click",
        },
        {
            content: "Le QR-code de contrôle s'affiche",
            trigger: ".o_scan_desk_test img[src*='barcode_type=QR']",
            run: () => type("ICP-TEST-DOUCHETTE/0123456789/azqwm/AZQWM/:.,;-_", "Enter"),
        },
        {
            content: "Verdict du test",
            trigger: ".o_scan_desk_card[data-status=success]:contains('Douchette bien réglée')",
            run: () => {},
        },
    ],
});
