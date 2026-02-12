import 'package:flutter/material.dart';
import '../theme/app_design.dart';

/// A pulsing shimmer placeholder that mimics content shape during loading.
/// Reusable across the app for any loading state that benefits from
/// skeleton-style placeholders instead of plain spinners.
class ShimmerLoading extends StatefulWidget {
  final Widget child;

  const ShimmerLoading({super.key, required this.child});

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _animation,
      builder: (context, child) {
        return Opacity(
          opacity: 0.3 + (_animation.value * 0.5),
          child: widget.child,
        );
      },
    );
  }
}

/// A single shimmer "bone" — a rounded rectangle placeholder.
class ShimmerBone extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerBone({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.12);
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// Skeleton card matching the shape of SearchResultCard (160px, cover + text).
class SearchResultSkeleton extends StatelessWidget {
  const SearchResultSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ShimmerLoading(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        height: 160,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
          boxShadow: AppDesign.subtleShadow,
        ),
        child: Row(
          children: [
            // Cover placeholder
            Container(
              width: 110,
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.08),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppDesign.radiusLarge),
                  bottomLeft: Radius.circular(AppDesign.radiusLarge),
                ),
              ),
              child: Center(
                child: Icon(
                  Icons.auto_stories,
                  size: 32,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.15),
                ),
              ),
            ),
            // Text placeholders
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const ShimmerBone(width: 180, height: 16),
                    const SizedBox(height: 8),
                    const ShimmerBone(width: 120, height: 12),
                    const SizedBox(height: 12),
                    const ShimmerBone(width: 90, height: 10),
                    const SizedBox(height: 6),
                    const ShimmerBone(width: 70, height: 10),
                    const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ShimmerBone(
                          width: 36,
                          height: 36,
                          borderRadius: 18,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A list of skeleton cards for search loading state.
class SearchLoadingSkeleton extends StatelessWidget {
  final int count;

  const SearchLoadingSkeleton({super.key, this.count = 4});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 20),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: count,
      itemBuilder: (context, index) => const SearchResultSkeleton(),
    );
  }
}
