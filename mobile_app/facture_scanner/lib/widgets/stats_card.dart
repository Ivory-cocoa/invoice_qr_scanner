/// Stats Card Widget - Design Professionnel ICP
/// Affiche les statistiques de scan avec un design moderne

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import '../core/providers/scan_provider.dart';
import '../core/theme/app_theme.dart';

class StatsCard extends StatelessWidget {
  const StatsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    
    return Consumer<ScanProvider>(
      builder: (context, scan, _) {
        // Utiliser combinedStats pour inclure les compteurs locaux
        final stats = scan.combinedStats;
        
        return Container(
          decoration: AppTheme.getCardDecoration(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // En-tête avec gradient
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: isDark ? AppTheme.darkGradient : AppTheme.primaryGradient,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.analytics_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Statistiques',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Aperçu de vos scans',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Grille de statistiques
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatItem(
                            context: context,
                            label: 'Total scans',
                            value: '${stats['total_scans'] ?? 0}',
                            icon: Icons.qr_code_scanner_rounded,
                            color: AppTheme.getPrimary(context),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildStatItem(
                            context: context,
                            label: 'Réussis',
                            value: '${stats['successful_scans'] ?? 0}',
                            icon: Icons.check_circle_rounded,
                            color: AppTheme.getSuccess(context),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatItem(
                            context: context,
                            label: 'Traités',
                            value: '${stats['processed_scans'] ?? 0}',
                            icon: Icons.verified_rounded,
                            color: const Color(0xFF5C6BC0),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildStatItem(
                            context: context,
                            label: 'Non traités',
                            value: '${stats['unprocessed_scans'] ?? 0}',
                            icon: Icons.pending_actions_rounded,
                            color: const Color(0xFFFF8F00),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatItem(
                            context: context,
                            label: 'Doublons',
                            value: '${stats['duplicate_attempts'] ?? stats['duplicate_scans'] ?? 0}',
                            icon: Icons.content_copy_rounded,
                            color: AppTheme.getWarning(context),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildStatItem(
                            context: context,
                            label: 'Erreurs',
                            value: '${stats['error_scans'] ?? 0}',
                            icon: Icons.error_rounded,
                            color: AppTheme.getError(context),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Séparateur
              Divider(height: 1, color: AppTheme.getDivider(context)),
              
              // Montant total
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.getSuccess(context).withOpacity(isDark ? 0.2 : 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.account_balance_wallet_rounded,
                        color: AppTheme.getSuccess(context),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Montant total facturé',
                            style: TextStyle(
                              color: AppTheme.getTextMuted(context),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _formatAmount(stats['total_amount']),
                            style: TextStyle(
                              color: AppTheme.getSuccess(context),
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
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

  Widget _buildStatItem({
    required BuildContext context,
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    final isDark = AppTheme.isDark(context);
    
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withOpacity(isDark ? 0.25 : 0.15),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const Spacer(),
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: AppTheme.getTextSecondary(context),
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _formatAmount(dynamic amount) {
    if (amount == null) return '0 FCFA';
    final value = (amount as num).toInt();
    final formatted = value.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]} ',
    );
    return '$formatted FCFA';
  }

  Widget _buildLoadingCard(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    
    return Container(
      decoration: AppTheme.getCardDecoration(context),
      child: Shimmer.fromColors(
        baseColor: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
        highlightColor: isDark ? Colors.grey.shade700 : Colors.grey.shade100,
        child: Column(
          children: [
            Container(
              height: 80,
              decoration: BoxDecoration(
                color: isDark ? AppTheme.darkSurfaceHigher : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: _buildLoadingStatItem(context)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildLoadingStatItem(context)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _buildLoadingStatItem(context)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildLoadingStatItem(context)),
                    ],
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: AppTheme.getDivider(context)),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isDark ? AppTheme.darkSurfaceHigher : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 100, 
                        height: 12, 
                        color: isDark ? AppTheme.darkSurfaceHigher : Colors.white,
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: 140, 
                        height: 20, 
                        color: isDark ? AppTheme.darkSurfaceHigher : Colors.white,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingStatItem(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurfaceHigher : Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }
}
