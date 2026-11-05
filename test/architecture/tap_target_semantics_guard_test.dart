// Guard: every tap target on the main journey names itself AND says what it is.
//
// Measured on the rendered semantics tree, the way `theme_contrast_guard_test`
// measures contrast on pixels, and not from a scan of the source: two
// hand-written scanners of `InkWell`/`GestureDetector` sites each produced
// false positives and misses. The tree is what VoiceOver and TalkBack read.
//
// Two guidelines run on every screen.
//
// `labeledTapTargetGuideline` is Flutter's own: a tappable node must carry a
// label or a tooltip. It is necessary but far from sufficient. An `InkWell`
// around a `Text` passes it, because the text merges into the tappable node as
// its label, yet a screen reader then reads "Dune, Frank Herbert" with no hint
// that it can be activated. That silent majority is exactly the defect this
// guard exists for, so it adds a second guideline, [tapTargetRoleGuideline],
// which fails a node that:
//
// - can be tapped but declares no role (button, link, tab, toggle, check box,
//   radio, slider, text field, or a tap hint such as ExpansionTile's);
// - is announced as a button but has no tap action, which is what
//   `Semantics(button: true, excludeSemantics: true)` around a gesture does,
//   and what a label written above a `Card` does (the Card opens its own
//   node and keeps the tap for itself);
// - reads its own text twice, a label written above widgets whose text
//   merges in after it ("Dune, Dune").
//
// What none of this can judge is whether the name is RIGHT. A memory card
// named while face down, or a deliberately blurred cover named after the book,
// passes and hands over the answer. Those calls were made by reading each
// site, not by this test.
//
// A guard only sees what its probe renders. The probe below mounts the real
// screens of the main journey with realistic data, walks the states a reader
// reaches (every library layout, the collections module, every settings
// section page, the drawer and the rail) and scrolls each page one viewport
// at a time, because a widget off screen is not in the tree. Screens and
// states outside [_probes] are not covered.
//
// `A11Y_GUARD_VERBOSE=1` lists every tap target each probe rendered.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show CheckedState, SemanticsAction, SemanticsRole, Tristate;

import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/audio/providers/audio_provider.dart';
import 'package:bibliogenius/data/repositories/book_repository.dart';
import 'package:bibliogenius/data/repositories/collection_repository.dart';
import 'package:bibliogenius/data/repositories/contact_repository.dart';
import 'package:bibliogenius/data/repositories/copy_repository.dart';
import 'package:bibliogenius/data/repositories/loan_repository.dart';
import 'package:bibliogenius/data/repositories/recommendation_repository.dart';
import 'package:bibliogenius/data/repositories/tag_repository.dart';
import 'package:bibliogenius/models/book.dart';
import 'package:bibliogenius/models/collection.dart';
import 'package:bibliogenius/models/collection_book.dart';
import 'package:bibliogenius/models/contact.dart';
import 'package:bibliogenius/models/copy.dart';
import 'package:bibliogenius/models/discovery.dart';
import 'package:bibliogenius/models/loan.dart';
import 'package:bibliogenius/models/recommendation.dart';
import 'package:bibliogenius/models/tag.dart';
import 'package:bibliogenius/providers/book_note_provider.dart';
import 'package:bibliogenius/providers/book_refresh_notifier.dart';
import 'package:bibliogenius/providers/favorites_provider.dart';
import 'package:bibliogenius/providers/flash_message_provider.dart';
import 'package:bibliogenius/providers/hub_directory_provider.dart';
import 'package:bibliogenius/providers/metadata_fill_provider.dart';
import 'package:bibliogenius/providers/notification_provider.dart';
import 'package:bibliogenius/providers/ownership_preference_provider.dart';
import 'package:bibliogenius/providers/pending_peers_provider.dart';
import 'package:bibliogenius/providers/recommendation_provider.dart';
import 'package:bibliogenius/providers/sort_preference_provider.dart';
import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/screens/add_book_screen.dart';
import 'package:bibliogenius/screens/book_list_screen.dart';
import 'package:bibliogenius/screens/book_details_screen.dart';
import 'package:bibliogenius/screens/borrow_requests_screen.dart';
import 'package:bibliogenius/screens/collection/collection_detail_screen.dart';
import 'package:bibliogenius/screens/dashboard_screen.dart';
import 'package:bibliogenius/screens/library_screen.dart';
import 'package:bibliogenius/screens/network_screen.dart';
import 'package:bibliogenius/screens/profile_screen.dart';
import 'package:bibliogenius/screens/settings/settings_scope.dart';
import 'package:bibliogenius/screens/settings/settings_section_screen.dart';
import 'package:bibliogenius/screens/settings/settings_sections.dart';
import 'package:bibliogenius/screens/settings_screen.dart';
import 'package:bibliogenius/screens/organize_shelves_screen.dart';
import 'package:bibliogenius/services/api_service.dart';
import 'package:bibliogenius/services/auth_service.dart';
import 'package:bibliogenius/services/backup_scheduler_service.dart';
import 'package:bibliogenius/services/ffi_service.dart';
import 'package:bibliogenius/services/sync_service.dart';
import 'package:bibliogenius/services/recent_shelves_store.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/hierarchical_tag_selector.dart';
import 'package:bibliogenius/widgets/book_cover_grid.dart';
import 'package:bibliogenius/widgets/collection_selector.dart';
import 'package:bibliogenius/widgets/bookshelf_view.dart';
import 'package:bibliogenius/widgets/collection_stack_widget.dart';
import 'package:bibliogenius/widgets/scaffold_with_nav.dart';
import 'package:bibliogenius/widgets/selectable_book_tile.dart';
import 'package:bibliogenius/widgets/cached_book_cover.dart';
import 'package:bibliogenius/widgets/shelf_tree_rows.dart';
import 'package:bibliogenius/widgets/shelf_thumbnail.dart';

import '../helpers/mock_classes.dart';
import '../helpers/mock_repositories.dart';

// ---------------------------------------------------------------------------
// The role guideline
// ---------------------------------------------------------------------------

/// Roles Material assigns through [SemanticsRole] rather than a flag.
const _roleCarriers = {
  SemanticsRole.tab,
  SemanticsRole.menuItem,
  SemanticsRole.menuItemCheckbox,
  SemanticsRole.menuItemRadio,
};

bool _declaresRole(SemanticsNode node) {
  // The merged data, as a screen reader receives it: a node's own flags miss
  // what a MergeSemantics folded into it (a FloatingActionButton's role).
  final flags = node.getSemanticsData().flagsCollection;
  return flags.isButton ||
      flags.isLink ||
      flags.isSlider ||
      flags.isTextField ||
      flags.isKeyboardKey ||
      flags.isInMutuallyExclusiveGroup ||
      flags.isChecked != CheckedState.none ||
      flags.isToggled != Tristate.none ||
      // An expandable header (ExpansionTile) announces "collapsed" or
      // "expanded", which tells the reader it acts.
      flags.isExpanded != Tristate.none ||
      _roleCarriers.contains(node.getSemanticsData().role) ||
      // Flutter's ExpansionTile carries no role: it tells the reader what the
      // tap does through a tap hint ("double tap to expand"), which serves.
      node.hintOverrides?.onTapHint != null;
}

/// Where in `lib/` the offending tap target was built, as `Widget @ file:line`.
///
/// Flutter tracks widget creation locations under `flutter test`; the hit test
/// at the node's centre finds the render object, and its element's ancestry
/// is walked up to the first widget created by the app itself. For a
/// framework widget that builds its own `InkWell` (a `PopupMenuButton` with a
/// custom child), that is the app's `PopupMenuButton`, which is where the fix
/// goes.
final _appLib = '${Directory.current.path}/lib/';

/// `A11Y_GUARD_VERBOSE=1 flutter test ...` lists every tap target the probe
/// rendered, passing or not: the way to check what the guard actually sees.
final _verbose = Platform.environment['A11Y_GUARD_VERBOSE'] == '1';

String _siteOf(WidgetTester tester, SemanticsNode node) {
  var rect = node.rect;
  for (SemanticsNode? n = node; n != null; n = n.parent) {
    if (n.transform != null) {
      rect = MatrixUtils.transformRect(n.transform!, rect);
    }
  }
  final hit = HitTestResult();
  tester.binding.hitTestInView(hit, rect.center, tester.view.viewId);
  final deepest = hit.path
      .map((e) => e.target)
      .whereType<RenderObject>()
      .map((r) => r.debugCreator)
      .whereType<DebugCreator>()
      .firstOrNull;
  if (deepest == null) return 'site unknown at $rect';

  // The first app-created widget above the hit is often a Text or an Icon
  // inside the target; the useful line is the gesture that owns the tap.
  String? firstLocal;
  String? gesture;
  void visit(Element e) {
    final json = e.widget.toDiagnosticsNode().toJsonMap(
      InspectorSerializationDelegate(service: WidgetInspectorService.instance),
    );
    final loc = json['creationLocation'] as Map<String, Object?>?;
    final file = loc?['file'] as String?;
    if (file == null || !file.contains(_appLib)) return;
    final site =
        '${e.widget.runtimeType} @ '
        'lib/${file.split(_appLib).last}:${loc!['line']}';
    firstLocal ??= site;
    final type = e.widget.runtimeType.toString();
    if (_tapWrappers.contains(type)) {
      // A shared tap widget: the useful site is its caller, one level up.
      gesture = site;
    } else if (gesture == null && _gestureOwners.any(type.startsWith)) {
      gesture = site;
    }
  }

  visit(deepest.element);
  var steps = 0;
  deepest.element.visitAncestorElements((e) {
    // Past the gesture, keep looking a little further for a shared wrapper
    // that owns it.
    if (gesture != null && steps++ > 12) return false;
    visit(e);
    return true;
  });
  return gesture ?? firstLocal ?? 'site unknown at $rect';
}

/// Shared widgets whose own gesture is an implementation detail: the report
/// names the place that uses them.
const _tapWrappers = {'ScaleOnTap'};

/// Widgets that own a tap.
const _gestureOwners = [
  'GestureDetector',
  'InkWell',
  'InkResponse',
  'PopupMenuButton',
  'FloatingActionButton',
  'Dismissible',
];

class _TapTargetRoleGuideline extends AccessibilityGuideline {
  const _TapTargetRoleGuideline();

  @override
  String get description =>
      'Tappable widgets should carry a name and declare a role '
      '(button, link, tab, toggle...)';

  @override
  FutureOr<Evaluation> evaluate(WidgetTester tester) {
    var result = const Evaluation.pass();
    for (final view in tester.binding.renderViews) {
      result += _traverse(
        tester,
        view.owner!.semanticsOwner!.rootSemanticsNode!,
      );
    }
    return result;
  }

  Evaluation _traverse(WidgetTester tester, SemanticsNode node) {
    var result = const Evaluation.pass();
    node.visitChildren((child) {
      result += _traverse(tester, child);
      return true;
    });
    // Same exclusions as Flutter's `labeledTapTargetGuideline`, so the two
    // judge the same set of nodes.
    if (node.isMergedIntoParent ||
        node.isInvisible ||
        node.flagsCollection.isHidden) {
      return result;
    }
    final data = node.getSemanticsData();
    final activatable =
        data.hasAction(SemanticsAction.tap) ||
        data.hasAction(SemanticsAction.longPress);
    if (!activatable) {
      // The converse defect: a node announced as a button that a screen
      // reader cannot press. `Semantics(button: true, excludeSemantics:
      // true)` around a `GestureDetector` does exactly that, because
      // `excludeSemantics` also drops the child's tap action.
      final flags = data.flagsCollection;
      if ((flags.isButton || flags.isLink) &&
          flags.isEnabled != Tristate.isFalse) {
        result += Evaluation.fail(
          '"${data.label.replaceAll('\n', ' | ')}" is announced as a button '
          'but has no tap action: ${_siteOf(tester, node)}\n',
        );
      }
      return result;
    }
    final name = data.label.isNotEmpty ? data.label : data.tooltip;
    if (_verbose) {
      // ignore: avoid_print
      print(
        'TAP "${name.replaceAll('\n', ' | ')}" '
        'role=${_declaresRole(node)} ${_siteOf(tester, node)}',
      );
    }
    final missing = [
      if (name.isEmpty) 'no name',
      if (!_declaresRole(node)) 'no role',
      if (_readsTwice(data.label)) 'its text read twice',
    ];
    if (missing.isEmpty) return result;
    result += Evaluation.fail(
      '"${name.replaceAll('\n', ' | ')}" has ${missing.join(' and ')}: '
      '${_siteOf(tester, node)}${_verbose ? ' ${node.getSemanticsData()}' : ''}\n',
    );
    return result;
  }
}

/// Whether [label] says the same thing twice: a Semantics label written above
/// widgets whose own text merges in after it ("Dune, Dune"; "My Books : 3,
/// 3, My Books"). Flutter joins merged texts with newlines, so the mark is a
/// repeated line, later lines all already contained in the first, or a line
/// whose comma-separated parts were all read before, as a cover labelled
/// "Dune, Frank Herbert" over a card printing "Dune" then "Frank Herbert".
bool _readsTwice(String label) {
  final lines = label
      .split('\n')
      .map((l) => l.trim().toLowerCase())
      .where((l) => l.isNotEmpty)
      .toList();
  if (lines.length < 2) return false;
  if (lines.toSet().length < lines.length) return true;
  if (lines.skip(1).every(lines.first.contains)) return true;
  final heard = <String>{};
  for (final line in lines) {
    final parts = line.split(', ').map((p) => p.trim()).toList();
    if (heard.containsAll(parts)) return true;
    heard.addAll(parts);
  }
  return false;
}

/// A tappable node must say what it is, not only what it is called.
const AccessibilityGuideline tapTargetRoleGuideline = _TapTargetRoleGuideline();

// ---------------------------------------------------------------------------
// Test doubles: the FFI is not up under test, everything else is real.
// ---------------------------------------------------------------------------

class _FakeRecommendationRepository implements RecommendationRepository {
  @override
  Future<List<Recommendation>> getBookRecommendations(
    String bookId, {
    int? limit,
  }) async => const [];

  @override
  Future<PersonalRecommendations?> getPersonalRecommendations({
    int? limit,
  }) async => null;

  @override
  Future<DiscoveryLookupInputs?> getDiscoveryLookupInputs() async => null;
}

Response _ok(String path, Object data) => Response(
  requestOptions: RequestOptions(path: path),
  statusCode: 200,
  data: data,
);

/// Every HTTP read the main screens make, answered with a small fixture so
/// they render their populated state and not an error or a spinner.
class _OfflineApiService extends MockApiService {
  @override
  Future<Response> getLibraryConfig() async =>
      _ok('/api/config', <String, dynamic>{});

  @override
  Future<Response> getUserStatus() async => _ok('/api/user/status', {
    'config': {'reading_goal_yearly': 12, 'reading_goal_progress': 3},
  });

  @override
  Future<Response> getPeers() async => _ok('/api/peers', {
    'data': [
      {
        'id': 7,
        'name': 'Rue des Livres',
        'url': 'http://192.168.1.20:8000',
        'status': 'connected',
        'library_uuid': '0e0b3c3e-5a8d-4f7e-9a51-1f1f4a0a2b10',
      },
    ],
  });

  @override
  Future<Response> getIncomingRequests() async => _ok('/api/requests', [
    {
      'id': 'r1',
      'status': 'pending',
      'book_title': 'Dune',
      'book_isbn': '9780441172719',
      'peer_name': 'Rue des Livres',
      'created_at': '2026-09-20T10:00:00Z',
    },
  ]);

  @override
  Future<Response> getOutgoingRequests() async =>
      _ok('/api/requests/outgoing', []);

  @override
  Future<Response> getPendingPeers() async =>
      _ok('/api/peers/pending', {'requests': []});

  @override
  Future<Response> getBorrowedCopies() async =>
      _ok('/api/copies/borrowed', {'loans': []});
}

/// The hub directory, inert: every loader resolves at once with nothing, the
/// way a reader who never joined the directory sees it.
class _OfflineHubDirectoryProvider extends HubDirectoryProvider {
  _OfflineHubDirectoryProvider() : super(ffi: FfiService());

  @override
  Future<void> loadConfig() async {}

  @override
  Future<bool> ensureRegistered() async => false;

  @override
  Future<void> loadFollowing() async {}

  @override
  Future<void> loadPendingRequests() async {}
}

class _QuietSyncService extends SyncService {
  _QuietSyncService(super.api) : super(isLanEnabled: () => false);

  @override
  Future<void> syncAllPeers() async {}
}

// ---------------------------------------------------------------------------
// Fixture: a small library that exercises the states the screens branch on.
// ---------------------------------------------------------------------------

final _books = [
  Book(
    id: 'b1',
    // Most real books carry a cover, and the cover names the book: a fixture
    // without one hid a card that read every covered title twice.
    coverUrl: 'https://covers.example/b1.jpg',
    title: 'The Anomaly',
    author: 'Herve Le Tellier',
    readingStatus: 'to_read',
    subjects: ['Novel'],
  ),
  Book(
    id: 'b2',
    coverUrl: 'https://covers.example/b2.jpg',
    title: 'Dune',
    author: 'Frank Herbert',
    readingStatus: 'reading',
    userRating: 8,
    subjects: ['Science fiction'],
  ),
  Book(
    id: 'b3',
    title: 'Mrs Dalloway',
    author: 'Virginia Woolf',
    readingStatus: 'read',
    finishedReadingAt: DateTime(2026, 8, 1),
  ),
  Book(
    id: 'b4',
    title: 'Neuromancer',
    author: 'William Gibson',
    readingStatus: 'wanting',
    owned: false,
  ),
];

final _tags = [
  Tag(id: 't1', name: 'Novel', count: 1),
  Tag(id: 't2', name: 'Genre', count: 0),
  Tag(id: 't3', name: 'Science fiction', parentId: 't2', count: 1),
];

final _collections = [
  Collection(
    id: 'c1',
    name: 'Summer reads',
    source: 'manual',
    createdAt: '2026-06-01T00:00:00Z',
    updatedAt: '2026-06-01T00:00:00Z',
  ),
];

class _Harness {
  final theme = ThemeProvider()..setLocaleSync(const Locale('en'));
  final refresh = BookRefreshNotifier();
  final api = _OfflineApiService();
  final books = MockBookRepository()..mockBooks = _books;
  final tags = MockTagRepository()
    ..mockTags = _tags
    // Mrs Dalloway: owned, on no shelf. Neuromancer is on none either, but
    // wished, so outside the default view the count covers.
    ..mockUnshelvedCount = 1;
  final collections = MockCollectionRepository()
    ..mockCollections = _collections
    ..mockCollectionBooks = [
      CollectionBook(
        bookId: 'b2',
        title: 'Dune',
        author: 'Frank Herbert',
        isOwned: true,
        readingStatus: 'reading',
      ),
    ];
  final contacts = MockContactRepository()
    ..mockContacts = [
      Contact(
        id: 'k1',
        type: 'borrower',
        name: 'Ada Martin',
        libraryOwnerId: 1,
      ),
      // Two borrowers, not one: every contact-backed member has the same int
      // `id`, and a key built from it collided as soon as there were two.
      Contact(
        id: 'k2',
        type: 'borrower',
        name: 'Basile Roux',
        libraryOwnerId: 1,
      ),
    ];
  final copies = MockCopyRepository()
    ..mockCopies = [
      Copy(
        id: 'cp1',
        bookId: 'b2',
        libraryId: 1,
        status: 'available',
        isTemporary: false,
      ),
    ];
  final loans = MockLoanRepository()
    ..mockLoans = [
      Loan(
        id: 'l1',
        copyId: 'cp1',
        contactId: 'k1',
        libraryId: 1,
        loanDate: '2026-09-01',
        dueDate: '2026-10-01',
        status: 'active',
        contactName: 'Ada Martin',
        bookTitle: 'Dune',
        bookId: 'b2',
      ),
    ];
  final auth = MockAuthService();
  final BackupSchedulerService backups;

  _Harness(SharedPreferences prefs)
    : backups = BackupSchedulerService(
        prefs: prefs,
        authService: MockAuthService(),
        clock: DateTime.now,
        probeWatermark: () async => null,
        runBackup: (_) async =>
            const BackupRunResult(archivePath: '', archiveSizeBytes: 0),
        resolveBackupsDir: () async => Directory.systemTemp,
      );

  Widget app(String location) {
    final router = GoRouter(
      initialLocation: location,
      routes: [
        ShellRoute(
          builder: (_, _, child) => ScaffoldWithNav(child: child),
          routes: [
            GoRoute(
              path: '/books',
              builder: (_, _) => LibraryScreen(initialIndex: 0),
              routes: [
                GoRoute(path: 'add', builder: (_, _) => const AddBookScreen()),
                GoRoute(
                  path: ':id',
                  builder: (_, state) {
                    final id = state.pathParameters['id']!;
                    final book = _books.firstWhere((b) => b.id == id);
                    books.mockBook = book;
                    return BookDetailsScreen(bookId: id, book: book);
                  },
                ),
              ],
            ),
            GoRoute(
              path: '/shelves',
              builder: (_, state) => LibraryScreen.forShelvesUri(state.uri),
            ),
            GoRoute(
              path: '/collections',
              builder: (_, _) => LibraryScreen(initialIndex: 2),
              routes: [
                GoRoute(
                  path: ':id',
                  builder: (_, _) =>
                      CollectionDetailScreen(collection: _collections.first),
                ),
              ],
            ),
            GoRoute(path: '/network', builder: (_, _) => const NetworkScreen()),
            GoRoute(
              path: '/requests',
              builder: (_, _) => const LoansScreen(isTabView: false),
            ),
            GoRoute(
              path: '/dashboard',
              builder: (_, _) => const DashboardScreen(),
            ),
            GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
            GoRoute(
              path: '/settings',
              builder: (_, _) => SettingsScreen(),
              routes: [settingsSectionRoute],
            ),
          ],
        ),
        // Outside the shell, as in main.dart.
        GoRoute(
          path: '/shelves-management',
          pageBuilder: (_, state) => MaterialPage<void>(
            key: state.pageKey,
            fullscreenDialog: true,
            child: const OrganizeShelvesScreen(),
          ),
        ),
      ],
    );

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<BookRefreshNotifier>.value(value: refresh),
        Provider<ApiService>.value(value: api),
        Provider<BookRepository>.value(value: books),
        Provider<TagRepository>.value(value: tags),
        Provider<ContactRepository>.value(value: contacts),
        Provider<CollectionRepository>.value(value: collections),
        Provider<CopyRepository>.value(value: copies),
        Provider<LoanRepository>.value(value: loans),
        Provider<RecommendationRepository>.value(
          value: _FakeRecommendationRepository(),
        ),
        ChangeNotifierProvider<RecommendationProvider>(
          create: (_) =>
              RecommendationProvider(_FakeRecommendationRepository(), refresh),
        ),
        ChangeNotifierProvider<FavoritesProvider>(
          create: (_) => FavoritesProvider(collections, refresh),
        ),
        Provider<SyncService>.value(value: _QuietSyncService(api)),
        ChangeNotifierProvider<AudioProvider>(create: (_) => AudioProvider()),
        ChangeNotifierProvider<PendingPeersProvider>(
          create: (_) => PendingPeersProvider(api),
        ),
        ChangeNotifierProvider<BookNoteProvider>(
          create: (_) => BookNoteProvider(),
        ),
        ChangeNotifierProvider<FlashMessageProvider>(
          create: (_) => FlashMessageProvider(),
        ),
        // Loaded as main.dart does, so a remembered sort reaches the list.
        ChangeNotifierProvider<SortPreferenceProvider>(
          create: (_) => SortPreferenceProvider()..load(),
        ),
        ChangeNotifierProvider<OwnershipPreferenceProvider>(
          create: (_) => OwnershipPreferenceProvider(),
        ),
        ChangeNotifierProvider<NotificationProvider>(
          create: (_) => NotificationProvider(),
        ),
        ChangeNotifierProvider<HubDirectoryProvider>(
          create: (_) => _OfflineHubDirectoryProvider(),
        ),
        Provider<AuthService>.value(value: auth),
        ChangeNotifierProvider<MetadataFillProvider>(
          create: (_) => MetadataFillProvider(),
        ),
        ChangeNotifierProvider<BackupSchedulerService>.value(value: backups),
        ChangeNotifierProvider<SettingsData>(create: (_) => SettingsData()),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }
}

/// Settles without `pumpAndSettle`: several screens hold spinners or lazy
/// sections whose futures never complete with the FFI down.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 500));
  }
}

/// Both guidelines, reported together so one run lists every offender.
///
/// A node scrolled out of view is invisible to both guidelines, so a long
/// page is audited one viewport at a time down its main scrollable, and the
/// findings of every stop are pooled.
Future<void> _expectAccessibleTapTargets(WidgetTester tester) async {
  final findings = <String>{};
  Future<void> audit() async {
    if (_verbose) {
      // ignore: avoid_print
      print(
        'TEXTS ${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).toList()}',
      );
    }
    final labeled = await labeledTapTargetGuideline.evaluate(tester);
    final roles = await tapTargetRoleGuideline.evaluate(tester);
    findings.addAll(
      [roles.reason, labeled.reason]
          .whereType<String>()
          .expand((r) => r.split('\n'))
          .where((line) => line.trim().isNotEmpty),
    );
  }

  await audit();
  final scrollable = _mainVerticalScrollable(tester);
  if (scrollable != null) {
    final position = scrollable.position;
    // Reaching a state can leave the page scrolled (opening every settings
    // section scrolls to the last one): the walk down starts from the top.
    if (position.pixels > 0) {
      position.jumpTo(0);
      await _settle(tester);
      await audit();
    }
    var stops = 0;
    while (position.pixels < position.maxScrollExtent && stops++ < 20) {
      position.jumpTo(
        (position.pixels + position.viewportDimension * 0.8).clamp(
          0,
          position.maxScrollExtent,
        ),
      );
      await _settle(tester);
      await audit();
    }
  }
  expect(findings, isEmpty, reason: findings.join('\n'));
}

/// The tallest vertical scrollable on screen, which is the page body.
ScrollableState? _mainVerticalScrollable(WidgetTester tester) {
  ScrollableState? best;
  var bestHeight = 0.0;
  for (final element in find.byType(Scrollable).evaluate()) {
    final state = (element as StatefulElement).state as ScrollableState;
    if (state.axisDirection != AxisDirection.down) continue;
    if (!state.position.hasContentDimensions) continue;
    final box = element.renderObject as RenderBox?;
    final height = box?.size.height ?? 0;
    if (height > bestHeight) {
      best = state;
      bestHeight = height;
    }
  }
  return best;
}

/// One state of the app a reader can reach, as the guard renders it.
class _Probe {
  final String name;
  final String location;
  final Size size;
  final bool collections;
  final bool bottomNav;

  /// The shelves the route lists, when not the shared fixture.
  final List<Tag>? tags;

  /// Taps that lead from the route to the state under audit.
  final Future<void> Function(WidgetTester tester)? reach;

  const _Probe(
    this.name,
    this.location, {
    this.size = _phone,
    this.collections = false,
    this.bottomNav = true,
    this.tags,
    this.reach,
  });
}

/// Where the shelves tab's "to shelve" card leads.
const _toShelveLocation = '/shelves?unshelved=1&select=1&owned=library';

// Phone width puts the bottom-bar / drawer shell in play; the wide layout is
// the navigation rail. Both are the first thing a reader navigates.
const _phone = Size(390, 844);

/// A phone as wide as [_phone], taller: the shelves tree fixture in full.
/// Each row carries a 72 pt thumbnail, and the test font draws every glyph
/// a full em wide, so the fixture's names wrap and push its last rows below
/// a phone's fold, where their finders find nothing.
const _tallPhone = Size(390, 1100);
const _desktop = Size(1280, 900);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await _settle(tester);
  await tester.tap(finder);
  await _settle(tester);
}

/// Opens every collapsed [ExpansionTile], top to bottom.
Future<void> _expandAll(WidgetTester tester) async {
  for (var i = 0; i < find.byType(ExpansionTile).evaluate().length; i++) {
    final tile = find.byType(ExpansionTile).at(i);
    if (tester.widget<ExpansionTile>(tile).initiallyExpanded) continue;
    final header = find.descendant(of: tile, matching: find.byType(ListTile));
    await _tap(tester, header.first);
  }
}

final _shelfSheet = find.byKey(const Key('shelfPickerSheet'));

Finder _inShelfSheet(Finder finder) =>
    find.descendant(of: _shelfSheet, matching: finder);

/// Scrolls the add form until [finder] is built: the form is a lazy list,
/// and its shelves section sits below the fold on a phone.
Future<void> _revealInForm(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find
        .descendant(
          of: find.byType(ListView).first,
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await _settle(tester);
}

/// Opens the shelf picker from the add form's "Add" chip.
Future<void> _openShelfPicker(WidgetTester tester) async {
  final add = find.byKey(const Key('addShelfChip'));
  await _revealInForm(tester, add);
  await _tap(tester, add);
}

/// The row of the shelves tab tree for the shelf named [name].
Finder _treeRow(String name) => find.byKey(ValueKey('shelfTreeRow:$name'));

/// The drag handle of that row, also its "Move <name>" button.
Finder _treeHandle(String name) =>
    find.byKey(ValueKey('shelfTreeHandle:$name'));

/// The drop zone a drag shows at the head of the tree.
final _firstLevelZone = find.byKey(const Key('shelfTreeFirstLevelZone'));

final _treeSearch = find.byKey(const Key('shelfTreeSearch'));

/// Opens the "…" menu of the shelves tab row named [name].
Future<void> _openShelfRowMenu(WidgetTester tester, String name) =>
    _tap(tester, find.byTooltip('Actions for $name'));

/// "Delete Shelf" from the menu of the row of the shelf named [name].
Future<void> _deleteFromRow(WidgetTester tester, String name) async {
  await _openShelfRowMenu(tester, name);
  await _tap(tester, find.text('Delete Shelf'));
}

/// The same, without the settle [_tap] takes before each tap: two of
/// them would outlast the five seconds of a message already up.
Future<void> _deleteNowFromRow(WidgetTester tester, String name) async {
  await _tapNow(tester, find.byTooltip('Actions for $name'));
  await _tapNow(tester, find.text('Delete Shelf'));
}

/// Renames the shelf named [name] to [to] through "Edit Shelf".
Future<void> _renameFromRow(
  WidgetTester tester,
  String name,
  String to,
) async {
  await _openShelfRowMenu(tester, name);
  await _tap(tester, find.text('Edit Shelf'));
  await tester.enterText(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextFormField),
    ),
    to,
  );
  await _tap(tester, find.text('Update'));
}

/// The message on screen whose text contains [text].
Finder _messageText(String text) => find.descendant(
  of: find.byType(SnackBar),
  matching: find.textContaining(text),
);

/// The Undo of the message on screen.
final _undo = find.descendant(
  of: find.byType(SnackBar),
  matching: find.text('Undo'),
);

/// Taps at once: [_tap] settles first, which eats two of the five seconds
/// an Undo stays up.
Future<void> _tapNow(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await _settle(tester);
}

/// Past the five seconds of a message and its exit.
Future<void> _letMessagesGo(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  await _settle(tester);
}

/// As with VoiceOver or TalkBack on, for the rest of the test.
void _holdMessages(WidgetTester tester) {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(accessibleNavigation: true);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
}

/// "Move to…" from the menu of the row of the shelf named [name].
Future<void> _openMoveFromRow(WidgetTester tester, String name) async {
  await _openShelfRowMenu(tester, name);
  await _tap(tester, find.text('Move to…'));
}

/// Drags the shelf named [name] onto [target] and lets go: by its handle,
/// or by a long press on the row as a phone does. A [fast] drop lets go in
/// the frame the pointer arrives, as a quick mouse flick does.
Future<void> _dragShelf(
  WidgetTester tester,
  String name,
  Finder target, {
  bool longPress = false,
  bool fast = false,
  PointerDeviceKind kind = PointerDeviceKind.touch,
}) async {
  final gesture = await _startShelfDrag(
    tester,
    name,
    longPress: longPress,
    kind: kind,
  );
  // Read after the drag started: the first-level zone only shows then.
  await gesture.moveTo(tester.getCenter(target));
  if (!fast) await tester.pump();
  await gesture.up();
  await _settle(tester);
}

/// Picks up the shelf named [name] and holds it just off its place.
Future<TestGesture> _startShelfDrag(
  WidgetTester tester,
  String name, {
  bool longPress = false,
  PointerDeviceKind kind = PointerDeviceKind.touch,
}) async {
  final from = longPress ? _treeRow(name) : _treeHandle(name);
  await tester.ensureVisible(from);
  await _settle(tester);
  final gesture = await tester.startGesture(
    tester.getCenter(from),
    kind: kind,
  );
  if (longPress) {
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
  }
  await gesture.moveBy(const Offset(0, 24));
  await tester.pump();
  await tester.pump();
  return gesture;
}

/// Holds [gesture] just under the first-level zone until the list has made
/// room above its first row, which otherwise lies under the zone.
Future<void> _revealFirstRow(WidgetTester tester, TestGesture gesture) async {
  final zone = tester.getRect(_firstLevelZone);
  await gesture.moveTo(Offset(zone.center.dx, zone.bottom + 8));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Where a drag can let go over no drop target: the bottom navigation bar.
Offset _offTheTree(WidgetTester tester) =>
    Offset(tester.getCenter(find.byType(OrganizeShelvesScreen)).dx, _phone.height - 8);

/// The drag is over: no first-level zone, no branch greyed out.
void _expectDragOver(WidgetTester tester, List<String> rows) {
  expect(_firstLevelZone, findsNothing);
  for (final name in rows) {
    expect(
      tester.getSemantics(_treeRow(name)),
      containsSemantics(hasEnabledState: true, isEnabled: true),
      reason: name,
    );
  }
}

/// Living room › Novels › Crime › Nordic crime, and Study: four levels,
/// the deepest past the indentation cap.
final _treeTags = [
  Tag(id: 's1', name: 'Living room', count: 2),
  Tag(id: 's2', name: 'Novels', parentId: 's1', count: 3),
  Tag(id: 's3', name: 'Crime', parentId: 's2', count: 4),
  Tag(id: 's4', name: 'Nordic crime', parentId: 's3', count: 1),
  Tag(id: 's5', name: 'Study', count: 5),
];

final _moveSheet = find.byKey(const Key('moveShelfSheet'));

Finder _moveRow(String name) => find.descendant(
  of: _moveSheet,
  matching: find.byKey(ValueKey('placementRow:$name')),
);

/// Types in the picker's one field, past its debounce.
Future<void> _typeInShelfPicker(WidgetTester tester, String text) async {
  await tester.enterText(_inShelfSheet(find.byType(TextField)), text);
  await _settle(tester);
}

/// The main journey: the four destinations of the bottom bar and what a
/// reader opens from them. Listed by what they render, not by route, since
/// one route renders several states.
final _probes = <_Probe>[
  // Library. The cover grid is only the default layout: the other two are one
  // menu away and render different widgets for the same books.
  const _Probe('library, books tab', '/books'),
  _Probe(
    'library in shelf view',
    '/books',
    reach: (t) async {
      await _tap(t, find.byTooltip('Change View'));
      await t.tap(find.text('Shelf view').last);
      await _settle(t);
    },
  ),
  _Probe(
    'library in list view',
    '/books',
    reach: (t) async {
      await _tap(t, find.byTooltip('Change View'));
      await t.tap(find.text('List view').last);
      await _settle(t);
    },
  ),
  // Selection mode swaps the filter bar for its own, and turns every book
  // tile into a toggle.
  _Probe(
    'library, selection mode',
    '/books',
    reach: (t) async {
      await _tap(t, find.byKey(const Key('selectBooksButton')));
      await _tap(t, find.byKey(const Key('selectAllBooksButton')));
    },
  ),
  const _Probe('library, shelves tab', '/shelves'),
  const _Probe('library, sub-shelves', '/shelves?tag=Genre'),
  _Probe('library, place page', '/shelves?tag=Living+room', tags: _treeTags),
  _Probe('library, place page, deep', '/shelves?tag=Crime', tags: _treeTags),
  _Probe('library, place page, empty', '/shelves?tag=Kitchen', tags: [
    ..._treeTags,
    Tag(id: 's6', name: 'Kitchen', count: 0),
  ]),
  // The tree of the tab: chevrons, handles and menus on every row, four
  // levels deep.
  _Probe('organize shelves, tree', '/shelves-management', tags: _treeTags),
  // A shelf picked up: its branch greyed, the first-level zone shown.
  _Probe(
    'organize shelves, during a drag',
    '/shelves-management',
    tags: _treeTags,
    reach: (t) async {
      await _startShelfDrag(t, 'Novels');
    },
  ),
  // A deletion waiting on its Undo, held as a screen reader holds it: the
  // message is a live region, Undo a named button.
  _Probe(
    'organize shelves, a deletion to undo',
    '/shelves-management',
    size: _tallPhone,
    tags: _treeTags,
    reach: (t) async {
      _holdMessages(t);
      await _deleteFromRow(t, 'Study');
    },
  ),
  // "Move to…" from a row: the placement tree, a branch greyed out and the
  // current place marked, both read as disabled.
  _Probe(
    'organize shelves, move tree',
    '/shelves-management',
    reach: (t) => _openMoveFromRow(t, 'Science fiction'),
  ),
  // The "to shelve" card's list: selection armed from the start, a header of
  // its own in a tab that has no app bar.
  const _Probe('library, to shelve', _toShelveLocation),
  // The collections module is off for a new reader and on for many others:
  // it adds a third library tab and groups the book list by collection.
  const _Probe(
    'library, books grouped by collection',
    '/books',
    collections: true,
  ),
  const _Probe('library, collections tab', '/collections', collections: true),
  const _Probe('collection detail', '/collections/c1', collections: true),
  const _Probe('add a book', '/books/add'),
  // The shelf picker the form opens: its tree, a name to create, and the
  // placement tree behind "Create in a shelf…".
  _Probe('add a book, shelf picker', '/books/add', reach: _openShelfPicker),
  _Probe(
    'add a book, shelf picker, a new name',
    '/books/add',
    reach: (t) async {
      await _openShelfPicker(t);
      await _typeInShelfPicker(t, 'Night');
    },
  ),
  _Probe(
    'add a book, shelf picker, a taken name',
    '/books/add',
    reach: (t) async {
      await _openShelfPicker(t);
      await _typeInShelfPicker(t, 'science FICTION');
    },
  ),
  _Probe(
    'add a book, placement tree',
    '/books/add',
    reach: (t) async {
      await _openShelfPicker(t);
      await _typeInShelfPicker(t, 'Night');
      await _tap(t, find.text('Create in a shelf…'));
    },
  ),
  // The book page, in the three states its actions branch on.
  const _Probe('book details, being read', '/books/b2'),
  const _Probe('book details, finished and rated', '/books/b3'),
  const _Probe('book details, wished for', '/books/b4'),
  // Network.
  const _Probe('network', '/network'),
  _Probe(
    'network, directory tab',
    '/network',
    reach: (t) => _tap(t, find.text('Directory')),
  ),
  // Loans, one tab at a time.
  const _Probe('loans, requests', '/requests'),
  _Probe('loans, lent', '/requests', reach: (t) => _tap(t, find.text('Lent'))),
  _Probe(
    'loans, borrowed',
    '/requests',
    reach: (t) => _tap(t, find.text('Borrowed')),
  ),
  // Insights and the profile.
  const _Probe('dashboard', '/dashboard'),
  _Probe(
    'dashboard, statistics tab',
    '/dashboard',
    reach: (t) => _tap(t, find.text('Statistics')),
  ),
  const _Probe('profile', '/profile'),
  const _Probe('settings', '/settings'),
  // Each settings section has its own page, with its inner panels opened.
  for (final group in settingsSectionGroups)
    for (final section in group.sections)
      _Probe(
        'settings, ${section.name}',
        '/settings/${section.name}',
        reach: _expandAll,
      ),
  // Navigation itself: the drawer (bottom bar off) and the rail (wide).
  _Probe(
    'drawer',
    '/books',
    bottomNav: false,
    reach: (t) => _tap(t, find.byTooltip('Open menu')),
  ),
  const _Probe('navigation rail', '/books', size: _desktop),
];

/// Renders [probe] and leaves it settled on the state under audit. [books]
/// replaces the fixture library.
Future<_Harness> _render(
  WidgetTester tester,
  _Probe probe, {
  List<Book>? books,
  List<Tag>? tags,
}) async {
  tester.view.physicalSize = probe.size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  // The test font draws every glyph as a full square, so a row sized for
  // real text can overflow here and nowhere else. Layout is not what this
  // guard measures; an overflow must not mask what it does.
  final reportError = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exceptionAsString().contains('overflowed')) return;
    reportError?.call(details);
  };
  addTearDown(() => FlutterError.onError = reportError);
  final harness = _Harness(await SharedPreferences.getInstance());
  if (books != null) harness.books.mockBooks = books;
  final shelves = tags ?? probe.tags;
  if (shelves != null) harness.tags.mockTags = shelves;
  // Both setters also push the module list to a server that is not there
  // under test; the flag itself is set before that call and is all the
  // screens read.
  if (probe.collections) {
    await tester.runAsync(() => harness.theme.setCollectionsEnabled(true));
  }
  if (!probe.bottomNav) {
    await tester.runAsync(() => harness.theme.setBottomNavEnabled(false));
  }
  await tester.pumpWidget(harness.app(probe.location));
  await _settle(tester);
  await probe.reach?.call(tester);
  return harness;
}

Future<void> _setUpAll() async {
  // `ApiService.hubUrl` reads the env; the settings page renders it.
  dotenv.testLoad();
  // The real English catalogue, so a label that resolves to a raw key or to
  // nothing shows up as what a reader would hear.
  await TranslationService.loadTranslations();
}

void _setUp() {
  SharedPreferences.setMockInitialValues({
    'languageCode': 'en',
    // A shelf picked in an earlier form, plus one deleted since: the add
    // form shows the first and hides the second.
    'recent_shelf_names': ['Novel', 'Gone shelf'],
    // The dashboard's quote of the day is drawn at random unless a fresh one
    // is cached; a fixed one keeps the probe the same from run to run.
    'quote_cache_v2_en': jsonEncode({
      'text': 'A room without books is like a body without a soul.',
      'author': 'Cicero',
      'source': 'Philosophy',
      'locale': 'en',
      'cachedAt': DateTime.now().toIso8601String(),
    }),
  });
}

void main() {
  setUpAll(_setUpAll);
  setUp(_setUp);

  // Not a semantics check, but a crash the lot moving this key exposed: the
  // borrower tile's key became a direct child key of the network list, and
  // every borrower shared `memberTile_0`, which broke the list on rebuild.
  testWidgets('each borrower tile of the network list has its own key', (
    tester,
  ) async {
    await _render(tester, _probes.firstWhere((p) => p.name == 'network'));
    expect(find.byKey(const Key('memberTile_k1')), findsOneWidget);
    expect(find.byKey(const Key('memberTile_k2')), findsOneWidget);
  });

  // The "To Read" header counts the whole pile, while its row shows at most
  // ten covers; a screen reader hears the count in words, not the middle dot.
  testWidgets('the dashboard to-read header counts every book to read', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _render(
      tester,
      _probes.firstWhere((p) => p.name == 'dashboard'),
      books: [
        for (var i = 1; i <= 12; i++)
          Book(
            id: 'tr$i',
            title: 'Pile book $i',
            author: 'Author $i',
            readingStatus: 'to_read',
          ),
      ],
    );

    final header = find.text('To Read · 12');
    await tester.ensureVisible(header);
    await _settle(tester);
    expect(header, findsOneWidget);
    expect(
      tester.getSemantics(header),
      containsSemantics(label: 'To Read, 12 books', isHeader: true),
    );

    final row = tester.widget<ListView>(
      find.descendant(
        of: find.ancestor(of: header, matching: find.byType(Column)).first,
        matching: find.byType(ListView),
      ),
    );
    final delegate = row.childrenDelegate as SliverChildBuilderDelegate;
    expect(delegate.childCount, 10);
    semantics.dispose();
    // With the FFI down, the completeness card retries its stats four times,
    // two seconds apart: let the last retry fire before the test ends.
    await tester.pump(const Duration(seconds: 10));
  });

  // Not semantics checks either. Selection mode lives in the list body, and
  // `/books` renders the branch of the book list that has no app bar of its
  // own: only the real route proves the mode is mounted where the reader is.
  group('library selection mode on the real route', () {
    final selectButton = find.byKey(const Key('selectBooksButton'));
    final selectAll = find.byKey(const Key('selectAllBooksButton'));
    final addTo = find.byKey(const Key('bulkAssignButton'));

    /// Picks the fixture collection in the destination sheet and confirms.
    Future<void> fileIntoSummerReads(WidgetTester tester) async {
      final field = find.descendant(
        of: find.byType(CollectionSelector),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(field, 'Summer reads');
      await _tap(
        tester,
        find.descendant(
          of: find.byType(CollectionSelector),
          matching: find.byIcon(Icons.add),
        ),
      );
      await _tap(tester, find.byKey(const Key('bulkAssignConfirmButton')));
    }

    testWidgets('files every visible book and leaves the mode', (tester) async {
      final harness = await _render(
        tester,
        _probes.firstWhere((p) => p.name == 'library, books tab'),
      );

      await _tap(tester, selectButton);
      expect(find.text('0 selected'), findsOneWidget);
      // The wished-for book is outside the default view: three remain.
      await _tap(tester, selectAll);
      expect(find.text('3 selected'), findsOneWidget);

      await _tap(tester, addTo);
      await fileIntoSummerReads(tester);

      final sent = harness.collections.lastAssignment!;
      expect(sent['bookIds']!.toSet(), {'b1', 'b2', 'b3'});
      expect(sent['addCollectionIds'], ['c1']);
      expect(sent['removeShelves'], isEmpty);
      expect(addTo, findsNothing);
      expect(selectButton, findsOneWidget);
    });

    testWidgets('back leaves the mode before it leaves the library', (
      tester,
    ) async {
      await _render(
        tester,
        _probes.firstWhere((p) => p.name == 'library, books tab'),
      );
      await _tap(tester, selectButton);
      expect(addTo, findsOneWidget);

      await tester.binding.handlePopRoute();
      await _settle(tester);

      expect(addTo, findsNothing);
      expect(selectButton, findsOneWidget);
    });

    testWidgets('leaving the mode gives the grouped view back', (tester) async {
      // The view menu does not offer the grouped view: a reader moved to the
      // covers grid for the selection has no other way back to it.
      await _render(
        tester,
        _probes.firstWhere(
          (p) => p.name == 'library, books grouped by collection',
        ),
      );
      expect(find.byType(CollectionGroupGrid), findsOneWidget);

      await _tap(tester, selectButton);
      expect(find.byType(BookCoverGrid), findsOneWidget);
      expect(find.byType(CollectionGroupGrid), findsNothing);

      await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(find.byType(CollectionGroupGrid), findsOneWidget);
    });

    testWidgets('an open shelf can be moved out of', (tester) async {
      final harness = await _render(
        tester,
        const _Probe('shelf', '/books?tag=Novel'),
      );
      await _tap(tester, selectButton);
      await _tap(tester, selectAll);
      expect(find.text('1 selected'), findsOneWidget);

      await _tap(tester, addTo);
      await _tap(tester, find.text('Remove from “Novel”'));
      await fileIntoSummerReads(tester);

      final sent = harness.collections.lastAssignment!;
      expect(sent['bookIds'], ['b1']);
      expect(sent['removeShelves'], ['Novel']);
    });
  });

  // The list behind the shelves tab's "to shelve" card, on the real route.
  group('to shelve list on the real route', () {
    final addTo = find.byKey(const Key('bulkAssignButton'));
    final selectAll = find.byKey(const Key('selectAllBooksButton'));
    final toShelve = _probes.firstWhere((p) => p.name == 'library, to shelve');

    testWidgets('holds only the books on no shelf, selection armed', (
      tester,
    ) async {
      await _render(tester, toShelve);

      expect(find.text('To shelve'), findsOneWidget);
      expect(find.text('1 book on no shelf'), findsOneWidget);
      // Armed on arrival: the reader came here to pick books.
      expect(addTo, findsOneWidget);
      expect(find.text('0 selected'), findsOneWidget);
      // Two books are on a shelf, the wished one is outside the default view:
      // one remains.
      await _tap(tester, selectAll);
      expect(find.text('1 selected'), findsOneWidget);
    });

    testWidgets('keeps to the default view whatever axis is remembered', (
      tester,
    ) async {
      // The card counts the default view; a remembered "everything" must not
      // pull the wished book into the list it opens.
      SharedPreferences.setMockInitialValues({
        'languageCode': 'en',
        'library_ownership_scope': 'all',
      });
      await _render(tester, toShelve);

      await _tap(tester, selectAll);
      expect(find.text('1 selected'), findsOneWidget);
    });

    testWidgets('back from the header returns to the shelves grid', (
      tester,
    ) async {
      await _render(tester, toShelve);

      await _tap(tester, find.byKey(const Key('toShelveBackButton')));

      expect(addTo, findsNothing);
      expect(find.byKey(const Key('toShelveCard')), findsOneWidget);
      expect(find.text('Novel'), findsOneWidget);
    });

    testWidgets('waits for a page opened on top before giving the grid back', (
      tester,
    ) async {
      final harness = await _render(tester, toShelve);
      await _tap(tester, find.byTooltip('Cancel'));
      await _tap(tester, find.text('Mrs Dalloway').first);
      expect(find.byType(BookDetailsScreen), findsOneWidget);

      // The last book gets a shelf from its own page: the list underneath
      // empties, and must not pull the reader out of the page they are on.
      harness.books.mockBooks = [
        for (final b in _books)
          if (b.id != 'b3') b,
        Book(
          id: 'b3',
          title: 'Mrs Dalloway',
          author: 'Virginia Woolf',
          readingStatus: 'read',
          subjects: ['Novel'],
        ),
      ];
      harness.tags.mockUnshelvedCount = 0;
      harness.refresh.refresh();
      await _settle(tester);
      expect(find.byType(BookDetailsScreen), findsOneWidget);

      // Back on the emptied list: now it hands the grid back.
      await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(find.byType(BookDetailsScreen), findsNothing);
      expect(find.byKey(const Key('toShelveCard')), findsNothing);
      expect(find.text('Novel'), findsOneWidget);
    });

    testWidgets('a status filter that hides every book is not an empty list', (
      tester,
    ) async {
      // Nothing on no shelf is being read, but Mrs Dalloway still waits: the
      // reader stays where they filtered.
      await _render(
        tester,
        const _Probe('to shelve, reading', '$_toShelveLocation&status=reading'),
      );

      expect(find.text('To shelve'), findsOneWidget);
      expect(find.byKey(const Key('toShelveCard')), findsNothing);
      // The header counts what is left to shelve, as the card did, not what
      // the filter happens to show.
      expect(find.text('1 book on no shelf'), findsOneWidget);
    });

    testWidgets('once its books are shelved, gives the grid back', (
      tester,
    ) async {
      final harness = await _render(tester, toShelve);
      await _tap(tester, selectAll);
      await _tap(tester, addTo);

      // What the filing writes, as the next read of the library sees it.
      harness.books.mockBooks = [
        for (final b in _books)
          if (b.id != 'b3') b,
        Book(
          id: 'b3',
          title: 'Mrs Dalloway',
          author: 'Virginia Woolf',
          readingStatus: 'read',
          subjects: ['Novel'],
        ),
      ];
      harness.tags.mockUnshelvedCount = 0;
      final field = find.descendant(
        of: find.byType(CollectionSelector),
        matching: find.byType(TextFormField),
      );
      await tester.enterText(field, 'Summer reads');
      await _tap(
        tester,
        find.descendant(
          of: find.byType(CollectionSelector),
          matching: find.byIcon(Icons.add),
        ),
      );
      await _tap(tester, find.byKey(const Key('bulkAssignConfirmButton')));
      await _settle(tester);

      expect(addTo, findsNothing);
      expect(find.byKey(const Key('toShelveCard')), findsNothing);
      expect(find.text('Novel'), findsOneWidget);
    });
  });

  // The order a reader gives a shelf by hand, on the real route: the shelves
  // tab renders the list in the branch that has no app bar, so the action
  // has to be in the list's own header, and the saved order has to survive
  // the list's sort.
  group('shelf order on the real route', () {
    final reorder = find.byTooltip('Reorder shelf');
    const shelf = _Probe('shelf, from the shelves tab', '/shelves?tag=Novel');

    // Two books on the Novel shelf, so an order means something.
    final novels = [
      for (final b in _books) b,
      Book(
        id: 'b5',
        title: 'Zazie',
        author: 'Raymond Queneau',
        readingStatus: 'read',
        subjects: ['Novel'],
      ),
    ];

    /// Top-left of a book's tile in the list, to compare where two books
    /// sit. Read in the list layout, through the tile's own label: a covered
    /// book paints no title text, and the activity carousel above the list
    /// names the same books.
    Offset at(WidgetTester tester, String title) => tester.getTopLeft(
      find.byWidgetPredicate(
        (w) => w is SelectableBookTile && w.semanticLabel.startsWith(title),
      ),
    );

    Future<void> toListView(WidgetTester tester) async {
      await _tap(tester, find.byTooltip('Change View'));
      await tester.tap(find.text('List view').last);
      await _settle(tester);
    }

    bool before(Offset a, Offset b) =>
        a.dy < b.dy || (a.dy == b.dy && a.dx < b.dx);

    /// Opens the sort menu from its pill, which paints the current field.
    Future<void> openSortMenu(WidgetTester tester, String field) async {
      await _tap(tester, find.text(field));
    }

    Finder checkedMenuItem(String label) => find.descendant(
      of: find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
      ),
      matching: find.byIcon(Icons.check),
    );

    testWidgets('an open shelf offers the action; the grid and the books tab '
        'do not', (tester) async {
      await _render(tester, shelf);
      expect(reorder, findsOneWidget);
      expect(find.text('Novel'), findsOneWidget);
      expect(find.byKey(const Key('shelfBackButton')), findsOneWidget);
    });

    testWidgets('the reorder action does not wear the sort pill glyph', (
      tester,
    ) async {
      await _render(tester, shelf);
      // The sort pill just below uses Icons.sort: the same glyph on the
      // action made two different controls look like one.
      expect(
        find.descendant(of: reorder, matching: find.byIcon(Icons.swap_vert)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: reorder, matching: find.byIcon(Icons.sort)),
        findsNothing,
      );
    });

    testWidgets('the shelves grid has no reorder action', (tester) async {
      await _render(
        tester,
        _probes.firstWhere((p) => p.name == 'library, shelves tab'),
      );
      expect(reorder, findsNothing);
    });

    testWidgets('the books tab has no reorder action', (tester) async {
      await _render(
        tester,
        _probes.firstWhere((p) => p.name == 'library, books tab'),
      );
      expect(reorder, findsNothing);
    });

    testWidgets('a long shelf name wraps beside the fan, the actions stay put', (
      tester,
    ) async {
      const longName =
          'A shelf whose name goes on far longer than a phone is wide';
      await _render(
        tester,
        const _Probe('long shelf', '/shelves?tag=$longName'),
        books: [
          for (final b in _books) b,
          Book(
            id: 'b6',
            title: 'Long',
            readingStatus: 'read',
            subjects: [longName],
          ),
        ],
      );
      final icon = tester.getRect(reorder);
      final title = tester.getRect(find.byKey(const Key('shelfHeaderTitle')));
      final fan = tester.getRect(find.byKey(const Key('shelfPlaceFan')));
      expect(icon.right, lessThanOrEqualTo(_phone.width));
      expect(fan.right, lessThanOrEqualTo(_phone.width));
      expect(title.right, lessThanOrEqualTo(fan.left));
    });

    testWidgets('saving an order raises the shelf order and gives the grid '
        'back', (tester) async {
      final harness = await _render(tester, shelf, books: novels);
      expect(find.byType(BookCoverGrid), findsOneWidget);

      await _tap(tester, reorder);
      expect(find.text('Reordering Shelf...'), findsOneWidget);
      expect(reorder, findsNothing);
      // Drag and drop needs the list.
      expect(find.byType(ReorderableListView), findsOneWidget);

      await _tap(tester, find.byTooltip('Save order'));

      // Author A-Z was the order on screen, by surname: Queneau, Le Tellier.
      expect(harness.books.lastReorder, ['b5', 'b1']);
      // The covers grid the reader was in comes back, not the list.
      expect(find.byType(ReorderableListView), findsNothing);
      expect(find.byType(BookCoverGrid), findsOneWidget);
      expect(
        find.text(
          'Order saved. The books on this shelf now follow your order.',
        ),
        findsOneWidget,
      );
      final prefs = await SharedPreferences.getInstance();
      // Novel, and Novel alone, follows its order now.
      expect(prefs.getStringList('shelf_order_ids'), ['t1']);
      expect(prefs.getString('library_sort_by'), isNull);
      expect(find.text('Shelf order'), findsOneWidget);
    });

    testWidgets('saving an order leaves the library sort as the reader set '
        'it', (tester) async {
      SharedPreferences.setMockInitialValues({
        'languageCode': 'en',
        'library_sort_by': 'title',
        'library_sort_dir': 'desc',
      });
      await _render(tester, shelf, books: novels);
      await _tap(tester, reorder);
      await _tap(tester, find.byTooltip('Save order'));
      expect(find.text('Shelf order'), findsOneWidget);

      // Out of the shelf, into the books tab: "Title Z-A" is still the sort.
      await _tap(tester, find.byKey(const Key('shelfBackButton')));
      await _tap(tester, find.widgetWithText(Tab, 'Books'));
      await toListView(tester);
      // The list builds only what fits: its first two tiles say the order.
      // Title Z-A opens on Zazie then The Anomaly; author A-Z would open on
      // Dune (Herbert), and so would title A-Z.
      final tiles = tester
          .widgetList<SelectableBookTile>(find.byType(SelectableBookTile))
          .map((t) => t.semanticLabel.split(',').first)
          .toList();
      expect(tiles.take(2), ['Zazie', 'The Anomaly']);
      expect(find.text('Title'), findsOneWidget);
      expect(find.text('Shelf order'), findsNothing);
      await openSortMenu(tester, 'Title');
      expect(checkedMenuItem('Title (Z-A)'), findsOneWidget);
      expect(find.text('Shelf order'), findsNothing);
    });

    testWidgets('leaving the mode without saving gives the grid back too', (
      tester,
    ) async {
      await _render(tester, shelf, books: novels);
      await _tap(tester, reorder);
      expect(find.byType(ReorderableListView), findsOneWidget);

      await _tap(tester, find.byTooltip('Cancel'));

      expect(find.byType(ReorderableListView), findsNothing);
      expect(find.byType(BookCoverGrid), findsOneWidget);
      expect(reorder, findsOneWidget);
    });

    testWidgets('a selection in progress hides the reorder action', (
      tester,
    ) async {
      await _render(tester, shelf, books: novels);
      await _tap(tester, find.byKey(const Key('selectBooksButton')));
      expect(reorder, findsNothing);

      await tester.binding.handlePopRoute();
      await _settle(tester);
      expect(reorder, findsOneWidget);
    });

    testWidgets('a saved order is what the shelf shows', (tester) async {
      // Title Z-A would open on Zazie too: only the positions put The
      // Anomaly first.
      SharedPreferences.setMockInitialValues({
        'languageCode': 'en',
        'shelf_order_ids': ['t1'],
        'library_sort_by': 'title',
        'library_sort_dir': 'desc',
      });
      await _render(
        tester,
        shelf,
        books: [
          for (final b in _books)
            if (b.id != 'b1') b,
          // Positions that contradict the author order (Queneau < Tellier).
          Book(
            id: 'b1',
            title: 'The Anomaly',
            author: 'Herve Le Tellier',
            readingStatus: 'to_read',
            subjects: ['Novel'],
            shelfPosition: 0,
          ),
          Book(
            id: 'b5',
            title: 'Zazie',
            author: 'Raymond Queneau',
            readingStatus: 'read',
            subjects: ['Novel'],
            shelfPosition: 1,
          ),
        ],
      );
      await toListView(tester);
      expect(before(at(tester, 'The Anomaly'), at(tester, 'Zazie')), isTrue);
      expect(find.text('Shelf order'), findsOneWidget);

      await openSortMenu(tester, 'Shelf order');
      expect(checkedMenuItem('Shelf order'), findsOneWidget);
    });

    testWidgets('outside a shelf the saved order never applies', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'languageCode': 'en',
        'shelf_order_ids': ['t1'],
      });
      await _render(
        tester,
        _probes.firstWhere((p) => p.name == 'library, books tab'),
        books: [
          for (final b in _books)
            if (b.id != 'b1' && b.id != 'b2') b,
          // Positions that contradict the author order.
          Book(
            id: 'b1',
            title: 'The Anomaly',
            author: 'Herve Le Tellier',
            readingStatus: 'to_read',
            subjects: ['Novel'],
            shelfPosition: 0,
          ),
          Book(
            id: 'b2',
            title: 'Dune',
            author: 'Frank Herbert',
            readingStatus: 'reading',
            subjects: ['Science fiction'],
            shelfPosition: 9,
          ),
        ],
      );
      await toListView(tester);
      // Herbert before Le Tellier.
      expect(before(at(tester, 'Dune'), at(tester, 'The Anomaly')), isTrue);
      expect(find.text('Shelf order'), findsNothing);
      expect(find.text('Author'), findsOneWidget);

      await openSortMenu(tester, 'Author');
      expect(find.text('Shelf order'), findsNothing);
      expect(checkedMenuItem('Author (A-Z)'), findsOneWidget);
    });

    testWidgets('the sort menu of an open shelf offers the shelf order', (
      tester,
    ) async {
      await _render(tester, shelf);
      await openSortMenu(tester, 'Author');
      expect(find.text('Shelf order'), findsOneWidget);
      expect(checkedMenuItem('Author (A-Z)'), findsOneWidget);
    });

    // Each shelf remembers whether it follows its own order: what is chosen
    // in one shelf never reorders another.
    Future<void> openShelf(WidgetTester tester, String name) async {
      GoRouter.of(
        tester.element(find.byType(LibraryScreen)),
      ).go('/shelves?tag=${Uri.encodeQueryComponent(name)}');
      await _settle(tester);
    }

    Future<void> pickSort(WidgetTester tester, String pill, String item) async {
      await openSortMenu(tester, pill);
      await tester.tap(find.text(item).last);
      await _settle(tester);
    }

    // Two books on Science fiction whose positions contradict the author
    // order (Herbert before Simmons).
    final twoShelves = [
      for (final b in novels)
        if (b.id != 'b2') b,
      Book(
        id: 'b2',
        title: 'Dune',
        author: 'Frank Herbert',
        readingStatus: 'reading',
        subjects: ['Science fiction'],
        shelfPosition: 1,
      ),
      Book(
        id: 'b6',
        title: 'Hyperion',
        author: 'Dan Simmons',
        readingStatus: 'read',
        subjects: ['Science fiction'],
        shelfPosition: 0,
      ),
    ];

    testWidgets('an order saved on one shelf leaves another on the library '
        'sort', (tester) async {
      await _render(tester, shelf, books: twoShelves);
      await _tap(tester, reorder);
      await _tap(tester, find.byTooltip('Save order'));
      expect(find.text('Shelf order'), findsOneWidget);

      await openShelf(tester, 'Science fiction');
      await toListView(tester);

      expect(find.text('Author'), findsOneWidget);
      expect(find.text('Shelf order'), findsNothing);
      expect(before(at(tester, 'Dune'), at(tester, 'Hyperion')), isTrue);
    });

    testWidgets('a field sort picked in one shelf leaves the order of '
        'another', (tester) async {
      await _render(tester, shelf, books: twoShelves);
      await pickSort(tester, 'Author', 'Shelf order');
      await openShelf(tester, 'Science fiction');
      await pickSort(tester, 'Author', 'Shelf order');
      await pickSort(tester, 'Shelf order', 'Author (A-Z)');
      expect(find.text('Author'), findsOneWidget);

      await openShelf(tester, 'Novel');
      expect(find.text('Shelf order'), findsOneWidget);
    });

    testWidgets('deleting a shelf forgets its order', (tester) async {
      SharedPreferences.setMockInitialValues({
        'languageCode': 'en',
        'shelf_order_ids': ['t1', 't3'],
      });
      await _render(tester, const _Probe('shelves', '/shelves-management'));

      await _openShelfRowMenu(tester, 'Novel');
      await _tap(tester, find.text('Delete Shelf'));
      // The deletion goes, and its order with it, once its Undo is past.
      await _letMessagesGo(tester);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('shelf_order_ids'), ['t3']);
    });

    testWidgets('the order of a shelf gone meanwhile is forgotten', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'languageCode': 'en',
        'shelf_order_ids': ['t1', 'gone'],
      });
      await _render(tester, const _Probe('shelves', '/shelves'));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('shelf_order_ids'), ['t1']);
    });

    // A shelf known only from the books, with two books on it.
    final looseBooks = [
      for (final b in _books) b,
      Book(id: 'b7', title: 'Loose leaves', author: 'Ann Able',
          readingStatus: 'read', subjects: ['Loose']),
      Book(id: 'b8', title: 'Loose ends', author: 'Bob Baker',
          readingStatus: 'read', subjects: ['Loose']),
    ];
    final looseTags = [
      ..._tags,
      Tag(id: '${Tag.syntheticIdPrefix}-1', name: 'Loose', count: 2),
    ];
    const looseShelf = _Probe('loose shelf', '/shelves?tag=Loose');

    testWidgets('a shelf known only from the books follows its order once it '
        'has its row, created once', (tester) async {
      final harness = await _render(
        tester,
        looseShelf,
        books: looseBooks,
        tags: looseTags,
      );

      await pickSort(tester, 'Author', 'Shelf order');
      expect(find.text('Shelf order'), findsOneWidget);
      await pickSort(tester, 'Shelf order', 'Shelf order');

      expect(harness.tags.created, ['Loose']);
    });

    testWidgets('a shelf given its row meanwhile is found by name', (
      tester,
    ) async {
      final harness = await _render(
        tester,
        looseShelf,
        books: looseBooks,
        tags: looseTags,
      );
      // A sync created the row since the list loaded: creating it again
      // fails on the unique name.
      harness.tags
        ..mockTags = [..._tags, Tag(id: 'u9', name: 'Loose', count: 2)]
        ..mockCreateError = Exception('UNIQUE constraint failed: tags.name');

      await pickSort(tester, 'Author', 'Shelf order');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('shelf_order_ids'), ['u9']);
      expect(find.text('Shelf order'), findsOneWidget);
    });

    testWidgets('saving an order the shelf cannot follow says so', (
      tester,
    ) async {
      final harness = await _render(
        tester,
        looseShelf,
        books: looseBooks,
        tags: looseTags,
      );
      harness.tags.mockCreateError = Exception('storage failure');

      await _tap(tester, reorder);
      await _tap(tester, find.byTooltip('Save order'));

      expect(find.textContaining('Order saved'), findsNothing);
      expect(find.textContaining('Error saving order'), findsOneWidget);
    });

    testWidgets('a shelf whose name differs from another only by case keeps '
        'its own order', (tester) async {
      // Shelf names are unique byte for byte: "Novel" and "novel" are two
      // shelves.
      await _render(
        tester,
        const _Probe('lower-case shelf', '/shelves?tag=novel'),
        books: [
          for (final b in _books) b,
          Book(id: 'b9', title: 'Lower', readingStatus: 'read',
              subjects: ['novel']),
        ],
        tags: [..._tags, Tag(id: 't9', name: 'novel', count: 1)],
      );

      await pickSort(tester, 'Author', 'Shelf order');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('shelf_order_ids'), ['t9']);
    });

    testWidgets('"Shelf order" a shelf cannot follow says so', (tester) async {
      final harness = await _render(
        tester,
        looseShelf,
        books: looseBooks,
        tags: looseTags,
      );
      harness.tags.mockCreateError = Exception('storage failure');

      await pickSort(tester, 'Author', 'Shelf order');

      expect(find.textContaining('Error saving order'), findsOneWidget);
    });

    testWidgets('a failed save leaves the books in the order the sort '
        'announces', (tester) async {
      final harness = await _render(
        tester,
        looseShelf,
        books: looseBooks,
        tags: looseTags,
      );
      harness.tags.mockCreateError = Exception('storage failure');
      await toListView(tester);
      await _tap(tester, reorder);

      // Ends (Baker, b8) dragged above Leaves (Able, b7) by its handle. The
      // cards are keyed `ValueKey(book.id ?? index)`, an Object key.
      final ends = find.byKey(const ValueKey<Object>('b8'));
      final leaves = find.byKey(const ValueKey<Object>('b7'));
      final gesture = await tester.startGesture(
        tester.getCenter(
          find.descendant(of: ends, matching: find.byIcon(Icons.drag_handle)),
        ),
      );
      await tester.pump();
      final lift = tester.getTopLeft(leaves).dy - tester.getTopLeft(ends).dy;
      for (var i = 1; i <= 4; i++) {
        await gesture.moveBy(Offset(0, (lift - 20) / 4));
        await tester.pump(const Duration(milliseconds: 50));
      }
      await gesture.up();
      await _settle(tester);
      expect(
        before(tester.getTopLeft(ends), tester.getTopLeft(leaves)),
        isTrue,
        reason: 'the drag did not move the book',
      );

      await _tap(tester, find.byTooltip('Save order'));
      expect(find.textContaining('Error saving order'), findsOneWidget);

      // Back to author A-Z, as the pill says: Able before Baker.
      expect(find.text('Author'), findsOneWidget);
      expect(
        before(at(tester, 'Loose leaves'), at(tester, 'Loose ends')),
        isTrue,
      );
    });

    testWidgets('a library that lists no shelf keeps every saved order', (
      tester,
    ) async {
      // The FFI listing answers an empty list on any core error: nothing
      // there says the shelves are gone.
      SharedPreferences.setMockInitialValues({
        'languageCode': 'en',
        'shelf_order_ids': ['t1'],
      });
      await _render(
        tester,
        const _Probe('shelves', '/shelves-management'),
        tags: const [],
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('shelf_order_ids'), ['t1']);
    });

    testWidgets('a shelf known only from the books gets its row before it '
        'follows its order', (tester) async {
      final harness = await _render(
        tester,
        const _Probe('loose shelf', '/shelves?tag=Loose'),
        books: [
          for (final b in _books) b,
          Book(id: 'b7', title: 'Loose', readingStatus: 'read',
              subjects: ['Loose']),
        ],
        tags: [
          ..._tags,
          Tag(id: '${Tag.syntheticIdPrefix}-1', name: 'Loose', count: 1),
        ],
      );

      await pickSort(tester, 'Author', 'Shelf order');

      // The mock gives every created row the id '1'.
      expect(harness.tags.created, ['Loose']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('shelf_order_ids'), ['1']);
    });
  });

  // The shelves of the add form, on the real route: the genre chips above
  // them, the recent shelves under them, and the picker they open.
  group('shelves in the add form on the real route', () {
    final addForm = _probes.firstWhere((p) => p.name == 'add a book');
    final selector = find.byType(HierarchicalTagSelector);
    Finder recent(String name) => find.byKey(ValueKey('recentShelf:$name'));
    Finder row(String name) => _inShelfSheet(
      find.byKey(ValueKey('shelfRow:$name')),
    );
    Finder createNamed(String name) =>
        _inShelfSheet(find.text('Create “$name”'));
    final takenHint = _inShelfSheet(
      find.textContaining('A book can be on several shelves'),
    );

    testWidgets('a recent shelf is one tap away, and leaves the row once '
        'picked', (tester) async {
      await _render(tester, addForm);
      await _revealInForm(tester, recent('Novel'));

      expect(find.descendant(of: selector, matching: find.text('Recent')),
          findsOneWidget);
      expect(recent('Novel'), findsOneWidget);
      expect(recent('Gone shelf'), findsNothing, reason: 'deleted since');

      await _tap(tester, recent('Novel'));

      expect(
        find.descendant(of: selector, matching: find.widgetWithText(Chip,
            'Novel')),
        findsOneWidget,
      );
      expect(recent('Novel'), findsNothing);
      expect(
        find.descendant(of: selector, matching: find.text('Recent')),
        findsNothing,
        reason: 'nothing left to suggest',
      );
    });

    testWidgets('a genre picked above is not repeated in the shelves row', (
      tester,
    ) async {
      await _render(tester, addForm);
      await _revealInForm(tester, find.text('Science fiction'));
      await _tap(tester, find.text('Science fiction'));
      await _revealInForm(tester, find.byKey(const Key('addShelfChip')));

      expect(find.text('Science fiction'), findsOneWidget);
      expect(
        find.descendant(of: selector, matching: find.text('Science fiction')),
        findsNothing,
      );
    });

    testWidgets('saving the book remembers its shelves as recent', (
      tester,
    ) async {
      await _render(tester, addForm);
      await tester.enterText(find.byKey(const Key('titleField')), 'Germinal');
      await _revealInForm(tester, find.text('Science fiction'));
      await _tap(tester, find.text('Science fiction'));
      await _tap(tester, find.byKey(const Key('saveBookButton')));
      await tester.pump(const Duration(seconds: 1));

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('recent_shelf_names'), [
        'Science fiction',
        'Novel',
        'Gone shelf',
      ]);
    });

    testWidgets('a failing recent-shelves write still saves and closes the '
        'form', (tester) async {
      RecentShelvesStore.prefs = () async => throw StateError('disk full');
      addTearDown(
        () => RecentShelvesStore.prefs = SharedPreferences.getInstance,
      );
      final harness = await _render(tester, addForm);
      await tester.enterText(find.byKey(const Key('titleField')), 'Germinal');
      // A shelf, or there is nothing to record and the write never runs.
      await _revealInForm(tester, find.text('Science fiction'));
      await _tap(tester, find.text('Science fiction'));
      await _tap(tester, find.byKey(const Key('saveBookButton')));
      await tester.pump(const Duration(seconds: 1));
      await _settle(tester);

      expect(harness.books.lastCreate?['title'], 'Germinal');
      expect(harness.books.lastCreate?['subjects'], ['Science fiction']);
      expect(find.textContaining('Error saving'), findsNothing);
      expect(find.byType(AddBookScreen), findsNothing);
    });

    testWidgets('the picker says what it is for, without a checkbox', (
      tester,
    ) async {
      await _render(tester, addForm);
      await _openShelfPicker(tester);

      expect(_inShelfSheet(find.text('Choose shelves')), findsOneWidget);
      expect(_inShelfSheet(find.text('You can pick several')), findsOneWidget);
      expect(_inShelfSheet(find.byType(Checkbox)), findsNothing);
      expect(_inShelfSheet(find.text('Recent')), findsOneWidget);
      expect(_inShelfSheet(find.text('All Shelves')), findsOneWidget);
      // Unfolded: the sub-shelf is there without opening its parent.
      expect(row('Science fiction'), findsOneWidget);
    });

    testWidgets('its rows wear the same thumbnail as the shelves tab', (
      tester,
    ) async {
      await _render(tester, addForm);
      await _openShelfPicker(tester);

      for (final name in ['Novel', 'Science fiction']) {
        expect(
          find.descendant(of: row(name), matching: find.byType(ShelfThumbnail)),
          findsOneWidget,
          reason: name,
        );
      }
    });

    testWidgets('each row is a toggle that says whether it is checked', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _render(tester, addForm);
      await _openShelfPicker(tester);

      expect(
        tester.getSemantics(row('Novel')),
        containsSemantics(
          label: 'Novel',
          isButton: true,
          hasCheckedState: true,
          isChecked: false,
        ),
      );
      await _tap(tester, row('Novel'));
      expect(
        tester.getSemantics(row('Novel')),
        containsSemantics(isButton: true, hasCheckedState: true,
            isChecked: true),
      );
      handle.dispose();
    });

    testWidgets('a taken name offers no "Create" and raises the existing '
        'shelf', (tester) async {
      final harness = await _render(tester, addForm);
      await _openShelfPicker(tester);
      // Case and accents ignored: names are unique across the whole tree.
      await _typeInShelfPicker(tester, 'sciénce FICTION');

      expect(_inShelfSheet(find.textContaining('Create')), findsNothing);
      expect(row('Science fiction'), findsOneWidget);
      expect(
        _inShelfSheet(find.text('already exists, in Genre')),
        findsOneWidget,
      );
      expect(takenHint, findsOneWidget);

      await _tap(tester, row('Science fiction'));
      expect(harness.tags.created, isEmpty);
      await _tap(tester, _inShelfSheet(find.text('Done')));

      // Kept in the selection: the picker opens with it checked. (Not in
      // the shelves row, being a genre the chips above light.)
      final handle = tester.ensureSemantics();
      await _openShelfPicker(tester);
      expect(
        tester.getSemantics(row('Science fiction')),
        containsSemantics(hasCheckedState: true, isChecked: true),
      );
      handle.dispose();
    });

    testWidgets('a first-level shelf already taken says so, with no parent', (
      tester,
    ) async {
      await _render(tester, addForm);
      await _openShelfPicker(tester);
      await _typeInShelfPicker(tester, 'nóvel');

      expect(_inShelfSheet(find.text('already exists')), findsOneWidget);
      expect(createNamed('nóvel'), findsNothing);
    });

    testWidgets('a new name is created at the first level and checked in '
        'one tap', (tester) async {
      final handle = tester.ensureSemantics();
      final harness = await _render(tester, addForm);
      await _openShelfPicker(tester);
      await _typeInShelfPicker(tester, 'Night');

      // The create block leads the results.
      expect(createNamed('Night'), findsOneWidget);
      expect(
        _inShelfSheet(find.text('At the first level, picked right away')),
        findsOneWidget,
      );
      await _tap(tester, createNamed('Night'));

      expect(harness.tags.created, ['Night']);
      expect(
        tester.getSemantics(row('Night')),
        containsSemantics(isButton: true, hasCheckedState: true,
            isChecked: true),
      );
      handle.dispose();
    });

    testWidgets('Enter in the field creates the name it offers', (
      tester,
    ) async {
      final harness = await _render(tester, addForm);
      await _openShelfPicker(tester);
      await _typeInShelfPicker(tester, 'Night');

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await _settle(tester);

      expect(harness.tags.created, ['Night']);
    });

    testWidgets('"Create in a shelf…" places the new shelf where tapped', (
      tester,
    ) async {
      final harness = await _render(tester, addForm);
      await _openShelfPicker(tester);
      await _typeInShelfPicker(tester, 'Night');
      await _tap(tester, _inShelfSheet(find.text('Create in a shelf…')));

      expect(_inShelfSheet(find.text('Create “Night” in…')), findsOneWidget);
      await _tap(
        tester,
        _inShelfSheet(find.byKey(const ValueKey('placementRow:Genre'))),
      );

      expect(harness.tags.created, ['Night < t2']);
      // Back on the picker, the new shelf checked.
      expect(_inShelfSheet(find.text('Choose shelves')), findsOneWidget);
      expect(row('Night'), findsOneWidget);
    });

    testWidgets('a search result names its parent instead of nesting', (
      tester,
    ) async {
      await _render(tester, addForm);
      await _openShelfPicker(tester);
      await _typeInShelfPicker(tester, 'fic');

      expect(_inShelfSheet(find.text('Matching shelves')), findsOneWidget);
      expect(_inShelfSheet(find.text('in Genre')), findsOneWidget);
    });
  });

  // Moving a shelf goes through the placement tree, from the shelves tab and
  // from the management screen alike. A tap is the choice: there is no
  // confirm button that could send a shelf to the first level unasked.
  group('moving a shelf on the real routes', () {
    // Every level is on the tab at once: no descent to reach a sub-shelf.
    const subShelves = _Probe('sub-shelves', '/shelves-management');
    final firstLevel = find.descendant(
      of: _moveSheet,
      matching: find.byKey(const ValueKey('placementFirstLevel')),
    );

    testWidgets('a card offers "Move to…": its branch greyed, its place '
        'marked, a tap moves', (tester) async {
      final handle = tester.ensureSemantics();
      final harness = await _render(tester, subShelves);
      await _openMoveFromRow(tester, 'Science fiction');

      expect(
        find.descendant(
          of: _moveSheet,
          matching: find.text('Move “Science fiction” to…'),
        ),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(_moveRow('Science fiction')),
        containsSemantics(isButton: true, hasEnabledState: true,
            isEnabled: false),
      );
      expect(
        tester.getSemantics(_moveRow('Genre')),
        containsSemantics(isButton: true, hasEnabledState: true,
            isEnabled: false, value: 'Current place'),
      );
      await tester.tap(_moveRow('Science fiction'), warnIfMissed: false);
      await tester.tap(_moveRow('Genre'), warnIfMissed: false);
      await _settle(tester);
      expect(harness.tags.updated, isEmpty);

      await _tap(tester, _moveRow('Novel'));
      expect(harness.tags.updated, ['t3: Science fiction < t1']);
      expect(_moveSheet, findsNothing);
      expect(find.text('Science fiction moved under Novel'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('"At the first level" moves with no parent', (tester) async {
      final harness = await _render(tester, subShelves);
      await _openMoveFromRow(tester, 'Science fiction');

      await _tap(tester, firstLevel);
      expect(harness.tags.updated, ['t3: Science fiction']);
      expect(
        find.text('Science fiction moved to the first level'),
        findsOneWidget,
      );
    });

    testWidgets('a first-level shelf finds the first level marked as its '
        'place, not offered', (tester) async {
      final handle = tester.ensureSemantics();
      final harness = await _render(
        tester,
        const _Probe('shelves', '/shelves-management'),
      );
      await _openMoveFromRow(tester, 'Novel');

      expect(
        tester.getSemantics(firstLevel),
        containsSemantics(isButton: true, hasEnabledState: true,
            isEnabled: false, value: 'Current place'),
      );
      await tester.tap(firstLevel, warnIfMissed: false);
      await _settle(tester);
      expect(harness.tags.updated, isEmpty);
      expect(_moveSheet, findsOneWidget);
      handle.dispose();
    });

    testWidgets('the edit dialog only renames, and leaves the shelf where it '
        'is', (tester) async {
      final harness = await _render(tester, subShelves);
      await _openShelfRowMenu(tester, 'Science fiction');
      await _tap(tester, find.text('Edit Shelf'));

      final dialog = find.byType(AlertDialog);
      expect(dialog, findsOneWidget);
      expect(
        find.descendant(
          of: dialog,
          matching: find.byType(DropdownButtonFormField<Tag?>),
        ),
        findsNothing,
      );
      expect(
        find.descendant(of: dialog, matching: find.byType(TextFormField)),
        findsOneWidget,
      );

      await tester.enterText(
        find.descendant(of: dialog, matching: find.byType(TextFormField)),
        'Sci-fi',
      );
      await _tap(tester, find.text('Update'));
      expect(harness.tags.updated, ['t3: Sci-fi < t2']);
    });
  });

  // The shelves tab is one tree: every level at once, folded by a chevron,
  // rearranged by dragging a shelf onto another or onto the first level.
  group('the shelf tree on the real route', () {
    final tree = _Probe(
      'shelf tree',
      '/shelves-management',
      size: _tallPhone,
      tags: _treeTags,
    );

    testWidgets('lists every level at once', (tester) async {
      await _render(tester, tree);

      expect(find.byType(GridView), findsNothing);
      for (final tag in _treeTags) {
        expect(_treeRow(tag.name), findsOneWidget, reason: tag.name);
      }
      // Parents before their children, each level in alphabetical order.
      final top = [
        for (final name in ['Living room', 'Novels', 'Crime', 'Study'])
          tester.getTopLeft(_treeRow(name)).dy,
      ];
      expect(top, orderedEquals([...top]..sort()));
    });

    testWidgets('a tap on a row opens the books of its shelf', (
      tester,
    ) async {
      await _render(tester, const _Probe('shelves', '/shelves-management'));

      await _tap(
        tester,
        find.descendant(of: _treeRow('Genre'), matching: find.text('Genre')),
      );

      expect(
        tester.widget<Text>(find.byKey(const Key('shelfHeaderTitle'))).data,
        'Genre',
      );
      // Its sub-shelf is a card there, with the books of that one behind it.
      expect(
        find.byKey(const ValueKey('subShelfCard:Science fiction')),
        findsOneWidget,
      );
    });

    testWidgets('a row says how many books and sub-shelves it holds', (
      tester,
    ) async {
      await _render(tester, tree);

      expect(
        find.descendant(
          of: _treeRow('Living room'),
          matching: find.text('10 books'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byTooltip('Collapse Living room'),
          matching: find.text('1 sub-shelf'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: _treeRow('Study'), matching: find.text('5 books')),
        findsOneWidget,
      );
    });

    testWidgets('every row, at every level, wears a thumbnail that adds no '
        'semantics node', (tester) async {
      final handle = tester.ensureSemantics();
      await _render(tester, tree);

      for (final tag in _treeTags) {
        final thumbnail = find.descendant(
          of: _treeRow(tag.name),
          matching: find.byType(ShelfThumbnail),
        );
        expect(thumbnail, findsOneWidget, reason: tag.name);
        // The nearest node is the row's own, and nothing merges into it:
        // the row reads its name alone, as before.
        final rowNode = tester.getSemantics(_treeRow(tag.name));
        expect(
          tester.getSemantics(thumbnail).id,
          rowNode.id,
          reason: tag.name,
        );
        expect(rowNode.label, tag.name, reason: tag.name);
      }
      handle.dispose();
    });

    testWidgets('a shelf piles up its covers; a shelf with books and none, '
        'and an empty one, say which they are', (tester) async {
      await _render(
        tester,
        _Probe(
          'shelf tree, covers',
          '/shelves-management',
          size: _tallPhone,
          tags: [
            // No book of its own: its books sit on a sub-shelf.
            Tag(
              id: 's1',
              name: 'Living room',
              count: 0,
              coverPaths: const [
                'https://c/a.jpg',
                'https://c/b.jpg',
                'https://c/c.jpg',
              ],
            ),
            Tag(id: 's2', name: 'Novels', parentId: 's1', count: 2),
            Tag(id: 's3', name: 'Kitchen', count: 0),
            Tag(id: 's5', name: 'Study', count: 5),
          ],
        ),
      );
      ShelfThumbnail thumbnailOf(String name) => tester.widget(
        find.descendant(
          of: _treeRow(name),
          matching: find.byType(ShelfThumbnail),
        ),
      );

      expect(
        find.descendant(
          of: _treeRow('Living room'),
          matching: find.byType(CachedBookCover),
        ),
        findsNWidgets(3),
      );
      expect(thumbnailOf('Study').hasBooks, isTrue);
      expect(thumbnailOf('Study').coverPaths, isEmpty);
      expect(thumbnailOf('Kitchen').hasBooks, isFalse);
      // A parent counts the books of its sub-shelves.
      expect(thumbnailOf('Living room').hasBooks, isTrue);
    });

    testWidgets('"Move to…" shows the same thumbnail on its rows', (
      tester,
    ) async {
      await _render(tester, tree);
      await _openMoveFromRow(tester, 'Study');

      expect(
        find.descendant(
          of: _moveRow('Living room'),
          matching: find.byType(ShelfThumbnail),
        ),
        findsOneWidget,
      );
    });

    testWidgets('from the fourth level a row stops moving right and names '
        'its parent', (tester) async {
      await _render(tester, tree);
      double left(String name) => tester
          .getTopLeft(
            find.descendant(of: _treeRow(name), matching: find.text(name)),
          )
          .dx;

      // The indentation alone tells the levels apart.
      expect(left('Novels') - left('Living room'), shelfTreeIndent);
      expect(left('Crime') - left('Novels'), shelfTreeIndent);
      expect(left('Nordic crime'), left('Crime'));
      expect(
        find.descendant(
          of: _treeRow('Nordic crime'),
          matching: find.textContaining('in Living room › Novels › Crime'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _treeRow('Crime'),
          matching: find.textContaining('in '),
        ),
        findsNothing,
      );
    });

    testWidgets('a long press on the fold button picks the shelf up', (
      tester,
    ) async {
      await _render(tester, tree);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byTooltip('Collapse Living room')),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
      await gesture.moveBy(const Offset(0, 24));
      await tester.pump();
      await tester.pump();

      expect(_firstLevelZone, findsOneWidget);
      await gesture.up();
      await _settle(tester);
    });

    testWidgets('the row keeps its height under a dragged shelf', (
      tester,
    ) async {
      await _render(tester, tree);
      final before = tester.getSize(_treeRow('Living room')).height;

      final gesture = await _startShelfDrag(tester, 'Study');
      await _revealFirstRow(tester, gesture);
      await gesture.moveTo(tester.getCenter(_treeRow('Living room')));
      await tester.pump();
      await tester.pump();

      // The drag is really over that row.
      expect(
        tester.widget<ShelfTreeRow>(_treeRow('Living room')).subtitleNotice,
        isNotNull,
      );
      expect(tester.getSize(_treeRow('Living room')).height, before);
      await gesture.up();
      await _settle(tester);
    });

    testWidgets('a tap on the thumbnail, or anywhere on a row with nothing '
        'to fold, opens the shelf', (tester) async {
      await _render(tester, tree);
      String title() =>
          tester.widget<Text>(find.byKey(const Key('shelfHeaderTitle'))).data!;

      await _tap(
        tester,
        find.descendant(
          of: _treeRow('Living room'),
          matching: find.byType(ShelfThumbnail),
        ),
      );
      expect(title(), 'Living room');
    });

    testWidgets('"2 sub-shelves" folds the branch and leaves the shelf closed', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _render(tester, tree);
      final fold = find.byTooltip('Collapse Living room');

      // A 44 pt target around 16 pt of text, with a 16 pt arrow that turns.
      final size = tester.getSize(fold);
      expect(size.height, greaterThanOrEqualTo(44));
      expect(size.width, greaterThanOrEqualTo(44));
      final arrow = find.descendant(
        of: fold,
        matching: find.byIcon(Icons.chevron_right),
      );
      expect(tester.widget<Icon>(arrow).size, 16);
      AnimatedRotation turn() => tester.widget(
        find.descendant(
          of: find.ancestor(of: arrow, matching: find.byType(Tooltip)),
          matching: find.byType(AnimatedRotation),
        ),
      );
      expect(turn().turns, 0.25);
      // Announced as its action, and the row still reads the whole count.
      expect(
        tester.getSemantics(fold),
        containsSemantics(
          label: 'Collapse Living room',
          isButton: true,
          hasExpandedState: true,
          isExpanded: true,
          isFocusable: true,
          hasFocusAction: true,
        ),
      );
      final rowNode = tester.getSemantics(_treeRow('Living room'));
      expect(rowNode.value, contains('sub-shelf'));

      await _tap(tester, fold);
      expect(_treeRow('Novels'), findsNothing);
      final expand = find.byTooltip('Expand Living room');
      expect(
        tester.getSemantics(expand),
        containsSemantics(
          label: 'Expand Living room',
          isButton: true,
          hasExpandedState: true,
          isExpanded: false,
        ),
      );
      expect(
        tester
            .widget<AnimatedRotation>(
              find.descendant(
                of: expand,
                matching: find.byType(AnimatedRotation),
              ),
            )
            .turns,
        0,
      );
      expect(
        GoRouterState.of(tester.element(_treeRow('Living room'))).uri.path,
        '/shelves-management',
      );
      handle.dispose();
    });

    testWidgets('a folded shelf stays folded after leaving the tab', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _render(tester, tree);
      final collapse = find.byTooltip('Collapse Living room');
      expect(
        tester.getSemantics(collapse),
        containsSemantics(
          isButton: true,
          hasExpandedState: true,
          isExpanded: true,
        ),
      );
      // A shelf with no sub-shelf has nothing to fold.
      expect(find.byTooltip('Collapse Study'), findsNothing);
      expect(find.byTooltip('Expand Study'), findsNothing);

      await _tap(tester, collapse);
      expect(_treeRow('Novels'), findsNothing);
      expect(_treeRow('Crime'), findsNothing);
      final expand = find.byTooltip('Expand Living room');
      expect(
        tester.getSemantics(expand),
        containsSemantics(
          isButton: true,
          hasExpandedState: true,
          isExpanded: false,
        ),
      );

      // The tab rebuilt from scratch, as when the reader comes back to it.
      await _render(tester, tree);
      expect(_treeRow('Living room'), findsOneWidget);
      expect(_treeRow('Novels'), findsNothing);

      await _tap(tester, find.byTooltip('Expand Living room'));
      expect(_treeRow('Novels'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('the handle is a "Move <name>" button that opens the move '
        'tree', (tester) async {
      final handle = tester.ensureSemantics();
      final harness = await _render(tester, tree);
      expect(
        tester.getSemantics(_treeHandle('Crime')),
        containsSemantics(isButton: true, tooltip: 'Move Crime'),
      );

      await _tap(tester, _treeHandle('Crime'));
      expect(
        find.descendant(
          of: _moveSheet,
          matching: find.text('Move “Crime” to…'),
        ),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(_moveRow('Nordic crime')),
        containsSemantics(isButton: true, hasEnabledState: true,
            isEnabled: false),
      );
      await _tap(tester, _moveRow('Study'));
      expect(harness.tags.updated, ['s3: Crime < s5']);
      handle.dispose();
    });

    testWidgets('a drop on the shelf itself or one of its sub-shelves is '
        'refused and writes nothing', (tester) async {
      final handle = tester.ensureSemantics();
      final harness = await _render(tester, tree);

      final gesture = await _startShelfDrag(tester, 'Novels');
      // The branch in hand reads as disabled, the rest stays a target.
      for (final name in ['Novels', 'Crime', 'Nordic crime']) {
        expect(
          tester.getSemantics(_treeRow(name)),
          containsSemantics(hasEnabledState: true, isEnabled: false),
          reason: name,
        );
      }
      expect(
        tester.getSemantics(_treeRow('Study')),
        containsSemantics(hasEnabledState: true, isEnabled: true),
      );
      await gesture.moveTo(tester.getCenter(_treeRow('Crime')));
      await tester.pump();
      await gesture.up();
      await _settle(tester);

      await _dragShelf(tester, 'Living room', _treeRow('Nordic crime'));
      await _dragShelf(tester, 'Study', _treeRow('Study'));

      expect(harness.tags.updated, isEmpty);
      expect(harness.tags.created, isEmpty);
      expect(find.textContaining('moved'), findsNothing);
      _expectDragOver(tester, ['Novels', 'Crime', 'Nordic crime']);
      handle.dispose();
    });

    testWidgets('a drag ends even when its row has scrolled out of the lazy '
        'list', (tester) async {
      final handle = tester.ensureSemantics();
      final many = [
        for (var i = 1; i <= 60; i++)
          Tag(id: 'm$i', name: 'Shelf ${'$i'.padLeft(2, '0')}', count: 1),
      ];
      await _render(tester, tree, tags: many);

      final gesture = await _startShelfDrag(tester, 'Shelf 01');
      // Held at the bottom edge: the list scrolls the picked row out of
      // its cache, which unmounts it.
      final mounted = find.byKey(
        const ValueKey('shelfTreeHandle:Shelf 01'),
        skipOffstage: false,
      );
      final list = tester.getRect(find.byKey(const Key('shelfTreeList')));
      await gesture.moveTo(list.center);
      await tester.pump();
      await gesture.moveTo(Offset(list.center.dx, list.bottom - 8));
      for (var i = 0; i < 60 && mounted.evaluate().isNotEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(mounted, findsNothing);
      await gesture.moveTo(_offTheTree(tester));
      await tester.pump();
      await gesture.up();
      await _settle(tester);

      expect(_firstLevelZone, findsNothing);
      await tester.scrollUntilVisible(
        _treeRow('Shelf 01'),
        -400,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('shelfTreeList')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      _expectDragOver(tester, ['Shelf 01']);
      handle.dispose();
    });

    testWidgets('a drag ends even when the tree reloads under it', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final harness = await _render(tester, tree);

      final gesture = await _startShelfDrag(tester, 'Novels');
      // A sync brings a shelf above the one in hand, then renames it.
      harness.tags.mockTags = [
        Tag(id: 's0', name: 'Attic', count: 0),
        for (final t in _treeTags)
          t.id == 's2'
              ? Tag(id: 's2', name: 'Novels 2', parentId: 's1', count: 3)
              : t,
      ];
      harness.refresh.refresh();
      await _settle(tester);
      await gesture.moveTo(_offTheTree(tester));
      await tester.pump();
      await gesture.up();
      await _settle(tester);

      expect(harness.tags.updated, isEmpty);
      _expectDragOver(tester, ['Novels 2', 'Crime', 'Nordic crime']);
      handle.dispose();
    });

    testWidgets('a target that became a sub-shelf of the one in hand while '
        'hovered refuses the drop', (tester) async {
      final harness = await _render(tester, tree);

      final gesture = await _startShelfDrag(tester, 'Study');
      await gesture.moveTo(tester.getCenter(_treeRow('Living room')));
      await tester.pump();
      // A sync files Living room under Study meanwhile.
      harness.tags.mockTags = [
        for (final t in _treeTags)
          t.id == 's1'
              ? Tag(id: 's1', name: 'Living room', parentId: 's5', count: 2)
              : t,
      ];
      harness.refresh.refresh();
      await _settle(tester);
      await gesture.up();
      await _settle(tester);

      expect(harness.tags.updated, isEmpty);
      expect(harness.tags.created, isEmpty);
    });

    testWidgets('a shelf renamed by a sync while in hand moves under its '
        'new name', (tester) async {
      final harness = await _render(tester, tree);

      final gesture = await _startShelfDrag(tester, 'Novels');
      harness.tags.mockTags = [
        for (final t in _treeTags)
          t.id == 's2'
              ? Tag(id: 's2', name: 'Fiction', parentId: 's1', count: 3)
              : t,
      ];
      harness.refresh.refresh();
      await _settle(tester);
      await gesture.moveTo(tester.getCenter(_treeRow('Study')));
      await tester.pump();
      await gesture.up();
      await _settle(tester);

      // The rename made on the other device stays.
      expect(harness.tags.updated, ['s2: Fiction < s5']);
    });

    testWidgets('a second finger lifting leaves the drag in progress alone', (
      tester,
    ) async {
      final harness = await _render(tester, tree);

      final gesture = await _startShelfDrag(tester, 'Crime');
      final other = await tester.startGesture(
        tester.getCenter(_firstLevelZone),
      );
      await tester.pump();
      await other.up();
      await _settle(tester);
      expect(_firstLevelZone, findsOneWidget);

      await gesture.moveTo(tester.getCenter(_firstLevelZone));
      await tester.pump();
      await gesture.up();
      await _settle(tester);
      expect(harness.tags.updated, ['s3: Crime']);
    });

    testWidgets('picking up a row inside the top scroll band moves nothing '
        'until the pointer comes back to it', (tester) async {
      final harness = await _render(tester, tree);
      harness.tags.mockUnshelvedCount = 0;
      harness.refresh.refresh();
      await _settle(tester);
      await tester.ensureVisible(_treeHandle('Living room'));
      await _settle(tester);
      final before = tester.getRect(_treeRow('Living room'));

      final gesture = await _startShelfDrag(tester, 'Living room');
      final zone = tester.getRect(_firstLevelZone);
      final pointer = tester.getCenter(_treeHandle('Living room')).dy + 24;
      // The pick itself lands in the band under the zone.
      expect(pointer, inInclusiveRange(zone.bottom, zone.bottom + 56));
      // A finger never holds perfectly still.
      await gesture.moveBy(const Offset(0, 2));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.getRect(_treeRow('Living room')).top, before.top);
      await gesture.up();
      await _settle(tester);
    });

    testWidgets('a reload that adds a shelf above keeps the drag of the row '
        'in hand alive', (tester) async {
      final harness = await _render(tester, tree);
      State<StatefulWidget> held() => tester.state(
        find.ancestor(
          of: _treeHandle('Study'),
          matching: find.byType(Draggable<Tag>),
        ),
      );

      final gesture = await _startShelfDrag(tester, 'Study');
      final before = held();
      harness.tags.mockTags = [
        Tag(id: 's0', name: 'Attic', count: 0),
        ..._treeTags,
      ];
      harness.refresh.refresh();
      await _settle(tester);

      // The same Draggable: one rebuilt from scratch stops reporting the
      // drag, and the edge scroll with it.
      expect(identical(held(), before), isTrue);
      await gesture.up();
      await _settle(tester);
    });

    testWidgets('a drop on a folded shelf unfolds it and shows the shelf at '
        'its new place', (tester) async {
      final harness = await _render(tester, tree);
      await _tap(tester, find.byTooltip('Collapse Living room'));

      final gesture = await _startShelfDrag(tester, 'Study');
      await _revealFirstRow(tester, gesture);
      await gesture.moveTo(tester.getCenter(_treeRow('Living room')));
      await tester.pump();
      // What the reload after the write returns: Study inside Living room.
      harness.tags.mockTags = [
        for (final t in _treeTags)
          t.id == 's5'
              ? Tag(id: 's5', name: 'Study', parentId: 's1', count: 5)
              : t,
      ];
      await gesture.up();
      await _settle(tester);

      expect(harness.tags.updated, ['s5: Study < s1']);
      expect(find.byTooltip('Collapse Living room'), findsOneWidget);
      // Unfolded for good, not only on screen.
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getStringList('shelf_tree_collapsed'),
        isNot(contains('s1')),
      );
      expect(_treeRow('Novels'), findsOneWidget);
      expect(_treeRow('Study'), findsOneWidget);
      expect(
        tester.getTopLeft(_treeRow('Study')).dy,
        greaterThan(tester.getTopLeft(_treeRow('Living room')).dy),
      );
    });

    testWidgets('the first row stays a target with the list at its top', (
      tester,
    ) async {
      final harness = await _render(tester, tree);
      // No "to shelve" card: the first shelf heads the list, where the
      // zone shows.
      harness.tags.mockUnshelvedCount = 0;
      harness.refresh.refresh();
      await _settle(tester);
      expect(find.byKey(const Key('toShelveCard')), findsNothing);

      final gesture = await _startShelfDrag(tester, 'Study');
      final zone = tester.getRect(_firstLevelZone);
      // Held just under the zone: the list makes room above its first row.
      await gesture.moveTo(Offset(zone.center.dx, zone.bottom + 8));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final row = tester.getRect(_treeRow('Living room'));
      expect(row.top, greaterThanOrEqualTo(zone.bottom));
      await gesture.moveTo(row.center);
      await tester.pump();
      await gesture.up();
      await _settle(tester);

      expect(harness.tags.updated, ['s5: Study < s1']);
    });

    testWidgets('a folded shelf that loses its sub-shelves and gets new ones '
        'shows them', (tester) async {
      final harness = await _render(tester, tree);
      await _tap(tester, find.byTooltip('Collapse Living room'));
      Future<void> reload(List<Tag> tags) async {
        harness.tags.mockTags = tags;
        harness.refresh.refresh();
        await _settle(tester);
      }

      // Novels moved away from another device: Living room has no child.
      await reload([
        for (final t in _treeTags)
          t.id == 's2' ? Tag(id: 's2', name: 'Novels', count: 3) : t,
      ]);
      // Then a new sub-shelf is filed under it.
      await reload([
        ...harness.tags.mockTags,
        Tag(id: 's6', name: 'Poetry', parentId: 's1', count: 0),
      ]);

      expect(_treeRow('Poetry'), findsOneWidget);
    });

    testWidgets('a drop on the first-level zone moves with no parent', (
      tester,
    ) async {
      final harness = await _render(tester, tree);
      expect(_firstLevelZone, findsNothing);

      await _dragShelf(tester, 'Crime', _firstLevelZone);

      expect(harness.tags.updated, ['s3: Crime']);
      expect(find.text('Crime moved to the first level'), findsOneWidget);
      expect(_firstLevelZone, findsNothing);
    });

    testWidgets('picking a shelf up moves no row under the finger, and the '
        'zone shows in sight, one node', (tester) async {
      final handle = tester.ensureSemantics();
      await _render(tester, tree);
      // Scrolled first, as a reader does: the library header has gone and
      // its pinned tabs cover the top of the tab.
      await tester.ensureVisible(_treeHandle('Study'));
      await _settle(tester);
      final before = tester.getRect(_treeRow('Study'));

      final gesture = await _startShelfDrag(tester, 'Study', longPress: true);

      expect(tester.getRect(_treeRow('Study')), before);
      final zone = tester.getRect(_firstLevelZone);
      final hit = HitTestResult();
      tester.binding.hitTestInView(hit, zone.center, tester.view.viewId);
      expect(
        hit.path.map((e) => e.target),
        contains(tester.renderObject(_firstLevelZone)),
        reason: 'the zone is under something else',
      );
      expect(
        tester.getSemantics(_firstLevelZone),
        containsSemantics(label: 'First level'),
      );
      await gesture.up();
      await _settle(tester);
      handle.dispose();
    });

    testWidgets('a drop on a row files the shelf inside it', (tester) async {
      final harness = await _render(tester, tree);

      await _dragShelf(tester, 'Crime', _treeRow('Study'));

      expect(harness.tags.updated, ['s3: Crime < s5']);
      expect(find.text('Crime moved under Study'), findsOneWidget);
    });

    testWidgets('a long press on a row picks the shelf up', (tester) async {
      final harness = await _render(tester, tree);

      await _dragShelf(tester, 'Study', _treeRow('Novels'), longPress: true);

      expect(harness.tags.updated, ['s5: Study < s2']);
    });

    // A mouse drags by the handle. The macOS mouse tracker crash on a quick
    // drop does not reproduce under test: the deferred state change that
    // avoids it is checked by hand on a Mac.
    testWidgets('a quick mouse drop on the desktop layout moves the shelf', (
      tester,
    ) async {
      final harness = await _render(
        tester,
        _Probe('desktop tree', '/shelves-management', size: _desktop, tags: _treeTags),
      );

      await _dragShelf(
        tester,
        'Crime',
        _treeRow('Study'),
        fast: true,
        kind: PointerDeviceKind.mouse,
      );

      expect(tester.takeException(), isNull);
      expect(harness.tags.updated, ['s3: Crime < s5']);
    });

    testWidgets('a shelf known only from the books gets its row before it '
        'takes a sub-shelf', (tester) async {
      final harness = await _render(
        tester,
        tree,
        tags: [
          ..._treeTags,
          Tag(id: '${Tag.syntheticIdPrefix}-1', name: 'Loose', count: 1),
        ],
      );

      await _dragShelf(tester, 'Study', _treeRow('Loose'));

      // The mock gives every created row the id '1'.
      expect(harness.tags.created, ['Loose']);
      expect(harness.tags.updated, ['s5: Study < 1']);
    });

    testWidgets('a search field shows past fifteen shelves and keeps the '
        'parents of what it finds', (tester) async {
      final filler = [
        for (var i = 1; i <= 11; i++)
          Tag(id: 'f$i', name: 'Shelf $i', count: 0),
      ];
      await _render(tester, tree, tags: [..._treeTags, ...filler.take(10)]);
      expect(_treeSearch, findsNothing);

      await _render(tester, tree, tags: [..._treeTags, ...filler]);
      expect(_treeSearch, findsOneWidget);
      await tester.enterText(_treeSearch, 'nordic');
      await _settle(tester);

      for (final name in ['Living room', 'Novels', 'Crime', 'Nordic crime']) {
        expect(_treeRow(name), findsOneWidget, reason: name);
      }
      expect(_treeRow('Study'), findsNothing);
      expect(_treeRow('Shelf 1'), findsNothing);
    });

    testWidgets('two hundred shelves build lazily, the last one in reach', (
      tester,
    ) async {
      final many = [
        for (var i = 0; i < 200; i++)
          Tag(
            id: 'p$i',
            name: 'Shelf $i',
            parentId: i % 4 == 0 ? null : 'p${i - i % 4}',
            count: 1,
          ),
      ];
      await _render(tester, tree, tags: many);

      // Built rows, the off-screen cache included: a list built in one go
      // would hold all two hundred.
      expect(
        find.byType(ShelfTreeRow, skipOffstage: false).evaluate().length,
        lessThan(40),
      );
      await tester.scrollUntilVisible(
        _treeRow('Shelf 199'),
        400,
        scrollable: find
            .descendant(
              of: find.byKey(const Key('shelfTreeList')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(_treeRow('Shelf 199'), findsOneWidget);
    });

    testWidgets('the + creates at the first level, a row\'s menu inside it', (
      tester,
    ) async {
      final harness = await _render(tester, tree);
      Future<void> create(String name) async {
        await tester.enterText(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(TextFormField),
          ),
          name,
        );
        await _tap(tester, find.text('Create'));
      }

      await _tap(
        tester,
        find.descendant(
          of: find.byType(OrganizeShelvesScreen),
          matching: find.byType(FloatingActionButton),
        ),
      );
      await create('Poetry');
      await _openShelfRowMenu(tester, 'Study');
      await _tap(tester, find.text('Add Sub-Shelf'));
      await create('Essays');

      expect(harness.tags.created, ['Poetry', 'Essays < s5']);
    });
  });

  // A shelf is a place: its page on the real route, with the sub-shelves
  // before the books and only the books filed directly there in the grid.
  group('the page of a shelf on the real route', () {
    Book filed(String id, String title, String shelf, {DateTime? added}) =>
        Book(
          id: id,
          title: title,
          author: 'Ann Able',
          subjects: [shelf],
          addedAt: added,
        );
    final tags = [
      ..._treeTags,
      Tag(id: 's6', name: 'Kitchen', count: 0),
    ];
    final books = [
      filed('p1', 'Old lamp', 'Living room', added: DateTime(2026, 1, 1)),
      filed('p2', 'New lamp', 'Living room', added: DateTime(2026, 3, 1)),
      filed('p3', 'Sofa novel', 'Novels', added: DateTime(2026, 6, 1)),
      filed('p4', 'Thin crime', 'Crime'),
      filed('p5', 'Fjord', 'Nordic crime', added: DateTime(2026, 7, 1)),
    ];
    _Probe page(String shelf, {Size size = _tallPhone}) => _Probe(
      'place',
      '/shelves?tag=${Uri.encodeQueryComponent(shelf)}',
      size: size,
      tags: tags,
    );
    final name = find.byKey(const Key('shelfHeaderTitle'));
    final back = find.byKey(const Key('shelfBackButton'));
    final chip = find.byKey(const Key('shelfPlaceChip'));
    final heading = find.byKey(const Key('shelvedHereHeading'));
    final lastAdded = find.byKey(const Key('shelfPlaceLastAdded'));
    final menu = find.byKey(const Key('shelfPlaceMenu'));
    final bigEmpty = find.byKey(const Key('shelfPlaceEmpty'));
    Finder subCard(String shelf) => find.byKey(ValueKey('subShelfCard:$shelf'));
    Finder card(String shelf) => find.byKey(ValueKey('shelfCard:$shelf'));
    String location(WidgetTester tester) =>
        GoRouterState.of(tester.element(find.byType(LibraryScreen))).uri
            .toString();
    Future<void> pick(WidgetTester tester, String item) async {
      await _tap(tester, menu);
      await _tap(tester, find.text(item).last);
    }

    testWidgets('a first-level shelf: its name and counts, back to the shelves, '
        'no path', (tester) async {
      await _render(tester, page('Living room'), books: books);

      expect(tester.widget<Text>(name).data, 'Living room');
      expect(find.text('10 books · 1 sub-shelf'), findsOneWidget);
      expect(
        find.descendant(of: back, matching: find.text('Shelves')),
        findsOneWidget,
      );
      expect(chip, findsNothing);
    });

    testWidgets('one level down the path names the parent, and back too', (
      tester,
    ) async {
      await _render(tester, page('Novels'), books: books);

      expect(
        find.descendant(of: chip, matching: find.text('in Living room')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: back, matching: find.text('Living room')),
        findsOneWidget,
      );
    });

    testWidgets('two levels down the path names both', (tester) async {
      await _render(tester, page('Crime'), books: books);

      expect(
        find.descendant(
          of: chip,
          matching: find.text('in Living room › Novels'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: back, matching: find.text('Novels')),
        findsOneWidget,
      );
    });

    testWidgets('three levels down the path cuts the top short', (
      tester,
    ) async {
      await _render(tester, page('Nordic crime'), books: books);

      expect(
        find.descendant(of: chip, matching: find.text('… › Novels › Crime')),
        findsOneWidget,
      );
    });

    testWidgets('the path leads up to the parent', (tester) async {
      await _render(tester, page('Crime'), books: books);

      await _tap(tester, chip);

      expect(location(tester), '/shelves?tag=Novels');
    });

    testWidgets('back leads to the parent, then to the shelves', (
      tester,
    ) async {
      await _render(tester, page('Novels'), books: books);

      await _tap(tester, back);
      expect(location(tester), '/shelves?tag=Living+room');

      await _tap(tester, back);
      expect(location(tester), '/shelves');
    });

    testWidgets('the Shelves tab leads back to the grid of first-level shelves', (
      tester,
    ) async {
      await _render(tester, page('Crime'), books: books);

      await _tap(tester, find.widgetWithText(Tab, 'Shelves'));

      expect(location(tester), '/shelves');
      expect(card('Living room'), findsOneWidget);
      expect(name, findsNothing);
    });

    testWidgets('the sub-shelves come before the books, as cards that open', (
      tester,
    ) async {
      await _render(tester, page('Living room'), books: books);

      expect(
        tester.getTopLeft(subCard('Novels')).dy,
        lessThan(tester.getTopLeft(heading).dy),
      );
      expect(
        tester.getSize(
          find.descendant(
            of: subCard('Novels'),
            matching: find.byType(ShelfThumbnail),
          ),
        ),
        const Size(48, 34),
      );

      await _tap(tester, subCard('Novels'));
      expect(location(tester), '/shelves?tag=Novels');
    });

    testWidgets('the head wears the extra large fan, the path the smallest', (
      tester,
    ) async {
      await _render(tester, page('Novels'), books: books);

      expect(
        tester.getSize(find.byKey(const Key('shelfPlaceFan'))),
        const Size(112, 80),
      );
      expect(
        tester.getSize(
          find.descendant(of: chip, matching: find.byType(ShelfThumbnail)),
        ),
        const Size(34, 24),
      );
    });

    testWidgets('the grid shows only the books filed directly here', (
      tester,
    ) async {
      await _render(tester, page('Living room'), books: books);

      expect(
        find.descendant(of: heading, matching: find.textContaining('2 books')),
        findsOneWidget,
      );
      expect(find.text('New lamp'), findsWidgets);
      expect(find.text('Sofa novel'), findsNothing);
      expect(find.text('Fjord'), findsNothing);
    });

    testWidgets('the Books tab filter still takes the whole subtree', (
      tester,
    ) async {
      await _render(
        tester,
        _Probe('books filter', '/books?tag=Living+room', tags: tags),
        books: books,
      );

      expect(find.text('Sofa novel'), findsWidgets);
      expect(heading, findsNothing);
    });

    testWidgets('the last arrived is the newest added among the books here, '
        'not those of its sub-shelves', (tester) async {
      await _render(tester, page('Living room'), books: books);

      expect(
        tester.widget<Text>(lastAdded).textSpan!.toPlainText(),
        contains('New lamp'),
      );
    });

    testWidgets('no book here, or no date: no last arrived', (tester) async {
      await _render(tester, page('Crime'), books: books);
      expect(lastAdded, findsNothing);

      await _render(tester, page('Kitchen'), books: books);
      expect(lastAdded, findsNothing);
    });

    testWidgets('a parent with no book of its own shows its sub-shelves and a '
        'quiet section, not the big empty state', (tester) async {
      await _render(
        tester,
        page('Living room'),
        books: [filed('p3', 'Sofa novel', 'Novels')],
      );

      expect(subCard('Novels'), findsOneWidget);
      expect(bigEmpty, findsNothing);
      expect(find.text('No books found'), findsNothing);
      expect(
        find.descendant(of: heading, matching: find.textContaining('0 books')),
        findsOneWidget,
      );
    });

    testWidgets('neither sub-shelf nor book: the ghost, the sentence and its '
        'two buttons', (tester) async {
      await _render(tester, page('Kitchen'), books: books);

      expect(bigEmpty, findsOneWidget);
      expect(
        find.descendant(of: bigEmpty, matching: find.byKey(const Key('shelfThumbnailGhost'))),
        findsOneWidget,
      );
      expect(find.byKey(const Key('shelfEmptyAddBook')), findsOneWidget);
      expect(find.byKey(const Key('shelfEmptyAddSubShelf')), findsOneWidget);
    });

    testWidgets('its two buttons have the corners of the app buttons', (
      tester,
    ) async {
      await _render(tester, page('Kitchen'), books: books);

      for (final key in const ['shelfEmptyAddBook', 'shelfEmptyAddSubShelf']) {
        final style = tester
            .widget<ButtonStyleButton>(find.byKey(Key(key)))
            .style;
        expect(
          style?.shape?.resolve(const {}),
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          reason: key,
        );
        expect(
          style?.textStyle?.resolve(const {})?.fontWeight,
          FontWeight.w600,
          reason: key,
        );
      }
    });

    testWidgets('the empty page creates a sub-shelf inside the shelf, and its '
        'card shows without leaving', (tester) async {
      final harness = await _render(tester, page('Kitchen'), books: books);

      await _tap(tester, find.byKey(const Key('shelfEmptyAddSubShelf')));
      await tester.enterText(find.byType(TextFormField).first, 'Cookbooks');
      harness.tags.mockTags = [
        ...tags,
        Tag(id: 's7', name: 'Cookbooks', parentId: 's6', count: 0),
      ];
      await _tap(tester, find.text('Create'));

      expect(harness.tags.created, ['Cookbooks < s6']);
      expect(subCard('Cookbooks'), findsOneWidget);
    });

    testWidgets('sorting and reordering are still there, on this shelf', (
      tester,
    ) async {
      await _render(tester, page('Living room'), books: books);

      expect(find.byTooltip('Reorder shelf'), findsOneWidget);
      expect(find.text('Author'), findsOneWidget);
    });

    testWidgets('"+" adds a book with this shelf filled in, by its name', (
      tester,
    ) async {
      await _render(tester, page('Crime'), books: books);

      await _tap(tester, find.byKey(const Key('addBookButton')));

      final extra =
          GoRouterState.of(tester.element(find.byType(AddBookScreen))).extra
              as Map<String, dynamic>;
      expect(extra['shelfId'], 'Crime');
      expect(extra['shelfName'], 'Crime');
    });

    testWidgets('the name and the two sections are titles', (tester) async {
      final handle = tester.ensureSemantics();
      await _render(tester, page('Living room'), books: books);

      expect(
        tester.getSemantics(name),
        containsSemantics(label: 'Living room', isHeader: true),
      );
      expect(
        tester.getSemantics(heading),
        containsSemantics(isHeader: true),
      );
      expect(
        find.bySemanticsLabel('Sub-shelves'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('a sub-shelf card is one button with its counts', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _render(tester, page('Living room'), books: books);

      expect(
        tester.getSemantics(subCard('Novels')),
        containsSemantics(
          label: 'Novels, 8 books, 1 sub-shelf',
          isButton: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });

    group('when its shelf changes under it', () {
      final done = find.widgetWithText(TextButton, 'Done');
      Future<void> toOrganize(WidgetTester tester) async {
        await pick(tester, 'Organize shelves');
        expect(_treeRow('Crime'), findsOneWidget);
      }

      testWidgets('renamed from Organize: the page follows the new name', (
        tester,
      ) async {
        final harness = await _render(tester, page('Crime'), books: books);
        await toOrganize(tester);

        await _renameFromRow(tester, 'Crime', 'Thrillers');
        harness.tags.mockTags = [
          for (final t in tags)
            t.id == 's3'
                ? Tag(id: 's3', name: 'Thrillers', parentId: 's2', count: 4)
                : t,
        ];
        await _tap(tester, done);
        await _settle(tester);

        expect(location(tester), '/shelves?tag=Thrillers');
        expect(tester.widget<Text>(name).data, 'Thrillers');
      });

      testWidgets('deleted from Organize: back up to its parent', (
        tester,
      ) async {
        final harness = await _render(tester, page('Crime'), books: books);
        await toOrganize(tester);

        await _deleteFromRow(tester, 'Crime');
        // The core takes the name off the books with the row.
        harness.tags.mockTags = [
          for (final t in tags)
            if (t.id != 's3') t,
        ];
        harness.books.mockBooks = [
          for (final b in books)
            if (!(b.subjects?.contains('Crime') ?? false)) b,
        ];
        await _tap(tester, done);
        await _settle(tester);

        expect(harness.tags.deleted, ['Crime']);
        expect(location(tester), '/shelves?tag=Novels');
        await _letMessagesGo(tester);
      });

      testWidgets('gone with a sync: back to the grid for a first-level shelf', (
        tester,
      ) async {
        final harness = await _render(
          tester,
          page('Kitchen'),
          books: books,
        );

        harness.tags.mockTags = [
          for (final t in tags)
            if (t.id != 's6') t,
        ];
        harness.refresh.refresh();
        await _settle(tester);

        expect(location(tester), '/shelves');
      });

      testWidgets('an empty listing proves nothing: the page stays', (
        tester,
      ) async {
        final harness = await _render(tester, page('Kitchen'), books: books);

        harness.tags.mockTags = const [];
        harness.refresh.refresh();
        await _settle(tester);

        expect(location(tester), '/shelves?tag=Kitchen');
      });

      testWidgets('a sub-shelf changed in Organize shows on coming back by a '
          'tap on this shelf', (tester) async {
        final harness = await _render(tester, page('Crime'), books: books);
        await toOrganize(tester);
        await _renameFromRow(tester, 'Nordic crime', 'Fjords');
        harness.tags.mockTags = [
          for (final t in tags)
            t.id == 's4'
                ? Tag(id: 's4', name: 'Fjords', parentId: 's3', count: 1)
                : t,
        ];

        await _tap(
          tester,
          find.descendant(of: _treeRow('Crime'), matching: find.text('Crime')),
        );
        await _settle(tester);

        expect(subCard('Fjords'), findsOneWidget);
      });
    });

    group('a shelf known only from its books', () {
      final loose = Tag(id: 'legacy:-1', name: 'Loose', count: 1);
      final fixture = [...tags, loose];
      final filedLoose = [filed('l1', 'Stray', 'Loose')];

      testWidgets('gets its row before a sub-shelf goes inside', (
        tester,
      ) async {
        final harness = await _render(
          tester,
          _Probe('loose', '/shelves?tag=Loose', size: _tallPhone, tags: fixture),
          books: filedLoose,
        );

        await pick(tester, 'Add Sub-Shelf');
        await tester.enterText(find.byType(TextFormField).first, 'Inner');
        await _tap(tester, find.text('Create'));

        expect(harness.tags.created.first, 'Loose');
        expect(harness.tags.created.last, startsWith('Inner < '));
        expect(harness.tags.created.last, isNot(contains('legacy:')));
      });

      testWidgets('gets its row to be renamed', (tester) async {
        final harness = await _render(
          tester,
          _Probe('loose', '/shelves?tag=Loose', size: _tallPhone, tags: fixture),
          books: filedLoose,
        );

        await pick(tester, 'Rename');
        await tester.enterText(find.byType(TextFormField).first, 'Found');
        harness.tags.mockTags = [
          ...tags,
          Tag(id: '1', name: 'Found', count: 1),
        ];
        await _tap(tester, find.text('Update'));

        expect(harness.tags.created, ['Loose']);
        expect(harness.tags.updated.single, isNot(contains('legacy:')));
        expect(location(tester), '/shelves?tag=Found');
      });
    });

    testWidgets('a shelf not on the listing but with books has no menu to act '
        'on it blind', (tester) async {
      await _render(
        tester,
        _Probe('unlisted', '/shelves?tag=Ghost', size: _tallPhone, tags: tags),
        books: [filed('g1', 'Haunted', 'Ghost')],
      );

      expect(name, findsOneWidget);
      expect(menu, findsNothing);
    });

    testWidgets('a subject with stray spaces counts as filed here, as the core '
        'counts it', (tester) async {
      await _render(
        tester,
        page('Kitchen'),
        books: [filed('s1', 'Spaced', ' Kitchen ')],
      );

      expect(bigEmpty, findsNothing);
      expect(find.text('Spaced'), findsWidgets);
    });

    testWidgets('a page opened from far down starts at its own top', (
      tester,
    ) async {
      final crowded = [
        Tag(id: 'p', name: 'Crowded', count: 0),
        for (var i = 0; i < 30; i++)
          Tag(id: 'c$i', name: 'Sub $i', parentId: 'p', count: 0),
      ];
      await _render(
        tester,
        _Probe('crowded', '/shelves?tag=Sub+29', tags: crowded),
        books: const [],
      );
      final top = tester.getTopLeft(name).dy;

      GoRouter.of(
        tester.element(find.byType(LibraryScreen)),
      ).go('/shelves?tag=Crowded');
      await _settle(tester);
      await tester.scrollUntilVisible(
        subCard('Sub 29'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await _settle(tester);
      await tester.tap(subCard('Sub 29'));
      await _settle(tester);

      expect(tester.getTopLeft(name).dy, top);
    });

    group('in one scroll with the books', () {
      final many = [
        for (var i = 0; i < 40; i++)
          filed('m$i', 'Book $i', 'Living room', added: DateTime(2026, 1, i + 1)),
      ];
      /// A drag on the books carries the head away with them, and back.
      Future<void> scrollsAway(WidgetTester tester) async {
        await tester.drag(find.byType(BookListScreen), const Offset(0, 2000));
        await _settle(tester);
        final before = tester.getTopLeft(name).dy;
        await tester.drag(
          find.byType(BookListScreen),
          const Offset(0, -400),
        );
        await _settle(tester);
        if (name.evaluate().isNotEmpty) {
          expect(tester.getTopLeft(name).dy, lessThan(before));
        }
        await tester.drag(find.byType(BookListScreen), const Offset(0, 2000));
        await _settle(tester);
        expect(tester.getTopLeft(name).dy, before);
      }

      Future<void> showAs(WidgetTester tester, String mode) async {
        await _tap(tester, find.byTooltip('Change View'));
        await tester.tap(find.text(mode).last);
        await _settle(tester);
      }

      testWidgets('the head leaves with the books: covers', (tester) async {
        await _render(tester, page('Living room', size: _phone), books: many);
        expect(find.byType(BookCoverGrid), findsOneWidget);

        await scrollsAway(tester);
      });

      testWidgets('the head leaves with the books: list', (tester) async {
        await _render(tester, page('Living room', size: _phone), books: many);
        await showAs(tester, 'List view');
        expect(find.byType(BookCoverGrid), findsNothing);

        await scrollsAway(tester);
      });

      testWidgets('the head leaves with the books: spines', (tester) async {
        await _render(tester, page('Living room', size: _phone), books: many);
        await showAs(tester, 'Shelf view');
        expect(find.byType(BookshelfView), findsOneWidget);

        await scrollsAway(tester);
      });

      testWidgets('the head leaves with the books: by collection', (
        tester,
      ) async {
        await _render(
          tester,
          _Probe(
            'grouped',
            '/shelves?tag=Living+room',
            collections: true,
            tags: tags,
          ),
          books: many,
        );
        expect(find.byType(CollectionGroupGrid), findsOneWidget);

        await scrollsAway(tester);
      });

      testWidgets('a shelf with few books and many sub-shelves: every card is '
          'in reach', (tester) async {
        final crowded = [
          Tag(id: 'p', name: 'Crowded', count: 1),
          for (var i = 0; i < 30; i++)
            Tag(id: 'c$i', name: 'Sub $i', parentId: 'p', count: 0),
        ];
        await _render(
          tester,
          _Probe('crowded', '/shelves?tag=Crowded', tags: crowded),
          books: [filed('o', 'Only one', 'Crowded')],
        );
        expect(subCard('Sub 29'), findsNothing);

        await tester.scrollUntilVisible(
          subCard('Sub 29'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await _settle(tester);

        expect(subCard('Sub 29'), findsOneWidget);
      });

      testWidgets('a parent with no book and many sub-shelves: every card is '
          'in reach too', (tester) async {
        final crowded = [
          Tag(id: 'p', name: 'Crowded', count: 0),
          for (var i = 0; i < 30; i++)
            Tag(id: 'c$i', name: 'Sub $i', parentId: 'p', count: 0),
        ];
        await _render(
          tester,
          _Probe('crowded', '/shelves?tag=Crowded', tags: crowded),
          books: const [],
        );

        await tester.scrollUntilVisible(
          subCard('Sub 29'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await _settle(tester);

        expect(subCard('Sub 29'), findsOneWidget);
      });
    });

    group('its menu', () {
      testWidgets('offers the five actions, in order', (tester) async {
        await _render(tester, page('Novels'), books: books);

        await _tap(tester, menu);

        final tops = [
          for (final label in [
            'Rename',
            'Add Sub-Shelf',
            'Move to…',
            'Delete',
            'Organize shelves',
          ])
            tester.getTopLeft(find.text(label).last).dy,
        ];
        expect(tops, [...tops]..sort());
      });

      testWidgets('renaming reopens the page under the new name', (
        tester,
      ) async {
        final harness = await _render(tester, page('Crime'), books: books);

        await pick(tester, 'Rename');
        await tester.enterText(find.byType(TextFormField).first, 'Thrillers');
        harness.tags.mockTags = [
          for (final t in tags)
            t.id == 's3'
                ? Tag(id: 's3', name: 'Thrillers', parentId: 's2', count: 4)
                : t,
        ];
        await _tap(tester, find.text('Update'));

        expect(harness.tags.updated, ['s3: Thrillers < s2']);
        expect(location(tester), '/shelves?tag=Thrillers');
      });

      testWidgets('Undo of a rename goes back to the old name', (tester) async {
        final harness = await _render(tester, page('Crime'), books: books);

        await pick(tester, 'Rename');
        await tester.enterText(find.byType(TextFormField).first, 'Thrillers');
        harness.tags.mockTags = [
          for (final t in tags)
            t.id == 's3'
                ? Tag(id: 's3', name: 'Thrillers', parentId: 's2', count: 4)
                : t,
        ];
        await _tap(tester, find.text('Update'));
        await _tap(tester, _undo);

        expect(harness.tags.updated.last, 's3: Crime < s2');
        expect(location(tester), '/shelves?tag=Crime');
      });

      testWidgets('moving opens the tree, and the page follows', (
        tester,
      ) async {
        final harness = await _render(tester, page('Crime'), books: books);

        await pick(tester, 'Move to…');
        harness.tags.mockTags = [
          for (final t in tags)
            t.id == 's3'
                ? Tag(id: 's3', name: 'Crime', parentId: 's5', count: 4)
                : t,
        ];
        await _tap(tester, _moveRow('Study'));

        expect(harness.tags.updated, ['s3: Crime < s5']);
        expect(
          find.descendant(of: back, matching: find.text('Study')),
          findsOneWidget,
        );
      });

      testWidgets('"Organize shelves" opens the organizing route', (
        tester,
      ) async {
        await _render(tester, page('Crime'), books: books);

        await pick(tester, 'Organize shelves');

        expect(find.byKey(const ValueKey('shelfTreeRow:Crime')), findsOneWidget);
      });

      testWidgets('deleting goes up to the parent at once, without the shelf '
          'and with Undo; nothing is written', (tester) async {
        final harness = await _render(tester, page('Crime'), books: books);

        await pick(tester, 'Delete');

        expect(location(tester), '/shelves?tag=Novels');
        expect(subCard('Crime'), findsNothing);
        // Its own sub-shelf comes up a level.
        expect(subCard('Nordic crime'), findsOneWidget);
        expect(_undo, findsOneWidget);
        expect(harness.tags.deleted, isEmpty);
      });

      testWidgets('Undo brings the card back and writes nothing', (
        tester,
      ) async {
        final harness = await _render(tester, page('Crime'), books: books);

        await pick(tester, 'Delete');
        await _tap(tester, _undo);

        expect(subCard('Crime'), findsOneWidget);
        expect(subCard('Nordic crime'), findsNothing);
        expect(harness.tags.deleted, isEmpty);
      });

      testWidgets('a first-level shelf goes up to the grid, Undo brings the '
          'card back', (tester) async {
        final harness = await _render(tester, page('Study'), books: books);

        await pick(tester, 'Delete');
        expect(location(tester), '/shelves');
        expect(card('Study'), findsNothing);
        expect(harness.tags.deleted, isEmpty);

        await _tap(tester, _undo);
        expect(card('Study'), findsOneWidget);
        expect(harness.tags.deleted, isEmpty);
      });

      testWidgets('the deletion goes once the message expires', (tester) async {
        final harness = await _render(tester, page('Crime'), books: books);

        await pick(tester, 'Delete');
        await _letMessagesGo(tester);

        expect(harness.tags.deleted, ['Crime']);
      });

      testWidgets('going elsewhere sends the deletion and takes its Undo away', (
        tester,
      ) async {
        final harness = await _render(tester, page('Crime'), books: books);

        await pick(tester, 'Delete');
        await _tapNow(tester, subCard('Nordic crime'));
        await tester.pump();
        await tester.pump();

        expect(harness.tags.deleted, ['Crime']);
        await _settle(tester);
        expect(_undo, findsNothing);
      });

      testWidgets('leaving for another library tab sends it too', (
        tester,
      ) async {
        final harness = await _render(tester, page('Crime'), books: books);

        await pick(tester, 'Delete');
        await _tapNow(tester, find.widgetWithText(Tab, 'Books'));
        await tester.pump();
        await tester.pump();

        expect(harness.tags.deleted, ['Crime']);
      });

      testWidgets('a page opened over the library sends it too', (tester) async {
        final harness = await _render(tester, page('Crime'), books: books);

        await pick(tester, 'Delete');
        Navigator.of(
          tester.element(find.byType(LibraryScreen)),
          rootNavigator: true,
        ).push(MaterialPageRoute<void>(builder: (_) => const Scaffold()));
        await _settle(tester);

        expect(harness.tags.deleted, ['Crime']);
      });

      testWidgets('the app going to the background sends it too', (
        tester,
      ) async {
        final harness = await _render(tester, page('Crime'), books: books);

        await pick(tester, 'Delete');
        addTearDown(() {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        });
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        await tester.pump();

        expect(harness.tags.deleted, ['Crime']);
        await _letMessagesGo(tester);
      });

      testWidgets('once written, the parent reads the new tree', (tester) async {
        final harness = await _render(tester, page('Crime'), books: books);

        await pick(tester, 'Delete');
        harness.tags.mockTags = [
          for (final t in tags)
            if (t.id != 's3')
              t.id == 's4'
                  ? Tag(id: 's4', name: 'Nordic crime', parentId: 's2', count: 1)
                  : t,
          // Only a new listing can bring this one.
          Tag(id: 's8', name: 'Arrived since', parentId: 's2', count: 0),
        ];
        await _letMessagesGo(tester);

        expect(subCard('Arrived since'), findsOneWidget);
        expect(subCard('Nordic crime'), findsOneWidget);
        expect(subCard('Crime'), findsNothing);
      });
    });
  });

  // Only the fan travels from a card to the head of the shelf's page.
  group('the flight of a fan on the real route', () {
    final flight = find.byKey(const Key('shelfFanFlight'));
    final target = find.byKey(const Key('shelfPlaceFan'));
    Finder card(String shelf) => find.byKey(ValueKey('shelfCard:$shelf'));
    Finder subCard(String shelf) => find.byKey(ValueKey('subShelfCard:$shelf'));
    final tab = _Probe('tab', '/shelves', size: _tallPhone, tags: _treeTags);
    final page = _Probe(
      'page',
      '/shelves?tag=Living+room',
      size: _tallPhone,
      tags: _treeTags,
    );
    Finder fanOf(Finder of) =>
        find.descendant(of: of, matching: find.byType(ShelfThumbnail));

    testWidgets('a tap on a card sends its fan to the head, in 250 ms', (
      tester,
    ) async {
      await _render(tester, tab);
      final from = tester.getRect(fanOf(card('Living room')));

      await tester.tap(card('Living room'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(flight, findsOneWidget);
      final start = tester.getRect(flight);
      expect(start.top, closeTo(from.top, 40));

      await tester.pump(const Duration(milliseconds: 125));
      final middle = tester.getRect(flight);
      expect(middle.width, greaterThan(from.width));

      await tester.pump(const Duration(milliseconds: 150));
      await tester.pump();
      expect(flight, findsNothing);
      await _settle(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the fan at the head waits for it, then shows', (tester) async {
      await _render(tester, tab);

      await tester.tap(card('Living room'));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      double opacity() => tester
          .widget<Opacity>(
            find.ancestor(of: target, matching: find.byType(Opacity)).first,
          )
          .opacity;
      expect(opacity(), 0);

      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(opacity(), 1);
      await _settle(tester);
    });

    testWidgets('only the fan travels: nothing else is in the flight', (
      tester,
    ) async {
      await _render(tester, tab);

      await tester.tap(card('Living room'));
      await tester.pump();
      await tester.pump();

      expect(
        find.descendant(of: flight, matching: find.byType(ShelfThumbnail)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: flight, matching: find.byType(Text)),
        findsNothing,
      );
      await _settle(tester);
    });

    testWidgets('a sub-shelf card flies too', (tester) async {
      await _render(tester, page);

      await tester.tap(subCard('Novels'));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(flight, findsOneWidget);
      await _settle(tester);
      expect(flight, findsNothing);
    });

    testWidgets('with animations off, no flight at all', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await _render(tester, tab);

      await tester.tap(card('Living room'));
      await tester.pump();
      expect(flight, findsNothing);
      await tester.pump();
      await tester.pump();
      expect(flight, findsNothing);
      await _settle(tester);
      expect(target, findsOneWidget);
    });

    testWidgets('the page answers before the end of the flight', (
      tester,
    ) async {
      await _render(tester, tab);

      await tester.tap(card('Living room'));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(flight, findsOneWidget);
      // A touch goes through the fan itself to what lies under it.
      final fan = tester.renderObject(
        find.descendant(of: flight, matching: find.byType(ShelfThumbnail)),
      );
      final hits = tester.hitTestOnBinding(tester.getCenter(flight));
      expect(hits.path.map((e) => e.target), isNot(contains(fan)));

      await tester.tap(find.byKey(const Key('shelfBackButton')));
      await tester.pump();
      await tester.pump();

      expect(
        GoRouterState.of(tester.element(find.byType(LibraryScreen))).uri.toString(),
        '/shelves',
      );
      await _settle(tester);
      expect(flight, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a flight with nowhere to land ends by itself', (tester) async {
      await _render(tester, tab);

      await tester.tap(card('Living room'));
      // The way back before the head is there.
      GoRouter.of(
        tester.element(find.byType(LibraryScreen)),
      ).go('/shelves');
      await _settle(tester);

      expect(flight, findsNothing);
    });
  });

  // Organizing is another place, with a title and a way out, not a mode of the
  // grid: the tree, its drag and its Undo live there and end with it.
  group('organizing the shelves on the real route', () {
    final done = find.widgetWithText(TextButton, 'Done');
    final organize = find.text('Organize');
    Finder card(String shelf) => find.byKey(ValueKey('shelfCard:$shelf'));
    final tab = _Probe('tab', '/shelves', size: _tallPhone, tags: _treeTags);
    Future<void> openFromTab(WidgetTester tester) => _tap(tester, organize);
    String location(WidgetTester tester, Type on) =>
        GoRouterState.of(tester.element(find.byType(on))).uri.toString();

    testWidgets('its route shows the tree under a title, a sentence and Done, '
        'as a full-screen dialog', (tester) async {
      await _render(
        tester,
        _Probe('organize', '/shelves-management', tags: _treeTags),
      );

      expect(find.text('Organize shelves'), findsOneWidget);
      expect(done, findsOneWidget);
      expect(find.byKey(const Key('organizeHint')), findsOneWidget);
      expect(_treeRow('Living room'), findsOneWidget);
      expect(find.byKey(const Key('toShelveCard')), findsNothing);
      final route = ModalRoute.of(tester.element(_treeRow('Living room')))!;
      expect((route as PageRoute).fullscreenDialog, isTrue);
    });

    testWidgets('Done goes back to the tab', (tester) async {
      await _render(tester, tab);
      await openFromTab(tester);

      await _tap(tester, done);

      expect(card('Living room'), findsOneWidget);
      expect(_treeRow('Living room'), findsNothing);
    });

    testWidgets('Escape goes back too', (tester) async {
      await _render(tester, tab);
      await openFromTab(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(tester);

      expect(card('Living room'), findsOneWidget);
    });

    testWidgets('the system back goes back too', (tester) async {
      await _render(tester, tab);
      await openFromTab(tester);

      await tester.binding.handlePopRoute();
      await _settle(tester);

      expect(card('Living room'), findsOneWidget);
    });

    testWidgets('reached by a link, Done leads to the tab all the same', (
      tester,
    ) async {
      await _render(
        tester,
        _Probe('organize', '/shelves-management', tags: _treeTags),
      );

      await _tap(tester, done);

      expect(card('Living room'), findsOneWidget);
    });

    testWidgets('a tap on a name opens that shelf and closes this', (
      tester,
    ) async {
      await _render(tester, tab);
      await openFromTab(tester);

      await _tap(
        tester,
        find.descendant(of: _treeRow('Crime'), matching: find.text('Crime')),
      );

      expect(_treeRow('Crime'), findsNothing);
      expect(location(tester, LibraryScreen), '/shelves?tag=Crime');
    });

    testWidgets('closing sends the waiting deletion and the tab catches up', (
      tester,
    ) async {
      final harness = await _render(tester, tab);
      await openFromTab(tester);
      await _deleteFromRow(tester, 'Study');
      expect(harness.tags.deleted, isEmpty);

      harness.tags.mockTags = [
        for (final t in _treeTags)
          if (t.id != 's5') t,
      ];
      await _tap(tester, done);

      expect(harness.tags.deleted, ['Study']);
      expect(card('Study'), findsNothing);
      expect(_undo, findsNothing);
    });

    testWidgets('Undo before closing writes nothing, closing neither', (
      tester,
    ) async {
      final harness = await _render(tester, tab);
      await openFromTab(tester);
      await _deleteFromRow(tester, 'Study');
      await _tap(tester, _undo);

      await _tap(tester, done);

      expect(harness.tags.deleted, isEmpty);
      expect(card('Study'), findsOneWidget);
    });

    testWidgets('what changed here shows on the tab on closing', (
      tester,
    ) async {
      final harness = await _render(tester, tab);
      await openFromTab(tester);
      await _renameFromRow(tester, 'Study', 'Library');
      harness.tags.mockTags = [
        for (final t in _treeTags)
          t.id == 's5' ? Tag(id: 's5', name: 'Library', count: 5) : t,
      ];

      await _tap(tester, done);

      expect(card('Library'), findsOneWidget);
      expect(card('Study'), findsNothing);
    });

    testWidgets('closing with nothing changed reads nothing more', (
      tester,
    ) async {
      final harness = await _render(tester, tab);
      await openFromTab(tester);
      var refreshes = 0;
      harness.refresh.addListener(() => refreshes++);

      await _tap(tester, done);

      expect(refreshes, 0);
    });

    testWidgets('the Organize entry of a shelf page comes back to that page', (
      tester,
    ) async {
      await _render(
        tester,
        _Probe('page', '/shelves?tag=Crime', size: _tallPhone, tags: _treeTags),
      );
      await _tap(tester, find.byKey(const Key('shelfPlaceMenu')));
      await _tap(tester, find.text('Organize shelves').last);
      expect(_treeRow('Crime'), findsOneWidget);

      await _tap(tester, done);

      expect(location(tester, LibraryScreen), '/shelves?tag=Crime');
    });
  });

  group('undo on the shelves tab on the real route', () {
    final tree = _Probe(
      'shelf tree',
      '/shelves-management',
      size: _tallPhone,
      tags: _treeTags,
    );
    const livingRoomGone =
        'Shelf “Living room” deleted. The books stay in your library; '
        'they just leave this shelf. Its sub-shelf moves up one level.';

    double left(WidgetTester tester, String name) => tester
        .getTopLeft(
          find.descendant(of: _treeRow(name), matching: find.text(name)),
        )
        .dx;

    testWidgets('deleting asks nothing, hides the row and says the one '
        'rule', (tester) async {
      final harness = await _render(tester, tree);

      await _deleteFromRow(tester, 'Living room');

      expect(find.byType(AlertDialog), findsNothing);
      expect(_messageText(livingRoomGone), findsOneWidget);
      expect(_treeRow('Living room'), findsNothing);
      // Its sub-shelf already shows where the deletion will put it.
      expect(left(tester, 'Novels'), left(tester, 'Study'));
      expect(harness.tags.deleted, isEmpty);
      await _letMessagesGo(tester);
    });

    testWidgets('the sub-shelves of a deleted shelf show under its parent, '
        'not at the first level', (tester) async {
      await _render(tester, tree);

      await _deleteFromRow(tester, 'Novels');

      expect(_treeRow('Novels'), findsNothing);
      expect(left(tester, 'Crime'), greaterThan(left(tester, 'Living room')));
      expect(left(tester, 'Crime'), lessThan(left(tester, 'Nordic crime')));
      await _letMessagesGo(tester);
    });

    testWidgets('Undo within five seconds deletes nothing', (tester) async {
      final harness = await _render(tester, tree);
      await _deleteFromRow(tester, 'Living room');

      await _tapNow(tester, _undo);
      await _letMessagesGo(tester);

      expect(harness.tags.deleted, isEmpty);
      expect(_treeRow('Living room'), findsOneWidget);
      expect(left(tester, 'Novels'), greaterThan(left(tester, 'Study')));
    });

    testWidgets('the deletion goes once the message expires', (tester) async {
      final harness = await _render(tester, tree);
      await _deleteFromRow(tester, 'Living room');

      await _letMessagesGo(tester);

      expect(harness.tags.deleted, ['Living room']);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('leaving the tab sends the deletion and takes its Undo '
        'away', (tester) async {
      final harness = await _render(tester, tree);
      await _deleteFromRow(tester, 'Living room');

      GoRouter.of(tester.element(find.byType(OrganizeShelvesScreen))).go('/books');
      // Through the page transition, then the message's own way out.
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(harness.tags.deleted, ['Living room']);
      expect(_undo, findsNothing);
      await _letMessagesGo(tester);
      expect(harness.tags.deleted, ['Living room']);
    });

    testWidgets('a page opened over the tab sends the deletion', (
      tester,
    ) async {
      final harness = await _render(tester, tree);
      await _deleteFromRow(tester, 'Study');

      // An opaque page on top: the tab stays mounted, out of sight.
      Navigator.of(tester.element(find.byType(OrganizeShelvesScreen))).push(
        MaterialPageRoute<void>(builder: (_) => const Scaffold()),
      );
      await _settle(tester);

      expect(harness.tags.deleted, ['Study']);
      await _letMessagesGo(tester);
    });

    testWidgets('a second deletion sends the first', (tester) async {
      final harness = await _render(tester, tree);
      await _deleteFromRow(tester, 'Study');

      // Within the five seconds of the first message.
      await _deleteNowFromRow(tester, 'Crime');

      expect(harness.tags.deleted, ['Study']);
      expect(find.byType(SnackBar), findsOneWidget);
      await _tapNow(tester, _undo);
      await _letMessagesGo(tester);
      expect(harness.tags.deleted, ['Study']);
      expect(_treeRow('Crime'), findsOneWidget);
    });

    testWidgets('the app going to the background sends the deletion', (
      tester,
    ) async {
      final harness = await _render(tester, tree);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      await _deleteFromRow(tester, 'Living room');

      tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.inactive,
      );
      await tester.pump();
      // A glance at the control centre is not leaving the app.
      expect(harness.tags.deleted, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();

      expect(harness.tags.deleted, ['Living room']);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _letMessagesGo(tester);
      expect(harness.tags.deleted, ['Living room']);
    });

    testWidgets('a deletion forgets the shelf\'s own order only once it '
        'goes', (tester) async {
      await _render(tester, tree);
      final order = tester
          .element(find.byType(OrganizeShelvesScreen))
          .read<SortPreferenceProvider>();
      // Created by this read: its own load must not land after the choice.
      await tester.runAsync(order.load);
      await tester.runAsync(() => order.setShelfOrder('s5', true));

      await _deleteFromRow(tester, 'Study');
      expect(order.shelfOrderFor('s5'), isTrue);
      await _tapNow(tester, _undo);
      await _letMessagesGo(tester);
      expect(order.shelfOrderFor('s5'), isTrue);

      await _deleteFromRow(tester, 'Study');
      await _letMessagesGo(tester);
      expect(order.shelfOrderFor('s5'), isFalse);
    });

    testWidgets('with a screen reader on, the message waits for the reader '
        'and so does the deletion', (tester) async {
      final handle = tester.ensureSemantics();
      final harness = await _render(tester, tree);
      _holdMessages(tester);
      await _deleteFromRow(tester, 'Living room');

      await tester.pump(const Duration(seconds: 30));
      await _settle(tester);

      expect(harness.tags.deleted, isEmpty);
      // Announced as it appears, then reachable for as long as it takes.
      expect(
        tester.getSemantics(_messageText(livingRoomGone)),
        containsSemantics(isLiveRegion: true),
      );
      expect(
        tester.getSemantics(_undo),
        containsSemantics(isButton: true, label: 'Undo'),
      );
      await _tapNow(tester, _undo);
      expect(harness.tags.deleted, isEmpty);
      expect(_treeRow('Living room'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('Undo after a move puts the shelf back under its parent', (
      tester,
    ) async {
      final harness = await _render(tester, tree);
      await _tap(tester, _treeHandle('Crime'));
      await _tap(tester, _moveRow('Study'));
      expect(_messageText('Crime moved under Study'), findsOneWidget);

      await _tapNow(tester, _undo);

      expect(harness.tags.updated, ['s3: Crime < s5', 's3: Crime < s2']);
      await _letMessagesGo(tester);
    });

    testWidgets('Undo after a drop puts the shelf back', (tester) async {
      final harness = await _render(tester, tree);
      await _dragShelf(tester, 'Study', _treeRow('Novels'));

      await _tapNow(tester, _undo);

      expect(harness.tags.updated, ['s5: Study < s2', 's5: Study']);
      await _letMessagesGo(tester);
    });

    testWidgets('Undo of a move whose former parent is gone since puts the '
        'shelf at the first level', (tester) async {
      final harness = await _render(tester, tree);
      await _tap(tester, _treeHandle('Crime'));
      await _tap(tester, _moveRow('Study'));
      // A sync removed Novels while the message was up.
      harness.tags.mockTags = [
        for (final t in _treeTags)
          if (t.id != 's2') t,
      ];

      await _tapNow(tester, _undo);

      expect(harness.tags.updated, ['s3: Crime < s5', 's3: Crime']);
      await _letMessagesGo(tester);
    });

    testWidgets('Undo of a move that gave a shelf its row keeps the row, '
        'at the first level', (tester) async {
      final legacy = Tag(id: 'legacy:-1', name: 'Poetry', count: 2);
      final harness = await _render(
        tester,
        tree,
        tags: [..._treeTags, legacy],
      );
      await _tap(tester, _treeHandle('Poetry'));
      await _tap(tester, _moveRow('Study'));
      expect(harness.tags.created, ['Poetry < s5']);
      // The row the move created, as the next listing returns it.
      harness.tags.mockTags = [
        ..._treeTags,
        Tag(id: '1', name: 'Poetry', parentId: 's5', count: 2),
      ];

      await _tapNow(tester, _undo);

      expect(harness.tags.updated, ['1: Poetry']);
      expect(harness.tags.deleted, isEmpty);
      await _letMessagesGo(tester);
    });

    testWidgets('Undo after a rename brings the name back', (tester) async {
      final harness = await _render(tester, tree);
      await _renameFromRow(tester, 'Living room', 'Lounge');
      expect(_messageText('Shelf updated'), findsOneWidget);

      await _tapNow(tester, _undo);

      expect(harness.tags.updated, ['s1: Lounge', 's1: Living room']);
      await _letMessagesGo(tester);
    });

    testWidgets('Undo of a rename leaves alone a name another shelf took '
        'since', (tester) async {
      final harness = await _render(tester, tree);
      await _renameFromRow(tester, 'Living room', 'Lounge');
      harness.tags.mockTags = [
        Tag(id: 's1', name: 'Lounge', count: 2),
        for (final t in _treeTags)
          if (t.id != 's1') t,
        Tag(id: 's9', name: 'Living room', count: 0),
      ];

      await _tapNow(tester, _undo);

      expect(harness.tags.updated, ['s1: Lounge']);
      expect(
        _messageText('The name “Living room” is already taken by another '
            'shelf.'),
        findsOneWidget,
      );
      await _letMessagesGo(tester);
    });

    testWidgets('a deletion sent while its message still waits behind '
        'another leaves no Undo behind', (tester) async {
      final harness = await _render(tester, tree);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      await _renameFromRow(tester, 'Living room', 'Lounge');
      // A row near the top: the message, above every route, covers the
      // menu of the last one.
      await _tapNow(tester, find.byTooltip('Actions for Crime'));
      await tester.tap(find.text('Delete Shelf'));
      // Within the 250 ms the rename's message takes to leave: the
      // deletion's waits behind it.
      await tester.pump(const Duration(milliseconds: 50));
      expect(_messageText('Shelf updated'), findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await _settle(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _settle(tester);

      expect(harness.tags.deleted, ['Crime']);
      expect(_undo, findsNothing);
      await _letMessagesGo(tester);
    });

    testWidgets('leaving the tab takes away the Undo of a rename', (
      tester,
    ) async {
      final harness = await _render(tester, tree);
      // Held as a screen reader holds it, or it would follow the reader
      // from screen to screen.
      _holdMessages(tester);
      await _renameFromRow(tester, 'Living room', 'Lounge');
      expect(_undo, findsOneWidget);

      GoRouter.of(tester.element(find.byType(OrganizeShelvesScreen))).go('/books');
      // Through the page transition, then the message's own way out.
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(_undo, findsNothing);
      expect(harness.tags.updated, ['s1: Lounge']);
    });

    testWidgets('with a screen reader on, a message of the tab replaces an '
        'Undo rather than waiting behind it', (tester) async {
      final harness = await _render(tester, tree);
      _holdMessages(tester);
      await _renameFromRow(tester, 'Living room', 'Lounge');

      await _openShelfRowMenu(tester, 'Study');
      await _tap(tester, find.text('Add Sub-Shelf'));
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextFormField),
        ),
        'Poetry',
      );
      await _tap(tester, find.text('Create'));

      expect(harness.tags.created, ['Poetry < s5']);
      expect(_messageText('Shelf created'), findsOneWidget);
      expect(_undo, findsNothing);
    });

    testWidgets('a shelf with no row waiting on its deletion stays the one '
        'hidden when a reload renumbers such shelves', (tester) async {
      final poetry = Tag(id: 'legacy:-1', name: 'Poetry', count: 2);
      final essays = Tag(id: 'legacy:-2', name: 'Essays', count: 1);
      final harness = await _render(
        tester,
        tree,
        tags: [..._treeTags, poetry, essays],
      );
      await _deleteFromRow(tester, 'Poetry');

      // The core numbers them in no stable order.
      harness.tags.mockTags = [
        ..._treeTags,
        Tag(id: 'legacy:-1', name: 'Essays', count: 1),
        Tag(id: 'legacy:-2', name: 'Poetry', count: 2),
      ];
      harness.refresh.refresh();
      await _settle(tester);

      expect(_treeRow('Poetry'), findsNothing);
      expect(_treeRow('Essays'), findsOneWidget);
      await _tapNow(tester, _undo);
      expect(_treeRow('Poetry'), findsOneWidget);
      expect(harness.tags.deleted, isEmpty);
      await _letMessagesGo(tester);
    });

    testWidgets('a deletion the core refuses comes back with its error, and '
        'the next one keeps waiting on its Undo', (tester) async {
      final harness = await _render(tester, tree);
      harness.tags
        ..mockDeleteFailsFor = 'Study'
        ..mockDeleteDelay = const Duration(milliseconds: 800);
      await _deleteFromRow(tester, 'Study');
      // Sends Study, whose write fails once Crime's message is up.
      await _deleteNowFromRow(tester, 'Crime');

      expect(_treeRow('Study'), findsOneWidget);
      expect(_treeRow('Crime'), findsNothing);
      expect(harness.tags.deleted, isEmpty);
      expect(_messageText('Shelf “Crime” deleted.'), findsOneWidget);
      expect(_undo, findsOneWidget);

      await _letMessagesGo(tester);
      expect(harness.tags.deleted, ['Crime']);
      // The error waited its turn.
      expect(_messageText('core refused'), findsOneWidget);
      await _letMessagesGo(tester);
    });

    testWidgets('a slow listing started before a deletion went does not '
        'bring the shelf back', (tester) async {
      final harness = await _render(tester, tree);
      await _deleteFromRow(tester, 'Study');
      final stale = Completer<List<Tag>>();
      final before = harness.tags.mockTags;
      harness.tags.holdNextGetTags = stale;
      // A book changed elsewhere: a reload that hangs.
      harness.refresh.refresh();
      await tester.pump();

      await _letMessagesGo(tester);
      expect(harness.tags.deleted, ['Study']);
      expect(_treeRow('Study'), findsNothing);

      stale.complete(before);
      await _settle(tester);
      expect(_treeRow('Study'), findsNothing);
    });

    testWidgets('a reload started while the deletion\'s own reload is out '
        'keeps the shelf hidden until a fresh listing lands', (tester) async {
      final harness = await _render(tester, tree);
      await _deleteFromRow(tester, 'Study');
      final own = Completer<List<Tag>>();
      harness.tags.holdNextGetTags = own;

      // The message expires: the write lands, its reload hangs.
      await _letMessagesGo(tester);
      expect(harness.tags.deleted, ['Study']);
      final later = Completer<List<Tag>>();
      harness.tags.holdNextGetTags = later;
      // A sync starts another reload before the first comes back.
      harness.refresh.refresh();
      await tester.pump();

      // The first comes back superseded, and is dropped.
      own.complete(harness.tags.mockTags);
      await _settle(tester);
      expect(_treeRow('Study'), findsNothing);

      later.complete(harness.tags.mockTags);
      await _settle(tester);
      expect(_treeRow('Study'), findsNothing);
      expect(_treeRow('Crime'), findsOneWidget);
    });

    testWidgets('renaming a sub-shelf of a shelf waiting on its deletion '
        'keeps it under that shelf', (tester) async {
      final harness = await _render(tester, tree);
      // Held, so that the deletion still waits when the rename is saved.
      _holdMessages(tester);
      await _deleteFromRow(tester, 'Novels');

      // Shown under Living room meanwhile, stored under Novels still.
      await _renameFromRow(tester, 'Crime', 'Polar');

      expect(harness.tags.updated, ['s3: Polar < s2']);
    });

    testWidgets('the app going to the background keeps the Undo of a '
        'rename', (tester) async {
      final harness = await _render(tester, tree);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      await _renameFromRow(tester, 'Living room', 'Lounge');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      // Long enough for a closed message to have left, still within five
      // seconds of the rename.
      await _settle(tester);

      expect(_undo, findsOneWidget);
      await _tapNow(tester, _undo);
      expect(harness.tags.updated, ['s1: Lounge', 's1: Living room']);
      await _letMessagesGo(tester);
    });

    testWidgets('one message at a time: a move after a deletion sends the '
        'deletion', (tester) async {
      final harness = await _render(tester, tree);
      await _deleteFromRow(tester, 'Study');

      // Within the five seconds of the deletion's message.
      await _tapNow(tester, _treeHandle('Crime'));
      await _tapNow(tester, _moveRow('Living room'));

      expect(harness.tags.deleted, ['Study']);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(_messageText('Crime moved under Living room'), findsOneWidget);
      await _letMessagesGo(tester);
    });
  });

  for (final probe in _probes) {
    testWidgets('${probe.name}: every tap target has a name and a role', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _render(tester, probe);
      await _expectAccessibleTapTargets(tester);
      handle.dispose();
    });
  }
}
