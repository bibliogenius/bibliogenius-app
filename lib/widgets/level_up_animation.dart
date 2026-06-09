import 'dart:math';
import 'package:flutter/material.dart';

import '../services/translation_service.dart';

/// A celebratory overlay shown when the user reaches a new level on a
/// gamification track. The visual language mirrors the profile screen: a
/// circular progress ring filling around the track icon, with a corner level
/// medallion and the tier name below.
///
/// Use [LevelUpAnimation.show] (or [showInOverlay] to fire it after navigating
/// away from the originating screen).
class LevelUpAnimation {
  /// Shows the level up animation.
  /// [newLevel] - The new level reached (drives the corner medallion number)
  /// [trackName] - Translated track name (e.g. "Collectionneur")
  /// [trackColor] - Accent colour, ideally the tier colour reached
  /// [trackIcon] - The track's icon, shown at the centre of the ring
  /// [levelLabel] - Tier name (e.g. "Or"); falls back to "Niveau N"
  static void show(
    BuildContext context, {
    required int newLevel,
    required String trackName,
    required Color trackColor,
    IconData? trackIcon,
    String? levelLabel,
  }) {
    showInOverlay(
      Overlay.of(context, rootOverlay: true),
      newLevel: newLevel,
      trackName: trackName,
      trackColor: trackColor,
      trackIcon: trackIcon,
      levelLabel: levelLabel,
    );
  }

  /// Same as [show] but targets an explicit [overlay]. Lets a caller capture the
  /// root overlay before an `await` and fire the animation even after navigating
  /// away from the screen that triggered it.
  static void showInOverlay(
    OverlayState overlay, {
    required int newLevel,
    required String trackName,
    required Color trackColor,
    IconData? trackIcon,
    String? levelLabel,
  }) {
    late OverlayEntry entry;
    entry = OverlayEntry(
      // Transparent Material so text doesn't get Flutter's fallback yellow
      // underline (overlay has no Material ancestor otherwise).
      builder: (context) => Material(
        type: MaterialType.transparency,
        child: _LevelUpAnimationWidget(
          newLevel: newLevel,
          trackName: trackName,
          trackColor: trackColor,
          trackIcon: trackIcon ?? Icons.arrow_upward,
          levelLabel: levelLabel,
          onComplete: () => entry.remove(),
        ),
      ),
    );

    overlay.insert(entry);
  }
}

class _LevelUpAnimationWidget extends StatefulWidget {
  final int newLevel;
  final String trackName;
  final Color trackColor;
  final IconData trackIcon;
  final String? levelLabel;
  final VoidCallback onComplete;

  const _LevelUpAnimationWidget({
    required this.newLevel,
    required this.trackName,
    required this.trackColor,
    required this.trackIcon,
    this.levelLabel,
    required this.onComplete,
  });

  @override
  State<_LevelUpAnimationWidget> createState() =>
      _LevelUpAnimationWidgetState();
}

class _LevelUpAnimationWidgetState extends State<_LevelUpAnimationWidget>
    with TickerProviderStateMixin {
  late final AnimationController _main;
  late final AnimationController _glow;

  late final Animation<double> _backdrop;
  late final Animation<double> _scale;
  late final Animation<double> _ring;
  late final Animation<double> _medallion;
  late final Animation<double> _textOpacity;
  late final Animation<double> _textSlide;

  final List<_Particle> _particles = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();

    _main = AnimationController(
      duration: const Duration(milliseconds: 4200),
      vsync: this,
    );
    _glow = AnimationController(
      duration: const Duration(milliseconds: 1100),
      vsync: this,
    )..repeat(reverse: true);

    Animation<double> interval(double begin, double end, Curve curve) =>
        CurvedAnimation(
          parent: _main,
          curve: Interval(begin, end, curve: curve),
        );

    // Backdrop fades in fast, holds for a comfortable beat, fades out at the end.
    _backdrop = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0).chain(
          CurveTween(curve: Curves.easeOut),
        ),
        weight: 7,
      ),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 80),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0).chain(
          CurveTween(curve: Curves.easeIn),
        ),
        weight: 13,
      ),
    ]).animate(_main);

    // Entrance is kept snappy (finishes by ~45% of the timeline); the rest is
    // hold time so the celebration lingers before fading out.
    _scale = Tween(begin: 0.6, end: 1.0).animate(
      interval(0.0, 0.30, Curves.elasticOut),
    );
    _ring = Tween(begin: 0.0, end: 1.0).animate(
      interval(0.12, 0.42, Curves.easeOutCubic),
    );
    _medallion = Tween(begin: 0.0, end: 1.0).animate(
      interval(0.34, 0.50, Curves.elasticOut),
    );
    _textOpacity = interval(0.28, 0.46, Curves.easeOut);
    _textSlide = Tween(begin: 14.0, end: 0.0).animate(
      interval(0.28, 0.48, Curves.easeOutCubic),
    );

    _generateParticles();

    _main.forward().then((_) {
      _glow.stop();
      widget.onComplete();
    });
  }

  void _generateParticles() {
    for (int i = 0; i < 22; i++) {
      _particles.add(
        _Particle(
          x: _random.nextDouble(),
          startY: 1.05 + _random.nextDouble() * 0.15,
          speed: _random.nextDouble() * 0.35 + 0.25,
          size: _random.nextDouble() * 5 + 3,
          delay: _random.nextDouble() * 0.4,
        ),
      );
    }
  }

  @override
  void dispose() {
    _main.dispose();
    _glow.dispose();
    super.dispose();
  }

  void _dismiss() {
    // Jump to where the fade-out begins so a tap closes it promptly.
    if (_main.value < 0.87) {
      _main.animateTo(0.87, duration: const Duration(milliseconds: 200));
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.trackColor;
    final size = MediaQuery.of(context).size;

    return ListenableBuilder(
      listenable: Listenable.merge([_main, _glow]),
      builder: (context, _) {
        final ringProgress = _ring.value.clamp(0.0, 1.0);
        return Stack(
          children: [
            // Dim backdrop
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.62 * _backdrop.value),
                ),
              ),
            ),

            // Rising tier-coloured particles
            ..._buildParticles(size, color),

            // Centre content
            Center(
              child: IgnorePointer(
                child: Opacity(
                  opacity: _backdrop.value,
                  child: Transform.scale(
                    scale: _scale.value,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _eyebrow(context, color),
                        const SizedBox(height: 20),
                        _ringWithIcon(color, ringProgress),
                        const SizedBox(height: 22),
                        Opacity(
                          opacity: _textOpacity.value,
                          child: Transform.translate(
                            offset: Offset(0, _textSlide.value),
                            child: _labels(context, color),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Tap anywhere to dismiss early
            Positioned.fill(
              child: GestureDetector(
                onTap: _dismiss,
                behavior: HitTestBehavior.translucent,
              ),
            ),
          ],
        );
      },
    );
  }

  /// Small uppercase label above the ring (e.g. "LEVEL UP").
  Widget _eyebrow(BuildContext context, Color color) {
    return Opacity(
      opacity: _textOpacity.value,
      child: Text(
        TranslationService.translate(context, 'level_up').toUpperCase(),
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.92),
          fontSize: 14,
          fontWeight: FontWeight.w700,
          letterSpacing: 4,
          shadows: [
            Shadow(color: color.withValues(alpha: 0.6), blurRadius: 12),
          ],
        ),
      ),
    );
  }

  /// The circular progress ring around the track icon, with a corner medallion
  /// carrying the new level number. Mirrors the profile's TrackProgressWidget.
  Widget _ringWithIcon(Color color, double progress) {
    const ringSize = 156.0;
    final glow = 0.35 + 0.45 * _glow.value;

    return SizedBox(
      width: ringSize,
      height: ringSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Soft outer glow
          Container(
            width: ringSize * 0.78,
            height: ringSize * 0.78,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: glow),
                  blurRadius: 42,
                  spreadRadius: 6,
                ),
              ],
            ),
          ),
          // Background track ring
          SizedBox(
            width: ringSize,
            height: ringSize,
            child: CircularProgressIndicator(
              value: 1.0,
              strokeWidth: 9,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation(
                Colors.white.withValues(alpha: 0.16),
              ),
            ),
          ),
          // Animated progress ring
          SizedBox(
            width: ringSize,
            height: ringSize,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 9,
              strokeCap: StrokeCap.round,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          // Centre icon disc
          Container(
            width: ringSize * 0.6,
            height: ringSize * 0.6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  color.withValues(alpha: 0.30),
                  color.withValues(alpha: 0.12),
                ],
              ),
            ),
            child: Icon(
              widget.trackIcon,
              color: Colors.white,
              size: ringSize * 0.30,
            ),
          ),
          // Level medallion (top-right), echoing the profile's level badge
          Positioned(
            top: 2,
            right: 2,
            child: Transform.scale(
              scale: _medallion.value.clamp(0.0, 1.2),
              child: Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.6),
                      blurRadius: 12,
                    ),
                  ],
                ),
                child: Text(
                  widget.newLevel.toString(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Track name and tier label below the ring.
  Widget _labels(BuildContext context, Color color) {
    final tier = widget.levelLabel ??
        '${TranslationService.translate(context, 'level')} ${widget.newLevel}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.trackName,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.85),
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          tier,
          style: TextStyle(
            color: Colors.white,
            fontSize: 32,
            fontWeight: FontWeight.w900,
            shadows: [
              Shadow(color: color.withValues(alpha: 0.8), blurRadius: 18),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildParticles(Size screen, Color color) {
    final t = _main.value;
    return _particles.map((p) {
      final progress = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      final y = p.startY - progress * p.speed * 1.6;
      final opacity = (1.0 - progress).clamp(0.0, 1.0) * _backdrop.value;
      return Positioned(
        left: p.x * screen.width,
        top: y * screen.height,
        child: IgnorePointer(
          child: Opacity(
            opacity: opacity,
            child: Container(
              width: p.size,
              height: p.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.9),
                boxShadow: [
                  BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6),
                ],
              ),
            ),
          ),
        ),
      );
    }).toList();
  }
}

class _Particle {
  final double x;
  final double startY;
  final double speed;
  final double size;
  final double delay;

  _Particle({
    required this.x,
    required this.startY,
    required this.speed,
    required this.size,
    required this.delay,
  });
}
