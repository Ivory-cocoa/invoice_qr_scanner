/// Settings Screen - Configuration de la synchronisation programmée
/// Permet de configurer l'heure de synchronisation automatique

import 'package:flutter/material.dart';

import '../core/services/database_service.dart';
import '../core/services/scheduled_sync_service.dart';
import '../core/theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final DatabaseService _db = DatabaseService();
  final ScheduledSyncService _scheduledSync = ScheduledSyncService();

  int _syncHour = 20;
  int _syncMinute = 0;
  bool _autoSyncEnabled = true;
  String? _lastSync;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await _db.getSyncSettings();
    setState(() {
      _syncHour = (settings['sync_hour'] as int?) ?? 20;
      _syncMinute = (settings['sync_minute'] as int?) ?? 0;
      _autoSyncEnabled = (settings['auto_sync_enabled'] as int?) == 1;
      _lastSync = settings['last_scheduled_sync'] as String?;
      _isLoading = false;
    });
  }

  Future<void> _selectTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _syncHour, minute: _syncMinute),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _syncHour = picked.hour;
        _syncMinute = picked.minute;
      });
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);

    try {
      await _scheduledSync.updateSchedule(
        hour: _syncHour,
        minute: _syncMinute,
        enabled: _autoSyncEnabled,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white, size: 20),
                SizedBox(width: 12),
                Text('Paramètres de synchronisation sauvegardés'),
              ],
            ),
            backgroundColor: AppTheme.successColor,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: ${e.toString()}'),
            backgroundColor: AppTheme.errorColor,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }

    if (mounted) setState(() => _isSaving = false);
  }

  Future<void> _syncNow() async {
    setState(() => _isSaving = true);

    final result = await _scheduledSync.syncNow();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                result.success ? Icons.cloud_done : Icons.cloud_off,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(result.message)),
            ],
          ),
          backgroundColor:
              result.success ? AppTheme.successColor : AppTheme.errorColor,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
      // Reload settings (to update last sync time)
      await _loadSettings();
    }

    if (mounted) setState(() => _isSaving = false);
  }

  String _formatTime(int hour, int minute) {
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  String _formatLastSync(String? isoDate) {
    if (isoDate == null) return 'Jamais';
    try {
      final dt = DateTime.parse(isoDate);
      final now = DateTime.now();
      final diff = now.difference(dt);

      if (diff.inMinutes < 1) return 'À l\'instant';
      if (diff.inHours < 1) return 'Il y a ${diff.inMinutes} min';
      if (diff.inDays < 1) return 'Il y a ${diff.inHours}h';
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} à ${_formatTime(dt.hour, dt.minute)}';
    } catch (_) {
      return 'Inconnu';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paramètres'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Section: Synchronisation programmée
                _buildSectionHeader(
                  icon: Icons.schedule,
                  title: 'Synchronisation programmée',
                ),
                const SizedBox(height: 12),
                _buildCard(
                  children: [
                    SwitchListTile.adaptive(
                      title: const Text(
                        'Synchronisation automatique',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        _autoSyncEnabled
                            ? 'Les scans seront envoyés au serveur à l\'heure programmée'
                            : 'Synchronisation manuelle uniquement',
                      ),
                      value: _autoSyncEnabled,
                      activeColor: AppTheme.primaryColor,
                      onChanged: (value) {
                        setState(() => _autoSyncEnabled = value);
                      },
                    ),
                    if (_autoSyncEnabled) ...[
                      const Divider(),
                      ListTile(
                        leading: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.access_time,
                            color: AppTheme.primaryColor,
                          ),
                        ),
                        title: const Text('Heure de synchronisation'),
                        subtitle: const Text(
                          'Les scans en attente seront envoyés à cette heure',
                        ),
                        trailing: InkWell(
                          onTap: _selectTime,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _formatTime(_syncHour, _syncMinute),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    const Divider(),
                    ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.history,
                          color: Colors.orange,
                        ),
                      ),
                      title: const Text('Dernière synchronisation'),
                      trailing: Text(
                        _formatLastSync(_lastSync),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // Section: Extraction locale
                _buildSectionHeader(
                  icon: Icons.phone_android,
                  title: 'Extraction locale',
                ),
                const SizedBox(height: 12),
                _buildCard(
                  children: [
                    const ListTile(
                      leading: Icon(Icons.info_outline, color: Colors.blue),
                      title: Text(
                        'Traitement côté client',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'Quand vous scannez en mode hors-ligne, l\'application '
                        'charge la page DGI dans un navigateur intégré, extrait '
                        'les données (fournisseur, montant, numéro de facture) '
                        'et les stocke localement. Le serveur n\'a plus besoin de '
                        'refaire l\'extraction lors de la synchronisation.',
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // Boutons d'action
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isSaving ? null : _syncNow,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.sync),
                        label: const Text('Synchroniser maintenant'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isSaving ? null : _saveSettings,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save),
                        label: const Text('Sauvegarder'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String title,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppTheme.primaryColor),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildCard({required List<Widget> children}) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: Colors.grey.withOpacity(0.2),
        ),
      ),
      child: Column(children: children),
    );
  }
}
