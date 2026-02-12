/// Configuration des environnements pour Facture Scanner
/// 
/// Environnements disponibles:
/// - development: http://192.168.5.159:8069 (icp_dev_db) - Réseau local développement
/// - staging: http://192.168.5.85:8069 (icp_test_db) 
/// - production: http://192.168.5.86:8069 (icp_db)

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
    apiBaseUrl: 'http://192.168.5.86:8069',
    databaseName: 'icp_db',
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
  
  // Version de l'application
  static const String appVersion = '1.0.0';
  static const int buildNumber = 1;
  
  // Nom de l'application
  static const String appName = 'Facture Scanner';
  static const String appNameFull = 'Scanner QR Factures DGI';
}
