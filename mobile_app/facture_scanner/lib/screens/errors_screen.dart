/// Errors Screen - Gestion des erreurs avec retry
/// Écran pour visualiser et relancer les scans en erreur

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/services/api_service.dart';
import '../core/models/error_record.dart';
import '../core/theme/app_theme.dart';
import '../widgets/connectivity_banner.dart';

class ErrorsScreen extends StatefulWidget {
  const ErrorsScreen({super.key});

  @override
  State<ErrorsScreen> createState() => _ErrorsScreenState();
}

class _ErrorsScreenState extends State<ErrorsScreen> {
  final ApiService _api = ApiService();
  
  List<ErrorRecord> _errors = [];
  bool _isLoading = true;
  bool _isRetrying = false;
  String? _errorMessage;
  int _page = 1;
  int _totalPages = 1;
  bool _hasMore = false;
  Set<int> _selectedIds = {};
  bool _onlyRetryPossible = false;
  
  @override
  void initState() {
    super.initState();
    _loadErrors();
  }
  
  Future<void> _loadErrors({bool refresh = false}) async {
    if (refresh) {
      _page = 1;
      _selectedIds.clear();
    }
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      final response = await _api.getErrors(
        page: _page,
        limit: 20,
        retryPossible: _onlyRetryPossible ? true : null,
      );
      
      if (response.success && response.data != null) {
        final List<dynamic> recordsJson = response.data!['errors'] ?? [];
        final pagination = response.data!['pagination'] as Map<String, dynamic>?;
        
        setState(() {
          if (refresh || _page == 1) {
            _errors = recordsJson.map((json) => ErrorRecord.fromJson(json)).toList();
          } else {
            _errors.addAll(recordsJson.map((json) => ErrorRecord.fromJson(json)));
          }
          _totalPages = pagination?['total_pages'] ?? 1;
          _hasMore = _page < _totalPages;
        });
      } else {
        setState(() {
          _errorMessage = response.errorMessage ?? 'Erreur lors du chargement';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Erreur: ${e.toString()}';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  Future<void> _retryError(ErrorRecord error) async {
    setState(() => _isRetrying = true);
    
    try {
      final response = await _api.retryError(error.id);
      
      if (mounted) {
        if (response.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  Text(response.data?['message'] ?? 'Scan relancé avec succès'),
                ],
              ),
              backgroundColor: AppTheme.successColor,
              behavior: SnackBarBehavior.floating,
            ),
          );
          _loadErrors(refresh: true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error, color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  Expanded(child: Text(response.errorMessage ?? 'Échec du retry')),
                ],
              ),
              backgroundColor: AppTheme.errorColor,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: ${e.toString()}'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRetrying = false);
      }
    }
  }
  
  Future<void> _bulkRetry() async {
    if (_selectedIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sélectionnez au moins une erreur'),
          backgroundColor: AppTheme.warningColor,
        ),
      );
      return;
    }
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Relancer les erreurs'),
        content: Text('Relancer ${_selectedIds.length} scan(s) en erreur ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
            ),
            child: const Text('Relancer'),
          ),
        ],
      ),
    );
    
    if (confirm != true) return;
    
    setState(() => _isRetrying = true);
    
    try {
      final response = await _api.bulkRetryErrors(
        recordIds: _selectedIds.toList(),
      );
      
      if (mounted) {
        if (response.success && response.data != null) {
          final result = BulkRetryResult.fromJson(response.data!);
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${result.successful}/${result.processed} scan(s) traité(s) avec succès',
              ),
              backgroundColor: result.hasFailures 
                  ? AppTheme.warningColor 
                  : AppTheme.successColor,
              behavior: SnackBarBehavior.floating,
            ),
          );
          
          _selectedIds.clear();
          _loadErrors(refresh: true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response.errorMessage ?? 'Échec du retry en masse'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: ${e.toString()}'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isRetrying = false);
      }
    }
  }
  
  void _toggleSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }
  
  void _selectAll() {
    setState(() {
      if (_selectedIds.length == _errors.where((e) => e.retryPossible).length) {
        _selectedIds.clear();
      } else {
        _selectedIds = _errors.where((e) => e.retryPossible).map((e) => e.id).toSet();
      }
    });
  }
  
  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);
    
    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkSurface : AppTheme.surfaceLight,
      appBar: AppBar(
        title: const Text('Gestion des erreurs'),
        backgroundColor: isDark ? AppTheme.darkSurfaceElevated : AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_errors.isNotEmpty) ...[
            IconButton(
              icon: Icon(
                _selectedIds.length == _errors.where((e) => e.retryPossible).length
                    ? Icons.deselect
                    : Icons.select_all,
              ),
              tooltip: 'Tout sélectionner',
              onPressed: _selectAll,
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualiser',
              onPressed: () => _loadErrors(refresh: true),
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          const ConnectivityBanner(),
          
          // Filtre
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: isDark ? AppTheme.darkSurfaceElevated : AppTheme.surfaceLight,
            child: Row(
              children: [
                FilterChip(
                  label: const Text('Retry possible'),
                  selected: _onlyRetryPossible,
                  onSelected: (selected) {
                    setState(() => _onlyRetryPossible = selected);
                    _loadErrors(refresh: true);
                  },
                  selectedColor: AppTheme.primaryLight.withOpacity(isDark ? 0.4 : 0.3),
                ),
                const SizedBox(width: 8),
                if (_selectedIds.isNotEmpty)
                  Chip(
                    label: Text('${_selectedIds.length} sélectionné(s)'),
                    deleteIcon: const Icon(Icons.clear, size: 18),
                    onDeleted: () => setState(() => _selectedIds.clear()),
                  ),
              ],
            ),
          ),
          
          // Liste des erreurs
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
      floatingActionButton: _selectedIds.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _isRetrying ? null : _bulkRetry,
              backgroundColor: AppTheme.primaryColor,
              icon: _isRetrying
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : const Icon(Icons.replay),
              label: Text('Relancer (${_selectedIds.length})'),
            )
          : null,
    );
  }
  
  Widget _buildContent() {
    if (_isLoading && _errors.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }
    
    if (_errorMessage != null && _errors.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppTheme.textLight),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: AppTheme.bodyLarge),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _loadErrors(refresh: true),
              icon: const Icon(Icons.refresh),
              label: const Text('Réessayer'),
            ),
          ],
        ),
      );
    }
    
    if (_errors.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_outline, size: 64, color: AppTheme.successColor),
            const SizedBox(height: 16),
            const Text('Aucune erreur', style: AppTheme.headingSmall),
            const SizedBox(height: 8),
            Text(
              _onlyRetryPossible 
                  ? 'Aucune erreur avec retry possible'
                  : 'Tous les scans ont réussi',
              style: AppTheme.bodyLarge.copyWith(color: AppTheme.textLight),
            ),
          ],
        ),
      );
    }
    
    return RefreshIndicator(
      onRefresh: () => _loadErrors(refresh: true),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _errors.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _errors.length) {
            // Bouton charger plus
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: ElevatedButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          _page++;
                          _loadErrors();
                        },
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Charger plus'),
                ),
              ),
            );
          }
          
          return _buildErrorCard(_errors[index]);
        },
      ),
    );
  }
  
  Widget _buildErrorCard(ErrorRecord error) {
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final isSelected = _selectedIds.contains(error.id);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isSelected
            ? const BorderSide(color: AppTheme.primaryColor, width: 2)
            : BorderSide.none,
      ),
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.1),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _showErrorDetails(error),
        onLongPress: error.retryPossible ? () => _toggleSelection(error.id) : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // En-tête avec référence et catégorie
              Row(
                children: [
                  if (error.retryPossible)
                    GestureDetector(
                      onTap: () => _toggleSelection(error.id),
                      child: Checkbox(
                        value: isSelected,
                        onChanged: (_) => _toggleSelection(error.id),
                        activeColor: AppTheme.primaryColor,
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          error.reference,
                          style: AppTheme.headingSmall.copyWith(fontSize: 16),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            _buildCategoryChip(error.errorCategory),
                            if (error.duplicateCount > 0) ...[
                              const SizedBox(width: 8),
                              _buildCountChip(error.duplicateCount, Icons.replay, Colors.blue),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (error.retryPossible)
                    IconButton(
                      icon: _isRetrying
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.replay, color: AppTheme.primaryColor),
                      tooltip: 'Relancer',
                      onPressed: _isRetrying ? null : () => _retryError(error),
                    ),
                ],
              ),
              
              const Divider(height: 24),
              
              // Informations de la facture
              _buildInfoRow(Icons.business, 'Fournisseur', error.supplierName),
              _buildInfoRow(Icons.receipt, 'N° Facture', error.invoiceNumberDgi),
              _buildInfoRow(Icons.attach_money, 'Montant', error.formattedAmount),
              if (error.scanDate != null)
                _buildInfoRow(Icons.access_time, 'Date scan', dateFormat.format(error.scanDate!)),
              _buildInfoRow(Icons.person, 'Par', error.scannedBy),
              
              const SizedBox(height: 16),
              
              // Message d'erreur en vedette
              _buildErrorMessageCard(error.errorMessage ?? 'Erreur inconnue'),
              
              // Bouton voir détails
              const SizedBox(height: 12),
              Center(
                child: TextButton.icon(
                  onPressed: () => _showErrorDetails(error),
                  icon: const Icon(Icons.info_outline, size: 18),
                  label: const Text('Voir les détails'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.primaryColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildCountChip(int count, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildErrorMessageCard(String errorMessage) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.errorLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.errorColor.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.errorColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.report_problem_rounded,
              color: AppTheme.errorColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Message d\'erreur',
                  style: TextStyle(
                    color: AppTheme.errorColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  errorMessage,
                  style: AppTheme.bodyMedium.copyWith(
                    color: AppTheme.textDark,
                    height: 1.4,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  void _showErrorDetails(ErrorRecord error) {
    final dateFormat = DateFormat('dd/MM/yyyy à HH:mm');
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // Poignée
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // En-tête
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppTheme.errorColor, AppTheme.errorColor.withOpacity(0.8)],
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.error_outline, color: Colors.white, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            error.reference,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            error.errorCategoryLabel,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (error.retryPossible)
                      IconButton(
                        icon: const Icon(Icons.replay, color: Colors.white),
                        onPressed: () {
                          Navigator.pop(context);
                          _retryError(error);
                        },
                      ),
                  ],
                ),
              ),
              
              // Contenu défilable
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Message d'erreur complet
                      _buildDetailSection(
                        'Message d\'erreur',
                        Icons.report_problem_rounded,
                        AppTheme.errorColor,
                        error.errorMessage ?? 'Erreur inconnue',
                        isError: true,
                      ),
                      
                      const SizedBox(height: 20),
                      
                      // Informations fournisseur
                      _buildDetailSection(
                        'Informations fournisseur',
                        Icons.business_rounded,
                        AppTheme.primaryColor,
                        null,
                        children: [
                          _buildDetailItem('Nom', error.supplierName),
                          _buildDetailItem('Code DGI', error.supplierCodeDgi),
                          _buildDetailItem('N° Facture', error.invoiceNumberDgi),
                          _buildDetailItem('Montant', error.formattedAmount),
                        ],
                      ),
                      
                      const SizedBox(height: 20),
                      
                      // Informations du scan
                      _buildDetailSection(
                        'Informations du scan',
                        Icons.qr_code_scanner_rounded,
                        AppTheme.accentColor,
                        null,
                        children: [
                          _buildDetailItem('UUID QR', error.qrUuid, selectable: true),
                          if (error.scanDate != null)
                            _buildDetailItem('Date du scan', dateFormat.format(error.scanDate!)),
                          _buildDetailItem('Scanné par', error.scannedBy),
                          if (error.duplicateCount > 0)
                            _buildDetailItem('Tentatives', '${error.duplicateCount}'),
                        ],
                      ),
                      
                      const SizedBox(height: 30),
                      
                      // Boutons d'action
                      if (error.retryPossible)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _retryError(error);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryColor,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            icon: const Icon(Icons.replay),
                            label: const Text(
                              'Relancer le scan',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildDetailSection(
    String title,
    IconData icon,
    Color color,
    String? content, {
    bool isError = false,
    List<Widget>? children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isError ? AppTheme.errorLight : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isError ? AppTheme.errorColor.withOpacity(0.3) : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: TextStyle(
                  color: isError ? AppTheme.errorColor : AppTheme.textDark,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (content != null)
            Text(
              content,
              style: TextStyle(
                color: isError ? AppTheme.textDark : AppTheme.textMedium,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          if (children != null) ...children,
        ],
      ),
    );
  }
  
  Widget _buildDetailItem(String label, String value, {bool selectable = false}) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                color: AppTheme.textMuted,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: selectable
                ? SelectableText(
                    value.isNotEmpty ? value : '-',
                    style: const TextStyle(
                      color: AppTheme.textDark,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  )
                : Text(
                    value.isNotEmpty ? value : '-',
                    style: const TextStyle(
                      color: AppTheme.textDark,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildCategoryChip(ErrorCategory category) {
    Color chipColor;
    switch (category) {
      case ErrorCategory.dgiService:
        chipColor = Colors.orange;
        break;
      case ErrorCategory.network:
        chipColor = Colors.blue;
        break;
      case ErrorCategory.parsing:
        chipColor = Colors.purple;
        break;
      case ErrorCategory.invoiceCreation:
        chipColor = Colors.red;
        break;
      case ErrorCategory.browser:
        chipColor = Colors.teal;
        break;
      case ErrorCategory.other:
        chipColor = Colors.grey;
        break;
    }
    
    return Chip(
      avatar: Icon(
        _getCategoryIcon(category),
        size: 16,
        color: chipColor,
      ),
      label: Text(
        category.label,
        style: TextStyle(color: chipColor, fontSize: 12),
      ),
      backgroundColor: chipColor.withOpacity(0.1),
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
  }
  
  IconData _getCategoryIcon(ErrorCategory category) {
    switch (category) {
      case ErrorCategory.dgiService:
        return Icons.cloud_off;
      case ErrorCategory.network:
        return Icons.wifi_off;
      case ErrorCategory.parsing:
        return Icons.code_off;
      case ErrorCategory.invoiceCreation:
        return Icons.receipt_long;
      case ErrorCategory.browser:
        return Icons.web_asset_off;
      case ErrorCategory.other:
        return Icons.help_outline;
    }
  }
  
  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.textLight),
          const SizedBox(width: 8),
          Text('$label: ', style: AppTheme.bodyMedium.copyWith(color: AppTheme.textLight)),
          Expanded(
            child: Text(
              value.isNotEmpty ? value : '-',
              style: AppTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
