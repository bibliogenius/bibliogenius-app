import 'package:flutter/material.dart';

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
    label: 'To Read',
    icon: Icons.bookmark_border,
    color: Colors.orange,
  ),
  BookStatus(
    value: 'reading',
    label: 'Reading',
    icon: Icons.auto_stories,
    color: Colors.blue,
  ),
  BookStatus(
    value: 'read',
    label: 'Read',
    icon: Icons.check_circle,
    color: Colors.green,
  ),
  BookStatus(
    value: 'wanted',
    label: 'Wanted',
    icon: Icons.favorite_border,
    color: Colors.red,
  ),
  BookStatus(
    value: 'borrowed',
    label: 'Borrowed (lent out)',
    icon: Icons.people_outline,
    color: Colors.purple,
  ),
];

// Status options for librarian/professional cataloging
const List<BookStatus> librarianStatuses = [
  BookStatus(
    value: 'available',
    label: 'Available',
    icon: Icons.check_circle_outline,
    color: Colors.green,
  ),
  BookStatus(
    value: 'checked_out',
    label: 'Checked Out',
    icon: Icons.exit_to_app,
    color: Colors.blue,
  ),
  BookStatus(
    value: 'reference_only',
    label: 'Reference Only',
    icon: Icons.lock_outline,
    color: Colors.amber,
  ),
  BookStatus(
    value: 'missing',
    label: 'Missing/Lost',
    icon: Icons.error_outline,
    color: Colors.red,
  ),
  BookStatus(
    value: 'damaged',
    label: 'Damaged/Repair',
    icon: Icons.build_outlined,
    color: Colors.deepOrange,
  ),
  BookStatus(
    value: 'on_order',
    label: 'On Order',
    icon: Icons.shopping_cart_outlined,
    color: Colors.indigo,
  ),
];

// Get status options based on profile type
List<BookStatus> getStatusOptions(bool isLibrarian) {
  return isLibrarian ? librarianStatuses : individualStatuses;
}

// Get BookStatus object from value
BookStatus? getStatusFromValue(String value, bool isLibrarian) {
  final options = getStatusOptions(isLibrarian);
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
