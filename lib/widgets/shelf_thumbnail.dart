import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'cached_book_cover.dart';

/// The sizes of a shelf thumbnail: [xs] for the path of a shelf's page, [s] for
/// sub-shelves and the trees, [l] for the cards of the shelves tab, [xl] for
/// the head of a shelf's page.
enum ShelfThumbnailSize { xs, s, l, xl }

/// Where the three covers of a fan sit in its frame.
class _Fan {
  final Size frame;
  final Size cover;

  /// Top-left corner of each cover, before its rotation.
  final Offset centre;
  final Offset left;
  final Offset right;

  /// How far the side covers lean.
  final double degrees;

  /// Width of the highlight along the spine of a cover.
  final double spine;

  const _Fan({
    required this.frame,
    required this.cover,
    required this.centre,
    required this.left,
    required this.right,
    required this.degrees,
    required this.spine,
  });

  static const Map<ShelfThumbnailSize, _Fan> bySize = {
    ShelfThumbnailSize.xs: _Fan(
      frame: Size(34, 24),
      cover: Size(12, 17),
      centre: Offset(11, 2),
      left: Offset(4, 3),
      right: Offset(17, 3),
      degrees: 9,
      spine: 1,
    ),
    ShelfThumbnailSize.s: _Fan(
      frame: Size(48, 34),
      cover: Size(18, 25),
      centre: Offset(15, 3),
      left: Offset(6, 5),
      right: Offset(24, 5),
      degrees: 9,
      spine: 1,
    ),
    ShelfThumbnailSize.l: _Fan(
      frame: Size(92, 66),
      cover: Size(34, 52),
      centre: Offset(29, 6),
      left: Offset(12, 9),
      right: Offset(46, 9),
      degrees: 10,
      spine: 2,
    ),
    ShelfThumbnailSize.xl: _Fan(
      frame: Size(112, 80),
      cover: Size(40, 60),
      centre: Offset(36, 7),
      left: Offset(15, 11),
      right: Offset(56, 11),
      degrees: 10,
      spine: 2,
    ),
  };

  double get _radians => degrees * math.pi / 180;

  /// The slots in paint order, each with the index of the cover it holds in
  /// a newest-first list: the newest ends up in the centre and in front.
  List<({int cover, Offset at, double angle})> get slots => [
    (cover: 1, at: left, angle: -_radians),
    (cover: 2, at: right, angle: _radians),
    (cover: 0, at: centre, angle: 0),
  ];
}

const BorderRadius _coverRadius = BorderRadius.only(
  topLeft: Radius.circular(2),
  bottomLeft: Radius.circular(2),
  topRight: Radius.circular(4),
  bottomRight: Radius.circular(4),
);

/// The picture of a shelf: up to three of its covers in a fan, laid straight
/// on whatever is behind it, with only their shadow to lift them.
///
/// A shelf with nothing to show gets the same fan in outline, never an icon.
/// Decorative: the row or card around it already says the name and the count,
/// so nothing here reaches assistive technology.
class ShelfThumbnail extends StatelessWidget {
  final ShelfThumbnailSize size;

  /// Newest first, as the core lists them. Past three are ignored.
  final List<String> coverPaths;

  /// Whether the shelf or one of its sub-shelves holds a book, by the count
  /// printed next to it.
  final bool hasBooks;

  const ShelfThumbnail({
    super.key,
    required this.size,
    required this.hasBooks,
    this.coverPaths = const [],
  });

  @override
  Widget build(BuildContext context) {
    final fan = _Fan.bySize[size]!;
    // The covers come from the core's subtree, the count from the tree
    // shown: a shelf counted empty here shows no book either.
    final showCovers = hasBooks && coverPaths.isNotEmpty;
    return ExcludeSemantics(
      child: SizedBox.fromSize(
        size: fan.frame,
        child: showCovers
            ? _buildCovers(fan)
            : CustomPaint(
                key: const Key('shelfThumbnailGhost'),
                size: fan.frame,
                // Not the scheme's outline: the themes set it to their hairline
                // border colour, which the empty fan would vanish in.
                painter: _GhostFanPainter(
                  fan,
                  Theme.of(context).colorScheme.onSurface.withValues(
                    alpha: 0.38,
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildCovers(_Fan fan) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        for (final slot in fan.slots)
          if (slot.cover < coverPaths.length)
            Positioned(
              left: slot.at.dx,
              top: slot.at.dy,
              child: Transform.rotate(
                angle: slot.angle,
                child: _FanCover(path: coverPaths[slot.cover], fan: fan),
              ),
            ),
      ],
    );
  }
}

/// One cover of a fan, and its shadow.
///
/// The shadow comes only with the image: under a slot still loading, or one
/// that failed, it would draw a dark book.
class _FanCover extends StatefulWidget {
  final String path;
  final _Fan fan;

  const _FanCover({required this.path, required this.fan});

  @override
  State<_FanCover> createState() => _FanCoverState();
}

class _FanCoverState extends State<_FanCover> {
  /// The empty slots on screen: the loading one and the failed one can both
  /// be there during the cross-fade between them.
  int _emptySlots = 0;

  /// Off for the first frame: only after it do we know whether the cover
  /// went straight to its image.
  bool _settled = false;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _settled = true);
    });
  }

  void _rebuildAfterFrame() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  void _slotShown() {
    _emptySlots++;
    _rebuildAfterFrame();
  }

  void _slotGone() {
    _emptySlots--;
    _rebuildAfterFrame();
  }

  @override
  Widget build(BuildContext context) {
    final fan = widget.fan;
    final empty = _EmptySlot(
      size: fan.cover,
      onShown: _slotShown,
      onGone: _slotGone,
    );
    final cover = CachedBookCover(
      imageUrl: widget.path,
      width: fan.cover.width,
      height: fan.cover.height,
      borderRadius: _coverRadius,
      placeholder: empty,
      placeholderWhileDecoding: true,
      errorWidget: empty,
      semanticLabel: null,
    );
    final lifted = _settled && _emptySlots == 0;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // The same two boxes whether lifted or not: taking them away would mount
    // the cover anew, and load it again, at the moment it appears.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: _coverRadius,
        boxShadow: lifted
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? 0.6 : 0.28),
                  offset: const Offset(0, 2),
                  blurRadius: dark ? 5 : 4,
                ),
              ]
            : null,
      ),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: _coverRadius,
          gradient: lifted ? _spineHighlight(fan) : null,
        ),
        child: cover,
      ),
    );
  }

  /// The light catching the spine of the book: a hard edge, not a fade.
  Gradient _spineHighlight(_Fan fan) {
    final edge = fan.spine / fan.cover.width;
    final light = Colors.white.withValues(alpha: 0.22);
    return LinearGradient(
      colors: [light, light, Colors.transparent, Colors.transparent],
      stops: [0, edge, edge, 1],
    );
  }
}

/// Nothing to see in the place of a cover, and a word to its owner about it.
class _EmptySlot extends StatefulWidget {
  final Size size;
  final VoidCallback onShown;
  final VoidCallback onGone;

  const _EmptySlot({
    required this.size,
    required this.onShown,
    required this.onGone,
  });

  @override
  State<_EmptySlot> createState() => _EmptySlotState();
}

class _EmptySlotState extends State<_EmptySlot> {
  @override
  void initState() {
    super.initState();
    widget.onShown();
  }

  @override
  void dispose() {
    widget.onGone();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.fromSize(size: widget.size);
}

/// Three book outlines in a fan, with no fill: the front ones hide what is
/// behind them by cutting it out, so the ground shows through whatever it is.
class _GhostFanPainter extends CustomPainter {
  final _Fan fan;
  final Color color;

  const _GhostFanPainter(this.fan, this.color);

  static const double _stroke = 1.5;

  Path _outline(Offset at, double angle) {
    final rect = at & fan.cover;
    final centre = rect.center;
    final matrix = Matrix4.identity()
      ..translateByDouble(centre.dx, centre.dy, 0, 1)
      ..rotateZ(angle)
      ..translateByDouble(-centre.dx, -centre.dy, 0, 1);
    final shape = Path()
      ..addRRect(
        _coverRadius.toRRect(rect.deflate(_stroke / 2)),
      );
    return shape.transform(matrix.storage);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..color = color;
    final slots = fan.slots;
    final outlines = [for (final s in slots) _outline(s.at, s.angle)];
    // Beyond the frame too: a leaning outline passes its edge.
    final everywhere = Path()
      ..addRect((Offset.zero & size).inflate(fan.cover.height));
    for (var i = 0; i < outlines.length; i++) {
      canvas.save();
      for (final front in outlines.skip(i + 1)) {
        canvas.clipPath(
          Path.combine(PathOperation.difference, everywhere, front),
        );
      }
      canvas.drawPath(outlines[i], paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_GhostFanPainter oldDelegate) =>
      oldDelegate.color != color || !identical(oldDelegate.fan, fan);
}
