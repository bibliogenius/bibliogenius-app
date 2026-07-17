import 'package:flutter_test/flutter_test.dart';
import 'package:bibliogenius/models/contact.dart';
import 'package:bibliogenius/utils/known_libraries.dart';

Contact _library(String name, {bool isActive = true}) =>
    Contact(id: 'uuid-$name', type: 'Library', name: name, isActive: isActive);

void main() {
  group('selectUnpairedLibraryContacts', () {
    test('includes an active Library contact with no matching pairing', () {
      final result = selectUnpairedLibraryContacts(
        contacts: [_library('Bibliothèque de Federico')],
        pairedNames: const {},
      );
      expect(result, hasLength(1));
      expect(result.first.name, 'Bibliothèque de Federico');
    });

    test('excludes a contact whose name matches a paired library', () {
      final result = selectUnpairedLibraryContacts(
        contacts: [_library('Bibliothèque de Federico')],
        pairedNames: normalizedNameSet(const ['Bibliothèque de Federico']),
      );
      expect(result, isEmpty);
    });

    test('name matching ignores case and surrounding whitespace', () {
      final result = selectUnpairedLibraryContacts(
        contacts: [_library('Bibliothèque de Federico')],
        pairedNames: normalizedNameSet(const ['  bibliothèque de federico ']),
      );
      expect(result, isEmpty);
    });

    test('excludes inactive Library contacts', () {
      final result = selectUnpairedLibraryContacts(
        contacts: [_library('Old Library', isActive: false)],
        pairedNames: const {},
      );
      expect(result, isEmpty);
    });

    test('excludes non-library contacts regardless of pairing', () {
      final result = selectUnpairedLibraryContacts(
        contacts: [
          Contact(id: 'u1', type: 'borrower', name: 'Toto'),
          Contact(id: 'u2', type: 'user', name: 'Owner'),
        ],
        pairedNames: const {},
      );
      expect(result, isEmpty);
    });

    test('accepts the lowercase library type variant', () {
      final result = selectUnpairedLibraryContacts(
        contacts: [
          Contact(id: 'u1', type: 'library', name: 'Lowercase Lib'),
        ],
        pairedNames: const {},
      );
      expect(result, hasLength(1));
    });

    test('sorts results by name, case-insensitively', () {
      final result = selectUnpairedLibraryContacts(
        contacts: [_library('zeta'), _library('Alpha')],
        pairedNames: const {},
      );
      expect(result.map((c) => c.name).toList(), ['Alpha', 'zeta']);
    });
  });
}
