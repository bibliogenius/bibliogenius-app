import 'package:flutter/material.dart';
import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/translation_service.dart';

/// A modal bottom sheet for selecting a book edition from multiple options.
/// Inspired by Gleeph's edition picker.
class EditionPickerSheet extends StatefulWidget {
  final String title;
  final String? author;
  final List<Map<String, dynamic>> editions;
  final Function(Map<String, dynamic>) onSelect;

  const EditionPickerSheet({
    super.key,
    required this.title,
    this.author,
    required this.editions,
    required this.onSelect,
  });

  /// Show the edition picker as a modal bottom sheet
  static Future<Map<String, dynamic>?> show({
    required BuildContext context,
    required String title,
    String? author,
    required List<Map<String, dynamic>> editions,
  }) async {
    // Sort editions: cover + publisher first, then cover, then publisher, then ISBN
    final sortedEditions = List<Map<String, dynamic>>.from(editions);
    sortedEditions.sort((a, b) {
      final coverA = a['cover_url'] as String?;
      final coverB = b['cover_url'] as String?;
      final hasCoverA = coverA != null && coverA.isNotEmpty;
      final hasCoverB = coverB != null && coverB.isNotEmpty;

      final publisherA = a['publisher'] as String?;
      final publisherB = b['publisher'] as String?;
      final hasPublisherA = publisherA != null && publisherA.isNotEmpty;
      final hasPublisherB = publisherB != null && publisherB.isNotEmpty;

      // 1. Prioritize editions with BOTH cover AND publisher
      final hasCompleteA = hasCoverA && hasPublisherA;
      final hasCompleteB = hasCoverB && hasPublisherB;

      if (hasCompleteA && !hasCompleteB) return -1;
      if (!hasCompleteA && hasCompleteB) return 1;

      // 2. Prioritize editions with cover only
      if (hasCoverA && !hasCoverB) return -1;
      if (!hasCoverA && hasCoverB) return 1;

      // 3. Prioritize editions with publisher only
      if (hasPublisherA && !hasPublisherB) return -1;
      if (!hasPublisherA && hasPublisherB) return 1;

      // 4. Prioritize editions with ISBN
      final isbnA = a['isbn'] as String?;
      final isbnB = b['isbn'] as String?;
      final hasIsbnA = isbnA != null && isbnA.isNotEmpty;
      final hasIsbnB = isbnB != null && isbnB.isNotEmpty;

      if (hasIsbnA && !hasIsbnB) return -1;
      if (!hasIsbnA && hasIsbnB) return 1;

      return 0;
    });

    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => EditionPickerSheet(
        title: title,
        author: author,
        editions: sortedEditions,
        onSelect: (edition) => Navigator.of(ctx).pop(edition),
      ),
    );
  }

  @override
  State<EditionPickerSheet> createState() => _EditionPickerSheetState();
}

class _EditionPickerSheetState extends State<EditionPickerSheet> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Color _getSourceColor(String? source) {
    if (source == null) return Colors.blue;
    if (source.contains('Inventaire')) return Colors.green;
    if (source.toLowerCase().contains('bnf')) return Colors.orange;
    if (source.contains('Google')) return Colors.red;
    return Colors.blue;
  }

  String _getSourceLabel(String? source) {
    if (source == null) return 'OL';
    if (source.contains('Inventaire')) return 'INV';
    if (source.toLowerCase().contains('bnf')) return 'BNF';
    if (source.contains('Google')) return 'GB';
    return 'OL';
  }

  String _getLanguageLabel(String? langCode) {
    if (langCode == null || langCode.isEmpty) return '';
    final code = langCode.toLowerCase();
    const langMap = {
      'fr': 'FR',
      'fre': 'FR',
      'fra': 'FR',
      'en': 'EN',
      'eng': 'EN',
      'es': 'ES',
      'spa': 'ES',
      'de': 'DE',
      'ger': 'DE',
      'deu': 'DE',
      'it': 'IT',
      'ita': 'IT',
      'pt': 'PT',
      'por': 'PT',
    };
    return langMap[code] ??
        code.toUpperCase().substring(0, min(2, code.length));
  }

  Color _getCoverColor(String title) {
    if (title.isEmpty) return Colors.grey;
    final random = Random(title.hashCode);
    return Color.fromARGB(
      255,
      random.nextInt(200),
      random.nextInt(200),
      random.nextInt(200),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editionCount = widget.editions.length;
    final mediaQuery = MediaQuery.of(context);

    return Container(
      constraints: BoxConstraints(maxHeight: mediaQuery.size.height * 0.7),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header with title and author
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  TranslationService.translate(context, 'select_edition'),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Serif',
                    fontFamilyFallback: const [
                      'Hiragino Sans',
                      'PingFang SC',
                      'Noto Sans CJK JP',
                      'sans-serif',
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (widget.author != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.author!.toUpperCase(),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: 0.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),

          const Divider(height: 1),

          // Edition Carousel
          SizedBox(
            height: 200,
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (index) => setState(() => _currentPage = index),
              itemCount: editionCount,
              itemBuilder: (context, index) {
                final edition = widget.editions[index];
                return _buildEditionSlide(edition, theme);
              },
            ),
          ),

          // Dots Indicator + Edition count
          if (editionCount > 1) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                min(editionCount, 10), // Max 10 dots
                (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: _currentPage == index ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _currentPage == index
                        ? theme.primaryColor
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${_currentPage + 1} / $editionCount ${TranslationService.translate(context, 'editions')}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.secondary,
              ),
            ),
          ],

          // Select Button
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              16,
              20,
              mediaQuery.padding.bottom + 16,
            ),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => widget.onSelect(widget.editions[_currentPage]),
                icon: const Icon(Icons.check_circle_outline),
                label: Text(
                  TranslationService.translate(context, 'select_this_edition'),
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditionSlide(Map<String, dynamic> edition, ThemeData theme) {
    final coverUrl = edition['cover_url'] as String?;
    final source = edition['source'] as String?;
    final language = edition['language'] as String?;
    final langLabel = _getLanguageLabel(language);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cover
          Container(
            width: 100,
            height: 150,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              children: [
                // Gradient Fallback
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        _getCoverColor(widget.title),
                        _getCoverColor(widget.title).withOpacity(0.7),
                      ],
                    ),
                  ),
                  child: Center(
                    child: Text(
                      widget.title.isNotEmpty
                          ? widget.title.substring(0, 1).toUpperCase()
                          : '',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 32,
                      ),
                    ),
                  ),
                ),

                // Network Image
                if (coverUrl != null && coverUrl.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: coverUrl,
                      width: 100,
                      height: 150,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => const SizedBox.shrink(),
                      errorWidget: (context, url, error) =>
                          const SizedBox.shrink(),
                    ),
                  ),

                // Source Badge
                if (source != null)
                  Positioned(
                    bottom: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _getSourceColor(source),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _getSourceLabel(source),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(width: 16),

          // Metadata
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (edition['publisher'] != null &&
                    (edition['publisher'] as String).isNotEmpty)
                  Row(
                    children: [
                      Icon(
                        Icons.apartment,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          edition['publisher'] as String,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (edition['publication_year'] != null)
                      _buildChip(
                        Icons.calendar_today,
                        edition['publication_year'].toString(),
                        theme,
                      ),
                    if (langLabel.isNotEmpty)
                      _buildChip(Icons.language, langLabel, theme),
                    if (edition['isbn'] != null &&
                        (edition['isbn'] as String).isNotEmpty)
                      _buildChip(Icons.qr_code, 'ISBN', theme),
                  ],
                ),
                if (edition['isbn'] != null &&
                    (edition['isbn'] as String).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      edition['isbn'] as String,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(IconData icon, String label, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
