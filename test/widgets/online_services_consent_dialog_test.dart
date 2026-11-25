import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/providers/hub_directory_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/auth_service.dart';
import 'package:bibliogenius/services/device_service.dart';
import 'package:bibliogenius/services/ffi_service.dart';
import 'package:bibliogenius/services/online_services_consent.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/online_services_consent_dialog.dart';

class _MockFfiService extends FfiService {
  _MockFfiService() : super.forTest();
}

class _MockDeviceService extends DeviceService {}

/// What the dialog shows before any detail is opened: three lines, then
/// one sentence that names everything else the hub receives (ADR-073 D2),
/// the device identifier included.
const _items = [
  'online_reg_item_books',
  'online_reg_item_covers',
  'online_reg_item_library',
  'online_reg_more',
];

HubDirectoryProvider _hub({NetworkUseSignals signals = const NetworkUseSignals()}) {
  AuthService.storage = MockSecureStorage();
  return HubDirectoryProvider(
    ffi: _MockFfiService(),
    deviceService: _MockDeviceService(),
    onlineServices: OnlineServicesConsent(readSignals: () async => signals),
  );
}

/// The answers [confirmOnlineServices] gave, in order.
final _answers = <bool>[];

/// The answers [confirmOnlineServicesForPairing] gave, in order.
final _pairings = <PairingConsent>[];

Widget _harness(
  HubDirectoryProvider hub, {
  bool publishingWithoutApproval = false,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  // Providers above the MaterialApp, as in main.dart: a dialog route is
  // pushed on the root Navigator.
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
      ChangeNotifierProvider<HubDirectoryProvider>.value(value: hub),
    ],
    child: MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => Column(
            children: [
              TextButton(
                onPressed: () async => _answers.add(
                  await confirmOnlineServices(
                    context,
                    publishingWithoutApproval: publishingWithoutApproval,
                  ),
                ),
                child: const Text('act'),
              ),
              TextButton(
                onPressed: () => showOnlineServicesInfo(context),
                child: const Text('info'),
              ),
              for (final local in [true, false])
                TextButton(
                  onPressed: () async => _pairings.add(
                    await confirmOnlineServicesForPairing(
                      context,
                      localAddress: local,
                    ),
                  ),
                  child: Text(local ? 'pair-local' : 'pair-remote'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

Future<String?> _storedChoice() async =>
    (await SharedPreferences.getInstance()).getString(
      OnlineServicesConsent.prefKey,
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // No catalogue loaded: every text renders as its key.
    TranslationService.setPoTranslationsForTest({});
    _answers.clear();
    _pairings.clear();
  });

  group('a pairing', () {
    // The local network was designed to work without any server: declining
    // the registration must not take a local pairing away.
    testWidgets('with a peer on the local network, declining goes on '
        'without the hub and records nothing', (tester) async {
      await tester.pumpWidget(_harness(_hub()));

      await tester.tap(find.text('pair-local'));
      await tester.pumpAndSettle();
      expect(find.text('online_reg_refusal_local'), findsOneWidget);
      expect(find.text('online_reg_refuse'), findsNothing);

      await tester.tap(find.text('online_reg_continue_local'));
      await tester.pumpAndSettle();

      expect(_pairings, [PairingConsent.localOnly]);
      expect(await _storedChoice(), isNull);
    });

    testWidgets('dismissing the dialog cancels, even with a local peer', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(_hub()));

      await tester.tap(find.text('pair-local'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      expect(_pairings, [PairingConsent.cancelled]);
    });

    testWidgets('with no local address, declining cancels: only the hub '
        'could carry it', (tester) async {
      await tester.pumpWidget(_harness(_hub()));

      await tester.tap(find.text('pair-remote'));
      await tester.pumpAndSettle();
      expect(find.text('online_reg_continue_local'), findsNothing);
      expect(find.text('online_reg_refusal'), findsOneWidget);

      await tester.tap(find.text('online_reg_refuse'));
      await tester.pumpAndSettle();

      expect(_pairings, [PairingConsent.cancelled]);
      expect(await _storedChoice(), isNull);
    });

    testWidgets('accepting pairs with the hub', (tester) async {
      await tester.pumpWidget(_harness(_hub()));

      await tester.tap(find.text('pair-local'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('online_reg_accept'));
      await tester.pumpAndSettle();

      expect(_pairings, [PairingConsent.online]);
      expect(await _storedChoice(), 'granted');
    });

    testWidgets('an installation that already consents is not asked', (
      tester,
    ) async {
      final hub = _hub(signals: const NetworkUseSignals(hasAccount: true));
      await tester.pumpWidget(_harness(hub));

      await tester.tap(find.text('pair-local'));
      await tester.pumpAndSettle();

      expect(find.byType(OnlineServicesConsentDialog), findsNothing);
      expect(_pairings, [PairingConsent.online]);
    });
  });

  testWidgets('an installation that already consents is not asked', (
    tester,
  ) async {
    final hub = _hub(signals: const NetworkUseSignals(hasAccount: true));
    await tester.pumpWidget(_harness(hub));

    await tester.tap(find.text('act'));
    await tester.pumpAndSettle();

    expect(find.byType(OnlineServicesConsentDialog), findsNothing);
    expect(_answers, [true]);
    // A consent inferred from use is never written down.
    expect(await _storedChoice(), isNull);
  });

  testWidgets('a device that could not be read is read once more before '
      'anyone is asked', (tester) async {
    // A busy database must not put the question to someone who already
    // consents by use: accepting it would write a yes they never needed.
    var reads = 0;
    AuthService.storage = MockSecureStorage();
    final hub = HubDirectoryProvider(
      ffi: _MockFfiService(),
      deviceService: _MockDeviceService(),
      onlineServices: OnlineServicesConsent(
        readSignals: () async {
          if (reads++ == 0) throw StateError('database busy');
          return const NetworkUseSignals(hasAccount: true);
        },
      ),
    );
    await tester.pumpWidget(_harness(hub));

    await tester.tap(find.text('act'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.byType(OnlineServicesConsentDialog), findsNothing);
    expect(_answers, [true]);
    expect(await _storedChoice(), isNull);
  });

  testWidgets('a device that stays unreadable gets the question', (
    tester,
  ) async {
    AuthService.storage = MockSecureStorage();
    final hub = HubDirectoryProvider(
      ffi: _MockFfiService(),
      deviceService: _MockDeviceService(),
      onlineServices: OnlineServicesConsent(
        readSignals: () async => throw StateError('database busy'),
      ),
    );
    await tester.pumpWidget(_harness(hub));

    await tester.tap(find.text('act'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    expect(find.byType(OnlineServicesConsentDialog), findsOneWidget);
  });

  testWidgets('refusing cancels the action and records nothing', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(_hub()));

    await tester.tap(find.text('act'));
    await tester.pumpAndSettle();
    expect(find.text('online_reg_title'), findsOneWidget);

    await tester.tap(find.text('online_reg_refuse'));
    await tester.pumpAndSettle();

    expect(_answers, [false]);
    expect(await _storedChoice(), isNull);

    // Nothing was remembered: the next action asks again.
    await tester.tap(find.text('act'));
    await tester.pumpAndSettle();
    expect(find.byType(OnlineServicesConsentDialog), findsOneWidget);
  });

  testWidgets('dismissing the dialog is a refusal', (tester) async {
    await tester.pumpWidget(_harness(_hub()));

    await tester.tap(find.text('act'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    expect(_answers, [false]);
    expect(await _storedChoice(), isNull);
  });

  testWidgets('accepting records the yes, and the question is not asked '
      'again', (tester) async {
    await tester.pumpWidget(_harness(_hub()));

    await tester.tap(find.text('act'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('online_reg_accept'));
    await tester.pumpAndSettle();

    expect(_answers, [true]);
    expect(await _storedChoice(), 'granted');

    await tester.tap(find.text('act'));
    await tester.pumpAndSettle();
    expect(find.byType(OnlineServicesConsentDialog), findsNothing);
    expect(_answers, [true, true]);
  });

  testWidgets('names everything the hub receives, the device fingerprint '
      'included, before any detail is opened', (tester) async {
    await tester.pumpWidget(_harness(_hub()));

    await tester.tap(find.text('act'));
    await tester.pumpAndSettle();

    for (final key in _items) {
      expect(find.text(key), findsOneWidget, reason: key);
    }
    expect(find.text('online_reg_refusal'), findsOneWidget);
    // The explanations wait behind the expander.
    expect(find.text('online_reg_d_device_id_body'), findsNothing);

    await tester.ensureVisible(find.text('online_reg_details'));
    await tester.tap(find.text('online_reg_details'));
    await tester.pumpAndSettle();
    expect(find.text('online_reg_d_device_id_body'), findsOneWidget);
    expect(find.text('online_reg_d_three_body'), findsOneWidget);
    // The details say where to unregister (the settings) and point to the
    // page that tells who runs the server.
    expect(find.text('online_reg_d_who_body'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('online_reg_d_who_link'),
        matching: find.bySubtype<TextButton>(),
      ),
      findsOneWidget,
    );
  });

  testWidgets('publishing without approval says the list is readable by '
      'everyone, not that it is encrypted', (tester) async {
    await tester.pumpWidget(
      _harness(_hub(), publishingWithoutApproval: true),
    );

    await tester.tap(find.text('act'));
    await tester.pumpAndSettle();

    expect(find.text('online_reg_item_books_public'), findsOneWidget);
    expect(find.text('online_reg_item_books'), findsNothing);
  });

  testWidgets('on a small phone at twice the text size nothing overflows '
      'and both buttons stay in view', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _harness(_hub(), textScaler: const TextScaler.linear(2)),
    );

    await tester.tap(find.text('act'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Tappable without scrolling: the buttons are outside the scroll area.
    await tester.tap(find.text('online_reg_accept'));
    await tester.pumpAndSettle();
    expect(_answers, [true]);
  });

  testWidgets('both answers are buttons of the same kind, with a text label', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(_hub()));
    await tester.tap(find.text('act'));
    await tester.pumpAndSettle();

    final refuse = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'online_reg_refuse'),
    );
    final accept = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'online_reg_accept'),
    );
    // Neither answer is styled as the expected one.
    expect(refuse.runtimeType, accept.runtimeType);
    expect(
      refuse.defaultStyleOf(tester.element(find.byWidget(refuse))).backgroundColor
          ?.resolve({}),
      accept.defaultStyleOf(tester.element(find.byWidget(accept))).backgroundColor
          ?.resolve({}),
    );
  });

  testWidgets('the notice shows the same list with nothing to answer', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(_hub()));

    await tester.tap(find.text('info'));
    await tester.pumpAndSettle();

    expect(find.text('online_reg_info_title'), findsOneWidget);
    for (final key in _items) {
      expect(find.text(key), findsOneWidget, reason: key);
    }
    expect(find.text('online_reg_d_device_id_body'), findsOneWidget);
    expect(find.text('online_reg_accept'), findsNothing);
    expect(find.text('online_reg_refuse'), findsNothing);

    await tester.ensureVisible(find.text('close'));
    await tester.tap(find.text('close'));
    await tester.pumpAndSettle();
    expect(find.byType(OnlineServicesConsentDialog), findsNothing);
    expect(await _storedChoice(), isNull);
  });

  test('the data deletion page is opened in the language it exists in', () {
    String url(String language) => dataDeletionPageUri(language).toString();
    expect(url('fr'), 'https://bibliogenius.org/data-deletion.html');
    expect(url('en'), 'https://bibliogenius.org/en/data-deletion.html');
    expect(url('de'), 'https://bibliogenius.org/de/data-deletion.html');
    expect(url('es'), 'https://bibliogenius.org/es/data-deletion.html');
    // Not translated: the English page.
    expect(url('it'), 'https://bibliogenius.org/en/data-deletion.html');
    expect(url('pt'), 'https://bibliogenius.org/en/data-deletion.html');
  });

  group('the eight exposed catalogues', () {
    const languages = ['en', 'fr', 'es', 'de', 'it', 'pt-BR', 'tr', 'bg'];
    final keyPattern = RegExp(r'^msgid "(online_reg_[a-z_]+)"\nmsgstr "(.*)"$', multiLine: true);

    Map<String, String> read(String language) => {
      for (final m in keyPattern.allMatches(
        File('assets/i18n/$language.po').readAsStringSync(),
      ))
        m.group(1)!: m.group(2)!,
    };

    test('carry every key of the dialog, none empty', () {
      final reference = read('en');
      expect(reference.keys, containsAll(_items));
      expect(reference.length, 37);
      for (final language in languages) {
        final entries = read(language);
        expect(entries.keys.toSet(), reference.keys.toSet(), reason: language);
        for (final e in entries.entries) {
          expect(e.value.trim(), isNotEmpty, reason: '$language ${e.key}');
        }
      }
    });

    test('the sentence that stands for the rest of the list names the '
        'device identifier, the model, the version, the messages and the '
        'last connection', () {
      // The first level no longer lists them one per line: the sentence
      // must still name each (ADR-073 D2). Checked on the two catalogues
      // read by the maintainer.
      const named = {
        'fr': ['identifiant', 'modèle', 'version', 'messages', 'dernière connexion'],
        'en': ['identifier', 'model', 'version', 'messages', 'last connection'],
      };
      for (final language in named.keys) {
        final sentence = read(language)['online_reg_more']!;
        for (final word in named[language]!) {
          expect(sentence, contains(word), reason: '$language: $word');
        }
      }
    });

    test('say where to unregister through the name of the settings '
        'section', () {
      for (final language in languages) {
        expect(
          read(language)['online_reg_d_who_body'],
          contains('{section}'),
          reason: language,
        );
      }
    });

    test('name the settings switch through its placeholder', () {
      for (final language in languages) {
        final entries = read(language);
        for (final key in ['online_reg_d_three_title', 'online_reg_d_three_body']) {
          expect(entries[key], contains('{toggle}'), reason: '$language $key');
        }
      }
    });
  });
}
