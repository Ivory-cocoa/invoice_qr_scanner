/// Enhanced Stats Dashboard Widget - Design Professionnel ICP
/// Dashboard avec graphiques et statistiques avancées

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';

import '../core/providers/scan_provider.dart';
import '../core/theme/app_theme.dart';

/// Dashboard de statistiques amélioré avec graphiques
class EnhancedStatsDashboard extends StatefulWidget {
  final bool showChart;
  final bool compact;

  const EnhancedStatsDashboard({
    super.key,
    this.showChart = true,
    this.compact = false,
  });

  @override
  State<EnhancedStatsDashboard> createState() => _EnhancedStatsDashboardState();
}

class _EnhancedStatsDashboardState extends State<EnhancedStatsDashboard>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ScanProvider>(
      builder: (context, scan, _) {
        final stats = scan.stats;

        if (stats == null) {
          return _buildLoadingSkeleton();
        }

        final total = (stats['total_scans'] as num?)?.toInt() ?? 0;
        final success = (stats['successful_scans'] as num?)?.toInt() ?? 0;
        final duplicates = (stats['duplicate_scans'] as num?)?.toInt() ?? 0;
        final errors = (stats['error_scans'] as num?)?.toInt() ?? 0;
        final amount = (stats['total_amount'] as num?)?.toDouble() ?? 0.0;

        return AnimatedBuilder(
          animation: _animation,
          builder: (context, child) {
            return Opacity(
              opacity: _animation.value,
              child: child,
            );
          },
          child: Container(
            decoration: AppTheme.cardDecoration,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // En-tête
                _buildHeader(total),

                // KPIs en grille
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: widget.compact
                      ? _buildCompactKPIs(success, duplicates, errors)
                      : _buildFullKPIs(success, duplicates, errors),
                ),

                // Graphique circulaire
                if (widget.showChart && total > 0) ...[
                  const Divider(height: 1),
                  _buildPieChart(success, duplicates, errors),
                ],

                // Montant total
                const Divider(height: 1),
                _buildAmountSection(amount),

                // Taux de réussite
                if (!widget.compact) ...[
                  const Divider(height: 1),
                  _buildSuccessRateSection(total, success),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(int total) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
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
              Icons.dashboard_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tableau de bord',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '$total scans enregistrés',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          // Badge animé
          _buildAnimatedBadge(total),
        ],
      ),
    );
  }

  Widget _buildAnimatedBadge(int total) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: total.toDouble()),
      duration: const Duration(milliseconds: 1500),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            value.toInt().toString(),
            style: const TextStyle(
              color: AppTheme.primaryColor,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        );
      },
    );
  }

  Widget _buildCompactKPIs(int success, int duplicates, int errors) {
    return Row(
      children: [
        Expanded(
          child: _buildKPITile(
            value: success,
            label: 'Réussis',
            icon: Icons.check_circle_rounded,
            color: AppTheme.successColor,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildKPITile(
            value: duplicates,
            label: 'Doublons',
            icon: Icons.content_copy_rounded,
            color: AppTheme.warningColor,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildKPITile(
            value: errors,
            label: 'Erreurs',
            icon: Icons.error_rounded,
            color: AppTheme.errorColor,
          ),
        ),
      ],
    );
  }

  Widget _buildFullKPIs(int success, int duplicates, int errors) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildKPICard(
                value: success,
                label: 'Scans réussis',
                subtitle: 'Factures créées',
                icon: Icons.check_circle_rounded,
                color: AppTheme.successColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildKPICard(
                value: duplicates,
                label: 'Doublons',
                subtitle: 'Déjà enregistrés',
                icon: Icons.content_copy_rounded,
                color: AppTheme.warningColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildKPICard(
          value: errors,
          label: 'Erreurs',
          subtitle: 'Scans échoués',
          icon: Icons.error_outline_rounded,
          color: AppTheme.errorColor,
          fullWidth: true,
        ),
      ],
    );
  }

  Widget _buildKPITile({
    required int value,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: const Duration(milliseconds: 1200),
      curve: Curves.easeOutCubic,
      builder: (context, animValue, _) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 22),
              const SizedBox(height: 6),
              Text(
                animValue.toInt().toString(),
                style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  color: color.withOpacity(0.8),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildKPICard({
    required int value,
    required String label,
    required String subtitle,
    required IconData icon,
    required Color color,
    bool fullWidth = false,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: const Duration(milliseconds: 1200),
      curve: Curves.easeOutCubic,
      builder: (context, animValue, _) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withOpacity(0.15)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      animValue.toInt().toString(),
                      style: TextStyle(
                        color: color,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      label,
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12,
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

  Widget _buildPieChart(int success, int duplicates, int errors) {
    final total = success + duplicates + errors;
    if (total == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          // Graphique circulaire animé
          Expanded(
            flex: 2,
            child: AspectRatio(
              aspectRatio: 1,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 1500),
                curve: Curves.easeOutCubic,
                builder: (context, progress, _) {
                  return CustomPaint(
                    painter: _PieChartPainter(
                      success: success,
                      duplicates: duplicates,
                      errors: errors,
                      progress: progress,
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 20),
          // Légende
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLegendItem(
                  'Réussis',
                  success,
                  total,
                  AppTheme.successColor,
                ),
                const SizedBox(height: 10),
                _buildLegendItem(
                  'Doublons',
                  duplicates,
                  total,
                  AppTheme.warningColor,
                ),
                const SizedBox(height: 10),
                _buildLegendItem(
                  'Erreurs',
                  errors,
                  total,
                  AppTheme.errorColor,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String label, int value, int total, Color color) {
    final percentage = total > 0 ? (value / total * 100) : 0.0;

    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
        Text(
          '${percentage.toStringAsFixed(1)}%',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildAmountSection(double amount) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: AppTheme.accentGradient,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.accentColor.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.account_balance_wallet_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Montant total facturé',
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: amount),
                  duration: const Duration(milliseconds: 1500),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) {
                    return Text(
                      _formatAmount(value),
                      style: const TextStyle(
                        color: AppTheme.accentColor,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessRateSection(int total, int success) {
    final rate = total > 0 ? (success / total * 100) : 0.0;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Taux de réussite',
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: rate),
                duration: const Duration(milliseconds: 1500),
                curve: Curves.easeOutCubic,
                builder: (context, value, _) {
                  return Text(
                    '${value.toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: _getRateColor(value),
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: rate / 100),
            duration: const Duration(milliseconds: 1500),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: value,
                  minHeight: 10,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _getRateColor(value * 100),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Color _getRateColor(double rate) {
    if (rate >= 80) return AppTheme.successColor;
    if (rate >= 50) return AppTheme.warningColor;
    return AppTheme.errorColor;
  }

  Widget _buildLoadingSkeleton() {
    return Container(
      decoration: AppTheme.cardDecoration,
      child: Shimmer.fromColors(
        baseColor: Colors.grey.shade300,
        highlightColor: Colors.grey.shade100,
        child: Column(
          children: [
            Container(
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 100,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          height: 100,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatAmount(double amount) {
    if (amount >= 1000000000) {
      return '${(amount / 1000000000).toStringAsFixed(1)} Mrd FCFA';
    } else if (amount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(1)} M FCFA';
    } else if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(0)} K FCFA';
    }
    return '${amount.toStringAsFixed(0)} FCFA';
  }
}

/// Painter personnalisé pour le graphique circulaire
class _PieChartPainter extends CustomPainter {
  final int success;
  final int duplicates;
  final int errors;
  final double progress;

  _PieChartPainter({
    required this.success,
    required this.duplicates,
    required this.errors,
    required this.progress,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final total = success + duplicates + errors;
    if (total == 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 * 0.85;
    final strokeWidth = radius * 0.35;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromCircle(center: center, radius: radius);
    const startAngle = -math.pi / 2;

    final successAngle = (success / total) * 2 * math.pi * progress;
    final duplicatesAngle = (duplicates / total) * 2 * math.pi * progress;
    final errorsAngle = (errors / total) * 2 * math.pi * progress;

    // Dessiner les segments
    double currentAngle = startAngle;

    if (success > 0) {
      paint.color = AppTheme.successColor;
      canvas.drawArc(rect, currentAngle, successAngle, false, paint);
      currentAngle += successAngle;
    }

    if (duplicates > 0) {
      paint.color = AppTheme.warningColor;
      canvas.drawArc(rect, currentAngle, duplicatesAngle, false, paint);
      currentAngle += duplicatesAngle;
    }

    if (errors > 0) {
      paint.color = AppTheme.errorColor;
      canvas.drawArc(rect, currentAngle, errorsAngle, false, paint);
    }

    // Cercle central
    final centerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius - strokeWidth * 0.6, centerPaint);

    // Texte central
    final textPainter = TextPainter(
      text: TextSpan(
        text: total.toString(),
        style: const TextStyle(
          color: AppTheme.textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        center.dx - textPainter.width / 2,
        center.dy - textPainter.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(_PieChartPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.success != success ||
        oldDelegate.duplicates != duplicates ||
        oldDelegate.errors != errors;
  }
}
