import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/providers/hub_directory_provider.dart';
import 'package:bibliogenius/services/ffi_service.dart';

class _MockFfiService extends FfiService {
  _MockFfiService() : super.forTest();
}

/// ADR-067: which slot a stored contact lands in, on the way back into the
/// settings form. The answer must be the same one the peer side reads, since
/// both run the single decoder.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  HubDirectoryProvider provider() =>
      HubDirectoryProvider(ffi: _MockFfiService());

  test('a stored lone address fills the email field, not the note', () async {
    SharedPreferences.setMockInitialValues({
      'hub_contact_info': 'federico.calo@pm.me',
    });
    final p = provider();
    await p.loadContactInfo();
    expect(p.contactCard.email, 'federico.calo@pm.me');
    expect(p.contactCard.note, isEmpty);
    expect(p.contactCard.isActionable, isTrue);
  });

  test('a stored sentence fills the note, and opens no channel', () async {
    SharedPreferences.setMockInitialValues({
      'hub_contact_info': 'Ask at the desk, mornings only',
    });
    final p = provider();
    await p.loadContactInfo();
    expect(p.contactCard.note, 'Ask at the desk, mornings only');
    expect(p.contactCard.email, isEmpty);
    expect(p.contactCard.isActionable, isFalse);
  });

  test(
    'the legacy payload is still sealed byte for byte until an edit',
    () async {
      SharedPreferences.setMockInitialValues({
        'hub_contact_info': 'federico.calo@pm.me',
      });
      final p = provider();
      await p.loadContactInfo();
      // Read typed, but what leaves the device is unchanged: an older follower
      // must not start receiving JSON just because we upgraded.
      expect(p.contactInfo, 'federico.calo@pm.me');
    },
  );

  test(
    'editing one field promotes the whole card to the typed format',
    () async {
      SharedPreferences.setMockInitialValues({
        'hub_contact_info': 'federico.calo@pm.me',
      });
      final p = provider();
      await p.loadContactInfo();
      await p.setContactPhone('+33 6 12 34 56 78');
      // The address recognized on load survives the edit.
      expect(p.contactCard.email, 'federico.calo@pm.me');
      expect(p.contactCard.phone, '+33612345678');
      expect(p.contactInfo.startsWith('{"v":1'), isTrue);
    },
  );
}
