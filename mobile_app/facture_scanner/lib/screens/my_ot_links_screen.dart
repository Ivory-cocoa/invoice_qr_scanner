/// My OT Links Screen — Gestionnaire OT
/// Liste des scans liés par l'utilisateur courant à des OTs.

import 'package:flutter/material.dart';

import '../core/services/api_service.dart';
import '../core/theme/app_theme.dart';

class MyOtLinksScreen extends StatefulWidget {
  const MyOtLinksScreen({super.key});

  @override
  State<MyOtLinksScreen> createState() => _MyOtLinksScreenState();
}

class _MyOtLinksScreenState extends State<MyOtLinksScreen> {
  final _api = ApiService();
  List<Map<String, dynamic>> _links = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final resp = await _api.getMyOtLinks();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (resp.success && resp.data != null) {
        _links = List<Map<String, dynamic>>.from(resp.data!['links'] ?? []);
      } else {
        _error = resp.errorMessage ?? 'Erreur de chargement';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes liaisons OT'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(children: [
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!),
                    ),
                  ])
                : _links.isEmpty
                    ? ListView(children: const [
                        SizedBox(height: 80),
                        Center(child: Icon(Icons.link_off, size: 64, color: Colors.grey)),
                        SizedBox(height: 12),
                        Center(child: Text('Aucune liaison effectuée pour le moment.')),
                      ])
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _links.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) {
                          final l = _links[i];
                          return Card(
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    AppTheme.getPrimary(context).withOpacity(0.15),
                                child: Icon(
                                  Icons.receipt_long_rounded,
                                  color: AppTheme.getPrimary(context),
                                ),
                              ),
                              title: Text(
                                l['transit_order_ref'] ?? '',
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(l['name'] ?? ''),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${l['cost_type_label'] ?? ''} • '
                                    '${l['amount']?.toString() ?? '0'} '
                                    '${l['currency'] ?? 'XOF'}',
                                    style: TextStyle(
                                      color: AppTheme.getTextMuted(context),
                                      fontSize: 12,
                                    ),
                                  ),
                                  if ((l['invoice_ref'] ?? '').toString().isNotEmpty)
                                    Text(
                                      'Facture : ${l['invoice_ref']}',
                                      style: TextStyle(
                                        color: AppTheme.getTextMuted(context),
                                        fontSize: 12,
                                      ),
                                    ),
                                ],
                              ),
                              trailing: Chip(
                                label: Text(
                                  l['state_label'] ?? '',
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}
