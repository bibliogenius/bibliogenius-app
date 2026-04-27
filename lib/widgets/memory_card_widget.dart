import 'dart:math';

import 'package:flutter/material.dart';

import '../models/memory_game.dart';
import 'cached_book_cover.dart';

/// A memory game card with 3D flip animation.
///
/// Shows a book cover (front) or a card back (rear).
/// Animation: Y-axis rotation, 300ms, with perspective.
class MemoryCardWidget extends StatefulWidget {
  final MemoryCard card;
  final VoidCallback onTap;

  const MemoryCardWidget({super.key, required this.card, required this.onTap});

  @override
  State<MemoryCardWidget> createState() => _MemoryCardWidgetState();
}

class _MemoryCardWidgetState extends State<MemoryCardWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  bool _showFront = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _animation = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _showFront = widget.card.isFlipped || widget.card.isMatched;
    if (_showFront) {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(MemoryCardWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final shouldShowFront = widget.card.isFlipped || widget.card.isMatched;

    if (shouldShowFront != _showFront) {
      _showFront = shouldShowFront;
      if (_showFront) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.card.isMatched ? null : widget.onTap,
      child: AnimatedBuilder(
        animation: _animation,
        builder: (context, child) {
          final angle = _animation.value * pi;
          final isFront = angle > pi / 2;

          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001) // perspective
              ..rotateY(angle),
            child: isFront
                ? Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.rotationY(pi),
                    child: _buildFront(context),
                  )
                : _buildBack(context),
          );
        },
      ),
    );
  }

  Widget _buildFront(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: widget.card.isMatched
                ? colorScheme.primary.withValues(alpha: 0.4)
                : Colors.black26,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedBookCover(
              imageUrl: widget.card.coverUrl,
              fit: BoxFit.cover,
              borderRadius: BorderRadius.circular(8),
              errorWidget: Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.book,
                  size: 32,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (widget.card.isMatched)
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Icon(
                    Icons.check_circle,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBack(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colorScheme.primary, colorScheme.secondary],
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Center(
        child: Icon(
          Icons.auto_stories,
          size: 32,
          color: colorScheme.onPrimary.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}
