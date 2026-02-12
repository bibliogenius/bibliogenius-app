import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:go_router/go_router.dart';
import '../widgets/genie_app_bar.dart';
import '../widgets/contextual_help_sheet.dart';
import '../widgets/streak_celebration.dart';
import '../data/repositories/book_repository.dart';
import '../data/repositories/contact_repository.dart';
import '../data/repositories/loan_repository.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';
import '../models/book.dart';
// import 'genie_chat_screen.dart'; // Removed as we use route string
import '../providers/theme_provider.dart';

import '../widgets/premium_book_card.dart';
import '../widgets/premium_empty_state.dart';

import '../services/quote_service.dart';
import '../models/quote.dart';
import '../theme/app_design.dart';
import '../services/backup_reminder_service.dart';
import 'statistics_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  Quote? _dailyQuote;
  String? _userName;
  String? _lastLocale;
  final Map<String, dynamic> _stats = {};

  // New List categorization
  List<Book> _readingBooks = [];
  List<Book> _toReadBooks = [];
  List<Book> _recentBooks = [];
  List<Book> _allBooks = [];

  bool _quoteExpanded = false;

  final GlobalKey _statsKey = GlobalKey(debugLabel: 'dashboard_stats');
  final GlobalKey _menuKey = GlobalKey(debugLabel: 'dashboard_menu');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchDashboardData();
    Future.delayed(const Duration(seconds: 1), _checkWizard);
    _checkBackupReminder();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final themeProvider = Provider.of<ThemeProvider>(context);
    final currentLocale = themeProvider.locale.languageCode;
    if (_lastLocale != null && _lastLocale != currentLocale) {
      _lastLocale = currentLocale;
      _fetchQuote();
    }
  }

  void _checkBackupReminder() async {
    if (await BackupReminderService.shouldShowReminder()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          BackupReminderService.showReminderDialog(context);
        }
      });
    }
  }

  void _checkWizard() async {
    return;
  }

  Future<void> _fetchDashboardData() async {
    final bookRepo = Provider.of<BookRepository>(context, listen: false);
    final api = Provider.of<ApiService>(context, listen: false);
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    TranslationService.fetchTranslations(context);

    setState(() => _isLoading = true);

    try {
      try {
        print('Dashboard: Fetching books...');
        var books = await bookRepo.getBooks();
        print('Dashboard: Books fetched. Count: ${books.length}');

        final configRes = await api.getLibraryConfig();
        if (configRes.statusCode == 200) {
          final config = configRes.data;
          if (config['show_borrowed_books'] != true) {
            books = books.where((b) => b.readingStatus != 'borrowed').toList();
          }
          final name = config['library_name'] ?? config['name'];
          if (name != null) {
            themeProvider.setLibraryName(name);
          }
        }

        if (mounted) {
          setState(() {
            _allBooks = books;
            _stats['total_books'] = books.length;

            // Sort by recently added (ID desc)
            final sortedBooks = List<Book>.from(books);
            sortedBooks.sort((a, b) => (b.id ?? 0).compareTo(a.id ?? 0));
            _recentBooks = sortedBooks
                .where((b) => b.readingStatus != 'to_read')
                .take(10)
                .toList();

            // En cours de lecture
            _readingBooks = books
                .where((b) => b.readingStatus == 'reading')
                .toList();
            // Sort reading by most recently added/updated if possible, or just ID
            _readingBooks.sort((a, b) => (b.id ?? 0).compareTo(a.id ?? 0));

            // À lire
            _toReadBooks = books
                .where((b) => b.readingStatus == 'to_read')
                .toList();
            _toReadBooks.sort((a, b) => (b.id ?? 0).compareTo(a.id ?? 0));
          });
        }
      } catch (e) {
        debugPrint('Error fetching books: $e');
      }

      try {
        final contactRepo = Provider.of<ContactRepository>(context, listen: false);
        final contacts = await contactRepo.getContacts();
        if (mounted) {
          setState(() {
            _stats['contacts_count'] = contacts.length;
          });
        }
      } catch (e) {
        debugPrint('Error fetching contacts: $e');
      }

      try {
        final statusRes = await api.getUserStatus();
        if (statusRes.statusCode == 200) {
          final statusData = statusRes.data;
          if (mounted) {
            setState(() {
              _userName = statusData['name'];
            });

            if (themeProvider.gamificationEnabled) {
              final streakData = statusData['streak'] as Map<String, dynamic>?;
              if (streakData != null) {
                final currentStreak = streakData['current'] as int? ?? 0;
                final longestStreak = streakData['longest'] as int? ?? 0;
                Future.delayed(const Duration(milliseconds: 800), () {
                  if (mounted) {
                    StreakCelebration.showIfNeeded(
                      context,
                      currentStreak: currentStreak,
                      longestStreak: longestStreak,
                    );
                  }
                });
              }
            }
          }
        }

        final loanRepo = Provider.of<LoanRepository>(context, listen: false);
        final loans = await loanRepo.getLoans(status: 'active');
        if (mounted) {
          setState(() {
            _stats['active_loans'] = loans.length;
          });
        }

        if (themeProvider.canBorrowBooks) {
          try {
            final borrowed = await loanRepo.getBorrowedCopies();
            if (mounted) {
              setState(() {
                _stats['borrowed_count'] = borrowed.length;
              });
            }
          } catch (e) {
            debugPrint('Could not fetch borrowed copies: $e');
          }
        }

        final configRes = await api.getLibraryConfig();
        if (mounted) {
          setState(() {
            final config = configRes.data;
            final name = config?['library_name'] ?? config?['name'];
            if (name != null) {
              themeProvider.setLibraryName(name);
            }
            final profileType = config?['profile_type'];
            if (profileType != null) {
              themeProvider.setProfileType(profileType);
            }
          });
        }
      } catch (e) {
        debugPrint('Error fetching user status: $e');
      }

      if (themeProvider.quotesEnabled) {
        await _fetchQuote();
      }

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching dashboard data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _fetchQuote() async {
    try {
      final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
      // Use recent books for context
      final quoteService = QuoteService();
      final quote = await quoteService.fetchRandomQuote(
        _recentBooks,
        locale: themeProvider.locale.languageCode,
      );

      if (mounted) {
        setState(() {
          _dailyQuote = quote;
        });
      }
    } catch (e) {
      debugPrint('Error fetching quote: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isKid = themeProvider.isKid;
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 600;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GenieAppBar(
        title: 'BiblioGenius',
        leading: isWide
            ? null
            : IconButton(
                key: _menuKey,
                icon: const Icon(Icons.menu, color: Colors.white),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
        automaticallyImplyLeading: false,
        showQuickActions: false,
        actions: [
          ContextualHelpIconButton(
            titleKey: 'help_ctx_dashboard_title',
            contentKey: 'help_ctx_dashboard_content',
            tips: const [
              HelpTip(
                icon: Icons.insights,
                color: Colors.blue,
                titleKey: 'help_ctx_dashboard_tip_stats',
                descriptionKey: 'help_ctx_dashboard_tip_stats_desc',
              ),
              HelpTip(
                icon: Icons.menu_book,
                color: Colors.green,
                titleKey: 'help_ctx_dashboard_tip_reading',
                descriptionKey: 'help_ctx_dashboard_tip_reading_desc',
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 4,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withValues(alpha: 0.6),
          isScrollable: !isWide,
          tabAlignment: !isWide ? TabAlignment.start : TabAlignment.fill,
          labelStyle: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: isWide ? 16 : 15,
            letterSpacing: 0.5,
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          tabs: [
            Tab(
              icon: const Icon(Icons.dashboard_rounded, size: 22),
              text: TranslationService.translate(context, 'dashboard'),
            ),
            Tab(
              icon: const Icon(Icons.insights_rounded, size: 22),
              text: TranslationService.translate(context, 'nav_statistics'),
            ),
          ],
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: AppDesign.pageGradientForTheme(
            Provider.of<ThemeProvider>(context).themeStyle,
          ),
        ),
        child: SafeArea(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildDashboardTab(context, isWide, themeProvider, isKid),
              const StatisticsContent(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardTab(
    BuildContext context,
    bool isWide,
    ThemeProvider themeProvider,
    bool isKid,
  ) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      );
    }

    // EMPTY STATE Check
    if (_allBooks.isEmpty) {
      // Import PremiumEmptyState if not already imported, or use a basic one if not available.
      // Assuming PremiumEmptyState is available in the project structure at widgets/premium_empty_state.dart
      // If imports are missing, I'll need to add them, but I'm editing the state class here.
      // Since I see it used in other files in context, it should be importable.
      // NOTE: I need to ensure the import exists at the top of the file!
      return Center(
        child: PremiumEmptyState(
          message: TranslationService.translate(context, 'empty_library_title'),
          description: TranslationService.translate(
            context,
            'empty_library_subtitle',
          ),
          icon: Icons.library_books_outlined,
          buttonLabel: TranslationService.translate(context, 'scan_first_book'),
          onAction: () => context.push('/books/add'),
          colorOverride: Colors.white,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchDashboardData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(
          top: 24,
          left: isWide ? 32 : 16,
          right: isWide ? 32 : 16,
          bottom: 16,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isWide ? 900 : double.infinity,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (themeProvider.quotesEnabled) ...[
                  _buildHeader(context),
                  const SizedBox(height: 24),
                ],

                // Stats Row
                LayoutBuilder(
                  key: _statsKey,
                  builder: (context, constraints) {
                    final statCards = <Widget>[
                      _buildStatCard(
                        context,
                        TranslationService.translate(context, 'my_books'),
                        (_stats['total_books'] ?? 0).toString(),
                        Icons.menu_book,
                        onTap: () => context.push('/books'),
                      ),
                      _buildStatCard(
                        context,
                        TranslationService.translate(context, 'lent_status'),
                        (_stats['active_loans'] ?? 0).toString(),
                        Icons.arrow_upward,
                        isAccent: true,
                        onTap: () => context.push('/network?tab=lent'),
                      ),
                      if (!themeProvider.isLibrarian)
                        _buildStatCard(
                          context,
                          TranslationService.translate(
                            context,
                            'borrowed_status',
                          ),
                          (_stats['borrowed_count'] ?? 0).toString(),
                          Icons.arrow_downward,
                          onTap: () => context.push('/network?tab=borrowed'),
                        ),
                      if (!isKid)
                        _buildStatCard(
                          context,
                          themeProvider.isLibrarian
                              ? TranslationService.translate(
                                  context,
                                  'borrowers',
                                )
                              : TranslationService.translate(
                                  context,
                                  'contacts',
                                ),
                          (_stats['contacts_count'] ?? 0).toString(),
                          Icons.people,
                          onTap: () => context.push('/network'),
                        ),
                    ];

                    if (constraints.maxWidth < 400 && statCards.length > 2) {
                      final firstRow = statCards.take(2).toList();
                      final secondRow = statCards.skip(2).toList();
                      return Column(
                        children: [
                          Row(
                            children:
                                firstRow
                                    .expand(
                                      (w) => [
                                        Expanded(child: w),
                                        const SizedBox(width: 12),
                                      ],
                                    )
                                    .toList()
                                  ..removeLast(),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children:
                                secondRow
                                    .expand(
                                      (w) => [
                                        Expanded(child: w),
                                        const SizedBox(width: 12),
                                      ],
                                    )
                                    .toList()
                                  ..removeLast(),
                          ),
                        ],
                      );
                    }
                    return Row(
                      children:
                          statCards
                              .expand(
                                (w) => [
                                  Expanded(child: w),
                                  const SizedBox(width: 12),
                                ],
                              )
                              .toList()
                            ..removeLast(),
                    );
                  },
                ),

                const SizedBox(height: 24),

                // Main Content
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. En cours de lecture (Currently Reading)
                    if (_readingBooks.isNotEmpty)
                      _buildBookListSection(
                        context,
                        title: TranslationService.translate(
                          context,
                          'currently_reading',
                        ),
                        books: _readingBooks,
                        emptyMessage:
                            '', // Should not show if empty check passes
                        seeAllLabel: TranslationService.translate(
                          context,
                          'see_all_reading',
                        ),
                        seeAllRoute: '/books?status=reading',
                        showStatus: false,
                      ),

                    // 2. À lire (To Read)
                    if (_toReadBooks.isNotEmpty)
                      _buildBookListSection(
                        context,
                        title: TranslationService.translate(
                          context,
                          'reading_status_to_read',
                        ),
                        books: _toReadBooks,
                        emptyMessage: '',
                        seeAllLabel: TranslationService.translate(
                          context,
                          'see_all_to_read',
                        ),
                        seeAllRoute: '/books?status=to_read',
                        showStatus: false,
                      ),

                    // 3. Livres récents (Recent Books)
                    if (_recentBooks.isNotEmpty)
                      _buildBookListSection(
                        context,
                        title: TranslationService.translate(
                          context,
                          'recent_books',
                        ),
                        books: _recentBooks,
                        emptyMessage: TranslationService.translate(
                          context,
                          'no_recent_books',
                        ),
                        // No specific label requested, just generic link to library usually,
                        // but user said "for recent books it's just a link to the library"
                        seeAllLabel: TranslationService.translate(
                          context,
                          'see_all_books',
                        ),
                        seeAllRoute: '/books', // Just library
                        showStatus: false,
                      ),

                    const SizedBox(height: 24),
                    if (!isKid)
                      Center(
                        child: ScaleOnTap(
                          child: TextButton.icon(
                            onPressed: () => context.push('/statistics'),
                            icon: Icon(
                              Icons.insights,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                            label: Text(
                              TranslationService.translate(
                                context,
                                'view_insights',
                              ),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 16,
                              ),
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.05),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                                side: BorderSide(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.1),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBookListSection(
    BuildContext context, {
    required String title,
    required List<Book> books,
    required String emptyMessage,
    required String seeAllLabel,
    required String seeAllRoute,
    bool showStatus = true,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(context, title),
        const SizedBox(height: 16),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppDesign.radiusXLarge),
            boxShadow: AppDesign.cardShadow,
          ),
          child: Column(
            children: [
              // Accent gradient bar at top
              Container(
                height: 3,
                decoration: BoxDecoration(
                  gradient: AppDesign.sectionAccentGradient(
                    Provider.of<ThemeProvider>(context, listen: false).themeStyle,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
              // Show max 10 items in horizontal list
              _buildBookList(context, books.take(10).toList(), emptyMessage),

              const SizedBox(height: 12),
              // See All Link
              ScaleOnTap(
                onTap: () => context.go(seeAllRoute),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(AppDesign.radiusRound),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        seeAllLabel,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 16,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    if (_dailyQuote == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Theme-aware colors — light themes use a tinted primary wash
    final gradientColors = isDark
        ? [theme.colorScheme.surface, theme.colorScheme.surface.withValues(alpha: 0.9)]
        : [
            Color.alphaBlend(
              theme.colorScheme.primary.withValues(alpha: 0.04),
              const Color(0xFFFFFBF7),
            ),
            Color.alphaBlend(
              theme.colorScheme.secondary.withValues(alpha: 0.06),
              const Color(0xFFFFF5ED),
            ),
          ];
    final textColor = isDark
        ? theme.colorScheme.onSurface
        : Color.lerp(theme.colorScheme.primary, const Color(0xFF5D4037), 0.6)!;

    // Check if quote is long (more than ~100 chars typically needs expansion)
    final isLongQuote = _dailyQuote!.text.length > 120;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        MouseRegion(
          cursor: isLongQuote ? SystemMouseCursors.click : MouseCursor.defer,
          child: GestureDetector(
            onTap: isLongQuote
                ? () => setState(() => _quoteExpanded = !_quoteExpanded)
                : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradientColors,
                ),
                borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
                border: Border.all(
                  color: isDark
                      ? theme.colorScheme.outline
                      : theme.colorScheme.primary.withValues(alpha: 0.12),
                  width: 1,
                ),
                boxShadow: AppDesign.cardShadow,
              ),
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  // Decorative background icon
                  Positioned(
                    right: -20,
                    top: -16,
                    child: Icon(
                      Icons.format_quote_rounded,
                      size: 120,
                      color: textColor.withValues(alpha: 0.12),
                    ),
                  ),
                  // Content
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AnimatedCrossFade(
                          duration: const Duration(milliseconds: 200),
                          crossFadeState: _quoteExpanded || !isLongQuote
                              ? CrossFadeState.showSecond
                              : CrossFadeState.showFirst,
                          firstChild: Text(
                            _dailyQuote!.text,
                            style: TextStyle(
                              fontSize: 16,
                              height: 1.4,
                              fontStyle: FontStyle.italic,
                              color: textColor,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          secondChild: Text(
                            _dailyQuote!.text,
                            style: TextStyle(
                              fontSize: 16,
                              height: 1.4,
                              fontStyle: FontStyle.italic,
                              color: textColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Expand/collapse indicator for long quotes
                            if (isLongQuote)
                              AnimatedRotation(
                                duration: const Duration(milliseconds: 200),
                                turns: _quoteExpanded ? 0.5 : 0,
                                child: Icon(
                                  Icons.keyboard_arrow_down,
                                  size: 20,
                                  color: textColor.withValues(alpha: 0.6),
                                ),
                              )
                            else
                              const SizedBox.shrink(),
                            // Author attribution (Clickable)
                            Expanded(
                              child: Builder(
                                builder: (context) {
                                  // Smart Search Logic
                                  final rawSource = _dailyQuote!.source;
                                  final rawAuthor = _dailyQuote!.author;
                                  final source = rawSource == 'Wikiquote'
                                      ? ''
                                      : rawSource;
                                  final author = rawAuthor == 'Wikiquote'
                                      ? ''
                                      : rawAuthor;

                                  if (author.isEmpty && source.isEmpty)
                                    return const SizedBox.shrink();

                                  final localBook = (source.isNotEmpty)
                                      ? _allBooks.cast<Book?>().firstWhere(
                                          (b) =>
                                              b!.title.toLowerCase().contains(
                                                source.toLowerCase(),
                                              ) ||
                                              source.toLowerCase().contains(
                                                b.title.toLowerCase(),
                                              ),
                                          orElse: () => null,
                                        )
                                      : null;

                                  return InkWell(
                                    onTap: () async {
                                      if (localBook != null) {
                                        context.push('/books/${localBook.id}');
                                      } else {
                                        final searchQuery = source.isNotEmpty
                                            ? "$author $source"
                                            : author;
                                        final result = await context.push(
                                          '/search/external?q=${Uri.encodeComponent(searchQuery)}',
                                        );
                                        if (result == true) {
                                          _fetchDashboardData();
                                        }
                                      }
                                    },
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        Container(
                                          width: 16,
                                          height: 1,
                                          color: textColor.withValues(
                                            alpha: 0.3,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Text(
                                            _dailyQuote!.author,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: textColor,
                                              letterSpacing: 0.3,
                                              decoration:
                                                  TextDecoration.underline,
                                              decorationColor: textColor
                                                  .withValues(alpha: 0.3),
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(
                                          localBook != null
                                              ? Icons.arrow_forward
                                              : Icons.search,
                                          size: 14,
                                          color: textColor.withValues(
                                            alpha: 0.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    BuildContext context,
    String label,
    String value,
    IconData icon, {
    bool isAccent = false,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final iconClr = isAccent ? Colors.white : theme.colorScheme.primary;
    final valueClr = isAccent ? Colors.white : theme.colorScheme.onSurface;
    final labelClr = isAccent
        ? Colors.white.withValues(alpha: 0.8)
        : theme.colorScheme.onSurfaceVariant;

    return ScaleOnTap(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: isAccent
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.primary.withValues(alpha: 0.85),
                  ],
                )
              : null,
          color: isAccent ? null : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppDesign.radiusXLarge),
          border: isAccent
              ? null
              : Border.all(
                  color: theme.colorScheme.outlineVariant,
                ),
          boxShadow: isAccent
              ? AppDesign.glowShadow(theme.colorScheme.primary)
              : AppDesign.cardShadow,
        ),
        child: Builder(
          builder: (context) {
            final isDesktop = MediaQuery.of(context).size.width > 600;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isAccent
                        ? Colors.white.withValues(alpha: 0.2)
                        : iconClr.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
                  ),
                  child: Icon(icon, color: iconClr, size: isDesktop ? 24 : 20),
                ),
                SizedBox(height: isDesktop ? 14 : 10),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: isDesktop ? 32 : 26,
                    fontWeight: FontWeight.w900,
                    color: valueClr,
                    letterSpacing: -0.5,
                  ),
                ),
                SizedBox(height: isDesktop ? 4 : 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: isDesktop ? 13 : 11,
                    fontWeight: FontWeight.w600,
                    color: labelClr,
                    letterSpacing: 0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    IconData icon = Icons.auto_stories;
    if (title.toLowerCase().contains('recent') ||
        title.toLowerCase().contains('récent')) {
      icon = Icons.history;
    } else if (title.toLowerCase().contains('reading') ||
        title.toLowerCase().contains('lecture')) {
      icon = Icons.bookmark;
    } else if (title.toLowerCase().contains('action')) {
      icon = Icons.bolt;
    }

    final themeStyle =
        Provider.of<ThemeProvider>(context, listen: false).themeStyle;
    final theme = Theme.of(context);
    final accentGradient = AppDesign.sectionAccentGradient(themeStyle);
    final iconColor = theme.colorScheme.primary;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 32,
            decoration: BoxDecoration(
              gradient: accentGradient,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: theme.colorScheme.onSurface,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBookList(
    BuildContext context,
    List<Book> books,
    String emptyMessage,
  ) {
    if (books.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: AppDesign.glassDecoration(),
        child: Center(
          child: Text(
            emptyMessage,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 260,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: books.length,
        padding: const EdgeInsets.only(top: 8, bottom: 4, left: 4, right: 4),
        clipBehavior: Clip.none,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(right: 16),
            child: PremiumBookCard(book: books[index]),
          );
        },
      ),
    );
  }

  Widget _buildKidActionCard(
    BuildContext context,
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap, {
    Key? key,
  }) {
    return ScaleOnTap(
      onTap: onTap,
      child: Container(
        key: key,
        height: 140,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: AppDesign.subtleShadow,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withAlpha(25),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: color),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
