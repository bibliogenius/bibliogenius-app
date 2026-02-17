import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/translation_service.dart';
import '../screens/audio_webview_screen.dart';
import '../models/audio_resource.dart';
import '../providers/audio_provider.dart';
import 'audio_player_widget.dart';

/// Self-contained audio section widget for book details screen.
///
/// This widget handles all audio-related UI logic:
/// - Checks if audio module is enabled
/// - Triggers audiobook search if needed (multi-language)
/// - Shows appropriate state (searching, not found, WiFi required, player)
/// - If multiple results, shows ChoiceChips to switch between versions
///
/// Usage:
/// ```dart
/// AudioSection(
///   bookId: book.id!,
///   bookTitle: book.title,
///   bookAuthor: book.author,
///   bookLanguage: book.language,
///   userLanguages: ['fr', 'en'],
/// )
/// ```
class AudioSection extends StatefulWidget {
  final int bookId;
  final String bookTitle;
  final String? bookAuthor;

  /// Language of the book (e.g., 'fr', 'en', 'French', 'English').
  /// Used to filter audiobook results to match the book's language.
  final String? bookLanguage;

  /// User's reading languages (from ThemeProvider.userLanguages).
  /// Combined with bookLanguage to search across all relevant languages.
  final List<String> userLanguages;

  const AudioSection({
    super.key,
    required this.bookId,
    required this.bookTitle,
    this.bookAuthor,
    this.bookLanguage,
    this.userLanguages = const [],
  });

  @override
  State<AudioSection> createState() => _AudioSectionState();
}

class _AudioSectionState extends State<AudioSection> {
  bool _searchTriggered = false;
  int _selectedIndex = 0;

  /// Build the deduplicated list of search languages.
  /// Combines book language + user languages, normalized to ISO 639-1.
  List<String> get _searchLanguages {
    final langs = <String>{};
    if (widget.bookLanguage != null && widget.bookLanguage!.isNotEmpty) {
      langs.add(_normalizeLanguageCode(widget.bookLanguage!));
    }
    for (final lang in widget.userLanguages) {
      langs.add(_normalizeLanguageCode(lang));
    }
    if (langs.isEmpty) {
      // Fallback: use UI locale
      final uiLang = Localizations.localeOf(context).languageCode;
      langs.add(uiLang);
    }
    return langs.toList();
  }

  /// Normalize ISO 639-2 (3-letter) codes to ISO 639-1 (2-letter).
  String _normalizeLanguageCode(String code) {
    final lower = code.toLowerCase().trim();
    const iso639_2to1 = {
      'fre': 'fr', 'fra': 'fr', 'french': 'fr',
      'eng': 'en', 'english': 'en',
      'spa': 'es', 'spanish': 'es',
      'ger': 'de', 'deu': 'de', 'german': 'de',
      'ita': 'it', 'italian': 'it',
      'por': 'pt', 'portuguese': 'pt',
      'dut': 'nl', 'nld': 'nl', 'dutch': 'nl',
      'rus': 'ru', 'russian': 'ru',
      'chi': 'zh', 'zho': 'zh', 'chinese': 'zh',
      'jpn': 'ja', 'japanese': 'ja',
    };
    return iso639_2to1[lower] ?? lower;
  }

  void _triggerSearchIfNeeded(AudioProvider provider) {
    // Re-arm if cache was cleared externally (e.g. metadata refresh)
    if (_searchTriggered &&
        !provider.hasSearched(widget.bookId) &&
        !provider.isSearching(widget.bookId)) {
      _searchTriggered = false;
    }
    if (_searchTriggered) return;
    if (!provider.isInitialized) return;
    if (!provider.isEnabled) return;
    if (provider.hasSearched(widget.bookId)) return;

    _searchTriggered = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final languages = _searchLanguages;
      debugPrint('[AudioSection] bookLanguage=${widget.bookLanguage}, userLanguages=${widget.userLanguages}, searchLanguages=$languages');
      if (languages.length > 1) {
        provider.searchAudiobookMultiLang(
          bookId: widget.bookId,
          title: widget.bookTitle,
          author: widget.bookAuthor,
          languages: languages,
        );
      } else {
        provider.searchAudiobook(
          bookId: widget.bookId,
          title: widget.bookTitle,
          author: widget.bookAuthor,
          preferredLanguage: languages.firstOrNull,
        );
      }
    });
  }

  void _forceRefresh() {
    final provider = context.read<AudioProvider>();
    provider.clearBookCache(widget.bookId);
    _searchTriggered = false;
    setState(() => _selectedIndex = 0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final languages = _searchLanguages;
      if (languages.length > 1) {
        provider.searchAudiobookMultiLang(
          bookId: widget.bookId,
          title: widget.bookTitle,
          author: widget.bookAuthor,
          languages: languages,
          forceRefresh: true,
        );
      } else {
        provider.searchAudiobook(
          bookId: widget.bookId,
          title: widget.bookTitle,
          author: widget.bookAuthor,
          preferredLanguage: languages.firstOrNull,
          forceRefresh: true,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AudioProvider>();

    debugPrint('[AudioSection] build: bookId=${widget.bookId}, enabled=${provider.isEnabled}, initialized=${provider.isInitialized}, searching=${provider.isSearching(widget.bookId)}, hasSearched=${provider.hasSearched(widget.bookId)}');

    // Don't show anything if module is disabled
    if (!provider.isEnabled) return const SizedBox.shrink();

    // Wait for initialization
    if (!provider.isInitialized) return const SizedBox.shrink();

    // Trigger search if not yet done
    _triggerSearchIfNeeded(provider);

    // Check if searching
    if (provider.isSearching(widget.bookId)) {
      return _buildSearchingState(context);
    }

    // Get all cached results
    final audioResources = provider.getAudioResources(widget.bookId);

    // No audiobook found
    if (audioResources.isEmpty) {
      if (provider.hasSearched(widget.bookId)) {
        return const SizedBox.shrink(); // Silently hide if not found
      }
      return const SizedBox.shrink();
    }

    // Clamp selected index
    final safeIndex = _selectedIndex.clamp(0, audioResources.length - 1);
    final selectedResource = audioResources[safeIndex];

    // Check WiFi for streaming
    if (!provider.isWifiConnected) {
      return _buildWifiRequiredState(context, selectedResource);
    }

    // Show player (with optional language/source selector)
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (audioResources.length > 1)
            _buildVersionSelector(context, audioResources, safeIndex),
          GestureDetector(
            onLongPress: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(TranslationService.translate(context, 'audio_refreshing')),
                  action: SnackBarAction(
                    label: TranslationService.translate(context, 'audio_refresh'),
                    onPressed: _forceRefresh,
                  ),
                ),
              );
            },
            child: AudioPlayerWidget(
              key: ValueKey(selectedResource.sourceId),
              audioResource: selectedResource,
              onOpenInBrowser: () => _openInBrowser(selectedResource),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVersionSelector(
    BuildContext context,
    List<AudioResource> resources,
    int currentIndex,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        height: 36,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: resources.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final resource = resources[index];
            final isSelected = index == currentIndex;
            final label = _buildChipLabel(resource);
            return ChoiceChip(
              label: Text(label),
              selected: isSelected,
              onSelected: (selected) {
                if (selected) setState(() => _selectedIndex = index);
              },
              labelStyle: TextStyle(
                fontSize: 12,
                color: isSelected
                    ? colorScheme.onPrimary
                    : colorScheme.onSurfaceVariant,
              ),
              selectedColor: colorScheme.primary,
              backgroundColor: colorScheme.surfaceContainerHighest,
              visualDensity: VisualDensity.compact,
            );
          },
        ),
      ),
    );
  }

  String _buildChipLabel(AudioResource resource) {
    final lang = resource.language ?? '';
    final source = resource.source.displayName;
    if (lang.isNotEmpty) {
      return '$lang - $source';
    }
    return source;
  }

  Widget _buildSearchingState(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outline.withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                TranslationService.translate(context, 'audio_searching'),
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWifiRequiredState(
    BuildContext context,
    AudioResource audioResource,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.tertiaryContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outline.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.headphones, size: 18, color: colorScheme.tertiary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    TranslationService.translate(context, 'audio_available'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onTertiaryContainer,
                    ),
                  ),
                ),
                Text(
                  audioResource.source.displayName,
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onTertiaryContainer.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.wifi_off,
                  size: 16,
                  color: colorScheme.onTertiaryContainer.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    TranslationService.translate(context, 'audio_wifi_required'),
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onTertiaryContainer.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _openInBrowser(audioResource),
                  icon: const Icon(Icons.open_in_new, size: 14),
                  label: Text(TranslationService.translate(context, 'audio_open')),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openInBrowser(AudioResource resource) {
    final url = resource.streamUrl?.isNotEmpty == true
        ? resource.streamUrl!
        : resource.source.websiteUrl;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) =>
            AudioWebViewScreen(url: url, title: resource.title),
      ),
    );
  }
}
