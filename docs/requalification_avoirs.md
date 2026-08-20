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

### 3.3 Où s'impute la correction (à trancher AVANT d'appliquer)

Par défaut, la correction retombe dans la **période d'origine** :

- l'extourne prend la date comptable de la facture erronée (janvier pour une
  pièce de janvier) ;
- l'avoir prend celle de son document DGI.

Les deux se neutralisent donc sur le même mois, et le résultat net de chaque
période redevient juste. C'est comptablement le plus propre — mais cela
**écrit dans des mois déjà déclarés**, de janvier à juillet 2026.

L'argument `posting_date` impute au contraire toute la correction sur une
période ouverte :

```python
env['invoice.scan.record'].repair_refund_documents(
    dry_run=False, posting_date='2026-08-31')
```

La date du **document** reste celle de la DGI dans les deux cas ; seule la date
d'**imputation comptable** change.

| | Sans `posting_date` (défaut) | Avec `posting_date` |
|---|---|---|
| Périodes touchées | janvier → juillet | le mois indiqué seulement |
| Résultat par mois | rétabli | inchangé sur le passé, corrigé sur le mois courant |
| Déclarations déjà déposées | à revoir | intactes |

Aucune date de verrouillage n'est configurée sur la société : Odoo laissera
passer les deux options sans broncher. **Le choix appartient donc entièrement
à la comptabilité, et rien dans l'outil ne l'imposera.**

### 3.4 Procédure — avec le script (recommandé)

`scripts/requalifier_avoirs.sh` enchaîne tous les contrôles, la sauvegarde et
la requalification. Il **simule par défaut** : il faut `--apply` pour qu'il
écrive quoi que ce soit.

```bash
cd /home/digital/ivorycocoa/invoice_qr_scanner/scripts

# 1. SIMULATION — rien n'est écrit
./requalifier_avoirs.sh --db <base_prod>

# 2. Après validation comptable du CSV produit : APPLICATION
./requalifier_avoirs.sh --db <base_prod> --apply
#    ...ou, pour imputer sur la période ouverte :
./requalifier_avoirs.sh --db <base_prod> --apply --posting-date 2026-08-31

# 3. Contrôles
./requalifier_avoirs.sh --db <base_prod> --check
```

Ce qu'il fait pour vous, et qu'une session manuelle ne fera pas :

- refuse de tourner si le module n'est pas au moins en 17.0.1.5.0 (la méthode
  n'existerait pas) ;
- **sauvegarde la base avant toute écriture, et vérifie que la sauvegarde est
  relisible** (`pg_restore -l`) avant de continuer — un filet qu'on n'a pas
  vérifié n'en est pas un ;
- exige de taper `APPLIQUER` en toutes lettres ;
- rappelle l'avertissement sur la période d'imputation quand `--posting-date`
  est absent ;
- committe la transaction (le shell Odoo ne le fait pas seul : sans cela, tout
  le travail serait perdu à la fermeture, silencieusement) ;
- écrit un journal et un **CSV** dans `rapports_avoirs/`, à faire relire par la
  comptabilité.

Options utiles : `--scan-ids 2596,2595` pour reprendre des cas précis après
arbitrage, `--full` pour interroger la DGI sur tout le stock (~40 min),
`--outdir` pour écrire ailleurs que dans le dépôt, `--container` pour viser un
autre conteneur (`odoo17-web-dev` en développement), `--db-user` si le rôle
PostgreSQL n'est pas `odoo`.

> **Lancer avec `./requalifier_avoirs.sh`, pas `sh requalifier_avoirs.sh`.**
> Le script utilise des constructions bash que `sh` (dash) ne connaît pas. Il
> se relance désormais tout seul sous bash, mais autant prendre la bonne
> habitude.

> Le script ne passe **aucun identifiant de connexion** à `odoo shell` : le
> conteneur sait déjà joindre sa base, c'est ainsi que le serveur tourne. Les
> imposer reviendrait à parier sur un mot de passe que le script ne connaît
> pas.

### 3.5 Procédure — manuelle

À utiliser si le script ne peut pas tourner. Sur le VPS, dans le répertoire du
projet :

```bash
# 0. Nom exact de la base de production
docker exec odoo17-db-prod psql -U odoo -lqt | cut -d'|' -f1
DB=<base_prod>
```

⚠️ `odoo.sh` a `DEFAULT_DATABASE="icp_dev_db"` en dur : **toujours passer le nom
de la base en troisième argument**, sinon la commande vise une base qui
n'existe pas côté prod.

```bash
# 1. Récupérer le code — les DEUX dépôts, et AVANT la mise à jour
cd /home/digital/ivorycocoa/invoice_qr_scanner && git pull
cd /home/digital/ivorycocoa/potting_management  && git pull

# 2. Redémarrer, puis mettre à jour les deux modules ENSEMBLE
cd /home/digital/<projet> && ./restart.sh
./odoo.sh prod update invoice_qr_scanner,potting_management "$DB"
```

`odoo.sh` passe déjà le `--addons-path` complet, `/mnt/oca-addons` compris.
Vérifier ensuite qu'aucun module ne reste en transit :

```sql
SELECT name, state FROM ir_module_module
 WHERE state NOT IN ('installed', 'uninstalled', 'uninstallable');
```

```bash
# 3. Shell Odoo sur la production
docker exec -it odoo17-web-prod odoo shell -d "$DB" \
  --addons-path=/usr/lib/python3/dist-packages/odoo/addons,/mnt/extra-addons,/mnt/oca-addons \
  --no-http
```

```python
# 4. SIMULATION — c'est le comportement par défaut, rien n'est écrit.
res = env['invoice.scan.record'].repair_refund_documents()
print(res['examined'], res['requalified'], res['blocked'], res['unreachable'])
for c in res['changes']:
    print(c['scan_reference'], c['invoice_number_dgi'], c['supplier'],
          c['amount_ttc'], c['move_name'], c['move_state'])
for b in res['blocked_details']:
    print('BLOQUÉ', b['scan_reference'], b['move_name'], b['blockers'])
```

**Faire valider cette liste par la comptabilité, et trancher la question de la
période (§ 3.3), avant d'aller plus loin.**

```python
# 5. APPLICATION — choisir UNE des deux formes
res = env['invoice.scan.record'].repair_refund_documents(dry_run=False)
# ... ou, pour tout imputer sur le mois courant :
res = env['invoice.scan.record'].repair_refund_documents(
    dry_run=False, posting_date='2026-08-31')

env.cr.commit()   # indispensable : le shell Odoo ne committe pas tout seul
```

```python
# 6. Balayage exhaustif (facultatif, lent : un appel DGI par scan, ~40 min)
# À lancer une fois, hors heures ouvrées, pour confirmer qu'aucun avoir
# n'échappe à la présélection par référence.
env['invoice.scan.record'].repair_refund_documents(only_suspect=False)
```

Pour reprendre un cas bloqué après arbitrage comptable, cibler les scans :

```python
env['invoice.scan.record'].repair_refund_documents(
    dry_run=False, scan_ids=[2596, 2595])
```

### 3.6 Contrôles après application

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

## 5. Ordre de déploiement et retour arrière

| Étape | Action | Réversible ? |
|---|---|---|
| 1 | `git pull` des deux dépôts (`invoice_qr_scanner`, `potting_management`) | oui |
| 2 | `./restart.sh` puis mise à jour des deux modules | oui (revert + update) |
| 3 | Simulation de la requalification | rien n'est écrit |
| 4 | Validation comptable de la liste + choix de la période | — |
| 5 | Application (`dry_run=False`) | **non** — voir ci-dessous |
| 6 | Déploiement APK 3.3.0 + PWA | oui |

La PWA est servie par le module (`static/pwa/`) : elle part avec le `git pull`,
sans manipulation. L'APK `dist/facture_scanner_prod_20260820_103725.apk` se
distribue par le canal habituel.

**Retour arrière de l'étape 5.** Les écritures produites sont comptabilisées :
il n'y a pas d'annulation en un clic. Le retour se fait comme n'importe quelle
correction comptable — extourner l'avoir créé, extourner l'extourne — ce qui
laisse six pièces au lieu de trois. D'où l'importance de l'étape 4.

**Sauvegarde.** Prendre un instantané de la base avant l'étape 5 ; c'est le
seul retour arrière réellement propre.

## 6. Après le déploiement

- Filtre back-office **« Nature à confirmer »** : il recense les scans dont la
  nature n'a jamais été validée par la DGI (tout l'historique y figure au
  départ, puisque le champ vient de naître). Le bouton « Vérifier la nature
  auprès de la DGI », disponible aussi en action de masse depuis la liste,
  les résorbe par lots.
- Filtre **« Avoirs sans facture d'origine »** : avoirs dont la facture
  corrigée n'a jamais été scannée. Rien d'anormal en soi ; utile pour repérer
  une facture manquante.
- Les nouveaux scans, eux, arrivent déjà confirmés : la nature vient de la DGI
  à la source.
