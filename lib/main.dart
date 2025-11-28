import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'services/auth_service.dart';
import 'services/api_service.dart';
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

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();
    final apiService = ApiService(authService);

    return MultiProvider(
      providers: [
        Provider<AuthService>.value(value: authService),
        Provider<ApiService>.value(value: apiService),
      ],
      child: const AppRouter(),
    );
  }
}

class AppRouter extends StatelessWidget {
  const AppRouter({super.key});

  @override
  Widget build(BuildContext context) {
    final router = GoRouter(
      initialLocation: '/login',
      routes: [
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
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
        GoRoute(path: '/scan', builder: (context, state) => const ScanScreen()),
        GoRoute(path: '/p2p', builder: (context, state) => const P2PScreen()),
        GoRoute(
          path: '/profile',
          builder: (context, state) => const ProfileScreen(),
        ),
      ],
    );

    return MaterialApp.router(
      title: 'Bibliotech',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      routerConfig: router,
    );
  }
}
