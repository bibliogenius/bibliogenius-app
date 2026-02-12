# BiblioGenius — Flutter Frontend Conventions

> **SDK**: Flutter 3.x | **State**: Provider | **Navigation**: GoRouter | **HTTP**: Dio
>
> Architecture enforcement rules are in the root `CLAUDE.md` (section ARCHITECTURE ENFORCEMENT).
> This file covers Flutter-specific conventions, patterns, and best practices.

---

## Project Structure

```
lib/
├── screens/           # Full-page widgets (one per file)
├── widgets/           # Reusable UI components
├── data/
│   ├── repositories/       # Abstract repository interfaces
│   └── repositories_impl/  # Concrete implementations
├── services/          # API, Auth, Sync, Translation
├── providers/         # ChangeNotifier state managers
├── models/            # Data classes
├── themes/            # Theme registry + implementations
├── audio/             # Audio module (optional feature)
├── utils/             # Constants, helpers, validators
├── config/            # Platform-specific initialization
└── src/rust/          # FFI bindings (generated)
```

---

## State Management (Provider)

### Service Injection

```dart
// main.dart - Inject services at root
MultiProvider(
  providers: [
    Provider<ApiService>.value(value: apiService),
    ChangeNotifierProvider(create: (_) => ThemeProvider()),
    ChangeNotifierProvider(create: (_) => AudioProvider()),
  ],
  child: App(),
)
```

### Accessing Services

```dart
// PREFERRED: Use context.read for one-time access (callbacks, init)
final api = context.read<ApiService>();

// PREFERRED: Use Consumer for reactive rebuilds
Consumer<ThemeProvider>(
  builder: (context, theme, child) => Text(theme.currentTheme),
)

// AVOID: Provider.of with listen: false in build methods
// Only use in callbacks or initState
```

### Custom Providers

```dart
class BookListProvider extends ChangeNotifier {
  List<Book> _books = [];
  bool _isLoading = false;
  String? _error;

  List<Book> get books => _books;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> fetchBooks() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _books = await _apiService.getBooks();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
```

---

## Widget Patterns

### Screen Structure

```dart
class BookDetailScreen extends StatefulWidget {
  final int bookId;

  const BookDetailScreen({super.key, required this.bookId});

  @override
  State<BookDetailScreen> createState() => _BookDetailScreenState();
}

class _BookDetailScreenState extends State<BookDetailScreen> {
  late final ApiService _api;
  Book? _book;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _api = context.read<ApiService>();
    _loadBook();
  }

  Future<void> _loadBook() async {
    try {
      final book = await _api.getBook(widget.bookId);
      if (mounted) setState(() => _book = book);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const LoadingIndicator();
    if (_book == null) return const ErrorWidget();
    return _buildContent();
  }

  Widget _buildContent() {
    // Build UI with _book data
  }
}
```

### Widget Decomposition Rules

```dart
// Rule: Extract widgets when they exceed ~100 lines or are reusable

// GOOD: Extracted to separate widget
class BookCoverCard extends StatelessWidget {
  final Book book;
  const BookCoverCard({super.key, required this.book});
  // ...
}

// GOOD: Private widget for screen-specific components
class _FilterBar extends StatelessWidget {
  // Only used within this screen file
}

// AVOID: 500+ line build methods
// AVOID: Business logic in widgets
```

### Const Constructors

```dart
// ALWAYS use const when possible
const SizedBox(height: 16),
const Icon(Icons.book),
const EdgeInsets.all(16),

// Widget declarations
class MyWidget extends StatelessWidget {
  const MyWidget({super.key});  // Always const constructor
}
```

---

## Async & Mounted Checks

```dart
// ALWAYS check mounted after async operations
Future<void> _fetchData() async {
  setState(() => _isLoading = true);

  try {
    final data = await _api.fetchData();
    if (!mounted) return;  // Widget may have been disposed
    setState(() => _data = data);
  } catch (e) {
    if (!mounted) return;
    _showError(e.toString());
  } finally {
    if (!mounted) return;
    setState(() => _isLoading = false);
  }
}
```

---

## Controller Management

```dart
class _MyScreenState extends State<MyScreen> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _debounce;

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _debounce?.cancel();
    super.dispose();
  }
}
```

---

## Debouncing

```dart
// Use for search inputs to avoid excessive API calls
void _onSearchChanged(String query) {
  _debounce?.cancel();
  _debounce = Timer(const Duration(milliseconds: 300), () {
    _performSearch(query);
  });
}
```

---

## Navigation (GoRouter)

### Route Definition

```dart
GoRouter(
  routes: [
    GoRoute(
      path: '/books',
      builder: (context, state) => const BookListScreen(),
      routes: [
        GoRoute(
          path: ':id',
          builder: (context, state) {
            final id = int.parse(state.pathParameters['id']!);
            return BookDetailScreen(bookId: id);
          },
        ),
      ],
    ),
  ],
)
```

### Navigation

```dart
// Named navigation
context.go('/books/123');

// With query parameters
context.go('/books?tag=fiction&sort=title');

// Passing complex objects via extra (avoid when possible)
context.go('/books/edit', extra: book);
```

---

## Theming

### Design Tokens (AppDesign)

```dart
// Use centralized design tokens
class AppDesign {
  static const spacing = 16.0;
  static const borderRadius = BorderRadius.all(Radius.circular(12));

  static BoxDecoration cardDecoration(BuildContext context) {
    return BoxDecoration(
      color: Theme.of(context).cardColor,
      borderRadius: borderRadius,
      boxShadow: [/* ... */],
    );
  }
}

// Usage
Container(
  padding: const EdgeInsets.all(AppDesign.spacing),
  decoration: AppDesign.cardDecoration(context),
)
```

### Theme-Aware Colors

```dart
// GOOD: Use theme colors
final color = Theme.of(context).colorScheme.primary;

// GOOD: Use design system
final gradient = AppDesign.pageGradientForTheme(themeStyle);

// AVOID: Hardcoded colors
final color = Color(0xFF123456);  // Bad
```

---

## Image Caching

```dart
// Use CachedNetworkImage for all remote images
CachedNetworkImage(
  imageUrl: book.coverUrl ?? '',
  placeholder: (context, url) => const BookPlaceholder(),
  errorWidget: (context, url, error) => const BookPlaceholder(),
  fit: BoxFit.cover,
)
```

---

## Internationalization (MANDATORY)

> **CRITICAL RULE**: When adding ANY user-facing text, you MUST:
>
> 1. Add the translation key to `_localizedValues` in `translation_service.dart`
> 2. Add translations for BOTH `'en'` AND `'fr'` locales
> 3. Use `TranslationService.translate()` in the widget

### Adding New Text (Required Steps)

```dart
// Step 1: Add to translation_service.dart in _localizedValues
static final Map<String, Map<String, String>> _localizedValues = {
  'en': {
    // ... existing keys ...
    'new_feature_title': 'My New Feature',  // ADD THIS
  },
  'fr': {
    // ... existing keys ...
    'new_feature_title': 'Ma nouvelle fonctionnalité',  // AND THIS
  },
};

// Step 2: Use in widget
Text(TranslationService.translate(context, 'new_feature_title'))
```

### Key Naming Convention

```dart
// Use snake_case with semantic prefixes
'screen_name_element'      // e.g., 'book_list_empty_state'
'action_verb'              // e.g., 'save_changes', 'delete_book'
'error_context'            // e.g., 'error_network', 'error_save_failed'
'label_field'              // e.g., 'label_title', 'label_author'
'button_action'            // e.g., 'button_confirm', 'button_cancel'
'dialog_purpose'           // e.g., 'dialog_delete_confirm'
```

### NEVER Do This

```dart
// BAD: Hardcoded string
Text('My Feature')

// BAD: Missing French translation
'en': { 'key': 'Value' }  // Where is 'fr'?

// BAD: Using translate without adding to _localizedValues first
TranslationService.translate(context, 'undefined_key')  // Will return null!
```

### Fallback Pattern (only when key might not exist yet)

```dart
Text(TranslationService.translate(context, 'key') ?? 'Default English')
```

---

## Error Handling

```dart
// Consistent error display
void _showError(String message) {
  if (!mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: Theme.of(context).colorScheme.error,
    ),
  );
}

// Try-catch pattern for async operations
try {
  await _api.saveBook(book);
  if (mounted) context.pop();
} catch (e) {
  _showError(TranslationService.translate(context, 'save_error') ?? 'Error');
}
```

---

## Code Style

### Dart Naming

- Classes: `PascalCase` (e.g., `BookListScreen`, `ApiService`)
- Methods/variables: `camelCase` (e.g., `fetchBooks`, `isLoading`)
- Private members: Leading `_` (e.g., `_books`, `_isLoading`)
- Constants: `camelCase` (e.g., `defaultPadding`)
- Files: `snake_case` (e.g., `book_list_screen.dart`)

### Dart Imports

```dart
// Order: dart, flutter, packages, local
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../services/api_service.dart';
import '../models/book.dart';
```

---

## Post-Development Checks

**MANDATORY**: After completing any Flutter development work:

```bash
flutter analyze lib/
```

Must pass before considering work complete.

---

## Version Bump — Non-Regression Testing Policy

When incrementing the version in `pubspec.yaml`, run the appropriate level of non-regression tests from `QA_NON_REGRESSION.md`:

| Version Change | Example | Required Tests |
|----------------|---------|----------------|
| **Patch** (`x.y.Z`) | 0.7.0 → 0.7.1 | Pre-release checklist (cargo fmt/clippy/test, flutter analyze/build) + P0 tests only + tests related to the specific fix |
| **Minor** (`x.Y.0`) | 0.7.x → 0.8.0 | Full TNR Part A (all priorities, all platforms) |
| **Major** (`X.0.0`) | 0.x → 1.0.0 | Full TNR Part A + all Part B detailed scenarios (data integrity, security, resilience, performance) |

---

## Known Technical Debt

> These patterns exist but should be refactored:

1. **Large screen files**: BookListScreen has 2,500+ lines (should be decomposed)
2. **Inconsistent state access**: Mix of `Provider.of` and `Consumer`
3. **Missing debounce**: Search/filter operations lack debouncing in some screens
4. **Edit deep linking broken**: EditBookScreen throws if navigated directly
5. **Unbounded audio cache**: `AudioProvider._audioCache` can grow indefinitely
6. **Incomplete i18n**: Spanish/German listed but not implemented
7. **ApiService bloat**: 3,700+ lines with mixed concerns (FFI routing, retry, health check)

---

## Performance Checklist

- [ ] Use `const` constructors wherever possible
- [ ] Check `mounted` after all async operations
- [ ] Dispose all controllers in `dispose()`
- [ ] Use `Consumer` instead of `Provider.of` for rebuilds
- [ ] Debounce search/filter inputs (300ms)
- [ ] Use `CachedNetworkImage` for remote images
- [ ] Avoid business logic in `build()` methods
