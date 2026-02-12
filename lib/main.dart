import 'dart:io';
import 'config/platform_init.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'services/auth_service.dart';
import 'services/api_service.dart';
import 'services/sync_service.dart';
import 'services/translation_service.dart';
import 'services/mdns_service.dart';
import 'services/ffi_service.dart';
import 'utils/app_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/theme_provider.dart';
import 'providers/book_refresh_notifier.dart';
import 'audio/audio_module.dart'; // Audio module (decoupled)
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
import 'screens/profile_screen.dart';
import 'screens/setup_screen.dart';

import 'screens/peer_book_list_screen.dart';
import 'screens/shelf_management_screen.dart';
import 'screens/search_peer_screen.dart';
import 'screens/genie_chat_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/statistics_screen.dart';
import 'screens/help_screen.dart';
import 'screens/network_search_screen.dart';
import 'screens/onboarding_tour_screen.dart';
import 'screens/network_screen.dart';
import 'screens/library_screen.dart';
import 'screens/feedback_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/migration_wizard_screen.dart';

import 'screens/link_device_screen.dart';
import 'screens/external_search_screen.dart';

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

    // Auto-initialize mDNS for local network discovery (Native Bonjour)
    // This makes the app discoverable on the local WiFi network
    // Only start if user has enabled network discovery in settings
    if (themeProvider.networkDiscoveryEnabled) {
      try {
        final authService = AuthService();
        final libraryUuid = await authService.getOrCreateLibraryUuid();
        // Include device hostname for network disambiguation
        final baseName = themeProvider.libraryName.isNotEmpty
            ? themeProvider.libraryName
            : 'BiblioGenius Library';
        final deviceName = Platform.localHostname;
        final libraryName = deviceName.isNotEmpty
            ? '$baseName ($deviceName)'
            : baseName;
        await MdnsService.startAnnouncing(
          libraryName,
          httpPort,
          libraryId: libraryUuid,
        );
        await MdnsService.startDiscovery();
      } catch (mdnsError) {
        debugPrint('mDNS: Init failed (non-blocking): $mdnsError');
      }
    } else {
      debugPrint('mDNS: Disabled by user preference');
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
          value: CollectionRepositoryImpl(apiService),
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);

    _router = GoRouter(
      initialLocation: '/books',
      refreshListenable: themeProvider,
      redirect: (context, state) async {
        final isOnboardingRoute = state.uri.path == '/onboarding';
        final isLoginRoute = state.uri.path == '/login';
        final authService = Provider.of<AuthService>(context, listen: false);

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
        final isLoggedIn = await authService.isLoggedIn();

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
          path: '/genie-chat',
          builder: (context, state) => const GenieChatScreen(),
        ),
        GoRoute(
          path: '/shelves-management',
          builder: (context, state) => const ShelfManagementScreen(),
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
              builder: (context, state) {
                // Support query parameter for initial loans tab: ?tab=lent or ?tab=borrowed
                final loansTab = state.uri.queryParameters['tab'];
                // If a loans tab is specified, go to Loans tab (index 1)
                final initialIndex = loansTab != null ? 1 : 0;
                return NetworkScreen(
                  initialIndex: initialIndex,
                  initialLoansTab: loansTab,
                );
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
            GoRoute(path: '/p2p', redirect: (context, state) => '/network'),
            GoRoute(
              path: '/requests',
              builder: (context, state) => const NetworkScreen(initialIndex: 1),
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
                    );
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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When app resumes from background, check if embedded HTTP server is still running
    if (state == AppLifecycleState.resumed) {
      debugPrint('📱 App resumed from background, checking server health...');
      // Check server health asynchronously (don't block the UI)
      ApiService.ensureServerRunning().then((available) {
        if (available) {
          debugPrint('✅ Server is healthy after app resume');
        } else {
          debugPrint('⚠️ Server unavailable after app resume');
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp.router(
      // Force complete widget tree rebuild when theme changes to avoid
      // TextStyle.lerp errors with AnimatedDefaultTextStyle during transitions
      key: ValueKey(themeProvider.themeStyle),
      title: 'BiblioGenius',
      debugShowCheckedModeBanner: false,
      theme: themeProvider.themeData,
      // Disable theme animation to prevent TextStyle.lerp errors when switching between
      // themes with different inherit values (e.g., Sorbonne vs Default)
      themeAnimationDuration: Duration.zero,
      themeAnimationStyle: AnimationStyle.noAnimation,
      locale: themeProvider.locale,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('fr'),
        Locale('es'),
        Locale('de'),
      ],
      scrollBehavior: AppScrollBehavior(),
      builder: (context, child) {
        return child!;
      },
      routerConfig: _router,
    );
  }
}
