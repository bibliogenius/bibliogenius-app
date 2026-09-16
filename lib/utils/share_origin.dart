import 'package:flutter/widgets.dart';

/// Computes a non-zero anchor [Rect], inside the view, for the system share
/// sheet.
///
/// On iPad (and, more strictly, on recent iOS) `share_plus` presents the
/// share sheet as a popover and requires `sharePositionOrigin` to be set,
/// non-zero and within the source view, otherwise it throws
/// `PlatformException(... sharePositionOrigin ... must be non-zero and within
/// coordinate space of source view ...)`.
///
/// The anchor is the render box of [context] clamped to the view bounds: a
/// screen-level context inside a scrolled body reports a rect that starts
/// above the screen and is taller than it, which iOS rejects as-is. When the
/// box is unavailable or scrolled entirely out of view, the fallback is a 1x1
/// rect at the centre of the screen, which is always inside the source view
/// and never zero.
Rect shareOrigin(BuildContext context) {
  final viewSize = MediaQuery.maybeOf(context)?.size ?? const Size(400, 800);
  final viewBounds = Offset.zero & viewSize;
  final renderObject = context.findRenderObject();
  if (renderObject is RenderBox &&
      renderObject.hasSize &&
      renderObject.size.width > 0 &&
      renderObject.size.height > 0) {
    final box = renderObject.localToGlobal(Offset.zero) & renderObject.size;
    final visible = box.intersect(viewBounds);
    if (visible.width > 0 && visible.height > 0) {
      return visible;
    }
  }
  return Rect.fromCenter(center: viewBounds.center, width: 1, height: 1);
}
