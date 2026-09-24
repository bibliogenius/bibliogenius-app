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
// section open, the drawer and the rail) and scrolls each page one viewport
// at a time, because a widget off screen is not in the tree. Screens and
// states outside [_probes] are not covered.
//
// `A11Y_GUARD_VERBOSE=1` lists every tap target each probe rendered.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show CheckedState, SemanticsAction, SemanticsRole, Tristate;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
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
import 'package:bibliogenius/screens/book_details_screen.dart';
import 'package:bibliogenius/screens/borrow_requests_screen.dart';
import 'package:bibliogenius/screens/collection/collection_detail_screen.dart';
import 'package:bibliogenius/screens/dashboard_screen.dart';
import 'package:bibliogenius/screens/library_screen.dart';
import 'package:bibliogenius/screens/network_screen.dart';
import 'package:bibliogenius/screens/profile_screen.dart';
import 'package:bibliogenius/screens/settings_screen.dart';
import 'package:bibliogenius/services/api_service.dart';
import 'package:bibliogenius/services/auth_service.dart';
import 'package:bibliogenius/services/backup_scheduler_service.dart';
import 'package:bibliogenius/services/ffi_service.dart';
import 'package:bibliogenius/services/sync_service.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/scaffold_with_nav.dart';

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
/// 3, My Books"). Flutter joins merged texts with newlines, so a repeated
/// line, or later lines all already contained in the first, is the mark.
bool _readsTwice(String label) {
  final lines = label
      .split('\n')
      .map((l) => l.trim().toLowerCase())
      .where((l) => l.isNotEmpty)
      .toList();
  if (lines.length < 2) return false;
  if (lines.toSet().length < lines.length) return true;
  return lines.skip(1).every(lines.first.contains);
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
    title: 'The Anomaly',
    author: 'Herve Le Tellier',
    readingStatus: 'to_read',
    subjects: ['Novel'],
  ),
  Book(
    id: 'b2',
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
  final tags = MockTagRepository()..mockTags = _tags;
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
              builder: (_, state) => LibraryScreen(
                initialIndex: 1,
                shelfTagFilter: state.uri.queryParameters['tag'],
              ),
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
            GoRoute(path: '/settings', builder: (_, _) => SettingsScreen()),
          ],
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
        ChangeNotifierProvider<SortPreferenceProvider>(
          create: (_) => SortPreferenceProvider(),
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

  /// Taps that lead from the route to the state under audit.
  final Future<void> Function(WidgetTester tester)? reach;

  const _Probe(
    this.name,
    this.location, {
    this.size = _phone,
    this.collections = false,
    this.bottomNav = true,
    this.reach,
  });
}

// Phone width puts the bottom-bar / drawer shell in play; the wide layout is
// the navigation rail. Both are the first thing a reader navigates.
const _phone = Size(390, 844);
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
  const _Probe('library, shelves tab', '/shelves'),
  const _Probe('library, sub-shelves', '/shelves?tag=Genre'),
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
  // Most of the settings page sits in collapsed sections, out of the tree
  // until opened.
  _Probe('settings, every section open', '/settings', reach: _expandAll),
  // Navigation itself: the drawer (bottom bar off) and the rail (wide).
  _Probe(
    'drawer',
    '/books',
    bottomNav: false,
    reach: (t) => _tap(t, find.byTooltip('Open menu')),
  ),
  const _Probe('navigation rail', '/books', size: _desktop),
];

/// Renders [probe] and leaves it settled on the state under audit.
Future<void> _render(WidgetTester tester, _Probe probe) async {
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
