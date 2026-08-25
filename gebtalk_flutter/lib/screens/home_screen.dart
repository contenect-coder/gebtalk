import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_state.dart';
import '../services/webrtc_service.dart';
import '../theme/colors.dart';
import '../widgets/call_overlay.dart';
import 'chat_list_screen.dart';
import 'calls_screen.dart';
import 'email_inbox_screen.dart';
import 'contacts_screen.dart';
import 'profile_screen.dart';
import '../services/api_service.dart';
import 'app_lock_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int _currentIndex = 0;
  late AnimationController _navGlowController;
  late AnimationController _shockwaveController;
  late AnimationController _sparkController;

  @override
  void initState() {
    super.initState();
    ApiService.logDebug('HomeScreen: initState started');
    
    _navGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);

    _shockwaveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _sparkController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    
    // Pre-fetch initial data to load contacts, lists, profile, emails, requests
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final appState = Provider.of<AppState>(context, listen: false);
      appState.ensureInitialDataLoaded();
      appState.fetchEmails(silent: true);
      appState.fetchContactRequests();
      appState.addListener(_onAppStateChanged);
      _onAppStateChanged();
    });
  }

  void _onAppStateChanged() {
    if (!mounted) return;
    final appState = Provider.of<AppState>(context, listen: false);
    final webrtcService = Provider.of<WebRtcService>(context, listen: false);
    if (appState.currentProfile != null && webrtcService.currentUserId != appState.currentProfile!.id) {
      webrtcService.initialize(appState.currentProfile!.id);
    }
  }

  @override
  void dispose() {
    _navGlowController.dispose();
    _shockwaveController.dispose();
    _sparkController.dispose();
    try {
      final appState = Provider.of<AppState>(context, listen: false);
      appState.removeListener(_onAppStateChanged);
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    final tabs = [
      {'icon': Icons.chat_bubble_rounded, 'label': 'Chats'},
      {'icon': Icons.people_alt_rounded, 'label': 'Contacts'},
      {'icon': Icons.person_rounded, 'label': 'Me'},
    ];

    final pages = [
      ChatListScreen(onTabChanged: (index) => _switchTab(index)),
      const ContactsScreen(),
      ProfileScreen(onTabChanged: (index) => _switchTab(index)),
    ];

    if (_currentIndex >= pages.length) {
      _currentIndex = 0;
    }

    ApiService.logDebug('HomeScreen: build started, pagesCount=${pages.length}');

    if (appState.isAppLocked) {
      return const AppLockScreen();
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          // Active page with premium transition
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: CurvedAnimation(
                  parent: animation,
                  curve: const Interval(0.0, 0.8, curve: Curves.easeOut),
                ),
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.97, end: 1.0).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  ),
                  child: child,
                ),
              );
            },
            child: SizedBox.expand(
              key: ValueKey(_currentIndex),
              child: pages[_currentIndex],
            ),
          ),

          // Floating Holographic Command Strip
          Positioned(
            bottom: 20,
            left: 16,
            right: 16,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 650),
                child: _buildHolographicNavBar(tabs),
              ),
            ),
          ),

          // WebRTC call overlay
          const CallOverlay(),
        ],
      ),
    );
  }

  void _switchTab(int index) {
    if (index == _currentIndex) return;
    setState(() {
      _currentIndex = index;
    });
    _shockwaveController.forward(from: 0);
  }

  Widget _buildHolographicNavBar(List<Map<String, dynamic>> tabs) {
    return AnimatedBuilder(
      animation: Listenable.merge([_navGlowController, _shockwaveController, _sparkController]),
      builder: (context, child) {
        final glowVal = _navGlowController.value;
        final shockVal = _shockwaveController.value;
        return Container(
          height: 80,
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.08 + glowVal * 0.08),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.7),
                blurRadius: 35,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.04 + glowVal * 0.03),
                blurRadius: 25,
                spreadRadius: -4,
              ),
              BoxShadow(
                color: AppColors.nebulaPurple.withValues(alpha: 0.02 + glowVal * 0.02),
                blurRadius: 40,
                spreadRadius: -8,
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Stack(
                children: [
                  // Shockwave ripple on tab switch
                  if (shockVal > 0 && shockVal < 1.0)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _NavShockwavePainter(
                            progress: shockVal,
                            tabCount: tabs.length,
                            activeIndex: _currentIndex,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ),
                  child!,
                ],
              ),
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Column(
          children: [
            // XP progress bar at top of nav
            _buildXPBar(),
            Expanded(
              child: Row(
                children: List.generate(tabs.length, (index) {
                  final isSelected = _currentIndex == index;
                  final tab = tabs[index];

                  return Expanded(
                    child: GestureDetector(
                      onTap: () => _switchTab(index),
                      behavior: HitTestBehavior.opaque,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primary.withValues(alpha: 0.10)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          border: isSelected
                              ? Border.all(color: AppColors.primary.withValues(alpha: 0.20), width: 1)
                              : Border.all(color: Colors.transparent, width: 1),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Stack(
                              clipBehavior: Clip.none,
                              children: [
                                _buildNavIconWithBadge(tab['label'] as String, tab['icon'] as IconData, isSelected),
                                // Active energy indicator + spark emitter
                                if (isSelected)
                                  Positioned(
                                    bottom: -2,
                                    left: 0,
                                    right: 0,
                                    child: Center(
                                      child: AnimatedBuilder(
                                        animation: _sparkController,
                                        builder: (context, _) {
                                          return Container(
                                            width: 14 + sin(_sparkController.value * 2 * pi) * 2,
                                            height: 2.5,
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [
                                                  AppColors.primary.withValues(alpha: 0.0),
                                                  AppColors.primary,
                                                  AppColors.primaryLight,
                                                  AppColors.primary,
                                                  AppColors.primary.withValues(alpha: 0.0),
                                                ],
                                              ),
                                              borderRadius: BorderRadius.circular(1.5),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: AppColors.primary.withValues(alpha: 0.7 + sin(_sparkController.value * 2 * pi) * 0.2),
                                                  blurRadius: 8 + sin(_sparkController.value * 2 * pi) * 4,
                                                  spreadRadius: 1 + sin(_sparkController.value * 2 * pi),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                tab['label'] as String,
                                style: TextStyle(
                                  color: isSelected ? AppColors.primary : AppColors.textLight,
                                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                                  fontSize: 9.5,
                                  letterSpacing: 0.2,
                                  fontFamily: 'Product Sans',
                                ),
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// XP progress bar along the top of the nav bar
  Widget _buildXPBar() {
    return AnimatedBuilder(
      animation: _sparkController,
      builder: (context, _) {
        final shimmer = sin(_sparkController.value * 2 * pi) * 0.5 + 0.5;
        return Container(
          height: 2,
          margin: const EdgeInsets.only(top: 4, left: 8, right: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(1),
            color: AppColors.surface.withValues(alpha: 0.6),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: 0.72, // 72% XP progress (can be made dynamic)
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(1),
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: 0.6),
                    AppColors.neonIce.withValues(alpha: 0.4 + shimmer * 0.2),
                    AppColors.primary.withValues(alpha: 0.6),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3 + shimmer * 0.15),
                    blurRadius: 4,
                    spreadRadius: 0,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNavIcon(IconData icon, bool isSelected) {
    return Icon(
      icon,
      color: isSelected ? AppColors.primary : AppColors.textMuted,
      size: 22,
      shadows: isSelected ? [
        Shadow(
          color: AppColors.primary.withValues(alpha: 0.5),
          blurRadius: 10,
        ),
      ] : null,
    );
  }

  Widget _buildNavIconWithBadge(String label, IconData icon, bool isSelected) {
    final appState = Provider.of<AppState>(context);
    int badgeCount = 0;
    Color badgeColor = AppColors.secondary;

    if (label == 'Chats' || label == 'Chat') {
      badgeCount = appState.contacts.fold(0, (sum, c) => sum + c.unreadCount);
    } else if (label == 'Contacts') {
      badgeCount = appState.contactRequests.length;
      badgeColor = const Color(0xFF7C3AED);
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        _buildNavIcon(icon, isSelected),
        if (badgeCount > 0)
          Positioned(
            top: -4,
            right: -8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: badgeColor,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: badgeColor.withValues(alpha: 0.5),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
              constraints: const BoxConstraints(
                minWidth: 16,
                minHeight: 14,
              ),
              child: Center(
                child: Text(
                  badgeCount > 99 ? '99+' : '$badgeCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Shockwave ripple painter for tab switch
class _NavShockwavePainter extends CustomPainter {
  final double progress;
  final int tabCount;
  final int activeIndex;
  final Color color;

  _NavShockwavePainter({
    required this.progress,
    required this.tabCount,
    required this.activeIndex,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final tabWidth = size.width / tabCount;
    final centerX = tabWidth * activeIndex + tabWidth / 2;
    final centerY = size.height / 2;

    final radius = size.width * Curves.easeOutCubic.transform(progress);
    final alpha = ((1.0 - progress) * 0.12).clamp(0.0, 1.0);

    canvas.drawCircle(
      Offset(centerX, centerY),
      radius,
      Paint()
        ..color = color.withValues(alpha: alpha)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Secondary inner ring
    if (progress < 0.7) {
      canvas.drawCircle(
        Offset(centerX, centerY),
        radius * 0.5,
        Paint()
          ..color = color.withValues(alpha: alpha * 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
