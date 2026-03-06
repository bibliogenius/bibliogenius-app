import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'config/platform_init.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:dio/dio.dart';
import 'services/auth_service.dart';
import 'services/api_service.dart';
import 'services/sync_service.dart';
import 'services/translation_service.dart';
import 'services/mdns_service.dart';
import 'services/ffi_service.dart';
import 'src/rust/api/frb.dart' as frb;
import 'utils/app_constants.dart';
import 'utils/invite_payload.dart';
import 'utils/language_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/theme_provider.dart';
import 'providers/book_refresh_notifier.dart';
import 'providers/pending_peers_provider.dart';
import 'audio/audio_module.dart'; // Audio module (decoupled)
import 'providers/memory_game_provider.dart';
import 'providers/device_sync_provider.dart';
import 'providers/operation_log_provider.dart';
import 'providers/sliding_puzzle_provider.dart';
import 'data/repositories/book_repository.dart';
import 'data/repositories/tag_repository.dart';
import 'data/repositories/contact_repository.dart';
import 'data/repositories/collection_repository.dart';
import 'data/repositories/copy_repository.dart';
import 'data/repositories/loan_repository.dart';
import 'data/repositories_impl/book_repository_impl.dart';
import 'data/repositories_impl/tag_repository_impl.dart';
import 'data/repositories_impl/contact_repository_impl.dart';
import 'data/repositories_impl/collection_repository_impl.dart';
import 'data/repositories_impl/copy_repository_impl.dart';
import 'data/repositories_impl/loan_repository_impl.dart';

import 'screens/login_screen.dart';
import 'screens/add_book_screen.dart';
import 'screens/book_copies_screen.dart';
import 'screens/book_details_screen.dart';
import 'screens/edit_book_screen.dart';
import 'screens/add_contact_screen.dart';
import 'screens/contact_details_screen.dart';
import 'models/book.dart';
import 'models/contact.dart';
import 'screens/scan_screen.dart';
import 'screens/scan_qr_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/setup_screen.dart';

import 'screens/peer_book_list_screen.dart';
import 'screens/peer_detail_screen.dart';
import 'models/library_relation.dart';
import 'screens/shelf_management_screen.dart';
import 'screens/search_peer_screen.dart';
import 'screens/memory_game_screen.dart';
import 'screens/operation_log_screen.dart';
import 'screens/sliding_puzzle_screen.dart';
import 'screens/games_hub_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/statistics_screen.dart';
import 'screens/help_screen.dart';
import 'screens/network_search_screen.dart';
import 'screens/onboarding_tour_screen.dart';
import 'screens/network_screen.dart';
import 'screens/borrow_requests_screen.dart';
import 'screens/library_screen.dart';
import 'screens/feedback_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/migration_wizard_screen.dart';

import 'screens/link_device_screen.dart';
import 'screens/device_pairing_screen.dart';
import 'screens/sync_review_screen.dart';
import 'screens/external_search_screen.dart';
import 'screens/invite_acceptance_screen.dart';
import 'screens/library_catalog_screen.dart';
import 'screens/notifications_screen.dart';
import 'providers/hub_directory_provider.dart';
import 'providers/flash_message_provider.dart';
import 'providers/notification_provider.dart';
import 'package:app_links/app_links.dart';

import 'services/wizard_service.dart';
import 'widgets/scaffold_with_nav.dart';

import 'package:flutter/gestures.dart';

import 'screens/collection/collection_detail_screen.dart';
import 'models/collection.dart';

class AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
  };
}

void main([List<String>? args]) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Custom error widget to display errors visibly for debugging
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Colors.red.shade50,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '⚠️ Error',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  details.exception.toString(),
                  style: const TextStyle(fontSize: 14, color: Colors.black87),
                ),
                const SizedBox(height: 16),
                Text(
                  details.stack?.toString() ?? 'No stack trace',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.black54,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  };

  Map<String, String> envConfig = {};
  try {
    await dotenv.load(fileName: ".env");
    envConfig = dotenv.env;
  } catch (e) {
    debugPrint('No .env file found, using default configuration');
  }
  await TranslationService.loadFromCache();
  await TranslationService.loadTranslations();
  final themeProvider = ThemeProvider();

  // Load settings early so library name is available for mDNS
  try {
    await themeProvider.loadSettings();
    // Auto-initialize defaults if first launch (skip setup wizard)
    final authService = AuthService();
    if (!themeProvider.isSetupComplete) {
      await themeProvider.initializeDefaults();
      // Auto-login user on first launch (no password required by default)
      await authService.saveUsername('admin');
      await authService.saveToken(
        'local-auto-token-${DateTime.now().millisecondsSinceEpoch}',
      );
      debugPrint('✅ First launch: auto-logged in as admin');
    } else {
      // Fallback: auto-login for existing installs without a token
      final isLoggedIn = await authService.isLoggedIn();
      if (!isLoggedIn) {
        await authService.saveUsername('admin');
        await authService.saveToken(
          'local-auto-token-${DateTime.now().millisecondsSinceEpoch}',
        );
        debugPrint('✅ Existing install: auto-logged in as admin');
      }
    }
    // Initialize feature flags
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('enableHierarchicalTags')) {
      AppConstants.enableHierarchicalTags =
          prefs.getBool('enableHierarchicalTags') ?? true;
    }
  } catch (e) {
    debugPrint('Error loading settings early: $e');
  }

  // Initialize FFI for native platforms using conditional imports (Web friendly)
  bool useFfi = await initializePlatform();

  if (useFfi) {
    // Sync library name to Rust backend now that FFI is ready
    // (fixes desync where SharedPrefs has the user's name but SQLite has the default)
    if (themeProvider.libraryName != 'My Library') {
      try {
        await FfiService().updateLibraryName(themeProvider.libraryName);
      } catch (e) {
        debugPrint('Startup library name sync (non-fatal): $e');
      }
    }

    int httpPort = 8000;
    try {
      final startedPort = await FfiService().startServer(8000);
      if (startedPort != null) {
        httpPort = startedPort;
        ApiService.setHttpPort(httpPort); // Store the actual port globally
        debugPrint('FFI: HTTP server confirmed running on port $httpPort');
      }
    } catch (e) {
      debugPrint('FFI: Failed to start HTTP server: $e');
    }

    // Initialize E2EE identity if any network feature is active
    // (local discovery OR remote reachable via relay).
    // Identity is required for both mDNS key exchange and relay E2EE.
    String? ed25519Key;
    String? x25519Key;
    String? libraryUuid;

    if (themeProvider.networkDiscoveryEnabled ||
        themeProvider.remoteReachableEnabled) {
      try {
        final authService = AuthService();
        libraryUuid = await authService.getOrCreateLibraryUuid();

        await frb.initIdentityFfi(libraryUuid: libraryUuid);
        final keysJson = await frb.getPublicKeysFfi();
        final keys = Map<String, dynamic>.from(
          const JsonDecoder().convert(keysJson) as Map,
        );
        ed25519Key = keys['ed25519'] as String?;
        x25519Key = keys['x25519'] as String?;
        debugPrint(
            'E2EE: Identity initialized (hasKeys=${ed25519Key != null})');
      } catch (e) {
        debugPrint('E2EE: Identity init failed (non-blocking): $e');
      }
    }

    // Auto-initialize mDNS for local network discovery (Native Bonjour)
    // This makes the app discoverable on the local WiFi network
    // Only start if user has enabled network discovery in settings
    if (themeProvider.networkDiscoveryEnabled) {
      try {
        if (libraryUuid == null) {
          final authService = AuthService();
          libraryUuid = await authService.getOrCreateLibraryUuid();
        }

        // Use clean library name for mDNS (no hostname suffix).
        // Disambiguation is handled by short library_id in the UI.
        final libraryName = themeProvider.libraryName.isNotEmpty
            ? themeProvider.libraryName
            : 'BiblioGenius Library';
        await MdnsService.startAnnouncing(
          libraryName,
          httpPort,
          libraryId: libraryUuid,
          ed25519PublicKey: ed25519Key,
          x25519PublicKey: x25519Key,
        );
        await MdnsService.startDiscovery();
      } catch (mdnsError) {
        debugPrint('mDNS: Init failed (non-blocking): $mdnsError');
      }
    } else {
      debugPrint('mDNS: Disabled by user preference');
    }

    // Auto-setup relay hub for WAN communication (if not already configured)
    // Relay is independent of mDNS: it enables connectivity via the hub
    // even without local network discovery (e.g. on cellular/different WiFi)
    if (themeProvider.remoteReachableEnabled) {
      try {
        final localDio = Dio(
          BaseOptions(baseUrl: 'http://localhost:$httpPort'),
        );
        bool needsSetup = true;
        try {
          final configRes = await localDio.get('/api/peers/relay/config');
          if (configRes.statusCode == 200 &&
              configRes.data is Map &&
              configRes.data['relay_url'] != null) {
            needsSetup = false;
            debugPrint('Relay: Already configured (${configRes.data['relay_url']})');
          }
        } on DioException {
          // 404 = no config yet - needs setup
        }
        if (needsSetup) {
          await localDio.post(
            '/api/peers/relay/setup',
            data: {'relay_url': ApiService.hubUrl},
          );
          debugPrint('Relay: Auto-configured with ${ApiService.hubUrl}');
        }
      } catch (e) {
        debugPrint('Relay: Auto-setup failed (non-blocking): $e');
      }
    }
  }

  // Settings already loaded earlier, no need to call again

  runApp(
    MyApp(themeProvider: themeProvider, useFfi: useFfi, envConfig: envConfig),
  );
}

class MyApp extends StatelessWidget {
  final ThemeProvider themeProvider;
  final bool useFfi;
  final Map<String, String> envConfig;

  const MyApp({
    super.key,
    required this.themeProvider,
    required this.useFfi,
    required this.envConfig,
  });

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();

    // Determine base URL for HTTP mode (web or fallback)
    String baseUrl = envConfig['API_BASE_URL'] ?? '';

    if (useFfi) {
      // FFI mode: no HTTP needed for local operations
      baseUrl = 'ffi://local'; // Placeholder, ApiService will detect FFI mode
      debugPrint('Using FFI mode for local database operations');
    } else if (baseUrl.isNotEmpty) {
      debugPrint('Using API_BASE_URL from .env: $baseUrl');
    } else {
      baseUrl = ApiService.defaultBaseUrl;
      debugPrint('Using Default Backend URL: $baseUrl');
    }

    final apiService = ApiService(
      authService,
      baseUrl: baseUrl,
      useFfi: useFfi,
    );

    // Run TTL cleanup for peer_books cache (privacy: auto-delete entries older than 30 days)
    // Run async, don't block app startup
    apiService.cleanupStalePeerBooksCache();

    // Enrich missing covers in background (async, don't block startup)
    final bookRefreshNotifier = BookRefreshNotifier();
    apiService.enrichMissingCovers().then((count) {
      if (count > 0) {
        debugPrint('Enriched $count book covers');
        bookRefreshNotifier.refresh();
      }
    });

    Widget app = MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
        ChangeNotifierProvider<BookRefreshNotifier>.value(
          value: bookRefreshNotifier,
        ),
        Provider<AuthService>.value(value: authService),
        Provider<ApiService>.value(value: apiService),
        Provider<BookRepository>.value(
          value: BookRepositoryImpl(apiService),
        ),
        Provider<TagRepository>.value(
          value: TagRepositoryImpl(apiService),
        ),
        Provider<ContactRepository>.value(
          value: ContactRepositoryImpl(apiService),
        ),
        Provider<CollectionRepository>.value(
          value: CollectionRepositoryImpl(FfiService()),
        ),
        Provider<CopyRepository>.value(
          value: CopyRepositoryImpl(apiService),
        ),
        Provider<LoanRepository>.value(
          value: LoanRepositoryImpl(apiService),
        ),
        Provider<SyncService>(create: (_) => SyncService(apiService)),
        // Audio module (decoupled, can be removed without breaking the app)
        ChangeNotifierProvider<AudioProvider>(create: (_) => AudioProvider()),
        ChangeNotifierProvider<PendingPeersProvider>(
          create: (_) => PendingPeersProvider(apiService),
        ),
        ChangeNotifierProvider<MemoryGameProvider>(
          create: (_) => MemoryGameProvider(),
        ),
        ChangeNotifierProvider<SlidingPuzzleProvider>(
          create: (_) => SlidingPuzzleProvider(),
        ),
        ChangeNotifierProvider<OperationLogProvider>(
          create: (_) => OperationLogProvider(),
        ),
        ChangeNotifierProvider<DeviceSyncProvider>(
          create: (_) => DeviceSyncProvider(),
        ),
        ChangeNotifierProvider<HubDirectoryProvider>(
          create: (_) => HubDirectoryProvider()
            ..loadHubEnabled()
            ..loadContactInfo()
            ..loadCustomFollowNames(),
        ),
        ChangeNotifierProvider<FlashMessageProvider>(
          create: (_) => FlashMessageProvider(),
        ),
        ChangeNotifierProvider<NotificationProvider>(
          create: (_) => NotificationProvider()..init(),
        ),
      ],
      child: const AppRouter(),
    );

    return app;
  }
}

class AppRouter extends StatefulWidget {
  const AppRouter({super.key});

  @override
  State<AppRouter> createState() => _AppRouterState();
}

class _AppRouterState extends State<AppRouter> with WidgetsBindingObserver {
  late final GoRouter _router;
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  String? _lastHandledDeepLink;
  Timer? _deepLinkTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);

    _router = GoRouter(
      initialLocation: '/books',
      refreshListenable: themeProvider,
      errorBuilder: (context, state) {
        debugPrint('GoRouter error: no route for uri=${state.uri} path=${state.uri.path} scheme=${state.uri.scheme} host=${state.uri.host} query=${state.uri.query}');
        return Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 64),
                const SizedBox(height: 16),
                Text(
                  TranslationService.translate(context, 'page_not_found_title'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  TranslationService.translate(context, 'page_not_found_message'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => context.go('/books'),
                  icon: const Icon(Icons.home),
                  label: Text(TranslationService.translate(context, 'back_to_library')),
                ),
              ],
            ),
          ),
        );
      },
      redirect: (context, state) async {
        // Handle custom scheme deep links (bibliogenius://invite?d=...).
        // On cold start, GoRouter receives the custom scheme URL as the
        // initial route. Since the path is empty (host=invite, path=""),
        // no route matches and the error page shows. Intercept here and
        // redirect to the proper /invite path with the query parameter.
        if (state.uri.scheme == 'bibliogenius' && state.uri.host == 'invite') {
          final d = state.uri.queryParameters['d'];
          debugPrint('GoRouter redirect: intercepted custom scheme invite (d=${d != null ? "present" : "missing"})');
          if (d != null) return '/invite?d=$d';
          return '/books';
        }
        // Fallback: GoRouter may strip the scheme, leaving empty path + d param
        if (state.uri.path.isEmpty && state.uri.queryParameters.containsKey('d')) {
          return '/invite?d=${state.uri.queryParameters['d']}';
        }

        final isOnboardingRoute = state.uri.path == '/onboarding';
        final isLoginRoute = state.uri.path == '/login';
        final isInviteRoute = state.uri.path == '/invite';
        final authService = Provider.of<AuthService>(context, listen: false);

        // Never redirect away from invite screen
        if (isInviteRoute) return null;

        // Auto-init if setup not complete (e.g., after resetSetup)
        if (!themeProvider.isSetupComplete) {
          await themeProvider.initializeDefaults();
          await authService.saveUsername('admin');
          await authService.saveToken(
            'local-auto-token-${DateTime.now().millisecondsSinceEpoch}',
          );
          debugPrint('✅ Redirect: auto-initialized and logged in');
        }

        // Auth check
        var isLoggedIn = await authService.isLoggedIn();

        if (!isLoggedIn) {
          final hasPassword = await authService.hasPasswordSet();
          if (hasPassword) {
            // Password configured - must show login screen
            if (isLoginRoute) return null;
            return '/login';
          }

          // No password - perform auto-login for seamless experience
          await authService.saveUsername('admin');
          await authService.saveToken(
            'local-auto-token-${DateTime.now().millisecondsSinceEpoch}',
          );
          isLoggedIn = true;
          debugPrint('✅ Redirect: auto-logged in (no password set)');
          // Continue to destination (now logged in)
        }

        // Logged in user trying to access login
        if (isLoggedIn && isLoginRoute) {
          return '/books';
        }

        // Onboarding check (only if logged in)
        if (isLoggedIn && state.uri.path == '/books') {
          final hasSeenTour = await WizardService.hasSeenOnboardingTour();
          if (!hasSeenTour) return '/onboarding';
        }

        return null;
      },
      routes: [
        GoRoute(
          path: '/setup',
          builder: (context, state) => const SetupScreen(),
        ),
        GoRoute(
          path: '/onboarding',
          builder: (context, state) => const OnboardingTourScreen(),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),
        GoRoute(
          path: '/shelves-management',
          builder: (context, state) => const ShelfManagementScreen(),
        ),
        GoRoute(
          path: '/invite',
          builder: (context, state) {
            var payload = state.extra as Map<String, dynamic>?;
            // Also decode d= query parameter (from GoRouter redirect on cold
            // start via custom scheme, or from long-format invite URL).
            if (payload == null) {
              final d = state.uri.queryParameters['d'];
              if (d != null) {
                try {
                  final decoded = base64Url.decode(base64Url.normalize(d));
                  final jsonStr = utf8.decode(decoded);
                  final raw = jsonDecode(jsonStr) as Map<String, dynamic>;
                  payload = normalizeInvitePayload(raw);
                } catch (e) {
                  debugPrint('Invite query param decode error: $e');
                }
              }
            }
            if (payload == null) return const LibraryScreen(initialIndex: 0);
            return InviteAcceptanceScreen(payload: payload);
          },
        ),
        ShellRoute(
          builder: (context, state, child) {
            return ScaffoldWithNav(child: child);
          },
          routes: [
            GoRoute(
              path: '/dashboard',
              builder: (context, state) => const DashboardScreen(),
            ),
            GoRoute(
              path: '/games',
              redirect: (context, state) {
                final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
                if (!themeProvider.gamesEnabled) return '/dashboard';
                return null;
              },
              builder: (context, state) => const GamesHubScreen(),
            ),
            GoRoute(
              path: '/memory-game',
              redirect: (context, state) {
                final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
                if (!themeProvider.memoryGameEnabled) return '/games';
                return null;
              },
              builder: (context, state) => const MemoryGameScreen(),
            ),
            GoRoute(
              path: '/sliding-puzzle',
              redirect: (context, state) {
                final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
                if (!themeProvider.slidingPuzzleEnabled) return '/games';
                return null;
              },
              builder: (context, state) => const SlidingPuzzleScreen(),
            ),
            GoRoute(
              path: '/operation-log',
              redirect: (context, state) {
                final tp = Provider.of<ThemeProvider>(context, listen: false);
                if (!tp.operationLogViewerEnabled) return '/settings';
                return null;
              },
              builder: (context, state) => const OperationLogScreen(),
            ),
            GoRoute(
              path: '/device-pairing',
              builder: (context, state) => const DevicePairingScreen(),
            ),
            GoRoute(
              path: '/sync-review',
              builder: (context, state) => const SyncReviewScreen(),
            ),
            GoRoute(
              path: '/books',
              pageBuilder: (context, state) =>
                  NoTransitionPage(child: LibraryScreen(initialIndex: 0)),
              routes: [
                GoRoute(
                  path: 'add',
                  builder: (context, state) {
                    final extra = state.extra as Map<String, dynamic>?;
                    final queryParams = state.uri.queryParameters;

                    final isbn = extra?['isbn'] ?? queryParams['isbn'];

                    final collectionIdStr =
                        extra?['collectionId']?.toString() ??
                        queryParams['collectionId'];
                    final preSelectedCollectionId = collectionIdStr;

                    final preSelectedShelfId =
                        extra?['shelfId'] ?? queryParams['shelfId'];

                    return AddBookScreen(
                      isbn: isbn,
                      preSelectedCollectionId: preSelectedCollectionId,
                      preSelectedShelfId: preSelectedShelfId,
                    );
                  },
                ),
                GoRoute(
                  path: ':id',
                  builder: (context, state) {
                    final bookId =
                        int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
                    Book? book;
                    if (state.extra is Book) {
                      book = state.extra as Book;
                    } else if (state.extra is Map<String, dynamic>) {
                      book = Book.fromJson(state.extra as Map<String, dynamic>);
                    }
                    return BookDetailsScreen(bookId: bookId, book: book);
                  },
                ),
                GoRoute(
                  path: ':id/edit',
                  builder: (context, state) {
                    Book? book;
                    if (state.extra is Book) {
                      book = state.extra as Book;
                    } else if (state.extra is Map<String, dynamic>) {
                      book = Book.fromJson(state.extra as Map<String, dynamic>);
                    }
                    /* WARNING: EditBookScreen currently REQUIRES a Book object. 
                       If deep linking support is needed here, EditBookScreen must also be refactored 
                       to fetch by ID, similar to BookDetailsScreen. 
                       For now, this remains a risk if navigated to directly without extra. */
                    if (book == null) {
                      // Fallback or error screen could be returned here ideally
                      // For now we assume typical navigation flow or let it throw/show error
                      // But to prevent hard crash let's redirect or show details if possible?
                      // Actually EditBookScreen constructor requires 'book'.
                      throw Exception(
                        'Direct navigation to edit not fully supported without object properly passed yet. Please go via details.',
                      );
                    }
                    return EditBookScreen(book: book);
                  },
                ),
                GoRoute(
                  path: ':id/copies',
                  builder: (context, state) {
                    final bookId =
                        int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
                    final extra = state.extra as Map<String, dynamic>?;
                    final bookTitle = extra?['bookTitle'] as String? ?? '';
                    return BookCopiesScreen(
                      bookId: bookId,
                      bookTitle: bookTitle,
                    );
                  },
                ),
              ],
            ),
            // External search - inside ShellRoute for hamburger menu access
            GoRoute(
              path: '/search/external',
              builder: (context, state) => const ExternalSearchScreen(),
            ),
            GoRoute(
              path: '/network',
              redirect: (context, state) {
                // Loans tabs moved to /requests
                final tab = state.uri.queryParameters['tab'];
                if (tab == 'lent' || tab == 'borrowed') {
                  return '/requests?tab=$tab';
                }
                return null;
              },
              builder: (context, state) {
                final tab = state.uri.queryParameters['tab'];
                final initialIndex = tab == 'discover' ? 1 : 0;
                return NetworkScreen(initialIndex: initialIndex);
              },
              routes: [
                GoRoute(
                  path: 'contact/:id',
                  builder: (context, state) {
                    final contact = state.extra as Contact?;
                    if (contact != null) {
                      return ContactDetailsScreen(contact: contact);
                    }
                    return const NetworkScreen();
                  },
                ),
              ],
            ),
            GoRoute(
              path: '/contacts',
              redirect: (context, state) {
                if (state.uri.path == '/contacts') {
                  return '/network';
                }
                return null;
              },
              builder: (context, state) => const NetworkScreen(),
              routes: [
                GoRoute(
                  path: 'add',
                  builder: (context, state) => const AddContactScreen(),
                ),
                GoRoute(
                  path: ':id',
                  builder: (context, state) {
                    final contact = state.extra as Contact?;
                    if (contact != null) {
                      return ContactDetailsScreen(contact: contact);
                    }
                    return const NetworkScreen();
                  },
                ),
              ],
            ),
            GoRoute(
              path: '/scan',
              builder: (context, state) {
                // Safely cast extra to Map
                final extra = state.extra is Map ? state.extra as Map : null;

                // Support batch mode with pre-selected destination
                final shelfId =
                    extra?['shelfId'] as String? ??
                    state.uri.queryParameters['shelfId'];
                final shelfName =
                    extra?['shelfName'] as String? ??
                    state.uri.queryParameters['shelfName'];

                // Handle collectionId (String)
                String? collectionId;
                if (extra != null && extra.containsKey('collectionId')) {
                  collectionId = extra['collectionId']?.toString();
                } else {
                  collectionId = state.uri.queryParameters['collectionId'];
                }

                final collectionName =
                    extra?['collectionName'] as String? ??
                    state.uri.queryParameters['collectionName'];

                // Batch mode check
                bool batch = false;
                if (extra != null && extra.containsKey('batch')) {
                  batch = extra['batch'] == true;
                } else {
                  batch = state.uri.queryParameters['batch'] == 'true';
                }

                return ScanScreen(
                  preSelectedShelfId: shelfId,
                  preSelectedShelfName: shelfName,
                  preSelectedCollectionId: collectionId,
                  preSelectedCollectionName: collectionName,
                  batchMode: batch,
                );
              },
            ),
            GoRoute(
              path: '/scan-qr',
              builder: (context, state) => const ScanQrScreen(),
            ),
            GoRoute(path: '/p2p', redirect: (context, state) => '/network'),
            GoRoute(
              path: '/requests',
              builder: (context, state) {
                final tab = state.uri.queryParameters['tab'];
                return LoansScreen(isTabView: false, initialTab: tab);
              },
            ),
            GoRoute(
              path: '/profile',
              builder: (context, state) {
                final action = state.uri.queryParameters['action'];
                return ProfileScreen(initialAction: action);
              },
              routes: [
                GoRoute(
                  path: 'link-device',
                  builder: (context, state) => const LinkDeviceScreen(),
                ),
              ],
            ),
            GoRoute(
              path: '/peers',
              builder: (context, state) =>
                  const NetworkScreen(initialIndex: 0), // Fallback to network
              routes: [
                GoRoute(
                  path: ':id/books',
                  builder: (context, state) {
                    final peer = state.extra as Map<String, dynamic>;
                    return PeerBookListScreen(
                      peerId: peer['id'],
                      peerName: peer['name'],
                      peerUrl: peer['url'],
                      hasRelayCredentials:
                          peer['hasRelayCredentials'] as bool? ?? false,
                      nodeId: peer['nodeId'] as String?,
                    );
                  },
                ),
                GoRoute(
                  path: ':id/details',
                  builder: (context, state) {
                    final relation = state.extra as LibraryRelation;
                    return PeerDetailScreen(relation: relation);
                  },
                ),
                GoRoute(
                  path: 'search',
                  builder: (context, state) => const SearchPeerScreen(),
                ),
              ],
            ),
            GoRoute(
              path: '/statistics',
              builder: (context, state) => const StatisticsScreen(),
            ),
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsScreen(),
              routes: [
                GoRoute(
                  path: 'migration-wizard',
                  builder: (context, state) => const MigrationWizardScreen(),
                ),
              ],
            ),
            GoRoute(
              path: '/directory',
              redirect: (context, state) {
                // DirectoryScreen absorbed into NetworkScreen Discover tab
                if (state.uri.path == '/directory') {
                  return '/network?tab=discover';
                }
                return null;
              },
              builder: (context, state) =>
                  const NetworkScreen(initialIndex: 1),
              routes: [
                GoRoute(
                  path: ':nodeId',
                  builder: (context, state) {
                    final nodeId = Uri.decodeComponent(
                      state.pathParameters['nodeId'] ?? '',
                    );
                    return LibraryCatalogScreen(nodeId: nodeId);
                  },
                ),
              ],
            ),
            GoRoute(
              path: '/notifications',
              builder: (context, state) => const NotificationsScreen(),
            ),
            GoRoute(
              path: '/help',
              builder: (context, state) => const HelpScreen(),
            ),
            GoRoute(
              path: '/network-search',
              builder: (context, state) => const NetworkSearchScreen(),
            ),
            GoRoute(
              path: '/shelves',
              pageBuilder: (context, state) {
                final tagFilter = state.uri.queryParameters['tag'];
                return NoTransitionPage(
                  child: LibraryScreen(
                    initialIndex: 1,
                    shelfTagFilter: tagFilter,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/feedback',
              builder: (context, state) => const FeedbackScreen(),
            ),
            GoRoute(
              path: '/collections',
              pageBuilder: (context, state) =>
                  const NoTransitionPage(child: LibraryScreen(initialIndex: 2)),
              routes: [
                GoRoute(
                  path: ':id',
                  builder: (context, state) {
                    final collection = state.extra as Collection;
                    return CollectionDetailScreen(collection: collection);
                  },
                ),
              ],
            ),
          ],
        ),
      ],
    );

    _initDeepLinks();
    _registerFlashMessages();
  }

  void _registerFlashMessages() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final flashProvider =
          Provider.of<FlashMessageProvider>(context, listen: false);

      // Flash A: Inline library name editor
      flashProvider.register(FlashMessageDefinition(
        key: 'flash_customize_library_name',
        textKey: 'flash_customize_library_name',
        icon: Icons.edit_outlined,
        condition: (ctx) {
          final tp = Provider.of<ThemeProvider>(ctx, listen: false);
          return tp.libraryName == 'My Library';
        },
        excludedRoutes: ['/settings', '/setup', '/onboarding', '/profile'],
        contentBuilder: (ctx, dismiss) => _FlashLibraryNameEditor(
          onDismiss: dismiss,
        ),
      ));

      // Flash B: Inline preset selector chips
      flashProvider.register(FlashMessageDefinition(
        key: 'flash_discover_presets',
        textKey: 'flash_discover_presets',
        icon: Icons.tune,
        condition: (_) => true,
        allowedRoutes: ['/books', '/dashboard', '/shelves', '/collections'],
        contentBuilder: (ctx, dismiss) => _FlashPresetSelector(
          onDismiss: dismiss,
        ),
      ));

      flashProvider.loadDismissedFlags();

      // Wire incoming peer detection to ephemeral flashes
      final pendingProvider =
          Provider.of<PendingPeersProvider>(context, listen: false);
      pendingProvider.onNewPeerDetected = (peer) {
        final isPending =
            (peer['connection_status'] as String?) == 'pending';
        flashProvider.addEphemeralPeer(EphemeralPeerFlash(
          peerId: peer['id'] as int,
          peerName: peer['name'] as String? ?? 'Unknown',
          peerUrl: peer['url'] as String?,
          nodeId: peer['library_uuid'] as String?,
          hasRelayCredentials:
              (peer['relay_url'] as String?)?.isNotEmpty == true &&
                  (peer['mailbox_id'] as String?)?.isNotEmpty == true,
          connectedAt: DateTime.now(),
          isPending: isPending,
        ));
      };
    });
  }

  void _initDeepLinks() {
    _appLinks = AppLinks();

    // app_links plugin (works on iOS/Android, not reliable on macOS)
    _appLinks.getInitialLink().then((uri) {
      debugPrint('Deep link: getInitialLink returned ${uri ?? "null"}');
      if (uri != null) _handleDeepLink(uri);
    });
    _linkSubscription = _appLinks.uriLinkStream.listen((uri) {
      debugPrint('Deep link: uriLinkStream received $uri');
      _handleDeepLink(uri);
    });

    // macOS: AppDelegate stores URL in UserDefaults via Apple Event handler.
    // Poll periodically because app_links doesn't work on macOS debug
    // and didChangeAppLifecycleState doesn't fire reliably on window focus.
    if (Platform.isMacOS) {
      _checkPendingDeepLink();
      _deepLinkTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        _checkPendingDeepLink();
      });
    }
  }

  Map<String, dynamic>? _parseInviteUri(Uri uri) {
    // Custom scheme: bibliogenius://invite?d=... (host=invite, path empty)
    // Hub HTTPS: https://<any-hub>/invite?d=... (path=/invite)
    final isInvite =
        (uri.scheme == 'bibliogenius' && uri.host == 'invite') ||
        (uri.path == '/invite' && uri.queryParameters.containsKey('d'));

    if (!isInvite) return null;

    final b64 = uri.queryParameters['d'];
    if (b64 == null) return null;

    try {
      final decoded = base64Url.decode(base64Url.normalize(b64));
      final jsonStr = utf8.decode(decoded);
      final raw = jsonDecode(jsonStr) as Map<String, dynamic>;
      return normalizeInvitePayload(raw);
    } catch (e) {
      debugPrint('Deep link decode error: $e');
      return null;
    }
  }

  Future<void> _checkPendingDeepLink() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final pendingLink = prefs.getString('pending_deep_link');
      if (pendingLink != null) {
        await prefs.remove('pending_deep_link');
        final uri = Uri.tryParse(pendingLink);
        if (uri != null) _handleDeepLink(uri);
      }
    } catch (_) {}
  }

  void _handleDeepLink(Uri uri) {
    debugPrint('Deep link: _handleDeepLink called with $uri');
    // Dedup: avoid processing the same link twice
    final key = uri.toString();
    if (_lastHandledDeepLink == key) {
      debugPrint('Deep link: skipped (duplicate)');
      return;
    }
    _lastHandledDeepLink = key;

    final payload = _parseInviteUri(uri);
    if (payload == null) {
      debugPrint('Deep link: _parseInviteUri returned null for $uri');
      return;
    }
    debugPrint('Deep link: parsed invite for "${payload['name']}"');

    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) {
        _router.go('/invite', extra: payload);
      }
    });
  }

  @override
  void dispose() {
    _deepLinkTimer?.cancel();
    _linkSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When app resumes from background, check if embedded HTTP server is still running
    if (state == AppLifecycleState.resumed) {
      // Check server health asynchronously (don't block the UI)
      ApiService.ensureServerRunning().then((available) {
        if (!available) {
          debugPrint('Server unavailable after app resume');
        }
      });

      // Push catalog to hub if books changed since last sync
      try {
        context.read<HubDirectoryProvider>().syncCatalogIfDirty();
      } catch (e) {
        debugPrint('Catalog sync on resume skipped: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp.router(
      // Force complete widget tree rebuild when theme changes to avoid
      // TextStyle.lerp errors with AnimatedDefaultTextStyle during transitions
      key: ValueKey(themeProvider.themeStyle),
      // Window title set by macOS CFBundleName - empty here to avoid
      // VoiceOver reading "BiblioGenius" multiple times in the accessibility tree
      title: '',
      debugShowCheckedModeBanner: false,
      theme: themeProvider.themeData,
      // Disable theme animation to prevent TextStyle.lerp errors when switching between
      // themes with different inherit values (e.g., Dark vs Default)
      themeAnimationDuration: Duration.zero,
      themeAnimationStyle: AnimationStyle.noAnimation,
      locale: themeProvider.locale,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: TranslationService.supportedLocales
          .map((code) => parseLocaleTag(code))
          .toList(),
      scrollBehavior: AppScrollBehavior(),
      builder: (context, child) {
        final appScale = Provider.of<ThemeProvider>(context).textScaleFactor;
        if (appScale == 1.0) return child!;
        final systemScale = MediaQuery.of(context).textScaler.scale(1.0);
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(appScale * systemScale),
          ),
          child: child!,
        );
      },
      routerConfig: _router,
    );
  }
}

/// Inline library name editor for Flash A.
/// Shows a compact TextField pre-filled with the current name.
/// An "OK" button appears when the text differs from the current value.
class _FlashLibraryNameEditor extends StatefulWidget {
  final VoidCallback onDismiss;
  const _FlashLibraryNameEditor({required this.onDismiss});

  @override
  State<_FlashLibraryNameEditor> createState() =>
      _FlashLibraryNameEditorState();
}

class _FlashLibraryNameEditorState extends State<_FlashLibraryNameEditor> {
  late final TextEditingController _controller;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    final tp = context.read<ThemeProvider>();
    _controller = TextEditingController(text: tp.libraryName);
    _controller.addListener(_onChanged);
  }

  void _onChanged() {
    final current = context.read<ThemeProvider>().libraryName;
    final dirty = _controller.text.trim() != current &&
        _controller.text.trim().isNotEmpty;
    if (dirty != _dirty) {
      setState(() => _dirty = dirty);
    }
  }

  Future<void> _save() async {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    try {
      // 1. Persist to SharedPreferences FIRST (frontend reads from here)
      final tp = context.read<ThemeProvider>();
      await tp.setLibraryName(name);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('ffi_library_name', name);
      if (!mounted) return;
      // 2. Persist to Rust DB via FFI (so HTTP /api/config also returns it)
      try {
        await FfiService().updateLibraryName(name);
      } catch (e) {
        debugPrint('FFI library name update failed (non-fatal): $e');
      }
      if (!mounted) return;
      // 3. Update hub profile with new name (if registered)
      try {
        final hubProvider = context.read<HubDirectoryProvider>();
        final hubConfig = hubProvider.config;
        if (hubConfig != null) {
          final bookCount = await FfiService().countBooks();
          await hubProvider.register(
            nodeId: hubConfig.nodeId,
            displayName: name,
            bookCount: bookCount,
            isListed: hubConfig.isListed,
            requiresApproval: hubConfig.requiresApproval,
            acceptFrom: hubConfig.acceptFrom,
            allowBorrowing: hubConfig.allowBorrowing,
          );
        }
      } catch (e) {
        debugPrint('Hub name update failed: $e');
      }
      if (!mounted) return;
      widget.onDismiss();
    } catch (e) {
      debugPrint('Flash name save failed: $e');
      if (!mounted) return;
      widget.onDismiss();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Flexible(
          child: Text(
            TranslationService.translate(
              context,
              'flash_customize_library_name',
            ),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 160,
          height: 34,
          child: TextField(
            controller: _controller,
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.onSurface,
            ),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: colorScheme.onSurface.withValues(alpha: 0.05),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(
                  color: colorScheme.primary.withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
              hintText: TranslationService.translate(
                context,
                'flash_library_name_hint',
              ),
              hintStyle: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ),
        ),
        if (_dirty) ...[
          const SizedBox(width: 6),
          SizedBox(
            height: 34,
            child: FilledButton.tonal(
              onPressed: _save,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                minimumSize: const Size(0, 34),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'OK',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Inline preset selector for Flash B.
/// Shows a compact text followed by wrapping chips with tooltips.
class _FlashPresetSelector extends StatelessWidget {
  final VoidCallback onDismiss;
  const _FlashPresetSelector({required this.onDismiss});

  static const _presets = [
    (key: 'reader', icon: Icons.menu_book),
    (key: 'librarian', icon: Icons.local_library),
    (key: 'bookseller', icon: Icons.storefront),
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          TranslationService.translate(context, 'flash_discover_presets'),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: colorScheme.onSurface,
          ),
        ),
        ..._presets.map((preset) {
          final label = TranslationService.translate(
            context,
            'preset_${preset.key}',
          );
          final legend = TranslationService.translate(
            context,
            'preset_${preset.key}_legend',
          );
          return Tooltip(
            message: legend,
            child: ActionChip(
              avatar: Icon(preset.icon, size: 15, color: colorScheme.primary),
              label: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurface,
                ),
              ),
              backgroundColor: colorScheme.primary.withValues(alpha: 0.06),
              side: BorderSide(
                color: colorScheme.primary.withValues(alpha: 0.15),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              onPressed: () async {
                final tp = context.read<ThemeProvider>();
                await tp.applyPreset(preset.key);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      TranslationService.translate(
                        context,
                        'preset_applied',
                      ),
                    ),
                  ),
                );
                onDismiss();
              },
            ),
          );
        }),
      ],
    );
  }
}
