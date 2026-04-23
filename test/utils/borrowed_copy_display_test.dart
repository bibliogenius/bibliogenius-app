import 'package:bibliogenius/utils/borrowed_copy_display.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BorrowedCopyDisplay.fromBookMap (ADR-034)', () {
    test('reads typed columns when present', () {
      final display = BorrowedCopyDisplay.fromBookMap({
        'lender_display_name': 'Alice',
        'borrow_due_date': '2026-12-01',
        'borrow_source': 'peer',
        'notes': null,
      });

      expect(display.lenderName, 'Alice');
      expect(display.dueDate, '2026-12-01');
    });

    test('contact loan has lender name but empty due date', () {
      final display = BorrowedCopyDisplay.fromBookMap({
        'lender_display_name': 'Bob',
        'borrow_source': 'contact',
      });

      expect(display.lenderName, 'Bob');
      expect(display.dueDate, '');
    });

    test('falls back to legacy FR peer notes when new columns null', () {
      final display = BorrowedCopyDisplay.fromBookMap({
        'lender_display_name': null,
        'borrow_due_date': null,
        'notes': "Emprunté de Charlie jusqu'au 2026-11-15",
      });

      expect(display.lenderName, 'Charlie');
      expect(display.dueDate, '2026-11-15');
    });

    test('falls back to legacy EN contact notes', () {
      final display = BorrowedCopyDisplay.fromBookMap({
        'notes': 'Borrowed from Diane',
      });

      expect(display.lenderName, 'Diane');
      expect(display.dueDate, '');
    });

    test('typed columns take precedence over legacy notes', () {
      // Migrated rows may have both; the authoritative source is the typed
      // column (same value post-backfill, but the principle matters).
      final display = BorrowedCopyDisplay.fromBookMap({
        'lender_display_name': 'Eve',
        'borrow_due_date': '2030-01-01',
        'notes': "Emprunté de Stale jusqu'au 1999-01-01",
      });

      expect(display.lenderName, 'Eve');
      expect(display.dueDate, '2030-01-01');
    });

    test('unparseable notes yield empty strings without crashing', () {
      final display = BorrowedCopyDisplay.fromBookMap({
        'notes': 'Random user freeform note',
      });

      expect(display.lenderName, '');
      expect(display.dueDate, '');
    });

    test('missing map entries are treated as empty', () {
      final display = BorrowedCopyDisplay.fromBookMap({});
      expect(display.lenderName, '');
      expect(display.dueDate, '');
    });
  });
}
