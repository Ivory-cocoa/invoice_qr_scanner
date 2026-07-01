/// OT Manager Home Screen — Tableau de bord dédié au profil Gestionnaire OT.
///
/// Cet écran remplace le tableau de bord scanner classique pour les utilisateurs
/// dont le rôle principal est `ot_manager`. Il met en avant les deux flux
/// principaux :
///   1. "Scanner et lier" — scanner une nouvelle facture puis la rattacher à
///      un ou plusieurs OTs.
///   2. "Lier une facture déjà scannée" — choisir une facture parmi
///      l'historique pour la rattacher à un ou plusieurs OTs.
///
/// Y figurent également un compteur de liaisons effectuées et un accès direct
/// à la liste détaillée "Mes liaisons OT".

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models/api_response.dart';
import '../core/models/scan_record.dart';
import '../core/providers/auth_provider.dart';
import '../core/providers/connectivity_provider.dart';
import '../core/providers/scan_provider.dart';
import '../core/services/api_service.dart';
import '../core/ot_link_flow.dart';
import '../core/theme/app_theme.dart';
import '../widgets/connectivity_banner.dart';
import 'invoice_picker_screen.dart';
import 'manual_entry_screen.dart';
import 'my_ot_links_screen.dart';
import 'ot_cost_scans_screen.dart';
import 'scanner_screen.dart';

class OtManagerHomeScreen extends StatefulWidget {
  const OtManagerHomeScreen({super.key});

  @override
  State<OtManagerHomeScreen> createState() => _OtManagerHomeScreenState();
}

class _OtManagerHomeScreenState extends State<OtManagerHomeScreen> {
  final _api = ApiService();
  Map<String, dynamic>? _stats;
  bool _loadingStats = false;
  String? _statsError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AuthProvider>().addListener(_onAuthStateChanged);
      _loadStats();
    });
  }

  @override
  void dispose() {
    // Retrait sûr du listener (le provider survit à l'écran).
    try {
      context.read<AuthProvider>().removeListener(_onAuthStateChanged);
    } catch (_) {}
    super.dispose();
  }

  void _onAuthStateChanged() {
    final auth = context.read<AuthProvider>();
    if (!auth.isAuthenticated && mounted) {
      // Session expirée : rediriger vers la connexion.
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }

  Future<void> _loadStats() async {
    if (!mounted) return;
    setState(() {
      _loadingStats = true;
      _statsError = null;
    });
    final ApiResponse<Map<String, dynamic>> resp = await _api.getOtStats();
    if (!mounted) return;
    setState(() {
      _loadingStats = false;
      if (resp.success && resp.data != null) {
        _stats = resp.data;
      } else {
        _statsError = resp.errorMessage ?? 'Erreur de chargement';
      }
    });
  }

  Future<void> _scanAndLink() async {
    final connectivity = context.read<ConnectivityProvider>();
    final scan = context.read<ScanProvider>();

    final qrContent = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScannerScreen()),
    );
    if (qrContent == null || !mounted) return;

    // Process QR (extraction DGI côté client) avec un loader bloquant.
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ProcessingDialog(),
    );

    final manualEntryNeeded = await scan.processQrCodeWithExtraction(
      qrContent,
      isOnline: connectivity.isOnline,
    );

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // close loader

    final ScanRecord? record = scan.lastScanResult;
    final state = scan.state;

    if (manualEntryNeeded || state == ScanState.manualEntry) {
      // Le serveur DGI n'a pas répondu — on bascule sur la saisie manuelle.
      _toast(
        'Vérification DGI indisponible. Saisie manuelle requise.',
        isError: false,
      );
      final qrUrl = scan.pendingQrUrl ?? qrContent;
      final ok = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => ManualEntryScreen(
            qrUrl: qrUrl,
            prefillData: scan.extractedDgiData,
            verificationDuration: scan.lastVerificationDuration,
            timedOut: true,
          ),
        ),
      );
      if (!mounted) return;
      if (ok == true) {
        final r = scan.lastScanResult;
        if (r != null && r.id > 0) {
          await _pushLinkToOt(r);
        }
      }
      scan.resetState();
      _loadStats();
      return;
    }

    if ((state == ScanState.success || state == ScanState.duplicate) &&
        record != null &&
        record.id > 0) {
      if (state == ScanState.duplicate) {
        _toast(
          'Cette facture est déjà scannée. Vous pouvez la lier à un OT.',
          isError: false,
        );
      }
      scan.resetState();
      await _pushLinkToOt(record);
      return;
    }

    // Erreur
    final msg = scan.message ?? 'Impossible de traiter ce QR code';
    scan.resetState();
    _toast(msg, isError: true);
  }

  Future<void> _pushLinkToOt(ScanRecord record) async {
    // Parcours unifié : statut OT → sheet Cas A/B/C → écran de liaison.
    await startOtLinkFlow(context, record);
    if (mounted) _loadStats();
  }

  Future<void> _pickAndLink() async {
    final connectivity = context.read<ConnectivityProvider>();
    if (!connectivity.isOnline) {
      _toast('Connexion requise pour parcourir les factures', isError: true);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const InvoicePickerScreen()),
    );
    if (mounted) _loadStats();
  }

  Future<void> _openMyLinks() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const MyOtLinksScreen()),
    );
    if (mounted) _loadStats();
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Déconnexion'),
        content: const Text('Êtes-vous sûr de vouloir vous déconnecter ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.errorColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Déconnexion'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await context.read<AuthProvider>().logout();
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
      }
    }
  }

  void _toast(String msg, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor:
            isError ? AppTheme.errorColor : AppTheme.successColor,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.surfaceLight,
      appBar: AppBar(
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: isDark ? AppTheme.darkGradient : AppTheme.primaryGradient,
          ),
        ),
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.link_rounded, size: 24),
            SizedBox(width: 10),
            Text('Liaison OT'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Rafraîchir',
            onPressed: _loadingStats ? null : _loadStats,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.account_circle_rounded),
            onSelected: (v) {
              if (v == 'logout') _logout();
              if (v == 'my_links') _openMyLinks();
              if (v == 'settings') Navigator.pushNamed(context, '/settings');
            },
            itemBuilder: (context) {
              final user = context.read<AuthProvider>().user;
              return [
                PopupMenuItem(
                  enabled: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.name ?? 'Utilisateur',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        user?.roleLabel ?? '',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.getTextMuted(context),
                        ),
                      ),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'my_links',
                  child: Row(children: [
                    Icon(Icons.link_rounded, size: 20),
                    SizedBox(width: 12),
                    Text('Mes liaisons OT'),
                  ]),
                ),
                const PopupMenuItem(
                  value: 'settings',
                  child: Row(children: [
                    Icon(Icons.settings_rounded, size: 20),
                    SizedBox(width: 12),
                    Text('Paramètres'),
                  ]),
                ),
                const PopupMenuItem(
                  value: 'logout',
                  child: Row(children: [
                    Icon(Icons.logout_rounded, size: 20),
                    SizedBox(width: 12),
                    Text('Déconnexion'),
                  ]),
                ),
              ];
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const ConnectivityBanner(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadStats,
                color: AppTheme.getPrimary(context),
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildWelcomeCard(),
                      const SizedBox(height: 18),
                      _buildSectionTitle('Que voulez-vous faire ?'),
                      const SizedBox(height: 10),
                      _buildPrimaryAction(
                        icon: Icons.qr_code_scanner_rounded,
                        title: 'Scanner et lier',
                        subtitle:
                            'Scanner une nouvelle facture puis la rattacher à un ou plusieurs OTs',
                        color: AppTheme.primaryColor,
                        onTap: _scanAndLink,
                      ),
                      const SizedBox(height: 12),
                      _buildPrimaryAction(
                        icon: Icons.folder_open_rounded,
                        title: 'Lier une facture déjà scannée',
                        subtitle:
                            'Choisir une facture dans l\'historique et la lier à un ou plusieurs OTs',
                        color: AppTheme.accentColor,
                        onTap: _pickAndLink,
                      ),
                      const SizedBox(height: 12),
                      _buildPrimaryAction(
                        icon: Icons.local_shipping_rounded,
                        title: 'Consulter un OT',
                        subtitle:
                            'Scanner le QR-code d\'un OT ou le rechercher pour voir ses coûts et paiements',
                        color: AppTheme.infoColor,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const OtCostScansScreen(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildSectionTitle('Mon activité'),
                      const SizedBox(height: 10),
                      _buildStatsGrid(),
                      const SizedBox(height: 12),
                      _buildMyLinksTile(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeCard() {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        return Container(
          decoration: AppTheme.getGradientCardDecoration(context),
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.link_rounded,
                    color: Colors.white, size: 28),
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
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Gestionnaire OT • Rattachez vos factures aux OTs',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w800,
        color: AppTheme.getTextPrimary(context),
      ),
    );
  }

  Widget _buildPrimaryAction({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    final isDark = AppTheme.isDark(context);
    return Material(
      color: isDark ? AppTheme.darkSurfaceElevated : Colors.white,
      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      elevation: 3,
      shadowColor: color.withOpacity(0.18),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: color.withOpacity(isDark ? 0.22 : 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.getTextPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.getTextSecondary(context),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_ios_rounded,
                  color: color, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsGrid() {
    final myLinks = _stats?['my_links_count'] ?? 0;
    final myAmount = _stats?['my_total_amount'];
    final unlinked = _stats?['scans_unlinked'] ?? 0;
    final otsOpen = _stats?['ots_open'] ?? 0;
    final currency = (_stats?['currency'] ?? 'XOF').toString();

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildStatTile(
                icon: Icons.link_rounded,
                label: 'Mes liaisons',
                value: '$myLinks',
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildStatTile(
                icon: Icons.payments_rounded,
                label: 'Montant lié',
                value: _formatAmount(myAmount, currency),
                color: AppTheme.successColor,
                small: true,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildStatTile(
                icon: Icons.receipt_long_rounded,
                label: 'Factures à lier',
                value: '$unlinked',
                color: AppTheme.warningColor,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildStatTile(
                icon: Icons.local_shipping_rounded,
                label: 'OTs ouverts',
                value: '$otsOpen',
                color: AppTheme.accentColor,
              ),
            ),
          ],
        ),
        if (_statsError != null) ...[
          const SizedBox(height: 10),
          Text(
            _statsError!,
            style: TextStyle(color: AppTheme.errorColor, fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _buildStatTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    bool small = false,
  }) {
    final isDark = AppTheme.isDark(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurfaceElevated : Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.25 : 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(isDark ? 0.22 : 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: small ? 15 : 20,
              fontWeight: FontWeight.w800,
              color: AppTheme.getTextPrimary(context),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.getTextSecondary(context),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyLinksTile() {
    final isDark = AppTheme.isDark(context);
    return Material(
      color: isDark ? AppTheme.darkSurfaceElevated : Colors.white,
      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      elevation: 1.5,
      child: ListTile(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium)),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.list_alt_rounded,
              color: AppTheme.primaryColor),
        ),
        title: const Text('Voir toutes mes liaisons OT',
            style: TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(
          'Détail de chaque ligne de coût liée à un scan',
          style:
              TextStyle(color: AppTheme.getTextSecondary(context), fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: _openMyLinks,
      ),
    );
  }

  String _formatAmount(dynamic v, String currency) {
    if (v == null) return '0 $currency';
    num n;
    try {
      n = (v is num) ? v : num.parse(v.toString());
    } catch (_) {
      return '0 $currency';
    }
    final s = n.toStringAsFixed(0);
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return '${buf.toString()} $currency';
  }
}

class _ProcessingDialog extends StatelessWidget {
  const _ProcessingDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Consumer<ScanProvider>(
          builder: (context, scan, _) {
            final progress = scan.extractionProgress ??
                'Vérification de la facture en cours...';
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(
                  color: AppTheme.getPrimary(context),
                ),
                const SizedBox(height: 16),
                Text(
                  progress,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.getTextSecondary(context),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
