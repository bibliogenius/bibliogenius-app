import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../models/book.dart';
import '../models/book_sequence.dart';
import 'book_details_screen.dart';

typedef BookPageBuilder =
    Widget Function(BuildContext context, Book book, BookStepper stepper);

/// A horizontal drag shorter than this never steps, however fast.
const double _minSwipeDistance = 48;

/// A drag at least this fast steps once past [_minSwipeDistance].
const double _minSwipeVelocity = 300;

/// The book page of a list, with stepping to the previous or next book of
/// that list: the page's own buttons, the arrow keys and a horizontal swipe.
///
/// One route for the whole browse, the page swapped in place: replacing the
/// route instead would drop the future the list awaits, and with it the
/// "changed" result that makes the list refresh when the reader comes back.
class BookBrowserScreen extends StatefulWidget {
  final BookSequence sequence;

  /// Builds the page of one book; the real book page by default.
  final BookPageBuilder? pageBuilder;

  const BookBrowserScreen({
    super.key,
    required this.sequence,
    this.pageBuilder,
  });

  @override
  State<BookBrowserScreen> createState() => _BookBrowserScreenState();
}

class _BookBrowserScreenState extends State<BookBrowserScreen> {
  late BookSequence _sequence = widget.sequence;
  final _focusNode = FocusNode(debugLabel: 'BookBrowser');

  /// Whether any book of this browse was changed so far.
  bool _changed = false;

  /// +1 when the last step went to the next book, -1 to the previous one:
  /// the side the new page slides in from.
  int _direction = 1;

  /// Counts the steps: each page gets its own key, so that stepping back to
  /// the book still sliding out mounts a new page instead of two pages
  /// sharing one key.
  int _stepCount = 0;

  double _dragDistance = 0;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _step(int delta) {
    final target = delta < 0 ? _sequence.previous : _sequence.next;
    if (target == null) return;
    setState(() {
      _direction = delta.sign;
      _sequence = _sequence.step(delta);
      _stepCount++;
    });
    // Whatever had focus belonged to the page that is leaving; the arrows
    // must keep reaching this screen.
    _focusNode.requestFocus();
    // The whole page changed under a screen reader without its focus moving.
    SemanticsService.sendAnnouncement(
      View.of(context),
      target.title,
      Directionality.of(context),
    );
  }

  bool get _isRtl => Directionality.of(context) == TextDirection.rtl;

  /// Arrow keys follow the reading direction: the "previous" arrow points
  /// back along the line.
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_isEditingText()) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.arrowLeft &&
        key != LogicalKeyboardKey.arrowRight) {
      return KeyEventResult.ignored;
    }
    // The repeat of a held key is swallowed, not followed: each step mounts
    // a full book page and its queries.
    if (event is KeyRepeatEvent) return KeyEventResult.handled;
    final towardsLineStart = key == LogicalKeyboardKey.arrowLeft;
    final delta = towardsLineStart != _isRtl ? -1 : 1;
    // At an end of the list the arrow is not ours: it goes on to focus
    // traversal or scrolling.
    if ((delta < 0 ? _sequence.previous : _sequence.next) == null) {
      return KeyEventResult.ignored;
    }
    _step(delta);
    return KeyEventResult.handled;
  }

  /// A text field moves its caret with the arrows: they are not ours then.
  /// Its focus node sits under its EditableText, so look upwards.
  bool _isEditingText() {
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused == null) return false;
    return focused.widget is EditableText ||
        focused.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  void _onDragStart(DragStartDetails details) => _dragDistance = 0;

  void _onDragUpdate(DragUpdateDetails details) =>
      _dragDistance += details.primaryDelta ?? 0;

  void _onDragEnd(DragEndDetails details) {
    final distance = _dragDistance;
    _dragDistance = 0;
    final width = context.size?.width ?? 0;
    final velocity = details.primaryVelocity ?? 0;
    if (distance.abs() < _minSwipeDistance) return;
    final fastEnough =
        velocity.abs() >= _minSwipeVelocity && velocity.sign == distance.sign;
    if (!fastEnough && distance.abs() < width / 3) return;
    // Swiping towards the line start pulls in what comes after.
    final towardsLineStart = _isRtl ? distance > 0 : distance < 0;
    _step(towardsLineStart ? 1 : -1);
  }

  BookStepper _stepper() {
    return BookStepper(
      previous: _sequence.previous,
      next: _sequence.next,
      onPrevious: _sequence.previous == null ? null : () => _step(-1),
      onNext: _sequence.next == null ? null : () => _step(1),
      carriedChanges: _changed,
      onChanged: () => _changed = true,
    );
  }

  Widget _buildPage(BuildContext context, Book book) {
    final stepper = _stepper();
    final builder = widget.pageBuilder;
    if (builder != null) return builder(context, book, stepper);
    return BookDetailsScreen(bookId: book.id!, book: book, stepper: stepper);
  }

  @override
  Widget build(BuildContext context) {
    final book = _sequence.current;
    final currentKey = ValueKey(_stepCount);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 250);
    final slideSign = _isRtl ? -_direction : _direction;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: RawGestureDetector(
        gestures: {
          HorizontalDragGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<
                HorizontalDragGestureRecognizer
              >(
                HorizontalDragGestureRecognizer.new,
                (recognizer) => recognizer
                  ..onStart = _onDragStart
                  ..onUpdate = _onDragUpdate
                  ..onEnd = _onDragEnd,
              ),
        },
        child: ClipRect(
          child: AnimatedSwitcher(
            duration: duration,
            transitionBuilder: (child, animation) {
              final incoming = child.key == currentKey;
              final offset =
                  Tween<Offset>(
                    begin: Offset(
                      incoming ? slideSign * 1.0 : -slideSign * 1.0,
                      0,
                    ),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    ),
                  );
              // The leaving page is only a picture on its way out. The same
              // widgets whichever way, switched by flags: a change of widget
              // type would mount the leaving page afresh, queries and all.
              final leaving = !incoming;
              return BookPageActivity(
                active: incoming,
                child: IgnorePointer(
                  ignoring: leaving,
                  child: ExcludeFocus(
                    excluding: leaving,
                    child: ExcludeSemantics(
                      excluding: leaving,
                      child: HeroMode(
                        enabled: incoming,
                        child: SlideTransition(position: offset, child: child),
                      ),
                    ),
                  ),
                ),
              );
            },
            child: KeyedSubtree(
              key: currentKey,
              child: Builder(builder: (context) => _buildPage(context, book)),
            ),
          ),
        ),
      ),
    );
  }
}
