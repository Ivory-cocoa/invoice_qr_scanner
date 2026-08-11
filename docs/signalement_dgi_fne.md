# Signalement à la DGI — exposition de données sur la plateforme FNE

> **Projet de courrier, à relire et à envoyer par ICP.** Ce document n'est pas
> envoyé automatiquement : un signalement à une administration doit partir
> d'une adresse ICP identifiée.

## Le constat

La page publique de vérification d'une facture certifiée
(`https://www.services.fne.dgi.gouv.ci/fr/verification/<uuid>`) s'appuie sur un
service REST public :

```
GET https://www.services.fne.dgi.gouv.ci/ws/invoices/qr/<uuid>
```

Ce service répond **sans aucune authentification** et renvoie, en plus des
données de la facture, la fiche complète de l'entreprise émettrice :

| Champ renvoyé | Nature |
|---|---|
| `company.apiKey` + `company.isApiKeyEnabled` | **Clé d'API de facturation du fournisseur** |
| `company.bankReference` | Coordonnées bancaires |
| `company.email`, `company.phone`, `company.address` | Coordonnées de contact |
| `company.availableFunds`, `company.availableInvoiceStickers`, `company.lastLogin` | Données de compte |
| `clientEmail`, `clientPhone` | Coordonnées du client |

Conséquence : toute personne disposant du QR-code d'une facture — donc de
n'importe quelle facture papier — peut obtenir la clé d'API de son émetteur.

**Constaté le 11 août 2026.** Vérifié sur des factures dont ICP est le client.

## Ce que nous avons fait de notre côté

- Notre intégration n'extrait que les champs nécessaires à la comptabilisation
  (fournisseur, client, numéro, date, montant, mention commerciale) : liste
  blanche explicite dans `models/fne_api.py`, couverte par un test de
  non-régression (`test_normalize_never_leaks_sensitive_supplier_data`).
- Le payload brut n'est **ni stocké ni journalisé**.
- Aucun usage n'a été fait de ces données au-delà du constat.

## Canal d'envoi

À confirmer avant envoi. Pistes, par ordre de pertinence :

1. **Assistance du compte entreprise FNE d'ICP** (canal contractuel, traçable).
2. Contact DGI habituel du service comptable d'ICP.
3. Le prestataire technique de la plateforme, s'il est connu.

---

## Projet de courrier

**Objet : Signalement d'une exposition de données sensibles sur la plateforme FNE**

Madame, Monsieur,

Dans le cadre de l'intégration de la vérification des factures certifiées FNE à
notre système de gestion, nous avons constaté que le service interrogé par la
page publique de vérification (`/ws/invoices/qr/<identifiant>`) renvoie, **sans
aucune authentification**, l'intégralité de la fiche de l'entreprise émettrice
de la facture, incluant notamment :

- sa **clé d'API** (`company.apiKey`) ainsi que son état d'activation ;
- sa **référence bancaire** (`company.bankReference`) ;
- ses coordonnées de contact et des informations de compte (solde de vignettes,
  dernières connexions).

Autrement dit, toute personne en possession du QR-code d'une facture — donc de
n'importe quelle facture papier — peut obtenir la clé d'API de son émetteur.

Nous n'avons fait aucun usage de ces données au-delà de ce constat, nous ne les
conservons pas, et notre intégration n'extrait que les champs strictement
nécessaires à la vérification (fournisseur, client, numéro, date, montant).

Nous restons à votre disposition pour tout complément, et vous remercions de
nous orienter vers le service compétent si ce n'est pas le vôtre.

Veuillez agréer, Madame, Monsieur, l'expression de nos salutations
distinguées.

*[Signataire ICP]*

---

## À demander dans le même échange

L'accès **officiel** au service de vérification (la plateforme mentionne une
documentation d'API et des clés API). L'endpoint que nous utilisons est celui du
site public : il n'est pas contractuel et peut changer sans préavis. Un accès
documenté sécuriserait notre intégration — et permettrait à la DGI de restreindre
l'endpoint public sans nous couper le service.
