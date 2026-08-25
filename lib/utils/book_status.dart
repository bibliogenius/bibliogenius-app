import 'package:flutter/material.dart';
import '../services/translation_service.dart';

class BookStatus {
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  const BookStatus({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });
}

/// The value a book carries when the reader recorded no reading intent: they
/// own it, have not read it, are not reading it, and have not planned to.
///
/// Spelled as the empty string, never null: the column behind it is NOT NULL,
/// and a book decoded from any payload always carries the field. The Rust
/// write gate accepts it alongside the five reading statuses
/// (`models::book::NO_READING_STATUS`).
const String noReadingStatus = '';

/// Whether [value] names an actual reading status.
///
/// Badges key on this rather than on a null check: a book whose status was
/// explicitly cleared holds an empty string, and a badge built for it prints
/// an untranslated `reading_status_` and claims a state the book does not have.
bool hasReadingStatus(String? value) =>
    value != null && value != noReadingStatus;

// Status options for individual/personal libraries. The last entry is the
// absence of a status, offered like any other choice: without it, clearing a
// status is only reachable by guessing that re-tapping the active chip undoes
// it.
const List<BookStatus> individualStatuses = [
  BookStatus(
    value: 'to_read',
    label: 'to_read_status',
    icon: Icons.bookmark_border,
    color: Colors.orange,
  ),
  BookStatus(
    value: 'reading',
    label: 'currently_reading',
    icon: Icons.auto_stories,
    color: Colors.blue,
  ),
  BookStatus(
    value: 'read',
    label: 'read_status',
    icon: Icons.check_circle,
    color: Colors.green,
  ),
  BookStatus(
    value: 'wanting',
    label: 'wishlist_status',
    icon: Icons.favorite_border,
    color: Colors.red,
  ),
  BookStatus(
    value: noReadingStatus,
    label: 'no_reading_status',
    icon: Icons.remove_circle_outline,
    color: Colors.blueGrey,
  ),
];

// Status options for librarian/professional cataloging
const List<BookStatus> librarianStatuses = [
  BookStatus(
    value: 'available',
    label: 'status_available',
    icon: Icons.check_circle_outline,
    color: Colors.green,
  ),
  BookStatus(
    value: 'checked_out',
    label: 'status_checked_out',
    icon: Icons.exit_to_app,
    color: Colors.blue,
  ),
  BookStatus(
    value: 'reference_only',
    label: 'status_reference',
    icon: Icons.lock_outline,
    color: Colors.amber,
  ),
  BookStatus(
    value: 'missing',
    label: 'status_missing',
    icon: Icons.error_outline,
    color: Colors.red,
  ),
  BookStatus(
    value: 'damaged',
    label: 'status_damaged',
    icon: Icons.build_outlined,
    color: Colors.deepOrange,
  ),
  BookStatus(
    value: 'on_order',
    label: 'status_on_order',
    icon: Icons.shopping_cart_outlined,
    color: Colors.indigo,
  ),
];

/// The `.po` key naming a raw `books.reading_status` value, or null when the
/// value belongs to no vocabulary we know.
///
/// Covers more than the five stored reading statuses on purpose: the column is
/// also reached by cr-sqlite replication and by the possession values older
/// payloads overlaid onto it, so a tally over it meets tokens the picker never
/// offers. A null return is the caller's cue to fall back on the raw token
/// rather than draw an anonymous slice.
String? readingStatusLabelKey(String status) {
  switch (status) {
    case noReadingStatus:
      return 'no_reading_status';
    case 'read':
      return 'reading_status_read';
    case 'reading':
      return 'reading_status_reading';
    case 'to_read':
      return 'reading_status_to_read';
    case 'wanting':
      return 'reading_status_wanting';
    case 'abandoned':
      return 'reading_status_abandoned';
    case 'owned':
      return 'owned_status';
    case 'lent':
      return 'reading_status_lent';
    case 'borrowed':
      return 'reading_status_borrowed';
    default:
      return null;
  }
}

/// The translated label for a raw `books.reading_status` value, falling back to
/// a readable form of the token itself for a value we cannot name.
String readingStatusLabel(BuildContext context, String status) {
  final key = readingStatusLabelKey(status);
  return key == null
      ? status.replaceAll('_', ' ')
      : TranslationService.translate(context, key);
}

/// Groups [statuses] into the buckets the reading-status chart draws.
///
/// Both spellings of "nothing recorded" fold onto one bucket: a status the
/// reader cleared is the empty string, a status absent from a decoded payload
/// is null, and drawing them apart would put two unnamed slices side by side.
Map<String, int> tallyReadingStatuses(Iterable<String?> statuses) {
  final counts = <String, int>{};
  for (final status in statuses) {
    final key = hasReadingStatus(status) ? status! : noReadingStatus;
    counts[key] = (counts[key] ?? 0) + 1;
  }
  return counts;
}

// Get status options. When useInventoryStatuses is true, returns the
// cataloguing list (available/checked_out/...); otherwise the personal
// reading list (to_read/reading/read/...).
List<BookStatus> getStatusOptions(
  BuildContext context,
  bool useInventoryStatuses,
) {
  final options = useInventoryStatuses ? librarianStatuses : individualStatuses;
  return options
      .map(
        (s) => BookStatus(
          value: s.value,
          label: TranslationService.translate(context, s.label),
          icon: s.icon,
          color: s.color,
        ),
      )
      .toList();
}

// Get BookStatus object from value
BookStatus? getStatusFromValue(
  BuildContext context,
  String value,
  bool useInventoryStatuses,
) {
  final options = getStatusOptions(context, useInventoryStatuses);
  try {
    return options.firstWhere((s) => s.value == value);
  } catch (e) {
    return null;
  }
}

// Default status when creating a new book.
String getDefaultStatus(bool useInventoryStatuses) {
  return useInventoryStatuses ? 'available' : 'to_read';
}

/// Show a bottom sheet to pick a reading status.
/// Returns the selected status value, or null if dismissed.
Future<String?> showReadingStatusPicker(
  BuildContext context, {
  required String? currentStatus,
  required bool useInventoryStatuses,
}) {
  final options = getStatusOptions(context, useInventoryStatuses);

  return showModalBottomSheet<String>(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                TranslationService.translate(
                  context,
                  'reading_status_picker_title',
                ),
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            ...options.map((status) {
              final isSelected = status.value == (currentStatus ?? '');
              return ListTile(
                leading: Icon(status.icon, color: status.color),
                title: Text(status.label),
                trailing: isSelected
                    ? Icon(Icons.check, color: cs.primary)
                    : null,
                onTap: () => Navigator.of(ctx).pop(status.value),
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}
