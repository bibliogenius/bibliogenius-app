import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../services/api_service.dart';
import '../../services/collection_import_service.dart';
import '../../services/translation_service.dart';
import '../../utils/collection_display.dart';
import '../../providers/theme_provider.dart';

/// Screen for importing a shared .bibliogenius.yml file.
class ImportSharedListScreen extends StatefulWidget {
  final String? initialYamlContent;

  const ImportSharedListScreen({Key? key, this.initialYamlContent})
    : super(key: key);

  @override
  State<ImportSharedListScreen> createState() => _ImportSharedListScreenState();
}

class _ImportSharedListScreenState extends State<ImportSharedListScreen> {
  String? _yamlContent;
  Map<String, dynamic>? _preview;
  String? _validationError;
  bool _isImporting = false;
  String _selectedStatus = 'wanting';

  @override
  void initState() {
    super.initState();
    if (widget.initialYamlContent != null) {
      _processYaml(widget.initialYamlContent!);
    }
  }

  void _processYaml(String content) {
    final apiService = Provider.of<ApiService>(context, listen: false);
    final importService = CollectionImportService(apiService);

    final error = importService.validateYaml(content);
    final preview = importService.getPreview(content);

    setState(() {
      _yamlContent = content;
      _validationError = error;
      _preview = preview;
    });
  }

  void _showTooLarge() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          TranslationService.translate(context, 'import_file_too_large'),
        ),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['yml', 'yaml', 'bibliogenius'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        String content;

        // Measured BEFORE reading: the point of the bound is not to parse a
        // huge file, and loading it into a String to then measure it would
        // have already paid the cost the bound exists to avoid.
        if (CollectionImportService.isTooLargeToParse(file.size)) {
          if (mounted) _showTooLarge();
          return;
        }

        if (file.bytes != null) {
          // UTF-8, never code units: the exported file is written as UTF-8,
          // and reading it back byte per byte doubled every accent.
          content = CollectionImportService.decodeSharedListBytes(file.bytes!);
        } else if (file.path != null) {
          // Same decoder as the bytes branch: `readAsString` is strict UTF-8
          // and throws on a file saved in another encoding, so which branch
          // the picker takes would decide whether the import is possible.
          content = CollectionImportService.decodeSharedListBytes(
            await File(file.path!).readAsBytes(),
          );
        } else {
          throw Exception('Could not read file');
        }

        _processYaml(content);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'error_reading_file')}: $e',
            ),
          ),
        );
      }
    }
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      // Already in memory here, the system handed it over, but the parse is
      // still ahead and that is what the bound protects.
      final pasted = data?.text ?? '';
      if (CollectionImportService.isTooLargeToParse(pasted.length)) {
        if (mounted) _showTooLarge();
        return;
      }
      if (pasted.isNotEmpty) {
        _processYaml(pasted);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                TranslationService.translate(context, 'clipboard_empty'),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'error_reading_clipboard')}: $e',
            ),
          ),
        );
      }
    }
  }

  Future<void> _importCollection() async {
    if (_yamlContent == null || _validationError != null) return;

    setState(() {
      _isImporting = true;
    });

    try {
      final apiService = Provider.of<ApiService>(context, listen: false);
      final importService = CollectionImportService(apiService);

      // Compared by DISPLAYED name: a favourites collection stores the
      // `__favorites__` sentinel and shows a translated label, so a check on
      // stored names would miss the very collision this guards against.
      final existing = (await apiService.getCollections())
          .map((c) => collectionDisplayName(context, c))
          .toList();
      if (!mounted) return;

      final result = await importService.importFromYaml(
        _yamlContent!,
        readingStatus: _selectedStatus == 'owned' ? 'to_read' : _selectedStatus,
        markAsOwned: _selectedStatus != 'wanting',
        existingCollectionNames: existing,
        nameCollisionFormat: TranslationService.translate(
          context,
          'imported_collection_name_from',
        ),
        // A shared list arrives in whatever language its author wrote it, so
        // read its title in the reader's own rather than in a hardcoded one.
        langCode: context.read<ThemeProvider>().locale.languageCode,
      );

      if (mounted) {
        String message = TranslationService.translate(
          context,
          'collection_created',
          params: {
            'title': result.collection?.name ?? "Unknown",
            'count': result.successCount.toString(),
          },
        );
        if (result.errorCount > 0) {
          message +=
              ' ${TranslationService.translate(context, 'books_skipped_count', params: {'count': result.errorCount.toString()})}';
        }

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));

        Navigator.pop(context, true); // Return success
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'import_error')}: $e',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          TranslationService.translate(context, 'import_shared_list'),
        ),
      ),
      body: _isImporting
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(
                    TranslationService.translate(
                      context,
                      'importing_collection',
                    ),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Source selection
                  if (_yamlContent == null) ...[
                    Text(
                      TranslationService.translate(
                        context,
                        'import_choose_source',
                      ),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Pick file button
                    OutlinedButton.icon(
                      onPressed: _pickFile,
                      icon: const Icon(Icons.file_open),
                      label: Text(
                        TranslationService.translate(
                          context,
                          'select_bibliogenius_file',
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Paste button
                    OutlinedButton.icon(
                      onPressed: _pasteFromClipboard,
                      icon: const Icon(Icons.paste),
                      label: Text(
                        TranslationService.translate(
                          context,
                          'paste_from_clipboard',
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Info card
                    Card(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.info_outline, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  TranslationService.translate(
                                    context,
                                    'import_supported_formats',
                                  ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // Names the export that produces these files, so
                            // the two halves of sharing stop being strangers
                            // to each other.
                            Text(
                              TranslationService.translate(
                                context,
                                'import_supported_formats_detail',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  // Preview
                  if (_yamlContent != null) ...[
                    if (_validationError != null)
                      Card(
                        color: Colors.red.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              const Icon(Icons.error, color: Colors.red),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _validationError!,
                                  style: const TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (_preview != null) ...[
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _preview!['title'] ?? 'Untitled',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              if (_preview!['description'] != null) ...[
                                const SizedBox(height: 8),
                                Text(_preview!['description']),
                              ],
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  const Icon(Icons.book, size: 18),
                                  const SizedBox(width: 8),
                                  Text(
                                    // The same key the share panel prints, so
                                    // the two ends of one exchange count in
                                    // the same words.
                                    TranslationService.translate(
                                      context,
                                      'collection_share_count',
                                    ).replaceAll(
                                      '{count}',
                                      '${_preview!['bookCount']}',
                                    ),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodyLarge,
                                  ),
                                ],
                              ),
                              // A long list is unusual, not hostile, so this
                              // warns and never refuses. What it warns about
                              // is cost: the import calls the metadata lookup
                              // once per book, each waiting out its own
                              // timeout.
                              if (CollectionImportService.isLargeSharedList(
                                (_preview!['bookCount'] as int?) ?? 0,
                              )) ...[
                                const SizedBox(height: 12),
                                Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.hourglass_top,
                                      size: 18,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.tertiary,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        TranslationService.translate(
                                          context,
                                          'import_large_list_warning',
                                        ).replaceAll(
                                          '{count}',
                                          '${_preview!['bookCount']}',
                                        ),
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              if (_preview!['contributor'] != null) ...[
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(Icons.person, size: 18),
                                    const SizedBox(width: 8),
                                    Text(
                                      TranslationService.translate(
                                        context,
                                        'shared_list_by_contributor',
                                        params: {
                                          'name':
                                              '${_preview!['contributor']}',
                                        },
                                      ),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium,
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Status selection. The same label the curated import
                      // dialog prints: one wording for one question, and it
                      // was the only English line left on this screen.
                      Text(
                        TranslationService.translate(
                          context,
                          'imported_books_status',
                        ),
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _selectedStatus,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'owned',
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.inventory_2_outlined,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  TranslationService.translate(
                                    context,
                                    'status_owned',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'to_read',
                            child: Row(
                              children: [
                                const Icon(Icons.bookmark_border, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  // `status_to_read` was asked for here and
                                  // exists in no catalogue, so this option
                                  // read as its own key in every language.
                                  TranslationService.translate(
                                    context,
                                    'reading_status_to_read',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'wanting',
                            child: Row(
                              children: [
                                const Icon(Icons.favorite_border, size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  TranslationService.translate(
                                    context,
                                    'status_wanted',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        onChanged: (val) {
                          setState(() {
                            _selectedStatus = val ?? 'wanting';
                          });
                        },
                      ),

                      const SizedBox(height: 24),

                      // Import button
                      FilledButton.icon(
                        onPressed: _importCollection,
                        icon: const Icon(Icons.download),
                        label: Text(
                          TranslationService.translate(
                            context,
                            'import_collection',
                          ),
                        ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.all(16),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Cancel/Choose different file
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _yamlContent = null;
                            _preview = null;
                            _validationError = null;
                          });
                        },
                        child: Text(
                          TranslationService.translate(
                            context,
                            'choose_different_file',
                          ),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
    );
  }
}
