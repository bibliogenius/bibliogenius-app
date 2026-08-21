import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../data/repositories/collection_repository.dart';
import '../models/collection.dart';
import '../models/collection_book.dart';
import '../services/translation_service.dart';
import '../utils/series_ordering.dart';
import 'app_snack_bar.dart';
import 'cached_book_cover.dart';
import 'dashboard_section.dart';
import 'volume_badge.dart';

/// Reading-order timeline ("frise") for a series-typed collection, shown on the
/// book-detail screen. Volumes are laid out left-to-right by `volumeNumber`;
/// unread volumes are dimmed and unowned volumes carry a distinct "wanted"
/// treatment, so a reader sees at a glance where they are in the cycle and what
/// is still missing from the shelf.
///
/// The frise is also an editing surface: long-press a cover to drag it into a
/// new position (renumbering the volumes 1..N), or tap the number pill to set a
/// value explicitly. This mirrors the collection detail screen via the shared
/// helpers in `series_ordering.dart`.
///
/// Renders nothing until at least two volumes exist: a one-cover timeline
/// carries no information.
class SeriesFriezeWidget extends StatefulWidget {
  final Collection collection;

  /// UUID of the book whose detail page is showing this frise; that volume is
  /// highlighted as the current position in the series.
  final String currentBookId;

  const SeriesFriezeWidget({
    super.key,
    required this.collection,
    required this.currentBookId,
  });

  @override
  State<SeriesFriezeWidget> createState() => _SeriesFriezeWidgetState();
}

class _SeriesFriezeWidgetState extends State<SeriesFriezeWidget> {
  List<CollectionBook>? _volumes;

  CollectionRepository get _repo =>
      Provider.of<CollectionRepository>(context, listen: false);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final volumes = await _repo.getCollectionBooks(widget.collection.id);
      if (mounted) setState(() => _volumes = volumes);
    } catch (_) {
      // Leave the frise hidden on a load error rather than surfacing noise on
      // the book detail; the collection screen is the place to manage a series.
      if (mounted) setState(() => _volumes = const []);
    }
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    final current = _volumes;
    if (current == null) return;
    final updated = reorderedSequentialVolumes(current, oldIndex, newIndex);
    // Defer the tree mutation off the pointer-up handler to avoid the desktop
    // mouse_tracker re-entrancy assertion (see collection detail screen).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _volumes = updated);
    });
    try {
      await persistVolumeNumbers(_repo, widget.collection.id, updated, current);
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(
          context,
          '${TranslationService.translate(context, 'error')}: $e',
        );
        _load();
      }
    }
  }

  Future<void> _editVolume(CollectionBook book) async {
    final result = await showVolumeEditor(context, current: book.volumeNumber);
    if (result == null || !mounted) return;
    try {
      await _repo.setBookVolumeNumber(
        widget.collection.id,
        book.bookId,
        result.volumeNumber,
      );
      await _load(); // reload so the strip re-sorts by the new number
    } catch (e) {
      if (mounted) {
        AppSnackBar.error(
          context,
          '${TranslationService.translate(context, 'error')}: $e',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final volumes = _volumes ?? const [];
    // A timeline needs at least two volumes; otherwise show nothing (and stay
    // invisible while loading rather than reserve space).
    if (volumes.length < 2) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // "Série {name}" is one parameterized string, not a label
          // concatenated with the raw collection name: word order and
          // separator are not universal across catalogues. Truncated at
          // one line (unlike the other frieze headings): the collection
          // name is arbitrary, unbounded data, not a fixed UI string.
          FriezeSectionHeader(
            icon: Icons.auto_stories_outlined,
            title: TranslationService.translate(
              context,
              'series_frieze_title_named',
              params: {'name': widget.collection.name},
            ),
            maxLines: 1,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 172,
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              onReorder: _onReorder,
              itemCount: volumes.length,
              // Custom handle only (see _VolumeTile): the default handle renders
              // over the title on desktop.
              buildDefaultDragHandles: false,
              // Drag the cover itself, without the default Material lift, so the
              // dragged proxy matches the strip.
              proxyDecorator: (child, index, animation) => child,
              itemBuilder: (context, index) {
                final volume = volumes[index];
                return _VolumeTile(
                  key: ValueKey(volume.bookId),
                  index: index,
                  volume: volume,
                  isCurrent: volume.bookId == widget.currentBookId,
                  onEditVolume: () => _editVolume(volume),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// A single cover in the frise: read/unread dimming, an owned/wanted treatment,
/// the volume number pill (tappable to edit), and current-volume highlighting.
class _VolumeTile extends StatelessWidget {
  final int index;
  final CollectionBook volume;
  final bool isCurrent;
  final VoidCallback onEditVolume;

  const _VolumeTile({
    super.key,
    required this.index,
    required this.volume,
    required this.isCurrent,
    required this.onEditVolume,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final coverOpacity = volume.isRead ? 1.0 : 0.4;

    final statusWord = volume.isRead
        ? TranslationService.translate(context, 'series_read')
        : TranslationService.translate(context, 'series_unread');
    final ownershipWord = volume.isOwned
        ? TranslationService.translate(context, 'status_owned')
        : TranslationService.translate(context, 'status_wanted');
    final numberWord = volume.volumeNumber != null
        ? '${TranslationService.translate(context, 'series_volume_abbrev')} ${volume.volumeNumber}'
        : TranslationService.translate(context, 'series_unnumbered');
    final semanticLabel =
        '$numberWord, ${volume.title}, $statusWord, $ownershipWord'
        '${isCurrent ? ', ${TranslationService.translate(context, 'series_current_volume')}' : ''}';

    final borderColor = isCurrent
        ? theme.colorScheme.primary
        : (volume.isOwned
              ? Colors.transparent
              : theme.colorScheme.tertiary.withValues(alpha: 0.7));

    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: SizedBox(
        width: 92,
        child: Semantics(
          button: true,
          label: semanticLabel,
          child: InkWell(
            onTap: () => context.push('/books/${volume.bookId}'),
            borderRadius: BorderRadius.circular(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: borderColor,
                          width: isCurrent ? 2.5 : 1.5,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Opacity(
                          opacity: coverOpacity,
                          child: CachedBookCover(
                            imageUrl: volume.coverUrl,
                            width: 86,
                            height: 120,
                            semanticLabel: null,
                          ),
                        ),
                      ),
                    ),
                    // Volume number pill, tappable to edit (same as the
                    // collection detail list).
                    Positioned(
                      top: 3,
                      left: 3,
                      child: VolumeBadge(
                        volumeNumber: volume.volumeNumber,
                        onTap: onEditVolume,
                      ),
                    ),
                    // Unowned marker: a "wanted" bookmark badge so a missing
                    // volume reads differently from an owned one.
                    if (!volume.isOwned)
                      Positioned(
                        top: 3,
                        right: 3,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.tertiaryContainer,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.bookmark_add_outlined,
                            size: 13,
                            color: theme.colorScheme.onTertiaryContainer,
                          ),
                        ),
                      ),
                    // Drag handle on the cover: grab it to reorder. Sits on the
                    // cover (not below) so it never overlaps the title, and uses
                    // an immediate listener so a grab starts the drag right away
                    // while the rest of the strip still scrolls and taps.
                    Positioned(
                      bottom: 4,
                      left: 0,
                      right: 0,
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: ReorderableDragStartListener(
                          index: index,
                          child: Tooltip(
                            message: TranslationService.translate(
                              context,
                              'series_reorder_handle',
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Icon(
                                Icons.drag_indicator,
                                size: 15,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  volume.title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: volume.isRead ? null : Colors.grey,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
