import 'package:flutter/material.dart';

import '../../services/translation_service.dart';

/// Ask for a new collection name. Returns the trimmed name, or null when the
/// user cancelled. Both entry points (the collection list and the collection
/// detail screen) go through this so the field, its validation and its
/// controller lifetime stay in one place.
Future<String?> showRenameCollectionDialog(
  BuildContext context, {
  required String initialName,
}) => showDialog<String>(
  context: context,
  builder: (_) => RenameCollectionDialog(initialName: initialName),
);

/// The rename dialog, a widget of its own so it owns its text controller.
///
/// A controller created by the caller and disposed right after `showDialog`
/// resolves is still in use by the field while the dialog animates out, which
/// throws "A TextEditingController was used after being disposed" and blanks
/// the frame. Owning it here ties its life to the dialog's.
class RenameCollectionDialog extends StatefulWidget {
  const RenameCollectionDialog({super.key, required this.initialName});

  final String initialName;

  @override
  State<RenameCollectionDialog> createState() =>
      _RenameCollectionDialogState();
}

class _RenameCollectionDialogState extends State<RenameCollectionDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(TranslationService.translate(context, 'rename_collection')),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          labelText: TranslationService.translate(context, 'name'),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(TranslationService.translate(context, 'cancel')),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(TranslationService.translate(context, 'rename')),
        ),
      ],
    );
  }
}
