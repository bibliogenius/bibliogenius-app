import 'package:bibliogenius/services/ffi_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Locks the placeholder-nodeId guards in [FfiService.hubDirectoryGetProfile]
/// and [FfiService.hubDirectoryGetCatalog].
///
/// `peer_<row id>` node ids are fabricated locally when a peers row has no
/// `library_uuid` yet; they can never exist hub-side. The wrappers are the
/// choke points for all hub profile/catalog lookups, so they must
/// short-circuit them before any FFI call instead of leaking a
/// guaranteed 404 to the hub.
void main() {
  group('FfiService.isPlaceholderNodeId', () {
    test('flags locally fabricated peer_<id> placeholders', () {
      expect(FfiService.isPlaceholderNodeId('peer_233'), isTrue);
      expect(FfiService.isPlaceholderNodeId('peer_1'), isTrue);
    });

    test('accepts real node uuids', () {
      expect(
        FfiService.isPlaceholderNodeId('49391e11-c367-4e25-9432-24658f41a04a'),
        isFalse,
      );
    });
  });

  group('FfiService.hubDirectoryGetCatalog', () {
    test('short-circuits placeholder ids before any FFI call', () async {
      final logs = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      addTearDown(() => debugPrint = originalDebugPrint);

      final entries =
          await FfiService.forTest().hubDirectoryGetCatalog('peer_233');

      expect(entries, isEmpty);
      expect(
        logs.where((m) => m.contains('hubDirectoryGetCatalog error')),
        isEmpty,
        reason: 'a placeholder nodeId must never reach the FFI bridge',
      );
    });
  });

  group('FfiService.hubDirectoryGetProfile', () {
    test('short-circuits placeholder ids before any FFI call', () async {
      // Capture debugPrint: in the test environment the FFI bridge is not
      // initialized, so reaching the frb call would throw and be caught,
      // logging "FFI hubDirectoryGetProfile error". The guard must return
      // before that path is ever taken.
      final logs = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) logs.add(message);
      };
      addTearDown(() => debugPrint = originalDebugPrint);

      final profile =
          await FfiService.forTest().hubDirectoryGetProfile('peer_233');

      expect(profile, isNull);
      expect(
        logs.where((m) => m.contains('hubDirectoryGetProfile error')),
        isEmpty,
        reason: 'a placeholder nodeId must never reach the FFI bridge',
      );
    });
  });
}
