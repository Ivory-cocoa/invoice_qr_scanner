/// InvoiceStatusSheet — Modal bottom sheet présentant le statut OT
/// d'une facture qui vient d'être scannée (ou sélectionnée).
///
/// Trois cas sont gérés :
///   - Cas A : aucune liaison (`links_count == 0`)
///     → bandeau information + bouton « Lier maintenant ».
///   - Cas B : facture totalement allouée (`remaining_amount <= 0`)
///     → liste des OTs liés + bouton secondaire « Voir / ajouter une liaison ».
///   - Cas C : facture partiellement allouée
///     → liste des OTs + mini résumé (Facture / Alloué / Restant) avec
///       barre de progression, puis bouton « Ajouter une liaison »
///       qui pré-remplit le montant restant.
///
/// Le sheet renvoie un [InvoiceStatusAction] décrivant ce que l'appelant
/// doit faire (ouvrir l'écran de liaison, fermer, etc.).
library;

import 'package:flutter/material.dart';

import '../core/services/share_service.dart';
import '../core/theme/app_theme.dart';

/// Action choisie par l'utilisateur dans le bottom sheet.
enum InvoiceStatusAction {
  /// Fermer sans action (utilisateur a tapé "Fermer" ou hors du sheet).
  close,

  /// Ouvrir l'écran de liaison OT. Le montant à pré-remplir est
  /// [InvoiceStatusResult.amountToAllocate].
  link,
}

class InvoiceStatusResult {
  final InvoiceStatusAction action;

  /// Montant à pré-remplir dans l'écran de liaison (utilisé en Cas C
  /// pour le « remaining », ou montant total en Cas A/B).
  final double? amountToAllocate;

  const InvoiceStatusResult(this.action, {this.amountToAllocate});
}

/// Affiche le sheet. Retourne le résultat de l'interaction (jamais null :
/// fermeture par geste = `close`).
Future<InvoiceStatusResult> showInvoiceStatusSheet(
  BuildContext context, {
  required Map<String, dynamic> status,
}) async {
  final result = await showModalBottomSheet<InvoiceStatusResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _InvoiceStatusSheet(status: status),
  );
  return result ?? const InvoiceStatusResult(InvoiceStatusAction.close);
}

class _InvoiceStatusSheet extends StatelessWidget {
  final Map<String, dynamic> status;

  const _InvoiceStatusSheet({required this.status});

  @override
  Widget build(BuildContext context) {
    final linksCount = (status['links_count'] as num?)?.toInt() ?? 0;
    final invoiceAmount = (status['invoice_amount'] as num?)?.toDouble() ?? 0.0;
    final linkedAmount =
        (status['total_linked_amount'] as num?)?.toDouble() ?? 0.0;
    final remaining = (status['remaining_amount'] as num?)?.toDouble() ?? 0.0;
    final currency = (status['currency'] as String?) ?? 'XOF';
    final invoiceNum = (status['invoice_number_dgi'] as String?) ?? '';
    final supplier = (status['supplier_name'] as String?) ?? '';
    final links = (status['links'] as List?) ?? const [];

    // Détermination du cas
    final _Case kase;
    if (linksCount == 0) {
      kase = _Case.unlinked;
    } else if (remaining <= 0.0001) {
      kase = _Case.fullyLinked;
    } else {
      kase = _Case.partiallyLinked;
    }

    final mediaHeight = MediaQuery.of(context).size.height;

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: mediaHeight * 0.85),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.getSurfaceElevated(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.getDivider(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              _buildHeader(context, kase, invoiceNum, supplier),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSummaryCard(
                        context: context,
                        kase: kase,
                        invoiceAmount: invoiceAmount,
                        linkedAmount: linkedAmount,
                        remaining: remaining,
                        currency: currency,
                      ),
                      if (links.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          'Liaisons existantes ($linksCount)',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.getTextSecondary(context),
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...links.map((l) => _buildLinkCard(
                              context,
                              l as Map<String, dynamic>,
                              currency: currency,
                            )),
                      ],
                    ],
                  ),
                ),
              ),
              const Divider(height: 1),
              _buildActions(context, kase, remaining, invoiceAmount),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
      BuildContext context, _Case kase, String invoiceNum, String supplier) {
    final IconData icon;
    final Color color;
    final String title;
    switch (kase) {
      case _Case.unlinked:
        icon = Icons.add_link_rounded;
        color = AppTheme.warningColor;
        title = 'Facture non liée';
        break;
      case _Case.fullyLinked:
        icon = Icons.check_circle_rounded;
        color = AppTheme.successColor;
        title = 'Facture entièrement liée';
        break;
      case _Case.partiallyLinked:
        icon = Icons.pie_chart_rounded;
        color = AppTheme.infoColor;
        title = 'Facture partiellement liée';
        break;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.getTextPrimary(context),
                  ),
                ),
                if (invoiceNum.isNotEmpty || supplier.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (invoiceNum.isNotEmpty) 'N° $invoiceNum',
                      if (supplier.isNotEmpty) supplier,
                    ].join(' • '),
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.getTextMuted(context),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Partager',
            icon: Icon(Icons.share_outlined, color: AppTheme.getTextSecondary(context)),
            onPressed: () async {
              try {
                await shareScanStatus(status);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Erreur partage : $e')),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard({
    required BuildContext context,
    required _Case kase,
    required double invoiceAmount,
    required double linkedAmount,
    required double remaining,
    required String currency,
  }) {
    final progress = invoiceAmount > 0
        ? (linkedAmount / invoiceAmount).clamp(0.0, 1.0)
        : 0.0;
    final Color barColor;
    switch (kase) {
      case _Case.unlinked:
        barColor = AppTheme.warningColor;
        break;
      case _Case.fullyLinked:
        barColor = AppTheme.successColor;
        break;
      case _Case.partiallyLinked:
        barColor = AppTheme.infoColor;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.getSurfaceLight(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.getDivider(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildAmountRow('Facture', invoiceAmount, currency,
              bold: true, color: AppTheme.getTextPrimary(context)),
          const SizedBox(height: 6),
          _buildAmountRow('Alloué', linkedAmount, currency,
              color: AppTheme.getTextSecondary(context)),
          const SizedBox(height: 6),
          _buildAmountRow(
            'Restant',
            remaining,
            currency,
            bold: true,
            color: remaining > 0.0001 ? AppTheme.warningColor : AppTheme.successColor,
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: AppTheme.getDivider(context),
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmountRow(String label, double amount, String currency,
      {bool bold = false, required Color color}) {
    final style = TextStyle(
      fontSize: 14,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
      color: color,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(_formatAmount(amount, currency), style: style),
      ],
    );
  }

  Widget _buildLinkCard(BuildContext context, Map<String, dynamic> link, {required String currency}) {
    final otRef = (link['transit_order_ref'] as String?) ?? '';
    final costLabel = (link['cost_type_label'] as String?) ?? '';
    final amount = (link['amount'] as num?)?.toDouble() ?? 0.0;
    final stateLabel = (link['state_label'] as String?) ?? '';
    final linkCurrency = (link['currency'] as String?) ?? currency;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.getSurfaceElevated(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.getDivider(context)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.primarySurface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.local_shipping_outlined,
              size: 18,
              color: AppTheme.primaryColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  otRef.isNotEmpty ? otRef : 'OT',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.getTextPrimary(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (costLabel.isNotEmpty || stateLabel.isNotEmpty)
                  Text(
                    [
                      if (costLabel.isNotEmpty) costLabel,
                      if (stateLabel.isNotEmpty) stateLabel,
                    ].join(' • '),
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.getTextMuted(context),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatAmount(amount, linkCurrency),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppTheme.getTextPrimary(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context, _Case kase, double remaining,
      double invoiceAmount) {
    // Cas A : Lier maintenant (montant total)
    // Cas B : Voir / ajouter une liaison (montant 0, l'utilisateur saisira)
    // Cas C : Ajouter une liaison (remaining)
    final String primaryLabel;
    final IconData primaryIcon;
    final double? amountToAllocate;

    switch (kase) {
      case _Case.unlinked:
        primaryLabel = 'Lier maintenant';
        primaryIcon = Icons.add_link_rounded;
        amountToAllocate = invoiceAmount > 0 ? invoiceAmount : null;
        break;
      case _Case.fullyLinked:
        primaryLabel = 'Ajouter une liaison';
        primaryIcon = Icons.add_circle_outline_rounded;
        amountToAllocate = null;
        break;
      case _Case.partiallyLinked:
        primaryLabel = 'Ajouter une liaison';
        primaryIcon = Icons.add_circle_outline_rounded;
        amountToAllocate = remaining > 0 ? remaining : null;
        break;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(
                const InvoiceStatusResult(InvoiceStatusAction.close),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                foregroundColor: AppTheme.getTextSecondary(context),
                side: BorderSide(color: AppTheme.getDivider(context)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Fermer'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(
                InvoiceStatusResult(
                  InvoiceStatusAction.link,
                  amountToAllocate: amountToAllocate,
                ),
              ),
              icon: Icon(primaryIcon, size: 18),
              label: Text(
                primaryLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatAmount(double v, String currency) {
    final s = v.toStringAsFixed(0);
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return '${buf.toString()} $currency';
  }
}

enum _Case { unlinked, fullyLinked, partiallyLinked }
