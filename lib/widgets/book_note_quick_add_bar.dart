import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../providers/book_note_provider.dart' show maxNoteContentLength;
import '../services/translation_service.dart';
import 'speech_note_button.dart';

/// Lines the note field grows to before it scrolls, so a long note never
/// pushes the notes list off screen.
const _maxVisibleLines = 5;

const _fieldPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 10);
const _pagePadding = EdgeInsets.symmetric(horizontal: 4, vertical: 10);
const _pageFieldWidth = 64.0;
const _fieldGap = 8.0;

/// Page field, multi-line note field, optional dictation and send button,
/// shared by the book page and the notes screen.
///
/// On a computer, Enter sends and Shift+Enter starts a new line (the
/// messaging-app convention). On a phone the keyboard key starts a new line
/// and the send button sends: the field cannot tell a short note from the
/// first line of a long one. A blank note is never sent.
class BookNoteQuickAddBar extends StatefulWidget {
  final TextEditingController contentController;
  final TextEditingController pageController;
  final bool dictationEnabled;
  final VoidCallback onSubmit;

  const BookNoteQuickAddBar({
    super.key,
    required this.contentController,
    required this.pageController,
    required this.dictationEnabled,
    required this.onSubmit,
  });

  @override
  State<BookNoteQuickAddBar> createState() => _BookNoteQuickAddBarState();
}

class _BookNoteQuickAddBarState extends State<BookNoteQuickAddBar> {
  late final FocusNode _contentFocus = FocusNode(onKeyEvent: _onContentKey);

  @override
  void dispose() {
    _contentFocus.dispose();
    super.dispose();
  }

  static bool get _enterSends => switch (defaultTargetPlatform) {
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux => true,
    _ => false,
  };

  void _submit() {
    if (widget.contentController.text.trim().isEmpty) return;
    widget.onSubmit();
  }

  KeyEventResult _onContentKey(FocusNode node, KeyEvent event) {
    if (!_enterSends || event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.enter &&
        key != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    // An input method (Japanese, Chinese...) uses Enter to confirm the
    // word being composed: that Enter must not send.
    if (widget.contentController.value.composing.isValid) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isShiftPressed ||
        keyboard.isAltPressed ||
        keyboard.isControlPressed ||
        keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) _submit();
    // Key repeats are swallowed too, so holding Enter does not fill the
    // field with new lines.
    return KeyEventResult.handled;
  }

  OutlineInputBorder _border(ThemeData theme) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: BorderSide(color: theme.colorScheme.outline.withAlpha(60)),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = TranslationService.translate;
    final faded = theme.colorScheme.onSurface.withAlpha(100);
    final newlineHint = _enterSends ? t(context, 'note_newline_hint') : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          // Page field and buttons stay level with the last line as the
          // note field grows.
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              width: _pageFieldWidth,
              child: TextField(
                controller: widget.pageController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
                decoration: InputDecoration(
                  hintText: 'p.',
                  isDense: true,
                  prefixIcon: Icon(
                    Icons.bookmark_outline,
                    size: 16,
                    color: faded,
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 24,
                    minHeight: 0,
                  ),
                  contentPadding: _pagePadding,
                  border: _border(theme),
                  enabledBorder: _border(theme),
                ),
              ),
            ),
            const SizedBox(width: _fieldGap),
            Expanded(
              // The new-line hint is read with the field, where a screen
              // reader user needs it, rather than as a stray text after it.
              child: Semantics(
                hint: newlineHint,
                child: TextField(
                  controller: widget.contentController,
                  focusNode: _contentFocus,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.newline,
                  minLines: 1,
                  maxLines: _maxVisibleLines,
                  maxLength: maxNoteContentLength,
                  decoration: InputDecoration(
                    hintText: t(context, 'add_note_placeholder'),
                    hintStyle: theme.textTheme.bodySmall?.copyWith(
                      color: faded,
                    ),
                    isDense: true,
                    counterText: '',
                    contentPadding: _fieldPadding,
                    border: _border(theme),
                    enabledBorder: _border(theme),
                  ),
                ),
              ),
            ),
            if (widget.dictationEnabled)
              SpeechNoteButton(controller: widget.contentController),
            const SizedBox(width: 4),
            IconButton(
              onPressed: _submit,
              icon: const Icon(Icons.send),
              tooltip: t(context, 'tooltip_add_note'),
            ),
          ],
        ),
        if (newlineHint != null)
          Padding(
            padding: const EdgeInsets.only(
              left: _pageFieldWidth + _fieldGap,
              top: 4,
            ),
            child: ExcludeSemantics(
              child: Text(
                newlineHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
