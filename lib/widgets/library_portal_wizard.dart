import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../services/portal_probe.dart';
import '../services/translation_service.dart';
import '../utils/library_portals.dart';

/// What the witness wizard is connecting: the reader's public library
/// catalogue, or a bookshop added by hand (the escape valve for shops
/// outside the curated registry; the choice is the reader's own).
enum PortalWizardKind { library, bookshop }

/// Three-step wizard connecting an external catalogue by example: name
/// it, search the witness ISBN on its site, paste the result URL. The pasted URL is turned into a template
/// by [parseLibraryResultUrl]; verification is deliberately lenient (an
/// OPAC may not hold the witness edition, or render results in JS), so
/// a failed check warns but never blocks saving.
class LibraryPortalWizard extends StatefulWidget {
  final PortalWizardKind kind;

  const LibraryPortalWizard({
    super.key,
    this.kind = PortalWizardKind.library,
  });

  static Future<void> show(
    BuildContext context, {
    PortalWizardKind kind = PortalWizardKind.library,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => LibraryPortalWizard(kind: kind),
    );
  }

  @override
  State<LibraryPortalWizard> createState() => _LibraryPortalWizardState();
}

enum _Verdict { ok, unconfirmed }

class _LibraryPortalWizardState extends State<LibraryPortalWizard> {
  final _nameController = TextEditingController();
  final _urlController = TextEditingController();
  int _step = 0;
  LibraryTemplateError? _parseError;
  String? _template;
  bool _verifying = false;
  _Verdict? _verdict;

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  String t(String key) => TranslationService.translate(context, key);

  /// Kind-specific wording; the mechanics are identical.
  String tk(String suffix) => t(
        widget.kind == PortalWizardKind.library
            ? 'library_wizard_$suffix'
            : 'bookshop_wizard_$suffix',
      );

  Future<void> _verify() async {
    final parse = parseLibraryResultUrl(_urlController.text);
    if (parse.template == null) {
      setState(() {
        _parseError = parse.error;
        _template = null;
        _verdict = null;
      });
      return;
    }
    setState(() {
      _parseError = null;
      _template = parse.template;
      _verifying = true;
      _verdict = null;
    });
    final confirmed = await probePortalWitness(_urlController.text.trim());
    final verdict = confirmed ? _Verdict.ok : _Verdict.unconfirmed;
    if (!mounted) return;
    setState(() {
      _verifying = false;
      _verdict = verdict;
    });
  }

  Future<void> _save() async {
    final template = _template;
    if (template == null) return;
    final portal = LocalLibraryPortal(
      name: _nameController.text.trim(),
      urlTemplate: template,
    );
    final provider = context.read<ThemeProvider>();
    await (widget.kind == PortalWizardKind.library
        ? provider.addMyLibraryPortal(portal)
        : provider.addMyCustomBookshop(portal));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 16,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              t(
                widget.kind == PortalWizardKind.library
                    ? 'settings_libraries_add'
                    : 'settings_bookshops_add_custom',
              ),
              style: theme.textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 16),
          ..._stepContent(theme),
          const SizedBox(height: 16),
          _buttons(),
        ],
      ),
    );
  }

  List<Widget> _stepContent(ThemeData theme) {
    switch (_step) {
      case 0:
        return [
          Text(tk('intro')),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: tk('name_label'),
              border: const OutlineInputBorder(),
            ),
          ),
        ];
      case 1:
        return [
          Text(tk('search_step')),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(libraryWitnessTitle),
            subtitle: Text(libraryWitnessIsbn),
            trailing: IconButton(
              icon: const Icon(Icons.copy),
              tooltip: t('library_wizard_copy_isbn'),
              onPressed: () async {
                await Clipboard.setData(
                  const ClipboardData(text: libraryWitnessIsbn),
                );
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(t('library_wizard_isbn_copied')),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),
          ),
        ];
      default:
        return [
          TextField(
            controller: _urlController,
            autofocus: true,
            keyboardType: TextInputType.url,
            onChanged: (_) => setState(() {
              _parseError = null;
              _template = null;
              _verdict = null;
            }),
            decoration: InputDecoration(
              labelText: t('library_wizard_paste_label'),
              border: const OutlineInputBorder(),
              errorText: switch (_parseError) {
                null => null,
                LibraryTemplateError.notHttps =>
                  t('library_wizard_error_https'),
                LibraryTemplateError.witnessMissing =>
                  t('library_wizard_error_witness'),
              },
            ),
          ),
          if (_verifying)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (_verdict != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  Icon(
                    _verdict == _Verdict.ok
                        ? Icons.check_circle_outline
                        : Icons.info_outline,
                    color: _verdict == _Verdict.ok
                        ? Colors.green
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t(
                        _verdict == _Verdict.ok
                            ? 'library_wizard_verdict_ok'
                            : 'library_wizard_verdict_partial',
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ];
    }
  }

  Widget _buttons() {
    final lastStep = _step == 2;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: _step == 0
              ? () => Navigator.of(context).pop()
              : () => setState(() => _step -= 1),
          child: Text(t(_step == 0 ? 'cancel' : 'back')),
        ),
        const SizedBox(width: 8),
        if (!lastStep)
          FilledButton(
            onPressed: _step == 0 && _nameController.text.trim().isEmpty
                ? null
                : () => setState(() => _step += 1),
            child: Text(t('library_wizard_next')),
          )
        else ...[
          OutlinedButton(
            onPressed: _verifying || _urlController.text.trim().isEmpty
                ? null
                : _verify,
            child: Text(t('library_wizard_verify')),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _template == null || _verifying ? null : _save,
            child: Text(t('save')),
          ),
        ],
      ],
    );
  }
}
