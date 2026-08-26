import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/curated_affinity_service.dart';
import '../services/translation_service.dart';
import '../theme/app_design.dart';
import 'cached_book_cover.dart';
import 'compact_suggestion_card.dart';
import 'suggestion_tile.dart';

/// The two shapes [CuratedListSuggestionCard] can take, one per surface.
enum CuratedCardLayout {
  /// A small fan of covers on the left, text on the right, pinned to two
  /// book-card slots. The library top slot, where the ADR-062 height budget
  /// rules.
  strip,

  /// A fan of covers with the name and the reason below it: the vocabulary
  /// the Collections screen already speaks.
  fan,

  /// A full-width row on the "Suggestions for you" page, built to that
  /// page's tile anatomy: artwork on the tile's cover footprint, text from
  /// the tile's own left edge, dismissal as a close button in the corner.
  row,
}

/// A curated list offered as a suggestion (ADR-066): a fan of the reader's
/// OWN copies of the books it shares with their library, the list's name,
/// and the reason that earned it a slot.
///
/// It suggests the LIST as an object rather than its books one by one. One
/// card per list caps the noise, the artwork says "you already have a foot
/// in this selection" with the reader's own shelf rather than publisher art,
/// and a tap opens the existing curated import flow, so there is no dead end
/// and no new flow.
///
/// BOTH shapes draw the same fan the collection cards draw, because both sit
/// beside collections and a list IS that kind of object to a reader. What
/// they do not borrow is the collection cards' accounting; see [_CoverFan].
///
/// Two shapes, one per surface, chosen by [layout]:
///
/// [CuratedCardLayout.strip] is the library slot's. Sizing follows the
/// ADR-062 strip budget: the height is the strip's, the width is two book
/// cards plus a gap, and both come from [CompactSuggestionCard]'s helpers so
/// the strip keeps one rhythm. The fan takes a little over half the height
/// for its width ([stripArtWidth]) and the text lines ellipsize in the rest.
/// The 2x2 mosaic it replaced was a square as TALL as the strip, so it took
/// 120 of the card's 168 points for itself: the name was left with 48 and
/// broke mid-word on every list, and three covers of four read as a failed
/// image load, which is the common case rather than the edge one.
///
/// [CuratedCardLayout.fan] is the Collections screen's. That budget does not
/// exist there, and the block sits directly under a grid of collection cards
/// that speak a different language: a fan of covers with the name BELOW it.
/// Two vocabularies for the same kind of object on one screen made this card
/// the odd one out, and the horizontal shape paid for it twice - the name
/// fought the artwork for width, and the 2x2 mosaic reads as a failed image
/// load at three covers of four, which is the common case rather than the
/// edge one. The fan is right at any count from one to three.
///
/// [CuratedCardLayout.row] is the "Suggestions for you" page's. That page is
/// a single blended column of [SuggestionTile]s inside one card, so a list
/// joins the column as a row rather than as an object dropped into it: same
/// cover footprint, same text offset (so the hairline separators keep
/// cutting at ONE place), same close button in the corner. The dismissal is
/// that button and not the long press the two other shapes use, because
/// every other row on the page offers one and a reader who found it there
/// would look for it here.
///
/// What the fan deliberately does NOT borrow from the collection cards is
/// their accounting: no count badge, no progress pill. "3/10" on an
/// editorial list would read as a collection the reader is a third of the
/// way through, when it is a list they own three books of.
class CuratedListSuggestionCard extends StatelessWidget {
  const CuratedListSuggestionCard({
    super.key,
    required this.affinity,
    required this.onTap,
    this.onDismiss,
    this.dismissTooltip,
    this.layout = CuratedCardLayout.strip,
  }) : assert(
         layout != CuratedCardLayout.row ||
             onDismiss == null ||
             dismissTooltip != null,
         'a dismissible row needs a translated dismissTooltip',
       );

  final CuratedAffinity affinity;
  final VoidCallback onTap;

  /// "Not interested". Absent on surfaces that offer no dismissal.
  final VoidCallback? onDismiss;

  /// Already-translated label for the row layout's close button, which is a
  /// real button and must never be unlabelled (Rules A1/A4). The two other
  /// shapes hang the dismissal on a long press and announce it as a hint
  /// instead, so they leave this null.
  final String? dismissTooltip;

  /// Which of the two shapes to draw. See [CuratedCardLayout].
  final CuratedCardLayout layout;

  /// Two book cards plus the strip's own gap, so a list card occupies an
  /// exact number of book-card slots and the strip stays on its grid.
  static double cardWidth(BuildContext context) =>
      CompactSuggestionCard.cardWidth(context) * 2 + AppDesign.spacingSm;

  static double cardHeight(BuildContext context) =>
      CompactSuggestionCard.stripHeight(context);

  /// The fan's footprint inside the strip card, width-wise: a little over
  /// half the card's height, which is what a 2:3 cover plus the tilt of the
  /// two behind it needs once the fan is laid out in the full strip height.
  /// Everything else on the card is the name and the reason, so this is the
  /// one number that decides whether they have room to be read.
  static double stripArtWidth(BuildContext context) =>
      cardHeight(context) * 0.56;

  /// Two book-card slots wide, at both of the strip's sizes, so the fan card
  /// sits on the same rhythm as everything else the app scrolls sideways.
  static double fanCardWidth(BuildContext context) =>
      CompactSuggestionCard.cardWidth(context) * 2;

  /// Room for a fanned cover plus the tilt of the two behind it. The 2:3
  /// cover inside is what actually sets its own size; this is the box it is
  /// laid out in, and it is deliberately taller than it is wide for that
  /// reason.
  static double fanArtHeight(BuildContext context) =>
      fanCardWidth(context) * 1.3;

  /// Up to three covers in the fan. Four fits a 2x2 and does not fan: the
  /// third layer already reads as "a pile", and the fourth only steepens the
  /// tilt. The payload caps at four for the strip's mosaic, so this clamps.
  static const int fanCovers = 3;

  /// The reason, in the reader's language: how many books they already have
  /// in common, and how many of those they liked.
  ///
  /// The liked half only appears when the count is non-zero. Zero liked is
  /// the common case (the liked signal is structurally sparse), and
  /// "3 books in common, 0 of them liked" would read as an accusation.
  static String reasonLabel(BuildContext context, CuratedAffinity affinity) {
    if (affinity.likedCount > 0) {
      return TranslationService.translate(
        context,
        'curated_affinity_reason_liked',
        params: {
          'owned': '${affinity.ownedCount}',
          'liked': '${affinity.likedCount}',
        },
      );
    }
    return TranslationService.translate(
      context,
      'curated_affinity_reason',
      params: {'owned': '${affinity.ownedCount}'},
    );
  }

  /// The card's single screen-reader announcement (Rule A1, and the ADR-061
  /// A2 rule that nothing nested gains its own node): the list name, the
  /// reason, and the source, none of which is spoken by the mosaic.
  static String semanticsLabel(
    BuildContext context,
    CuratedAffinity affinity,
    String title,
  ) {
    return [
      title,
      reasonLabel(context, affinity),
      TranslationService.translate(context, 'suggestion_badge_editorial'),
    ].join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    final title = affinity.list.getTitle(locale);
    final theme = Theme.of(context);

    // The row owns its Semantics rather than taking the shared wrapper: its
    // close button sits OUTSIDE the excluded subtree, and a button excluded
    // from semantics is a button a screen reader cannot reach.
    if (layout == CuratedCardLayout.row) {
      return _buildRow(context, theme, title);
    }

    return Semantics(
      button: true,
      excludeSemantics: true,
      label: semanticsLabel(context, affinity, title),
      // The card carries its own actions because `excludeSemantics` drops
      // the InkWell's. A tap is synthesized back by the platform when a node
      // advertises none, so it survived unnoticed; a LONG PRESS is not, so
      // the dismissal existed for a finger and for nothing else. The hint
      // names the gesture, in the wording the dismiss button uses on every
      // other suggestion surface.
      onTap: onTap,
      onLongPress: onDismiss,
      onLongPressHint: onDismiss == null
          ? null
          : TranslationService.translate(
              context,
              'recommendation_not_interested',
            ),
      child: switch (layout) {
        CuratedCardLayout.strip => _buildStrip(context, theme, title),
        CuratedCardLayout.fan => _buildFan(context, theme, title),
        // Returned above: the row never reaches this wrapper.
        CuratedCardLayout.row => const SizedBox.shrink(),
      },
    );
  }

  /// The "Suggestions for you" page's shape: one row of the same anatomy as
  /// every book tile on that page.
  Widget _buildRow(BuildContext context, ThemeData theme, String title) {
    final dismiss = onDismiss;

    return Stack(
      children: [
        Semantics(
          button: true,
          excludeSemantics: true,
          label: semanticsLabel(context, affinity, title),
          onTap: onTap,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: 10,
                horizontal: SuggestionTile.horizontalPadding,
              ),
              child: Row(
                // Top-aligned like the book tiles, so the artwork lines up
                // with the name whatever the reason line does below it.
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: SuggestionTile.coverWidth,
                    height: SuggestionTile.coverHeight,
                    child: _CoverFan(
                      coverUrls: affinity.ownedCoverUrls
                          .take(fanCovers)
                          .toList(growable: false),
                      layerScale:
                          SuggestionTile.coverWidth / fanCardWidth(context),
                      // The page words the source in a chip under the name,
                      // where every other row on it carries its own.
                      showSourceBadge: false,
                    ),
                  ),
                  const SizedBox(width: SuggestionTile.coverGap),
                  Expanded(
                    child: Padding(
                      // Keeps the name clear of the close button parked in
                      // the corner of the Stack. The tile's own figure.
                      padding: EdgeInsets.only(right: dismiss != null ? 28 : 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            reasonLabel(context, affinity),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          // The page's own source vocabulary, the one the
                          // external cards already wear, so a list is told
                          // apart from a book by its wording rather than by
                          // a shape the reader has to learn.
                          SuggestionSourceBadge(
                            label: TranslationService.translate(
                              context,
                              'suggestion_badge_editorial',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (dismiss != null)
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              icon: const Icon(Icons.close, size: 16),
              iconSize: 16,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: dismissTooltip,
              color: theme.colorScheme.onSurfaceVariant,
              onPressed: dismiss,
            ),
          ),
      ],
    );
  }

  /// The library slot's shape: mosaic left, text right, on two book slots.
  Widget _buildStrip(BuildContext context, ThemeData theme, String title) {
    return SizedBox(
      width: cardWidth(context),
      height: cardHeight(context),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.4),
          ),
          borderRadius: BorderRadius.circular(AppDesign.radiusSmall),
        ),
        child: InkWell(
          onTap: onTap,
          onLongPress: onDismiss,
          child: Row(
            children: [
              Padding(
                // The pile leans past its own cover on both sides, so it
                // keeps a hair of clearance from the card's clipped edge.
                padding: const EdgeInsets.only(left: 4),
                child: SizedBox(
                  width: stripArtWidth(context),
                  height: cardHeight(context),
                  child: _CoverFan(
                    coverUrls: affinity.ownedCoverUrls
                        .take(fanCovers)
                        .toList(growable: false),
                    // The tilt offsets are in points, tuned for the fan
                    // card's cover: shrink the card, shrink the lean, or a
                    // pile a third of the size fans twice as wide.
                    layerScale: stripArtWidth(context) / fanCardWidth(context),
                    // The word "Selection" rides in the text column here,
                    // and the badge is wider than this fan's front cover.
                    showSourceBadge: false,
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.auto_stories_outlined,
                            size: 12,
                            color: theme.colorScheme.tertiary,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              TranslationService.translate(
                                context,
                                'suggestion_badge_editorial',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.tertiary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        reasonLabel(context, affinity),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.15,
                        ),
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

  /// The Collections screen's shape: the fan, the list name under it, and
  /// the reason under that.
  ///
  /// No surface and no outline of its own, unlike the strip card: the block
  /// around it already draws one, and the collection cards it sits beneath
  /// are bare artwork over the page too.
  Widget _buildFan(BuildContext context, ThemeData theme, String title) {
    return SizedBox(
      width: fanCardWidth(context),
      child: InkWell(
        onTap: onTap,
        onLongPress: onDismiss,
        borderRadius: BorderRadius.circular(AppDesign.radiusSmall),
        // The card sizes itself from its content, so a reader at 200% text
        // size gets taller cards rather than a clipped reason line.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: fanArtHeight(context),
              child: _CoverFan(
                coverUrls: affinity.ownedCoverUrls
                    .take(fanCovers)
                    .toList(growable: false),
              ),
            ),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              // The collection cards' own name style, to the letter: this
              // block is read as part of that grid, not as a visitor in it.
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                  height: 1.15,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                reasonLabel(context, affinity),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The reader's own copies, up to three, fanned like a small pile.
///
/// The tilts, offsets and cover ratio are the collection cards' own, so the
/// two families of card read as one. What is NOT borrowed is everything that
/// counts something: the collection tag says COLLECTION, the badge counts
/// books, the pill tracks ownership, and all three would be lies here. The
/// only marker kept is the source, because ADR-059 asks every suggestion to
/// say where it comes from, and it says SELECTION instead.
///
/// Deliberately NOT falling back to the list's own remote `cover_url` when
/// the reader owns no cover: the fan exists to say "these are books you
/// already have", and publisher art for a list the reader does not own would
/// say the opposite while costing a network fetch inside a scrolling strip.
class _CoverFan extends StatelessWidget {
  const _CoverFan({
    required this.coverUrls,
    this.layerScale = 1.0,
    this.showSourceBadge = true,
  });

  final List<String> coverUrls;

  /// Multiplies the tilt offsets, which are points rather than ratios. 1.0
  /// is the fan card's own size; the strip's smaller fan scales them down.
  final double layerScale;

  /// The strip card words the source in its text column instead, and turns
  /// this off: the badge is wider than the front cover at that size.
  final bool showSourceBadge;

  /// The three front layers of the collection cards' fan: [tilt, dx, dy].
  static const List<List<double>> _layers = [
    [-5.0, -7.0, -3.0],
    [6.0, 8.0, -1.0],
    [0.0, 0.0, 0.0],
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // One layer is always drawn: with no cover at all it is the placeholder.
    final visible = math.max(1, math.min(coverUrls.length, _layers.length));
    final layers = _layers.sublist(_layers.length - visible);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availW = constraints.maxWidth;
        final availH = constraints.maxHeight;
        // A lone cover fills more of the box; a fan leaves room for the tilt.
        final coverW = availW * (visible == 1 ? 0.94 : 0.82);
        final coverH = math.min(availH * 0.94, coverW / 0.67);

        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < visible; i++)
              _FanLayer(
                coverUrl: i < coverUrls.length ? coverUrls[i] : null,
                config: layers[i],
                layerScale: layerScale,
                coverW: coverW,
                coverH: coverH,
                isTop: i == visible - 1,
              ),
            // The source marker, where the collection cards put their type
            // tag: the top-right of the front cover. Wording, not an icon,
            // and it is in the card's screen-reader label too.
            if (showSourceBadge)
              Positioned(
                top: (availH - coverH) / 2 + 4,
                right: (availW - coverW) / 2 + 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.tertiary,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    TranslationService.translate(
                      context,
                      'suggestion_badge_editorial',
                    ).toUpperCase(),
                    style: TextStyle(
                      color: theme.colorScheme.onTertiary,
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      height: 1,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// One cover of the fan, tilted and shadowed. A null URL draws the same
/// placeholder the mosaic uses, so both layouts fail identically.
class _FanLayer extends StatelessWidget {
  const _FanLayer({
    required this.coverUrl,
    required this.config,
    required this.layerScale,
    required this.coverW,
    required this.coverH,
    required this.isTop,
  });

  final String? coverUrl;
  final List<double> config;
  final double layerScale;
  final double coverW;
  final double coverH;
  final bool isTop;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Transform.translate(
      offset: Offset(config[1] * layerScale, config[2] * layerScale),
      child: Transform.rotate(
        angle: config[0] * math.pi / 180,
        child: Container(
          width: coverW,
          height: coverH,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isTop ? 0.28 : 0.14),
                blurRadius: isTop ? 14 : 6,
                spreadRadius: isTop ? 0 : -1,
                offset: Offset(isTop ? 2 : 1, isTop ? 5 : 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: coverUrl == null
                ? ColoredBox(
                    color: colorScheme.surfaceContainerHigh,
                    child: Center(
                      child: Icon(
                        Icons.collections_bookmark_outlined,
                        size: coverW * 0.34,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                // Decorative: the card's own Semantics names the list.
                : CachedBookCover(
                    imageUrl: coverUrl,
                    width: coverW,
                    height: coverH,
                    fit: BoxFit.cover,
                  ),
          ),
        ),
      ),
    );
  }
}
