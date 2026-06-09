import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// A full-screen celebration overlay with confetti when a user unlocks a new badge.
/// Use [BadgeUnlockAnimation.show] to display it.
class BadgeUnlockAnimation {
  /// Shows the badge unlock celebration with confetti.
  /// [badgeName] - The translated name of the badge
  /// [badgeAssetPath] - Path to the badge SVG asset
  /// [badgeColor] - Primary color of the badge
  static void show(
    BuildContext context, {
    required String badgeName,
    required String badgeAssetPath,
    required Color badgeColor,
    String? subtitle,
  }) {
    showInOverlay(
      Overlay.of(context, rootOverlay: true),
      badgeName: badgeName,
      badgeAssetPath: badgeAssetPath,
      badgeColor: badgeColor,
      subtitle: subtitle,
    );
  }

  /// Same as [show] but targets an explicit [overlay]. Lets a caller capture the
  /// root overlay before an `await` and fire the animation even after navigating
  /// away from the screen that triggered it.
  static void showInOverlay(
    OverlayState overlay, {
    required String badgeName,
    required String badgeAssetPath,
    required Color badgeColor,
    String? subtitle,
  }) {
    late OverlayEntry entry;
    entry = OverlayEntry(
      // Transparent Material so text doesn't get Flutter's fallback yellow
      // underline (overlay has no Material ancestor otherwise).
      builder: (context) => Material(
        type: MaterialType.transparency,
        child: _BadgeUnlockAnimationWidget(
          badgeName: badgeName,
          badgeAssetPath: badgeAssetPath,
          badgeColor: badgeColor,
          subtitle: subtitle,
          onComplete: () => entry.remove(),
        ),
      ),
    );

    overlay.insert(entry);
  }
}

class _BadgeUnlockAnimationWidget extends StatefulWidget {
  final String badgeName;
  final String badgeAssetPath;
  final Color badgeColor;
  final String? subtitle;
  final VoidCallback onComplete;

  const _BadgeUnlockAnimationWidget({
    required this.badgeName,
    required this.badgeAssetPath,
    required this.badgeColor,
    this.subtitle,
    required this.onComplete,
  });

  @override
  State<_BadgeUnlockAnimationWidget> createState() =>
      _BadgeUnlockAnimationWidgetState();
}

class _BadgeUnlockAnimationWidgetState
    extends State<_BadgeUnlockAnimationWidget>
    with TickerProviderStateMixin {
  late AnimationController _mainController;
  late AnimationController _confettiController;
  late AnimationController _pulseController;

  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _glowAnimation;

  final List<_ConfettiParticle> _confetti = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();

    // Main animation controller (badge reveal)
    _mainController = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    );

    // Confetti controller
    _confettiController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    );

    // Pulse controller for glow effect
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);

    // Fade in overlay
    _fadeAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.0,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 15,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 70),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.0,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 15,
      ),
    ]).animate(_mainController);

    // Badge scale - bouncy entrance
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.0,
          end: 1.2,
        ).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.2,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 20,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 40),
    ]).animate(_mainController);

    // Glow effect
    _glowAnimation = Tween<double>(
      begin: 0.3,
      end: 0.8,
    ).animate(_pulseController);

    // Generate confetti particles
    _generateConfetti();

    // Start animations
    _mainController.forward().then((_) {
      // Stop all repeating animations before removing overlay
      _pulseController.stop();
      _confettiController.stop();
      widget.onComplete();
    });
    _confettiController.forward();
  }

  void _generateConfetti() {
    final colors = [
      widget.badgeColor,
      widget.badgeColor.withValues(alpha: 0.7),
      Colors.amber,
      Colors.white,
      Colors.orange,
    ];

    for (int i = 0; i < 50; i++) {
      _confetti.add(
        _ConfettiParticle(
          x: _random.nextDouble(),
          y: _random.nextDouble() * 0.3 - 0.3, // Start above screen
          velocityX: (_random.nextDouble() - 0.5) * 0.3,
          velocityY: _random.nextDouble() * 0.5 + 0.3,
          rotation: _random.nextDouble() * 2 * pi,
          rotationSpeed: (_random.nextDouble() - 0.5) * 0.2,
          size: _random.nextDouble() * 10 + 5,
          color: colors[_random.nextInt(colors.length)],
          shape: _random.nextBool()
              ? _ConfettiShape.rectangle
              : _ConfettiShape.circle,
        ),
      );
    }
  }

  @override
  void dispose() {
    _mainController.dispose();
    _confettiController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _mainController,
        _confettiController,
        _pulseController,
      ]),
      builder: (context, _) {
        return Stack(
          children: [
            // Dark overlay
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: Colors.black.withValues(
                    alpha: 0.7 * _fadeAnimation.value,
                  ),
                ),
              ),
            ),

            // Confetti
            ..._buildConfetti(),

            // Badge and text
            Center(
              child: IgnorePointer(
                child: Opacity(
                  opacity: _fadeAnimation.value,
                  child: Transform.scale(
                    scale: _scaleAnimation.value,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Glow effect behind badge
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: widget.badgeColor.withValues(
                                  alpha: _glowAnimation.value,
                                ),
                                blurRadius: 60,
                                spreadRadius: 20,
                              ),
                            ],
                          ),
                          child: SvgPicture.asset(
                            widget.badgeAssetPath,
                            width: 150,
                            height: 150,
                            placeholderBuilder: (_) => Icon(
                              Icons.emoji_events,
                              size: 150,
                              color: widget.badgeColor,
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        // "New Badge Unlocked!" text
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                widget.badgeColor,
                                widget.badgeColor.withValues(alpha: 0.8),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: [
                              BoxShadow(
                                color: widget.badgeColor.withValues(alpha: 0.4),
                                blurRadius: 15,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Text(
                            widget.subtitle ?? 'New Badge Unlocked!',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Badge name
                        Text(
                          widget.badgeName,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                            shadows: [
                              Shadow(color: widget.badgeColor, blurRadius: 20),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Tap to dismiss
            Positioned.fill(
              child: GestureDetector(
                onTap: () {
                  _mainController.animateTo(
                    1.0,
                    duration: const Duration(milliseconds: 300),
                  );
                },
                behavior: HitTestBehavior.translucent,
              ),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _buildConfetti() {
    final screenSize = MediaQuery.of(context).size;
    final progress = _confettiController.value;

    return _confetti.map((particle) {
      final x = particle.x + particle.velocityX * progress;
      final y = particle.y + particle.velocityY * progress * 2;
      final rotation =
          particle.rotation + particle.rotationSpeed * progress * 10;
      final opacity = (1.0 - progress).clamp(0.0, 1.0);

      return Positioned(
        left: x * screenSize.width,
        top: y * screenSize.height,
        child: IgnorePointer(
          child: Opacity(
            opacity: opacity * _fadeAnimation.value,
            child: Transform.rotate(
              angle: rotation,
              child: particle.shape == _ConfettiShape.circle
                  ? Container(
                      width: particle.size,
                      height: particle.size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: particle.color,
                      ),
                    )
                  : Container(
                      width: particle.size,
                      height: particle.size * 0.6,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: particle.color,
                      ),
                    ),
            ),
          ),
        ),
      );
    }).toList();
  }
}

// Workaround for AnimatedBuilder which doesn't exist - use ListenableBuilder pattern
class AnimatedBuilder extends StatelessWidget {
  final Listenable animation;
  final Widget Function(BuildContext, Widget?) builder;

  const AnimatedBuilder({
    super.key,
    required this.animation,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(listenable: animation, builder: builder);
  }
}

class _ConfettiParticle {
  final double x;
  final double y;
  final double velocityX;
  final double velocityY;
  final double rotation;
  final double rotationSpeed;
  final double size;
  final Color color;
  final _ConfettiShape shape;

  _ConfettiParticle({
    required this.x,
    required this.y,
    required this.velocityX,
    required this.velocityY,
    required this.rotation,
    required this.rotationSpeed,
    required this.size,
    required this.color,
    required this.shape,
  });
}

enum _ConfettiShape { rectangle, circle }
