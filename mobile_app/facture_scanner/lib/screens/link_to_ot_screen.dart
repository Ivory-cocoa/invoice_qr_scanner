/// Link Scan to OT Screen — Gestionnaire OT
/// Permet de lier une facture scannée à un Ordre de Transit comme coût opérationnel.

import 'package:flutter/material.dart';

import '../core/services/api_service.dart';
import '../core/theme/app_theme.dart';

class LinkToOtScreen extends StatefulWidget {
  final int scanId;
  final String? invoiceLabel; // ex: "Facture 12345" pour affichage

  const LinkToOtScreen({
    super.key,
    required this.scanId,
    this.invoiceLabel,
  });

  @override
  State<LinkToOtScreen> createState() => _LinkToOtScreenState();
}

class _LinkToOtScreenState extends State<LinkToOtScreen> {
  final _api = ApiService();
  final _descCtrl = TextEditingController();
  final _otSearchCtrl = TextEditingController();

  List<Map<String, dynamic>> _ots = [];
  List<Map<String, dynamic>> _costTypes = [];
  List<Map<String, dynamic>> _existingCosts = [];

  Map<String, dynamic>? _selectedOt;
  String? _selectedCostType;
  Map<String, dynamic>? _selectedExisting;

  String _mode = 'create'; // 'create' | 'link_existing'

  bool _loadingOts = false;
  bool _loadingCosts = false;
  bool _loadingExisting = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _otSearchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    setState(() {
      _loadingOts = true;
      _loadingCosts = true;
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
      _loadingCosts = false;
      if (otsResp.success && otsResp.data != null) {
        _ots = List<Map<String, dynamic>>.from(otsResp.data!['ots'] ?? []);
      }
      if (ctResp.success && ctResp.data != null) {
        _costTypes = List<Map<String, dynamic>>.from(ctResp.data!['cost_types'] ?? []);
      }
    });
  }

  Future<void> _searchOts(String query) async {
    setState(() => _loadingOts = true);
    final resp = await _api.listOts(search: query);
    if (!mounted) return;
    setState(() {
      _loadingOts = false;
      if (resp.success && resp.data != null) {
        _ots = List<Map<String, dynamic>>.from(resp.data!['ots'] ?? []);
      }
    });
  }

  Future<void> _loadExistingCosts(int otId) async {
    setState(() {
      _loadingExisting = true;
      _existingCosts = [];
      _selectedExisting = null;
    });
    final resp = await _api.getOtExistingCosts(otId);
    if (!mounted) return;
    setState(() {
      _loadingExisting = false;
      if (resp.success && resp.data != null) {
        _existingCosts = List<Map<String, dynamic>>.from(resp.data!['lines'] ?? []);
      }
    });
  }

  bool get _canSubmit {
    if (_submitting || _selectedOt == null) return false;
    if (_mode == 'create') return _selectedCostType != null;
    return _selectedExisting != null;
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _submitting = true);
    final resp = await _api.linkScanToOt(
      scanId: widget.scanId,
      otId: _selectedOt!['id'] as int,
      mode: _mode,
      costType: _mode == 'create' ? _selectedCostType : null,
      costLineId: _mode == 'link_existing'
          ? _selectedExisting!['id'] as int
          : null,
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
    );
    if (!mounted) return;
    setState(() => _submitting = false);

    if (resp.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(resp.message ?? 'Scan lié avec succès'),
          backgroundColor: AppTheme.getSuccess(context),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(resp.errorMessage ?? 'Erreur'),
          backgroundColor: AppTheme.getError(context),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lier à un OT'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            children: [
              if (widget.invoiceLabel != null) ...[
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.receipt_long_rounded),
                    title: const Text('Facture scannée'),
                    subtitle: Text(widget.invoiceLabel!),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Recherche OT
              TextField(
                controller: _otSearchCtrl,
                decoration: InputDecoration(
                  labelText: 'Rechercher un OT (référence, nom, navire)',
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  suffixIcon: _loadingOts
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: () => _searchOts(_otSearchCtrl.text.trim()),
                        ),
                ),
                onSubmitted: _searchOts,
              ),
              const SizedBox(height: 12),

              // Liste des OTs
              if (_loadingOts)
                const Center(child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ))
              else if (_ots.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Aucun OT trouvé.'),
                )
              else
                Card(
                  child: Column(
                    children: _ots.map((ot) {
                      final isSelected = _selectedOt?['id'] == ot['id'];
                      return RadioListTile<int>(
                        value: ot['id'] as int,
                        groupValue: _selectedOt?['id'] as int?,
                        onChanged: (v) {
                          setState(() {
                            _selectedOt = ot;
                            _selectedExisting = null;
                            _existingCosts = [];
                          });
                          if (_mode == 'link_existing') {
                            _loadExistingCosts(ot['id'] as int);
                          }
                        },
                        title: Text(
                          ot['reference'] ?? '',
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          [
                            if ((ot['campaign'] ?? '').toString().isNotEmpty)
                              ot['campaign'],
                            if ((ot['vessel_name'] ?? '').toString().isNotEmpty)
                              'Navire ${ot['vessel_name']}',
                            ot['state_label'] ?? '',
                          ].where((e) => (e ?? '').toString().isNotEmpty).join(' • '),
                        ),
                        dense: true,
                      );
                    }).toList(),
                  ),
                ),

              const SizedBox(height: 16),

              // Mode
              if (_selectedOt != null) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: [
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'create',
                              label: Text('Créer un coût'),
                              icon: Icon(Icons.add_circle_outline),
                            ),
                            ButtonSegment(
                              value: 'link_existing',
                              label: Text('Lier à un existant'),
                              icon: Icon(Icons.link),
                            ),
                          ],
                          selected: {_mode},
                          onSelectionChanged: (s) {
                            final next = s.first;
                            setState(() => _mode = next);
                            if (next == 'link_existing' &&
                                _selectedOt != null &&
                                _existingCosts.isEmpty) {
                              _loadExistingCosts(_selectedOt!['id'] as int);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                if (_mode == 'create') ...[
                  if (_loadingCosts)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else
                    DropdownButtonFormField<String>(
                      value: _selectedCostType,
                      decoration: const InputDecoration(
                        labelText: 'Type de coût *',
                        border: OutlineInputBorder(),
                      ),
                      items: _costTypes
                          .map<DropdownMenuItem<String>>((ct) => DropdownMenuItem(
                                value: ct['value'] as String,
                                child: Text(ct['label'] as String),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedCostType = v),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _descCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Description (optionnel)',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                ] else ...[
                  if (_loadingExisting)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_existingCosts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        "Aucune ligne 'Estimé' libre disponible sur cet OT.",
                      ),
                    )
                  else
                    Card(
                      child: Column(
                        children: _existingCosts.map((line) {
                          return RadioListTile<int>(
                            value: line['id'] as int,
                            groupValue: _selectedExisting?['id'] as int?,
                            onChanged: (_) =>
                                setState(() => _selectedExisting = line),
                            title: Text(line['name'] ?? ''),
                            subtitle: Text(
                              '${line['cost_type_label'] ?? ''} • '
                              '${line['amount']?.toString() ?? '0'} '
                              '${line['currency'] ?? 'XOF'}',
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _canSubmit ? _submit : null,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    icon: _submitting
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_circle_outline),
                    label: Text(_submitting ? 'Envoi...' : 'Valider la liaison'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
