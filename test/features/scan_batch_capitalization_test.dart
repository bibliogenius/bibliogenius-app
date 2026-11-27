import 'package:bibliogenius/data/repositories/book_repository.dart';
import 'package:bibliogenius/data/repositories/copy_repository.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/screens/scan_screen.dart';
import 'package:bibliogenius/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/mock_classes.dart';
import '../helpers/mock_repositories.dart';

/// The batch-scan review sheet lets the user fix a title, an author or a
/// publisher on the phone, right after scanning: its fields capitalize like
/// the add form's (sentence for the title, every word for names), and the
/// year keeps the default.
void main() {
  const connectivityChannel = MethodChannel(
    'dev.fluttercommunity.plus/connectivity',
  );

  late MockApiService mockApi;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockApi = MockApiService();
    // The batch path asks for connectivity before the metadata lookup.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityChannel, (call) async {
          return call.method == 'check' ? <String>['wifi'] : null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityChannel, null);
  });

  testWidgets('review sheet fields capitalize like the add form', (
    tester,
  ) async {
    // The sheet scrolls lazily: a tall surface builds all four fields.
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    late void Function(BarcodeCapture) onDetect;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiService>.value(value: mockApi),
          Provider<BookRepository>.value(value: MockBookRepository()),
          Provider<CopyRepository>.value(value: MockCopyRepository()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ],
        child: MaterialApp(
          home: ScanScreen(
            batchMode: true,
            controller: MockMobileScannerController(),
            scannerBuilder: (ctx, ctrl, detect) {
              onDetect = detect;
              return const SizedBox.expand(key: Key('mockScanner'));
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    mockApi.lookupResult = {'title': 'La Peste', 'author': 'Albert Camus'};
    onDetect(BarcodeCapture(barcodes: [Barcode(rawValue: '9782070612918')]));
    await tester.pumpAndSettle();
    // Let the "added to batch" toast expire under the frozen test clock.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.checklist));
    await tester.pumpAndSettle();

    // The sheet's fields, in declaration order: title, author, publisher, year.
    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .map((f) => f.textCapitalization)
        .toList();
    expect(fields, [
      TextCapitalization.sentences,
      TextCapitalization.words,
      TextCapitalization.words,
      TextCapitalization.none,
    ]);
  });
}
