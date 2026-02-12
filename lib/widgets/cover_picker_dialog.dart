import 'dart:math';

import 'package:flutter/material.dart';

import '../models/cover_candidate.dart';
import '../services/translation_service.dart';
import 'cached_book_cover.dart';

/// A dialog that presents multiple cover candidates in a carousel
/// and lets the user pick the one they want.
class CoverPickerDialog extends StatefulWidget {
  final List<CoverCandidate> candidates;
  final String bookTitle;

  const CoverPickerDialog({
    super.key,
    required this.candidates,
    required this.bookTitle,
  });

  /// Show the cover picker dialog and return the selected cover URL, or null.
  static Future<String?> show({
    required BuildContext context,
    required List<CoverCandidate> candidates,
    required String bookTitle,
  }) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => CoverPickerDialog(
        candidates: candidates,
        bookTitle: bookTitle,
      ),
    );
  }

  @override
  State<CoverPickerDialog> createState() => _CoverPickerDialogState();
}

class _CoverPickerDialogState extends State<CoverPickerDialog> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Color _getSourceColor(String source) {
    if (source.contains('Inventaire')) return Colors.green;
    if (source.contains('BNF')) return Colors.orange;
    if (source.contains('Google')) return Colors.red;
    return Colors.blue; // OpenLibrary
  }

  String _getSourceLabel(String source) {
    if (source.contains('Inventaire')) return 'INV';
    if (source.contains('BNF')) return 'BNF';
    if (source.contains('Google')) return 'GB';
    return 'OL';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = widget.candidates.length;

    return AlertDialog(
      title: Text(
        TranslationService.translate(context, 'cover_pick_title') ??
            'Choose a cover',
      ),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 320,
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemCount: count,
                itemBuilder: (context, index) {
                  final candidate = widget.candidates[index];
                  return _buildCoverSlide(candidate);
                },
              ),
            ),
            if (count > 1) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  min(count, 10),
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: _currentPage == i ? 16 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: _currentPage == i
                          ? theme.colorScheme.primary
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_currentPage + 1} / $count',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.secondary,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context)
              .pop(widget.candidates[_currentPage].url),
          child: Text(
            TranslationService.translate(context, 'cover_use_button') ?? 'Use',
          ),
        ),
      ],
    );
  }

  Widget _buildCoverSlide(CoverCandidate candidate) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CachedBookCover(
            imageUrl: candidate.url,
            width: 160,
            height: 240,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _getSourceColor(candidate.source),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            _getSourceLabel(candidate.source),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
