/// Manual Entry Screen
/// Formulaire de saisie manuelle des données de facture DGI
/// Affiché quand la vérification DGI dépasse le timeout ou échoue
/// - Lien cliquable vers le site DGI pour consulter la facture
/// - Ré-extraction automatique en arrière-plan pour pré-remplir les champs
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/services/api_service.dart';

import '../core/models/scan_record.dart' show DocumentType;
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

  /// Nature du document saisi : facture ou AVOIR.
  ///
  /// Choix explicite et non déductible du montant : la page DGI affiche les
  /// avoirs en valeur absolue, exactement comme les factures. Sans cette
  /// question posée à l'utilisateur, la saisie manuelle reste le dernier
  /// endroit par lequel un avoir peut entrer en dette fournisseur.
  DocumentType _documentType = DocumentType.invoice;

  bool get _isRefund => _documentType == DocumentType.refund;

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
    _documentType = d?.documentType ?? DocumentType.invoice;

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

  /// Nouvelle tentative de récupération automatique, PAR LE SERVEUR.
  ///
  /// On arrive sur cet écran parce que la vérification a échoué ; elle peut
  /// avoir échoué pour une raison passagère (DGI momentanément injoignable),
  /// d'où cette seconde tentative. L'ancienne version relançait une extraction
  /// locale par WebView : c'est elle qui pré-remplissait le formulaire avec un
  /// nom tronqué et un faux code DGI, que l'utilisateur validait sans le voir.
  Future<void> _startBackgroundReExtraction() async {
    if (_reExtractionDone) return;

    setState(() {
      _isReExtracting = true;
      _reExtractionStatus = 'Nouvelle tentative auprès de la DGI...';
    });

    try {
      final response = await ApiService().scanFromUrl(widget.qrUrl);

      if (!mounted) return;

      if (response.success && response.data != null) {
        // La facture vient d'être créée côté serveur : il n'y a plus rien à
        // saisir. On referme l'écran en signalant le succès.
        Navigator.of(context).pop(true);
        return;
      }

      setState(() {
        _isReExtracting = false;
        _reExtractionDone = true;
        _reExtractionStatus = response.errorCode == 'DUPLICATE'
            ? 'Cette facture a déjà été enregistrée.'
            : 'Récupération automatique impossible. '
                'Ouvrez le lien DGI ci-dessous et recopiez les informations.';
      });
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
      amountTtc: (double.tryParse(
            _amountTtcCtrl.text.replaceAll(' ', '').replaceAll('\u00a0', ''),
          ) ??
              0)
          .abs(),
      documentType: _documentType,
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
      body: SafeArea(
        child: SingleChildScrollView(
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
                        ? AppTheme.warningColor.withValues(alpha: 0.2)
                        : AppTheme.warningLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.warningColor.withValues(alpha: 0.3),
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
                        ? AppTheme.infoColor.withValues(alpha: 0.2)
                        : AppTheme.infoLight,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.infoColor.withValues(alpha: 0.3),
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
                      ? Colors.blue.shade900.withValues(alpha: 0.3)
                      : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.blue.withValues(alpha: 0.3),
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
                            ? Colors.orange.shade900.withValues(alpha: 0.2)
                            : (_reExtractionStatus.contains('succès')
                                ? Colors.green.shade900.withValues(alpha: 0.2)
                                : Colors.grey.shade800.withValues(alpha: 0.3)))
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

              // --- Nature du document (facture / avoir) ---
              _buildSectionTitle(
                  context, 'Nature du document', Icons.rule_folder_rounded),
              const SizedBox(height: 8),
              _buildDocumentTypeSelector(context, isDark),
              const SizedBox(height: 20),

              // --- Champs essentiels ---
              _buildSectionTitle(
                  context,
                  _isRefund ? 'Avoir' : 'Facture',
                  _isRefund ? Icons.undo_rounded : Icons.receipt_long_rounded),
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
                label: _isRefund ? 'Numéro de l\'avoir *' : 'Numéro de facture *',
                icon: Icons.numbers_rounded,
                textCapitalization: TextCapitalization.characters,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Champ obligatoire' : null,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _amountTtcCtrl,
                label: _isRefund
                    ? 'Montant TTC de l\'avoir (FCFA, sans le signe) *'
                    : 'Montant TTC (FCFA) *',
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
                    backgroundColor: _isRefund
                        ? AppTheme.getError(context)
                        : AppTheme.getPrimary(context),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 2,
                  ),
                  icon: Icon(_isRefund
                      ? Icons.undo_rounded
                      : Icons.check_circle_rounded),
                  label: Text(
                    _isRefund
                        ? 'Valider et enregistrer l\'avoir'
                        : 'Valider et créer la facture',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
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
      ),
    );
  }

  /// Sélecteur Facture / Avoir.
  ///
  /// Volontairement en haut du formulaire et impossible à manquer : c'est la
  /// seule information que ni le QR-code, ni la page DGI ne donnent d'un coup
  /// d'œil, et c'est celle qui décide du SENS de l'écriture comptable.
  Widget _buildDocumentTypeSelector(BuildContext context, bool isDark) {
    final errorColor = AppTheme.getError(context);
    final primaryColor = AppTheme.getPrimary(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<DocumentType>(
          segments: const [
            ButtonSegment<DocumentType>(
              value: DocumentType.invoice,
              icon: Icon(Icons.receipt_long_rounded, size: 18),
              label: Text('Facture'),
            ),
            ButtonSegment<DocumentType>(
              value: DocumentType.refund,
              icon: Icon(Icons.undo_rounded, size: 18),
              label: Text('Avoir'),
            ),
          ],
          selected: <DocumentType>{_documentType},
          showSelectedIcon: false,
          onSelectionChanged: (selection) {
            HapticFeedback.selectionClick();
            setState(() => _documentType = selection.first);
          },
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (!states.contains(WidgetState.selected)) return null;
              return (_isRefund ? errorColor : primaryColor)
                  .withValues(alpha: isDark ? 0.35 : 0.15);
            }),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: (_isRefund ? errorColor : primaryColor)
                .withValues(alpha: isDark ? 0.18 : 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: (_isRefund ? errorColor : primaryColor)
                  .withValues(alpha: 0.35),
            ),
          ),
          child: Row(
            children: [
              Icon(
                _isRefund ? Icons.undo_rounded : Icons.info_outline_rounded,
                color: _isRefund ? errorColor : primaryColor,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _isRefund
                      ? 'AVOIR : le fournisseur vous doit ce montant. '
                          'Un avoir fournisseur sera créé, et il viendra en '
                          'DÉDUCTION des coûts.'
                      : 'FACTURE : vous devez ce montant au fournisseur. '
                          'Une facture d\'achat sera créée.',
                  style: TextStyle(
                    color: AppTheme.getTextPrimary(context),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
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
                ? Colors.green.shade900.withValues(alpha: 0.2)
                : Colors.orange.shade900.withValues(alpha: 0.2))
            : (hasCodes ? Colors.green.shade50 : Colors.orange.shade50),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (hasCodes ? Colors.green : Colors.orange).withValues(alpha: 0.3),
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

  /// Montant TTC en valeur absolue : le sens est porté par [documentType].
  final double amountTtc;
  final DocumentType documentType;
  final double verificationDuration;

  const ManualEntryResult({
    required this.supplierName,
    this.supplierCodeDgi = '',
    this.customerName = '',
    this.customerCodeDgi = '',
    required this.invoiceNumberDgi,
    this.invoiceDate = '',
    required this.amountTtc,
    this.documentType = DocumentType.invoice,
    this.verificationDuration = 0,
  });

  bool get isRefund => documentType == DocumentType.refund;
}
