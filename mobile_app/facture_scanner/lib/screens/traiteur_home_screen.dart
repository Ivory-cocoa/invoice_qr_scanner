/// Traiteur Home Screen - Profil Traiteur
/// Écran d'accueil pour les utilisateurs avec le rôle "Traiteur"
/// - Scanner QR pour trouver et traiter les factures existantes
/// - Tableau de bord avec statistiques de traitement
/// - Liste des factures en attente de traitement

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/providers/auth_provider.dart';
import '../core/providers/scan_provider.dart';
import '../core/providers/connectivity_provider.dart';
import '../core/theme/app_theme.dart';
import '../core/models/scan_record.dart';
import '../widgets/connectivity_banner.dart';
import '../widgets/scan_result_dialog.dart';
import 'scanner_screen.dart';

class TraiteurHomeScreen extends StatefulWidget {
  const TraiteurHomeScreen({super.key});

  @override
  State<TraiteurHomeScreen> createState() => _TraiteurHomeScreenState();
}

class _TraiteurHomeScreenState extends State<TraiteurHomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _initializeAndLoad();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthProvider>().addListener(_onAuthStateChanged);
    });
  }

  void _onAuthStateChanged() {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated && mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }

  Future<void> _initializeAndLoad() async {
    final scan = context.read<ScanProvider>();
    await scan.init();
    await _loadData();
  }

  Future<void> _loadData() async {
    final connectivity = context.read<ConnectivityProvider>();
    final scan = context.read<ScanProvider>();

    if (connectivity.isOnline) {
      await Future.wait([
        scan.loadTraiteurPending(),
        scan.loadTraiteurStats(),
        scan.loadHistory(),
      ]);
    }
  }

  @override
  void dispose() {
    try {
      context.read<AuthProvider>().removeListener(_onAuthStateChanged);
    } catch (_) {}
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _openScanner() async {
    final connectivity = context.read<ConnectivityProvider>();
    
    if (!connectivity.isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.wifi_off_rounded, color: Colors.white, size: 20),
              SizedBox(width: 12),
              Text('Connexion requise pour traiter les factures'),
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

    final scan = context.read<ScanProvider>();

    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (context) => const ScannerScreen(),
      ),
    );

    if (result != null && mounted) {
      await scan.processQrCodeAsTraiteur(result);

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

        if (dialogResult == 'scan_again' && mounted) {
          _openScanner();
        }
      }
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        ),
        title: const Row(
          children: [
            Icon(Icons.logout, color: AppTheme.errorColor),
            SizedBox(width: 12),
            Text('Déconnexion', style: AppTheme.headingSmall),
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
                  _buildDashboardTab(),
                  _buildPendingTab(),
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
          gradient: isDark ? AppTheme.darkGradient : const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF00897B), Color(0xFF004D40)],
          ),
        ),
      ),
      title: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_rounded, size: 24),
          SizedBox(width: 10),
          Text('Traiteur - Factures'),
        ],
      ),
      bottom: TabBar(
        controller: _tabController,
        indicatorColor: Colors.white,
        indicatorWeight: 3,
        indicatorSize: TabBarIndicatorSize.label,
        tabs: const [
          Tab(icon: Icon(Icons.dashboard_rounded), text: 'Tableau de bord'),
          Tab(icon: Icon(Icons.pending_actions_rounded), text: 'En attente'),
        ],
      ),
      actions: [
        // Refresh button
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          tooltip: 'Actualiser',
          onPressed: _loadData,
        ),
        // User menu
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
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  enabled: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        auth.user?.name ?? 'Utilisateur',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: AppTheme.textDark,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        auth.user?.roleLabel ?? 'Traiteur',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.textLight,
                        ),
                      ),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout, color: AppTheme.errorColor, size: 20),
                      SizedBox(width: 12),
                      Text('Déconnexion', style: TextStyle(color: AppTheme.errorColor)),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildFAB() {
    return FloatingActionButton.extended(
      onPressed: _openScanner,
      backgroundColor: const Color(0xFF00897B),
      foregroundColor: Colors.white,
      elevation: 6,
      icon: const Icon(Icons.qr_code_scanner_rounded, size: 24),
      label: const Text(
        'Scanner pour traiter',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────
  // TAB 1: Dashboard
  // ─────────────────────────────────────────

  Widget _buildDashboardTab() {
    return Consumer<ScanProvider>(
      builder: (context, scan, _) {
        final stats = scan.traiteurStats;

        return RefreshIndicator(
          onRefresh: _loadData,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
              // Welcome header
              _buildWelcomeHeader(),
              const SizedBox(height: 20),

              // KPI cards
              _buildKpiGrid(stats),
              const SizedBox(height: 20),

              // Processing rate card
              _buildProcessingRateCard(stats),
              const SizedBox(height: 20),

              // Recent treatments
              _buildRecentTreatmentsCard(scan),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWelcomeHeader() {
    final auth = context.watch<AuthProvider>();
    final isDark = AppTheme.isDark(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: isDark
            ? AppTheme.darkGradient
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF00897B), Color(0xFF004D40)],
              ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.verified_rounded,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bonjour, ${auth.user?.name ?? "Traiteur"}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Scannez les QR-codes pour traiter les factures',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiGrid(Map<String, dynamic>? stats) {
    final pendingCount = stats?['pending_count'] ?? 0;
    final pendingAmount = _formatAmount(stats?['pending_amount'] ?? 0);
    final myProcessedCount = stats?['my_processed_count'] ?? 0;
    final myProcessedAmount = _formatAmount(stats?['my_processed_amount'] ?? 0);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildKpiCard(
                'En attente',
                '$pendingCount',
                pendingAmount,
                Icons.pending_actions_rounded,
                AppTheme.warningColor,
                AppTheme.warningLight,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildKpiCard(
                'Mes traitements',
                '$myProcessedCount',
                myProcessedAmount,
                Icons.check_circle_rounded,
                AppTheme.successColor,
                AppTheme.successLight,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildKpiCard(
                'Total traités',
                '${stats?['all_processed_count'] ?? 0}',
                null,
                Icons.done_all_rounded,
                AppTheme.primaryColor,
                AppTheme.primarySurface,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildKpiCard(
                'Taux traitement',
                '${(stats?['processing_rate'] ?? 0).toStringAsFixed(0)}%',
                null,
                Icons.speed_rounded,
                AppTheme.accentColor,
                const Color(0xFFE0F2F1),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildKpiCard(
    String label,
    String value,
    String? subtitle,
    IconData icon,
    Color color,
    Color bgColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 22),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: color.withOpacity(0.8),
              fontWeight: FontWeight.w500,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: color.withOpacity(0.6),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProcessingRateCard(Map<String, dynamic>? stats) {
    final rate = (stats?['processing_rate'] ?? 0.0).toDouble();
    final color = rate >= 75
        ? AppTheme.successColor
        : rate >= 50
            ? AppTheme.warningColor
            : AppTheme.errorColor;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: AppTheme.getCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bar_chart_rounded, color: AppTheme.accentColor, size: 22),
              SizedBox(width: 10),
              Text(
                'Taux de traitement global',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: rate / 100,
              minHeight: 14,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${rate.toStringAsFixed(1)}% traité',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              Text(
                '${stats?['all_processed_count'] ?? 0} / ${(stats?['all_processed_count'] ?? 0) + (stats?['pending_count'] ?? 0)}',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textLight,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecentTreatmentsCard(ScanProvider scan) {
    final history = scan.history
        .where((r) => r.state == 'processed')
        .take(5)
        .toList();

    return Container(
      decoration: AppTheme.getCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF00897B), Color(0xFF004D40)],
              ),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: const Row(
              children: [
                Icon(Icons.history_rounded, color: Colors.white, size: 22),
                SizedBox(width: 10),
                Text(
                  'Derniers traitements',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          // List
          if (history.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.inbox_rounded, color: AppTheme.textLight, size: 40),
                    SizedBox(height: 8),
                    Text(
                      'Aucun traitement récent',
                      style: TextStyle(color: AppTheme.textLight, fontSize: 14),
                    ),
                  ],
                ),
              ),
            )
          else
            ...history.map((record) => _buildRecordTile(record)),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────
  // TAB 2: Pending invoices
  // ─────────────────────────────────────────

  Widget _buildPendingTab() {
    return Consumer<ScanProvider>(
      builder: (context, scan, _) {
        final pending = scan.pendingInvoices;

        return RefreshIndicator(
          onRefresh: () => scan.loadTraiteurPending(),
          child: pending.isEmpty
              ? _buildEmptyPending()
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  itemCount: pending.length,
                  itemBuilder: (context, index) => _buildPendingCard(pending[index]),
                ),
        );
      },
    );
  }

  Widget _buildEmptyPending() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            size: 64,
            color: AppTheme.successColor.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          const Text(
            'Aucune facture en attente',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.textMedium,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Toutes les factures ont été traitées !',
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingCard(ScanRecord record) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.warningColor.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.warningLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  color: AppTheme.warningColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.reference,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    if (record.supplierName.isNotEmpty)
                      Text(
                        record.supplierName,
                        style: const TextStyle(
                          color: AppTheme.textLight,
                          fontSize: 13,
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.warningLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'En attente',
                  style: TextStyle(
                    color: AppTheme.warningColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (record.invoiceNumberDgi.isNotEmpty)
                Text(
                  'N° ${record.invoiceNumberDgi}',
                  style: const TextStyle(
                    color: AppTheme.textMedium,
                    fontSize: 13,
                  ),
                ),
              Text(
                _formatAmount(record.amountTtc),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: AppTheme.primaryColor,
                ),
              ),
            ],
          ),
          if (record.scanDate != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.calendar_today_rounded, size: 14, color: AppTheme.textLight),
                const SizedBox(width: 6),
                Text(
                  _formatDate(record.scanDate!),
                  style: const TextStyle(
                    color: AppTheme.textLight,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRecordTile(ScanRecord record) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTheme.successLight,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(
          Icons.check_circle_rounded,
          color: AppTheme.successColor,
          size: 20,
        ),
      ),
      title: Text(
        record.reference,
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Text(
        record.supplierName.isNotEmpty ? record.supplierName : 'Fournisseur inconnu',
        style: const TextStyle(fontSize: 12, color: AppTheme.textLight),
      ),
      trailing: Text(
        _formatAmount(record.amountTtc),
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 14,
          color: AppTheme.successColor,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────
  // Utilities
  // ─────────────────────────────────────────

  String _formatAmount(dynamic amount) {
    final value = (amount is num) ? amount.toDouble() : 0.0;
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M FCFA';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(0)}K FCFA';
    }
    return '${value.toStringAsFixed(0)} FCFA';
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}
