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
          return _buildLoadingList(context);
        }
        
        if (scan.history.isEmpty) {
          return _buildEmptyState(context);
        }
        
        return RefreshIndicator(
          onRefresh: () => scan.loadHistory(
            forceRefresh: true,
            isOnline: connectivity.isOnline,
          ),
          color: AppTheme.getPrimary(context),
          backgroundColor: AppTheme.getSurfaceElevated(context),
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
                      _buildStateIcon(context, record.state),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              record.reference,
                              style: TextStyle(
                                color: AppTheme.getTextPrimary(context),
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
                                    color: AppTheme.getTextSecondary(context),
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
                      _buildStateBadge(context, record.state, record.stateLabel),
                    ],
                  ),
                  
                  const SizedBox(height: 14),
                  
                  // Divider avec gradient
                  Container(
                    height: 1,
                    decoration: BoxDecoration(
                      color: AppTheme.getDivider(context),
                    ),
                  ),
                  
                  const SizedBox(height: 14),
                  
                  // Details row
                  Row(
                    children: [
                      Expanded(
                        child: _buildDetailColumn(
                          context,
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
                        color: AppTheme.getDivider(context),
                      ),
                      Expanded(
                        child: _buildDetailColumn(
                          context,
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
                      color: AppTheme.getSurfaceLight(context),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 16,
                          color: AppTheme.getTextMuted(context),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          record.scanDate != null 
                              ? dateFormat.format(record.scanDate!) 
                              : '-',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.getTextMuted(context),
                          ),
                        ),
                        const Spacer(),
                        if (record.isProcessed)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: AppTheme.getPrimary(context).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: AppTheme.getPrimary(context).withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.verified_rounded,
                                  size: 12,
                                  color: AppTheme.getPrimary(context),
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  'Traité',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.getPrimary(context),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (record.invoiceName != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.getPrimary(context).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.link_rounded,
                                  size: 14,
                                  color: AppTheme.getPrimary(context),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  record.invoiceName!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.getPrimary(context),
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
  
  Widget _buildStateIcon(BuildContext context, String state) {
    IconData icon;
    Color color;
    
    switch (state) {
      case 'done':
        icon = Icons.check_circle_rounded;
        color = AppTheme.getSuccess(context);
        break;
      case 'processed':
        icon = Icons.verified_rounded;
        color = AppTheme.getPrimary(context);
        break;
      case 'error':
        icon = Icons.error_rounded;
        color = AppTheme.getError(context);
        break;
      case 'duplicate':
        icon = Icons.content_copy_rounded;
        color = AppTheme.getWarning(context);
        break;
      default:
        icon = Icons.pending_rounded;
        color = AppTheme.getTextMuted(context);
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
  
  Widget _buildStateBadge(BuildContext context, String state, String label) {
    Color color;
    Color bgColor;
    
    switch (state) {
      case 'done':
        color = AppTheme.getSuccess(context);
        bgColor = AppTheme.getSuccess(context).withOpacity(0.1);
        break;
      case 'processed':
        color = AppTheme.getPrimary(context);
        bgColor = AppTheme.getPrimary(context).withOpacity(0.1);
        break;
      case 'error':
        color = AppTheme.getError(context);
        bgColor = AppTheme.getError(context).withOpacity(0.1);
        break;
      case 'duplicate':
        color = AppTheme.getWarning(context);
        bgColor = AppTheme.getWarning(context).withOpacity(0.1);
        break;
      default:
        color = AppTheme.getTextMuted(context);
        bgColor = AppTheme.getTextMuted(context).withOpacity(0.1);
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
  
  Widget _buildDetailColumn(BuildContext context, String label, String value, IconData icon, {bool isAmount = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: AppTheme.getTextMuted(context)),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: AppTheme.getTextMuted(context),
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
              color: isAmount ? AppTheme.getSuccess(context) : AppTheme.getTextPrimary(context),
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

  Widget _buildLoadingList(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: AppTheme.cardDecoration,
          child: Shimmer.fromColors(
            baseColor: AppTheme.isDark(context) ? const Color(0xFF3A3A3A) : Colors.grey.shade300,
            highlightColor: AppTheme.isDark(context) ? const Color(0xFF4A4A4A) : Colors.grey.shade100,
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

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.getPrimary(context).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.history_rounded,
                size: 64,
                color: AppTheme.getPrimary(context),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Aucun scan pour le moment',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppTheme.getTextPrimary(context),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Vos factures scannées apparaîtront ici.\nCommencez par scanner un QR code!',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: AppTheme.getTextMuted(context),
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
      decoration: BoxDecoration(
        color: AppTheme.getSurfaceElevated(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
              color: AppTheme.getDivider(context),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                _buildStateIcon(context, record.state),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Détails du scan',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.getTextPrimary(context),
                        ),
                      ),
                      Text(
                        record.stateLabel,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: _getStateColor(context, record.state),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.getSurfaceLight(context),
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
                _buildDetailRow(context, 'Référence', record.reference, Icons.tag_rounded),
                if (record.supplierName.isNotEmpty)
                  _buildDetailRow(context, 'Fournisseur', record.supplierName, Icons.business_rounded),
                if (record.invoiceNumberDgi.isNotEmpty)
                  _buildDetailRow(context, 'N° Facture DGI', record.invoiceNumberDgi, Icons.receipt_long_rounded),
                _buildDetailRow(context, 'Montant', record.formattedAmount, Icons.payments_rounded, highlight: true),
                if (record.invoiceName != null)
                  _buildDetailRow(context, 'Facture Odoo', record.invoiceName!, Icons.link_rounded),
                if (record.scanDate != null)
                  _buildDetailRow(context, 'Date du scan', dateFormat.format(record.scanDate!), Icons.schedule_rounded),
                if (record.isProcessed && record.processedBy != null)
                  _buildDetailRow(context, 'Traité par', record.processedBy!, Icons.verified_rounded),
                if (record.isProcessed && record.processedDate != null)
                  _buildDetailRow(context, 'Date de traitement', dateFormat.format(record.processedDate!), Icons.event_available_rounded),
              ],
            ),
          ),
          
          // Actions
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
            child: Column(
              children: [
                // Bouton marquer comme traité / non traité
                if (record.state == 'done' || record.state == 'processed')
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: _ProcessToggleButton(record: record),
                    ),
                  ),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.getPrimary(context),
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
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildStateIcon(BuildContext context, String state) {
    IconData icon;
    Color color;
    
    switch (state) {
      case 'done':
        icon = Icons.check_circle_rounded;
        color = AppTheme.getSuccess(context);
        break;
      case 'processed':
        icon = Icons.verified_rounded;
        color = AppTheme.getPrimary(context);
        break;
      case 'error':
        icon = Icons.error_rounded;
        color = AppTheme.getError(context);
        break;
      case 'duplicate':
        icon = Icons.content_copy_rounded;
        color = AppTheme.getWarning(context);
        break;
      default:
        icon = Icons.pending_rounded;
        color = AppTheme.getTextMuted(context);
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
  
  Color _getStateColor(BuildContext context, String state) {
    switch (state) {
      case 'done': return AppTheme.getSuccess(context);
      case 'processed': return AppTheme.getPrimary(context);
      case 'error': return AppTheme.getError(context);
      case 'duplicate': return AppTheme.getWarning(context);
      default: return AppTheme.getTextMuted(context);
    }
  }
  
  Widget _buildDetailRow(BuildContext context, String label, String value, IconData icon, {bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (highlight ? AppTheme.getSuccess(context) : AppTheme.getPrimary(context)).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 20,
              color: highlight ? AppTheme.getSuccess(context) : AppTheme.getPrimary(context),
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
                    color: AppTheme.getTextMuted(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: highlight ? AppTheme.getSuccess(context) : AppTheme.getTextPrimary(context),
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

/// Bouton toggle pour marquer un scan comme traité / non traité
class _ProcessToggleButton extends StatefulWidget {
  final ScanRecord record;
  
  const _ProcessToggleButton({required this.record});
  
  @override
  State<_ProcessToggleButton> createState() => _ProcessToggleButtonState();
}

class _ProcessToggleButtonState extends State<_ProcessToggleButton> {
  bool _isLoading = false;
  
  Future<void> _toggleProcessed() async {
    setState(() => _isLoading = true);
    
    final scan = context.read<ScanProvider>();
    bool success;
    
    if (widget.record.state == 'done') {
      success = await scan.markAsProcessed(widget.record.id);
    } else {
      success = await scan.markAsUnprocessed(widget.record.id);
    }
    
    if (mounted) {
      setState(() => _isLoading = false);
      
      if (success) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  widget.record.state == 'done' 
                      ? Icons.verified_rounded 
                      : Icons.undo_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(
                  widget.record.state == 'done'
                      ? 'Scan marqué comme traité'
                      : 'Scan remis à non traité',
                ),
              ],
            ),
            backgroundColor: widget.record.state == 'done' 
                ? AppTheme.getPrimary(context) 
                : AppTheme.getWarning(context),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.error_rounded, color: Colors.white, size: 20),
                SizedBox(width: 12),
                Text('Erreur lors du changement de statut'),
              ],
            ),
            backgroundColor: AppTheme.getError(context),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    final isProcessed = widget.record.state == 'processed';
    
    return ElevatedButton.icon(
      onPressed: _isLoading ? null : _toggleProcessed,
      style: ElevatedButton.styleFrom(
        backgroundColor: isProcessed 
            ? Colors.orange.shade50 
            : AppTheme.getPrimary(context).withOpacity(0.1),
        foregroundColor: isProcessed 
            ? Colors.orange.shade700 
            : AppTheme.getPrimary(context),
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isProcessed 
                ? Colors.orange.shade300 
                : AppTheme.getPrimary(context).withOpacity(0.3),
          ),
        ),
      ),
      icon: _isLoading
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: isProcessed ? Colors.orange.shade700 : AppTheme.getPrimary(context),
              ),
            )
          : Icon(isProcessed ? Icons.undo_rounded : Icons.verified_rounded),
      label: Text(
        _isLoading
            ? 'Traitement...'
            : (isProcessed ? 'Remettre non traité' : 'Marquer comme traité'),
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    );
  }
}
