/// Scanner Screen - Design Professionnel ICP
/// Interface de scan QR moderne avec overlay personnalisé
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/theme/app_theme.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> with SingleTickerProviderStateMixin {
  MobileScannerController? _controller;
  bool _isFlashOn = false;
  bool _hasScanned = false;
  String? _errorFlash;
  Timer? _resetTimer;
  late AnimationController _animationController;
  late Animation<double> _scanLineAnimation;

  @override
  void initState() {
    super.initState();
    _initScanner();
    _setupAnimation();
  }

  void _initScanner() {
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  void _setupAnimation() {
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    
    _scanLineAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    _animationController.dispose();
    // Arrêter le flux caméra AVANT de disposer le contrôleur pour éviter
    // qu'un dernier `onDetect` ne se déclenche après la libération.
    _controller?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    // Garde atomique : ignore toute détection après le premier scan réussi
    // ou après démontage du widget (évite "setState after dispose").
    if (_hasScanned || !mounted) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final String? value = barcodes.first.rawValue;
    if (value == null || value.isEmpty) return;

    // Validation immédiate : seuls les QR-codes DGI sont acceptés. En cas de
    // QR non reconnu, on affiche un retour visuel sans quitter le scanner,
    // pour permettre de rescanner un code correct tout de suite.
    if (!_isDgiUrl(value)) {
      _hasScanned = true;
      HapticFeedback.vibrate();
      if (mounted) {
        setState(() => _errorFlash = 'QR-code non reconnu. Scannez une facture DGI.');
      }
      _resetTimer?.cancel();
      _resetTimer = Timer(const Duration(milliseconds: 1800), () {
        if (!mounted) return;
        setState(() {
          _hasScanned = false;
          _errorFlash = null;
        });
      });
      return;
    }

    _hasScanned = true;
    if (mounted) setState(() => _errorFlash = null);

    // Feedback haptique
    HapticFeedback.mediumImpact();

    // Arrêter la caméra immédiatement puis retourner le résultat
    _controller?.stop();
    if (mounted) {
      Navigator.of(context).pop(value);
    }
  }

  /// Un QR-code DGI valide contient le domaine de vérification officiel.
  bool _isDgiUrl(String value) => value.contains('services.fne.dgi.gouv.ci');

  void _toggleFlash() async {
    try {
      await _controller?.toggleTorch();
      if (mounted) setState(() => _isFlashOn = !_isFlashOn);
    } catch (_) {
      // Certains appareils n'ont pas de flash : ignorer silencieusement.
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final scanAreaSize = size.width * 0.75;
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Scanner camera
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          
          // Overlay sombre avec découpe
          _buildScanOverlay(size, scanAreaSize),
          
          // AppBar personnalisée
          _buildCustomAppBar(),
          
          // Zone de scan avec animation
          _buildScanArea(size, scanAreaSize),
          
          // Instructions en bas
          _buildInstructions(size),

          // Retour visuel transitoire pour un QR non reconnu
          if (_errorFlash != null) _buildErrorFlash(size),
        ],
      ),
    );
  }

  Widget _buildErrorFlash(Size size) {
    return Positioned(
      top: size.height * 0.5 + size.width * 0.4,
      left: 24,
      right: 24,
      child: AnimatedOpacity(
        opacity: _errorFlash != null ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppTheme.errorColor.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.white, size: 22),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  _errorFlash!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomAppBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Bouton retour
              _buildCircleButton(
                icon: Icons.arrow_back_rounded,
                onTap: () => Navigator.of(context).pop(),
                semanticLabel: 'Retour',
              ),
              
              // Titre
              const Text(
                'Scanner QR',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              
              // Bouton flash
              _buildCircleButton(
                icon: _isFlashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                onTap: _toggleFlash,
                isActive: _isFlashOn,
                semanticLabel:
                    _isFlashOn ? 'Désactiver le flash' : 'Activer le flash',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required VoidCallback onTap,
    bool isActive = false,
    String? semanticLabel,
  }) {
    return Semantics(
      label: semanticLabel,
      button: true,
      child: Material(
        color: isActive ? AppTheme.primaryColor : Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(25),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(25),
          child: Container(
            width: 50,
            height: 50,
            alignment: Alignment.center,
            child: Icon(
              icon,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScanOverlay(Size size, double scanAreaSize) {
    return CustomPaint(
      size: size,
      painter: ScanOverlayPainter(
        scanAreaSize: scanAreaSize,
        overlayColor: Colors.black.withValues(alpha: 0.6),
      ),
    );
  }

  Widget _buildScanArea(Size size, double scanAreaSize) {
    final top = (size.height - scanAreaSize) / 2 - 30;
    final left = (size.width - scanAreaSize) / 2;
    
    return Positioned(
      top: top,
      left: left,
      child: SizedBox(
        width: scanAreaSize,
        height: scanAreaSize,
        child: Stack(
          children: [
            // Coins du cadre
            _buildCorner(Alignment.topLeft),
            _buildCorner(Alignment.topRight),
            _buildCorner(Alignment.bottomLeft),
            _buildCorner(Alignment.bottomRight),
            
            // Ligne de scan animée
            AnimatedBuilder(
              animation: _scanLineAnimation,
              builder: (context, child) {
                return Positioned(
                  top: _scanLineAnimation.value * (scanAreaSize - 4),
                  left: 20,
                  right: 20,
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          AppTheme.primaryLight.withValues(alpha: 0.8),
                          AppTheme.primaryColor,
                          AppTheme.primaryLight.withValues(alpha: 0.8),
                          Colors.transparent,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryColor.withValues(alpha: 0.5),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCorner(Alignment alignment) {
    const size = 30.0;
    const thickness = 4.0;
    
    BorderRadius borderRadius;
    if (alignment == Alignment.topLeft) {
      borderRadius = const BorderRadius.only(topLeft: Radius.circular(12));
    } else if (alignment == Alignment.topRight) {
      borderRadius = const BorderRadius.only(topRight: Radius.circular(12));
    } else if (alignment == Alignment.bottomLeft) {
      borderRadius = const BorderRadius.only(bottomLeft: Radius.circular(12));
    } else {
      borderRadius = const BorderRadius.only(bottomRight: Radius.circular(12));
    }
    
    return Positioned(
      top: alignment == Alignment.topLeft || alignment == Alignment.topRight ? 0 : null,
      bottom: alignment == Alignment.bottomLeft || alignment == Alignment.bottomRight ? 0 : null,
      left: alignment == Alignment.topLeft || alignment == Alignment.bottomLeft ? 0 : null,
      right: alignment == Alignment.topRight || alignment == Alignment.bottomRight ? 0 : null,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          border: Border(
            top: alignment == Alignment.topLeft || alignment == Alignment.topRight
                ? const BorderSide(color: Colors.white, width: thickness)
                : BorderSide.none,
            bottom: alignment == Alignment.bottomLeft || alignment == Alignment.bottomRight
                ? const BorderSide(color: Colors.white, width: thickness)
                : BorderSide.none,
            left: alignment == Alignment.topLeft || alignment == Alignment.bottomLeft
                ? const BorderSide(color: Colors.white, width: thickness)
                : BorderSide.none,
            right: alignment == Alignment.topRight || alignment == Alignment.bottomRight
                ? const BorderSide(color: Colors.white, width: thickness)
                : BorderSide.none,
          ),
          borderRadius: borderRadius,
        ),
      ),
    );
  }

  Widget _buildInstructions(Size size) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 30, 24, 50),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.transparent,
              Colors.black.withValues(alpha: 0.8),
            ],
          ),
        ),
        child: Column(
          children: [
            // Icône
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.qr_code_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Titre instruction
            const Text(
              'Placez le QR code dans le cadre',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            
            const SizedBox(height: 8),
            
            // Sous-titre
            Text(
              'Le scan sera effectué automatiquement',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Painter pour l'overlay avec découpe
class ScanOverlayPainter extends CustomPainter {
  final double scanAreaSize;
  final Color overlayColor;

  ScanOverlayPainter({
    required this.scanAreaSize,
    required this.overlayColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = overlayColor;
    
    // Zone de découpe au centre (légèrement au-dessus du centre)
    final scanRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2 - 30),
        width: scanAreaSize,
        height: scanAreaSize,
      ),
      const Radius.circular(16),
    );
    
    // Dessiner l'overlay avec la découpe
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(scanRect)
      ..fillType = PathFillType.evenOdd;
    
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
