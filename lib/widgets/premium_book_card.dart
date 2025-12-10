import '../models/book.dart';
import '../services/translation_service.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class PremiumBookCard extends StatefulWidget {
  final Book book;
  final double width;
  final double height;
  final bool isHero;

  const PremiumBookCard({
    super.key,
    required this.book,
    this.width = 160,
    this.height = 240,
    this.isHero = false,
  });

  @override
  State<PremiumBookCard> createState() => _PremiumBookCardState();
}

class _PremiumBookCardState extends State<PremiumBookCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isHovering = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
        duration: const Duration(milliseconds: 200), vsync: this);
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.05).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isHero) {
      return _buildHeroCard(context);
    }
    return _buildStandardCard(context);
  }

  Color _generateRandomColor(String seed) {
    final hash = seed.hashCode;
    final colors = [
      Colors.blue.shade800,
      Colors.red.shade800,
      Colors.green.shade800,
      Colors.purple.shade800,
      Colors.orange.shade800,
      Colors.teal.shade800,
      Colors.indigo.shade800,
      Colors.brown.shade800,
    ];
    return colors[hash.abs() % colors.length];
  }

  Widget _buildFallbackCover(BuildContext context) {
    final color = _generateRandomColor(widget.book.title + (widget.book.id?.toString() ?? ''));
    
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: color,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color,
            color.withValues(alpha: 0.6),
          ],
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            widget.book.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14, // Adjusted for smaller standard cards
              shadows: [Shadow(color: Colors.black26, offset: Offset(0, 1), blurRadius: 2)],
            ),
          ),
          if (widget.book.author != null) ...[
            const SizedBox(height: 4),
            Text(
              widget.book.author!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Icon(Icons.auto_stories, color: Colors.white.withValues(alpha: 0.2), size: 24),
        ],
      ),
    );
  }

  Widget _buildHeroCard(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/books/${widget.book.id}', extra: widget.book),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovering = true),
        onExit: (_) => setState(() => _isHovering = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          height: 300,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _isHovering ? 0.3 : 0.2),
                blurRadius: _isHovering ? 30 : 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                // Background Image (Blurred)
                Positioned.fill(
                  child: widget.book.coverUrl != null
                      ? Image.network(
                          widget.book.coverUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              _buildFallbackCover(context),
                        )
                      : _buildFallbackCover(context),
                ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.8),
                        ],
                        stops: const [0.5, 1.0],
                      ),
                    ),
                  ),
                ),
                // Content
                Positioned(
                  bottom: 24,
                  left: 24,
                  right: 24,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('CONTINUE READING',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        widget.book.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            Shadow(
                                color: Colors.black54,
                                offset: Offset(0, 2),
                                blurRadius: 4)
                          ],
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.book.author != null)
                        Text(
                          widget.book.author!,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 16),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStandardCard(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/books/${widget.book.id}', extra: widget.book),
      child: MouseRegion(
        onEnter: (_) {
          _controller.forward();
          setState(() => _isHovering = true);
        },
        onExit: (_) {
          _controller.reverse();
          setState(() => _isHovering = false);
        },
        child: AnimatedBuilder(
          animation: _scaleAnimation,
          builder: (context, child) => Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              width: widget.width,
              margin: const EdgeInsets.only(right: 16, bottom: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: _isHovering ? 0.25 : 0.15),
                    blurRadius: _isHovering ? 15 : 10,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    // Cover Image
                    SizedBox(
                      height: widget.height,
                      width: widget.width,
                      child: widget.book.coverUrl != null
                          ? Image.network(
                              widget.book.coverUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _buildFallbackCover(context),
                            )
                          : _buildFallbackCover(context),
                    ),
                    // Gradient Overlay on Hover
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: _isHovering ? 1.0 : 0.0,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.8),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Status Badge
                    if (widget.book.readingStatus != null)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            widget.book.readingStatus!
                                .replaceAll('_', ' ')
                                .toUpperCase(),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
