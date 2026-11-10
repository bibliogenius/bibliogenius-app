import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/providers/hub_directory_provider.dart';
import 'package:bibliogenius/providers/notification_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/screens/library_catalog_screen.dart';
import 'package:bibliogenius/services/auth_service.dart';
import 'package:bibliogenius/services/device_service.dart';
import 'package:bibliogenius/services/ffi_service.dart';
import 'package:bibliogenius/src/rust/api/frb.dart' as frb;
import 'package:bibliogenius/widgets/book_cover_card.dart';

/// A followed library whose catalog holds books without an ISBN.
///
/// The hub carries a missing ISBN as an empty string. Opening such a book
/// used to send that empty string to the metadata lookup, which answered with
/// an unrelated book, and cache the answer under the empty key: every book
/// without an ISBN then showed the same foreign cover, title and author.
const _nodeId = 'node-eve';

class _MockDeviceService extends DeviceService {
  @override
  Future<String?> getDeviceModel() async => 'TestDevice';

  @override
  Future<String?> getDeviceFingerprint() async => 'fp-test-1234';

  @override
  Future<String?> getAppVersion() async => '1.2.3';
}

class _MockFfiService extends FfiService {
  _MockFfiService() : super.forTest();

  /// The followed library's catalog. Copied out growable, like the
  /// bridge's: the screen sorts the list in place.
  List<frb.FrbCatalogEntry> catalog = const [
    frb.FrbCatalogEntry(isbn: '', title: 'La distinction'),
    frb.FrbCatalogEntry(isbn: '', title: 'la cantatrice chauve'),
  ];

  /// Every ISBN the screen asked metadata for.
  final List<String> lookups = [];

  @override
  Future<List<frb.FrbHubFollow>> hubDirectoryListFollowing() async => [
    const frb.FrbHubFollow(
      id: 1,
      followerNodeId: 'me',
      followedNodeId: _nodeId,
      status: 'active',
      createdAt: '2026-09-01T08:00:00Z',
    ),
  ];

  @override
  Future<frb.FrbHubProfile?> hubDirectoryGetProfile(String nodeId) async =>
      null;

  @override
  Future<List<frb.FrbCatalogEntry>> hubDirectoryGetCatalog(
    String nodeId,
  ) async => List.of(catalog);

  @override
  Future<List<Book>> getBooks({
    String? status,
    String? title,
    String? tag,
  }) async => [];

  /// Titles of the books the sheet added to the local library.
  final List<String> created = [];

  @override
  Future<frb.FrbBook> createBook(frb.FrbBook book) async {
    created.add(book.title);
    return book;
  }

  /// What a source answered for an empty query on the reported device.
  @override
  Future<Map<String, String?>?> lookupBookMetadata(
    String isbn, {
    String? lang,
  }) async {
    lookups.add(isbn);
    return {
      'title': 'Martin Eden',
      'author': 'Jack London',
      'cover_url': 'https://inventaire.io/img/entities/martin-eden',
    };
  }
}

Future<void> _pumpScreen(WidgetTester tester, _MockFfiService ffi) async {
  SharedPreferences.setMockInitialValues({});
  AuthService.storage = MockSecureStorage();
  final hub = HubDirectoryProvider(
    ffi: ffi,
    deviceService: _MockDeviceService(),
  );
  await hub.loadFollowing();

  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  // Providers above the MaterialApp: the detail sheet is pushed on the root
  // Navigator and would not see providers scoped inside `home`.
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: ThemeProvider()),
        ChangeNotifierProvider<HubDirectoryProvider>.value(value: hub),
        ChangeNotifierProvider<NotificationProvider>(
          create: (_) => NotificationProvider(),
        ),
      ],
      // The app bar reads GoRouter for its leading button.
      child: MaterialApp.router(
        routerConfig: GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) =>
                  LibraryCatalogScreen(nodeId: _nodeId, ffi: ffi),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpSheet(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _openAndClose(WidgetTester tester, String title) async {
  await tester.tap(find.text(title).first);
  // Bounded pumps: a sheet that loads a network cover keeps a spinner
  // running, which pumpAndSettle would wait on forever.
  await _pumpSheet(tester);

  // The sheet names the book it was opened for, never a looked-up stranger.
  expect(find.text(title), findsAtLeastNWidgets(2));
  expect(find.text('Martin Eden'), findsNothing);
  expect(find.text('Jack London'), findsNothing);

  await tester.tap(find.byIcon(Icons.close));
  await _pumpSheet(tester);
}

void main() {
  testWidgets('a book without an ISBN opens on its own data, with no lookup', (
    tester,
  ) async {
    final ffi = _MockFfiService();
    await _pumpScreen(tester, ffi);

    await _openAndClose(tester, 'La distinction');
    // The second book used to read the first one's cached answer.
    await _openAndClose(tester, 'la cantatrice chauve');

    expect(ffi.lookups, isEmpty);
  });

  testWidgets('adding a book without an ISBN leaves the others addable', (
    tester,
  ) async {
    final ffi = _MockFfiService();
    await _pumpScreen(tester, ffi);

    await tester.tap(find.text('La distinction').first);
    await _pumpSheet(tester);
    await tester.tap(find.text('catalog_add_to_library'));
    await _pumpSheet(tester);
    expect(ffi.created, ['La distinction']);

    // The added book's empty ISBN must not match every other ISBN-less one.
    await tester.tap(find.text('la cantatrice chauve').first);
    await _pumpSheet(tester);
    expect(find.text('catalog_add_to_library'), findsOneWidget);
    expect(find.text('catalog_already_in_library'), findsNothing);
  });

  testWidgets('the sheet shows the cover the owner published', (tester) async {
    const ownerCover = 'https://hub.example/api/directory/node-eve/covers/1';
    final ffi = _MockFfiService()
      ..catalog = const [
        frb.FrbCatalogEntry(
          isbn: '',
          title: 'La distinction',
          coverUrl: ownerCover,
        ),
      ];
    await _pumpScreen(tester, ffi);

    Iterable<CachedNetworkImage> ownerCoverImages() => tester
        .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
        .where((image) => image.imageUrl == ownerCover);
    // The grid tile already draws it.
    expect(ownerCoverImages(), hasLength(1));

    await tester.tap(find.byType(BookCoverCard));
    await _pumpSheet(tester);

    // The sheet draws the same cover as the tile it was opened from.
    expect(ownerCoverImages(), hasLength(2));
  });

  testWidgets('with no cover from the owner, the sheet keeps the looked-up one', (
    tester,
  ) async {
    const lookedUpCover = 'https://inventaire.io/img/entities/martin-eden';
    // An empty cover URL is no cover: it must not hide the looked-up one.
    final ffi = _MockFfiService()
      ..catalog = const [
        frb.FrbCatalogEntry(
          isbn: '9782264071958',
          title: 'Martin Eden',
          coverUrl: '',
        ),
      ];
    await _pumpScreen(tester, ffi);

    await tester.tap(find.byType(BookCoverCard));
    await _pumpSheet(tester);

    expect(ffi.lookups, ['9782264071958']);
    expect(
      tester
          .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
          .where((image) => image.imageUrl == lookedUpCover),
      hasLength(1),
    );
  });
}
