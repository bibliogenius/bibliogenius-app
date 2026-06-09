import 'package:flutter/material.dart';

/// A Mario Bros-style "+1" animation overlay that floats up and fades out.
/// Use [PlusOneAnimation.show] to display it anywhere on the screen.
class PlusOneAnimation {
  /// Shows the +1 animation at the given position (or screen center if not specified).
  /// The animation floats up and fades out like a Mario Bros coin.
  static void show(
    BuildContext context, {
    Offset? position,
    String text = '+1',
  }) {
    final overlay = Overlay.of(context);
    final screenSize = MediaQuery.of(context).size;

    // Default to center of screen if no position specified
    final animationPosition =
        position ?? Offset(screenSize.width / 2, screenSize.height / 2);

    late OverlayEntry entry;
    entry = OverlayEntry(
      // Transparent Material so text doesn't get Flutter's fallback yellow
      // underline (overlay has no Material ancestor otherwise).
      builder: (context) => Material(
        type: MaterialType.transparency,
        child: _PlusOneAnimationWidget(
          position: animationPosition,
          text: text,
          onComplete: () => entry.remove(),
        ),
      ),
    );

    overlay.insert(entry);
  }
}

class _PlusOneAnimationWidget extends StatefulWidget {
  final Offset position;
  final String text;
  final VoidCallback onComplete;

  const _PlusOneAnimationWidget({
    required this.position,
    required this.text,
    required this.onComplete,
  });

  @override
  State<_PlusOneAnimationWidget> createState() =>
      _PlusOneAnimationWidgetState();
}

class _PlusOneAnimationWidgetState extends State<_PlusOneAnimationWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _moveAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    // Fade in quickly, then fade out
    _fadeAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.0,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 20,
      ),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 1.0), weight: 40),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.0,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 40,
      ),
    ]).animate(_controller);

    // Float upward with deceleration (like Mario coins)
    _moveAnimation = Tween<double>(
      begin: 0,
      end: -80,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutQuad));

    // Quick pop-in scale effect
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.5,
          end: 1.3,
        ).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.3,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 20,
      ),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 0.8), weight: 50),
    ]).animate(_controller);

    _controller.forward().then((_) => widget.onComplete());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        return Stack(
          children: [
            Positioned(
              left: widget.position.dx - 30, // Center the text
              top: widget.position.dy + _moveAnimation.value - 20,
              child: IgnorePointer(
                child: Opacity(
                  opacity: _fadeAnimation.value,
                  child: Transform.scale(
                    scale: _scaleAnimation.value,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.orange.withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        widget.text,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              color: Colors.black54,
                              offset: Offset(1, 1),
                              blurRadius: 2,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
