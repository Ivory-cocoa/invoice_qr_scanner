/// Invoice Picker Screen — Gestionnaire OT
/// Liste paginée des factures déjà scannées : recherche d'une facture,
/// filtre « liées à un OT / non liées », et ouverture d'une facture pour
/// voir ses OT et la lier à un ou plusieurs OTs.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../core/services/api_service.dart';
import '../core/theme/app_theme.dart';
import '../widgets/invoice_status_sheet.dart';
import 'link_to_ot_screen.dart';

/// Filtre de la liste selon le lien aux OT.
enum InvoiceLinkFilter {
  all('all', 'Toutes'),
  linked('linked', 'Liées à un OT'),
  unlinked('unlinked', 'Non liées');

  const InvoiceLinkFilter(this.apiValue, this.label);
  final String apiValue;
  final String label;

  /// Garde une facture selon son nombre d'OT liés. Sert de filet quand le
  /// serveur (ancienne version) ignore le filtre demandé.
  bool keeps(int linkedOtCount) => switch (this) {
    InvoiceLinkFilter.all => true,
    InvoiceLinkFilter.linked => linkedOtCount > 0,
    InvoiceLinkFilter.unlinked => linkedOtCount == 0,
  };
}

class InvoicePickerScreen extends StatefulWidget {
  const InvoicePickerScreen({
    super.key,
    this.initialFilter = InvoiceLinkFilter.all,
  });

  /// Filtre affiché à l'ouverture (l'utilisateur peut en changer).
  final InvoiceLinkFilter initialFilter;

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
  late InvoiceLinkFilter _filter = widget.initialFilter;
  // Chaque chargement porte un numéro : une réponse arrivée après un
  // changement de recherche ou de filtre est ignorée.
  int _generation = 0;
  int _autoLoads = 0;
  static const int _maxAutoLoads = 5;

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
    if (_loading && !reset) return;
    if (reset) _generation++;
    final generation = _generation;
    final filter = _filter;
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
      linkState: filter.apiValue,
    );
    if (!mounted || generation != _generation) return;
    setState(() {
      _loading = false;
      if (resp.success && resp.data != null) {
        final data = resp.data!;
        final records = List<Map<String, dynamic>>.from(
          data['records'] ?? const [],
        );
        _items.addAll(records.where((r) => filter.keeps(_linkedCount(r))));
        final pag = data['pagination'] as Map<String, dynamic>?;
        _hasNext = pag?['has_next'] == true;
        if (_hasNext) _page += 1;
      } else {
        _error = resp.errorMessage ?? 'Erreur de chargement';
      }
    });
    // Filet pour un serveur ancien qui ignore le filtre : la page reçue peut
    // être presque vide une fois filtrée, donc impossible à faire défiler.
    // On enchaîne alors quelques pages, sans jamais boucler sans fin.
    if (reset) _autoLoads = 0;
    if (_error == null &&
        _hasNext &&
        _items.length < _limit &&
        _autoLoads < _maxAutoLoads) {
      _autoLoads++;
      await _load();
    }
  }

  static int _linkedCount(Map<String, dynamic> scan) =>
      (scan['linked_ot_count'] as num?)?.toInt() ?? 0;

  void _onFilterChanged(InvoiceLinkFilter filter) {
    if (filter == _filter) return;
    setState(() => _filter = filter);
    _load(reset: true);
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
    final isRefund =
        (scan['is_refund'] as bool?) ??
        ((scan['document_type'] as String?) == 'refund');
    final kind = isRefund ? 'Avoir' : 'Facture';
    final label = invoiceNum.isNotEmpty
        ? '$kind $invoiceNum${supplier.isNotEmpty ? ' • $supplier' : ''}'
        : (supplier.isNotEmpty ? supplier : kind);
    final scanId = scan['id'] as int;
    // Valeur absolue : le signe est appliqué par le serveur d'après la nature.
    final fallbackAmount = (scan['amount_ttc'] as num?)?.toDouble().abs();

    // Récupérer le statut OT pour présenter le sheet (Cas A/B/C) avant
    // d'ouvrir l'écran de liaison.
    final statusResp = await _api.getScanOtStatus(scanId);
    if (!mounted) return;

    double? amountToAllocate = fallbackAmount;
    if (statusResp.success && statusResp.data != null) {
      final result = await showInvoiceStatusSheet(
        context,
        status: statusResp.data!,
      );
      if (!mounted) return;
      if (result.action == InvoiceStatusAction.close) {
        return;
      }
      amountToAllocate = result.amountToAllocate ?? amountToAllocate;
    }

    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => LinkToOtScreen(
          scanId: scanId,
          invoiceLabel: label,
          invoiceAmount: amountToAllocate,
          isRefund: isRefund,
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
      appBar: AppBar(title: const Text('Factures scannées')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
              child: TextField(
                controller: _searchCtrl,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'N° de facture, fournisseur, OT…',
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
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 0,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  for (final filter in InvoiceLinkFilter.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(filter.label),
                        selected: _filter == filter,
                        onSelected: (_) => _onFilterChanged(filter),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _load(reset: true),
                color: primary,
                child: _buildList(primary),
              ),
            ),
          ],
        ),
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
          Icon(
            Icons.error_outline_rounded,
            size: 64,
            color: AppTheme.getError(context),
          ),
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
        children: [
          const SizedBox(height: 80),
          const Icon(Icons.inbox_rounded, size: 64, color: Colors.grey),
          const SizedBox(height: 12),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(switch (_filter) {
                InvoiceLinkFilter.linked =>
                  'Aucune facture liée à un OT ne correspond.',
                InvoiceLinkFilter.unlinked =>
                  'Aucune facture non liée ne correspond.',
                InvoiceLinkFilter.all => 'Aucune facture scannée trouvée.',
              }, textAlign: TextAlign.center),
            ),
          ),
        ],
      );
    }
    return ListView.separated(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      itemCount: _items.length + (_hasNext ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 8),
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
        final linkedCount = _linkedCount(s);
        final otRefs = (s['linked_ot_refs'] ?? '').toString();
        final linkColor = linkedCount > 0
            ? AppTheme.getSuccess(context)
            : AppTheme.getWarning(context);

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
                      color: primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.receipt_long_rounded,
                      color: primary,
                      size: 24,
                    ),
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
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        // Le numéro de facture n'est jamais coupé : c'est lui
                        // que l'on compare au papier. Il rétrécit au besoin.
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            invoiceNum.isNotEmpty
                                ? 'N° $invoiceNum'
                                : (ref.isNotEmpty ? ref : '—'),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.2,
                              color: AppTheme.getTextPrimary(context),
                            ),
                            maxLines: 1,
                            softWrap: false,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.event_rounded,
                              size: 13,
                              color: AppTheme.getTextSecondary(context),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              date.isNotEmpty ? date : '—',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.getTextSecondary(context),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _formatAmount(amount, currency),
                                textAlign: TextAlign.end,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // Liée ou non : l'information que le Gestionnaire OT
                        // vient chercher, toujours affichée.
                        Row(
                          children: [
                            Icon(
                              linkedCount > 0
                                  ? Icons.link_rounded
                                  : Icons.link_off_rounded,
                              size: 14,
                              color: linkColor,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                linkedCount == 0
                                    ? 'Non liée à un OT'
                                    : otRefs.isNotEmpty
                                    ? 'Liée : $otRefs'
                                    : '$linkedCount OT(s) lié(s)',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: linkColor,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: AppTheme.getTextMuted(context),
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
