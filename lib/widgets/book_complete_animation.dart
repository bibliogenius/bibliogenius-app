import 'dart:math';
import 'package:flutter/material.dart';

/// A celebration animation when a user finishes reading a book.
/// Shows a closing book with stars and XP points animation.
/// Use [BookCompleteCelebration.show] to display it.
class BookCompleteCelebration {
  /// Shows the book complete celebration.
  /// [bookTitle] - Title of the completed book
  /// [xpEarned] - Optional XP points earned (shown as +50 XP style)
  static void show(
    BuildContext context, {
    required String bookTitle,
    int xpEarned = 1,
    String? subtitle,
  }) {
    final overlay = Overlay.of(context);

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _BookCompleteCelebrationWidget(
        bookTitle: bookTitle,
        xpEarned: xpEarned,
        subtitle: subtitle,
        onComplete: () => entry.remove(),
      ),
    );

    overlay.insert(entry);
  }
}

class _BookCompleteCelebrationWidget extends StatefulWidget {
  final String bookTitle;
  final int xpEarned;
  final String? subtitle;
  final VoidCallback onComplete;

  const _BookCompleteCelebrationWidget({
    required this.bookTitle,
    required this.xpEarned,
    this.subtitle,
    required this.onComplete,
  });

  @override
  State<_BookCompleteCelebrationWidget> createState() =>
      _BookCompleteCelebrationWidgetState();
}

class _BookCompleteCelebrationWidgetState
    extends State<_BookCompleteCelebrationWidget>
    with TickerProviderStateMixin {
  late AnimationController _mainController;
  late AnimationController _starsController;

  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _bookCloseAnimation;
  late Animation<double> _xpAnimation;
  late Animation<double> _xpSlideAnimation;

  final List<_Star> _stars = [];
  final Random _random = Random();

  @override
  void initState() {
    super.initState();

    _mainController = AnimationController(
      duration: const Duration(milliseconds: 2800),
      vsync: this,
    );

    _starsController = AnimationController(
      duration: const Duration(milliseconds: 2000),
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

    // Scale animation
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.8,
          end: 1.1,
        ).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 30,
      ),
      TweenSequenceItem(tween: Tween<double>(begin: 1.1, end: 1.0), weight: 15),
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 55),
    ]).animate(_mainController);

    // Book closing animation (3D perspective effect)
    _bookCloseAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 0.0,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 30,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 70),
    ]).animate(_mainController);

    // XP counter animation
    _xpAnimation = Tween<double>(begin: 0, end: widget.xpEarned.toDouble())
        .animate(
          CurvedAnimation(
            parent: _mainController,
            curve: const Interval(0.3, 0.7, curve: Curves.easeOut),
          ),
        );

    // XP text slide up
    _xpSlideAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween<double>(0), weight: 25),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 30,
          end: 0,
        ).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 30,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(0), weight: 45),
    ]).animate(_mainController);

    // Generate stars
    _generateStars();

    // Completion is observed through the status, not the `forward()` future:
    // Flutter cancels that future (it never resolves) when tap-to-dismiss
    // calls `animateTo`, and the overlay would then never be removed.
    _mainController.addStatusListener(_onStatus);
    _mainController.forward();
    _starsController.repeat();
  }

  void _generateStars() {
    for (int i = 0; i < 12; i++) {
      final angle = (i / 12) * 2 * pi;
      _stars.add(
        _Star(
          angle: angle,
          distance: _random.nextDouble() * 40 + 80,
          size: _random.nextDouble() * 12 + 8,
          delay: _random.nextDouble() * 0.3,
          rotationSpeed: (_random.nextDouble() - 0.5) * 2,
        ),
      );
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) widget.onComplete();
  }

  @override
  void dispose() {
    _mainController.removeStatusListener(_onStatus);
    _mainController.dispose();
    _starsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_mainController, _starsController]),
      builder: (context, _) {
        return Stack(
          children: [
            // Semi-transparent backdrop
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: Colors.black.withValues(
                    alpha: 0.6 * _fadeAnimation.value,
                  ),
                ),
              ),
            ),

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
                        // Stars around the book
                        SizedBox(
                          width: 250,
                          height: 250,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Animated stars
                              ..._buildStars(),

                              // Book icon with closing effect
                              _buildBook(),
                            ],
                          ),
                        ),

                        const SizedBox(height: 20),

                        // "Book Complete!" text
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
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
                                blurRadius: 15,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: Text(
                            widget.subtitle ?? '📖 Book Complete!',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ),

                        const SizedBox(height: 16),

                        // Book title
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40),
                          child: Text(
                            widget.bookTitle,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // XP earned with animation
                        Transform.translate(
                          offset: Offset(0, _xpSlideAnimation.value),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                              ),
                              borderRadius: BorderRadius.circular(25),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.orange.withValues(alpha: 0.5),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.star,
                                  color: Colors.white,
                                  size: 24,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '+${_xpAnimation.value.round()} XP',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    shadows: [
                                      Shadow(
                                        color: Colors.black26,
                                        offset: Offset(1, 1),
                                        blurRadius: 2,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
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

  Widget _buildBook() {
    final closeProgress = _bookCloseAnimation.value;

    return Container(
      width: 100,
      height: 130,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withValues(alpha: 0.4),
            blurRadius: 20 + closeProgress * 20,
            spreadRadius: closeProgress * 10,
          ),
        ],
      ),
      child: Stack(
        children: [
          // Book back cover
          Container(
            width: 100,
            height: 130,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.green.shade700, Colors.green.shade500],
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.shade800, width: 2),
            ),
          ),
          // Book front cover (animated closing)
          Transform(
            alignment: Alignment.centerLeft,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(-closeProgress * pi * 0.4),
            child: Container(
              width: 100,
              height: 130,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.green.shade600, Colors.green.shade400],
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade700, width: 2),
              ),
              child: Center(
                child: Icon(
                  closeProgress > 0.5 ? Icons.check_circle : Icons.menu_book,
                  color: Colors.white,
                  size: 50,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildStars() {
    final time = _starsController.value;
    final mainProgress =
        _mainController.value.clamp(0.0, 0.5) *
        2; // First half of main animation

    return _stars.map((star) {
      final adjustedTime = (time + star.delay) % 1.0;
      final twinkle = (sin(adjustedTime * 2 * pi) + 1) / 2;
      final distance = star.distance * mainProgress;
      final x = cos(star.angle) * distance;
      final y = sin(star.angle) * distance;
      final rotation = star.rotationSpeed * time * 2 * pi;

      return Positioned(
        left: 125 + x - star.size / 2,
        top: 125 + y - star.size / 2,
        child: Opacity(
          opacity: mainProgress * (0.5 + twinkle * 0.5),
          child: Transform.rotate(
            angle: rotation,
            child: Icon(
              Icons.star,
              size: star.size,
              color: Colors.amber.withValues(alpha: 0.8 + twinkle * 0.2),
            ),
          ),
        ),
      );
    }).toList();
  }
}

class _Star {
  final double angle;
  final double distance;
  final double size;
  final double delay;
  final double rotationSpeed;

  _Star({
    required this.angle,
    required this.distance,
    required this.size,
    required this.delay,
    required this.rotationSpeed,
  });
}
