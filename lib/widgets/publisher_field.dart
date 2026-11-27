import 'package:flutter/material.dart';

import '../utils/publisher_suggestions.dart';

/// The book form's publisher field, suggesting the library's publishers as
/// the user types ([publisherSuggestions]). The suggestion helps, it does not
/// constrain: any name can be typed and saved.
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

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
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
      // `onFieldSubmitted` is left unwired on purpose: Enter would replace
      // the name typed with the first suggestion ("Seuil" becoming "Seuil
      // Jeunesse"). A suggestion is taken by tapping it.
      fieldViewBuilder: (context, controller, focusNode, _) => TextFormField(
        key: widget.textFieldKey,
        controller: controller,
        focusNode: focusNode,
        textInputAction: widget.textInputAction,
        textCapitalization: widget.textCapitalization,
        decoration: widget.decoration,
      ),
    );
  }
}
