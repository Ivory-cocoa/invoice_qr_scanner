/// Widget bannière pour la file d'attente de scans en arrière-plan
/// Affiche le statut des traitements et permet l'accès à la saisie manuelle

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/services/background_scan_queue.dart';
import '../core/theme/app_theme.dart';
import '../screens/manual_entry_screen.dart';

class QueueStatusBanner extends StatelessWidget {
  const QueueStatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<BackgroundScanQueue>(
      builder: (context, queue, _) {
        if (!queue.hasItems) return const SizedBox.shrink();

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Bannière principale (items actifs)
            if (queue.hasActiveItems) _buildActiveBanner(context, queue),
            // Items nécessitant une saisie manuelle
            ...queue.manualEntryItems.map(
              (item) => _buildManualEntryCard(context, queue, item),
            ),
            // Items complétés récents (auto-dismiss après 5s)
            ...queue.completedItems.map(
              (item) => _buildCompletedCard(context, queue, item),
            ),
            // Items en erreur
            ...queue.failedItems.map(
              (item) => _buildFailedCard(context, queue, item),
            ),
          ],
        );
      },
    );
  }

  Widget _buildActiveBanner(BuildContext context, BackgroundScanQueue queue) {
    final activeItems = queue.activeItems;
    final currentItem = activeItems.first;
    final remaining = activeItems.length - 1;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.infoLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.infoColor.withAlpha(77)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showQueueDetails(context, queue),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: AppTheme.infoColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        remaining > 0
                            ? '${activeItems.length} scan(s) en traitement...'
                            : 'Traitement en cours...',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: AppTheme.infoColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        currentItem.progressMessage ?? 'Vérification DGI...',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                ),
                // Bouton saisie manuelle rapide
                _ManualEntryShortcutButton(
                  onTap: () => _openManualEntryForItem(context, queue, currentItem),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildManualEntryCard(
      BuildContext context, BackgroundScanQueue queue, QueueItem item) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.warningLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.warningColor.withAlpha(77)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openManualEntryForItem(context, queue, item),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppTheme.warningColor.withAlpha(26),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.edit_note_rounded,
                    color: AppTheme.warningColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Saisie manuelle requise',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: AppTheme.warningColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.resultMessage ?? 'Timeout DGI',
                        style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: AppTheme.warningColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompletedCard(
      BuildContext context, BackgroundScanQueue queue, QueueItem item) {
    return _AutoDismissCard(
      key: ValueKey(item.id),
      onDismissed: () => queue.removeItem(item.id),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.successLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.successColor.withAlpha(77)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded,
                color: AppTheme.successColor, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.resultMessage ?? 'Facture créée',
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                  color: AppTheme.successColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () => queue.removeItem(item.id),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              color: Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFailedCard(
      BuildContext context, BackgroundScanQueue queue, QueueItem item) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.errorLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.errorColor.withAlpha(77)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: AppTheme.errorColor, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              item.resultMessage ?? 'Erreur',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 13,
                color: AppTheme.errorColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Retry button
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            onPressed: () => queue.retryItem(item.id),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            color: AppTheme.errorColor,
            tooltip: 'Réessayer',
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => queue.removeItem(item.id),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            color: Colors.grey[400],
          ),
        ],
      ),
    );
  }

  void _showQueueDetails(BuildContext context, BackgroundScanQueue queue) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _QueueDetailsSheet(queue: queue),
    );
  }

  Future<void> _openManualEntryForItem(
      BuildContext context, BackgroundScanQueue queue, QueueItem item) async {
    final result = await Navigator.of(context).push<ManualEntryResult>(
      MaterialPageRoute(
        builder: (context) => ManualEntryScreen(
          qrUrl: item.qrUrl,
          prefillData: item.extractedData,
          verificationDuration: item.verificationDuration,
          timedOut: true,
        ),
      ),
    );

    if (result != null) {
      await queue.submitManualEntry(
        itemId: item.id,
        supplierName: result.supplierName,
        supplierCodeDgi: result.supplierCodeDgi,
        customerName: result.customerName,
        customerCodeDgi: result.customerCodeDgi,
        invoiceNumberDgi: result.invoiceNumberDgi,
        invoiceDate: result.invoiceDate,
        amountTtc: result.amountTtc,
        verificationDuration: result.verificationDuration,
      );
    }
  }
}

/// Bouton raccourci "Saisie manuelle" dans la bannière active
class _ManualEntryShortcutButton extends StatelessWidget {
  final VoidCallback onTap;
  const _ManualEntryShortcutButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.warningColor,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.edit_note_rounded, color: Colors.white, size: 16),
              SizedBox(width: 4),
              Text(
                'Saisir',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Carte qui s'auto-supprime après 5 secondes
class _AutoDismissCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onDismissed;

  const _AutoDismissCard({
    super.key,
    required this.child,
    required this.onDismissed,
  });

  @override
  State<_AutoDismissCard> createState() => _AutoDismissCardState();
}

class _AutoDismissCardState extends State<_AutoDismissCard> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 5), widget.onDismissed);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Bottom sheet avec détails de la file d'attente
class _QueueDetailsSheet extends StatelessWidget {
  final BackgroundScanQueue queue;
  const _QueueDetailsSheet({required this.queue});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: queue,
      builder: (context, _) {
        final items = queue.items;
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
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
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    const Icon(Icons.queue_rounded,
                        color: AppTheme.primaryColor),
                    const SizedBox(width: 8),
                    Text(
                      'File d\'attente (${items.length})',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (queue.completedCount > 0 || queue.failedCount > 0)
                      TextButton.icon(
                        onPressed: queue.clearCompleted,
                        icon: const Icon(Icons.clear_all, size: 18),
                        label: const Text('Vider'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.grey[600],
                        ),
                      ),
                  ],
                ),
              ),
              // Stats row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    _StatChip(
                      icon: Icons.hourglass_top,
                      label: '${queue.activeCount}',
                      color: AppTheme.infoColor,
                    ),
                    const SizedBox(width: 8),
                    _StatChip(
                      icon: Icons.check_circle,
                      label: '${queue.sessionSuccessCount}',
                      color: AppTheme.successColor,
                    ),
                    const SizedBox(width: 8),
                    _StatChip(
                      icon: Icons.edit_note,
                      label: '${queue.needsManualEntryCount}',
                      color: AppTheme.warningColor,
                    ),
                    const SizedBox(width: 8),
                    _StatChip(
                      icon: Icons.error,
                      label: '${queue.sessionErrorCount}',
                      color: AppTheme.errorColor,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Divider(),
              // Items list
              Flexible(
                child: items.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text('Aucun scan en cours'),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.all(16),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final item = items[items.length - 1 - index]; // Recent first
                          return _QueueItemTile(item: item, queue: queue);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

class _QueueItemTile extends StatelessWidget {
  final QueueItem item;
  final BackgroundScanQueue queue;

  const _QueueItemTile({required this.item, required this.queue});

  @override
  Widget build(BuildContext context) {
    final (icon, color, trailing) = _getItemVisuals();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(13),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withAlpha(51)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _stateLabel(),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: color,
                  ),
                ),
                Text(
                  item.progressMessage ?? item.resultMessage ?? item.qrUrl,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  (IconData, Color, Widget?) _getItemVisuals() {
    switch (item.state) {
      case QueueItemState.pending:
        return (Icons.hourglass_empty, Colors.grey, null);
      case QueueItemState.extracting:
        return (
          Icons.sync_rounded,
          AppTheme.infoColor,
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case QueueItemState.submitting:
        return (
          Icons.cloud_upload_rounded,
          AppTheme.primaryColor,
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      case QueueItemState.completed:
        return (Icons.check_circle, AppTheme.successColor, null);
      case QueueItemState.needsManualEntry:
        return (
          Icons.edit_note_rounded,
          AppTheme.warningColor,
          const Icon(Icons.arrow_forward_ios,
              size: 14, color: AppTheme.warningColor),
        );
      case QueueItemState.failed:
        return (
          Icons.error_outline,
          AppTheme.errorColor,
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            onPressed: () => queue.retryItem(item.id),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            color: AppTheme.errorColor,
          ),
        );
    }
  }

  String _stateLabel() {
    switch (item.state) {
      case QueueItemState.pending:
        return 'En attente';
      case QueueItemState.extracting:
        return 'Extraction DGI...';
      case QueueItemState.submitting:
        return 'Création facture...';
      case QueueItemState.completed:
        return 'Terminé';
      case QueueItemState.needsManualEntry:
        return 'Saisie manuelle requise';
      case QueueItemState.failed:
        return 'Erreur';
    }
  }
}
