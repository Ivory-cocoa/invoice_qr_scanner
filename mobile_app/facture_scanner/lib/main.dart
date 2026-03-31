/// Main entry point for Facture Scanner App
/// Application de scan de QR-codes pour créer des factures fournisseur
/// Supporte les profils: Vérificateur, Traiteur, Manager

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/services/api_service.dart';
import 'core/services/database_service.dart';
import 'core/services/sync_service.dart';
import 'core/services/scheduled_sync_service.dart';
import 'core/services/background_scan_queue.dart';
import 'core/providers/auth_provider.dart';
import 'core/providers/scan_provider.dart';
import 'core/providers/connectivity_provider.dart';
import 'core/theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/traiteur_home_screen.dart';
import 'screens/manager_home_screen.dart';
import 'screens/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize services
  await DatabaseService().init();
  await ApiService().init();
  
  // Initialize scheduled sync (WorkManager)
  await ScheduledSyncService().initialize();
  
  runApp(const FactureScannerApp());
}

class FactureScannerApp extends StatelessWidget {
  const FactureScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ConnectivityProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProxyProvider<AuthProvider, ScanProvider>(
          create: (_) => ScanProvider(),
          update: (_, auth, scan) => scan!..updateAuth(auth),
        ),
        ChangeNotifierProxyProvider<ScanProvider, BackgroundScanQueue>(
          create: (_) => BackgroundScanQueue(),
          update: (_, scan, queue) {
            queue!.verificationTimeout = scan.verificationTimeout;
            queue.onHistoryChanged = () => scan.loadHistory(isOnline: true);
            return queue;
          },
        ),
        Provider(create: (_) => SyncService()),
      ],
      child: MaterialApp(
        title: 'Facture Scanner',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        initialRoute: '/',
        routes: {
          '/': (context) => const SplashScreen(),
          '/login': (context) => const LoginScreen(),
          '/home': (context) => const RoleBasedHomeScreen(),
          '/settings': (context) => const SettingsScreen(),
        },
      ),
    );
  }
}

/// Routes to the appropriate home screen based on user role
class RoleBasedHomeScreen extends StatelessWidget {
  const RoleBasedHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final role = auth.user?.role ?? 'user';

    switch (role) {
      case 'traiteur':
        return const TraiteurHomeScreen();
      case 'manager':
        return const ManagerHomeScreen();
      case 'verificateur':
      default:
        return const HomeScreen();
    }
  }
}
