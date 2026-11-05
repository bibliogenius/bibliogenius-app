import 'dart:async';

import 'package:flutter/material.dart';

import 'shelf_thumbnail.dart';

/// Carries a shelf's fan from the card that was tapped to the head of its page.
///
/// Drawn by hand above everything: the pages of the shelves replace each other
/// inside one route, so there is no route transition for a [Hero] to fly on.
/// Only the fan travels; it takes no touch, so the page answers all the while.
class ShelfFanFlight {
  static const Duration duration = Duration(milliseconds: 250);

  /// How long a fan waits for the head to appear before it gives up: the books
  /// and the shelves of a page opened from nowhere can take their time.
  static const Duration _patience = Duration(milliseconds: 400);

  _Flight? _flight;

  /// Lifts the fan of the shelf [name] from [from], where it holds until the
  /// head of the page calls [land]. Nothing with animations off.
  void takeOff(
    BuildContext context, {
    required String name,
    required Rect from,
    required ShelfThumbnailSize size,
    required bool hasBooks,
    required List<String> coverPaths,
  }) {
    cancel();
    if (MediaQuery.disableAnimationsOf(context)) return;
    final flight = _Flight(name);
    final entry = OverlayEntry(
      builder: (_) => _FlyingFan(
        flight: flight,
        from: from,
        fan: ShelfThumbnail(
          size: size,
          hasBooks: hasBooks,
          coverPaths: coverPaths,
        ),
        onDone: () {
          if (identical(_flight, flight)) cancel();
        },
      ),
    );
    flight
      ..entry = entry
      ..patience = Timer(_patience, () {
        if (identical(_flight, flight)) cancel();
      });
    _flight = flight;
    Overlay.of(context, rootOverlay: true).insert(entry);
  }

  /// The head of the page of [name] stands at [to]. Returns the end of the
  /// flight to wait for before showing its own fan, or null when no fan is
  /// coming.
  Future<void>? land(String name, Rect to) {
    final flight = _flight;
    if (flight == null || flight.name != name) return null;
    flight.patience?.cancel();
    flight.to.value = to;
    return flight.done.future;
  }

  /// Ends any flight at once.
  void cancel() {
    final flight = _flight;
    if (flight == null) return;
    _flight = null;
    flight.end();
  }
}

class _Flight {
  final String name;
  final ValueNotifier<Rect?> to = ValueNotifier<Rect?>(null);
  final Completer<void> done = Completer<void>();
  OverlayEntry? entry;
  Timer? patience;

  _Flight(this.name);

  void end() {
    patience?.cancel();
    entry?.remove();
    entry?.dispose();
    entry = null;
    if (!done.isCompleted) done.complete();
  }
}

class _FlyingFan extends StatefulWidget {
  final _Flight flight;
  final Rect from;
  final Widget fan;
  final VoidCallback onDone;

  const _FlyingFan({
    required this.flight,
    required this.from,
    required this.fan,
    required this.onDone,
  });

  @override
  State<_FlyingFan> createState() => _FlyingFanState();
}

class _FlyingFanState extends State<_FlyingFan>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: ShelfFanFlight.duration,
  )..addStatusListener(_onStatus);

  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  @override
  void initState() {
    super.initState();
    widget.flight.to.addListener(_onTarget);
  }

  void _onTarget() {
    if (widget.flight.to.value != null) _controller.forward();
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) widget.onDone();
  }

  @override
  void dispose() {
    widget.flight.to.removeListener(_onTarget);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final to = widget.flight.to.value ?? widget.from;
        return Positioned.fromRect(
          key: const Key('shelfFanFlight'),
          rect: Rect.lerp(widget.from, to, _curve.value)!,
          child: child!,
        );
      },
      child: IgnorePointer(
        child: ExcludeSemantics(child: FittedBox(child: widget.fan)),
      ),
    );
  }
}
