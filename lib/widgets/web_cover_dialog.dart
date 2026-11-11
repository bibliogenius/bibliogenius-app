import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../services/translation_service.dart';
import '../services/web_cover_service.dart';

/// Asks for the address of a book's page on a publisher's site (or of the
/// cover image itself), fetches the cover into a temp file and shows it for
/// the user to keep or refuse. Resolves to the kept cover, still under its
/// temp name, or null; a refused or abandoned preview is deleted.
Future<WebCoverPick?> showWebCoverDialog(
  BuildContext context, {
  WebCoverService? service,
}) {
  return showDialog<WebCoverPick>(
    context: context,
    builder: (_) => WebCoverDialog(service: service ?? WebCoverService()),
  );
}

class WebCoverDialog extends StatefulWidget {
  final WebCoverService service;

  const WebCoverDialog({super.key, required this.service});

  @override
  State<WebCoverDialog> createState() => _WebCoverDialogState();
}

class _WebCoverDialogState extends State<WebCoverDialog> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _loading = false;
  String? _errorKey;

  /// The fetched cover, shown for confirmation. Nothing outside this dialog
  /// knows about it until the user keeps it.
  WebCoverPick? _preview;
  bool _kept = false;

  @override
  void dispose() {
    // However the dialog closes (cancel, barrier, back), a preview that was
    // not kept must not stay on disk.
    final preview = _preview;
    if (preview != null && !_kept) widget.service.discard(preview);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    final url = _controller.text.trim();
    if (url.isEmpty || _loading) return;
    setState(() {
      _loading = true;
      _errorKey = null;
    });
    String? errorKey;
    WebCoverPick? pick;
    try {
      pick = await widget.service.fetchAndSave(url);
    } on WebCoverException catch (e) {
      errorKey = e.translationKey;
    } catch (e) {
      // The service maps every failure; this only keeps the dialog usable
      // should something slip through.
      debugPrint('[WEB-COVER] unexpected failure: $e');
      errorKey = WebCoverException('network').translationKey;
    }
    if (!mounted) {
      if (pick != null) widget.service.discard(pick);
      return;
    }
    setState(() {
      _loading = false;
      _errorKey = errorKey;
      _preview = pick;
    });
    if (errorKey != null) {
      _focus.requestFocus();
    } else {
      // The preview replaces the address field: a screen reader would
      // otherwise not say that the cover has arrived.
      SemanticsService.sendAnnouncement(
        View.of(context),
        TranslationService.translate(context, 'web_cover_preview_label'),
        Directionality.of(context),
      );
    }
  }

  void _tryAnother() {
    final preview = _preview;
    if (preview != null) widget.service.discard(preview);
    setState(() => _preview = null);
    _focus.requestFocus();
  }

  void _keep() {
    _kept = true;
    Navigator.of(context).pop(_preview);
  }

  @override
  Widget build(BuildContext context) {
    String t(String key) => TranslationService.translate(context, key);
    final preview = _preview;
    // The dialog can be left at any time, a fetch included: a result landing
    // after that is deleted (see the !mounted branch of _fetch).
    return AlertDialog(
        scrollable: true,
        title: Semantics(
          header: true,
          child: Text(t('web_cover_dialog_title')),
        ),
        content: preview == null
            ? _buildAddressForm(t)
            : _buildPreview(preview, t),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t('cancel')),
          ),
          if (preview == null)
            FilledButton(
              onPressed: _loading ? null : _fetch,
              child: Text(t('web_cover_dialog_fetch')),
            )
          else ...[
            TextButton(
              onPressed: _tryAnother,
              child: Text(t('web_cover_try_another')),
            ),
            FilledButton(onPressed: _keep, child: Text(t('web_cover_use'))),
          ],
        ],
    );
  }

  Widget _buildAddressForm(String Function(String) t) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t('web_cover_dialog_help')),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          focusNode: _focus,
          autofocus: true,
          // readOnly rather than disabled: a disabled field drops the focus,
          // and the user would have to tap it again after an error.
          readOnly: _loading,
          keyboardType: TextInputType.url,
          autocorrect: false,
          textInputAction: TextInputAction.go,
          decoration: InputDecoration(
            labelText: t('web_cover_dialog_field'),
            hintText: 'https://',
            errorText: _errorKey == null ? null : t(_errorKey!),
            errorMaxLines: 3,
          ),
          onSubmitted: (_) => _fetch(),
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
    );
  }

  Widget _buildPreview(WebCoverPick preview, String Function(String) t) {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(preview.path),
          height: 240,
          fit: BoxFit.contain,
          semanticLabel: t('web_cover_preview_label'),
          errorBuilder: (_, _, _) => const SizedBox(width: 160, height: 240),
        ),
      ),
    );
  }
}
