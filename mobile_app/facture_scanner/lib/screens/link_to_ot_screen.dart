/// Link Scan to OTs Screen — Gestionnaire OT (multi-OT)
/// Permet de lier une facture scannée (nouvelle OU déjà existante)
/// à un ou plusieurs Ordres de Transit en une seule opération.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/services/api_service.dart';
import '../core/theme/app_theme.dart';

/// Configuration de liaison pour un OT donné (modifiable par l'utilisateur).
class _OtLinkConfig {
  String mode; // 'create' | 'link_existing'
  String? costType;
  int? existingCostLineId;
  final TextEditingController amountCtrl;
  final TextEditingController descCtrl;
  List<Map<String, dynamic>> existingLines;
  bool loadingExisting;

  _OtLinkConfig({
    this.mode = 'create',
    this.costType,
    this.existingCostLineId,
    String initialAmount = '',
    String initialDesc = '',
    this.existingLines = const [],
    this.loadingExisting = false,
  })  : amountCtrl = TextEditingController(text: initialAmount),
        descCtrl = TextEditingController(text: initialDesc);

  void dispose() {
    amountCtrl.dispose();
    descCtrl.dispose();
  }

  Map<String, dynamic> toApiPayload(int otId) {
    final amountStr = amountCtrl.text.trim().replaceAll(',', '.');
    final amount = double.tryParse(amountStr);
    final desc = descCtrl.text.trim();
    return {
      'ot_id': otId,
      'mode': mode,
      if (mode == 'create' && costType != null) 'cost_type': costType,
      if (mode == 'link_existing' && existingCostLineId != null)
        'cost_line_id': existingCostLineId,
      if (amount != null) 'amount': amount,
      if (desc.isNotEmpty) 'description': desc,
    };
  }
}

class LinkToOtScreen extends StatefulWidget {
  final int scanId;
  final String? invoiceLabel;
  final double? invoiceAmount;

  const LinkToOtScreen({
    super.key,
    required this.scanId,
    this.invoiceLabel,
    this.invoiceAmount,
  });

  @override
  State<LinkToOtScreen> createState() => _LinkToOtScreenState();
}

class _LinkToOtScreenState extends State<LinkToOtScreen> {
  final _api = ApiService();
  final _otSearchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final GlobalKey _configSectionKey = GlobalKey();

  List<Map<String, dynamic>> _ots = [];
  List<Map<String, dynamic>> _costTypes = [];
  // OT id -> config
  final Map<int, _OtLinkConfig> _selected = {};
  // OT id -> data row (kept for header info even if filtered out by search)
  final Map<int, Map<String, dynamic>> _selectedOtData = {};

  bool _loadingOts = false;
  bool _loadingCostTypes = false;
  bool _submitting = false;
  String? _costTypesError;
  Timer? _searchDebounce;
  int _searchSeq = 0;

  @override
  void initState() {
    super.initState();
    _otSearchCtrl.addListener(_onSearchChanged);
    _loadInitial();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _otSearchCtrl.removeListener(_onSearchChanged);
    _otSearchCtrl.dispose();
    _scrollCtrl.dispose();
    for (final cfg in _selected.values) {
      cfg.dispose();
    }
    super.dispose();
  }

  void _onSearchChanged() {
    // Rebuild pour afficher/cacher le bouton clear, puis debounce la recherche
    if (mounted) setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _searchOts(_otSearchCtrl.text);
    });
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loadingOts = true;
      _loadingCostTypes = true;
      _costTypesError = null;
    });
    final results = await Future.wait([
      _api.listOts(),
      _api.getOtCostTypes(),
    ]);
    if (!mounted) return;
    final otsResp = results[0];
    final ctResp = results[1];
    setState(() {
      _loadingOts = false;
      _loadingCostTypes = false;
      if (otsResp.success && otsResp.data != null) {
        _ots = List<Map<String, dynamic>>.from(otsResp.data!['ots'] ?? []);
      }
      if (ctResp.success && ctResp.data != null) {
        _costTypes =
            List<Map<String, dynamic>>.from(ctResp.data!['cost_types'] ?? []);
        if (_costTypes.isEmpty) {
          _costTypesError = 'Aucun type de coût disponible';
        }
      } else {
        _costTypesError = ctResp.errorMessage ??
            'Impossible de charger les types de coût';
      }
    });
  }

  Future<void> _searchOts(String query) async {
    final seq = ++_searchSeq;
    setState(() => _loadingOts = true);
    final resp = await _api.listOts(search: query);
    if (!mounted || seq != _searchSeq) return; // résultat obsolète : ignore
    setState(() {
      _loadingOts = false;
      if (resp.success && resp.data != null) {
        _ots = List<Map<String, dynamic>>.from(resp.data!['ots'] ?? []);
      }
    });
  }

  void _toggleOt(Map<String, dynamic> ot, bool selected) {
    final int otId = ot['id'];
    final bool wasEmpty = _selected.isEmpty;
    setState(() {
      if (selected) {
        final defaultCostType = _costTypes.isNotEmpty
            ? _costTypes.first['value'] as String?
            : null;
        // Pré-remplit le montant avec le total de la facture si connu
        // (cas le plus courant : 1 OT = montant complet de la facture).
        final String initialAmount = widget.invoiceAmount != null
            ? widget.invoiceAmount!.toStringAsFixed(0)
            : '';
        _selected[otId] = _OtLinkConfig(
          costType: defaultCostType,
          initialAmount: initialAmount,
        );
        _selectedOtData[otId] = ot;
      } else {
        _selected.remove(otId)?.dispose();
        _selectedOtData.remove(otId);
      }
    });
    // Auto-scroll vers la config UNIQUEMENT à la 1ère sélection,
    // pour ne pas perturber la sélection multiple suivante.
    if (selected && wasEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToConfigSection();
      });
    }
  }

  /// Répartit équitablement le montant de la facture entre les OTs sélectionnés.
  void _splitEqually() {
    if (_selected.isEmpty || widget.invoiceAmount == null) return;
    final n = _selected.length;
    final share = (widget.invoiceAmount! / n);
    // Arrondi : (n-1) parts arrondies vers le bas, dernière part = reste exact
    final shareFloor = share.floorToDouble();
    final remainder = widget.invoiceAmount! - shareFloor * (n - 1);
    setState(() {
      final entries = _selected.entries.toList();
      for (var i = 0; i < entries.length; i++) {
        final amount = (i == entries.length - 1) ? remainder : shareFloor;
        entries[i].value.amountCtrl.text = amount.toStringAsFixed(0);
      }
    });
  }

  /// Remplit chaque OT avec le montant total de la facture (cas "même coût sur chaque OT").
  void _fillAllWithInvoiceAmount() {
    if (_selected.isEmpty || widget.invoiceAmount == null) return;
    setState(() {
      for (final cfg in _selected.values) {
        cfg.amountCtrl.text = widget.invoiceAmount!.toStringAsFixed(0);
      }
    });
  }

  /// Remet à 0 tous les montants pour repartir d'une feuille blanche.
  void _resetAllAmounts() {
    if (_selected.isEmpty) return;
    setState(() {
      for (final cfg in _selected.values) {
        cfg.amountCtrl.text = '';
      }
    });
  }

  /// Affecte le solde restant (facture - déjà alloué) à une seule ligne.
  void _fillRemainingOn(int otId) {
    if (widget.invoiceAmount == null || widget.invoiceAmount! <= 0) return;
    final cfg = _selected[otId];
    if (cfg == null) return;
    // Total alloué hors cette ligne
    double other = 0;
    for (final e in _selected.entries) {
      if (e.key == otId) continue;
      final v = double.tryParse(
          e.value.amountCtrl.text.trim().replaceAll(',', '.'));
      if (v != null) other += v;
    }
    final remaining = widget.invoiceAmount! - other;
    setState(() {
      cfg.amountCtrl.text = remaining > 0 ? remaining.toStringAsFixed(0) : '0';
    });
  }

  void _scrollToConfigSection() {
    final ctx = _configSectionKey.currentContext;
    if (ctx == null || !_scrollCtrl.hasClients) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      alignment: 0.0,
    );
  }

  void _scrollToTop() {
    if (!_scrollCtrl.hasClients) return;
    _scrollCtrl.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> _loadExistingFor(int otId) async {
    final cfg = _selected[otId];
    if (cfg == null) return;
    setState(() {
      cfg.loadingExisting = true;
      cfg.existingLines = [];
      cfg.existingCostLineId = null;
    });
    final resp = await _api.getOtExistingCosts(otId);
    if (!mounted) return;
    setState(() {
      cfg.loadingExisting = false;
      if (resp.success && resp.data != null) {
        cfg.existingLines =
            List<Map<String, dynamic>>.from(resp.data!['lines'] ?? []);
      }
    });
  }

  double get _totalAmount {
    double total = 0;
    for (final cfg in _selected.values) {
      final v = double.tryParse(cfg.amountCtrl.text.trim().replaceAll(',', '.'));
      if (v != null) total += v;
    }
    return total;
  }

  String? _validateBeforeSubmit() {
    if (_selected.isEmpty) return "Sélectionnez au moins un OT";
    for (final entry in _selected.entries) {
      final otId = entry.key;
      final cfg = entry.value;
      final ref = _selectedOtData[otId]?['reference'] ?? 'OT #$otId';
      final issue = _cardIssue(otId, cfg);
      if (issue != null) return '$ref : $issue';
    }
    return null;
  }

  /// Renvoie un message d'erreur si la config d'un OT est invalide, ou null si OK.
  String? _cardIssue(int otId, _OtLinkConfig cfg) {
    if (cfg.mode == 'create' &&
        (cfg.costType == null || cfg.costType!.isEmpty)) {
      return 'Type de coût manquant';
    }
    if (cfg.mode == 'link_existing' && cfg.existingCostLineId == null) {
      return 'Aucune ligne existante sélectionnée';
    }
    final amountStr = cfg.amountCtrl.text.trim();
    if (amountStr.isEmpty) return 'Montant manquant';
    final amount = double.tryParse(amountStr.replaceAll(',', '.'));
    if (amount == null || amount <= 0) return 'Montant invalide';
    return null;
  }

  Future<void> _submit() async {
    final error = _validateBeforeSubmit();
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: AppTheme.getError(context)),
      );
      return;
    }
    setState(() => _submitting = true);
    final payload = _selected.entries
        .map((e) => e.value.toApiPayload(e.key))
        .toList();
    final resp = await _api.linkScanToOts(
      scanId: widget.scanId,
      links: payload,
    );
    if (!mounted) return;
    setState(() => _submitting = false);
    if (!resp.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(resp.errorMessage ?? "Échec de la liaison"),
          backgroundColor: AppTheme.getError(context),
        ),
      );
      return;
    }
    final data = resp.data ?? {};
    final totalLinked = data['total_linked'] ?? 0;
    final totalErrors = data['total_errors'] ?? 0;
    final results = List<Map<String, dynamic>>.from(data['results'] ?? []);
    final hasErrors = totalErrors > 0;
    if (hasErrors) {
      await _showResultsDialog(totalLinked, totalErrors, results);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("$totalLinked OT(s) lié(s) avec succès"),
          backgroundColor: AppTheme.getSuccess(context),
        ),
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _showResultsDialog(
      int linked, int errors, List<Map<String, dynamic>> results) async {
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text("$linked succès, $errors erreur(s)"),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: results.map((r) {
              final status = r['status'] ?? 'error';
              IconData icon;
              Color color;
              switch (status) {
                case 'created':
                  icon = Icons.add_circle;
                  color = AppTheme.getSuccess(context);
                  break;
                case 'linked':
                  icon = Icons.link;
                  color = AppTheme.getSuccess(context);
                  break;
                case 'already_linked':
                  icon = Icons.info;
                  color = Colors.blue;
                  break;
                default:
                  icon = Icons.error;
                  color = AppTheme.getError(context);
              }
              return ListTile(
                leading: Icon(icon, color: color),
                title: Text(_selectedOtData[r['ot_id']]?['reference'] ??
                    'OT #${r['ot_id']}'),
                subtitle: Text(_statusLabel(status, r['error_message'])),
              );
            }).toList(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _statusLabel(String status, dynamic msg) {
    switch (status) {
      case 'created':
        return 'Coût créé';
      case 'linked':
        return 'Lié à ligne existante';
      case 'already_linked':
        return 'Déjà lié (idempotent)';
      default:
        return msg?.toString() ?? 'Erreur';
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.getPrimary(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lier à des OTs'),
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            if (_costTypesError != null) _buildCostTypesErrorBanner(),
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollCtrl,
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildOtSelectionSection(),
                    if (_selected.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      _buildConfigSection(),
                    ],
                    const SizedBox(height: 80), // espace pour bouton flottant
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: AppTheme.getPrimary(context).withValues(alpha: 0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Facture à lier',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.getTextMuted(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.invoiceLabel ?? 'Scan #${widget.scanId}',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppTheme.getTextPrimary(context),
            ),
          ),
          if (widget.invoiceAmount != null && widget.invoiceAmount! > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Montant facture : ${_formatXof(widget.invoiceAmount!)}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppTheme.getPrimary(context),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatXof(double v) {
    final s = v.toStringAsFixed(0);
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return '${buf.toString()} XOF';
  }

  Widget _buildCostTypesErrorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: AppTheme.getError(context).withValues(alpha: 0.10),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded,
              color: AppTheme.getError(context), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _costTypesError ?? '',
              style: TextStyle(
                  color: AppTheme.getError(context), fontSize: 12),
            ),
          ),
          TextButton(
            onPressed: _loadInitial,
            child: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }

  Widget _buildOtSelectionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('1. Sélection des OTs',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Spacer(),
            if (_selected.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.getPrimary(context),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_selected.length} sélectionné(s)',
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _otSearchCtrl,
          decoration: InputDecoration(
            hintText: 'Rechercher (référence, navire...)',
            prefixIcon: const Icon(Icons.search),
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: _otSearchCtrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: 'Effacer',
                    onPressed: () {
                      _otSearchCtrl.clear();
                      _searchOts('');
                    },
                  )
                : null,
          ),
          // Le listener déclenche la recherche debouncée à chaque frappe.
          onSubmitted: (q) {
            _searchDebounce?.cancel();
            _searchOts(q);
          },
        ),
        const SizedBox(height: 8),
        if (_loadingOts)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_ots.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Aucun OT trouvé',
              style: TextStyle(color: AppTheme.getTextMuted(context)),
            ),
          )
        else
          Container(
            constraints: const BoxConstraints(maxHeight: 280),
            decoration: BoxDecoration(
              border: Border.all(color: AppTheme.getDivider(context)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _ots.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final ot = _ots[i];
                final id = ot['id'] as int;
                final isSel = _selected.containsKey(id);
                return CheckboxListTile(
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: isSel,
                  onChanged: (v) => _toggleOt(ot, v == true),
                  title: Text(
                    ot['reference']?.toString() ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    [
                      if ((ot['vessel_name'] ?? '').toString().isNotEmpty)
                        ot['vessel_name'],
                      if ((ot['campaign'] ?? '').toString().isNotEmpty)
                        ot['campaign'],
                      ot['state_label'],
                    ].where((e) => e != null && e.toString().isNotEmpty)
                        .join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildConfigSection() {
    return Column(
      key: _configSectionKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('2. Configuration des liens',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.getPrimary(context),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${_selected.length} à configurer',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Choisissez le type de coût et le montant pour chaque OT.',
          style: TextStyle(
              fontSize: 12, color: AppTheme.getTextMuted(context)),
        ),
        // Actions rapides de répartition (uniquement si le montant facture est connu)
        if (widget.invoiceAmount != null && widget.invoiceAmount! > 0) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (_selected.length >= 2)
                OutlinedButton.icon(
                  onPressed: _splitEqually,
                  icon: const Icon(Icons.call_split, size: 16),
                  label: const Text('Répartir équitablement'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              OutlinedButton.icon(
                onPressed: _fillAllWithInvoiceAmount,
                icon: const Icon(Icons.content_copy, size: 16),
                label: Text(_selected.length >= 2
                    ? 'Même montant partout'
                    : 'Utiliser montant facture'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
              OutlinedButton.icon(
                onPressed: _resetAllAmounts,
                icon: const Icon(Icons.restart_alt, size: 16),
                label: const Text('Réinitialiser'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  foregroundColor: AppTheme.getError(context),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        ..._selected.entries.map((entry) {
          final otId = entry.key;
          final cfg = entry.value;
          final ot = _selectedOtData[otId] ?? {};
          return _buildOtConfigCard(otId, cfg, ot);
        }),
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            onPressed: _scrollToTop,
            icon: const Icon(Icons.add_circle_outline, size: 18),
            label: const Text('Ajouter un autre OT'),
          ),
        ),
      ],
    );
  }

  Widget _buildOtConfigCard(
      int otId, _OtLinkConfig cfg, Map<String, dynamic> ot) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header avec OT + bouton supprimer
            Row(
              children: [
                Expanded(
                  child: Text(
                    ot['reference']?.toString() ?? 'OT #$otId',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => _toggleOt(ot, false),
                  tooltip: 'Retirer',
                ),
              ],
            ),
            // Mode toggle
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'create',
                  label: Text('Créer'),
                  icon: Icon(Icons.add, size: 16),
                ),
                ButtonSegment(
                  value: 'link_existing',
                  label: Text('Lier existant'),
                  icon: Icon(Icons.link, size: 16),
                ),
              ],
              selected: {cfg.mode},
              onSelectionChanged: (s) {
                setState(() {
                  cfg.mode = s.first;
                  if (cfg.mode == 'link_existing' &&
                      cfg.existingLines.isEmpty &&
                      !cfg.loadingExisting) {
                    _loadExistingFor(otId);
                  }
                });
              },
            ),
            const SizedBox(height: 12),
            if (cfg.mode == 'create') ...[
              DropdownButtonFormField<String>(
                value: cfg.costType,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Type de coût *',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  helperText: _costTypes.isEmpty
                      ? 'Chargement des types de coût...'
                      : null,
                ),
                items: _costTypes.map((ct) {
                  return DropdownMenuItem<String>(
                    value: ct['value'] as String,
                    child: Text(
                      ct['label']?.toString() ?? '',
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: _costTypes.isEmpty
                    ? null
                    : (v) => setState(() => cfg.costType = v),
              ),
            ] else ...[
              if (cfg.loadingExisting)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (cfg.existingLines.isEmpty)
                Text(
                  'Aucune ligne estimée disponible',
                  style: TextStyle(color: AppTheme.getTextMuted(context)),
                )
              else
                DropdownButtonFormField<int>(
                  value: cfg.existingCostLineId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Ligne estimée',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: cfg.existingLines.map((l) {
                    return DropdownMenuItem<int>(
                      value: l['id'] as int,
                      child: Text(
                        '${l['cost_type_label']} • ${l['amount']} ${l['currency']}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (v) {
                    setState(() {
                      cfg.existingCostLineId = v;
                      // Pré-remplir le montant avec celui de la ligne sélectionnée
                      final match = cfg.existingLines
                          .firstWhere((l) => l['id'] == v, orElse: () => {});
                      final amt = match['amount'];
                      if (amt != null) {
                        cfg.amountCtrl.text = amt.toString();
                      }
                    });
                  },
                ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: cfg.amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: InputDecoration(
                labelText: 'Montant',
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: (widget.invoiceAmount != null &&
                        widget.invoiceAmount! > 0)
                    ? IconButton(
                        icon: const Icon(Icons.swap_horiz, size: 18),
                        tooltip: 'Affecter le solde restant',
                        onPressed: () => _fillRemainingOn(otId),
                      )
                    : null,
              ),
              onChanged: (_) => setState(() {}), // pour recalculer total
            ),
            const SizedBox(height: 8),
            TextField(
              controller: cfg.descCtrl,
              decoration: const InputDecoration(
                labelText: 'Description (optionnel)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 2,
            ),
            // Badge de validation inline
            Builder(builder: (_) {
              final issue = _cardIssue(otId, cfg);
              if (issue == null) {
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(children: [
                    Icon(Icons.check_circle,
                        size: 14, color: AppTheme.getSuccess(context)),
                    const SizedBox(width: 4),
                    Text('Prêt',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.getSuccess(context))),
                  ]),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  Icon(Icons.error_outline,
                      size: 14, color: AppTheme.getError(context)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(issue,
                        style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.getError(context))),
                  ),
                ]),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    if (_selected.isEmpty) {
      return const SizedBox.shrink();
    }
    final invAmount = widget.invoiceAmount;
    final hasInvoice = invAmount != null && invAmount > 0;
    final delta = hasInvoice ? (_totalAmount - invAmount) : 0.0;
    final matches = hasInvoice && delta.abs() < 1.0;
    // Couleur de progression : vert si match, orange si sous-alloué, rouge si dépassement
    Color progressColor;
    if (!hasInvoice) {
      progressColor = AppTheme.getPrimary(context);
    } else if (matches) {
      progressColor = AppTheme.getSuccess(context);
    } else if (delta > 0) {
      progressColor = AppTheme.getError(context);
    } else {
      progressColor = Colors.orange;
    }
    final progressValue = hasInvoice
        ? (_totalAmount / invAmount).clamp(0.0, 1.0).toDouble()
        : 0.0;
    // Validation globale
    final globalIssue = _validateBeforeSubmit();
    final canSubmit = globalIssue == null && !_submitting;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(
            top: BorderSide(color: AppTheme.getDivider(context)),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasInvoice) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progressValue,
                minHeight: 6,
                backgroundColor: AppTheme.getDivider(context),
                valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Total ${_selected.length} OT(s)',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppTheme.getTextMuted(context),
                          ),
                        ),
                        if (hasInvoice) ...[
                          const SizedBox(width: 6),
                          Icon(
                            matches ? Icons.check_circle : Icons.info_outline,
                            size: 14,
                            color: progressColor,
                          ),
                        ],
                      ],
                    ),
                    Text(
                      _formatXof(_totalAmount),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: progressColor,
                      ),
                    ),
                    if (hasInvoice && !matches)
                      Text(
                        delta > 0
                            ? '⚠ +${_formatXof(delta)} au-delà du facturé'
                            : '${_formatXof(delta.abs())} restant à allouer',
                        style: TextStyle(
                          fontSize: 11,
                          color: progressColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    if (globalIssue != null && _selected.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          globalIssue,
                          style: TextStyle(
                            fontSize: 10,
                            color: AppTheme.getError(context),
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: canSubmit ? _submit : null,
                icon: _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.link),
                label: Text(_submitting
                    ? 'Envoi...'
                    : 'Lier ${_selected.length} OT(s)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.getPrimary(context),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade400,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 14),
                ),
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }
}
