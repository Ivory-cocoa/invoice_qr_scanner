/// Scan Record Model
class ScanRecord {
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
  final int? invoiceId;
  final String? invoiceName;
  final String? invoiceState;
  final DateTime? scanDate;
  final String scannedBy;
  final String? errorMessage;
  
  // Champs pour le suivi des doublons
  final int duplicateCount;
  final DateTime? lastDuplicateAttempt;
  final String? lastDuplicateUser;
  
  ScanRecord({
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
    this.invoiceId,
    this.invoiceName,
    this.invoiceState,
    this.scanDate,
    required this.scannedBy,
    this.errorMessage,
    this.duplicateCount = 0,
    this.lastDuplicateAttempt,
    this.lastDuplicateUser,
  });
  
  factory ScanRecord.fromJson(Map<String, dynamic> json) {
    return ScanRecord(
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
      state: json['state'] as String? ?? '',
      stateLabel: json['state_label'] as String? ?? '',
      invoiceId: json['invoice_id'] as int?,
      invoiceName: json['invoice_name'] as String?,
      invoiceState: json['invoice_state'] as String?,
      scanDate: json['scan_date'] != null 
          ? DateTime.tryParse(json['scan_date']) 
          : null,
      scannedBy: json['scanned_by'] as String? ?? '',
      errorMessage: json['error_message'] as String?,
      duplicateCount: json['duplicate_count'] as int? ?? 0,
      lastDuplicateAttempt: json['last_duplicate_attempt'] != null
          ? DateTime.tryParse(json['last_duplicate_attempt'])
          : null,
      lastDuplicateUser: json['last_duplicate_user'] as String?,
    );
  }
  
  factory ScanRecord.fromMap(Map<String, dynamic> map) {
    return ScanRecord(
      id: map['id'] as int,
      reference: map['reference'] as String? ?? '',
      qrUuid: map['qr_uuid'] as String? ?? '',
      supplierName: map['supplier_name'] as String? ?? '',
      supplierCodeDgi: map['supplier_code_dgi'] as String? ?? '',
      invoiceNumberDgi: map['invoice_number_dgi'] as String? ?? '',
      invoiceDate: map['invoice_date'] != null 
          ? DateTime.tryParse(map['invoice_date']) 
          : null,
      amountTtc: (map['amount_ttc'] as num?)?.toDouble() ?? 0.0,
      currency: map['currency'] as String? ?? 'XOF',
      state: map['state'] as String? ?? '',
      stateLabel: map['state_label'] as String? ?? '',
      invoiceId: map['invoice_id'] as int?,
      invoiceName: map['invoice_name'] as String?,
      invoiceState: map['invoice_state'] as String?,
      scanDate: map['scan_date'] != null 
          ? DateTime.tryParse(map['scan_date']) 
          : null,
      scannedBy: map['scanned_by'] as String? ?? '',
      errorMessage: map['error_message'] as String?,
      duplicateCount: map['duplicate_count'] as int? ?? 0,
      lastDuplicateAttempt: map['last_duplicate_attempt'] != null
          ? DateTime.tryParse(map['last_duplicate_attempt'])
          : null,
      lastDuplicateUser: map['last_duplicate_user'] as String?,
    );
  }
  
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'reference': reference,
      'qr_uuid': qrUuid,
      'supplier_name': supplierName,
      'supplier_code_dgi': supplierCodeDgi,
      'invoice_number_dgi': invoiceNumberDgi,
      'invoice_date': invoiceDate?.toIso8601String(),
      'amount_ttc': amountTtc,
      'currency': currency,
      'state': state,
      'state_label': stateLabel,
      'invoice_id': invoiceId,
      'invoice_name': invoiceName,
      'invoice_state': invoiceState,
      'scan_date': scanDate?.toIso8601String(),
      'scanned_by': scannedBy,
      'error_message': errorMessage,
      'duplicate_count': duplicateCount,
      'last_duplicate_attempt': lastDuplicateAttempt?.toIso8601String(),
      'last_duplicate_user': lastDuplicateUser,
    };
  }
  
  bool get isSuccess => state == 'done';
  bool get isError => state == 'error';
  bool get hasDuplicates => duplicateCount > 0;
  
  String get formattedAmount {
    final formatted = amountTtc.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]} ',
    );
    return '$formatted $currency';
  }
  
  @override
  String toString() => 'ScanRecord($reference - $supplierName)';
}
