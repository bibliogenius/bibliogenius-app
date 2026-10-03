import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/providers/account_sync_provider.dart';
import 'package:bibliogenius/providers/book_refresh_notifier.dart';
import 'package:bibliogenius/providers/household_provider.dart';
import 'package:bibliogenius/providers/notification_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/screens/account_sync_screen.dart';
import 'package:bibliogenius/services/ffi_service.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/src/rust/api/frb.dart' show FrbReader;

/// FFI stub: a signed-in account with two devices and no reader.
class _FakeFfi extends FfiService {
  _FakeFfi() : super.forTest();

  @override
  Future<String> accountStatus() async => jsonEncode({
    'signed_in': true,
    'email': 'reader@example.org',
    'account_id': 'acc-1',
    'device_id': 'dev-1',
  });

  @override
  Future<String> accountRefreshDevices() async => jsonEncode({
    'devices': const [
      {'device_id': 'dev-1', 'name': 'macOS', 'is_self': true},
      {'device_id': 'dev-2', 'name': 'iPhone', 'is_self': false},
    ],
  });

  @override
  Future<List<FrbReader>> listHouseholdReaders() async => const [];

  @override
  Future<FrbReader?> getCurrentHouseholdReader() async => null;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TranslationService.setPoTranslationsForTest({
      'en': {
        'account_sync_devices_title': 'Authorized devices',
        'account_sync_devices_subtitle': 'A device gives access.',
        'account_sync_add_device': 'Add a device',
        'account_sync_sync_now': 'Sync now',
        'account_sync_account_section_title': 'Account',
        'account_sync_account_section_subtitle': 'The account syncs.',
        'household_title': 'Readers',
        'household_subtitle': 'A reader is a person.',
      },
    });
  });

  tearDown(() {
    TranslationService.setPoTranslationsForTest({});
  });

  testWidgets('each section says what it holds and keeps its own action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final ffi = _FakeFfi();
    final themeProvider = ThemeProvider()..setLocaleSync(const Locale('en'));
    final household = HouseholdProvider(ffi: ffi);
    await household.load();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
          ChangeNotifierProvider<AccountSyncProvider>(
            create: (_) => AccountSyncProvider(ffi: ffi),
          ),
          ChangeNotifierProvider<HouseholdProvider>.value(value: household),
          ChangeNotifierProvider<BookRefreshNotifier>(
            create: (_) => BookRefreshNotifier(),
          ),
          // Read by the app bar.
          ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider(),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(
            routes: [
              GoRoute(path: '/', builder: (_, _) => const AccountSyncScreen()),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('A device gives access.'), findsOneWidget);
    expect(find.text('A reader is a person.'), findsOneWidget);
    expect(find.text('The account syncs.'), findsOneWidget);

    // Adding a device belongs to the device list: below the last device,
    // above the readers.
    final addDevice = tester.getTopLeft(find.text('Add a device')).dy;
    expect(addDevice, greaterThan(tester.getTopLeft(find.text('iPhone')).dy));
    expect(addDevice, lessThan(tester.getTopLeft(find.text('READERS')).dy));

    // The account-wide actions get their own header, so they do not read as
    // part of the readers above them.
    final account = tester.getTopLeft(find.text('ACCOUNT')).dy;
    expect(account, greaterThan(tester.getTopLeft(find.text('READERS')).dy));
    expect(account, lessThan(tester.getTopLeft(find.text('Sync now')).dy));
    expect(tester.takeException(), isNull);
  });
}
