/// OT Manager Home Screen — Tableau de bord dédié au profil Gestionnaire OT.
///
/// Cet écran remplace le tableau de bord scanner classique pour les utilisateurs
/// dont le rôle principal est `ot_manager`.
///
/// Le Gestionnaire OT ne vérifie PAS les factures (pas de création de scan,
/// pas de contrôle de doublon) et ne les traite pas. Il peut :
///   1. "Vérifier une facture" — scanner une facture DÉJÀ scannée par un
///      Vérificateur pour savoir si elle est liée à un OT, puis la lier ;
///   2. "Rechercher une facture" — par numéro, fournisseur ou OT ;
///   3. "Factures liées à des OT" — consulter la liste ;
///   4. "Rechercher un OT" — voir ses coûts et paiements.
///
/// Y figurent également un compteur de liaisons effectuées et un accès direct
/// à la liste détaillée "Mes liaisons OT".
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models/api_response.dart';
import '../core/models/scan_record.dart';
import '../core/providers/auth_provider.dart';
import '../core/providers/connectivity_provider.dart';
import '../core/services/api_service.dart';
import '../core/ot_link_flow.dart';
import '../core/theme/app_theme.dart';
import '../widgets/connectivity_banner.dart';
import 'invoice_picker_screen.dart';
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
      // Redirection en cas de perte de session : assurée globalement par
      // AuthGuard (cf. main.dart).
      _loadStats();
    });
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

  /// Scanner une facture pour savoir si elle est liée à un OT.
  ///
  /// Lecture seule : le Gestionnaire OT ne vérifie pas les factures. Rien
  /// n'est créé, la DGI n'est pas interrogée et aucun doublon n'est compté.
  /// La facture doit avoir été scannée auparavant par un Vérificateur.
  Future<void> _scanAndCheck() async {
    final connectivity = context.read<ConnectivityProvider>();
    if (!connectivity.isOnline) {
      _toast('Connexion requise pour vérifier une facture', isError: true);
      return;
    }

    final qrContent = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const ScannerScreen()));
    if (qrContent == null || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ProcessingDialog(),
    );
    final resp = await _api.lookupScan(qrContent);
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // close loader

    final data = resp.data;
    if (!resp.success || data == null) {
      _toast(
        resp.errorMessage ?? 'Impossible de vérifier cette facture',
        isError: true,
      );
      return;
    }

    final recordJson = data['record'];
    if (data['found'] == true && recordJson is Map<String, dynamic>) {
      final ScanRecord record;
      try {
        record = ScanRecord.fromJson(recordJson);
      } catch (_) {
        _toast('Réponse du serveur illisible', isError: true);
        return;
      }
      // Statut OT (liée, partiellement liée, non liée) puis liaison.
      await _pushLinkToOt(record);
      return;
    }

    await _showNotScannedDialog(notReady: data['reason'] == 'not_ready');
  }

  Future<void> _showNotScannedDialog({required bool notReady}) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(
          Icons.search_off_rounded,
          color: AppTheme.warningColor,
          size: 40,
        ),
        title: const Text('Facture introuvable'),
        content: Text(
          notReady
              ? 'Cette facture a été scannée mais son enregistrement n\'est '
                    'pas terminé (scan en erreur ou en attente). Elle ne '
                    'peut pas encore être liée à un OT.\n\n'
                    'Signalez-la à un Vérificateur.'
              : 'Cette facture n\'a pas encore été scannée par un '
                    'Vérificateur : elle n\'est donc liée à aucun OT et ne '
                    'peut pas encore l\'être.\n\n'
                    'Remettez-la à un Vérificateur, puis scannez-la de '
                    'nouveau.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Compris'),
          ),
        ],
      ),
    );
  }

  Future<void> _pushLinkToOt(ScanRecord record) async {
    // Parcours unifié : statut OT → sheet Cas A/B/C → écran de liaison.
    await startOtLinkFlow(context, record);
    if (mounted) _loadStats();
  }

  /// Liste des factures scannées : toutes (recherche d'une facture), ou
  /// seulement celles liées à des OT.
  Future<void> _openInvoices(InvoiceLinkFilter filter) async {
    final connectivity = context.read<ConnectivityProvider>();
    if (!connectivity.isOnline) {
      _toast('Connexion requise pour parcourir les factures', isError: true);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InvoicePickerScreen(initialFilter: filter),
      ),
    );
    if (mounted) _loadStats();
  }

  Future<void> _openMyLinks() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const MyOtLinksScreen()));
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
        backgroundColor: isError ? AppTheme.errorColor : AppTheme.successColor,
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
                  child: Row(
                    children: [
                      Icon(Icons.link_rounded, size: 20),
                      SizedBox(width: 12),
                      Text('Mes liaisons OT'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'settings',
                  child: Row(
                    children: [
                      Icon(Icons.settings_rounded, size: 20),
                      SizedBox(width: 12),
                      Text('Paramètres'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout_rounded, size: 20),
                      SizedBox(width: 12),
                      Text('Déconnexion'),
                    ],
                  ),
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
                        title: 'Vérifier une facture',
                        subtitle:
                            'Scanner une facture pour savoir si elle est liée à un OT, puis la lier',
                        color: AppTheme.primaryColor,
                        onTap: _scanAndCheck,
                      ),
                      const SizedBox(height: 12),
                      _buildPrimaryAction(
                        icon: Icons.manage_search_rounded,
                        title: 'Rechercher une facture',
                        subtitle:
                            'Par numéro, fournisseur ou OT, puis la lier à un ou plusieurs OTs',
                        color: AppTheme.accentColor,
                        onTap: () => _openInvoices(InvoiceLinkFilter.all),
                      ),
                      const SizedBox(height: 12),
                      _buildPrimaryAction(
                        icon: Icons.link_rounded,
                        title: 'Factures liées à des OT',
                        subtitle:
                            'Consulter la liste des factures déjà rattachées et leurs OT',
                        color: AppTheme.successColor,
                        onTap: () => _openInvoices(InvoiceLinkFilter.linked),
                      ),
                      const SizedBox(height: 12),
                      _buildPrimaryAction(
                        icon: Icons.local_shipping_rounded,
                        title: 'Rechercher un OT',
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
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.link_rounded,
                  color: Colors.white,
                  size: 28,
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
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Gestionnaire OT • Factures liées aux OT',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
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
      shadowColor: color.withValues(alpha: 0.18),
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
                  color: color.withValues(alpha: isDark ? 0.22 : 0.14),
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
              Icon(Icons.arrow_forward_ios_rounded, color: color, size: 18),
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
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
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
              color: color.withValues(alpha: isDark ? 0.22 : 0.12),
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
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        ),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.primaryColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.list_alt_rounded,
            color: AppTheme.primaryColor,
          ),
        ),
        title: const Text(
          'Voir toutes mes liaisons OT',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          'Détail de chaque ligne de coût liée à un scan',
          style: TextStyle(
            color: AppTheme.getTextSecondary(context),
            fontSize: 12,
          ),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppTheme.getPrimary(context)),
            const SizedBox(height: 16),
            Text(
              'Recherche de la facture…',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.getTextSecondary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
