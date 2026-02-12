/// Scan History Card Widget - Design Professionnel ICP
/// Carte individuelle d'historique avec animations et interactions

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/models/scan_record.dart';
import '../core/theme/app_theme.dart';

/// Carte d'historique de scan avec design moderne
class ScanHistoryCard extends StatefulWidget {
  final ScanRecord record;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool showActions;
  final int index;

  const ScanHistoryCard({
    super.key,
    required this.record,
    this.onTap,
    this.onLongPress,
    this.showActions = true,
    this.index = 0,
  });

  @override
  State<ScanHistoryCard> createState() => _ScanHistoryCardState();
}

class _ScanHistoryCardState extends State<ScanHistoryCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 300 + (widget.index * 50).clamp(0, 300)),
    );

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            setState(() => _isExpanded = !_isExpanded);
            widget.onTap?.call();
          },
          onLongPress: () {
            HapticFeedback.mediumImpact();
            widget.onLongPress?.call();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _getBorderColor(),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: _getShadowColor(),
                  blurRadius: _isExpanded ? 16 : 8,
                  offset: Offset(0, _isExpanded ? 8 : 4),
                ),
              ],
            ),
            child: Column(
              children: [
                // Contenu principal
                _buildMainContent(),

                // Section étendue
                AnimatedCrossFade(
                  firstChild: const SizedBox.shrink(),
                  secondChild: _buildExpandedContent(),
                  crossFadeState: _isExpanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 300),
                ),

                // Actions
                if (widget.showActions && _isExpanded) _buildActions(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    final record = widget.record;
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          // Icône de statut avec animation
          _buildStatusIcon(),
          const SizedBox(width: 14),

          // Informations principales
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Référence et badge
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        record.reference,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _buildStateBadge(),
                  ],
                ),
                const SizedBox(height: 6),

                // Fournisseur
                Row(
                  children: [
                    const Icon(
                      Icons.business_rounded,
                      size: 14,
                      color: AppTheme.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        record.supplierName.isNotEmpty
                            ? record.supplierName
                            : 'Fournisseur inconnu',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),

                // Date et montant
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      record.scanDate != null
                          ? dateFormat.format(record.scanDate!)
                          : 'Date inconnue',
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      record.formattedAmount,
                      style: TextStyle(
                        color: _getAmountColor(),
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Indicateur d'expansion
          const SizedBox(width: 8),
          AnimatedRotation(
            turns: _isExpanded ? 0.5 : 0,
            duration: const Duration(milliseconds: 300),
            child: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: AppTheme.textMuted,
              size: 24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusIcon() {
    final record = widget.record;
    Color color;
    IconData icon;

    switch (record.state) {
      case 'validated':
        color = AppTheme.successColor;
        icon = Icons.check_circle_rounded;
        break;
      case 'duplicate':
        color = AppTheme.warningColor;
        icon = Icons.content_copy_rounded;
        break;
      case 'error':
        color = AppTheme.errorColor;
        icon = Icons.error_rounded;
        break;
      default:
        color = AppTheme.infoColor;
        icon = Icons.pending_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Icon(icon, color: color, size: 26),
    );
  }

  Widget _buildStateBadge() {
    final record = widget.record;
    Color bgColor;
    Color textColor;

    switch (record.state) {
      case 'validated':
        bgColor = AppTheme.successLight;
        textColor = AppTheme.successColor;
        break;
      case 'duplicate':
        bgColor = AppTheme.warningLight;
        textColor = AppTheme.warningColor;
        break;
      case 'error':
        bgColor = AppTheme.errorLight;
        textColor = AppTheme.errorColor;
        break;
      default:
        bgColor = AppTheme.infoLight;
        textColor = AppTheme.infoColor;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        record.stateLabel,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildExpandedContent() {
    final record = widget.record;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        children: [
          const Divider(),
          const SizedBox(height: 12),

          // Grille de détails
          _buildDetailGrid([
            _DetailItem(
              icon: Icons.qr_code_rounded,
              label: 'UUID',
              value: record.qrUuid.length > 20
                  ? '${record.qrUuid.substring(0, 20)}...'
                  : record.qrUuid,
            ),
            _DetailItem(
              icon: Icons.receipt_long_rounded,
              label: 'N° Facture DGI',
              value: record.invoiceNumberDgi.isNotEmpty
                  ? record.invoiceNumberDgi
                  : 'N/A',
            ),
            _DetailItem(
              icon: Icons.badge_rounded,
              label: 'Code DGI',
              value: record.supplierCodeDgi.isNotEmpty
                  ? record.supplierCodeDgi
                  : 'N/A',
            ),
            if (record.invoiceName != null)
              _DetailItem(
                icon: Icons.link_rounded,
                label: 'Facture Odoo',
                value: record.invoiceName!,
              ),
          ]),

          // Message d'erreur si présent
          if (record.errorMessage != null && record.errorMessage!.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.errorLight,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.errorColor.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    color: AppTheme.errorColor,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      record.errorMessage!,
                      style: const TextStyle(
                        color: AppTheme.errorColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailGrid(List<_DetailItem> items) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: items.map((item) => _buildDetailTile(item)).toList(),
    );
  }

  Widget _buildDetailTile(_DetailItem item) {
    return Container(
      constraints: const BoxConstraints(minWidth: 140),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(item.icon, size: 16, color: AppTheme.textMuted),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.label,
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                item.value,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: _buildActionButton(
              icon: Icons.copy_rounded,
              label: 'Copier UUID',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: widget.record.qrUuid));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('UUID copié dans le presse-papier'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildActionButton(
              icon: Icons.share_rounded,
              label: 'Partager',
              isPrimary: true,
              onPressed: () {
                // Implémenter le partage
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool isPrimary = false,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          decoration: BoxDecoration(
            gradient: isPrimary ? AppTheme.primaryGradient : null,
            color: isPrimary ? null : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: isPrimary ? Colors.white : AppTheme.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isPrimary ? Colors.white : AppTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getBorderColor() {
    if (_isExpanded) {
      switch (widget.record.state) {
        case 'validated':
          return AppTheme.successColor.withOpacity(0.3);
        case 'duplicate':
          return AppTheme.warningColor.withOpacity(0.3);
        case 'error':
          return AppTheme.errorColor.withOpacity(0.3);
        default:
          return AppTheme.primaryColor.withOpacity(0.3);
      }
    }
    return Colors.grey.shade200;
  }

  Color _getShadowColor() {
    return _isExpanded
        ? AppTheme.primaryColor.withOpacity(0.1)
        : Colors.black.withOpacity(0.05);
  }

  Color _getAmountColor() {
    switch (widget.record.state) {
      case 'validated':
        return AppTheme.successColor;
      case 'duplicate':
        return AppTheme.warningColor;
      case 'error':
        return AppTheme.errorColor;
      default:
        return AppTheme.textPrimary;
    }
  }
}

class _DetailItem {
  final IconData icon;
  final String label;
  final String value;

  _DetailItem({
    required this.icon,
    required this.label,
    required this.value,
  });
}
