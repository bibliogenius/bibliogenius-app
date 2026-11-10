import 'package:flutter/material.dart';

import '../services/translation_service.dart';
import '../services/web_cover_service.dart';

/// Asks for the address of a book's page on a publisher's site (or of the
/// cover image itself), fetches the cover and saves it, as `<bookId>.jpg`
/// when [bookId] is known. Resolves to the saved cover, or null when the
/// dialog is dismissed.
Future<WebCoverPick?> showWebCoverDialog(
  BuildContext context, {
  String? bookId,
  WebCoverService? service,
}) {
  return showDialog<WebCoverPick>(
    context: context,
    builder: (_) =>
        WebCoverDialog(bookId: bookId, service: service ?? WebCoverService()),
  );
}

class WebCoverDialog extends StatefulWidget {
  final String? bookId;
  final WebCoverService service;

  const WebCoverDialog({super.key, this.bookId, required this.service});

  @override
  State<WebCoverDialog> createState() => _WebCoverDialogState();
}

class _WebCoverDialogState extends State<WebCoverDialog> {
  final _controller = TextEditingController();
  bool _loading = false;
  String? _errorKey;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final url = _controller.text.trim();
    if (url.isEmpty || _loading) return;
    setState(() {
      _loading = true;
      _errorKey = null;
    });
    try {
      final pick = await widget.service.fetchAndSave(
        url,
        bookId: widget.bookId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(pick);
    } on WebCoverException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorKey = e.translationKey;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    String t(String key) => TranslationService.translate(context, key);
    // While a fetch runs the dialog cannot be dismissed: in the edit flow the
    // fetch overwrites the book's cover file, which a "cancel" the user had
    // already seen succeed would contradict.
    return PopScope(
      canPop: !_loading,
      child: AlertDialog(
        title: Semantics(
          header: true,
          child: Text(t('web_cover_dialog_title')),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('web_cover_dialog_help')),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              enabled: !_loading,
              keyboardType: TextInputType.url,
              autocorrect: false,
              textInputAction: TextInputAction.go,
              decoration: InputDecoration(
                labelText: t('web_cover_dialog_field'),
                hintText: 'https://',
                errorText: _errorKey == null ? null : t(_errorKey!),
                errorMaxLines: 3,
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (_loading) ...[
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                label: t('web_cover_dialog_loading'),
                child: const LinearProgressIndicator(),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: _loading ? null : () => Navigator.of(context).pop(),
            child: Text(t('cancel')),
          ),
          FilledButton(
            onPressed: _loading ? null : _submit,
            child: Text(t('web_cover_dialog_fetch')),
          ),
        ],
      ),
    );
  }
}
