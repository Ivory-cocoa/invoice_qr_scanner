/// Configuration des environnements pour Facture Scanner
/// 
/// Environnements disponibles:
/// - development: http://192.168.5.159:8069 (icp_dev_db) - Réseau local développement
/// - staging: http://192.168.5.85:8069 (icp_test_db) 
/// - production: https://odoo.ivorycocoa.ci (odoo.ivorycocoa.ci)
library;

enum Environment {
  development,
  staging,
  production,
}

class EnvironmentConfig {
  final String name;
  final String apiBaseUrl;
  final String databaseName;
  final bool enableLogging;
  final bool enableCrashlytics;

  const EnvironmentConfig({
    required this.name,
    required this.apiBaseUrl,
    required this.databaseName,
    this.enableLogging = false,
    this.enableCrashlytics = false,
  });

  static const EnvironmentConfig development = EnvironmentConfig(
    name: 'Développement',
    apiBaseUrl: 'http://192.168.5.159:8069',
    databaseName: 'icp_dev_db',
    enableLogging: true,
    enableCrashlytics: false,
  );

  static const EnvironmentConfig staging = EnvironmentConfig(
    name: 'Préproduction',
    apiBaseUrl: 'http://192.168.5.85:8069',
    databaseName: 'icp_test_db',
    enableLogging: true,
    enableCrashlytics: false,
  );

  static const EnvironmentConfig production = EnvironmentConfig(
    name: 'Production',
    apiBaseUrl: 'https://odoo.ivorycocoa.ci',
    databaseName: 'odoo.ivorycocoa.ci',
    enableLogging: false,
    enableCrashlytics: true,
  );

  /// Récupère la configuration selon l'environnement
  static EnvironmentConfig fromEnvironment(Environment env) {
    switch (env) {
      case Environment.development:
        return development;
      case Environment.staging:
        return staging;
      case Environment.production:
        return production;
    }
  }
}

/// Configuration globale de l'application
/// MODIFIER ICI POUR CHANGER D'ENVIRONNEMENT
class AppConfig {
  // ========================================
  // ENVIRONNEMENT ACTUEL: PRODUCTION
  // ========================================
  static const Environment currentEnvironment = Environment.production;
  
  static EnvironmentConfig get config => 
      EnvironmentConfig.fromEnvironment(currentEnvironment);
  
  static String get apiBaseUrl => config.apiBaseUrl;
  static String get databaseName => config.databaseName;
  static String get environmentName => config.name;
  static bool get enableLogging => config.enableLogging;
  static bool get enableCrashlytics => config.enableCrashlytics;
  
  // Version de l'application — SOURCE UNIQUE pour l'affichage.
  //
  // ⚠️ Garder synchronisé avec `version:` dans pubspec.yaml. Ces valeurs ont
  // divergé par le passé (pubspec 2.1.0+3, AppConfig 2.0.1, et « Version
  // 2.0.0 » codé en dur dans deux écrans) : l'utilisateur voyait une version
  // qui n'était celle d'aucun build.
  //
  // Passage en 3.0.0 : la connexion par mot de passe est remplacée par un
  // code à usage unique envoyé par email. Les APK antérieurs ne peuvent plus
  // s'authentifier — c'est un changement incompatible, d'où le majeur.
  static const String appVersion = '3.0.0';
  static const int buildNumber = 4;
  
  // Nom de l'application
  static const String appName = 'Facture Scanner';
  static const String appNameFull = 'Scanner QR Factures DGI';
}
