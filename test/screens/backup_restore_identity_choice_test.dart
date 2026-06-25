// Unit tests for the restore wizard's same-device determination
// (ADR-042 §13.3). This mirrors the backend `same_device` rule in
// `backup.rs::apply_replace`: only a present, non-blank local `library_uuid`
// equal to the manifest uuid counts as same-device. An absent / blank value
// (a transiently-dark store, never a minted junk uuid) must NOT be read as a
// same-device match, otherwise a cross-device restore could be misframed.

import 'package:bibliogenius/screens/backup_restore_wizard_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const manifest = '550e8400-e29b-41d4-a716-446655440000';

  group('isSameDeviceRestore', () {
    test('matching local uuid -> same device', () {
      expect(isSameDeviceRestore(manifest, manifest), isTrue);
    });

    test('different local uuid -> not same device', () {
      expect(
        isSameDeviceRestore('00000000-0000-0000-0000-deadbeefdead', manifest),
        isFalse,
      );
    });

    test('null local uuid (absent / unreadable store) -> not same device', () {
      // The wizard must never mint here; a null value is honest "unknown".
      expect(isSameDeviceRestore(null, manifest), isFalse);
    });

    test('blank local uuid is normalized to absent -> not same device', () {
      expect(isSameDeviceRestore('', manifest), isFalse);
      expect(isSameDeviceRestore('   ', manifest), isFalse);
    });
  });
}
