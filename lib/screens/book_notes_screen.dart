import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/book_note.dart';
import '../providers/book_note_provider.dart';
import '../providers/theme_provider.dart';
import '../services/translation_service.dart';
import '../widgets/book_note_tile.dart';
import '../widgets/speech_note_button.dart';

/// Dedicated screen showing all reading notes for a book.
class BookNotesScreen extends StatefulWidget {
  final int bookId;
  final String bookTitle;

  const BookNotesScreen({
    super.key,
    required this.bookId,
    required this.bookTitle,
  });

  @override
  State<BookNotesScreen> createState() => _BookNotesScreenState();
}

class _BookNotesScreenState extends State<BookNotesScreen> {
  final _contentController = TextEditingController();
  final _pageController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BookNoteProvider>().loadNotes(widget.bookId);
    });
  }

  @override
  void dispose() {
    _contentController.dispose();
    _pageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _addNote() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) return;
    final page = int.tryParse(_pageController.text.trim());

    final success = await context.read<BookNoteProvider>().createNote(
      content: content,
      page: page,
    );
    if (success && mounted) {
      _contentController.clear();
      _pageController.clear();
      FocusScope.of(context).unfocus();
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }
  }

  Future<void> _editNote(BookNote note) async {
    final contentCtrl = TextEditingController(text: note.content);
    final pageCtrl = TextEditingController(text: note.page?.toString() ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(TranslationService.translate(context, 'edit_note')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: contentCtrl,
              maxLines: 4,
              maxLength: maxNoteContentLength,
              decoration: InputDecoration(
                hintText: TranslationService.translate(
                  context,
                  'add_note_placeholder',
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: pageCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: TranslationService.translate(
                  context,
                  'note_page_label',
                ),
                prefixIcon: const Icon(Icons.bookmark_outline, size: 20),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      final newContent = contentCtrl.text.trim();
      if (newContent.isEmpty) return;
      await context.read<BookNoteProvider>().updateNote(
        id: note.id,
        content: newContent,
        page: int.tryParse(pageCtrl.text.trim()),
      );
    }
    contentCtrl.dispose();
    pageCtrl.dispose();
  }

  Future<void> _deleteNote(BookNote note) async {
    await context.read<BookNoteProvider>().deleteNote(note.id);
  }

  @override
  Widget build(BuildContext context) {
    final t = TranslationService.translate;

    return Scaffold(
      appBar: AppBar(title: Text(t(context, 'notes_section_title'))),
      body: Consumer<BookNoteProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          return Column(
            children: [
              // Input bar
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 64,
                      child: TextField(
                        controller: _pageController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium,
                        decoration: InputDecoration(
                          hintText: 'p.',
                          isDense: true,
                          prefixIcon: Icon(
                            Icons.bookmark_outline,
                            size: 16,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withAlpha(100),
                          ),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 24,
                            minHeight: 0,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: Theme.of(
                                context,
                              ).colorScheme.outline.withAlpha(60),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: Theme.of(
                                context,
                              ).colorScheme.outline.withAlpha(60),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _contentController,
                        textInputAction: TextInputAction.send,
                        maxLength: maxNoteContentLength,
                        maxLines: null,
                        onSubmitted: (_) => _addNote(),
                        decoration: InputDecoration(
                          hintText: t(context, 'add_note_placeholder'),
                          hintStyle: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withAlpha(100),
                              ),
                          isDense: true,
                          counterText: '',
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: Theme.of(
                                context,
                              ).colorScheme.outline.withAlpha(60),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: Theme.of(
                                context,
                              ).colorScheme.outline.withAlpha(60),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (context.watch<ThemeProvider>().speechToTextEnabled)
                      SpeechNoteButton(controller: _contentController),
                    const SizedBox(width: 4),
                    IconButton(
                      onPressed: _addNote,
                      icon: const Icon(Icons.send),
                      tooltip: t(context, 'tooltip_add_note'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Notes list
              Expanded(
                child: provider.notes.isEmpty
                    ? Center(
                        child: Text(
                          t(context, 'no_notes_yet'),
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withAlpha(128),
                              ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: provider.notes.length,
                        itemBuilder: (context, index) {
                          final note = provider.notes[index];
                          return BookNoteTile(
                            note: note,
                            onEdit: () => _editNote(note),
                            onDelete: () => _deleteNote(note),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
