/// The single visual language for "not owned" (ADR-063).
///
/// One rule for every book surface (grid cards, spines, series frieze,
/// collection rows): the cover recedes through PARTIAL DESATURATION at full
/// opacity, never through transparency, which hurts legibility. A small
/// theme-token badge names the state. A wished book (`wanting`) IS a
/// not-owned book: it wears the same treatment plus its own heart marker so
/// it stays recognizable.
library;

import '../models/book.dart';

/// How a surface should mark a book's ownership state.
enum OwnershipMark { none, notOwned, wishedNotOwned }

/// Selector shared by every surface rendering a full [Book].
///
/// A book on loan is physically present and already carries its loan badge,
/// so it is never marked "not owned" on top of it.
OwnershipMark ownershipMarkOf(Book book) => ownershipMarkFromFlags(
  owned: book.owned,
  onLoan: book.isOnLoan,
  wished: book.readingStatus == 'wanting',
);

/// Same rule for surfaces that only carry flags (series frieze volumes,
/// collection rows expose `isOwned` without a reading status).
OwnershipMark ownershipMarkFromFlags({
  required bool owned,
  bool onLoan = false,
  bool wished = false,
}) {
  if (owned || onLoan) return OwnershipMark.none;
  return wished ? OwnershipMark.wishedNotOwned : OwnershipMark.notOwned;
}

/// The mark a surface should BADGE, given whether it also renders a
/// reading-status badge.
///
/// A wished book's heart is already told by its wanting status badge; on
/// surfaces rendering one, badging it again put two hearts on the same cover
/// telling the same fact. The wished mark therefore stands down there, while
/// the cover treatment (desaturation) is never affected. A plain not-owned
/// mark always badges: the status badge tells the reading story, not the
/// possession one.
OwnershipMark badgeMarkFor(
  OwnershipMark mark, {
  required bool statusBadgeShown,
}) {
  if (mark == OwnershipMark.wishedNotOwned && statusBadgeShown) {
    return OwnershipMark.none;
  }
  return mark;
}

/// Saturation kept on not-owned covers: low enough to stand out in a mixed
/// grid, high enough to keep the artwork recognizable (ADR-063 rejects
/// opacity-based attenuation).
const double notOwnedSaturation = 0.15;

/// 5x4 color matrix scaling saturation by [s] (1.0 = identity, 0.0 = full
/// grayscale), using the Rec. 709 luma weights. Fed to `ColorFilter.matrix`.
List<double> saturationMatrix(double s) {
  const lumR = 0.2126, lumG = 0.7152, lumB = 0.0722;
  final invS = 1 - s;
  final r = invS * lumR, g = invS * lumG, b = invS * lumB;
  return [
    r + s, g, b, 0, 0, //
    r, g + s, b, 0, 0, //
    r, g, b + s, 0, 0, //
    0, 0, 0, 1, 0,
  ];
}
