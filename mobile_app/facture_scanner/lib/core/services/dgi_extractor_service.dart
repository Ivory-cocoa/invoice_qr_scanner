/// DGI WebView Extraction Service
/// Charge la page DGI dans un WebView headless, attend le rendu JS,
/// puis extrait le texte pour le parser localement.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'dgi_parser_service.dart';

class DgiExtractorService {
  final DgiParserService _parser = DgiParserService();

  // Singleton
  static final DgiExtractorService _instance = DgiExtractorService._internal();
  factory DgiExtractorService() => _instance;
  DgiExtractorService._internal();

  /// Timeout pour le chargement de la page (en secondes)
  static const int pageLoadTimeout = 30;

  /// Intervalle entre les tentatives d'extraction (en secondes)
  static const int pollInterval = 2;

  /// Nombre maximum de tentatives d'extraction après chargement
  static const int maxExtractionAttempts = 10;

  /// Extraire les données DGI depuis l'URL en utilisant un WebView invisible.
  /// 
  /// Retourne [DgiParsedData] si l'extraction réussit, null sinon.
  /// [onProgress] est appelé avec un message de progression.
  Future<DgiExtractionResult> extractFromUrl(
    String url, {
    void Function(String message)? onProgress,
  }) async {
    onProgress?.call('Chargement de la page DGI...');

    // Normaliser l'URL en français pour que le parser reconnaisse les labels
    final normalizedUrl = _normalizeDgiUrl(url);

    final completer = Completer<DgiExtractionResult>();
    DgiParsedData? parsedData;
    int extractionAttempts = 0;
    Timer? pollingTimer;

    final controller = WebViewController();

    try {
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setUserAgent(
        'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
      );

      // Callback quand la page est chargée
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String finishedUrl) async {
            onProgress?.call('Page chargée, extraction des données...');

            // Commencer le polling pour attendre le rendu JS
            pollingTimer = Timer.periodic(
              const Duration(seconds: pollInterval),
              (timer) async {
                extractionAttempts++;

                if (extractionAttempts > maxExtractionAttempts) {
                  timer.cancel();
                  if (!completer.isCompleted) {
                    completer.complete(DgiExtractionResult(
                      success: false,
                      error: 'Timeout: données non trouvées après $maxExtractionAttempts tentatives',
                    ));
                  }
                  return;
                }

                onProgress?.call(
                  'Attente du rendu JS... (tentative $extractionAttempts/$maxExtractionAttempts)',
                );

                try {
                  // Extraire le texte visible de la page
                  final textResult = await controller.runJavaScriptReturningResult(
                    'document.body ? document.body.innerText : ""',
                  );

                  // Le résultat est une chaîne JSON-encodée
                  String textContent = '';
                  if (textResult is String) {
                    // Enlever les guillemets encadrants si présents
                    textContent = textResult;
                    if (textContent.startsWith('"') && textContent.endsWith('"')) {
                      textContent = jsonDecode(textContent) as String;
                    }
                  }

                  if (textContent.isEmpty) return;

                  // Tenter le parsing
                  final data = _parser.extractFromText(textContent);
                  if (data != null && data.hasSupplier) {
                    parsedData = data;
                    timer.cancel();
                    onProgress?.call('Données extraites avec succès !');

                    if (!completer.isCompleted) {
                      completer.complete(DgiExtractionResult(
                        success: true,
                        data: parsedData,
                      ));
                    }
                  }
                } catch (e) {
                  debugPrint('Erreur extraction tentative $extractionAttempts: $e');
                }
              },
            );
          },
          onWebResourceError: (error) {
            pollingTimer?.cancel();
            if (!completer.isCompleted) {
              completer.complete(DgiExtractionResult(
                success: false,
                error: 'Erreur de chargement: ${error.description}',
              ));
            }
          },
        ),
      );

      // Charger l'URL normalisée en français
      await controller.loadRequest(Uri.parse(normalizedUrl));

      // Timer de sécurité global
      final timeoutTimer = Timer(
        const Duration(seconds: pageLoadTimeout + maxExtractionAttempts * pollInterval + 5),
        () {
          pollingTimer?.cancel();
          if (!completer.isCompleted) {
            completer.complete(DgiExtractionResult(
              success: false,
              error: 'Timeout global de l\'extraction',
            ));
          }
        },
      );

      final result = await completer.future;
      timeoutTimer.cancel();
      pollingTimer?.cancel();
      return result;
    } catch (e) {
      pollingTimer?.cancel();
      if (!completer.isCompleted) {
        return DgiExtractionResult(
          success: false,
          error: 'Erreur: ${e.toString()}',
        );
      }
      return await completer.future;
    }
  }

  /// Normalise l'URL DGI pour forcer la version française.
  /// Ex: /en/verification/... → /fr/verification/...
  String _normalizeDgiUrl(String url) {
    return url.replaceFirst(
      RegExp(r'/(en|ar|es|de|pt|zh)/verification/'),
      '/fr/verification/',
    );
  }
}

/// Résultat de l'extraction DGI
class DgiExtractionResult {
  final bool success;
  final DgiParsedData? data;
  final String? error;

  const DgiExtractionResult({
    required this.success,
    this.data,
    this.error,
  });
}
