/// DGI Data Parser Service
/// Port de la logique Python _extract_dgi_data_from_text() côté client
/// Extrait les données de facture depuis le texte rendu de la page DGI

class DgiParserService {
  // Singleton
  static final DgiParserService _instance = DgiParserService._internal();
  factory DgiParserService() => _instance;
  DgiParserService._internal();

  /// Données extraites d'une page DGI
  /// Retourne un Map avec les champs parsés
  DgiParsedData? extractFromText(String textContent) {
    if (textContent.trim().isEmpty) return null;

    String? supplierName;
    String? supplierCodeDgi;
    String? customerName;
    String? customerCodeDgi;
    String? invoiceNumberDgi;
    String? invoiceDate;
    String? verificationId;
    double? amountTtc;

    // FOURNISSEUR: NOM - CODE (multi-lignes possible)
    final supplierRegex = RegExp(
      r'FOURNISSEUR:\s*\n*\s*([A-Z0-9\s\-\.&' "'" r']+?)\s*-\s*([A-Z0-9]+)',
      caseSensitive: false,
      multiLine: true,
    );
    final supplierMatch = supplierRegex.firstMatch(textContent);
    if (supplierMatch != null) {
      supplierName = supplierMatch.group(1)?.trim();
      supplierCodeDgi = supplierMatch.group(2)?.trim();
    }

    // CLIENT: NOM - CODE
    final clientRegex = RegExp(
      r'CLIENT:\s*\n*\s*([A-Z0-9\s\-\.&' "'" r']+?)\s*-\s*([A-Z0-9]+)',
      caseSensitive: false,
      multiLine: true,
    );
    final clientMatch = clientRegex.firstMatch(textContent);
    if (clientMatch != null) {
      customerName = clientMatch.group(1)?.trim();
      customerCodeDgi = clientMatch.group(2)?.trim();
    }

    // NUMERO DE FACTURE: CODE
    final invoiceRegex = RegExp(
      r'NUMERO DE FACTURE:\s*\n*\s*([A-Z0-9]+)',
      caseSensitive: false,
      multiLine: true,
    );
    final invoiceMatch = invoiceRegex.firstMatch(textContent);
    if (invoiceMatch != null) {
      invoiceNumberDgi = invoiceMatch.group(1)?.trim();
    }

    // DATE DE FACTURATION: DD/MM/YYYY
    final dateRegex = RegExp(
      r'DATE DE FACTURATION:\s*\n*\s*(\d{2}/\d{2}/\d{4})',
      caseSensitive: false,
      multiLine: true,
    );
    final dateMatch = dateRegex.firstMatch(textContent);
    if (dateMatch != null) {
      invoiceDate = dateMatch.group(1)?.trim();
    }

    // ID VERIFICATION: CODE
    final verifRegex = RegExp(
      r'ID VERIFICATION:\s*\n*\s*([A-Z0-9\-]+)',
      caseSensitive: false,
      multiLine: true,
    );
    final verifMatch = verifRegex.firstMatch(textContent);
    if (verifMatch != null) {
      verificationId = verifMatch.group(1)?.trim();
    }

    // MONTANT TTC: 1 677 566 CFA ou FCFA
    final amountRegex = RegExp(
      r'MONTANT TTC:\s*\n*\s*([\d\s\u00a0]+)\s*(?:F?CFA)',
      caseSensitive: false,
      multiLine: true,
    );
    final amountMatch = amountRegex.firstMatch(textContent);
    if (amountMatch != null) {
      final amountStr = amountMatch
          .group(1)!
          .replaceAll(' ', '')
          .replaceAll('\u00a0', '')
          .trim();
      amountTtc = double.tryParse(amountStr);
    }

    // Vérifier qu'on a au moins un champ exploitable
    final hasData = supplierName != null ||
        invoiceNumberDgi != null ||
        amountTtc != null;

    if (!hasData) return null;

    return DgiParsedData(
      supplierName: supplierName ?? '',
      supplierCodeDgi: supplierCodeDgi ?? '',
      customerName: customerName ?? '',
      customerCodeDgi: customerCodeDgi ?? '',
      invoiceNumberDgi: invoiceNumberDgi ?? '',
      invoiceDate: invoiceDate,
      verificationId: verificationId ?? '',
      amountTtc: amountTtc ?? 0,
      rawText: textContent.length > 3000
          ? textContent.substring(0, 3000)
          : textContent,
    );
  }

  /// Extraire l'UUID depuis l'URL DGI
  String? extractUuidFromUrl(String url) {
    final pattern = RegExp(
      r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
      caseSensitive: false,
    );
    final match = pattern.firstMatch(url);
    return match?.group(0)?.toLowerCase();
  }

  /// Valider que l'URL est bien du domaine DGI
  bool isValidDgiUrl(String url) {
    return url.contains('services.fne.dgi.gouv.ci');
  }

  /// Convertir une date DD/MM/YYYY en ISO (YYYY-MM-DD)
  String? parseDateToIso(String? dateStr) {
    if (dateStr == null) return null;
    final parts = dateStr.split('/');
    if (parts.length != 3) return null;
    try {
      final day = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final year = int.parse(parts[2]);
      return DateTime(year, month, day).toIso8601String().split('T').first;
    } catch (_) {
      return null;
    }
  }
}

/// Données structurées extraites de la page DGI
class DgiParsedData {
  final String supplierName;
  final String supplierCodeDgi;
  final String customerName;
  final String customerCodeDgi;
  final String invoiceNumberDgi;
  final String? invoiceDate; // Format DD/MM/YYYY
  final String verificationId;
  final double amountTtc;
  final String rawText;

  const DgiParsedData({
    required this.supplierName,
    required this.supplierCodeDgi,
    required this.customerName,
    required this.customerCodeDgi,
    required this.invoiceNumberDgi,
    this.invoiceDate,
    required this.verificationId,
    required this.amountTtc,
    required this.rawText,
  });

  Map<String, dynamic> toMap() {
    return {
      'supplier_name': supplierName,
      'supplier_code_dgi': supplierCodeDgi,
      'customer_name': customerName,
      'customer_code_dgi': customerCodeDgi,
      'invoice_number_dgi': invoiceNumberDgi,
      'invoice_date': invoiceDate,
      'verification_id': verificationId,
      'amount_ttc': amountTtc,
      'raw_text': rawText,
    };
  }

  factory DgiParsedData.fromMap(Map<String, dynamic> map) {
    return DgiParsedData(
      supplierName: map['supplier_name'] ?? '',
      supplierCodeDgi: map['supplier_code_dgi'] ?? '',
      customerName: map['customer_name'] ?? '',
      customerCodeDgi: map['customer_code_dgi'] ?? '',
      invoiceNumberDgi: map['invoice_number_dgi'] ?? '',
      invoiceDate: map['invoice_date'],
      verificationId: map['verification_id'] ?? '',
      amountTtc: (map['amount_ttc'] as num?)?.toDouble() ?? 0,
      rawText: map['raw_text'] ?? '',
    );
  }

  String get formattedAmount {
    final formatted = amountTtc.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]} ',
    );
    return '$formatted FCFA';
  }

  bool get hasSupplier => supplierName.isNotEmpty;
  bool get hasAmount => amountTtc > 0;
  bool get hasInvoiceNumber => invoiceNumberDgi.isNotEmpty;

  @override
  String toString() =>
      'DgiParsedData(supplier: $supplierName, amount: $amountTtc, invoice: $invoiceNumberDgi)';
}
