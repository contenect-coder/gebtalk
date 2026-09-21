import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../widgets/ebi_bot.dart';
import '../widgets/animations.dart';
import '../theme/colors.dart';
import 'home_screen.dart';
import '../services/api_service.dart';
import '../utils/error_handler.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({Key? key}) : super(key: key);

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with TickerProviderStateMixin {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _isCelebrating = false;
  String _errorMessage = '';

  // --- Animation controllers ---
  late AnimationController _bgController;
  late AnimationController _floatController1;
  late AnimationController _floatController2;
  late AnimationController _floatController3;
  late AnimationController _logoController;
  late AnimationController _celebrationController;

  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _celebrationScale;

  @override
  void initState() {
    super.initState();

    // Background gradient shift – 8 second loop
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);

    // Floating decorative circles – three different periods
    _floatController1 = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    _floatController2 = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();

    _floatController3 = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();

    // Logo entrance – elastic bounce
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _logoScale = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.elasticOut),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
      ),
    );

    // Celebration overlay bounce
    _celebrationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _celebrationScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _celebrationController, curve: Curves.elasticOut),
    );

    // Kick off logo entrance after a tiny delay
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _logoController.forward();
    });
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _bgController.dispose();
    _floatController1.dispose();
    _floatController2.dispose();
    _floatController3.dispose();
    _logoController.dispose();
    _celebrationController.dispose();
    super.dispose();
  }

  // ----- Business logic -----

  void _loginWithCredentials() async {
    final identifier = _usernameController.text.trim();
    if (identifier.isEmpty) {
      setState(() {
        _errorMessage = 'PLEASE ENTER USERNAME OR EMAIL';
      });
      return;
    }

    final password = _passwordController.text.trim();
    if (password.isEmpty) {
      setState(() {
        _errorMessage = 'PLEASE ENTER PASSWORD';
      });
      return;
    }

    setState(() {
      _errorMessage = '';
    });

    final appState = Provider.of<AppState>(context, listen: false);
    final success = await appState.loginWithEmail(identifier, password);

    if (success) {
      if (mounted) {
        setState(() {
          _isCelebrating = true;
        });
        _celebrationController.forward();

        Future.delayed(const Duration(milliseconds: 1400), () {
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (context) => const HomeScreen()),
            );
          }
        });
      }
    } else {
      setState(() {
        if (ApiService.lastAuthError == 'SERVER_ERROR' || ApiService.lastAuthError == 'NETWORK_ERROR') {
          _errorMessage = ApiService.lastDetailedError != null && ApiService.lastDetailedError!.isNotEmpty
              ? 'SERVER OFFLINE: ${ApiService.lastDetailedError}'
              : 'SERVER OFFLINE - CHECK SETTINGS (⚙️)';
        } else if (ApiService.lastAuthError != null && ApiService.lastAuthError != 'AUTH_FAILED') {
          _errorMessage = ApiService.lastAuthError!.toUpperCase();
        } else {
          _errorMessage = 'INVALID USERNAME OR PASSWORD';
        }
      });
    }
  }

  void _showServerSettingsDialog() {
    final TextEditingController urlController = TextEditingController(text: ApiService.baseUrl);
    String pingResult = '';
    bool isPinging = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.midnightNavy.withValues(alpha: 0.95),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: AppColors.primary.withValues(alpha: 0.3), width: 1.5),
              ),
              title: Row(
                children: const [
                  Icon(Icons.settings_suggest_rounded, color: AppColors.primary),
                  SizedBox(width: 10),
                  Text(
                    'Server Connection',
                    style: TextStyle(color: Colors.white, fontFamily: 'ProductSans', fontSize: 18),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Backend API Server URL',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.deepSpaceBlack.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.electricBlue.withValues(alpha: 0.3)),
                      ),
                      child: TextField(
                        controller: urlController,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: InputBorder.none,
                          hintText: 'http://127.0.0.1:5000/api',
                          hintStyle: TextStyle(color: Colors.white24),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        ActionChip(
                          avatar: const Icon(Icons.cloud_queue_rounded, size: 14, color: AppColors.primary),
                          label: const Text('Cloud Tunnel', style: TextStyle(fontSize: 11, color: Colors.white)),
                          backgroundColor: AppColors.deepSpaceBlack,
                          onPressed: () {
                            setDialogState(() {
                              urlController.text = ApiService.defaultFallbackUrl;
                            });
                          },
                        ),
                        ActionChip(
                          avatar: const Icon(Icons.wifi_rounded, size: 14, color: Colors.cyanAccent),
                          label: const Text('Local Wi-Fi', style: TextStyle(fontSize: 11, color: Colors.white)),
                          backgroundColor: AppColors.deepSpaceBlack,
                          onPressed: () {
                            setDialogState(() {
                              urlController.text = ApiService.defaultLocalUrl;
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.midnightNavy,
                            side: const BorderSide(color: AppColors.primary, width: 1),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          icon: isPinging
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                              : const Icon(Icons.network_check_rounded, size: 16, color: AppColors.primary),
                          label: const Text('Test Connection', style: TextStyle(fontSize: 12, color: Colors.white)),
                          onPressed: isPinging
                              ? null
                              : () async {
                                  setDialogState(() {
                                    isPinging = true;
                                    pingResult = 'Testing connection...';
                                  });
                                  final sw = Stopwatch()..start();
                                  final ok = await ApiService.testEndpoint(urlController.text.trim());
                                  sw.stop();
                                  setDialogState(() {
                                    isPinging = false;
                                    pingResult = ok
                                        ? '✅ Connected! (${sw.elapsedMilliseconds}ms)'
                                        : '❌ Failed to reach server';
                                  });
                                },
                        ),
                      ],
                    ),
                    if (pingResult.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        pingResult,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: pingResult.startsWith('✅') ? Colors.greenAccent : Colors.redAccent,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CANCEL', style: TextStyle(color: AppColors.textMuted)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.deepSpaceBlack,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () {
                    String newUrl = urlController.text.trim();
                    if (newUrl.isNotEmpty) {
                      setState(() {
                        ApiService.baseUrl = newUrl;
                      });
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('API base URL updated to: $newUrl'),
                          backgroundColor: AppColors.electricBlue,
                        ),
                      );
                    }
                  },
                  child: const Text('SAVE', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ----- Build helpers -----

  /// Animated gradient background
  Widget _buildAnimatedBackground() {
    return AnimatedBuilder(
      animation: _bgController,
      builder: (context, _) {
        final t = _bgController.value;
        return Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(sin(t * pi), cos(t * pi)),
              radius: 1.5 + (sin(t * pi) * 0.2),
              colors: [
                AppColors.deepSpaceBlack,
                AppColors.midnightNavy,
                Color.lerp(AppColors.midnightNavy, AppColors.electricBlue.withOpacity(0.2), t)!,
              ],
              stops: const [0.2, 0.6, 1.0],
            ),
          ),
          child: Stack(
            children: [
              // Grid overlay for futuristic feel
              Positioned.fill(
                child: CustomPaint(
                  painter: GridPainter(
                    color: AppColors.electricBlue.withOpacity(0.05),
                    spacing: 40.0,
                    offset: Offset(0, t * 40),
                  ),
                ),
              ),
              // Floating light orbs
              Positioned.fill(
                child: Stack(
                  children: [
                    _buildFloatingCircle(
                      controller: _floatController1,
                      baseX: MediaQuery.of(context).size.width * 0.2,
                      baseY: MediaQuery.of(context).size.height * 0.3,
                      radiusX: 60,
                      radiusY: 40,
                      size: 200,
                      color: AppColors.electricBlue.withOpacity(0.15),
                    ),
                    _buildFloatingCircle(
                      controller: _floatController2,
                      baseX: MediaQuery.of(context).size.width * 0.8,
                      baseY: MediaQuery.of(context).size.height * 0.6,
                      radiusX: 80,
                      radiusY: 100,
                      size: 300,
                      color: AppColors.darkTeal.withOpacity(0.15),
                    ),
                    _buildFloatingCircle(
                      controller: _floatController3,
                      baseX: MediaQuery.of(context).size.width * 0.5,
                      baseY: MediaQuery.of(context).size.height * 0.8,
                      radiusX: 50,
                      radiusY: 70,
                      size: 150,
                      color: AppColors.primary.withOpacity(0.1),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFloatingCircle({
    required AnimationController controller,
    required double baseX,
    required double baseY,
    required double radiusX,
    required double radiusY,
    required double size,
    required Color color,
  }) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final angle = controller.value * 2 * pi;
        final dx = baseX + sin(angle) * radiusX;
        final dy = baseY + cos(angle) * radiusY;
        return Positioned(
          left: dx,
          top: dy,
          child: Transform.translate(
            offset: Offset(sin(angle * 1.3) * 8, cos(angle * 0.7) * 8),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// The glassmorphic card that holds inputs
  Widget _buildGlassCard(bool isLoading) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 32.0),
      decoration: BoxDecoration(
        color: AppColors.midnightNavy.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(28.0),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.deepSpaceBlack.withValues(alpha: 0.6),
            blurRadius: 25,
            spreadRadius: 5,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28.0),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Title
              const Text(
                "ACCESS_PORTAL",
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'ProductSans',
                  letterSpacing: 2.0,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                "ENTER CREDENTIALS TO INITIALIZE SECURE CONNECTION",
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // 1. Username or Email Input
              _buildUsernameInput(),
              const SizedBox(height: 16),

              // 2. Password Input
              _buildPasswordInput(),

              if (_errorMessage.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _errorMessage.toUpperCase(),
                        style: const TextStyle(
                          color: AppColors.secondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (_errorMessage.contains('OFFLINE') ||
                          _errorMessage.contains('SERVER') ||
                          _errorMessage.contains('TIMEOUT') ||
                          _errorMessage.contains('NETWORK')) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          alignment: WrapAlignment.center,
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: AppColors.deepSpaceBlack,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              icon: const Icon(Icons.cloud_sync_rounded, size: 16),
                              label: const Text(
                                'Use Cloud Tunnel',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                              ),
                              onPressed: () {
                                setState(() {
                                  ApiService.baseUrl = ApiService.defaultFallbackUrl;
                                  _errorMessage = '';
                                });
                                ErrorHandler.showSuccess('Switched to Cloud Tunnel!');
                              },
                            ),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: AppColors.primary, width: 1),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              icon: const Icon(Icons.settings_suggest_rounded, size: 16, color: AppColors.primary),
                              label: const Text(
                                'Change URL',
                                style: TextStyle(fontSize: 11),
                              ),
                              onPressed: _showServerSettingsDialog,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 32),

              // CTA Button
              _buildCtaButton(isLoading),

              const SizedBox(height: 18),

              // Server indicator & configuration button
              InkWell(
                onTap: _showServerSettingsDialog,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.deepSpaceBlack.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.greenAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Server: ${ApiService.baseUrl.replaceFirst("https://", "").replaceFirst("http://", "")}',
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(Icons.tune_rounded, size: 14, color: AppColors.primary),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 8),
              const Text(
                'v1.0.6 (Permanent Server)',
                style: TextStyle(color: Colors.white30, fontSize: 10, letterSpacing: 1),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Glassmorphic text input for Username or Email
  Widget _buildUsernameInput() {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.1),
            blurRadius: 20,
            spreadRadius: -5,
          ),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.deepSpaceBlack.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(color: AppColors.electricBlue.withValues(alpha: 0.3), width: 1.0),
        ),
        child: Row(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Icon(Icons.person_rounded, color: AppColors.primary, size: 20),
            ),
            Container(
              width: 1,
              height: 32,
              color: AppColors.borderLight.withValues(alpha: 0.3),
            ),
            Expanded(
              child: TextField(
                controller: _usernameController,
                keyboardType: TextInputType.emailAddress,
                style: const TextStyle(
                  color: AppColors.primaryLight,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8,
                ),
                onChanged: (value) {
                  if (_errorMessage.isNotEmpty) {
                    setState(() {
                      _errorMessage = '';
                    });
                  }
                },
                onSubmitted: (_) => _loginWithCredentials(),
                decoration: InputDecoration(
                  hintText: "Enter Username or Email",
                  hintStyle: TextStyle(
                    color: AppColors.textMuted.withValues(alpha: 0.3),
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.8,
                  ),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Glassmorphic text input for Password
  Widget _buildPasswordInput() {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.1),
            blurRadius: 20,
            spreadRadius: -5,
          ),
        ],
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.deepSpaceBlack.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12.0),
          border: Border.all(color: AppColors.electricBlue.withValues(alpha: 0.3), width: 1.0),
        ),
        child: Row(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Icon(Icons.lock_rounded, color: AppColors.primary, size: 20),
            ),
            Container(
              width: 1,
              height: 32,
              color: AppColors.borderLight.withValues(alpha: 0.3),
            ),
            Expanded(
              child: TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                style: const TextStyle(
                  color: AppColors.primaryLight,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
                onChanged: (value) {
                  if (_errorMessage.isNotEmpty) {
                    setState(() {
                      _errorMessage = '';
                    });
                  }
                },
                onSubmitted: (_) => _loginWithCredentials(),
                decoration: InputDecoration(
                  hintText: "Enter Password",
                  hintStyle: TextStyle(
                    color: AppColors.textMuted.withValues(alpha: 0.3),
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.8,
                  ),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                      color: AppColors.primary.withValues(alpha: 0.6),
                      size: 20,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Call to action button (CONNECT >)
  Widget _buildCtaButton(bool isLoading) {
    return StatefulBuilder(
      builder: (context, setStateLocal) {
        bool isHovered = false;
        return MouseRegion(
          onEnter: (_) => setStateLocal(() => isHovered = true),
          onExit: (_) => setStateLocal(() => isHovered = false),
          child: GestureDetector(
            onTap: isLoading ? null : _loginWithCredentials,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  colors: [
                    isHovered ? AppColors.primaryLight : AppColors.primaryDark,
                    AppColors.electricBlue,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: isHovered ? 0.6 : 0.3),
                    blurRadius: isHovered ? 25 : 15,
                    spreadRadius: isHovered ? 5 : 2,
                  ),
                  BoxShadow(
                    color: AppColors.electricBlue.withValues(alpha: 0.4),
                    blurRadius: isHovered ? 30 : 10,
                    offset: const Offset(0, 8),
                  )
                ],
                border: Border.all(
                  color: AppColors.softWhite.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: Center(
                child: isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: AppColors.deepSpaceBlack,
                          strokeWidth: 3,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Text(
                            "CONNECT",
                            style: TextStyle(
                              color: AppColors.deepSpaceBlack,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2.0,
                            ),
                          ),
                          SizedBox(width: 8),
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            color: AppColors.deepSpaceBlack,
                            size: 16,
                          ),
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Celebration overlay with brand gradient and golden ring
  Widget _buildCelebrationOverlay() {
    return AnimatedBuilder(
      animation: _celebrationController,
      builder: (context, _) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.deepSpaceBlack.withValues(alpha: 0.97),
                AppColors.midnightNavy.withValues(alpha: 0.95),
                AppColors.electricBlue.withValues(alpha: 0.8),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ScaleTransition(
                  scale: _celebrationScale,
                  child: Container(
                    padding: const EdgeInsets.all(36.0),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppColors.electricBlue,
                          AppColors.primary.withValues(alpha: 0.9),
                        ],
                      ),
                      border: Border.all(
                        color: AppColors.secondaryLight,
                        width: 3.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.secondaryLight.withValues(alpha: 0.5),
                          blurRadius: 40,
                          spreadRadius: 8,
                        ),
                        BoxShadow(
                          color: AppColors.secondary.withValues(alpha: 0.3),
                          blurRadius: 60,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.thumb_up,
                      color: AppColors.secondaryLight,
                      size: 72,
                    ),
                  ),
                ),
                const SizedBox(height: 36),
                const Text(
                  "EBI VERIFIED!",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 3.0,
                    fontFamily: 'ProductSans',
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  "Launching secure workspace...",
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.secondaryLight.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ----- Main build -----

  @override
  Widget build(BuildContext context) {
    final isLoading = Provider.of<AppState>(context).isLoading;
    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: AppColors.deepSpaceBlack,
      body: Stack(
        children: [
          // 1. Animated gradient background
          _buildAnimatedBackground(),

          // 2. Floating decorative shapes
          _buildFloatingCircle(
            controller: _floatController1,
            baseX: screenSize.width * 0.7,
            baseY: -60,
            radiusX: 40,
            radiusY: 30,
            size: 220,
            color: AppColors.primary.withValues(alpha: 0.08),
          ),
          _buildFloatingCircle(
            controller: _floatController2,
            baseX: -80,
            baseY: screenSize.height * 0.6,
            radiusX: 30,
            radiusY: 50,
            size: 280,
            color: AppColors.secondary.withValues(alpha: 0.06),
          ),
          _buildFloatingCircle(
            controller: _floatController3,
            baseX: screenSize.width * 0.3,
            baseY: screenSize.height * 0.15,
            radiusX: 25,
            radiusY: 20,
            size: 120,
            color: AppColors.tealGlow.withValues(alpha: 0.07),
          ),

          // 3. Main content
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo with entrance animation
                  AnimatedBuilder(
                    animation: _logoController,
                    builder: (context, child) {
                      return Opacity(
                        opacity: _logoOpacity.value,
                        child: Transform.scale(
                          scale: _logoScale.value,
                          child: Transform.translate(
                            offset: Offset(0, (1 - _logoOpacity.value) * -30),
                            child: child,
                          ),
                        ),
                      );
                    },
                    child: SvgPicture.asset(
                      'assets/images/logo.svg',
                      height: 100,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const AnimatedListItem(
                    index: 0,
                    child: Text(
                      "GEBTALK",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.5,
                        fontFamily: 'Product Sans',
                        fontFamilyFallback: ['ProductSans', 'GoogleSans', 'sans-serif'],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  AnimatedListItem(
                    index: 1,
                    child: Text(
                      "Premium Business Communication Hub",
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Glassmorphic input card
                  AnimatedListItem(
                    index: 2,
                    child: _buildGlassCard(isLoading),
                  ),
                ],
              ),
            ),
          ),

          // 4. Celebration overlay
          if (_isCelebrating) _buildCelebrationOverlay(),

          // 5. Server Connection Settings (Top Right)
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: IconButton(
              icon: const Icon(
                Icons.settings_suggest_rounded,
                color: AppColors.primary,
                size: 28,
              ),
              onPressed: _showServerSettingsDialog,
              tooltip: 'Server Connection Settings',
            ),
          ),

          // 6. EbiBot
          const EbiBot(screen: 'auth'),
        ],
      ),
    );
  }
}

class GridPainter extends CustomPainter {
  final Color color;
  final double spacing;
  final Offset offset;

  GridPainter({required this.color, required this.spacing, required this.offset});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0;

    for (double i = offset.dx % spacing; i < size.width; i += spacing) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = offset.dy % spacing; i < size.height; i += spacing) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant GridPainter oldDelegate) {
    return oldDelegate.offset != offset || oldDelegate.color != color;
  }
}
