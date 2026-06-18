import 'package:flutter_test/flutter_test.dart';
import 'package:bibliogenius/models/contact.dart';
import 'package:bibliogenius/utils/network_count.dart';

Contact _contact({
  int? id,
  String type = 'borrower',
  bool isActive = true,
}) {
  return Contact(id: id, type: type, name: 'c$id', isActive: isActive);
}

Map<String, dynamic> _peer({
  required int id,
  String connectionStatus = 'accepted',
  String? libraryUuid,
}) {
  return {
    'id': id,
    'connection_status': connectionStatus,
    'library_uuid': libraryUuid,
  };
}

void main() {
  group('countNetworkContacts', () {
    test('counts manual contacts plus connected peers', () {
      final contacts = [_contact(id: 1), _contact(id: 2)];
      final peers = [_peer(id: 10), _peer(id: 11)];

      expect(countNetworkContacts(contacts, peers), 4);
    });

    test('counts a connected peer even without a contact row (the 6-of-8 bug)',
        () {
      // 8 connected peers, none of which produced a loan-time "Library" row.
      final peers = List.generate(8, (i) => _peer(id: i, libraryUuid: 'uuid$i'));

      expect(countNetworkContacts(const [], peers), 8);
    });

    test('includes manually created (non-connected) contacts', () {
      // The originally reported bug: a manual borrower must be counted.
      final contacts = [_contact(id: 1, type: 'borrower')];

      expect(countNetworkContacts(contacts, const []), 1);
    });

    test('excludes peer-mirror "Library" contacts to avoid double counting', () {
      // A peer that had a loan owns BOTH a peers row and a 'Library' contact.
      final contacts = [
        _contact(id: 1, type: 'borrower'),
        _contact(id: 2, type: 'Library'),
      ];
      final peers = [_peer(id: 10, libraryUuid: 'uuid-a')];

      // borrower (1) + peer (1) == 2, the 'Library' mirror is not added.
      expect(countNetworkContacts(contacts, peers), 2);
    });

    test('"Library" exclusion is case-insensitive', () {
      final contacts = [
        _contact(id: 1, type: 'library'),
        _contact(id: 2, type: 'LIBRARY'),
      ];

      expect(countNetworkContacts(contacts, const []), 0);
    });

    test('ignores inactive contacts', () {
      final contacts = [
        _contact(id: 1, isActive: true),
        _contact(id: 2, isActive: false),
      ];

      expect(countNetworkContacts(contacts, const []), 1);
    });

    test('does not count pending peers', () {
      final peers = [
        _peer(id: 10, connectionStatus: 'accepted'),
        _peer(id: 11, connectionStatus: 'pending'),
      ];

      expect(countNetworkContacts(const [], peers), 1);
    });

    test('deduplicates connected peers by library_uuid', () {
      // Same device, two rows after a port change: count once.
      final peers = [
        _peer(id: 10, libraryUuid: 'same-uuid'),
        _peer(id: 11, libraryUuid: 'same-uuid'),
        _peer(id: 12, libraryUuid: 'other-uuid'),
      ];

      expect(countNetworkContacts(const [], peers), 2);
    });

    test('peers without a library_uuid are each counted', () {
      final peers = [
        _peer(id: 10, libraryUuid: null),
        _peer(id: 11, libraryUuid: null),
      ];

      expect(countNetworkContacts(const [], peers), 2);
    });

    test('tolerates malformed peer entries', () {
      final peers = <dynamic>[
        _peer(id: 10),
        'not-a-map',
        42,
      ];

      expect(countNetworkContacts(const [], peers), 1);
    });
  });
}
