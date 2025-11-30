import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'services/auth_service.dart';
import 'services/api_service.dart';
import 'services/sync_service.dart';
import 'providers/theme_provider.dart';
import 'screens/login_screen.dart';
import 'screens/book_list_screen.dart';
import 'screens/add_book_screen.dart';
import 'screens/book_copies_screen.dart';
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
import 'screens/dashboard_screen.dart';
import 'screens/statistics_screen.dart';
import 'widgets/scaffold_with_nav.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final themeProvider = ThemeProvider();
  
  try {
    await themeProvider.loadSettings();
  } catch (e, stackTrace) {
    debugPrint('Error loading settings: $e');
    debugPrint(stackTrace.toString());
    // Continue with default settings
  }

  runApp(MyApp(themeProvider: themeProvider));
}

class MyApp extends StatelessWidget {
  final ThemeProvider themeProvider;

  const MyApp({super.key, required this.themeProvider});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();
    const baseUrl = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://localhost:8001',
    );
    final apiService = ApiService(authService, baseUrl: baseUrl);

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
        Provider<AuthService>.value(value: authService),
        Provider<ApiService>.value(value: apiService),
        Provider<SyncService>(create: (_) => SyncService(apiService)),
      ],
      child: const AppRouter(),
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
      redirect: (context, state) {
        final isSetup = themeProvider.isSetupComplete;
        final isSetupRoute = state.uri.path == '/setup';

        if (!isSetup && !isSetupRoute) return '/setup';
        if (isSetup && isSetupRoute) return '/dashboard';

        return null;
      },
      routes: [
        GoRoute(
          path: '/setup',
          builder: (context, state) => const SetupScreen(),
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
              ],
            ),
            GoRoute(
              path: '/statistics',
              builder: (context, state) => const StatisticsScreen(),
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
