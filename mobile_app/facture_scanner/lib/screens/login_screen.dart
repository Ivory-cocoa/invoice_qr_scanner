/// Login Screen - Design Professionnel ICP
/// Écran de connexion moderne avec gradient et animations
///
/// Connexion en deux temps par code à usage unique (OTP) : l'utilisateur
/// saisit son identifiant, reçoit un code à 6 chiffres par email, puis le
/// saisit pour obtenir son token de session. Il n'y a plus de mot de passe.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

import '../core/providers/auth_provider.dart';
import '../core/theme/app_theme.dart';
import '../core/config/environment.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _loginController = TextEditingController();
  final _otpController = TextEditingController();
  final _serverController = TextEditingController();

  bool _showServerConfig = false;

  /// Compte à rebours avant de pouvoir redemander un code. Doit rester aligné
  /// sur `OTP_RESEND_SECONDS` côté serveur, qui rejetterait une demande
  /// anticipée avec une erreur `OTP_TOO_SOON`.
  static const int _resendDelaySeconds = 60;
  int _resendCountdown = 0;
  Timer? _resendTimer;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _loadSavedServer();
    _setupAnimations();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic));
    
    _animationController.forward();
  }

  Future<void> _loadSavedServer() async {
    final auth = context.read<AuthProvider>();
    _serverController.text = auth.serverUrl;
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _animationController.dispose();
    _loginController.dispose();
    _otpController.dispose();
    _serverController.dispose();
    super.dispose();
  }

  void _startResendCountdown() {
    _resendTimer?.cancel();
    setState(() => _resendCountdown = _resendDelaySeconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _resendCountdown--);
      if (_resendCountdown <= 0) timer.cancel();
    });
  }

  /// Étape 1 — demander l'envoi du code par email.
  Future<void> _requestOtp() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();

    // Sauvegarder l'URL du serveur si modifiée
    if (_serverController.text.isNotEmpty) {
      await auth.setServerUrl(_serverController.text.trim());
    }

    final success = await auth.requestOtp(_loginController.text.trim());

    if (success && mounted) {
      _otpController.clear();
      _startResendCountdown();
    }
  }

  /// Étape 2 — vérifier le code saisi.
  Future<void> _verifyOtp() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();
    final success = await auth.verifyOtp(_otpController.text.trim());

    if (success && mounted) {
      Navigator.of(context).pushReplacementNamed('/home');
    }
  }

  /// Revenir à la saisie de l'identifiant.
  void _changeLogin() {
    _resendTimer?.cancel();
    setState(() => _resendCountdown = 0);
    _otpController.clear();
    context.read<AuthProvider>().resetOtpFlow();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    
    return Scaffold(
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Container(
          height: size.height,
          decoration: const BoxDecoration(
            gradient: AppTheme.darkGradient,
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: SlideTransition(
                    position: _slideAnimation,
                    child: Column(
                      children: [
                        SizedBox(height: size.height * 0.08),
                        
                        // Logo et titre
                        _buildHeader(),
                        
                        const SizedBox(height: 40),
                        
                        // Carte de formulaire
                        _buildLoginCard(),
                        
                        const SizedBox(height: 24),
                        
                        // Footer
                        _buildFooter(),
                        
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        // Icône logo
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(
            Icons.qr_code_scanner_rounded,
            size: 50,
            color: AppTheme.primaryDark,
          ),
        ),
        
        const SizedBox(height: 24),
        
        // Titre
        const Text(
          'Facture Scanner',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: -0.5,
          ),
        ),
        
        const SizedBox(height: 8),
        
        // Sous-titre
        Text(
          'Scanner QR DGI - Ivory Cocoa Products',
          style: TextStyle(
            fontSize: 15,
            color: Colors.white.withValues(alpha: 0.85),
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _buildLoginCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.getSurfaceElevated(context),
        borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 30,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Titre de la carte
              Text(
                'Connexion',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.getTextPrimary(context),
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 8),
              
              Consumer<AuthProvider>(
                builder: (context, auth, _) => Text(
                  auth.isAwaitingOtp
                      ? 'Saisissez le code envoyé à ${auth.pendingLogin}'
                      : 'Recevez un code de connexion par email',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.getTextSecondary(context),
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Message d'erreur
              Consumer<AuthProvider>(
                builder: (context, auth, _) {
                  if (auth.errorMessage != null) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 20),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.getErrorLight(context),
                        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                        border: Border.all(color: AppTheme.getError(context).withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: AppTheme.getError(context), size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              auth.errorMessage!,
                              style: TextStyle(
                                color: AppTheme.getError(context),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
              
              // Étape 1 (identifiant + serveur) ou étape 2 (code reçu)
              Consumer<AuthProvider>(
                builder: (context, auth, _) {
                  return auth.isAwaitingOtp
                      ? _buildOtpStep()
                      : _buildLoginStep();
                },
              ),

              const SizedBox(height: 32),

              // Bouton connexion
              _buildLoginButton(),
            ],
          ),
        ),
      ),
    );
  }

  /// Étape 1 : identifiant + configuration serveur.
  Widget _buildLoginStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTextField(
          controller: _loginController,
          label: 'Identifiant',
          hint: 'Email ou nom d\'utilisateur',
          icon: Icons.person_outline_rounded,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _requestOtp(),
          validator: (value) {
            if (value == null || value.trim().isEmpty) {
              return 'Veuillez entrer votre identifiant';
            }
            return null;
          },
        ),

        const SizedBox(height: 16),

        // Bouton configuration serveur
        _buildServerToggle(),

        // Champ serveur (collapsible) + avertissement HTTP non sécurisé
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _serverController,
          builder: (context, value, _) {
            final insecure = _isUrlInsecure(value.text);
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              height: _showServerConfig ? (insecure ? 178 : 90) : 0,
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildTextField(
                        controller: _serverController,
                        label: 'URL du serveur',
                        hint: 'https://odoo.example.com',
                        icon: Icons.cloud_outlined,
                        keyboardType: TextInputType.url,
                      ),
                      if (insecure) _buildInsecureWarning(),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  /// Étape 2 : saisie du code reçu par email, renvoi et retour arrière.
  Widget _buildOtpStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTextField(
          controller: _otpController,
          label: 'Code de connexion',
          hint: '6 chiffres',
          icon: Icons.mark_email_read_outlined,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _verifyOtp(),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          validator: (value) {
            final code = (value ?? '').trim();
            if (code.isEmpty) return 'Veuillez entrer le code reçu';
            if (code.length != 6) return 'Le code comporte 6 chiffres';
            return null;
          },
        ),

        const SizedBox(height: 12),

        Text(
          "Le code expire au bout de 10 minutes. Pensez à vérifier vos "
          "courriers indésirables.",
          style: TextStyle(
            fontSize: 12.5,
            color: AppTheme.getTextSecondary(context),
          ),
          textAlign: TextAlign.center,
        ),

        const SizedBox(height: 8),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: _changeLogin,
              child: Text(
                "Modifier l'identifiant",
                style: TextStyle(
                  color: AppTheme.getTextSecondary(context),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            TextButton(
              onPressed: _resendCountdown > 0 ? null : _requestOtp,
              child: Text(
                _resendCountdown > 0
                    ? 'Renvoyer ($_resendCountdown s)'
                    : 'Renvoyer le code',
                style: TextStyle(
                  color: _resendCountdown > 0
                      ? AppTheme.getTextMuted(context)
                      : AppTheme.getPrimary(context),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    Widget? suffixIcon,
    String? Function(String?)? validator,
    void Function(String)? onFieldSubmitted,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      inputFormatters: inputFormatters,
      validator: validator,
      style: const TextStyle(
        color: AppTheme.primaryDark,  // TEXTE BLEU FONCÉ
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: AppTheme.getPrimary(context)),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: AppTheme.getSurfaceLight(context),
        labelStyle: TextStyle(
          color: AppTheme.getTextSecondary(context),
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
        hintStyle: TextStyle(
          color: AppTheme.getTextMuted(context).withValues(alpha: 0.6),
          fontSize: 14,
        ),
        floatingLabelStyle: TextStyle(
          color: AppTheme.getPrimary(context),
          fontWeight: FontWeight.w600,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          borderSide: BorderSide(color: AppTheme.dividerColor.withValues(alpha: 0.5), width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          borderSide: BorderSide(color: AppTheme.getPrimary(context), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          borderSide: BorderSide(color: AppTheme.getError(context), width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          borderSide: BorderSide(color: AppTheme.getError(context), width: 2),
        ),
      ),
    );
  }

  /// Détecte une URL non sécurisée (http en clair hors réseau local privé).
  bool _isUrlInsecure(String url) {
    final u = url.trim().toLowerCase();
    if (!u.startsWith('http://')) return false;
    final isLocal = u.contains('localhost') ||
        u.contains('127.0.0.1') ||
        u.contains('//192.168.') ||
        u.contains('//10.') ||
        u.contains('//172.');
    return !isLocal;
  }

  Widget _buildInsecureWarning() {
    final warning = AppTheme.getWarning(context);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: warning, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Connexion non sécurisée (HTTP). Utilisez https:// pour '
              'protéger vos identifiants.',
              style: TextStyle(
                color: warning,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServerToggle() {
    return InkWell(
      onTap: () => setState(() => _showServerConfig = !_showServerConfig),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.settings_outlined,
              size: 18,
              color: AppTheme.getTextSecondary(context).withValues(alpha: 0.8),
            ),
            const SizedBox(width: 8),
            Text(
              'Configuration serveur',
              style: TextStyle(
                color: AppTheme.getTextSecondary(context).withValues(alpha: 0.8),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              _showServerConfig ? Icons.expand_less : Icons.expand_more,
              size: 20,
              color: AppTheme.getTextSecondary(context).withValues(alpha: 0.8),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginButton() {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        final awaitingOtp = auth.isAwaitingOtp;
        return SizedBox(
          height: 56,
          child: ElevatedButton(
            onPressed: auth.isLoading
                ? null
                : (awaitingOtp ? _verifyOtp : _requestOtp),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.getPrimary(context),
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppTheme.getPrimary(context).withValues(alpha: 0.6),
              elevation: auth.isLoading ? 0 : 4,
              shadowColor: AppTheme.getPrimary(context).withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              ),
            ),
            child: auth.isLoading
                ? const SpinKitThreeBounce(
                    color: Colors.white,
                    size: 24,
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        awaitingOtp
                            ? Icons.login_rounded
                            : Icons.send_rounded,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        awaitingOtp ? 'Se connecter' : 'Recevoir un code',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _buildFooter() {
    return Column(
      children: [
        Text(
          'Scanner QR Factures DGI',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 13,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Version ${AppConfig.appVersion}',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
