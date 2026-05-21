/// ShareService — Construit le texte de partage WhatsApp/système pour
/// le résultat d'un scan de facture, et déclenche le sélecteur de partage.
///
/// Utilisé par `InvoiceStatusSheet` (bouton « Partager » du header).
library;

import 'package:share_plus/share_plus.dart';

/// Construit le message texte (FR, format WhatsApp-friendly) à partir
/// du payload retourné par `/api/v1/invoice-scanner/scan/<id>/status`.
///
/// Pure function — testable sans Flutter.
String buildScanShareText(Map<String, dynamic> status) {
  final linksCount = (status['links_count'] as num?)?.toInt() ?? 0;
  final invoiceAmount = (status['invoice_amount'] as num?)?.toDouble() ?? 0.0;
  final linkedAmount =
      (status['total_linked_amount'] as num?)?.toDouble() ?? 0.0;
  final remaining = (status['remaining_amount'] as num?)?.toDouble() ?? 0.0;
  final currency = (status['currency'] as String?) ?? 'XOF';
  final invoiceNum = (status['invoice_number_dgi'] as String?) ?? '';
  final supplier = (status['supplier_name'] as String?) ?? '';
  final invoiceDate = (status['invoice_date'] as String?) ?? '';
  final links = (status['links'] as List?) ?? const [];

  final buf = StringBuffer();
  buf.writeln('📄 *Facture${invoiceNum.isNotEmpty ? ' $invoiceNum' : ''}*');
  if (supplier.isNotEmpty) {
    buf.writeln('🏢 Fournisseur : $supplier');
  }
  if (invoiceDate.isNotEmpty) {
    buf.writeln('📅 Date : ${_formatDate(invoiceDate)}');
  }
  buf.writeln('💰 Montant TTC : ${_formatAmount(invoiceAmount, currency)}');
  buf.writeln();

  if (linksCount == 0) {
    buf.writeln('⚠️ *Facture non liée à un OT*');
    buf.writeln('Reste à allouer : ${_formatAmount(invoiceAmount, currency)}');
  } else if (remaining <= 0.0001) {
    buf.writeln('✅ *Entièrement liée à $linksCount OT(s)* :');
    for (final l in links) {
      buf.writeln(_formatLinkLine(l as Map<String, dynamic>, currency));
    }
  } else {
    buf.writeln('🟠 *Partiellement liée à $linksCount OT(s)*');
    buf.writeln('Alloué : ${_formatAmount(linkedAmount, currency)}');
    buf.writeln('Restant : ${_formatAmount(remaining, currency)}');
    buf.writeln();
    buf.writeln('Liaisons :');
    for (final l in links) {
      buf.writeln(_formatLinkLine(l as Map<String, dynamic>, currency));
    }
  }

  buf.writeln();
  buf.writeln('— Partagé depuis Facture Scanner ICP');
  return buf.toString();
}

String _formatLinkLine(Map<String, dynamic> link, String fallbackCurrency) {
  final otRef = (link['transit_order_ref'] as String?) ?? 'OT';
  final amount = (link['amount'] as num?)?.toDouble() ?? 0.0;
  final cur = (link['currency'] as String?) ?? fallbackCurrency;
  final costLabel = (link['cost_type_label'] as String?) ?? '';
  final extras = costLabel.isNotEmpty ? ' ($costLabel)' : '';
  return '  • $otRef$extras — ${_formatAmount(amount, cur)}';
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

/// Convertit une date ISO (YYYY-MM-DD) en format français DD/MM/YYYY.
/// Retourne la chaîne d'origine si parsing échoue.
String _formatDate(String iso) {
  try {
    final d = DateTime.parse(iso);
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  } catch (_) {
    return iso;
  }
}

/// Ouvre le sélecteur de partage système avec le texte construit.
/// L'utilisateur choisit WhatsApp, SMS, email, etc.
Future<void> shareScanStatus(Map<String, dynamic> status) async {
  final text = buildScanShareText(status);
  final invoiceNum = (status['invoice_number_dgi'] as String?) ?? '';
  final subject = invoiceNum.isNotEmpty
      ? 'Facture $invoiceNum — statut OT'
      : 'Statut OT facture';
  await Share.share(text, subject: subject);
}
