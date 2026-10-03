# Facture Scanner

Application Android de scan des factures fournisseurs certifiées (FNE / DGI)
pour Odoo (module `invoice_qr_scanner`) : connexion par code OTP, file des
scans hors réseau, rattachement des factures aux OT comme coûts opérationnels.

## Construire l'APK

```bash
./build_apk.sh              # vérifie la config production, analyse, tests, APK
./build_apk.sh --skip-tests # build rapide
```

L'APK horodaté sort dans `dist/`. Avant chaque version : incrémenter ensemble
`version:` dans `pubspec.yaml` (après le `+`) et `appVersion` / `buildNumber`
dans `lib/core/config/environment.dart`. Publier ensuite dans Odoo :
**Applications mobiles ▸ Facture Scanner ▸ Nouvelle version**. Les téléphones
affichent alors le bandeau « Nouvelle version disponible »
(`lib/core/services/apk_update.dart`, fichier commun aux applications ICP) :
téléchargement dans l'application, contrôle SHA-256, installeur Android.

## Signature (clé ICP)

Depuis la 3.5.0+9 (3 octobre 2026), Facture Scanner est signée avec la clé
commune des applications ICP : `~/.icp-android/icp-release.jks`, alias `icp`,
SHA-256 `3c1cc19eababb6167339d7490d5373ca9979d13f000f9b6b8a56393de88a10ef`.
Gradle la lit dans `android/app/key.properties` (hors dépôt, jamais commité) :

```properties
storeFile=/Users/<vous>/.icp-android/icp-release.jks
storePassword=…
keyAlias=icp
keyPassword=…
```

**Sauvegardez la clé et son mot de passe** : sans eux, plus aucune mise à jour
ne s'installe par-dessus les versions publiées.

Les versions jusqu'à la 3.4 étaient signées avec une clé propre à
l'application (`CN=ICP`, SHA-256 `614156a7…`, conservée dans
`~/.icp-android/ancienne-cle-facture-scanner/`). Le changement de clé impose
une réinstallation unique : synchroniser les scans en attente (Paramètres ▸
Synchroniser maintenant), désinstaller l'ancienne application, installer la
3.5.0.
