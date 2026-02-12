/// History List Widget - Design Professionnel ICP
/// Affiche l'historique des factures scannées

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';

import '../core/providers/scan_provider.dart';
import '../core/providers/connectivity_provider.dart';
import '../core/models/scan_record.dart';
import '../core/theme/app_theme.dart';

class HistoryList extends StatelessWidget {
  const HistoryList({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<ScanProvider, ConnectivityProvider>(
      builder: (context, scan, connectivity, _) {
        if (scan.isLoadingHistory) {
          return _buildLoadingList();
        }
        
        if (scan.history.isEmpty) {
          return _buildEmptyState();
        }
        
        return RefreshIndicator(
          onRefresh: () => scan.loadHistory(
            forceRefresh: true,
            isOnline: connectivity.isOnline,
          ),
          color: AppTheme.primaryColor,
          backgroundColor: Colors.white,
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: scan.history.length,
            itemBuilder: (context, index) {
              return _buildHistoryItem(context, scan.history[index], index);
            },
          ),
        );
      },
    );
  }

  Widget _buildHistoryItem(BuildContext context, ScanRecord record, int index) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 300 + (index * 50)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: AppTheme.cardDecoration,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _showRecordDetails(context, record),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header row
                  Row(
                    children: [
                      _buildStateIcon(record.state),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              record.reference,
                              style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.w700,
                                fontSize: 17,
                              ),
                            ),
                            if (record.supplierName.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  record.supplierName,
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                      ),
                      _buildStateBadge(record.state, record.stateLabel),
                    ],
                  ),
                  
                  const SizedBox(height: 14),
                  
                  // Divider avec gradient
                  Container(
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.grey.shade200,
                          Colors.grey.shade300,
                          Colors.grey.shade200,
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 14),
                  
                  // Details row
                  Row(
                    children: [
                      Expanded(
                        child: _buildDetailColumn(
                          'N° Facture DGI',
                          record.invoiceNumberDgi.isNotEmpty 
                              ? record.invoiceNumberDgi 
                              : '-',
                          Icons.receipt_long_rounded,
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 40,
                        color: Colors.grey.shade200,
                      ),
                      Expanded(
                        child: _buildDetailColumn(
                          'Montant',
                          record.formattedAmount,
                          Icons.payments_rounded,
                          isAmount: true,
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // Footer row
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 16,
                          color: AppTheme.textMuted,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          record.scanDate != null 
                              ? dateFormat.format(record.scanDate!) 
                              : '-',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        const Spacer(),
                        if (record.invoiceName != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.link_rounded,
                                  size: 14,
                                  color: AppTheme.primaryColor,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  record.invoiceName!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.primaryColor,
                                    fontWeight: FontWeight.w600,
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
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildStateIcon(String state) {
    IconData icon;
    Color color;
    
    switch (state) {
      case 'done':
        icon = Icons.check_circle_rounded;
        color = AppTheme.successColor;
        break;
      case 'error':
        icon = Icons.error_rounded;
        color = AppTheme.errorColor;
        break;
      case 'duplicate':
        icon = Icons.content_copy_rounded;
        color = AppTheme.warningColor;
        break;
      default:
        icon = Icons.pending_rounded;
        color = Colors.grey;
    }
    
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withOpacity(0.2),
            color.withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Icon(icon, color: color, size: 26),
    );
  }
  
  Widget _buildStateBadge(String state, String label) {
    Color color;
    Color bgColor;
    
    switch (state) {
      case 'done':
        color = AppTheme.successColor;
        bgColor = AppTheme.successColor.withOpacity(0.1);
        break;
      case 'error':
        color = AppTheme.errorColor;
        bgColor = AppTheme.errorColor.withOpacity(0.1);
        break;
      case 'duplicate':
        color = AppTheme.warningColor;
        bgColor = AppTheme.warningColor.withOpacity(0.1);
        break;
      default:
        color = Colors.grey;
        bgColor = Colors.grey.withOpacity(0.1);
    }
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
  
  Widget _buildDetailColumn(String label, String value, IconData icon, {bool isAmount = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: AppTheme.textMuted),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: isAmount ? AppTheme.successColor : AppTheme.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
  
  void _showRecordDetails(BuildContext context, ScanRecord record) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _RecordDetailsSheet(record: record),
    );
  }

  Widget _buildLoadingList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: AppTheme.cardDecoration,
          child: Shimmer.fromColors(
            baseColor: Colors.grey.shade300,
            highlightColor: Colors.grey.shade100,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(width: 150, height: 16, color: Colors.white),
                            const SizedBox(height: 6),
                            Container(width: 100, height: 12, color: Colors.white),
                          ],
                        ),
                      ),
                      Container(
                        width: 70,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(height: 1, color: Colors.white),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(width: 80, height: 10, color: Colors.white),
                            const SizedBox(height: 6),
                            Container(width: 100, height: 14, color: Colors.white),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(width: 60, height: 10, color: Colors.white),
                            const SizedBox(height: 6),
                            Container(width: 90, height: 14, color: Colors.white),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.history_rounded,
                size: 64,
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Aucun scan pour le moment',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Vos factures scannées apparaîtront ici.\nCommencez par scanner un QR code!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: AppTheme.textMuted,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet pour les détails d'un enregistrement
class _RecordDetailsSheet extends StatelessWidget {
  final ScanRecord record;
  
  const _RecordDetailsSheet({required this.record});
  
  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy à HH:mm');
    
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                _buildStateIcon(record.state),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Détails du scan',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      Text(
                        record.stateLabel,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: _getStateColor(record.state),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey.shade100,
                  ),
                ),
              ],
            ),
          ),
          
          const Divider(height: 1),
          
          // Content
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _buildDetailRow('Référence', record.reference, Icons.tag_rounded),
                if (record.supplierName.isNotEmpty)
                  _buildDetailRow('Fournisseur', record.supplierName, Icons.business_rounded),
                if (record.invoiceNumberDgi.isNotEmpty)
                  _buildDetailRow('N° Facture DGI', record.invoiceNumberDgi, Icons.receipt_long_rounded),
                _buildDetailRow('Montant', record.formattedAmount, Icons.payments_rounded, highlight: true),
                if (record.invoiceName != null)
                  _buildDetailRow('Facture Odoo', record.invoiceName!, Icons.link_rounded),
                if (record.scanDate != null)
                  _buildDetailRow('Date du scan', dateFormat.format(record.scanDate!), Icons.schedule_rounded),
              ],
            ),
          ),
          
          // Actions
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.check_rounded),
                label: const Text(
                  'Fermer',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildStateIcon(String state) {
    IconData icon;
    Color color;
    
    switch (state) {
      case 'done':
        icon = Icons.check_circle_rounded;
        color = AppTheme.successColor;
        break;
      case 'error':
        icon = Icons.error_rounded;
        color = AppTheme.errorColor;
        break;
      case 'duplicate':
        icon = Icons.content_copy_rounded;
        color = AppTheme.warningColor;
        break;
      default:
        icon = Icons.pending_rounded;
        color = Colors.grey;
    }
    
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withOpacity(0.2), color.withOpacity(0.1)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, color: color, size: 32),
    );
  }
  
  Color _getStateColor(String state) {
    switch (state) {
      case 'done': return AppTheme.successColor;
      case 'error': return AppTheme.errorColor;
      case 'duplicate': return AppTheme.warningColor;
      default: return Colors.grey;
    }
  }
  
  Widget _buildDetailRow(String label, String value, IconData icon, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (highlight ? AppTheme.successColor : AppTheme.primaryColor).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 20,
              color: highlight ? AppTheme.successColor : AppTheme.primaryColor,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: highlight ? AppTheme.successColor : AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
