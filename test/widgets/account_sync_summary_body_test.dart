import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:bibliogenius/providers/account_sync_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/ffi_service.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/account_sync_summary_sheet.dart';

/// Minimal i18n table covering every key the summary body reads in both
/// account states. Kept inline so the test survives .po reorganization.
const Map<String, String> _enKeys = {
  'settings_goal_sync_devices': 'Read on my other devices',
  'account_sync_title': 'Encrypted account',
  'account_sync_signed_in_label': 'Signed in as',
  'account_sync_devices_count': 'Authorized devices: {count}',
  'account_sync_sync_now': 'Sync now',
  'account_sync_manage_button': 'Manage account',
  'account_sync_signed_out_intro': 'Signed-out intro copy.',
  'account_sync_create_account': 'Create an account',
  'account_sync_join_account': 'Join an account',
  'account_sync_pair_cta': 'Add this device via another device',
};

/// FFI stub: the provider is real, only the FFI boundary is faked.
class _FakeFfi extends FfiService {
  _FakeFfi({required this.signedIn, this.devices = const []})
    : super.forTest();

  final bool signedIn;
  final List<Map<String, Object>> devices;

  @override
  Future<String> accountStatus() async => jsonEncode({
    'signed_in': signedIn,
    'email': 'reader@example.org',
    'account_id': 'acc-1',
    'device_id': 'dev-1',
  });

  @override
  Future<String> accountRefreshDevices() async =>
      jsonEncode({'devices': devices});
}

Widget _harness(AccountSyncProvider provider, {Widget? child}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
      ChangeNotifierProvider<AccountSyncProvider>.value(value: provider),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: child ?? const AccountSyncSummaryBody(),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    TranslationService.setPoTranslationsForTest({'en': _enKeys});
  });

  tearDown(() {
    TranslationService.setPoTranslationsForTest({});
  });

  testWidgets('signed out: goal header + the three account doors', (
    tester,
  ) async {
    final provider = AccountSyncProvider(ffi: _FakeFfi(signedIn: false));
    await tester.pumpWidget(_harness(provider));
    await tester.pumpAndSettle();

    expect(find.text('Read on my other devices'), findsOneWidget);
    expect(find.text('Signed-out intro copy.'), findsOneWidget);
    expect(find.text('Create an account'), findsOneWidget);
    expect(find.text('Join an account'), findsOneWidget);
    expect(find.text('Add this device via another device'), findsOneWidget);
    // No signed-in furniture.
    expect(find.text('Sync now'), findsNothing);
    expect(find.text('Manage account'), findsNothing);
  });

  testWidgets('signed in: email, device count, sync + manage actions', (
    tester,
  ) async {
    final provider = AccountSyncProvider(
      ffi: _FakeFfi(
        signedIn: true,
        devices: const [
          {'device_id': 'dev-1', 'name': 'macOS', 'is_self': true},
          {'device_id': 'dev-2', 'name': 'iPhone', 'is_self': false},
        ],
      ),
    );
    await tester.pumpWidget(_harness(provider));
    await tester.pumpAndSettle();

    expect(find.text('reader@example.org'), findsOneWidget);
    expect(find.text('Authorized devices: 2'), findsOneWidget);
    expect(find.text('Sync now'), findsOneWidget);
    expect(find.text('Manage account'), findsOneWidget);
    // No signed-out doors.
    expect(find.text('Create an account'), findsNothing);
  });

  testWidgets('header adapts to the host via titleKey/icon params', (
    tester,
  ) async {
    final provider = AccountSyncProvider(ffi: _FakeFfi(signedIn: false));
    await tester.pumpWidget(
      _harness(
        provider,
        child: const AccountSyncSummaryBody(
          titleKey: 'account_sync_title',
          icon: Icons.lock_outline,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Encrypted account'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    expect(find.text('Read on my other devices'), findsNothing);
  });
}
