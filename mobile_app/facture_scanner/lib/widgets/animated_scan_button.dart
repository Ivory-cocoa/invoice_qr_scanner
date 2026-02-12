/// Animated Scan Button Widget - Design Professionnel ICP
/// Bouton de scan avec animation de pulsation et feedback haptique

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_theme.dart';

/// Bouton de scan animé avec effet de pulsation
/// Fournit un feedback visuel attractif pour l'action principale
class AnimatedScanButton extends StatefulWidget {
  final VoidCallback onPressed;
  final bool isLoading;
  final bool isEnabled;
  final double size;

  const AnimatedScanButton({
    super.key,
    required this.onPressed,
    this.isLoading = false,
    this.isEnabled = true,
    this.size = 80,
  });

  @override
  State<AnimatedScanButton> createState() => _AnimatedScanButtonState();
}

class _AnimatedScanButtonState extends State<AnimatedScanButton>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _rotationController;
  late AnimationController _scaleController;
  
  late Animation<double> _pulseAnimation;
  late Animation<double> _rotationAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    
    // Animation de pulsation continue
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    // Animation de rotation pour le loading
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    
    _rotationAnimation = Tween<double>(begin: 0, end: 2 * math.pi).animate(
      CurvedAnimation(parent: _rotationController, curve: Curves.linear),
    );
    
    // Animation de scale au tap
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.92).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(AnimatedScanButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    if (widget.isLoading && !oldWidget.isLoading) {
      _rotationController.repeat();
      _pulseController.stop();
    } else if (!widget.isLoading && oldWidget.isLoading) {
      _rotationController.stop();
      _rotationController.reset();
      _pulseController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotationController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (widget.isEnabled && !widget.isLoading) {
      _scaleController.forward();
      HapticFeedback.lightImpact();
    }
  }

  void _handleTapUp(TapUpDetails details) {
    _scaleController.reverse();
  }

  void _handleTapCancel() {
    _scaleController.reverse();
  }

  void _handleTap() {
    if (widget.isEnabled && !widget.isLoading) {
      HapticFeedback.mediumImpact();
      widget.onPressed();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: _handleTap,
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _pulseAnimation,
          _scaleAnimation,
        ]),
        builder: (context, child) {
          final double scale = widget.isLoading 
              ? 1.0 
              : _pulseAnimation.value * _scaleAnimation.value;
          
          return Transform.scale(
            scale: scale,
            child: child,
          );
        },
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: widget.isEnabled
                ? AppTheme.primaryGradient
                : LinearGradient(
                    colors: [Colors.grey.shade400, Colors.grey.shade500],
                  ),
            boxShadow: widget.isEnabled
                ? [
                    BoxShadow(
                      color: AppTheme.primaryColor.withOpacity(0.4),
                      blurRadius: 20,
                      spreadRadius: 2,
                      offset: const Offset(0, 8),
                    ),
                    BoxShadow(
                      color: AppTheme.primaryColor.withOpacity(0.2),
                      blurRadius: 40,
                      spreadRadius: 4,
                      offset: const Offset(0, 16),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.2),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Cercles concentriques animés
              if (!widget.isLoading) ..._buildRipples(),
              
              // Icône centrale
              widget.isLoading
                  ? _buildLoadingIndicator()
                  : Icon(
                      Icons.qr_code_scanner_rounded,
                      color: Colors.white,
                      size: widget.size * 0.45,
                    ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildRipples() {
    return [
      // Premier cercle
      AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, _) {
          return Container(
            width: widget.size * 0.7 * _pulseAnimation.value,
            height: widget.size * 0.7 * _pulseAnimation.value,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 1.5,
              ),
            ),
          );
        },
      ),
      // Deuxième cercle (déphasé)
      AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, _) {
          final delay = 1.0 - ((_pulseAnimation.value - 1.0) / 0.15).abs();
          return Container(
            width: widget.size * 0.5 * (1.0 + (0.15 * delay)),
            height: widget.size * 0.5 * (1.0 + (0.15 * delay)),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withOpacity(0.2 * delay),
                width: 1,
              ),
            ),
          );
        },
      ),
    ];
  }

  Widget _buildLoadingIndicator() {
    return AnimatedBuilder(
      animation: _rotationAnimation,
      builder: (context, child) {
        return Transform.rotate(
          angle: _rotationAnimation.value,
          child: child,
        );
      },
      child: SizedBox(
        width: widget.size * 0.4,
        height: widget.size * 0.4,
        child: CircularProgressIndicator(
          strokeWidth: 3,
          valueColor: AlwaysStoppedAnimation<Color>(
            Colors.white.withOpacity(0.9),
          ),
        ),
      ),
    );
  }
}

/// Mini bouton de scan pour la barre d'action
class MiniScanButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool isEnabled;

  const MiniScanButton({
    super.key,
    required this.onPressed,
    this.isEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isEnabled ? onPressed : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: isEnabled ? AppTheme.primaryGradient : null,
            color: isEnabled ? null : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(12),
            boxShadow: isEnabled
                ? [
                    BoxShadow(
                      color: AppTheme.primaryColor.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            Icons.qr_code_scanner_rounded,
            color: isEnabled ? Colors.white : Colors.grey.shade500,
            size: 24,
          ),
        ),
      ),
    );
  }
}
