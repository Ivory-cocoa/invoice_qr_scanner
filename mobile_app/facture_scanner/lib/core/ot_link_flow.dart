/// Parcours unifié de liaison d'un scan à un OT.
///
/// Centralise la logique auparavant dupliquée dans les écrans :
///   1. récupère le statut OT de la facture (existence + liaisons + restant) ;
///   2. affiche le bottom sheet [showInvoiceStatusSheet] (Cas A/B/C) pour que
///      l'utilisateur voie immédiatement si la facture est déjà liée à un OT ;
///   3. ouvre l'écran de liaison avec le montant à allouer pré-rempli.
///
/// Utilisé par le Gestionnaire OT ET le Responsable Scanner (tout utilisateur
/// dont `user.isOtManager == true`), depuis l'écran dédié comme depuis le
/// dialogue de résultat de scan.
library;

import 'package:flutter/material.dart';

import 'models/scan_record.dart';
import 'services/api_service.dart';
import '../screens/link_to_ot_screen.dart';
import '../widgets/invoice_status_sheet.dart';

/// Lance le parcours de liaison OT pour [record].
///
/// Retourne `true` si au moins une liaison a été effectuée, `false` si
/// l'utilisateur a fermé le sheet de statut ou annulé l'écran de liaison.
Future<bool> startOtLinkFlow(BuildContext context, ScanRecord record) async {
  final api = ApiService();

  final invoiceLabel = record.invoiceNumberDgi.isNotEmpty
      ? 'Facture ${record.invoiceNumberDgi}'
          '${record.supplierName.isNotEmpty ? ' • ${record.supplierName}' : ''}'
      : (record.supplierName.isNotEmpty
          ? record.supplierName
          : 'Facture scannée');

  // 1. Statut OT (existence + liaisons + montant restant) pour décider du
  //    parcours (Cas A : non liée / B : totalement liée / C : partielle).
  final double fallbackAmount = record.amountTtc > 0 ? record.amountTtc : 0.0;
  final statusResp = await api.getScanOtStatus(record.id);
  if (!context.mounted) return false;

  double? amountToAllocate = fallbackAmount > 0 ? fallbackAmount : null;

  if (statusResp.success && statusResp.data != null) {
    // 2. Sheet de statut : montre les OTs déjà liés, le montant restant, etc.
    final result = await showInvoiceStatusSheet(
      context,
      status: statusResp.data!,
    );
    if (!context.mounted) return false;
    if (result.action == InvoiceStatusAction.close) {
      return false;
    }
    amountToAllocate = result.amountToAllocate ?? amountToAllocate;
  }
  // En cas d'échec API on continue vers l'écran de liaison directement
  // (comportement de repli) avec le montant de la facture.

  // 3. Écran de liaison.
  final linked = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      builder: (_) => LinkToOtScreen(
        scanId: record.id,
        invoiceLabel: invoiceLabel,
        invoiceAmount: amountToAllocate,
      ),
    ),
  );
  return linked == true;
}
