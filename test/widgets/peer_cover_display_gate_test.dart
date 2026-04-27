import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/widgets/book_cover_card.dart';
import 'package:bibliogenius/widgets/bookshelf_view.dart';
import 'package:bibliogenius/widgets/cached_book_cover.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal stand-in for the view-selection logic in
/// [peer_book_list_screen.dart]. It mirrors the real screen's gate:
///
/// ```dart
/// final peerCoversEnabled =
///     context.watch<ThemeProvider>().peerCoverDisplayEnabled;
/// final effectiveViewMode =
///     peerCoversEnabled ? _viewMode : _PeerViewMode.shelf;
/// ```
///
/// The screen is too stateful to mount in a unit test (sync, delta pull,
/// mDNS, etc.), but the invariant we care about -- "toggle off means zero
/// CachedNetworkImage" -- lives entirely in this gate.
class _GatedPeerView extends StatelessWidget {
  const _GatedPeerView({required this.books});
  final List<Book> books;

  @override
  Widget build(BuildContext context) {
    final peerCoversEnabled = context
        .watch<ThemeProvider>()
        .peerCoverDisplayEnabled;

    if (!peerCoversEnabled) {
      return BookshelfView(books: books, onBookTap: (_) {});
    }
    // Cover-grid branch -- the one that actually fetches covers.
    return GridView.count(
      crossAxisCount: 2,
      children: books
          .map(
            (book) =>
                BookCoverCard(book: book, onTap: () {}, isPeerCover: true),
          )
          .toList(),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // loadSettings touches flutter_secure_storage via AuthService.getUsername
    // when the 'username' pref is absent. Mock the storage layer so the
    // plugin call returns empty instead of throwing on Linux CI.
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  Book makeBook(int id, String title, {String? coverUrl}) =>
      Book(id: id, title: title, coverUrl: coverUrl);

  Widget harness(ThemeProvider provider, List<Book> books) {
    return MaterialApp(
      home: ChangeNotifierProvider<ThemeProvider>.value(
        value: provider,
        child: Scaffold(body: _GatedPeerView(books: books)),
      ),
    );
  }

  testWidgets(
    'toggle off: zero CachedNetworkImage is built regardless of cover URLs',
    (tester) async {
      final provider = ThemeProvider();
      await provider.loadSettings();
      await provider.setPeerCoverDisplayEnabled(false);

      final books = [
        makeBook(1, 'A', coverUrl: 'https://peer.example/covers/1.jpg'),
        makeBook(2, 'B', coverUrl: 'https://peer.example/covers/2.jpg'),
        makeBook(3, 'C', coverUrl: 'https://peer.example/covers/3.jpg'),
      ];

      await tester.pumpWidget(harness(provider, books));
      await tester.pump();

      expect(
        find.byType(CachedNetworkImage),
        findsNothing,
        reason:
            'When peer cover display is disabled, the view must fall back '
            'to the colored-spine shelf -- no CachedNetworkImage should be '
            'built, which guarantees no HTTP fetch and no disk write.',
      );
      expect(
        find.byType(CachedBookCover),
        findsNothing,
        reason: 'Shelf view uses BookSpine exclusively; no CachedBookCover.',
      );
      expect(
        find.byType(BookshelfView),
        findsOneWidget,
        reason: 'Toggle off must route through the shelf view.',
      );
    },
  );

  testWidgets(
    'toggle on: covers are rendered and CachedNetworkImage is present',
    (tester) async {
      final provider = ThemeProvider();
      await provider.loadSettings();
      // Default is true but call explicitly for clarity.
      await provider.setPeerCoverDisplayEnabled(true);

      final books = [
        makeBook(1, 'A', coverUrl: 'https://peer.example/covers/1.jpg'),
      ];

      await tester.pumpWidget(harness(provider, books));
      await tester.pump();

      // Control test: proves the negative assertion above is meaningful --
      // with the toggle on, the tree DOES contain the cover network image.
      expect(find.byType(BookCoverCard), findsOneWidget);
      expect(find.byType(CachedNetworkImage), findsOneWidget);
    },
  );

  testWidgets(
    'flipping the toggle off at runtime rebuilds into the shelf view',
    (tester) async {
      final provider = ThemeProvider();
      await provider.loadSettings(); // default: true

      final books = [
        makeBook(1, 'A', coverUrl: 'https://peer.example/covers/1.jpg'),
      ];

      await tester.pumpWidget(harness(provider, books));
      await tester.pump();
      expect(find.byType(CachedNetworkImage), findsOneWidget);

      await provider.setPeerCoverDisplayEnabled(false);
      await tester.pump();

      expect(
        find.byType(CachedNetworkImage),
        findsNothing,
        reason:
            'Consumer<ThemeProvider> must rebuild the view when the user '
            'flips the toggle -- no lingering network image in the tree.',
      );
      expect(find.byType(BookshelfView), findsOneWidget);
    },
  );
}
