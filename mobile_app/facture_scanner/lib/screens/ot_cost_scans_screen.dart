/// OT Cost Scans Screen
/// =====================
/// Consultation par QR-code (ou recherche autocomplete) d'un Ordre de Transit
/// et affichage de tous les coûts opérationnels + scans liés + état paiement.
///
/// Trois modes d'entrée :
///   - Aucun argument  → autocomplete uniquement
///   - [initialOtId]   → chargement direct par ID
///   - [qrPayload]     → résolution serveur du QR `ICP-OT:<ref>|<token>`
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/services/api_service.dart';
import '../core/theme/app_theme.dart';

class OtCostScansScreen extends StatefulWidget {
  final int? initialOtId;
  final String? qrPayload;

  const OtCostScansScreen({super.key, this.initialOtId, this.qrPayload});

  @override
  State<OtCostScansScreen> createState() => _OtCostScansScreenState();
}

class _OtCostScansScreenState extends State<OtCostScansScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _searchCtrl = TextEditingController();
  final NumberFormat _money = NumberFormat.currency(
    locale: 'fr_FR', symbol: '', decimalDigits: 0,
  );

  Timer? _debounce;
  bool _loading = false;
  bool _searching = false;
  String? _error;
  Map<String, dynamic>? _payload;
  List<Map<String, dynamic>> _suggestions = [];

  @override
  void initState() {
    super.initState();
    if (widget.qrPayload != null && widget.qrPayload!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadByQr(widget.qrPayload!));
    } else if (widget.initialOtId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadById(widget.initialOtId!));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Chargement données
  // ---------------------------------------------------------------------------

  Future<void> _loadById(int otId) async {
    setState(() { _loading = true; _error = null; });
    final resp = await _api.getOtCostScans(otId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (resp.success && resp.data != null) {
        _payload = resp.data;
        _error = null;
      } else {
        _error = resp.errorMessage ?? 'Erreur de chargement';
        _payload = null;
      }
    });
  }

  Future<void> _loadByQr(String payload) async {
    setState(() { _loading = true; _error = null; });
    final resp = await _api.getOtByQr(payload);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (resp.success && resp.data != null) {
        _payload = resp.data;
        _error = null;
      } else {
        _error = resp.errorMessage ?? 'QR-OT invalide';
        _payload = null;
      }
    });
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _runSearch(q.trim()));
  }

  Future<void> _runSearch(String q) async {
    setState(() => _searching = true);
    final resp = await _api.searchOts(query: q, limit: 15);
    if (!mounted) return;
    setState(() {
      _searching = false;
      if (resp.success && resp.data != null) {
        _suggestions = List<Map<String, dynamic>>.from(resp.data!['ots'] ?? []);
      } else {
        _suggestions = [];
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Scan QR-OT
  // ---------------------------------------------------------------------------

  Future<void> _openQrScanner() async {
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _OtQrScannerPage()),
    );
    if (scanned != null && scanned.isNotEmpty) {
      _loadByQr(scanned);
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.isDark(context) ? AppTheme.darkSurface : AppTheme.primarySurface,
      appBar: AppBar(
        title: const Text('Consulter un OT'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Scanner un QR-OT',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: _openQrScanner,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildSearchBar(),
            if (_suggestions.isNotEmpty) _buildSuggestions(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: AppTheme.getSurfaceElevated(context),
      child: TextField(
        controller: _searchCtrl,
        onChanged: _onSearchChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Rechercher par référence OT, navire…',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searching
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : (_searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _suggestions = []);
                      },
                    )
                  : null),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: AppTheme.primarySurface,
        ),
      ),
    );
  }

  Widget _buildSuggestions() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 240),
      color: AppTheme.getSurfaceElevated(context),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: _suggestions.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (_, i) {
          final ot = _suggestions[i];
          final cnt = ot['cost_count'] ?? 0;
          return ListTile(
            dense: true,
            leading: const Icon(Icons.local_shipping, color: AppTheme.primaryColor),
            title: Text(
              ot['ot_reference'] ?? ot['name'] ?? '—',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              [
                if ((ot['vessel_name'] ?? '').toString().isNotEmpty) 'Navire: ${ot['vessel_name']}',
                if ((ot['state_label'] ?? '').toString().isNotEmpty) ot['state_label'],
              ].join(' • '),
              maxLines: 1, overflow: TextOverflow.ellipsis,
            ),
            trailing: Chip(
              label: Text('$cnt coût${cnt == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 11)),
              backgroundColor: AppTheme.primarySurface,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onTap: () {
              FocusScope.of(context).unfocus();
              _searchCtrl.text = (ot['ot_reference'] ?? '').toString();
              setState(() => _suggestions = []);
              _loadById(ot['id']);
            },
          );
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _buildErrorState(_error!);
    }
    if (_payload == null) {
      return _buildInitialEmptyState();
    }
    return RefreshIndicator(
      onRefresh: () async {
        final otId = (_payload!['ot'] as Map)['id'];
        await _loadById(otId);
      },
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _buildOtHeader(_payload!['ot'] as Map<String, dynamic>),
          const SizedBox(height: 12),
          _buildSummary(_payload!),
          const SizedBox(height: 12),
          if (!(_payload!['has_cost_lines'] ?? false))
            _buildNoCostsState(_payload!['message'] ?? '')
          else
            ..._buildCostLines(_payload!['cost_lines'] as List),
        ],
      ),
    );
  }

  Widget _buildErrorState(String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: AppTheme.errorColor),
            const SizedBox(height: 12),
            Text(msg, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scanner un QR-OT'),
              onPressed: _openQrScanner,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInitialEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.qr_code_2, size: 96, color: AppTheme.primaryColor.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            const Text(
              'Scannez le QR-code d\'un OT ou recherchez-le par référence pour afficher ses coûts opérationnels.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Colors.black54),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scanner un QR-OT'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
              onPressed: _openQrScanner,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoCostsState(String msg) {
    return Card(
      color: AppTheme.warningLight,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: AppTheme.warningColor, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                msg.isNotEmpty ? msg : 'Aucun coût opérationnel sur cet OT.',
                style: TextStyle(
                  fontSize: 15,
                  color: AppTheme.warningColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOtHeader(Map<String, dynamic> ot) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primarySurface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.local_shipping, color: AppTheme.primaryColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ot['ot_reference'] ?? '—',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      if ((ot['name'] ?? '').toString().isNotEmpty &&
                          ot['name'] != ot['ot_reference'])
                        Text(ot['name'], style: const TextStyle(color: Colors.black54)),
                    ],
                  ),
                ),
                if ((ot['state_label'] ?? '').toString().isNotEmpty)
                  Chip(
                    label: Text(ot['state_label'],
                        style: const TextStyle(fontSize: 11, color: Colors.white)),
                    backgroundColor: AppTheme.primaryColor,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if ((ot['vessel_name'] ?? '').toString().isNotEmpty)
              _infoRow(Icons.directions_boat, 'Navire', ot['vessel_name']),
            if ((ot['customer_name'] ?? '').toString().isNotEmpty)
              _infoRow(Icons.business, 'Client', ot['customer_name']),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.black54),
          const SizedBox(width: 6),
          Text('$label: ', style: const TextStyle(color: Colors.black54, fontSize: 13)),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(Map<String, dynamic> data) {
    final cur = data['currency'] ?? 'XOF';
    final total = (data['total_amount'] ?? 0).toDouble();
    final paid = (data['total_paid'] ?? 0).toDouble();
    final pending = (data['total_pending'] ?? 0).toDouble();
    final count = data['cost_count'] ?? 0;
    final scans = data['scans_count'] ?? 0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: _miniStat('Coûts', '$count', Icons.list_alt, AppTheme.primaryColor)),
                Expanded(child: _miniStat('Scans', '$scans', Icons.qr_code, AppTheme.infoColor)),
              ],
            ),
            const Divider(height: 16),
            _amountRow('Total', total, cur, AppTheme.primaryColor, bold: true),
            _amountRow('Payé', paid, cur, AppTheme.successColor),
            _amountRow('À payer', pending, cur, AppTheme.warningColor),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.black54)),
      ],
    );
  }

  Widget _amountRow(String label, double value, String cur, Color color, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: color, fontWeight: bold ? FontWeight.bold : FontWeight.w500)),
          Text('${_money.format(value)} $cur',
              style: TextStyle(color: color, fontWeight: bold ? FontWeight.bold : FontWeight.w500)),
        ],
      ),
    );
  }

  List<Widget> _buildCostLines(List lines) {
    return [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Text(
          'COÛTS OPÉRATIONNELS (${lines.length})',
          style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.bold,
            color: Colors.black54, letterSpacing: 1.2,
          ),
        ),
      ),
      ...lines.map((l) => _CostLineCard(line: l as Map<String, dynamic>, money: _money)),
    ];
  }
}

// =============================================================================
// Card pour une ligne de coût
// =============================================================================

class _CostLineCard extends StatelessWidget {
  final Map<String, dynamic> line;
  final NumberFormat money;
  const _CostLineCard({required this.line, required this.money});

  Color _stateColor(String state) {
    switch (state) {
      case 'paid': return AppTheme.successColor;
      case 'pending': return AppTheme.warningColor;
      case 'confirmed': return AppTheme.infoColor;
      case 'estimated': return Colors.grey;
      default: return Colors.black54;
    }
  }

  IconData _stateIcon(String state) {
    switch (state) {
      case 'paid': return Icons.check_circle;
      case 'pending': return Icons.hourglass_top;
      case 'confirmed': return Icons.fact_check;
      case 'estimated': return Icons.edit_note;
      default: return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = (line['state'] ?? '').toString();
    final color = _stateColor(state);
    final scan = line['scan'] as Map<String, dynamic>?;
    final payment = line['payment'] as Map<String, dynamic>?;
    final cur = line['currency'] ?? 'XOF';
    final amount = (line['amount'] ?? 0).toDouble();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(_stateIcon(state), color: color, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line['name']?.toString().isNotEmpty == true
                            ? line['name']
                            : (line['cost_type_label'] ?? '—'),
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      Text(
                        '${line['reference'] ?? ''} • ${line['cost_type_label'] ?? ''}',
                        style: const TextStyle(fontSize: 11, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    line['state_label'] ?? state,
                    style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            // Montant + partenaire
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    (line['partner_name'] ?? '').toString().isNotEmpty
                        ? line['partner_name']
                        : 'Fournisseur non renseigné',
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${money.format(amount)} $cur',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
            // Bloc paiement
            if (payment != null && (payment['method'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 8),
              _paymentBlock(payment, color),
            ],
            // Bloc scan
            if (scan != null) ...[
              const SizedBox(height: 8),
              _scanBlock(scan),
            ],
          ],
        ),
      ),
    );
  }

  Widget _paymentBlock(Map<String, dynamic> p, Color color) {
    final parts = <String>[];
    if ((p['method_label'] ?? '').toString().isNotEmpty) parts.add(p['method_label']);
    if ((p['check_number'] ?? '').toString().isNotEmpty) parts.add('N° ${p['check_number']}');
    if ((p['payment_reference'] ?? '').toString().isNotEmpty) parts.add(p['payment_reference']);
    if ((p['payment_date'] ?? '').toString().isNotEmpty) {
      try {
        final d = DateTime.parse(p['payment_date']);
        parts.add(DateFormat('dd/MM/yyyy').format(d));
      } catch (_) {}
    }
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(Icons.payments, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              parts.isEmpty ? 'Paiement enregistré' : parts.join(' • '),
              style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
            ),
          ),
          if ((p['payment_request_ref'] ?? '').toString().isNotEmpty)
            Text(p['payment_request_ref'],
                style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _scanBlock(Map<String, dynamic> scan) {
    final qrUrl = (scan['qr_url'] ?? '').toString();
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.infoLight,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.infoColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.qr_code, size: 18, color: AppTheme.infoColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '📷 Scan DGI ${scan['reference'] ?? ''}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12, color: AppTheme.infoColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          if ((scan['supplier_name'] ?? '').toString().isNotEmpty)
            Text('Fournisseur: ${scan['supplier_name']}',
                style: const TextStyle(fontSize: 12)),
          if ((scan['invoice_number_dgi'] ?? '').toString().isNotEmpty)
            Text('Facture DGI: ${scan['invoice_number_dgi']}',
                style: const TextStyle(fontSize: 12)),
          if (qrUrl.isNotEmpty)
            Text(qrUrl,
                style: const TextStyle(fontSize: 10, color: Colors.black54),
                maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

// =============================================================================
// Scanner QR dédié aux OTs (accepte uniquement le prefixe ICP-OT:)
// =============================================================================

class _OtQrScannerPage extends StatefulWidget {
  const _OtQrScannerPage();

  @override
  State<_OtQrScannerPage> createState() => _OtQrScannerPageState();
}

class _OtQrScannerPageState extends State<_OtQrScannerPage> {
  final MobileScannerController _controller = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    if (capture.barcodes.isEmpty) return;
    final raw = capture.barcodes.first.rawValue ?? '';
    if (!raw.startsWith('ICP-OT:')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ce QR-code ne correspond pas à un OT.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    _handled = true;
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(raw);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Scanner un QR-OT'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Positioned(
            left: 0, right: 0, bottom: 32,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Pointez la caméra sur le QR-code « ICP-OT » du document ou de la fiche OT.',
                style: TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
