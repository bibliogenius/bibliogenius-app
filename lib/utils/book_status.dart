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

// Status options for individual/personal libraries
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
    value: 'wanted',
    label: 'wishlist_status',
    icon: Icons.favorite_border,
    color: Colors.red,
  ),
  BookStatus(
    value: 'borrowed',
    label: 'borrowed_status',
    icon: Icons.arrow_downward,
    color: Colors.teal,
  ),
  BookStatus(
    value: 'lent',
    label: 'lent_status',
    icon: Icons.arrow_upward,
    color: Colors.purple,
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

// Get status options based on profile type
List<BookStatus> getStatusOptions(BuildContext context, bool isLibrarian) {
  final options = isLibrarian ? librarianStatuses : individualStatuses;
  return options.map((s) => BookStatus(
    value: s.value,
    label: TranslationService.translate(context, s.label),
    icon: s.icon,
    color: s.color,
  )).toList();
}

// Get BookStatus object from value
BookStatus? getStatusFromValue(BuildContext context, String value, bool isLibrarian) {
  final options = getStatusOptions(context, isLibrarian);
  try {
    return options.firstWhere((s) => s.value == value);
  } catch (e) {
    return null;
  }
}

// Default status based on profile type
String getDefaultStatus(bool isLibrarian) {
  return isLibrarian ? 'available' : 'to_read';
}
