/// Scheduled Sync Service
/// Gère la synchronisation programmée des scans à une heure configurable
/// Utilise workmanager pour les tâches en arrière-plan

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import 'api_service.dart';
import 'database_service.dart';
import 'sync_service.dart';

/// Nom unique de la tâche workmanager
const String scheduledSyncTaskName = 'com.icp.facturescanner.scheduledSync';
const String periodicSyncTaskName = 'com.icp.facturescanner.periodicSync';

/// Callback de haut niveau pour workmanager (doit être top-level)
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint('[ScheduledSync] Tâche exécutée: $task');

    try {
      // Initialiser les services nécessaires
      await DatabaseService().init();
      await ApiService().init();

      // Vérifier que l'utilisateur est connecté
      if (!ApiService().isAuthenticated) {
        debugPrint('[ScheduledSync] Utilisateur non connecté, sync ignorée');
        return true;
      }

      final db = DatabaseService();
      final settings = await db.getSyncSettings();
      final autoSyncEnabled = (settings['auto_sync_enabled'] as int?) == 1;

      if (!autoSyncEnabled) {
        debugPrint('[ScheduledSync] Sync automatique désactivée');
        return true;
      }

      // Vérifier l'heure configurée (pour les tâches périodiques)
      if (task == periodicSyncTaskName) {
        final syncHour = settings['sync_hour'] as int? ?? 20;
        final syncMinute = settings['sync_minute'] as int? ?? 0;
        final now = DateTime.now();

        // Tolérance de 30 minutes autour de l'heure configurée
        final scheduledTime = DateTime(now.year, now.month, now.day, syncHour, syncMinute);
        final diff = now.difference(scheduledTime).inMinutes.abs();
        if (diff > 30) {
          debugPrint('[ScheduledSync] Hors fenêtre de sync (diff: ${diff}min)');
          return true;
        }
      }

      // Exécuter la synchronisation
      final syncService = SyncService();
      final result = await syncService.syncPendingScans();

      debugPrint(
        '[ScheduledSync] Résultat: ${result.success ? "OK" : "ERREUR"} - '
        '${result.syncedCount} synchronisés, ${result.duplicateCount} doublons',
      );

      // Enregistrer le timestamp de la dernière sync
      await db.recordScheduledSync();

      return true;
    } catch (e) {
      debugPrint('[ScheduledSync] Erreur: $e');
      return false;
    }
  });
}

class ScheduledSyncService {
  final DatabaseService _db = DatabaseService();

  // Singleton
  static final ScheduledSyncService _instance = ScheduledSyncService._internal();
  factory ScheduledSyncService() => _instance;
  ScheduledSyncService._internal();

  /// Initialiser WorkManager (appeler une seule fois au démarrage)
  Future<void> initialize() async {
    await Workmanager().initialize(
      callbackDispatcher,
      isInDebugMode: kDebugMode,
    );
    // Programmer la sync si activée
    await rescheduleSync();
  }

  /// Programmer ou reprogrammer la tâche de synchronisation
  Future<void> rescheduleSync() async {
    final settings = await _db.getSyncSettings();
    final autoSyncEnabled = (settings['auto_sync_enabled'] as int?) == 1;

    // Annuler les tâches existantes
    await Workmanager().cancelByUniqueName(scheduledSyncTaskName);
    await Workmanager().cancelByUniqueName(periodicSyncTaskName);

    if (!autoSyncEnabled) {
      debugPrint('[ScheduledSync] Sync automatique désactivée, tâches annulées');
      return;
    }

    final syncHour = settings['sync_hour'] as int? ?? 20;
    final syncMinute = settings['sync_minute'] as int? ?? 0;

    // Calculer le délai initial jusqu'à la prochaine occurrence
    final now = DateTime.now();
    var nextSync = DateTime(now.year, now.month, now.day, syncHour, syncMinute);
    if (nextSync.isBefore(now)) {
      nextSync = nextSync.add(const Duration(days: 1));
    }
    final initialDelay = nextSync.difference(now);

    debugPrint(
      '[ScheduledSync] Prochaine sync programmée à '
      '${syncHour.toString().padLeft(2, '0')}:${syncMinute.toString().padLeft(2, '0')} '
      '(dans ${initialDelay.inMinutes} minutes)',
    );

    // Programmer une tâche unique pour la prochaine sync
    await Workmanager().registerOneOffTask(
      scheduledSyncTaskName,
      scheduledSyncTaskName,
      initialDelay: initialDelay,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );

    // Programmer une tâche périodique (toutes les 24h, vérifie l'heure elle-même)
    await Workmanager().registerPeriodicTask(
      periodicSyncTaskName,
      periodicSyncTaskName,
      frequency: const Duration(hours: 12),
      initialDelay: initialDelay,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
    );
  }

  /// Mettre à jour les paramètres de synchronisation et reprogrammer
  Future<void> updateSchedule({
    required int hour,
    required int minute,
    required bool enabled,
  }) async {
    await _db.updateSyncSettings(
      syncHour: hour,
      syncMinute: minute,
      autoSyncEnabled: enabled,
    );
    await rescheduleSync();
  }

  /// Obtenir les paramètres actuels
  Future<Map<String, dynamic>> getSettings() async {
    return await _db.getSyncSettings();
  }

  /// Forcer une synchronisation immédiate
  Future<SyncResult> syncNow() async {
    final syncService = SyncService();
    final result = await syncService.syncPendingScans();
    if (result.success) {
      await _db.recordScheduledSync();
    }
    return result;
  }
}
