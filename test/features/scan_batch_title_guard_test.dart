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

/// The batch-scan editor is the one place in the app where a book title can be
/// cleared: the add form has a validator on the field, this sheet had none. A
/// blank title there created a book nothing can identify, rendered as an empty
/// tile locally and on every peer caching the catalog, and the backend now
/// refuses it outright at creation.
///
/// The guard keeps the previous title and says so, instead of letting the book
/// fail at commit time when the batch is already closed.
void main() {
  const connectivityChannel = MethodChannel(
    'dev.fluttercommunity.plus/connectivity',
  );

  late MockApiService mockApi;
  late MockBookRepository bookRepo;
  late MockCopyRepository copyRepo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    mockApi = MockApiService();
    bookRepo = MockBookRepository();
    copyRepo = MockCopyRepository();

    // The batch path asks for connectivity before the metadata lookup; without
    // a stub the plugin channel throws and no book ever reaches the batch.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityChannel, (call) async {
          return call.method == 'check' ? <String>['wifi'] : null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(connectivityChannel, null);
  });

  /// Mounts the scanner in batch mode and hands back the detection callback,
  /// so the test can feed barcodes without a camera.
  Future<void Function(BarcodeCapture)> pumpScanner(WidgetTester tester) async {
    late void Function(BarcodeCapture) onDetect;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ApiService>.value(value: mockApi),
          Provider<BookRepository>.value(value: bookRepo),
          Provider<CopyRepository>.value(value: copyRepo),
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
    return onDetect;
  }

  /// Queues one book in the batch under [isbn], titled [title].
  Future<void> scan(
    WidgetTester tester,
    void Function(BarcodeCapture) onDetect, {
    required String isbn,
    required String title,
  }) async {
    mockApi.lookupResult = {'title': title, 'author': 'Albert Camus'};
    onDetect(BarcodeCapture(barcodes: [Barcode(rawValue: isbn)]));
    await tester.pumpAndSettle();
  }

  /// Each queued scan leaves a one-second confirmation toast, and a
  /// ScaffoldMessenger shows one snackbar at a time. Under a frozen test clock
  /// those toasts never expire on their own and would swallow the message the
  /// editor is expected to raise, so drain them before acting. A real user
  /// takes longer than a second to open the sheet and edit a field.
  Future<void> drainToasts(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  }

  /// The sheet's fields, in declaration order: title, author, publisher, year.
  Finder titleField() => find.byType(TextField).first;

  String currentTitleText(WidgetTester tester) =>
      tester.widget<TextField>(titleField()).controller!.text;

  testWidgets('clearing a title in the batch editor is refused', (
    tester,
  ) async {
    final onDetect = await pumpScanner(tester);

    // Two books: with a single one the sheet only offers "save", which also
    // commits the batch. Two lets the test move between them and inspect what
    // the editor kept, with no commit involved.
    await scan(tester, onDetect, isbn: '9782070612918', title: 'La Peste');
    await scan(tester, onDetect, isbn: '9782070360024', title: "L'Exil");

    await drainToasts(tester);

    // Open the review sheet on the first book.
    await tester.tap(find.byIcon(Icons.checklist));
    await tester.pumpAndSettle();
    expect(currentTitleText(tester), 'La Peste');

    // Clear the title and move on.
    await tester.enterText(titleField(), '');
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();

    // The refusal is visible, not silent.
    expect(
      find.text('enter_title_error'),
      findsOneWidget,
      reason: 'the user must be told why the title was not saved',
    );

    // Back on the first book: the editor kept the title it had.
    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(
      currentTitleText(tester),
      'La Peste',
      reason: 'a blank title must never replace the one already on the book',
    );
  });

  testWidgets('a whitespace-only title is refused like an empty one', (
    tester,
  ) async {
    final onDetect = await pumpScanner(tester);

    await scan(tester, onDetect, isbn: '9782070612918', title: 'La Peste');
    await scan(tester, onDetect, isbn: '9782070360024', title: "L'Exil");
    await drainToasts(tester);

    await tester.tap(find.byIcon(Icons.checklist));
    await tester.pumpAndSettle();

    // Matches `book_service::validate_title`, which trims before deciding.
    await tester.enterText(titleField(), '   ');
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();

    expect(find.text('enter_title_error'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(currentTitleText(tester), 'La Peste');
  });

  testWidgets('a real edit is still saved, and trimmed', (tester) async {
    final onDetect = await pumpScanner(tester);

    await scan(tester, onDetect, isbn: '9782070612918', title: 'La Peste');
    await scan(tester, onDetect, isbn: '9782070360024', title: "L'Exil");
    await drainToasts(tester);

    await tester.tap(find.byIcon(Icons.checklist));
    await tester.pumpAndSettle();

    await tester.enterText(titleField(), '  La Chute  ');
    await tester.tap(find.byIcon(Icons.arrow_forward));
    await tester.pumpAndSettle();

    expect(
      find.text('enter_title_error'),
      findsNothing,
      reason: 'a valid rename must not warn',
    );

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    expect(currentTitleText(tester), 'La Chute');
  });
}
