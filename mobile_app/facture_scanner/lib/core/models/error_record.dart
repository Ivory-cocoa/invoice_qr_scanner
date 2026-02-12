/// Error Record Model
/// Représente un enregistrement d'erreur avec classification

enum ErrorCategory {
  dgiService('dgi_service', 'Service DGI', 'Erreur du service DGI'),
  network('network', 'Réseau', 'Erreur de connexion réseau'),
  parsing('parsing', 'Analyse', 'Erreur d\'analyse des données'),
  invoiceCreation('invoice_creation', 'Création facture', 'Erreur lors de la création de la facture'),
  browser('browser', 'Navigateur', 'Erreur du navigateur'),
  other('other', 'Autre', 'Autre type d\'erreur');
  
  final String code;
  final String label;
  final String description;
  
  const ErrorCategory(this.code, this.label, this.description);
  
  static ErrorCategory fromCode(String code) {
    return ErrorCategory.values.firstWhere(
      (e) => e.code == code,
      orElse: () => ErrorCategory.other,
    );
  }
}

class ErrorRecord {
  final int id;
  final String reference;
  final String qrUuid;
  final String supplierName;
  final String supplierCodeDgi;
  final String invoiceNumberDgi;
  final DateTime? invoiceDate;
  final double amountTtc;
  final String currency;
  final String state;
  final String stateLabel;
  final String? errorMessage;
  final ErrorCategory errorCategory;
  final String errorCategoryLabel;
  final bool retryPossible;
  final DateTime? scanDate;
  final String scannedBy;
  
  // Champs pour le suivi des doublons
  final int duplicateCount;
  final DateTime? lastDuplicateAttempt;
  final String? lastDuplicateUser;
  
  ErrorRecord({
    required this.id,
    required this.reference,
    required this.qrUuid,
    required this.supplierName,
    required this.supplierCodeDgi,
    required this.invoiceNumberDgi,
    this.invoiceDate,
    required this.amountTtc,
    required this.currency,
    required this.state,
    required this.stateLabel,
    this.errorMessage,
    required this.errorCategory,
    required this.errorCategoryLabel,
    required this.retryPossible,
    this.scanDate,
    required this.scannedBy,
    this.duplicateCount = 0,
    this.lastDuplicateAttempt,
    this.lastDuplicateUser,
  });
  
  factory ErrorRecord.fromJson(Map<String, dynamic> json) {
    return ErrorRecord(
      id: json['id'] as int,
      reference: json['reference'] as String? ?? '',
      qrUuid: json['qr_uuid'] as String? ?? '',
      supplierName: json['supplier_name'] as String? ?? '',
      supplierCodeDgi: json['supplier_code_dgi'] as String? ?? '',
      invoiceNumberDgi: json['invoice_number_dgi'] as String? ?? '',
      invoiceDate: json['invoice_date'] != null 
          ? DateTime.tryParse(json['invoice_date']) 
          : null,
      amountTtc: (json['amount_ttc'] as num?)?.toDouble() ?? 0.0,
      currency: json['currency'] as String? ?? 'XOF',
      state: json['state'] as String? ?? 'error',
      stateLabel: json['state_label'] as String? ?? 'Erreur',
      errorMessage: json['error_message'] as String?,
      errorCategory: ErrorCategory.fromCode(json['error_category'] as String? ?? 'other'),
      errorCategoryLabel: json['error_category_label'] as String? ?? 'Autre',
      retryPossible: json['retry_possible'] as bool? ?? false,
      scanDate: json['scan_date'] != null 
          ? DateTime.tryParse(json['scan_date']) 
          : null,
      scannedBy: json['scanned_by'] as String? ?? '',
      duplicateCount: json['duplicate_count'] as int? ?? 0,
      lastDuplicateAttempt: json['last_duplicate_attempt'] != null
          ? DateTime.tryParse(json['last_duplicate_attempt'])
          : null,
      lastDuplicateUser: json['last_duplicate_user'] as String?,
    );
  }
  
  String get formattedAmount {
    final formatted = amountTtc.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]} ',
    );
    return '$formatted $currency';
  }
  
  @override
  String toString() => 'ErrorRecord($reference - $errorCategoryLabel)';
}

/// Résultat du bulk retry
class BulkRetryResult {
  final int processed;
  final int successful;
  final int failed;
  final List<RetryDetail> details;
  
  BulkRetryResult({
    required this.processed,
    required this.successful,
    required this.failed,
    required this.details,
  });
  
  factory BulkRetryResult.fromJson(Map<String, dynamic> json) {
    final detailsList = (json['details'] as List<dynamic>?)
        ?.map((d) => RetryDetail.fromJson(d))
        .toList() ?? [];
    
    return BulkRetryResult(
      processed: json['processed'] as int? ?? 0,
      successful: json['successful'] as int? ?? 0,
      failed: json['failed'] as int? ?? 0,
      details: detailsList,
    );
  }
  
  bool get hasFailures => failed > 0;
  double get successRate => processed > 0 ? (successful / processed) * 100 : 0;
}

class RetryDetail {
  final int recordId;
  final String reference;
  final bool success;
  final String? newState;
  final String? error;
  
  RetryDetail({
    required this.recordId,
    required this.reference,
    required this.success,
    this.newState,
    this.error,
  });
  
  factory RetryDetail.fromJson(Map<String, dynamic> json) {
    return RetryDetail(
      recordId: json['record_id'] as int? ?? 0,
      reference: json['reference'] as String? ?? '',
      success: json['success'] as bool? ?? false,
      newState: json['new_state'] as String?,
      error: json['error'] as String?,
    );
  }
}
