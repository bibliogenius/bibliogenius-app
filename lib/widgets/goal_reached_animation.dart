import 'dart:math';
import 'package:flutter/material.dart';
import '../services/translation_service.dart';

/// A celebratory fireworks animation when user reaches a reading goal.
/// More festive than Achievement Pop - used for milestone goals.
class GoalReachedAnimation {
  /// Shows the goal reached celebration.
  /// [goalType] - "yearly" or "monthly"
  /// [booksRead] - Number of books read to reach goal
  static void show(
    BuildContext context, {
    required String goalType,
    required int booksRead,
    String? customMessage,
  }) {
    final overlay = Overlay.of(context);

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _GoalReachedWidget(
        goalType: goalType,
        booksRead: booksRead,
        customMessage: customMessage,
        onComplete: () => entry.remove(),
      ),
    );

    overlay.insert(entry);
  }
}

class _GoalReachedWidget extends StatefulWidget {
  final String goalType;
  final int booksRead;
  final String? customMessage;
  final VoidCallback onComplete;

  const _GoalReachedWidget({
    required this.goalType,
    required this.booksRead,
    this.customMessage,
    required this.onComplete,
  });

  @override
  State<_GoalReachedWidget> createState() => _GoalReachedWidgetState();
}

class _GoalReachedWidgetState extends State<_GoalReachedWidget>
    with TickerProviderStateMixin {
  late AnimationController _mainController;
  late AnimationController _fireworksController;

  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _trophyBounceAnimation;

  final List<_Firework> _fireworks = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();

    _mainController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    );

    _fireworksController = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    );

    // Fade in/out
    _fadeAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.0,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 10,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 75),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.0,
          end: 0.0,
        ).chain(CurveTween(curve: Curves.easeIn)),
        weight: 15,
      ),
    ]).animate(_mainController);

    // Scale
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.5,
          end: 1.15,
        ).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.15, end: 1.0),
        weight: 10,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 50),
    ]).animate(_mainController);

    // Trophy bounce
    _trophyBounceAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween<double>(0), weight: 20),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0,
          end: -15,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: -15,
          end: 0,
        ).chain(CurveTween(curve: Curves.bounceOut)),
        weight: 30,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(0), weight: 30),
    ]).animate(_mainController);

    // Generate fireworks
    _generateFireworks();

    // Completion is observed through the status, not the `forward()` future:
    // Flutter cancels that future (it never resolves) when tap-to-dismiss
    // calls `animateTo`, and the overlay would then never be removed.
    _mainController.addStatusListener(_onStatus);
    _mainController.forward();
    _fireworksController.forward();
  }

  void _generateFireworks() {
    final colors = [
      Colors.red,
      Colors.orange,
      Colors.yellow,
      Colors.green,
      Colors.blue,
      Colors.purple,
      Colors.pink,
    ];

    // Create multiple firework bursts
    for (int i = 0; i < 6; i++) {
      final x = 0.2 + _random.nextDouble() * 0.6; // Center 60% of screen
      final y = 0.2 + _random.nextDouble() * 0.4; // Top 40% of screen
      final color = colors[_random.nextInt(colors.length)];
      final delay = _random.nextDouble() * 0.4;

      // Each firework has multiple particles
      for (int j = 0; j < 12; j++) {
        final angle = (j / 12) * 2 * pi;
        _fireworks.add(
          _Firework(
            startX: x,
            startY: y,
            angle: angle,
            distance: _random.nextDouble() * 80 + 40,
            color: color,
            delay: delay,
            size: _random.nextDouble() * 6 + 3,
          ),
        );
      }
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _fireworksController.stop();
    widget.onComplete();
  }

  @override
  void dispose() {
    _mainController.removeStatusListener(_onStatus);
    _mainController.dispose();
    _fireworksController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;

    return ListenableBuilder(
      listenable: Listenable.merge([_mainController, _fireworksController]),
      builder: (context, _) {
        return Stack(
          children: [
            // Semi-transparent backdrop
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: Colors.black.withValues(
                    alpha: 0.5 * _fadeAnimation.value,
                  ),
                ),
              ),
            ),

            // Fireworks particles
            ..._buildFireworks(screenSize),

            // Main content
            Center(
              child: IgnorePointer(
                child: Opacity(
                  opacity: _fadeAnimation.value,
                  child: Transform.scale(
                    scale: _scaleAnimation.value,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Trophy icon with bounce
                        Transform.translate(
                          offset: Offset(0, _trophyBounceAnimation.value),
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.orange.withValues(alpha: 0.6),
                                  blurRadius: 30,
                                  spreadRadius: 10,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.emoji_events,
                              size: 70,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 30),

                        // "Goal Reached!" text
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.green.shade600,
                                Colors.green.shade400,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.green.withValues(alpha: 0.5),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Text(
                            widget.customMessage ?? '🎯 Goal Reached!',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Details
                        Builder(
                          builder: (context) {
                            final periodText = widget.goalType == "yearly"
                                ? TranslationService.translate(
                                    context,
                                    'goal_books_this_year',
                                  )
                                : TranslationService.translate(
                                    context,
                                    'goal_books_this_month',
                                  );
                            return Text(
                              '${widget.booksRead} $periodText',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                              ),
                            );
                          },
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
                    duration: const Duration(milliseconds: 200),
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

  List<Widget> _buildFireworks(Size screenSize) {
    final mainProgress =
        _mainController.value.clamp(0.0, 0.6) / 0.6; // First 60%
    final fireworkProgress = _fireworksController.value;

    return _fireworks.map((firework) {
      final adjustedProgress = ((fireworkProgress + firework.delay) % 1.0);
      final distance = firework.distance * adjustedProgress;
      final x =
          firework.startX + cos(firework.angle) * distance / screenSize.width;
      final y =
          firework.startY + sin(firework.angle) * distance / screenSize.height;
      final opacity = mainProgress * (1.0 - adjustedProgress);

      return Positioned(
        left: x * screenSize.width,
        top: y * screenSize.height,
        child: IgnorePointer(
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Container(
              width: firework.size,
              height: firework.size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: firework.color,
                boxShadow: [
                  BoxShadow(
                    color: firework.color.withValues(alpha: 0.6),
                    blurRadius: 8,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }).toList();
  }
}

class _Firework {
  final double startX;
  final double startY;
  final double angle;
  final double distance;
  final Color color;
  final double delay;
  final double size;

  _Firework({
    required this.startX,
    required this.startY,
    required this.angle,
    required this.distance,
    required this.color,
    required this.delay,
    required this.size,
  });
}
