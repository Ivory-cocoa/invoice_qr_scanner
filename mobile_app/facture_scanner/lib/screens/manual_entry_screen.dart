/// Manual Entry Screen
/// Formulaire de saisie manuelle des données de facture DGI
/// Affiché quand la vérification DGI dépasse le timeout ou échoue
/// - Lien cliquable vers le site DGI pour consulter la facture
/// - Ré-extraction automatique en arrière-plan pour pré-remplir les champs

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/services/dgi_extractor_service.dart';
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

  /// État de la ré-extraction en arrière-plan
  bool _isReExtracting = false;
  String _reExtractionStatus = '';
  bool _reExtractionDone = false;

  /// Afficher/masquer les détails supplémentaires
  bool _showOptionalFields = false;

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

    // Lancer la ré-extraction automatique en arrière-plan
    _startBackgroundReExtraction();
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

  /// Lance la ré-extraction DGI en arrière-plan.
  /// Si elle réussit, pré-remplit les champs vides automatiquement.
  Future<void> _startBackgroundReExtraction() async {
    if (_reExtractionDone) return;

    setState(() {
      _isReExtracting = true;
      _reExtractionStatus = 'Tentative de récupération automatique...';
    });

    try {
      final extractor = DgiExtractorService();
      final result = await extractor.extractFromUrl(
        widget.qrUrl,
        onProgress: (message) {
          if (mounted) {
            setState(() => _reExtractionStatus = message);
          }
        },
      );

      if (!mounted) return;

      if (result.success && result.data != null) {
        _autoFillFromData(result.data!);
        setState(() {
          _isReExtracting = false;
          _reExtractionDone = true;
          _reExtractionStatus = 'Données récupérées avec succès !';
        });
      } else {
        setState(() {
          _isReExtracting = false;
          _reExtractionDone = true;
          _reExtractionStatus =
              'Récupération automatique échouée. Utilisez le lien DGI ci-dessous.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isReExtracting = false;
        _reExtractionDone = true;
        _reExtractionStatus =
            'Erreur de récupération. Utilisez le lien DGI ci-dessous.';
      });
    }
  }

  /// Pré-remplit uniquement les champs qui sont actuellement vides.
  void _autoFillFromData(DgiParsedData data) {
    if (_supplierNameCtrl.text.trim().isEmpty && data.supplierName.isNotEmpty) {
      _supplierNameCtrl.text = data.supplierName;
    }
    if (_supplierCodeCtrl.text.trim().isEmpty &&
        data.supplierCodeDgi.isNotEmpty) {
      _supplierCodeCtrl.text = data.supplierCodeDgi;
    }
    if (_customerNameCtrl.text.trim().isEmpty && data.customerName.isNotEmpty) {
      _customerNameCtrl.text = data.customerName;
    }
    if (_customerCodeCtrl.text.trim().isEmpty &&
        data.customerCodeDgi.isNotEmpty) {
      _customerCodeCtrl.text = data.customerCodeDgi;
    }
    if (_invoiceNumberCtrl.text.trim().isEmpty &&
        data.invoiceNumberDgi.isNotEmpty) {
      _invoiceNumberCtrl.text = data.invoiceNumberDgi;
    }
    if (_invoiceDateCtrl.text.trim().isEmpty && (data.invoiceDate?.isNotEmpty ?? false)) {
      _invoiceDateCtrl.text = data.invoiceDate!;
    }
    if (_amountTtcCtrl.text.trim().isEmpty && data.amountTtc > 0) {
      _amountTtcCtrl.text = data.amountTtc.toStringAsFixed(0);
    }
  }

  /// Ouvre le lien DGI dans le navigateur externe.
  Future<void> _openDgiLink() async {
    final uri = Uri.parse(widget.qrUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impossible d\'ouvrir le lien DGI'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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

              // --- Lien DGI cliquable ---
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.blue.shade900.withOpacity(0.3)
                      : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.blue.withOpacity(0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.link_rounded,
                            color: Colors.blue.shade700, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Consultez la facture sur le site DGI pour retrouver les informations (codes DGI, etc.)',
                            style: TextStyle(
                              color: AppTheme.getTextPrimary(context),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _openDgiLink,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.blue.shade700,
                          side: BorderSide(color: Colors.blue.shade300),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 14),
                        ),
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: const Text(
                          'Ouvrir la facture sur le site DGI',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // --- Statut de la ré-extraction automatique ---
              if (_isReExtracting || _reExtractionDone)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: isDark
                        ? (_isReExtracting
                            ? Colors.orange.shade900.withOpacity(0.2)
                            : (_reExtractionStatus.contains('succès')
                                ? Colors.green.shade900.withOpacity(0.2)
                                : Colors.grey.shade800.withOpacity(0.3)))
                        : (_isReExtracting
                            ? Colors.orange.shade50
                            : (_reExtractionStatus.contains('succès')
                                ? Colors.green.shade50
                                : Colors.grey.shade100)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      if (_isReExtracting)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.orange),
                          ),
                        )
                      else if (_reExtractionStatus.contains('succès'))
                        const Icon(Icons.check_circle_rounded,
                            color: Colors.green, size: 20)
                      else
                        Icon(Icons.info_outline_rounded,
                            color: Colors.grey.shade600, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _reExtractionStatus,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.getTextSecondary(context),
                          ),
                        ),
                      ),
                      if (!_isReExtracting && !_reExtractionStatus.contains('succès'))
                        TextButton.icon(
                          onPressed: () {
                            setState(() => _reExtractionDone = false);
                            _startBackgroundReExtraction();
                          },
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: const Text('Réessayer', style: TextStyle(fontSize: 12)),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                    ],
                  ),
                ),

              // --- Champs essentiels ---
              _buildSectionTitle(context, 'Facture', Icons.receipt_long_rounded),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _supplierNameCtrl,
                label: 'Nom du fournisseur *',
                icon: Icons.business_rounded,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Champ obligatoire' : null,
              ),
              const SizedBox(height: 12),
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

              const SizedBox(height: 20),

              // --- Codes DGI (préremplis automatiquement) ---
              _buildDgiCodesSection(context, isDark),

              const SizedBox(height: 16),

              // --- Détails supplémentaires (rétractable) ---
              _buildOptionalFieldsSection(context, isDark),

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

  /// Section Codes DGI : affiche les codes préremplis ou un message d'aide
  Widget _buildDgiCodesSection(BuildContext context, bool isDark) {
    final hasSupplierCode = _supplierCodeCtrl.text.trim().isNotEmpty;
    final hasCustomerCode = _customerCodeCtrl.text.trim().isNotEmpty;
    final hasCodes = hasSupplierCode || hasCustomerCode;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? (hasCodes
                ? Colors.green.shade900.withOpacity(0.2)
                : Colors.orange.shade900.withOpacity(0.2))
            : (hasCodes ? Colors.green.shade50 : Colors.orange.shade50),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (hasCodes ? Colors.green : Colors.orange).withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasCodes ? Icons.verified_rounded : Icons.info_outline_rounded,
                color: hasCodes ? Colors.green.shade700 : Colors.orange.shade700,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasCodes
                      ? 'Codes DGI récupérés automatiquement'
                      : 'Codes DGI non récupérés',
                  style: TextStyle(
                    color: AppTheme.getTextPrimary(context),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (hasCodes) ...[
            const SizedBox(height: 10),
            if (hasSupplierCode)
              _buildDgiCodeDisplay(
                context,
                'Code DGI fournisseur',
                _supplierCodeCtrl.text.trim(),
                isDark,
              ),
            if (hasSupplierCode && hasCustomerCode)
              const SizedBox(height: 6),
            if (hasCustomerCode)
              _buildDgiCodeDisplay(
                context,
                'Code DGI client',
                _customerCodeCtrl.text.trim(),
                isDark,
              ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              _isReExtracting
                  ? 'Récupération en cours... Veuillez patienter.'
                  : 'Ouvrez le lien DGI ci-dessus, puis copiez et collez '
                      'les codes DGI fournisseur et client ci-dessous.',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.getTextSecondary(context),
              ),
            ),
            if (!_isReExtracting) ...[
              const SizedBox(height: 10),
              _buildTextField(
                controller: _supplierCodeCtrl,
                label: 'Code DGI fournisseur',
                icon: Icons.tag_rounded,
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 10),
              _buildTextField(
                controller: _customerCodeCtrl,
                label: 'Code DGI client',
                icon: Icons.tag_rounded,
                textCapitalization: TextCapitalization.characters,
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// Affiche un code DGI prérempli en lecture seule
  Widget _buildDgiCodeDisplay(
    BuildContext context,
    String label,
    String code,
    bool isDark,
  ) {
    return Row(
      children: [
        const SizedBox(width: 30),
        Icon(Icons.tag_rounded, size: 16, color: Colors.green.shade600),
        const SizedBox(width: 6),
        Text(
          '$label : ',
          style: TextStyle(
            fontSize: 13,
            color: AppTheme.getTextSecondary(context),
          ),
        ),
        Text(
          code,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppTheme.getTextPrimary(context),
          ),
        ),
      ],
    );
  }

  /// Section rétractable pour les champs optionnels
  Widget _buildOptionalFieldsSection(BuildContext context, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _showOptionalFields = !_showOptionalFields),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(
                  _showOptionalFields
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 22,
                  color: AppTheme.getTextMuted(context),
                ),
                const SizedBox(width: 6),
                Text(
                  'Détails supplémentaires (optionnel)',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.getTextMuted(context),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_showOptionalFields) ...[
          const SizedBox(height: 8),
          _buildTextField(
            controller: _customerNameCtrl,
            label: 'Nom du client',
            icon: Icons.person_outline_rounded,
          ),
          const SizedBox(height: 12),
          _buildTextField(
            controller: _invoiceDateCtrl,
            label: 'Date de facturation (JJ/MM/AAAA)',
            icon: Icons.calendar_today_rounded,
            keyboardType: TextInputType.datetime,
            hintText: 'Ex: 15/03/2024',
          ),
        ],
      ],
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
