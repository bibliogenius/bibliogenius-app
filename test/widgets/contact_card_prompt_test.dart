import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/providers/hub_directory_provider.dart';
import 'package:bibliogenius/services/ffi_service.dart';
import 'package:bibliogenius/src/rust/api/frb.dart' as frb;
import 'package:bibliogenius/widgets/contact_card_prompt.dart';

class _MockFfiService extends FfiService {
  _MockFfiService() : super.forTest();

  List<frb.FrbHubFollow> followers = [];

  frb.FrbDirectoryConfig? config = const frb.FrbDirectoryConfig(
    nodeId: 'node-local',
    isListed: true,
    requiresApproval: true,
    acceptFrom: 'anyone',
    allowBorrowing: true,
  );

  @override
  Future<List<frb.FrbHubFollow>> hubDirectoryListFollowers() async => followers;

  @override
  Future<frb.FrbDirectoryConfig?> hubDirectoryGetConfig() async => config;
}

frb.FrbHubFollow _follow({required String status}) => frb.FrbHubFollow(
  id: 1,
  followerNodeId: 'node-follower',
  followedNodeId: 'node-local',
  status: status,
  createdAt: '2026-08-24T10:00:00Z',
);

/// ADR-067 D9: who gets asked to fill their contact card, and who is left
/// alone. The invitation only earns its place when its absence has a victim.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockFfiService ffi;

  Future<HubDirectoryProvider> provider({
    required String storedContact,
    required List<frb.FrbHubFollow> followers,
    bool hubEnabled = true,
  }) async {
    SharedPreferences.setMockInitialValues({
      'hub_contact_info': storedContact,
      'hub_directory_enabled': hubEnabled,
    });
    ffi = _MockFfiService()..followers = followers;
    final p = HubDirectoryProvider(ffi: ffi);
    await p.loadHubEnabled();
    await p.loadConfig();
    await p.loadContactInfo();
    await p.loadFollowers();
    return p;
  }

  test('offered when a follower has no way to reach us', () async {
    final p = await provider(
      storedContact: '',
      followers: [_follow(status: 'active')],
    );
    expect(shouldOfferContactPrompt(p), isTrue);
  });

  test('never offered once the card carries something', () async {
    final p = await provider(
      storedContact: 'federico.calo@pm.me',
      followers: [_follow(status: 'active')],
    );
    expect(shouldOfferContactPrompt(p), isFalse);
  });

  test(
    'a note alone still counts as filled: the owner made a choice',
    () async {
      final p = await provider(
        storedContact: 'Ask at the desk',
        followers: [_follow(status: 'active')],
      );
      expect(shouldOfferContactPrompt(p), isFalse);
    },
  );

  test('not offered with no follower: nobody is waiting on it', () async {
    final p = await provider(storedContact: '', followers: []);
    expect(shouldOfferContactPrompt(p), isFalse);
  });

  test('a pending follower does not trigger it', () async {
    final p = await provider(
      storedContact: '',
      followers: [_follow(status: 'pending')],
    );
    expect(shouldOfferContactPrompt(p), isFalse);
  });

  test('not offered when the directory is off', () async {
    final p = await provider(
      storedContact: '',
      followers: [_follow(status: 'active')],
      hubEnabled: false,
    );
    expect(shouldOfferContactPrompt(p), isFalse);
  });
}
