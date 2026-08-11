# Rapport de réparation des données DGI

Simulation exécutée le **11 août 2026** sur `icp_dev_db` (copie restaurée de la
production). **Aucune écriture** n'a été faite. Les chiffres sont à recompter en
production avant toute correction.

```python
env['invoice.scan.record'].repair_dgi_data(dry_run=True, only_invalid_code=True)
```

## Résultat

| | |
|---|---|
| Scans examinés (code DGI non conforme) | **464** |
| Scans corrigeables depuis la source DGI | **463** |
| Scans illisibles côté DGI | 1 |
| Fiches partenaires portant un faux code DGI | **14** |
| Factures comptabilisées sur **un autre tiers** | **50** |
| Simples écarts de libellé (même tiers) | 98 |

## Exemples de corrections de scans

| Enregistré | Réel (source DGI) |
|---|---|
| `3D INFOPLUS` / code `CI` | `3D INFOPLUS-CI` / `2404734J` |
| `TRANS` / code `ROULEMENTS` | `TRANS-ROULEMENTS C.I.` / `8203192F` |
| `PRESTATION MULTI` / code `SERVICE` | `PRESTATION MULTI-SERVICE INTERNATIONALE` / `2404564F` |
| `2M` / code `TEC` | `2M-TEC` / `2506110Z` |

## Fiches partenaires à nettoyer (code DGI non conforme)

`2M-TEC → TEC`, `3D INFOPLUS-CI → CI`, `AJUSTAGE MECANIQUE INDUSTRIELLE A.M.I →
FOURNITURES`, `CLIENT LOCAL TRANSCAO → ROULEMENTS`, `COMPAGNIE MARITIME
D'AFFRETEMENT → COMPAGNIE`, `DANOTH MULTI → SERVICES`, `KTD SA → SA`,
`NOUVELLE MICI EMBACI → EMBACI`, `PRESTATION MULTI → SERVICE`, `SOCIDA →
SOCIETE`, `SONOCO → SON`, `SPD → SAN`, `TERMINAL DE SAN PEDRO → PEDRO`,
`YOBO GBALLOU ROLAND → BERTRAND`.

Le nettoyage se contente d'**effacer** ces codes : l'identification retombe
alors sur le nom exact, et le bon NCC sera réécrit au prochain scan.

## Factures sur un autre tiers — décision comptable

**50 factures, toutes comptabilisées.** Elles se regroupent en cinq situations,
d'inégale gravité — c'est à la comptabilité de trancher, le module ne réimpute
rien tout seul.

| Tiers actuel | Fournisseur réel | Nb | Lecture |
|---|---|---|---|
| CLIENT LOCAL TRANSCAO | TRANS-ROULEMENTS C.I. (`8203192F`) | ~28 | **Erreur probable** : deux entités sans rapport, rapprochées par une recherche de nom partielle sur « TRANS » |
| SOCIDA | SOCIETE IVOIRIENNE DE DISTRIBUTION AUTOMOBILE… (`7502352H`) | ~13 | Vraisemblablement **la même entreprise** sous son nom commercial — à confirmer |
| 3D INFOPLUS-CI | CIS-CI (`9614240W`) | 4 | **Erreur certaine** : le faux code `CI` était partagé |
| 3D INFOPLUS-CI | LBTP-CI (`9402979L`) | 1 | **Erreur certaine**, même cause |
| ALTERNATIVE ENERGY INTERNATIONAL | INTER-GROUPE SERVICE (`1313469A`) | 2 | **Erreur probable** |
| AJUSTAGE MECANIQUE INDUSTRIELLE A.M.I | INDUSTRIEL-FOURNITURES ET DIVERS (`2604840D`) | 2 | **Erreur probable** |

La liste nominative complète (numéro de facture, état, tiers actuel, tiers réel)
est produite par l'outil ; la relancer en production donnera la liste à jour.

## Ordre d'exécution recommandé

1. Déployer le module (le robinet est fermé : les nouveaux scans ne peuvent plus
   produire de faux code ni d'imputation par nom partiel).
2. Relancer la simulation **en production** et vérifier les chiffres.
3. Appliquer la correction des scans et des fiches partenaires
   (`dry_run=False`) — sans effet sur les écritures comptables.
4. Traiter au cas par cas les factures listées ci-dessus, avec la comptabilité.
