import 'package:flutter/material.dart';
import 'dart:math';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/translation_service.dart';

/// A card showing a book work with multiple editions in a swipeable carousel.
/// Inspired by Gleeph's edition browser.
class WorkEditionCard extends StatefulWidget {
  final String workId;
  final String title;
  final String? author;
  final List<Map<String, dynamic>> editions;
  final Function(Map<String, dynamic>) onAddBook;
  final Function(Map<String, dynamic>)? onOpenUrl;

  const WorkEditionCard({
    super.key,
    required this.workId,
    required this.title,
    this.author,
    required this.editions,
    required this.onAddBook,
    this.onOpenUrl,
  });

  @override
  State<WorkEditionCard> createState() => _WorkEditionCardState();
}

class _WorkEditionCardState extends State<WorkEditionCard> {
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
    return Colors.blue; // OpenLibrary or default
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
      'french': 'FR',
      'en': 'EN',
      'eng': 'EN',
      'english': 'EN',
      'es': 'ES',
      'spa': 'ES',
      'spanish': 'ES',
      'de': 'DE',
      'ger': 'DE',
      'deu': 'DE',
      'german': 'DE',
      'it': 'IT',
      'ita': 'IT',
      'italian': 'IT',
      'pt': 'PT',
      'por': 'PT',
      'portuguese': 'PT',
      'nl': 'NL',
      'dut': 'NL',
      'nld': 'NL',
      'dutch': 'NL',
      'ru': 'RU',
      'rus': 'RU',
      'russian': 'RU',
      'ja': 'JA',
      'jpn': 'JA',
      'japanese': 'JA',
      'zh': 'ZH',
      'chi': 'ZH',
      'zho': 'ZH',
      'chinese': 'ZH',
    };
    return langMap[code] ?? code.toUpperCase().substring(0, 2);
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

  /// Truncate summary at word boundary for clean display
  String _truncateSummary(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    final truncated = text.substring(0, maxLength);
    final lastSpace = truncated.lastIndexOf(' ');
    if (lastSpace > maxLength * 0.7) {
      return '${truncated.substring(0, lastSpace)}...';
    }
    return '$truncated...';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final editionCount = widget.editions.length;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with title and author
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Serif', // Elegant touch
                    fontSize: 18,
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
                      fontWeight: FontWeight.w600,
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
          Container(
            height: 180,
            margin: const EdgeInsets.symmetric(vertical: 12),
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() => _currentPage = index);
              },
              itemCount: editionCount,
              itemBuilder: (context, index) {
                final edition = widget.editions[index];
                return _buildEditionSlide(edition, theme);
              },
            ),
          ),

          // Dots Indicator
          if (editionCount > 1)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                editionCount,
                (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: _currentPage == index ? 20 : 6,
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

          if (editionCount > 1)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  '$editionCount ${TranslationService.translate(context, 'editions')}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ),
            ),

          const SizedBox(height: 12),

          // Add Button
          Padding(
            padding: const EdgeInsets.all(16),
            child: Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FilledButton.icon(
                    onPressed: () =>
                        widget.onAddBook(widget.editions[_currentPage]),
                    icon: const Icon(Icons.add_circle_outline),
                    label: Text(
                      TranslationService.translate(context, 'add_to_library'),
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Find a fallback cover from sibling editions when current edition has none.
  /// Prioritizes: same language + same publisher > same language > any cover.
  String? _findFallbackCover(Map<String, dynamic> currentEdition) {
    final currentLang = _getLanguageLabel(currentEdition['language'] as String?);
    final currentPublisher =
        (currentEdition['publisher'] as String?)?.toLowerCase() ?? '';

    String? bestCover;
    int bestScore = -1;

    for (final edition in widget.editions) {
      if (identical(edition, currentEdition)) continue;
      final cover = edition['cover_url'] as String?;
      if (cover == null || cover.isEmpty) continue;

      int score = 0;
      final lang = _getLanguageLabel(edition['language'] as String?);
      if (currentLang.isNotEmpty && lang == currentLang) score += 10;
      final publisher =
          (edition['publisher'] as String?)?.toLowerCase() ?? '';
      if (currentPublisher.isNotEmpty && publisher == currentPublisher) {
        score += 5;
      }

      if (score > bestScore) {
        bestScore = score;
        bestCover = cover;
      }
    }

    return bestCover;
  }

  Widget _buildEditionSlide(Map<String, dynamic> edition, ThemeData theme) {
    var coverUrl = edition['cover_url'] as String?;
    if (coverUrl == null || coverUrl.isEmpty) {
      coverUrl = _findFallbackCover(edition);
    }
    final source = edition['source'] as String?;
    final language = edition['language'] as String?;
    final langLabel = _getLanguageLabel(language);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Robust Cover Display
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
                // 1. Gradient Fallback
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

                // 2. Network Image
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

                // 3. Source Badge Overlay
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
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
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

          const SizedBox(width: 20),

          // Metadata Column
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 8),
                if (edition['publisher'] != null &&
                    (edition['publisher'] as String).isNotEmpty)
                  _buildDetailRow(
                    Icons.apartment,
                    'Ed. ${edition['publisher']}',
                    theme,
                    isProminent: true,
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    if (edition['publication_year'] != null)
                      _buildDetailChip(
                        Icons.calendar_today,
                        edition['publication_year'].toString(),
                        theme,
                      ),
                    if (langLabel.isNotEmpty)
                      _buildDetailChip(Icons.language, langLabel, theme),
                    if (edition['isbn'] != null)
                      _buildDetailChip(Icons.qr_code, 'ISBN', theme),
                  ],
                ),

                // Display truncated summary immediately below hierarchy
                if (edition['summary'] != null &&
                    (edition['summary'] as String).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _truncateSummary(edition['summary'] as String, 120),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontStyle: FontStyle.italic,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                const Spacer(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    IconData icon,
    String value,
    ThemeData theme, {
    bool isProminent = false,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: isProminent ? 18 : 16,
          color: isProminent
              ? theme.colorScheme.primary
              : theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: isProminent
                ? theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                  )
                : theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildDetailChip(IconData icon, String label, ThemeData theme) {
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
