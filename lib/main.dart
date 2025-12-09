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
import 'providers/theme_provider.dart';
import 'screens/login_screen.dart';
import 'screens/book_list_screen.dart';
import 'screens/add_book_screen.dart';
import 'screens/book_copies_screen.dart';
import 'screens/book_details_screen.dart';
import 'screens/edit_book_screen.dart';
import 'screens/contacts_screen.dart';
import 'screens/add_contact_screen.dart';
import 'screens/contact_details_screen.dart';
import 'models/book.dart';
import 'models/contact.dart';
import 'screens/scan_screen.dart';
import 'screens/p2p_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/setup_screen.dart';
import 'screens/external_search_screen.dart';
import 'screens/borrow_requests_screen.dart';
import 'screens/peer_list_screen.dart';
import 'screens/peer_book_list_screen.dart';
import 'screens/search_peer_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/statistics_screen.dart';
import 'screens/help_screen.dart';
 import 'screens/network_search_screen.dart';
import 'screens/onboarding_tour_screen.dart';
import 'services/wizard_service.dart';
import 'widgets/scaffold_with_nav.dart';

import 'dart:io';
import 'services/backend_service.dart';
import 'widgets/app_lifecycle_observer.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    debugPrint('No .env file found, using default configuration');
  }
  await TranslationService.loadFromCache();
  final themeProvider = ThemeProvider();
  
  // Initialize and start backend service (not on web)
  final backendService = BackendService();
  if (!kIsWeb) {
    try {
      await backendService.start();
    } catch (e) {
      debugPrint('Failed to start bundled backend: $e');
      // Continue anyway, maybe user has external backend
    }
  }
  
  try {
    await themeProvider.loadSettings();
  } catch (e, stackTrace) {
    debugPrint('Error loading settings: $e');
    debugPrint(stackTrace.toString());
    // Continue with default settings
  }

  runApp(MyApp(
    themeProvider: themeProvider,
    backendService: backendService,
  ));
}

class MyApp extends StatelessWidget {
  final ThemeProvider themeProvider;
  final BackendService backendService;

  const MyApp({
    super.key,
    required this.themeProvider,
    required this.backendService,
  });

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();
    
    // Determine base URL:
    // 1. If backend service is running, use its port
    // 2. Else check .env
    // 3. Fallback to localhost:8001
    String baseUrl;
    if (backendService.isRunning && backendService.port != null) {
      baseUrl = 'http://localhost:${backendService.port}';
    } else {
      baseUrl = dotenv.env['API_BASE_URL'] ?? 'http://localhost:8001';
    }
    
    final apiService = ApiService(authService, baseUrl: baseUrl);

    return AppLifecycleObserver(
      backendService: backendService,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
          Provider<AuthService>.value(value: authService),
          Provider<ApiService>.value(value: apiService),
          Provider<SyncService>(create: (_) => SyncService(apiService)),
          Provider<BackendService>.value(value: backendService),
        ],
        child: const AppRouter(),
      ),
    );
  }
}

class AppRouter extends StatelessWidget {
  const AppRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    final router = GoRouter(
      initialLocation: '/dashboard',
      refreshListenable: themeProvider,
      redirect: (context, state) async {
        final isSetup = themeProvider.isSetupComplete;
        final isSetupRoute = state.uri.path == '/setup';
        final isOnboardingRoute = state.uri.path == '/onboarding';

        if (!isSetup && !isSetupRoute) return '/setup';
        if (isSetup && isSetupRoute) {
          // After setup, check if should show onboarding tour
          final hasSeenTour = await WizardService.hasSeenOnboardingTour();
          if (!hasSeenTour && !isOnboardingRoute) {
            return '/onboarding';
          }
          return '/dashboard';
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
          path: '/search/external',
          builder: (context, state) => const ExternalSearchScreen(),
        ),
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
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
              builder: (context, state) => const BookListScreen(),
              routes: [
                GoRoute(
                  path: 'add',
                  builder: (context, state) {
                    final extra = state.extra as Map<String, dynamic>?;
                    final isbn = extra?['isbn'] as String?;
                    return AddBookScreen(isbn: isbn);
                  },
                ),
                GoRoute(
                  path: ':id',
                  builder: (context, state) {
                    final book = state.extra as Book;
                    return BookDetailsScreen(book: book);
                  },
                ),
                GoRoute(
                  path: ':id/edit',
                  builder: (context, state) {
                    final book = state.extra as Book;
                    return EditBookScreen(book: book);
                  },
                ),
                GoRoute(
                  path: ':id/copies',
                  builder: (context, state) {
                    final extra = state.extra as Map<String, dynamic>;
                    return BookCopiesScreen(
                      bookId: extra['bookId'],
                      bookTitle: extra['bookTitle'],
                    );
                  },
                ),
              ],
            ),
            GoRoute(
              path: '/contacts',
              builder: (context, state) => const ContactsScreen(),
              routes: [
                GoRoute(
                  path: 'add',
                  builder: (context, state) => const AddContactScreen(),
                ),
                GoRoute(
                  path: ':id',
                  builder: (context, state) {
                    final contact = state.extra as Contact;
                    return ContactDetailsScreen(contact: contact);
                  },
                ),
              ],
            ),
            GoRoute(
              path: '/scan',
              builder: (context, state) => const ScanScreen(),
            ),
            GoRoute(
              path: '/p2p',
              builder: (context, state) => const P2PScreen(),
            ),
            GoRoute(
              path: '/requests',
              builder: (context, state) => const BorrowRequestsScreen(),
            ),
            GoRoute(
              path: '/profile',
              builder: (context, state) => const ProfileScreen(),
            ),
            GoRoute(
              path: '/peers',
              builder: (context, state) => const PeerListScreen(),
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
              path: '/help',
              builder: (context, state) => const HelpScreen(),
            ),
            GoRoute(
              path: '/network-search',
              builder: (context, state) => const NetworkSearchScreen(),
            ),
          ],
        ),
      ],
    );

    return MaterialApp.router(
      title: 'Bibliotech',
      theme: themeProvider.themeData,
      locale: themeProvider.locale,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'), // English
        Locale('fr'), // French
        Locale('es'), // Spanish
        Locale('de'), // German
      ],
      routerConfig: router,
    );
  }
}
