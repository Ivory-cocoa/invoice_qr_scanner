# Facture Scanner

Application Android de scan des factures fournisseurs certifiées (FNE / DGI)
pour Odoo (module `invoice_qr_scanner`) : connexion par code OTP, file des
scans hors réseau, rattachement des factures aux OT comme coûts opérationnels.

## Construire l'APK

```bash
./build_apk.sh              # vérifie la config production, analyse, tests, APK
./build_apk.sh --skip-tests # build rapide
```

Le code est au format `dart format`, que `build_apk.sh` exige. Ouvert comme
dossier racine dans VS Code (`code mobile_app/facture_scanner`), le projet
se formate à l'enregistrement (`.vscode/settings.json`). Sinon :
`dart format lib test` avant de commiter.

L'APK horodaté sort dans `dist/`. Avant chaque version : incrémenter ensemble
`version:` dans `pubspec.yaml` (après le `+`) et `appVersion` / `buildNumber`
dans `lib/core/config/environment.dart`. Publier ensuite dans Odoo :
**Applications mobiles ▸ Facture Scanner ▸ Nouvelle version**. Les téléphones
affichent alors le bandeau « Nouvelle version disponible »
(`lib/core/services/apk_update.dart`, fichier commun aux applications ICP) :
téléchargement dans l'application, contrôle SHA-256, installeur Android.

## Signature (clé ICP)

Facture Scanner est signée avec la clé commune des applications ICP :
`~/.icp-android/icp-release.jks`, alias `icp`, SHA-256 `66d28cde03fec1c1a8b121d6a7ad04f246ebf999ce834e4bee0046d022d328f8`
depuis la 3.5.1+10 (de la 3.5.0+9 du 3 octobre 2026 : `3c1cc19e…a10ef`).
Gradle la lit dans `android/app/key.properties` (hors dépôt, jamais commité) :

```properties
storeFile=/Users/<vous>/.icp-android/icp-release.jks
storePassword=…
keyAlias=icp
keyPassword=…
```

**Sauvegardez la clé et son mot de passe** : sans eux, plus aucune mise à jour
ne s'installe par-dessus les versions publiées.

**Changement de clé (29 octobre 2026).** La clé du 3 octobre 2026
(SHA-256 `3c1cc19e…a10ef`) n'est plus sur le Mac de build : le fichier
`icp-release.jks` a été recréé. Depuis la 3.5.1, l'application est
signée avec la nouvelle clé (certificat `CN=Ivory Cocoa Products, O=ICP,
L=San-Pedro, C=CI`, SHA-256 `66d28cde03fec1c1a8b121d6a7ad04f246ebf999ce834e4bee0046d022d328f8`). Android refuse la mise à jour
par-dessus la 3.5.0 : sur chaque téléphone, **désinstaller puis installer
la 3.5.1 une fois**, **après avoir envoyé les factures en attente** s'il en reste. Ensuite, les mises à jour s'installent de nouveau
par-dessus. Vérifier chaque APK avant publication (`apksigner verify
--print-certs`) : une autre empreinte = ne pas publier.


Les versions jusqu'à la 3.4 étaient signées avec une clé propre à
l'application (`CN=ICP`, SHA-256 `614156a7…`, conservée dans
`~/.icp-android/ancienne-cle-facture-scanner/`). Le changement de clé impose
une réinstallation unique : synchroniser les scans en attente (Paramètres ▸
Synchroniser maintenant), désinstaller l'ancienne application, installer la
3.5.0.
