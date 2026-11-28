import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/publisher_suggestions.dart';

/// The book form's publisher field, suggesting the library's publishers as
/// the user types ([publisherSuggestions]). The suggestion helps, it does not
/// constrain: any name can be typed and saved.
///
/// Enter keeps the name typed, unless the user has picked a suggestion with
/// the arrow keys since typing: Enter then takes the highlighted one.
///
/// The publishers are read when the field first takes the focus, not when
/// the form opens: reading them goes through the whole library, a cost not
/// worth paying while the field is left alone.
class PublisherField extends StatefulWidget {
  /// The form's controller, which keeps the field's text.
  final TextEditingController controller;

  /// Reads the library's publishers, one per name ([distinctPublishers]).
  final Future<List<String>> Function() loadPublishers;

  /// The form's decoration for its fields.
  final InputDecoration decoration;

  /// The key of the text field itself, for tests.
  final Key? textFieldKey;

  final TextInputAction? textInputAction;

  final TextCapitalization textCapitalization;

  const PublisherField({
    super.key,
    required this.controller,
    required this.loadPublishers,
    required this.decoration,
    this.textFieldKey,
    this.textInputAction,
    this.textCapitalization = TextCapitalization.none,
  });

  @override
  State<PublisherField> createState() => _PublisherFieldState();
}

class _PublisherFieldState extends State<PublisherField> {
  final _focusNode = FocusNode();
  List<String> _publishers = const [];
  bool _loadStarted = false;

  /// Whether the user has moved through the suggestions with the keyboard
  /// since the text last changed. The autocomplete keeps the highlighted
  /// index across typing, so it cannot tell by itself.
  bool _navigated = false;
  String _lastText = '';

  static final _navigationKeys = {
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.pageUp,
    LogicalKeyboardKey.pageDown,
  };

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
    _lastText = widget.controller.text;
    widget.controller.addListener(_onTextChange);
  }

  @override
  void didUpdateWidget(PublisherField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChange);
      _lastText = widget.controller.text;
      widget.controller.addListener(_onTextChange);
    }
  }

  void _onTextChange() {
    // The listener also fires on cursor moves: only typing resets.
    final text = widget.controller.text;
    if (text == _lastText) return;
    _lastText = text;
    _navigated = false;
  }

  /// Notes the navigation keys on their way to the autocomplete's shortcuts,
  /// which handle them: the event is never consumed here. With Shift or Alt
  /// the keys select or move through the text, not through the suggestions.
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (event is! KeyUpEvent &&
        _navigationKeys.contains(event.logicalKey) &&
        !keyboard.isShiftPressed &&
        !keyboard.isAltPressed) {
      _navigated = true;
    }
    return KeyEventResult.ignored;
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus || _loadStarted) return;
    _loadStarted = true;
    _load();
  }

  Future<void> _load() async {
    try {
      final publishers = await widget.loadPublishers();
      if (mounted) setState(() => _publishers = publishers);
    } catch (e) {
      // Without suggestions the field still takes any name.
      debugPrint('Error loading publishers for suggestions: $e');
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChange);
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      optionsBuilder: (value) =>
          publisherSuggestions(_publishers, value.text),
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) =>
          Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: _onKeyEvent,
            child: TextFormField(
              key: widget.textFieldKey,
              controller: controller,
              focusNode: focusNode,
              textInputAction: widget.textInputAction,
              textCapitalization: widget.textCapitalization,
              decoration: widget.decoration,
              // Without arrow navigation, Enter would replace the name typed
              // with the first suggestion ("Seuil" becoming "Seuil
              // Jeunesse"): it keeps the name instead.
              onFieldSubmitted: (_) {
                if (!_navigated) return;
                _navigated = false;
                onFieldSubmitted();
              },
            ),
          ),
    );
  }
}
