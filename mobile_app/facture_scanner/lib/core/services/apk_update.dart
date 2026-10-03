// Mise à jour de l'application depuis Odoo (catalogue « Applications
// mobiles ») — FICHIER COMMUN aux applications ICP : ICP Export, ICP Cacao,
// Employee Hub, Facture Scanner. Le garder identique dans les quatre.
//
// Odoo indique la dernière version publiée (numéro, version_code, empreinte
// SHA-256, lien de téléchargement signé). Si elle est plus récente que
// l'application, un bandeau la propose : un appui télécharge l'APK dans
// l'application (progression), vérifie son empreinte, puis ouvre
// l'installeur Android. En cas d'échec, le navigateur prend le relais.
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Version publiée dans Odoo.
class ApkUpdate {
  const ApkUpdate({
    required this.version,
    required this.versionCode,
    required this.url,
    this.sha256 = '',
    this.notes = '',
    this.fileSize = 0,
  });

  final String version;
  final int versionCode;
  final String url;
  final String sha256;
  final String notes;
  final int fileSize;

  /// Lit la réponse d'Odoo ({version, version_code, url | download_url,
  /// sha256, release_notes, file_size}) ; null si incomplète.
  static ApkUpdate? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    final code = raw['version_code'];
    final url = '${raw['url'] ?? raw['download_url'] ?? ''}';
    final versionCode = code is num ? code.toInt() : int.tryParse('${code ?? ''}');
    if (versionCode == null || url.isEmpty) return null;
    return ApkUpdate(
      version: '${raw['version'] ?? ''}',
      versionCode: versionCode,
      url: url,
      sha256: '${raw['sha256'] ?? ''}'.toLowerCase(),
      notes: '${raw['release_notes'] ?? ''}',
      fileSize: (raw['file_size'] as num?)?.toInt() ?? 0,
    );
  }

  bool isNewerThan(int currentCode) => versionCode > currentCode;
}

enum UpdatePhase { idle, downloading, verifying, installing, failed }

/// Téléchargement et installation de l'APK.
class ApkUpdater extends ChangeNotifier {
  ApkUpdater({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  UpdatePhase phase = UpdatePhase.idle;

  /// Avancement du téléchargement (0..1), null si la taille est inconnue.
  double? progress;
  String? error;

  bool get busy => phase == UpdatePhase.downloading || phase == UpdatePhase.verifying;

  void _set(UpdatePhase value, {double? progress, String? error}) {
    phase = value;
    this.progress = progress;
    this.error = error;
    notifyListeners();
  }

  /// Ouvre le lien dans le navigateur (repli, et version web).
  Future<bool> openInBrowser(ApkUpdate update) async {
    final uri = Uri.tryParse(update.url);
    return uri != null && await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> start(ApkUpdate update) async {
    if (busy) return;
    if (kIsWeb || !Platform.isAndroid) {
      await openInBrowser(update);
      return;
    }
    File? file;
    try {
      _set(UpdatePhase.downloading, progress: 0);
      final response = await _client.send(http.Request('GET', Uri.parse(update.url)));
      if (response.statusCode != 200) {
        throw _UpdateError(response.statusCode == 403 || response.statusCode == 404
            ? 'Lien de téléchargement expiré : rouvrez l\'application puis réessayez.'
            : 'Téléchargement refusé par le serveur (${response.statusCode}).');
      }
      final total = response.contentLength ?? update.fileSize;
      final dir = await getTemporaryDirectory();
      file = File('${dir.path}/mise-a-jour-${update.versionCode}.apk');
      final sink = file.openWrite();
      var received = 0;
      var lastNotified = 0.0;
      await for (final chunk in response.stream.timeout(const Duration(seconds: 60))) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) {
          final value = received / total;
          if (value - lastNotified >= 0.01 || value >= 1) {
            lastNotified = value;
            _set(UpdatePhase.downloading, progress: value.clamp(0.0, 1.0));
          }
        }
      }
      await sink.close();

      if (update.sha256.isNotEmpty) {
        _set(UpdatePhase.verifying);
        final digest = await sha256.bind(file.openRead()).first;
        if (digest.toString() != update.sha256) {
          throw _UpdateError('Fichier altéré pendant le téléchargement : réessayez.');
        }
      }

      _set(UpdatePhase.installing);
      final result = await OpenFilex.open(file.path, type: 'application/vnd.android.package-archive');
      if (result.type == ResultType.done) {
        _set(UpdatePhase.idle);
      } else if (result.type == ResultType.permissionDenied) {
        throw _UpdateError('Autorisez l\'installation d\'applications pour cette '
            'application (Paramètres Android), puis réessayez.');
      } else {
        throw _UpdateError('Impossible d\'ouvrir l\'installeur : ${result.message}');
      }
    } on _UpdateError catch (e) {
      await _discard(file);
      _set(UpdatePhase.failed, error: e.message);
    } on TimeoutException {
      await _discard(file);
      _set(UpdatePhase.failed, error: 'Le téléchargement s\'est interrompu (réseau trop lent).');
    } on SocketException {
      await _discard(file);
      _set(UpdatePhase.failed, error: 'Pas de connexion réseau.');
    } catch (e) {
      await _discard(file);
      _set(UpdatePhase.failed, error: 'Échec de la mise à jour : $e');
    }
  }

  Future<void> _discard(File? file) async {
    try {
      if (file != null && await file.exists()) await file.delete();
    } catch (_) {}
  }
}

class _UpdateError implements Exception {
  _UpdateError(this.message);
  final String message;
}

/// Bandeau « Nouvelle version disponible » : couleurs du thème de
/// l'application, s'affiche seulement si [update] est plus récente que
/// [currentVersionCode].
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({
    super.key,
    required this.update,
    required this.currentVersionCode,
    required this.updater,
    this.appName = 'l\'application',
  });

  final ApkUpdate? update;
  final int currentVersionCode;
  final ApkUpdater updater;
  final String appName;

  @override
  Widget build(BuildContext context) {
    final info = update;
    if (info == null || !info.isNewerThan(currentVersionCode)) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: updater,
      builder: (context, _) {
        final phase = updater.phase;
        final failed = phase == UpdatePhase.failed;
        // Taille à la française, insécable : « 40,9 Mo » ne se coupe pas.
        final size = info.fileSize > 0
            ? ' · ${(info.fileSize / 1048576).toStringAsFixed(1).replaceAll('.', ',')}\u00a0Mo'
            : '';
        final subtitle = switch (phase) {
          UpdatePhase.downloading => updater.progress == null
              ? 'Téléchargement…'
              : 'Téléchargement ${(100 * updater.progress!).round()} %',
          UpdatePhase.verifying => 'Vérification du fichier…',
          UpdatePhase.installing => 'Ouverture de l\'installeur Android…',
          UpdatePhase.failed => updater.error ?? 'Échec de la mise à jour.',
          UpdatePhase.idle => info.notes.isNotEmpty ? info.notes : 'Installez-la par-dessus $appName$size.',
        };
        return Semantics(
          container: true,
          label: 'Nouvelle version ${info.version} disponible',
          child: Material(
            color: failed ? scheme.errorContainer : scheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(failed ? Icons.error_outline : Icons.system_update,
                          color: failed ? scheme.onErrorContainer : scheme.onPrimaryContainer),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Nouvelle version ${info.version} disponible',
                                style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: failed ? scheme.onErrorContainer : scheme.onPrimaryContainer)),
                            const SizedBox(height: 2),
                            Text(subtitle,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 13,
                                    color: (failed ? scheme.onErrorContainer : scheme.onPrimaryContainer)
                                        .withValues(alpha: 0.85))),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // Actions sous le texte : rien ne déborde sur un petit écran
                  // avec une grande police.
                  if (!updater.busy && phase != UpdatePhase.installing) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        if (failed)
                          TextButton(
                            onPressed: () => updater.openInBrowser(info),
                            child: const Text('Navigateur'),
                          ),
                        FilledButton.icon(
                          onPressed: () => updater.start(info),
                          icon: Icon(failed ? Icons.refresh : Icons.download),
                          label: Text(failed ? 'Réessayer' : 'Mettre à jour'),
                        ),
                      ],
                    ),
                  ],
                  if (updater.busy) ...[
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(99),
                      child: LinearProgressIndicator(value: updater.progress, minHeight: 6),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
