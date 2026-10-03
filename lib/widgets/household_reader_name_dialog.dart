import 'package:flutter/material.dart';

import '../services/translation_service.dart';

/// Longest reader name the backend accepts, in characters. Mirrors
/// `MAX_READER_NAME_CHARS` of the Rust household module, which rejects
/// anything longer.
const int maxReaderNameLength = 50;

/// Asks for the name of a household reader. Resolves to the trimmed name, or
/// null when the dialog is dismissed or the name is left empty.
Future<String?> showHouseholdReaderNameDialog(
  BuildContext context, {
  required String titleKey,
  String confirmKey = 'household_confirm',
  String initialName = '',
}) async {
  final controller = TextEditingController(text: initialName);
  // The dialog's route, to release the controller only once its subtree is
  // gone (see below).
  ModalRoute<Object?>? route;
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) {
      route ??= ModalRoute.of(ctx);
      return _ReaderNameDialog(
        titleKey: titleKey,
        confirmKey: confirmKey,
        controller: controller,
      );
    },
  );
  // `showDialog` resolves on pop, while the TextField stays on screen for the
  // closing transition and rebuilds when the keyboard retracts. Disposing
  // here made that rebuild throw "used after being disposed"; `completed`
  // fires once the overlay entries are removed, after the dialog's last build.
  final closing = route?.completed;
  if (closing == null) {
    controller.dispose();
  } else {
    closing.whenComplete(controller.dispose);
  }
  final trimmed = name?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

class _ReaderNameDialog extends StatelessWidget {
  final String titleKey;
  final String confirmKey;
  final TextEditingController controller;

  const _ReaderNameDialog({
    required this.titleKey,
    required this.confirmKey,
    required this.controller,
  });

  @override
  Widget build(BuildContext ctx) {
    return AlertDialog(
      title: Text(TranslationService.translate(ctx, titleKey)),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: maxReaderNameLength,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(
          labelText: TranslationService.translate(ctx, 'household_name'),
        ),
        onSubmitted: (v) => Navigator.of(ctx).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(TranslationService.translate(ctx, 'cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text),
          child: Text(TranslationService.translate(ctx, confirmKey)),
        ),
      ],
    );
  }
}
