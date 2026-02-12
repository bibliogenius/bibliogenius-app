import 'package:flutter/material.dart';
import 'cached_book_cover.dart';
import '../theme/app_design.dart';

class SearchResultCard extends StatelessWidget {
  final Map<String, dynamic> book;
  final VoidCallback onAdd;
  final VoidCallback? onOpenUrl;

  const SearchResultCard({
    super.key,
    required this.book,
    required this.onAdd,
    this.onOpenUrl,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = book['title'] as String? ?? 'Unknown Title';
    final author = book['author'] as String? ?? 'Unknown Author';
    final publisher = book['publisher'] as String?;
    final year = book['publication_year'] as int?;
    final language = book['language'] as String?;
    final source = book['source'] as String?;
    final coverUrl = book['cover_url'] as String?;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: 160,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
        boxShadow: AppDesign.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
        child: InkWell(
          onTap: onOpenUrl,
          borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
          child: Row(
            children: [
              // Cover Section
              _buildCover(coverUrl, title, theme),

              // Info Section
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontFamily:
                              'Serif', // Use the premium font if available
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Author
                      Text(
                        author.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          letterSpacing: 0.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),

                      // Publisher & Year
                      if (publisher != null || year != null)
                        Text(
                          [
                            if (year != null) year.toString(),
                            if (publisher != null) publisher,
                          ].join(' • '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),

                      const SizedBox(height: 8),

                      // Badges Row
                      Row(
                        children: [
                          _buildSourceBadge(source, theme),
                          if (language != null) ...[
                            const SizedBox(width: 8),
                            _buildLangBadge(language, theme),
                          ],
                          const Spacer(),
                          // Add Button (Mini)
                          ElevatedButton(
                            onPressed: onAdd,
                            style: ElevatedButton.styleFrom(
                              shape: const CircleBorder(),
                              padding: const EdgeInsets.all(8),
                              backgroundColor:
                                  theme.colorScheme.primaryContainer,
                              foregroundColor:
                                  theme.colorScheme.onPrimaryContainer,
                              elevation: 0,
                            ),
                            child: const Icon(Icons.add, size: 20),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCover(String? url, String title, ThemeData theme) {
    final coverBg = theme.colorScheme.primaryContainer.withValues(alpha: 0.3);
    return Container(
      width: 100,
      height: 160,
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(AppDesign.radiusLarge),
          bottomLeft: Radius.circular(AppDesign.radiusLarge),
        ),
        color: coverBg,
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(AppDesign.radiusLarge),
          bottomLeft: Radius.circular(AppDesign.radiusLarge),
        ),
        child: CachedBookCover(
          imageUrl: url,
          fit: BoxFit.cover,
          placeholder: Container(
            color: coverBg,
            child: Center(
              child: Text(
                title.isNotEmpty ? title[0].toUpperCase() : '',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.3),
                ),
              ),
            ),
          ),
          errorWidget: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(
                    (title.hashCode & 0xFFFFFF) | 0xFF000000,
                  ).withOpacity(0.8),
                  Color(
                    (title.hashCode & 0xFFFFFF) | 0xFF000000,
                  ).withOpacity(0.4),
                ],
              ),
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSourceBadge(String? source, ThemeData theme) {
    Color color;
    String label;

    if (source == null) {
      color = Colors.blue;
      label = 'OL';
    } else if (source.contains('Inventaire')) {
      color = Colors.green;
      label = 'INV';
    } else if (source.toLowerCase().contains('bnf')) {
      color = Colors.orange;
      label = 'BNF';
    } else if (source.contains('Google')) {
      color = Colors.red;
      label = 'GB';
    } else {
      color = Colors.blue;
      label = 'OL';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        border: Border.all(color: color.withOpacity(0.5)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildLangBadge(String lang, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        lang.toUpperCase(),
        style: TextStyle(
          color: theme.colorScheme.onSurfaceVariant,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
