import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/colors.dart';

/// Staggered fade+slide animation for list items — enhanced with elastic
/// overshoot and materialization glow flash
class AnimatedListItem extends StatefulWidget {
  final Widget child;
  final int index;
  final Duration delay;
  
  const AnimatedListItem({
    super.key,
    required this.child,
    required this.index,
    this.delay = const Duration(milliseconds: 60),
  });

  @override
  State<AnimatedListItem> createState() => _AnimatedListItemState();
}

class _AnimatedListItemState extends State<AnimatedListItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowFlash;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.08),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _scaleAnimation = Tween<double>(begin: 0.96, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    // Glow flash at the end of materialization
    _glowFlash = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.2), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 0.2, end: 0.0), weight: 60),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    if (widget.index > 8) {
      _controller.value = 1.0;
    } else {
      final safeIndex = widget.index.clamp(0, 6);
      Future.delayed(widget.delay * safeIndex, () {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: Container(
                decoration: BoxDecoration(
                  boxShadow: _glowFlash.value > 0.01
                      ? [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: _glowFlash.value * 0.2),
                            blurRadius: 16,
                            spreadRadius: -4,
                          ),
                        ]
                      : null,
                ),
                child: child,
              ),
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Scale-on-tap wrapper with haptic ripple glow
class TapScaleWidget extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scaleDown;
  final Color rippleColor;

  const TapScaleWidget({
    super.key,
    required this.child,
    this.onTap,
    this.scaleDown = 0.97,
    this.rippleColor = AppColors.primary,
  });

  @override
  State<TapScaleWidget> createState() => _TapScaleWidgetState();
}

class _TapScaleWidgetState extends State<TapScaleWidget>
    with TickerProviderStateMixin {
  late AnimationController _scaleController;
  late AnimationController _rippleController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _rippleAnimation;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: widget.scaleDown).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _rippleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _rippleController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    _rippleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) {
        _scaleController.forward();
        _rippleController.forward(from: 0);
      },
      onTapUp: (_) {
        _scaleController.reverse();
        widget.onTap?.call();
      },
      onTapCancel: () => _scaleController.reverse(),
      child: AnimatedBuilder(
        animation: Listenable.merge([_scaleAnimation, _rippleAnimation]),
        builder: (context, child) {
          final rippleVal = _rippleAnimation.value;
          return Container(
            decoration: BoxDecoration(
              boxShadow: rippleVal > 0.01 && rippleVal < 0.99
                  ? [
                      BoxShadow(
                        color: widget.rippleColor.withValues(
                          alpha: (0.15 * (1.0 - rippleVal)).clamp(0.0, 1.0),
                        ),
                        blurRadius: 20 * rippleVal,
                        spreadRadius: 8 * rippleVal,
                      ),
                    ]
                  : null,
            ),
            child: ScaleTransition(
              scale: _scaleAnimation,
              child: child,
            ),
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// Pulsing dot with double-ring heartbeat effect
class PulsingDot extends StatefulWidget {
  final Color color;
  final double size;

  const PulsingDot({
    super.key,
    required this.color,
    this.size = 8.0,
  });

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final pulse = _controller.value;
        return SizedBox(
          width: widget.size + 16,
          height: widget.size + 16,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer ring pulse
              Container(
                width: widget.size + 6 + (pulse * 8),
                height: widget.size + 6 + (pulse * 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.color.withValues(alpha: (0.3 - pulse * 0.25).clamp(0.0, 1.0)),
                    width: 1,
                  ),
                ),
              ),
              // Inner ring pulse (delayed)
              Container(
                width: widget.size + 2 + (pulse * 4),
                height: widget.size + 2 + (pulse * 4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.color.withValues(alpha: (0.2 - pulse * 0.15).clamp(0.0, 1.0)),
                    width: 0.5,
                  ),
                ),
              ),
              // Core dot
              Container(
                width: widget.size + (pulse * 2),
                height: widget.size + (pulse * 2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color,
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.4 + (pulse * 0.3)),
                      blurRadius: 6 + (pulse * 6),
                      spreadRadius: pulse * 2,
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
}

/// Gradient shimmer loading placeholder — cyberpunk colors
class ShimmerBox extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8.0,
  });

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              colors: const [
                Color(0xFF0A0D14),
                Color(0xFF14082A),
                Color(0xFF0A1520),
                Color(0xFF0A0D14),
              ],
              stops: const [0.0, 0.35, 0.65, 1.0],
              begin: Alignment(-1.0 + (_controller.value * 3.0), 0.0),
              end: Alignment(0.0 + (_controller.value * 3.0), 0.0),
            ),
          ),
        );
      },
    );
  }
}

/// Holographic shimmer overlay — rainbow refraction effect
class HolographicShimmer extends StatefulWidget {
  final Widget child;
  final Duration duration;

  const HolographicShimmer({
    super.key,
    required this.child,
    this.duration = const Duration(seconds: 3),
  });

  @override
  State<HolographicShimmer> createState() => _HolographicShimmerState();
}

class _HolographicShimmerState extends State<HolographicShimmer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0.0),
                AppColors.primary.withValues(alpha: 0.15),
                AppColors.nebulaPurple.withValues(alpha: 0.1),
                AppColors.neonMagenta.withValues(alpha: 0.08),
                Colors.white.withValues(alpha: 0.0),
              ],
              stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
              begin: Alignment(-1.0 + (_controller.value * 3.0), -0.3),
              end: Alignment(0.0 + (_controller.value * 3.0), 0.3),
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: widget.child,
        );
      },
    );
  }
}

/// Energy pulse effect — rhythmic glow around a widget
class EnergyPulse extends StatefulWidget {
  final Widget child;
  final Color color;
  final double maxBlur;

  const EnergyPulse({
    super.key,
    required this.child,
    this.color = AppColors.primary,
    this.maxBlur = 16,
  });

  @override
  State<EnergyPulse> createState() => _EnergyPulseState();
}

class _EnergyPulseState extends State<EnergyPulse>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Container(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.1 + _controller.value * 0.15),
                blurRadius: widget.maxBlur * _controller.value,
                spreadRadius: _controller.value * 2,
              ),
            ],
          ),
          child: widget.child,
        );
      },
    );
  }
}

/// Typewriter text animation — characters appear one by one
class TypewriterText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Duration charDuration;
  final VoidCallback? onComplete;

  const TypewriterText({
    super.key,
    required this.text,
    this.style,
    this.charDuration = const Duration(milliseconds: 40),
    this.onComplete,
  });

  @override
  State<TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<TypewriterText> {
  String _displayedText = '';
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _typeNextChar();
  }

  void _typeNextChar() {
    if (_currentIndex < widget.text.length) {
      Future.delayed(widget.charDuration, () {
        if (mounted) {
          setState(() {
            _currentIndex++;
            _displayedText = widget.text.substring(0, _currentIndex);
          });
          _typeNextChar();
        }
      });
    } else {
      widget.onComplete?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _displayedText,
      style: widget.style,
    );
  }
}

/// Panel header with icon — standardized across all panels
class TitanPanelHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color? iconColor;
  
  const TitanPanelHeader({
    super.key,
    required this.icon,
    required this.title,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: (iconColor ?? AppColors.primary).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconColor ?? AppColors.primary, size: 14),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 12,
            letterSpacing: 1.5,
            fontFamily: 'Product Sans',
          ),
        ),
      ],
    );
  }
}
