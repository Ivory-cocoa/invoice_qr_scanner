/// Scan Result Dialog - Design Professionnel ICP
/// Affiche le résultat d'un scan QR avec un design moderne
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/providers/scan_provider.dart';
import '../core/providers/auth_provider.dart';
import '../core/models/scan_record.dart';
import '../core/theme/app_theme.dart';

class ScanResultDialog extends StatelessWidget {
  final ScanState state;
  final String? message;
  final ScanRecord? scanRecord;
  
  const ScanResultDialog({
    super.key,
    required this.state,
    this.message,
    this.scanRecord,
  });
  
  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;
    final isDark = AppTheme.isDark(context);
    
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.fromLTRB(16, 24, 16, 24 + bottomPadding + 32),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkSurfaceElevated : Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.2),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header avec icône
            _buildHeader(context),
            
            // Contenu
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  children: [
                    // Message d'erreur détaillé pour les erreurs
                    if (state == ScanState.error && message != null)
                      _buildErrorMessageBox(context, message!),
                    
                    // Message simple pour les autres états
                    if (state != ScanState.error && message != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          message!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppTheme.getTextPrimary(context),
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                          ),
                        ),
                      ),
                    
                    if (scanRecord != null) _buildRecordDetails(context),

                    if (scanRecord != null && scanRecord!.hasOtLinks)
                      _buildOtLinksSection(context),
                    
                    const SizedBox(height: 24),
                    
                    // Actions
                    _buildActions(context),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildHeader(BuildContext context) {
    Color color;
    IconData icon;
    String title;
    String subtitle;
    
    switch (state) {
      case ScanState.success:
        color = AppTheme.getSuccess(context);
        icon = Icons.check_circle_rounded;
        title = 'Succès!';
        subtitle = 'Facture créée avec succès';
        break;
      case ScanState.duplicate:
        color = AppTheme.getWarning(context);
        icon = Icons.content_copy_rounded;
        title = 'Doublon détecté';
        subtitle = scanRecord != null && scanRecord!.duplicateCount > 0
            ? 'Tentative #${scanRecord!.duplicateCount + 1}'
            : 'Cette facture existe déjà';
        break;
      case ScanState.alreadyProcessed:
        color = AppTheme.getWarning(context);
        icon = Icons.published_with_changes_rounded;
        title = 'Déjà traitée';
        subtitle = scanRecord != null && scanRecord!.reprocessAttemptCount > 0
            ? 'Tentative de retraitement #${scanRecord!.reprocessAttemptCount}'
            : 'Cette facture a déjà été traitée';
        break;
      case ScanState.error:
        color = AppTheme.getError(context);
        icon = Icons.error_rounded;
        title = 'Erreur';
        subtitle = 'Une erreur s\'est produite';
        break;
      default:
        color = AppTheme.getPrimary(context);
        icon = Icons.info_rounded;
        title = 'Information';
        subtitle = 'Résultat du scan';
    }
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, color.withValues(alpha: 0.8)],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Icône animée
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 40),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildRecordDetails(BuildContext context) {
    final record = scanRecord!;
    final dateFormat = DateFormat('dd/MM/yyyy à HH:mm');
    final isDark = AppTheme.isDark(context);
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurfaceHigher : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.getDivider(context)),
      ),
      child: Column(
        children: [
          if (record.supplierName.isNotEmpty)
            _buildDetailRow(
              context,
              'Fournisseur',
              record.supplierName,
              Icons.business_rounded,
            ),
          
          if (record.invoiceNumberDgi.isNotEmpty)
            _buildDetailRow(
              context,
              'N° Facture DGI',
              record.invoiceNumberDgi,
              Icons.receipt_long_rounded,
            ),
          
          if (record.amountTtc > 0)
            _buildDetailRow(
              context,
              'Montant',
              record.formattedAmount,
              Icons.payments_rounded,
              isHighlight: true,
            ),
          
          if (record.invoiceName != null)
            _buildDetailRow(
              context,
              'Facture Odoo',
              record.invoiceName!,
              Icons.link_rounded,
            ),
          
          if (record.scanDate != null)
            _buildDetailRow(
              context,
              'Date du scan',
              dateFormat.format(record.scanDate!),
              Icons.schedule_rounded,
              isLast: !record.isProcessed && record.reprocessAttemptCount == 0,
            ),
          
          // Infos de traitement (qui a déjà traité + date)
          if (record.isProcessed && record.processedBy != null)
            _buildDetailRow(
              context,
              'Traité par',
              record.processedBy!,
              Icons.person_rounded,
            ),
          
          if (record.isProcessed && record.processedDate != null)
            _buildDetailRow(
              context,
              'Date de traitement',
              dateFormat.format(record.processedDate!),
              Icons.event_available_rounded,
            ),
          
          // Compteur de tentatives de retraitement
          if (record.reprocessAttemptCount > 0)
            _buildDetailRow(
              context,
              'Tentatives de retraitement',
              '${record.reprocessAttemptCount}',
              Icons.replay_rounded,
              isHighlight: true,
              isLast: true,
            ),
        ],
      ),
    );
  }
  
  /// Section listant les Ordres de Transit (OT) auxquels le scan est rattaché.
  /// Un scan pouvant être lié à plusieurs OT, chaque lien est affiché sous
  /// forme de puce (référence OT + type de coût + montant).
  Widget _buildOtLinksSection(BuildContext context) {
    final links = scanRecord!.otLinks;
    final primaryColor = AppTheme.getPrimary(context);

    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: AppTheme.isDark(context) ? 0.16 : 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_shipping_rounded, size: 18, color: primaryColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  links.length > 1
                      ? 'Lié à ${links.length} Ordres de Transit'
                      : 'Lié à un Ordre de Transit',
                  style: TextStyle(
                    color: primaryColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: links.map((link) => _buildOtChip(context, link)).toList(),
          ),
        ],
      ),
    );
  }

  /// Puce représentant un lien scan → OT.
  Widget _buildOtChip(BuildContext context, OtLink link) {
    final primaryColor = AppTheme.getPrimary(context);
    final ref = link.otReference.isNotEmpty
        ? link.otReference
        : 'OT #${link.otId ?? '?'}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.getSurfaceElevated(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: primaryColor.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.tag_rounded, size: 14, color: primaryColor),
              const SizedBox(width: 4),
              Text(
                ref,
                style: TextStyle(
                  color: AppTheme.getTextPrimary(context),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          if (link.costType.isNotEmpty || link.amount > 0)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                [
                  if (link.costType.isNotEmpty) link.costType,
                  if (link.amount > 0) link.formattedAmount,
                ].join(' • '),
                style: TextStyle(
                  color: AppTheme.getTextSecondary(context),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    BuildContext context,
    String label,
    String value,
    IconData icon, {
    bool isHighlight = false,
    bool isLast = false,
  }) {
    final isDark = AppTheme.isDark(context);
    final primaryColor = AppTheme.getPrimary(context);
    final successColor = AppTheme.getSuccess(context);
    
    return Container(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      margin: EdgeInsets.only(bottom: isLast ? 0 : 12),
      decoration: BoxDecoration(
        border: isLast ? null : Border(
          bottom: BorderSide(color: AppTheme.getDivider(context)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: (isHighlight ? successColor : primaryColor)
                  .withValues(alpha: isDark ? 0.2 : 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 18,
              color: isHighlight ? successColor : primaryColor,
            ),
          ),
          const SizedBox(width: 12),
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
                    color: isHighlight ? successColor : AppTheme.getTextPrimary(context),
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildActions(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    final primaryColor = AppTheme.getPrimary(context);

    // Bouton "Lier à un OT" : visible pour les Gestionnaires OT après un scan
    // réussi OU un doublon, dès que l'on a une référence de scan.
    final auth = context.read<AuthProvider>();
    final user = auth.user;
    final canLinkToOt = user != null &&
        user.isOtManager &&
        scanRecord != null &&
        scanRecord!.id > 0 &&
        (state == ScanState.success ||
            state == ScanState.duplicate ||
            state == ScanState.alreadyProcessed);

    // Tous les états ont maintenant les deux boutons
    return Column(
      children: [
        if (canLinkToOt) ...[
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              // On délègue au caller : il lancera le parcours unifié
              // (statut OT → sheet Cas A/B/C → écran de liaison).
              onPressed: () => Navigator.of(context).pop('link_to_ot'),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
              icon: const Icon(Icons.link_rounded, size: 22),
              label: const Text(
                'Lier cette facture à un ou plusieurs OTs',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: BorderSide(color: isDark ? AppTheme.darkDivider : Colors.grey.shade300),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  state == ScanState.success ? 'Fermer' : 'Compris',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.getTextSecondary(context),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop('scan_again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: isDark ? const Color(0xFF1A1A1A) : Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
                label: const Text(
                  'Scanner une autre',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
  
  Widget _buildErrorMessageBox(BuildContext context, String errorMessage) {
    final isDark = AppTheme.isDark(context);
    final errorColor = AppTheme.getError(context);
    final errorLight = AppTheme.getErrorLight(context);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: errorLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: errorColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: errorColor.withValues(alpha: isDark ? 0.3 : 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.report_problem_rounded,
                  color: errorColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Détail de l\'erreur',
                  style: TextStyle(
                    color: errorColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkSurfaceElevated : Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              errorMessage,
              style: TextStyle(
                color: AppTheme.getTextPrimary(context),
                fontSize: 14,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Affiche le dialogue de résultat de scan
Future<String?> showScanResultDialog(
  BuildContext context, {
  required ScanState state,
  String? message,
  ScanRecord? scanRecord,
}) async {
  final isDark = AppTheme.isDark(context);
  
  return showGeneralDialog<String>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Scan Result',
    barrierColor: isDark 
        ? Colors.black.withValues(alpha: 0.7) 
        : Colors.white.withValues(alpha: 0.85),
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (context, animation, secondaryAnimation) {
      return ScanResultDialog(
        state: state,
        message: message,
        scanRecord: scanRecord,
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutBack,
      );
      
      return ScaleTransition(
        scale: Tween<double>(begin: 0.8, end: 1.0).animate(curvedAnimation),
        child: FadeTransition(
          opacity: animation,
          child: child,
        ),
      );
    },
  );
}
