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

### DRY - No Duplicated Styling

When multiple widgets share the same visual style (colors, decorations, paddings), extract shared values into file-level helpers (constants, functions, or a small utility class). Do NOT copy-paste `BoxDecoration`, color definitions, or icon badge patterns across widgets.

```dart
// GOOD: shared helpers at top of file
const _cardBg = Color(0xFFE8F6F5);
BoxDecoration _cardDecoration(bool isDark) => BoxDecoration(...);
Widget _iconBadge(ColorScheme cs, IconData icon) => Container(...);

// BAD: same decoration duplicated in 3 widgets
// Widget A: decoration: BoxDecoration(color: Color(0xFFE8F6F5), ...)
// Widget B: decoration: BoxDecoration(color: Color(0xFFE8F6F5), ...)
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
> 1. Add the translation key to `assets/i18n/en.po` and `assets/i18n/fr.po`
> 2. Use `TranslationService.translate()` in the widget

### Adding New Text (Required Steps)

```po
# Step 1: Add to assets/i18n/en.po
#. My New Feature
msgid "new_feature_title"
msgstr "My New Feature"

# Step 2: Add to assets/i18n/fr.po
#. My New Feature
msgid "new_feature_title"
msgstr "Ma nouvelle fonctionnalité"
```

```dart
// Step 3: Use in widget
Text(TranslationService.translate(context, 'new_feature_title'))
```

### Key Naming Convention

```
// Use snake_case with semantic prefixes
screen_name_element      // e.g., book_list_empty_state
action_verb              // e.g., save_changes, delete_book
error_context            // e.g., error_network, error_save_failed
label_field              // e.g., label_title, label_author
button_action            // e.g., button_confirm, button_cancel
dialog_purpose           // e.g., dialog_delete_confirm
```

### Validation

```bash
# Check translation completeness
dart tools/validate_po.dart

# Detailed missing keys
dart tools/validate_po.dart --verbose
```

### NEVER Do This

```dart
// BAD: Hardcoded string
Text('My Feature')

// BAD: Missing French translation — always add both en.po and fr.po entries

// BAD: Using translate without adding to .po files first
TranslationService.translate(context, 'undefined_key')  // Will return key as-is!
```

### Fallback Pattern (only when key might not exist yet)

```dart
Text(TranslationService.translate(context, 'key') ?? 'Default English')
```

---

## Accessibility (MANDATORY)

> **Target**: RGAA 4.1 level AA (WCAG 2.1 AA)
> **Roadmap**: `bibliogenius-docs/docs/research/accessibility-interoperability-roadmap.md`
> **Enforcement rules**: Root `CLAUDE.md` (Rules A1-A4)

### Screen Reader Support (VoiceOver / TalkBack)

Every new or modified widget that conveys information visually MUST also convey it to screen readers.

```dart
// REQUIRED: Book covers MUST have a semantic label
CachedNetworkImage(
  imageUrl: book.coverUrl ?? '',
  // ...
)
// Wrap with Semantics:
Semantics(
  image: true,
  label: '${book.title}, ${book.author}',
  child: CachedNetworkImage(/* ... */),
)

// REQUIRED: IconButton MUST have a translated tooltip
IconButton(
  icon: const Icon(Icons.delete),
  tooltip: TranslationService.translate(context, 'tooltip_delete'),
  onPressed: _onDelete,
)

// REQUIRED: Tappable cards MUST announce their content
Semantics(
  button: true,
  label: '${shelf.name}, ${shelf.bookCount} livres',
  child: InkWell(
    onTap: () => _openShelf(shelf),
    child: _ShelfCard(shelf: shelf),
  ),
)

// REQUIRED: Section headers MUST be marked
Semantics(
  header: true,
  child: Text('A lire', style: Theme.of(context).textTheme.titleLarge),
)

// REQUIRED: Decorative images MUST be excluded
Image.asset('assets/bg_pattern.png', excludeFromSemantics: true)
```

### What MUST Be Annotated (Checklist for New Screens)

```
- [ ] Every Image/CachedNetworkImage has semanticLabel or is excluded
- [ ] Every IconButton has a translated tooltip
- [ ] Every tappable card/tile is wrapped in Semantics(button: true, label: ...)
- [ ] Section titles use Semantics(header: true)
- [ ] Star ratings / progress bars have Semantics(label: 'Note : 3 sur 5')
- [ ] Empty states are already readable (Text widget - usually OK)
- [ ] Form fields have labelText or hintText in InputDecoration (usually OK)
```

### Color Contrast

```dart
// NEVER introduce a color pair without checking contrast ratio
// Minimum ratios (WCAG AA):
//   Normal text (< 18px):  4.5:1
//   Large text (>= 18px or 14px bold):  3:1
//   Icons / UI components:  3:1

// BAD: Light color on white
Text('Label', style: TextStyle(color: Color(0xFF6BB0A9)))  // ~2.5:1 on white

// GOOD: Checked color on white
Text('Label', style: TextStyle(color: Color(0xFF3D8B83)))  // >= 4.5:1 on white

// ALWAYS use Theme colors, which have been vetted:
Text('Label', style: Theme.of(context).textTheme.bodyMedium)
```

### Text Scaling

```dart
// The in-app text scaler MUST compose with the OS setting, not replace it.
// This is handled in main.dart - do NOT override MediaQuery.textScaler elsewhere.

// NEVER set a fixed fontSize that ignores scaling:
// BAD:
Text('Title', style: TextStyle(fontSize: 14))  // Won't scale with OS setting

// GOOD: Use theme text styles which respect the scaler
Text('Title', style: Theme.of(context).textTheme.bodyMedium)

// If you must use a custom fontSize, it will still scale via MediaQuery.
// Just don't wrap it in a local MediaQuery that overrides the scaler.
```

### NEVER Do This

```dart
// BAD: IconButton without tooltip
IconButton(icon: Icon(Icons.edit), onPressed: _onEdit)

// BAD: Image without semantic label
CachedNetworkImage(imageUrl: url)  // Screen reader says nothing

// BAD: Hardcoded English/French tooltip
IconButton(tooltip: 'Delete', ...)          // Not translated
IconButton(tooltip: 'Supprimer', ...)       // Not translated

// BAD: Color contrast not checked
Container(color: Color(0xFFB0D0CC), child: Text('light on light'))
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

### Single Responsibility & File Size

- **Files over 500 lines**: Extract reusable logic into dedicated files in `lib/utils/` or `lib/services/`.
- **Screens should stay focused on UI**: Network utilities, parsing, data transformation belong in `lib/utils/` or `lib/services/`, not in screen files.
- **`api_service.dart` (3700+ lines) is legacy debt**: When adding new functionality, prefer creating focused utility files rather than growing it further.

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
6. **Partial i18n**: IT/TR/BG `.po` files are ~70% translated. EN/FR/ES/DE are at 100%. See `dart tools/validate_po.dart`
7. **ApiService bloat**: 3,700+ lines with mixed concerns (FFI routing, retry, health check)
8. **HTTP local legacy**: Collections and gamification use `_getLocalDio()` detour instead of FFI direct. New features MUST use `FfiService` → `frb.*` (see root CLAUDE.md Rule F3)

---

## Performance Checklist

- [ ] Use `const` constructors wherever possible
- [ ] Check `mounted` after all async operations
- [ ] Dispose all controllers in `dispose()`
- [ ] Use `Consumer` instead of `Provider.of` for rebuilds
- [ ] Debounce search/filter inputs (300ms)
- [ ] Use `CachedNetworkImage` for remote images
- [ ] Avoid business logic in `build()` methods

## Accessibility Checklist

- [ ] Every `IconButton` has a translated `tooltip`
- [ ] Every `Image` / `CachedNetworkImage` has `semanticLabel` or `excludeFromSemantics: true`
- [ ] Tappable cards wrapped in `Semantics(button: true, label: ...)`
- [ ] Section headers wrapped in `Semantics(header: true)`
- [ ] No new hardcoded colors without contrast ratio check (>= 4.5:1 normal text)
- [ ] Star ratings / sliders / progress have `Semantics(label: ...)` with current value
- [ ] No `MediaQuery` override that replaces the system text scaler
