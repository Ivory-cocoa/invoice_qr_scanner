/// Manager Home Screen - Double profil Vérificateur + Traiteur
/// Permet de basculer entre le mode Vérificateur et Traiteur
/// Le dernier mode sélectionné est mémorisé via SharedPreferences
library;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme/app_theme.dart';
import 'home_screen.dart';
import 'traiteur_home_screen.dart';

const String _kModeKey = 'manager_active_mode';

enum ManagerMode { verificateur, traiteur }

class ManagerHomeScreen extends StatefulWidget {
  const ManagerHomeScreen({super.key});

  @override
  State<ManagerHomeScreen> createState() => _ManagerHomeScreenState();
}

class _ManagerHomeScreenState extends State<ManagerHomeScreen> {
  ManagerMode _mode = ManagerMode.verificateur;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadSavedMode();
  }

  Future<void> _loadSavedMode() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_kModeKey);
    if (saved == 'traiteur') {
      _mode = ManagerMode.traiteur;
    }
    setState(() => _loaded = true);
  }

  Future<void> _switchMode(ManagerMode mode) async {
    if (mode == _mode) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kModeKey,
      mode == ManagerMode.traiteur ? 'traiteur' : 'verificateur',
    );
    setState(() => _mode = mode);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Stack(
      children: [
        // Écran actif selon le mode
        if (_mode == ManagerMode.verificateur)
          const HomeScreen(embedded: true)
        else
          const TraiteurHomeScreen(embedded: true),

        // Sélecteur de mode flottant en haut
        // À GAUCHE, sur la place du titre : centré, il recouvrait les
        // boutons de la barre du haut (actualiser, compte) sur un téléphone
        // étroit. `Material` : sans lui, le texte n'a pas de style par
        // défaut et s'affiche souligné de jaune.
        Positioned(
          top: MediaQuery.of(context).padding.top + 6,
          left: 10,
          child: Material(
            type: MaterialType.transparency,
            child: _buildModeToggle(),
          ),
        ),
      ],
    );
  }

  Widget _buildModeToggle() {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppTheme.getSurfaceElevated(context),
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToggleButton(
            mode: ManagerMode.verificateur,
            label: 'Vérificateur',
            icon: Icons.qr_code_scanner_rounded,
            color: AppTheme.getPrimary(context),
          ),
          _buildToggleButton(
            mode: ManagerMode.traiteur,
            label: 'Traiteur',
            icon: Icons.assignment_turned_in_rounded,
            color: AppTheme.getAccent(context),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleButton({
    required ManagerMode mode,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    final isActive = _mode == mode;

    return Semantics(
      label: 'Mode $label',
      selected: isActive,
      button: true,
      child: GestureDetector(
        onTap: () => _switchMode(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: isActive ? color : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: isActive
                    ? AppTheme.onColor(color)
                    : AppTheme.getTextSecondary(context),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isActive
                      ? AppTheme.onColor(color)
                      : AppTheme.getTextSecondary(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
