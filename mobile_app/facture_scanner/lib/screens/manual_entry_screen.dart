/// Manual Entry Screen
/// Formulaire de saisie manuelle des données de facture DGI
/// Affiché quand la vérification DGI dépasse le timeout ou échoue

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/services/dgi_parser_service.dart';
import '../core/theme/app_theme.dart';

class ManualEntryScreen extends StatefulWidget {
  /// Données pré-remplies depuis l'extraction DGI (partielle ou complète)
  final DgiParsedData? prefillData;

  /// URL du QR code scanné
  final String qrUrl;

  /// Durée de la vérification en secondes
  final double verificationDuration;

  /// Indique si le timeout a été atteint
  final bool timedOut;

  const ManualEntryScreen({
    super.key,
    this.prefillData,
    required this.qrUrl,
    this.verificationDuration = 0,
    this.timedOut = false,
  });

  @override
  State<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ManualEntryScreenState extends State<ManualEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _supplierNameCtrl;
  late final TextEditingController _supplierCodeCtrl;
  late final TextEditingController _customerNameCtrl;
  late final TextEditingController _customerCodeCtrl;
  late final TextEditingController _invoiceNumberCtrl;
  late final TextEditingController _invoiceDateCtrl;
  late final TextEditingController _amountTtcCtrl;

  @override
  void initState() {
    super.initState();
    final d = widget.prefillData;
    _supplierNameCtrl = TextEditingController(text: d?.supplierName ?? '');
    _supplierCodeCtrl = TextEditingController(text: d?.supplierCodeDgi ?? '');
    _customerNameCtrl = TextEditingController(text: d?.customerName ?? '');
    _customerCodeCtrl = TextEditingController(text: d?.customerCodeDgi ?? '');
    _invoiceNumberCtrl = TextEditingController(text: d?.invoiceNumberDgi ?? '');
    _invoiceDateCtrl = TextEditingController(text: d?.invoiceDate ?? '');
    _amountTtcCtrl = TextEditingController(
      text: d != null && d.amountTtc > 0 ? d.amountTtc.toStringAsFixed(0) : '',
    );
  }

  @override
  void dispose() {
    _supplierNameCtrl.dispose();
    _supplierCodeCtrl.dispose();
    _customerNameCtrl.dispose();
    _customerCodeCtrl.dispose();
    _invoiceNumberCtrl.dispose();
    _invoiceDateCtrl.dispose();
    _amountTtcCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final result = ManualEntryResult(
      supplierName: _supplierNameCtrl.text.trim(),
      supplierCodeDgi: _supplierCodeCtrl.text.trim(),
      customerName: _customerNameCtrl.text.trim(),
      customerCodeDgi: _customerCodeCtrl.text.trim(),
      invoiceNumberDgi: _invoiceNumberCtrl.text.trim(),
      invoiceDate: _invoiceDateCtrl.text.trim(),
      amountTtc: double.tryParse(
        _amountTtcCtrl.text.replaceAll(' ', '').replaceAll('\u00a0', ''),
      ) ?? 0,
      verificationDuration: widget.verificationDuration,
    );

    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Saisie manuelle'),
        backgroundColor: AppTheme.getPrimary(context),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Info banner
              if (widget.timedOut)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.warningColor.withOpacity(0.2)
                        : AppTheme.warningLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.warningColor.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.timer_off_rounded,
                          color: AppTheme.warningColor, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'La vérification DGI a dépassé le délai. '
                          'Veuillez compléter ou corriger les informations ci-dessous.',
                          style: TextStyle(
                            color: AppTheme.getTextPrimary(context),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              if (widget.prefillData != null && !widget.timedOut)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? AppTheme.infoColor.withOpacity(0.2)
                        : AppTheme.infoLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.infoColor.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          color: AppTheme.infoColor, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Le site DGI est indisponible. Les données pré-remplies '
                          'proviennent d\'une extraction partielle.',
                          style: TextStyle(
                            color: AppTheme.getTextPrimary(context),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Fournisseur
              _buildSectionTitle(context, 'Fournisseur', Icons.business_rounded),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _supplierNameCtrl,
                label: 'Nom du fournisseur *',
                icon: Icons.person_rounded,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Champ obligatoire' : null,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _supplierCodeCtrl,
                label: 'Code DGI fournisseur',
                icon: Icons.tag_rounded,
                textCapitalization: TextCapitalization.characters,
              ),

              const SizedBox(height: 20),

              // Client
              _buildSectionTitle(context, 'Client', Icons.people_rounded),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _customerNameCtrl,
                label: 'Nom du client',
                icon: Icons.person_outline_rounded,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _customerCodeCtrl,
                label: 'Code DGI client',
                icon: Icons.tag_rounded,
                textCapitalization: TextCapitalization.characters,
              ),

              const SizedBox(height: 20),

              // Facture
              _buildSectionTitle(context, 'Facture', Icons.receipt_long_rounded),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _invoiceNumberCtrl,
                label: 'Numéro de facture *',
                icon: Icons.numbers_rounded,
                textCapitalization: TextCapitalization.characters,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Champ obligatoire' : null,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _invoiceDateCtrl,
                label: 'Date de facturation (JJ/MM/AAAA)',
                icon: Icons.calendar_today_rounded,
                keyboardType: TextInputType.datetime,
                hintText: 'Ex: 15/03/2024',
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _amountTtcCtrl,
                label: 'Montant TTC (FCFA) *',
                icon: Icons.payments_rounded,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Champ obligatoire';
                  final amount = double.tryParse(v.replaceAll(' ', ''));
                  if (amount == null || amount <= 0) return 'Montant invalide';
                  return null;
                },
              ),

              const SizedBox(height: 32),

              // Submit button
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.getPrimary(context),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 2,
                  ),
                  icon: const Icon(Icons.check_circle_rounded),
                  label: const Text(
                    'Valider et créer la facture',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Cancel button
              TextButton(
                onPressed: () => Navigator.of(context).pop(null),
                child: Text(
                  'Annuler',
                  style: TextStyle(
                    color: AppTheme.getTextMuted(context),
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(
      BuildContext context, String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppTheme.getPrimary(context)),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppTheme.getTextPrimary(context),
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hintText,
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      validator: validator,
    );
  }
}

/// Résultat retourné par le formulaire de saisie manuelle
class ManualEntryResult {
  final String supplierName;
  final String supplierCodeDgi;
  final String customerName;
  final String customerCodeDgi;
  final String invoiceNumberDgi;
  final String invoiceDate;
  final double amountTtc;
  final double verificationDuration;

  const ManualEntryResult({
    required this.supplierName,
    this.supplierCodeDgi = '',
    this.customerName = '',
    this.customerCodeDgi = '',
    required this.invoiceNumberDgi,
    this.invoiceDate = '',
    required this.amountTtc,
    this.verificationDuration = 0,
  });
}
