/// Confirmation avant de marquer « traitée » — donc de transmettre à la
/// comptabilité — une facture dont le numéro est déjà porté par une autre
/// facture enregistrée. Second filet après l'avertissement donné au scan.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/providers/scan_provider.dart';
import '../core/theme/app_theme.dart';

/// Affiche l'avertissement du serveur et renvoie `true` seulement si
/// l'utilisateur choisit de transmettre quand même. Fermer la fenêtre ou
/// revenir en arrière vaut « non ».
Future<bool> showSameNumberConfirmDialog(
  BuildContext context,
  String warning,
) async {
  final errorColor = AppTheme.getError(context);
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      icon: Icon(Icons.file_copy_rounded, color: errorColor, size: 40),
      title: const Text('Même numéro de facture'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              warning,
              style: TextStyle(
                color: errorColor,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Elle n\'a pas été marquée traitée. La transmettre quand même '
              'à la comptabilité ?',
            ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          key: const ValueKey('same-number-confirm'),
          style: TextButton.styleFrom(foregroundColor: errorColor),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Transmettre quand même'),
        ),
        FilledButton(
          key: const ValueKey('same-number-cancel'),
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Ne pas traiter'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// Marque un scan « traité » ; si le serveur demande une confirmation, la
/// pose à l'utilisateur et, sur son accord, recommence en la confirmant.
///
/// [whileWaiting] enveloppe chaque appel au serveur (indicateur d'attente).
Future<bool> markProcessedAskingIfSameNumber(
  BuildContext context,
  int recordId, {
  Future<bool> Function(Future<bool> Function() call)? whileWaiting,
}) async {
  final scan = context.read<ScanProvider>();
  Future<bool> run(bool confirm) {
    Future<bool> call() =>
        scan.markAsProcessed(recordId, confirmSameNumber: confirm);
    return whileWaiting != null ? whileWaiting(call) : call();
  }

  if (await run(false)) return true;
  final warning = scan.sameNumberConfirmation;
  if (warning == null || !context.mounted) return false;
  if (!await showSameNumberConfirmDialog(context, warning)) return false;
  if (!context.mounted) return false;
  return run(true);
}
