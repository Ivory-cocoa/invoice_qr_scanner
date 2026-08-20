# Requalification des avoirs DGI — mode opératoire

Version du module : **17.0.1.5.0** · Rédigé le 20 août 2026

---

## 1. Ce qui s'est passé

La plateforme FNE de la DGI certifie **deux natures de document sous un
QR-code de forme identique** :

| | Facture | Avoir |
|---|---|---|
| `subtype` renvoyé par l'API | `normal` | `refund` |
| Montants (`totalDue`, `amount`…) | positifs | **négatifs** |
| Affichage sur la page de vérification | `1 677 566 FCFA` | `250 000 FCFA` (valeur **absolue**) |

Rien dans l'URL scannée ne les distingue.

L'extraction historique de l'application mobile lisait le montant **sur le
texte de la page**, où l'avoir apparaît en valeur absolue. Un avoir de
250 000 F y était donc indiscernable d'une facture de 250 000 F, et le module
créait une facture d'achat : une **dette** envers le fournisseur là où il
fallait une **créance**.

L'extraction par l'API FNE, arrivée plus tard, voit le montant négatif. Elle a
rendu le défaut visible en **refusant** les avoirs (`FNE_INCOMPLETE_DATA —
montant TTC`) plutôt qu'en les enregistrant à l'envers. Ce refus, signalé par
les utilisateurs comme « les données ne sont pas extraites », était le
symptôme ; la cause dormait en base depuis des mois.

## 2. Ce que corrige la version 17.0.1.5.0

- La nature du document est un champ à part entière (`document_type`),
  renseigné par la DGI et non déduit.
- Un avoir crée un **avoir fournisseur** (`in_refund`), pas une facture.
- `amount_ttc` reste toujours positif ; le signe est porté par
  `amount_signed`, seul montant additionnable.
- Les avoirs se **retranchent** des coûts d'OT au lieu de s'y ajouter.
- Quand la DGI n'a pas pu confirmer la nature, `document_type_verified` reste
  faux et le scan remonte dans le filtre « Nature à confirmer ».

## 3. Requalifier l'existant

### 3.1 Principe

L'outil interroge la DGI scan par scan. **Aucune requalification ne repose sur
une heuristique** : la référence préfixée « A » sert uniquement à présélectionner
les candidats (24 appels au lieu de 4 962), la plateforme tranche.

Pour chaque avoir confirmé qui avait été enregistré en facture :

1. la facture d'achat erronée est **extournée** (écriture d'annulation
   comptabilisée) ;
2. un **avoir fournisseur** est créé à partir du scan ;
3. le scan est requalifié et son état antérieur rétabli (« traité » le reste) ;
4. les lignes de coût d'OT dérivées voient leur **signe inversé**.

Trois pièces comptables subsistent : la fausse facture, son extourne, l'avoir.
C'est voulu — une correction comptable se lit dans le grand livre, elle ne s'y
efface pas.

### 3.2 Cas que l'outil refuse de traiter

Il **signale et s'arrête** devant une écriture :

- réglée ou rapprochée (`payment_state` ≠ `not_paid`) ;
- déjà extournée ;
- annulée ;
- tombant dans une période comptable verrouillée.

Ces cas relèvent d'une décision comptable, pas d'un script.

### 3.3 Procédure

```bash
# Sur le serveur, dans un shell Odoo pointant la base de PRODUCTION
odoo shell -d <base_prod> --addons-path=...
```

```python
# ÉTAPE 1 — Rapport, sans aucune écriture. C'est le comportement par défaut.
res = env['invoice.scan.record'].repair_refund_documents()
print(res['examined'], res['requalified'], res['blocked'], res['unreachable'])
for c in res['changes']:
    print(c['scan_reference'], c['invoice_number_dgi'], c['supplier'],
          c['amount_ttc'], c['move_name'], c['move_state'])
for b in res['blocked_details']:
    print('BLOQUÉ', b['scan_reference'], b['move_name'], b['blockers'])
```

**Faire valider cette liste par la comptabilité avant d'aller plus loin.**

```python
# ÉTAPE 2 — Application
res = env['invoice.scan.record'].repair_refund_documents(dry_run=False)
env.cr.commit()
```

```python
# ÉTAPE 3 — Balayage exhaustif (facultatif, lent : un appel DGI par scan)
# À lancer une fois, hors heures ouvrées, pour confirmer qu'aucun avoir
# n'échappe à la présélection par référence.
env['invoice.scan.record'].repair_refund_documents(only_suspect=False)
```

### 3.4 Contrôles après application

```sql
-- Les avoirs portent bien des avoirs fournisseur
SELECT m.move_type, m.state, count(*), sum(m.amount_total)
  FROM account_move m
  JOIN invoice_scan_record r ON r.invoice_id = m.id
 WHERE r.document_type = 'refund'
 GROUP BY 1, 2;

-- Les anciennes factures sont neutralisées
SELECT state, payment_state, count(*)
  FROM account_move
 WHERE id IN (SELECT reversed_entry_id FROM account_move
               WHERE reversed_entry_id IS NOT NULL)
 GROUP BY 1, 2;
```

Attendu : `in_refund / posted` d'un côté, `posted / reversed` de l'autre.

## 4. Résultat de la validation en base de développement

Exécuté le 20 août 2026 sur `icp_dev_db` (copie restaurée de la production).

| | |
|---|---|
| Scans examinés | 24 |
| Confirmés avoirs par la DGI | **24 / 24** |
| Requalifiés | 24 |
| Bloqués (règlement, verrou, extourne) | 0 |
| DGI injoignable | 0 |
| Lignes de coût d'OT inversées | 2 |
| Montant total requalifié | **167 901 277 FCFA** |
| Impact net au grand livre | **− 167 901 277 FCFA** (créance) |

Contrôle de fiabilité de la présélection : 15 scans dont la référence ne
commence pas par « A » ont été soumis à la DGI — 15/15 confirmés `normal`.

### Détail des 24 documents

| Scan | N° DGI (avoir) | Fournisseur | Montant | Facture d'origine |
|---|---|---|---:|---|
| SCAN/2026/02596 | A1532352Y2600000001 | SOCIETE IVOIRIENNE DE TOUT ACHAT DE PRODUITS AGRICOLES | 141 696 200 | 1532352Y26000000014 |
| SCAN/2026/02595 | A1532352Y2600000002 | SOCIETE IVOIRIENNE DE TOUT ACHAT DE PRODUITS AGRICOLES | 5 841 920 | 1532352Y26000000018 |
| SCAN/2026/04718 | A0904648S2600000274 | ESPACE MEDICAL PASTEUR | 2 916 000 | 0904648S26000002324 |
| SCAN/2026/04493 | A1106600L2600005518 | SPRIINT TECHNIQUE COTE D'IVOIRE | 2 832 000 | 1106600L26000047351 |
| SCAN/2026/03405 | A2505594V2600000001 | NOUVELLE SOCIETE IVOIRIENNE D'INGENERIE | 2 360 000 | 2505594V26000000011 |
| SCAN/2026/04723 | A1868542G2600000011 | ROYAL SERVICES INTER | 2 350 923 | 1868542G26000000087 |
| SCAN/2026/04722 | A1868542G2600000012 | ROYAL SERVICES INTER | 2 327 818 | 1868542G26000000088 |
| SCAN/2026/03305 | A2245509Q2600000001 | YK SERVICE | 1 875 000 | 2245509Q26000000093 |
| SCAN/2026/02766 | A2114684L2600000006 | SAN PEDRO TRUCKS | 1 393 345 | 2114684L26000000188 |
| SCAN/2026/00309 | A1705315H2600000001 | COULIBALY ABDOUL KARIM | 1 250 000 | 1705315H26000000006 |
| SCAN/2026/00260 | A1727554W2600000001 | LOGIS TRANSPORT ET LOGISTIQUE | 828 950 | 1727554W26000000030 |
| SCAN/2026/00615 | A0194420S2600001216 | MEDITERRANEAN SHIPPING COMPANY | 806 827 | 0194420S26000012541 |
| SCAN/2026/04894 | A0904622G2600000043 | TERMINAL DE SAN | 533 000 | 0904622G26000004438 |
| SCAN/2026/01696 | A1225149H2600000092 | SHAZA TRANSIT | 170 000 | 1225149H25000000095 |
| SCAN/2026/04289 | A1315744F2600000002 | BERE JACOB | 150 000 | 1315744F26000000038 |
| SCAN/2026/02936 | A0194420S2600004605 | MEDITERRANEAN SHIPPING COMPANY | 149 730 | 0194420S26000063896 |
| SCAN/2026/02433 | A0194420S2600002850 | MEDITERRANEAN SHIPPING COMPANY | 147 590 | 0194420S25000035829 |
| SCAN/2026/05036 | A2245509Q2600000005 | YK SERVICE | 80 000 | 2245509Q26000000136 |
| SCAN/2026/01680 | A0194420S2600002476 | MEDITERRANEAN SHIPPING COMPANY | 69 845 | 0194420S26000031781 |
| SCAN/2026/04479 | A0194420S2600010551 | MEDITERRANEAN SHIPPING COMPANY | 44 778 | 0194420S26000068486 |
| SCAN/2026/01410 | A0194420S2600002222 | MEDITERRANEAN SHIPPING COMPANY | 27 800 | 0194420S26000031213 |
| SCAN/2026/00280 | A0194420S2600000918 | MEDITERRANEAN SHIPPING COMPANY | 19 679 | 0194420S26000012039 |
| SCAN/2026/03180 | A0194420S2600005263 | MEDITERRANEAN SHIPPING COMPANY | 14 946 | 0194420S26000066329 |
| SCAN/2026/03285 | A0194420S2600005706 | MEDITERRANEAN SHIPPING COMPANY | 14 926 | 0194420S26000068412 |

Deux lignes de coût d'OT étaient adossées à ces avoirs et gonflaient le coût de
leur dossier : OT 3864 (44 778 F) et OT 3916 (533 000 F). Elles ont été
inversées.

> ⚠️ Les numéros de pièces générés en développement (`RFACTU/2026/…`) ne
> préjugent pas de ceux qui seront attribués en production : les séquences y
> sont distinctes.

## 5. Ordre de déploiement

1. `git pull` des dépôts `invoice_qr_scanner` **et** `potting_management`
   (le signe des coûts d'OT est porté par le second).
2. Mise à jour des deux modules — **toujours avec `--addons-path` complet**,
   `/mnt/oca-addons` compris.
3. Vérifier le journal de migration : il indique combien de scans ont la forme
   d'un avoir.
4. Lancer la requalification en simulation, faire valider, puis appliquer.
5. Déployer l'APK `dist/facture_scanner_prod_*.apk` (version 3.3.0) et la PWA
   (déjà reconstruite dans `static/pwa/`).
