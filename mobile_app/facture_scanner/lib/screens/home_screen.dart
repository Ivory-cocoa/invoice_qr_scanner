/// Home Screen - Design Professionnel ICP
/// Écran d'accueil moderne avec dashboard et statistiques

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/providers/auth_provider.dart';
import '../core/providers/scan_provider.dart';
import '../core/providers/connectivity_provider.dart';
import '../core/theme/app_theme.dart';
import '../widgets/connectivity_banner.dart';
import '../widgets/scan_result_dialog.dart';
import '../widgets/stats_card.dart';
import '../widgets/history_list.dart';
import 'scanner_screen.dart';
import 'errors_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isAutoSyncing = false;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initializeAndLoad();
    
    // Écouter les changements d'état d'authentification et de connectivité
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthProvider>().addListener(_onAuthStateChanged);
      context.read<ConnectivityProvider>().addListener(_onConnectivityChanged);
    });
  }
  
  void _onAuthStateChanged() {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated && mounted) {
      // Session expirée, rediriger vers la page de connexion
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }
  
  /// Écoute les changements de connectivité pour synchronisation automatique
  void _onConnectivityChanged() {
    final connectivity = context.read<ConnectivityProvider>();
    final scan = context.read<ScanProvider>();
    
    // Si on vient de passer en ligne et qu'il y a des scans en attente
    if (connectivity.isOnline && scan.hasPendingScans && !_isAutoSyncing && mounted) {
      _autoSyncPendingScans();
    }
  }
  
  /// Synchronisation automatique silencieuse
  Future<void> _autoSyncPendingScans() async {
    if (_isAutoSyncing) return;
    
    _isAutoSyncing = true;
    final scan = context.read<ScanProvider>();
    final result = await scan.syncPendingScans();
    _isAutoSyncing = false;
    
    if (mounted && result.success && result.syncedCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.cloud_done_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 12),
              Text('${result.syncedCount} scan(s) synchronisé(s)'),
            ],
          ),
          backgroundColor: AppTheme.successColor,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }
  
  /// Initialiser le ScanProvider et charger les données
  Future<void> _initializeAndLoad() async {
    final scan = context.read<ScanProvider>();
    await scan.init(); // Initialiser pour charger le nombre de scans en attente
    await _loadData();
  }
  
  Future<void> _loadData() async {
    final connectivity = context.read<ConnectivityProvider>();
    final scan = context.read<ScanProvider>();
    
    await scan.loadHistory(isOnline: connectivity.isOnline);
    if (connectivity.isOnline) {
      await scan.loadStats();
    }
  }
  
  @override
  void dispose() {
    // Retirer les listeners
    try {
      context.read<AuthProvider>().removeListener(_onAuthStateChanged);
      context.read<ConnectivityProvider>().removeListener(_onConnectivityChanged);
    } catch (_) {
      // Ignorer si le context n'est plus disponible
    }
    _tabController.dispose();
    super.dispose();
  }
  
  Future<void> _openScanner() async {
    final connectivity = context.read<ConnectivityProvider>();
    final scan = context.read<ScanProvider>();
    
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => const ScannerScreen(),
      ),
    );
    
    if (result != null && mounted) {
      await scan.processQrCode(result, isOnline: connectivity.isOnline);
      
      if (scan.state != ScanState.idle && mounted) {
        final dialogResult = await showDialog<String>(
          context: context,
          builder: (context) => ScanResultDialog(
            state: scan.state,
            message: scan.message,
            scanRecord: scan.lastScanResult,
          ),
        );
        
        scan.resetState();
        
        // Si l'utilisateur veut scanner une autre facture
        if (dialogResult == 'scan_again' && mounted) {
          _openScanner();
        }
      }
    }
  }
  
  Future<void> _syncPendingScans() async {
    final scan = context.read<ScanProvider>();
    final result = await scan.syncPendingScans();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                result.success ? Icons.check_circle : Icons.error,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(result.message)),
            ],
          ),
          backgroundColor: result.success ? AppTheme.successColor : AppTheme.errorColor,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }
  
  Future<void> _clearOfflineData() async {
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
    
    final confirmed = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Clear Data',
      barrierColor: AppTheme.isDark(context) ? Colors.black.withOpacity(0.85) : Colors.white.withOpacity(0.85),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomPadding + 32),
            child: Material(
              color: Colors.transparent,
              child: AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                ),
                title: Row(
                  children: [
                    Icon(Icons.delete_sweep, color: AppTheme.getWarning(context)),
                    const SizedBox(width: 12),
                    const Text('Vider les données', style: AppTheme.headingSmall),
                  ],
                ),
                content: const Text(
                  'Cette action supprimera toutes les données hors ligne (scans en attente et cache). Continuer ?',
                  style: AppTheme.bodyLarge,
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Annuler'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.warningColor,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Vider'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.9, end: 1.0).animate(animation),
            child: child,
          ),
        );
      },
    );
    
    if (confirmed == true && mounted) {
      final scan = context.read<ScanProvider>();
      await scan.clearOfflineData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 12),
                Text('Données hors ligne supprimées'),
              ],
            ),
            backgroundColor: AppTheme.successColor,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  Future<void> _markAllProcessed() async {
    final connectivity = context.read<ConnectivityProvider>();
    
    if (!connectivity.isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.wifi_off_rounded, color: Colors.white, size: 20),
              SizedBox(width: 12),
              Text('Connexion requise pour cette action'),
            ],
          ),
          backgroundColor: AppTheme.errorColor,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        ),
        title: Row(
          children: [
            Icon(Icons.verified_rounded, color: AppTheme.getPrimary(context)),
            const SizedBox(width: 12),
            const Text('Tout marquer traité', style: AppTheme.headingSmall),
          ],
        ),
        content: const Text(
          'Marquer tous les scans en état "Facture créée" comme traités ?\n\nCette action est réversible.',
          style: AppTheme.bodyLarge,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
              foregroundColor: Colors.white,
            ),
            child: const Text('Tout marquer'),
          ),
        ],
      ),
    );
    
    if (confirmed == true && mounted) {
      final scan = context.read<ScanProvider>();
      final result = await scan.bulkMarkAsProcessed();
      
      if (mounted) {
        if (result != null) {
          final count = result['successful'] ?? 0;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.verified_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  Text('$count scan(s) marqué(s) comme traité(s)'),
                ],
              ),
              backgroundColor: const Color(0xFF6C63FF),
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.error_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 12),
                  Text('Erreur lors du marquage en masse'),
                ],
              ),
              backgroundColor: AppTheme.errorColor,
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      }
    }
  }
  
  Future<void> _logout() async {
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
    
    final confirmed = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Logout',
      barrierColor: AppTheme.isDark(context) ? Colors.black.withOpacity(0.85) : Colors.white.withOpacity(0.85),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Center(
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomPadding + 32),
            child: Material(
              color: Colors.transparent,
              child: AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
                ),
                title: Row(
                  children: [
                    Icon(Icons.logout, color: AppTheme.getError(context)),
                    const SizedBox(width: 12),
                    const Text('Déconnexion', style: AppTheme.headingSmall),
                  ],
                ),
                content: const Text(
                  'Êtes-vous sûr de vouloir vous déconnecter ?',
                  style: AppTheme.bodyLarge,
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Annuler'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.errorColor,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Déconnexion'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.9, end: 1.0).animate(animation),
            child: child,
          ),
        );
      },
    );
    
    if (confirmed == true && mounted) {
      final auth = context.read<AuthProvider>();
      final scan = context.read<ScanProvider>();
      
      await scan.clearData();
      await auth.logout();
      
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    
    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.surfaceLight,
      appBar: _buildAppBar(),
      body: SafeArea(
        bottom: true,
        child: Column(
          children: [
            const ConnectivityBanner(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildHomeTab(),
                  const HistoryList(),
                ],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 16,
        ),
        child: _buildFAB(),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final isDark = AppTheme.isDark(context);
    
    return AppBar(
      elevation: 0,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          gradient: isDark ? AppTheme.darkGradient : AppTheme.primaryGradient,
        ),
      ),
      title: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.qr_code_scanner, size: 24),
          SizedBox(width: 10),
          Text('Facture Scanner'),
        ],
      ),
      actions: [
        // Bouton sync avec badge
        Consumer<ScanProvider>(
          builder: (context, scan, _) {
            return Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.sync_rounded),
                  onPressed: scan.hasPendingScans ? _syncPendingScans : null,
                  tooltip: 'Synchroniser',
                ),
                if (scan.hasPendingScans)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: AppTheme.getWarning(context),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${scan.pendingScansCount}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        
        // Menu utilisateur
        Consumer<AuthProvider>(
          builder: (context, auth, _) {
            return PopupMenuButton<String>(
              icon: const Icon(Icons.account_circle_rounded),
              offset: const Offset(0, 50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              ),
              onSelected: (value) {
                if (value == 'logout') _logout();
                if (value == 'clear_offline') _clearOfflineData();
                if (value == 'mark_all_processed') _markAllProcessed();
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  enabled: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        auth.user?.name ?? 'Utilisateur',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: AppTheme.getTextPrimary(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        auth.user?.email ?? '',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.getTextSecondary(context),
                        ),
                      ),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: 'mark_all_processed',
                  child: Row(
                    children: [
                      Icon(Icons.verified_rounded, color: AppTheme.getPrimary(context), size: 20),
                      const SizedBox(width: 12),
                      Text(
                        'Tout marquer traité',
                        style: TextStyle(
                          color: AppTheme.getTextPrimary(context),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'clear_offline',
                  child: Row(
                    children: [
                      Icon(Icons.delete_sweep_rounded, color: AppTheme.getWarning(context), size: 20),
                      const SizedBox(width: 12),
                      Text(
                        'Vider données hors ligne',
                        style: TextStyle(
                          color: AppTheme.getTextPrimary(context),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout_rounded, color: AppTheme.getError(context), size: 20),
                      const SizedBox(width: 12),
                      Text(
                        'Déconnexion',
                        style: TextStyle(
                          color: AppTheme.getTextPrimary(context),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(width: 8),
      ],
      bottom: TabBar(
        controller: _tabController,
        indicatorColor: Colors.white,
        indicatorWeight: 3,
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 14),
        tabs: const [
          Tab(
            icon: Icon(Icons.dashboard_rounded, size: 22),
            text: 'Accueil',
          ),
          Tab(
            icon: Icon(Icons.history_rounded, size: 22),
            text: 'Historique',
          ),
        ],
      ),
    );
  }
  
  Widget _buildHomeTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      color: AppTheme.getPrimary(context),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Carte de bienvenue (réduite)
            _buildCompactWelcomeCard(),
            
            const SizedBox(height: 16),
            
            // Alerte erreurs non traitées (si présentes)
            _buildErrorsAlert(),
            
            // Alerte scans en attente
            _buildPendingScansAlert(),
            
            const SizedBox(height: 16),
            
            // Statistiques
            const StatsCard(),
            
            const SizedBox(height: 16),
            
            // Actions rapides
            _buildQuickActions(),
          ],
        ),
      ),
    );
  }
  
  Widget _buildCompactWelcomeCard() {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        return Container(
          decoration: AppTheme.getGradientCardDecoration(context),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.person_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bonjour, ${auth.user?.name ?? 'Utilisateur'}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Scanner de factures DGI',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _openScanner,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.2),
                ),
                icon: const Icon(
                  Icons.qr_code_scanner_rounded,
                  color: Colors.white,
                  size: 26,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  
  Widget _buildErrorsAlert() {
    return Consumer<ScanProvider>(
      builder: (context, scan, _) {
        final errorCount = scan.combinedStats['error_scans'] ?? 0;
        if (errorCount == 0) return const SizedBox.shrink();
        
        final errorColor = AppTheme.getError(context);
        final errorLight = AppTheme.getErrorLight(context);
        
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            decoration: BoxDecoration(
              color: errorLight,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(color: errorColor.withOpacity(0.3)),
            ),
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: errorColor.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.error_outline_rounded,
                    color: errorColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Erreurs à traiter',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppTheme.getTextPrimary(context),
                        ),
                      ),
                      Text(
                        '$errorCount scan(s) en erreur',
                        style: TextStyle(
                          color: AppTheme.getTextSecondary(context),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ErrorsScreen()),
                  ),
                  style: TextButton.styleFrom(
                    backgroundColor: errorColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Voir',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPendingScansAlert() {
    return Consumer<ScanProvider>(
      builder: (context, scan, _) {
        if (!scan.hasPendingScans) return const SizedBox.shrink();
        
        final warningColor = AppTheme.getWarning(context);
        final warningLight = AppTheme.getWarningLight(context);
        
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            decoration: BoxDecoration(
              color: warningLight,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(color: warningColor.withOpacity(0.3)),
            ),
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: warningColor.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.cloud_off_rounded,
                    color: warningColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Scans en attente',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppTheme.getTextPrimary(context),
                        ),
                      ),
                      Text(
                        '${scan.pendingScansCount} scan(s) à synchroniser',
                        style: TextStyle(
                          color: AppTheme.getTextSecondary(context),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _syncPendingScans,
                  style: TextButton.styleFrom(
                    backgroundColor: warningColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Sync',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Actions rapides',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: AppTheme.getTextPrimary(context),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: _buildActionCard(
                icon: Icons.qr_code_scanner_rounded,
                title: 'Scanner',
                subtitle: 'Nouvelle facture',
                color: AppTheme.primaryColor,
                onTap: _openScanner,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionCard(
                icon: Icons.history_rounded,
                title: 'Historique',
                subtitle: 'Voir les scans',
                color: AppTheme.accentColor,
                onTap: () => _tabController.animateTo(1),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Consumer<ScanProvider>(
                builder: (context, scan, _) {
                  final errorCount = scan.combinedStats['error_scans'] ?? 0;
                  return _buildActionCard(
                    icon: Icons.error_outline_rounded,
                    title: 'Erreurs',
                    subtitle: '$errorCount en erreur',
                    color: AppTheme.errorColor,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ErrorsScreen()),
                    ),
                    badge: errorCount > 0 ? errorCount : null,
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Consumer<ScanProvider>(
                builder: (context, scan, _) {
                  final duplicateAttempts = scan.combinedStats['duplicate_attempts'] ?? 0;
                  return _buildActionCard(
                    icon: Icons.copy_rounded,
                    title: 'Doublons',
                    subtitle: '$duplicateAttempts tentatives',
                    color: AppTheme.warningColor,
                    onTap: () => _tabController.animateTo(1),
                    badge: duplicateAttempts > 0 ? duplicateAttempts : null,
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
    int? badge,
  }) {
    final isDark = AppTheme.isDark(context);
    
    return Material(
      color: isDark ? AppTheme.darkSurfaceElevated : Colors.white,
      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      elevation: 2,
      shadowColor: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: color.withOpacity(isDark ? 0.2 : 0.12),
                      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    ),
                    child: Icon(icon, color: color, size: 26),
                  ),
                  if (badge != null && badge > 0) ...[
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        badge > 99 ? '99+' : badge.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.getTextPrimary(context),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.getTextSecondary(context),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFAB() {
    final primaryColor = AppTheme.getPrimary(context);
    
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.4),
            blurRadius: 15,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: FloatingActionButton.extended(
        onPressed: _openScanner,
        elevation: 0,
        backgroundColor: primaryColor,
        icon: const Icon(Icons.qr_code_scanner_rounded, size: 24),
        label: const Text(
          'Scanner',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
