/// Enhanced Scanner Screen - Design Professionnel ICP
/// Interface de scan QR moderne avec overlay personnalisé et animations avancées

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/theme/app_theme.dart';

/// Écran de scan QR amélioré avec animations et feedback visuel avancé
class EnhancedScannerScreen extends StatefulWidget {
  final bool showInstructions;
  final bool autoClose;
  final Duration? autoCloseDelay;
  final String? title;
  final List<String>? allowedDomains;

  const EnhancedScannerScreen({
    super.key,
    this.showInstructions = true,
    this.autoClose = true,
    this.autoCloseDelay,
    this.title,
    this.allowedDomains,
  });

  @override
  State<EnhancedScannerScreen> createState() => _EnhancedScannerScreenState();
}

class _EnhancedScannerScreenState extends State<EnhancedScannerScreen>
    with TickerProviderStateMixin {
  MobileScannerController? _controller;
  bool _isFlashOn = false;
  bool _hasScanned = false;
  bool _isCameraReady = false;
  String? _errorMessage;
  
  // Controllers d'animation
  late AnimationController _scanLineController;
  late AnimationController _cornerController;
  late AnimationController _pulseController;
  late AnimationController _successController;
  
  // Animations
  late Animation<double> _scanLineAnimation;
  late Animation<double> _cornerAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _successScaleAnimation;
  late Animation<double> _successOpacityAnimation;

  @override
  void initState() {
    super.initState();
    _initScanner();
    _setupAnimations();
  }

  void _initScanner() {
    try {
      _controller = MobileScannerController(
        detectionSpeed: DetectionSpeed.normal,
        facing: CameraFacing.back,
        torchEnabled: false,
      );
      
      // Écouter les changements d'état de la caméra
      _controller!.start().then((_) {
        if (mounted) {
          setState(() => _isCameraReady = true);
        }
      }).catchError((error) {
        if (mounted) {
          setState(() => _errorMessage = 'Erreur caméra: $error');
        }
      });
    } catch (e) {
      _errorMessage = 'Impossible d\'initialiser la caméra';
    }
  }

  void _setupAnimations() {
    // Animation de la ligne de scan
    _scanLineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);
    
    _scanLineAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _scanLineController, curve: Curves.easeInOut),
    );

    // Animation des coins
    _cornerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    
    _cornerAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _cornerController, curve: Curves.easeInOut),
    );

    // Animation de pulsation
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    
    _pulseAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );

    // Animation de succès
    _successController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    
    _successScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _successController,
        curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
      ),
    );
    
    _successOpacityAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _successController,
        curve: const Interval(0.0, 0.3, curve: Curves.easeIn),
      ),
    );
  }

  @override
  void dispose() {
    _scanLineController.dispose();
    _cornerController.dispose();
    _pulseController.dispose();
    _successController.dispose();
    _controller?.dispose();
    super.dispose();
  }

  bool _isValidQrCode(String? value) {
    if (value == null || value.isEmpty) return false;
    
    // Si des domaines sont spécifiés, vérifier
    if (widget.allowedDomains != null && widget.allowedDomains!.isNotEmpty) {
      return widget.allowedDomains!.any((domain) => value.contains(domain));
    }
    
    // Par défaut, accepter les URLs DGI
    return value.contains('services.fne.dgi.gouv.ci');
  }

  void _onDetect(BarcodeCapture capture) {
    if (_hasScanned) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final String? value = barcodes.first.rawValue;
    
    if (!_isValidQrCode(value)) {
      // QR code non valide - afficher un feedback
      HapticFeedback.lightImpact();
      _showInvalidQrFeedback();
      return;
    }

    setState(() => _hasScanned = true);
    
    // Feedback haptique
    HapticFeedback.mediumImpact();
    
    // Arrêter les animations de scan
    _scanLineController.stop();
    _cornerController.stop();
    _pulseController.stop();
    
    // Jouer l'animation de succès
    _successController.forward().then((_) {
      if (widget.autoClose) {
        Future.delayed(widget.autoCloseDelay ?? const Duration(milliseconds: 500), () {
          if (mounted) {
            Navigator.of(context).pop(value);
          }
        });
      }
    });
  }

  void _showInvalidQrFeedback() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning_rounded, color: Colors.white),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'QR code non valide. Seules les factures DGI sont acceptées.',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.warningColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _toggleFlash() async {
    if (_controller == null) return;
    await _controller!.toggleTorch();
    setState(() => _isFlashOn = !_isFlashOn);
    HapticFeedback.lightImpact();
  }

  void _switchCamera() async {
    if (_controller == null) return;
    await _controller!.switchCamera();
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final scanAreaSize = size.width * 0.72;

    if (_errorMessage != null) {
      return _buildErrorScreen();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Scanner camera
          if (_controller != null)
            MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
              errorBuilder: (context, error, child) {
                return _buildCameraError(error);
              },
            ),

          // Loading indicator pendant l'initialisation
          if (!_isCameraReady)
            const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),

          // Overlay sombre avec découpe
          _buildScanOverlay(size, scanAreaSize),

          // Zone de scan avec animations
          _buildScanArea(size, scanAreaSize),

          // Indicateur de succès
          if (_hasScanned) _buildSuccessIndicator(size, scanAreaSize),

          // AppBar personnalisée
          _buildCustomAppBar(),

          // Instructions en bas
          if (widget.showInstructions && !_hasScanned) _buildInstructions(size),
        ],
      ),
    );
  }

  Widget _buildErrorScreen() {
    return Scaffold(
      backgroundColor: AppTheme.surfaceLight,
      appBar: AppBar(
        title: const Text('Erreur'),
        backgroundColor: AppTheme.errorColor,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppTheme.errorLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.camera_alt_rounded,
                  size: 64,
                  color: AppTheme.errorColor,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Retour'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCameraError(MobileScannerException error) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.videocam_off_rounded,
              size: 64,
              color: Colors.white54,
            ),
            const SizedBox(height: 16),
            Text(
              _getCameraErrorMessage(error),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getCameraErrorMessage(MobileScannerException error) {
    switch (error.errorCode) {
      case MobileScannerErrorCode.permissionDenied:
        return 'Autorisation caméra refusée.\nVeuillez l\'activer dans les paramètres.';
      case MobileScannerErrorCode.controllerUninitialized:
        return 'Erreur d\'initialisation de la caméra.';
      default:
        return 'Erreur caméra: ${error.errorDetails?.message ?? "Inconnue"}';
    }
  }

  Widget _buildCustomAppBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.7),
                Colors.transparent,
              ],
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Bouton retour
              _buildCircleButton(
                icon: Icons.close_rounded,
                onTap: () => Navigator.of(context).pop(),
                tooltip: 'Fermer',
              ),

              // Titre
              Text(
                widget.title ?? 'Scanner QR',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),

              // Boutons d'action
              Row(
                children: [
                  _buildCircleButton(
                    icon: Icons.cameraswitch_rounded,
                    onTap: _switchCamera,
                    tooltip: 'Changer de caméra',
                  ),
                  const SizedBox(width: 8),
                  _buildCircleButton(
                    icon: _isFlashOn
                        ? Icons.flash_on_rounded
                        : Icons.flash_off_rounded,
                    onTap: _toggleFlash,
                    isActive: _isFlashOn,
                    tooltip: _isFlashOn ? 'Désactiver le flash' : 'Activer le flash',
                  ),
                ],
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
    String? tooltip,
  }) {
    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isActive
                ? AppTheme.primaryColor
                : Colors.black.withOpacity(0.4),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Icon(
            icon,
            color: Colors.white,
            size: 22,
          ),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip, child: button);
    }
    return button;
  }

  Widget _buildScanOverlay(Size size, double scanAreaSize) {
    return CustomPaint(
      size: size,
      painter: _ScanOverlayPainter(
        scanAreaSize: scanAreaSize,
        borderRadius: 24,
      ),
    );
  }

  Widget _buildScanArea(Size size, double scanAreaSize) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    return Positioned(
      left: centerX - scanAreaSize / 2,
      top: centerY - scanAreaSize / 2,
      child: AnimatedBuilder(
        animation: Listenable.merge([_cornerAnimation, _scanLineAnimation]),
        builder: (context, child) {
          return SizedBox(
            width: scanAreaSize,
            height: scanAreaSize,
            child: Stack(
              children: [
                // Coins animés
                _buildAnimatedCorners(scanAreaSize),

                // Ligne de scan
                if (!_hasScanned) _buildScanLine(scanAreaSize),

                // Cercles de pulsation
                if (!_hasScanned) _buildPulseRings(scanAreaSize),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAnimatedCorners(double size) {
    const cornerLength = 30.0;
    const cornerWidth = 4.0;
    final scale = _cornerAnimation.value;

    return Transform.scale(
      scale: scale,
      child: CustomPaint(
        size: Size(size, size),
        painter: _CornersPainter(
          cornerLength: cornerLength,
          cornerWidth: cornerWidth,
          color: AppTheme.primaryColor,
          borderRadius: 24,
        ),
      ),
    );
  }

  Widget _buildScanLine(double scanAreaSize) {
    final linePosition = _scanLineAnimation.value * (scanAreaSize - 40);

    return Positioned(
      top: linePosition + 20,
      left: 20,
      right: 20,
      child: Container(
        height: 3,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.primaryColor.withOpacity(0),
              AppTheme.primaryColor,
              AppTheme.primaryColor,
              AppTheme.primaryColor.withOpacity(0),
            ],
            stops: const [0, 0.2, 0.8, 1],
          ),
          borderRadius: BorderRadius.circular(2),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryColor.withOpacity(0.6),
              blurRadius: 8,
              spreadRadius: 2,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPulseRings(double scanAreaSize) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, _) {
        final progress = _pulseAnimation.value;
        final opacity = 1.0 - progress;
        final scale = 0.5 + (progress * 0.3);

        return Center(
          child: Container(
            width: scanAreaSize * scale,
            height: scanAreaSize * scale,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24 * scale),
              border: Border.all(
                color: AppTheme.primaryColor.withOpacity(opacity * 0.5),
                width: 2,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildSuccessIndicator(Size size, double scanAreaSize) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;

    return AnimatedBuilder(
      animation: _successController,
      builder: (context, _) {
        return Positioned(
          left: centerX - 50,
          top: centerY - 50,
          child: Opacity(
            opacity: _successOpacityAnimation.value,
            child: Transform.scale(
              scale: _successScaleAnimation.value,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: AppTheme.successColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.successColor.withOpacity(0.4),
                      blurRadius: 20,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 56,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInstructions(Size size) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 24,
          bottom: MediaQuery.of(context).padding.bottom + 24,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withOpacity(0.8),
              Colors.transparent,
            ],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icône QR
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.qr_code_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),

            // Texte principal
            const Text(
              'Placez le QR code dans le cadre',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),

            // Sous-texte
            Text(
              'Le scan sera automatique dès la détection',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
              textAlign: TextAlign.center,
            ),

            // Badge DGI
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppTheme.primaryColor.withOpacity(0.4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.verified_rounded,
                    color: AppTheme.primaryLight,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Factures DGI uniquement',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Painter pour l'overlay avec découpe
class _ScanOverlayPainter extends CustomPainter {
  final double scanAreaSize;
  final double borderRadius;

  _ScanOverlayPainter({
    required this.scanAreaSize,
    this.borderRadius = 24,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withOpacity(0.6)
      ..style = PaintingStyle.fill;

    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final halfSize = scanAreaSize / 2;

    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(centerX, centerY),
          width: scanAreaSize,
          height: scanAreaSize,
        ),
        Radius.circular(borderRadius),
      ))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ScanOverlayPainter oldDelegate) {
    return oldDelegate.scanAreaSize != scanAreaSize ||
        oldDelegate.borderRadius != borderRadius;
  }
}

/// Painter pour les coins de la zone de scan
class _CornersPainter extends CustomPainter {
  final double cornerLength;
  final double cornerWidth;
  final Color color;
  final double borderRadius;

  _CornersPainter({
    required this.cornerLength,
    required this.cornerWidth,
    required this.color,
    this.borderRadius = 24,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = cornerWidth
      ..strokeCap = StrokeCap.round;

    // Haut-gauche
    canvas.drawPath(
      _createCornerPath(0, 0, cornerLength, borderRadius, true, true),
      paint,
    );

    // Haut-droite
    canvas.drawPath(
      _createCornerPath(size.width, 0, cornerLength, borderRadius, false, true),
      paint,
    );

    // Bas-gauche
    canvas.drawPath(
      _createCornerPath(0, size.height, cornerLength, borderRadius, true, false),
      paint,
    );

    // Bas-droite
    canvas.drawPath(
      _createCornerPath(
          size.width, size.height, cornerLength, borderRadius, false, false),
      paint,
    );
  }

  Path _createCornerPath(
    double x,
    double y,
    double length,
    double radius,
    bool left,
    bool top,
  ) {
    final path = Path();
    final xDir = left ? 1 : -1;
    final yDir = top ? 1 : -1;

    path.moveTo(x + (xDir * length), y);
    path.lineTo(x + (xDir * radius), y);
    path.quadraticBezierTo(x, y, x, y + (yDir * radius));
    path.lineTo(x, y + (yDir * length));

    return path;
  }

  @override
  bool shouldRepaint(covariant _CornersPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.cornerLength != cornerLength ||
        oldDelegate.cornerWidth != cornerWidth;
  }
}
