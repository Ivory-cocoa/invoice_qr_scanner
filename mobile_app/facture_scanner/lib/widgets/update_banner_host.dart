import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/config/environment.dart';
import '../core/providers/auth_provider.dart';
import '../core/services/api_service.dart';
import '../core/services/apk_update.dart';

/// Bandeau de mise à jour au-dessus de TOUS les écrans (placé dans
/// `MaterialApp.builder`, comme la garde d'authentification) : vérifie la
/// dernière version publiée dans Odoo une fois connecté et à chaque retour
/// au premier plan. Rien sur web (la PWA se met à jour seule).
class UpdateBannerHost extends StatefulWidget {
  const UpdateBannerHost({super.key, required this.child});
  final Widget child;

  @override
  State<UpdateBannerHost> createState() => _UpdateBannerHostState();
}

class _UpdateBannerHostState extends State<UpdateBannerHost> with WidgetsBindingObserver {
  final ApkUpdater _updater = ApkUpdater();
  ApkUpdate? _update;
  bool _wasAuthenticated = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    if (!kIsWeb) WidgetsBinding.instance.removeObserver(this);
    _updater.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final authenticated = context.watch<AuthProvider>().isAuthenticated;
    if (authenticated && !_wasAuthenticated) _check();
    if (!authenticated) _update = null;
    _wasAuthenticated = authenticated;
  }

  Future<void> _check() async {
    if (kIsWeb || !ApiService().isAuthenticated) return;
    final info = await ApiService().getAppUpdate();
    if (!mounted) return;
    setState(() => _update = ApkUpdate.fromMap(info));
  }

  @override
  Widget build(BuildContext context) {
    final show = !kIsWeb && (_update?.isNewerThan(AppConfig.buildNumber) ?? false);
    if (!show) return widget.child;
    return Column(
      children: [
        Material(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              child: UpdateBanner(
                update: _update,
                currentVersionCode: AppConfig.buildNumber,
                updater: _updater,
                appName: AppConfig.appName,
              ),
            ),
          ),
        ),
        Expanded(
          child: MediaQuery.removePadding(context: context, removeTop: true, child: widget.child),
        ),
      ],
    );
  }
}
