/// Invoice Picker Screen — Gestionnaire OT
/// Liste paginée des factures déjà scannées, sélectionnables pour
/// être liées à un ou plusieurs OTs.

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/services/api_service.dart';
import '../core/theme/app_theme.dart';
import 'link_to_ot_screen.dart';

class InvoicePickerScreen extends StatefulWidget {
  const InvoicePickerScreen({super.key});

  @override
  State<InvoicePickerScreen> createState() => _InvoicePickerScreenState();
}

class _InvoicePickerScreenState extends State<InvoicePickerScreen> {
  final _api = ApiService();
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  Timer? _debounce;

  final List<Map<String, dynamic>> _items = [];
  int _page = 1;
  static const int _limit = 20;
  bool _loading = false;
  bool _hasNext = true;
  String? _error;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_loading || !_hasNext) return;
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      _load();
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      if (reset) {
        _error = null;
        _page = 1;
        _items.clear();
        _hasNext = true;
      }
    });
    final resp = await _api.getLinkableScans(
      search: _search,
      page: _page,
      limit: _limit,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (resp.success && resp.data != null) {
        final data = resp.data!;
        final records =
            List<Map<String, dynamic>>.from(data['records'] ?? const []);
        _items.addAll(records);
        final pag = data['pagination'] as Map<String, dynamic>?;
        _hasNext = pag?['has_next'] == true;
        if (_hasNext) _page += 1;
      } else {
        _error = resp.errorMessage ?? 'Erreur de chargement';
      }
    });
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => _search = v.trim());
      _load(reset: true);
    });
  }

  Future<void> _openLink(Map<String, dynamic> scan) async {
    final supplier = (scan['supplier_name'] ?? '').toString();
    final invoiceNum = (scan['invoice_number_dgi'] ?? '').toString();
    final label = invoiceNum.isNotEmpty
        ? 'Facture $invoiceNum${supplier.isNotEmpty ? ' • $supplier' : ''}'
        : (supplier.isNotEmpty ? supplier : 'Facture');
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => LinkToOtScreen(
          scanId: scan['id'] as int,
          invoiceLabel: label,
          invoiceAmount: (scan['amount_ttc'] as num?)?.toDouble(),
        ),
      ),
    );
    if (result == true && mounted) {
      // Une liaison vient d'être créée : recharger la liste pour mettre
      // à jour le compteur `linked_ot_count`.
      _load(reset: true);
    }
  }

  String _formatAmount(num? v, String currency) {
    if (v == null) return '0 $currency';
    final s = v.toStringAsFixed(0);
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return '${buf.toString()} $currency';
  }

  String _formatDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    try {
      final d = DateTime.parse(iso).toLocal();
      return '${d.day.toString().padLeft(2, '0')}/'
          '${d.month.toString().padLeft(2, '0')}/${d.year}';
    } catch (_) {
      return iso;
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.getPrimary(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sélectionner une facture'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Rechercher (fournisseur, n° facture, ref)',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchCtrl.clear();
                          _onSearchChanged('');
                        },
                      ),
                filled: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _load(reset: true),
              color: primary,
              child: _buildList(primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(Color primary) {
    if (_loading && _items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Icon(Icons.error_outline_rounded,
              size: 64, color: AppTheme.getError(context)),
          const SizedBox(height: 12),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(_error!, textAlign: TextAlign.center),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: ElevatedButton.icon(
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Réessayer'),
              onPressed: () => _load(reset: true),
            ),
          ),
        ],
      );
    }
    if (_items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 80),
          Icon(Icons.inbox_rounded, size: 64, color: Colors.grey),
          SizedBox(height: 12),
          Center(child: Text('Aucune facture scannée trouvée.')),
        ],
      );
    }
    return ListView.separated(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      itemCount: _items.length + (_hasNext ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        if (i >= _items.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final s = _items[i];
        final supplier = (s['supplier_name'] ?? '').toString();
        final invoiceNum = (s['invoice_number_dgi'] ?? '').toString();
        final amount = (s['amount_ttc'] as num?) ?? 0;
        final currency = (s['currency'] ?? 'XOF').toString();
        final date = _formatDate(s['invoice_date']?.toString());
        final ref = (s['reference'] ?? '').toString();
        final linkedCount = (s['linked_ot_count'] ?? 0) as int;

        return Material(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          elevation: 1.5,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _openLink(s),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: primary.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.receipt_long_rounded,
                        color: primary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          supplier.isEmpty ? 'Fournisseur inconnu' : supplier,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          invoiceNum.isNotEmpty
                              ? 'Facture $invoiceNum'
                              : (ref.isNotEmpty ? ref : '—'),
                          style: TextStyle(
                            fontSize: 13,
                            color: AppTheme.getTextSecondary(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.event_rounded,
                                size: 13,
                                color: AppTheme.getTextMuted(context)),
                            const SizedBox(width: 4),
                            Text(
                              date.isNotEmpty ? date : '—',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.getTextMuted(context),
                              ),
                            ),
                            const SizedBox(width: 12),
                            if (linkedCount > 0) ...[
                              Icon(Icons.link_rounded,
                                  size: 13, color: primary),
                              const SizedBox(width: 4),
                              Text(
                                '$linkedCount OT(s) lié(s)',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: primary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _formatAmount(amount, currency),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Icon(Icons.chevron_right_rounded,
                          color: AppTheme.getTextMuted(context)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
