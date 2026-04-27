import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/repositories/book_repository.dart';
import '../data/repositories/tag_repository.dart';
import '../data/repositories/contact_repository.dart';
import '../data/repositories/collection_repository.dart';
import '../data/repositories/loan_repository.dart';
import '../models/loan.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';
import '../models/book.dart';
import '../models/contact.dart';
import '../models/tag.dart';
import '../models/collection.dart';
import '../widgets/genie_app_bar.dart';
import '../widgets/scaffold_with_nav.dart';
import '../widgets/goal_reached_animation.dart';
import '../widgets/reorderable_sections.dart';
import '../theme/app_design.dart';
import '../providers/theme_provider.dart';
import '../src/rust/api/frb.dart' as frb;
import '../utils/loan_statistics.dart';
import '../utils/reading_statistics.dart';
import 'package:intl/intl.dart';

/// Data for a rating group (shelf or collection)
class _RatingGroup {
  final String name;
  final double avgRating;
  final int ratedCount;

  const _RatingGroup({
    required this.name,
    required this.avgRating,
    required this.ratedCount,
  });
}

class StatisticsScreen extends StatefulWidget {
  const StatisticsScreen({super.key});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen>
    with TickerProviderStateMixin {
  List<Book> _books = [];
  List<Loan> _loans = [];
  Map<int, Contact> _contactsMap = {};
  List<Tag> _tags = [];
  List<Collection> _collections = [];
  Map<String, dynamic>? _salesStats;
  frb.FrbOperationLogStats? _opLogStats;
  List<String>? _opLogEntityTypes;
  // Yearly reading goal
  int _yearlyGoal = 12;
  int _booksReadThisYear = 0;
  bool _goalAnimationShown = false;
  bool _isLoading = true;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  // late AnimationController _pulseController; removed
  // late Animation<double> _pulseAnimation; removed

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnim = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));

    _fetchData();
  }

  @override
  void dispose() {
    _animController.dispose();
    // _pulseController.dispose() removed
    super.dispose();
  }

  /// Check if the yearly goal was just reached and show celebration animation
  Future<void> _checkAndShowGoalAnimation() async {
    if (_goalAnimationShown) return;
    if (_yearlyGoal <= 0) return;
    if (_booksReadThisYear < _yearlyGoal) return;

    // Check if we already showed the animation for this year
    final prefs = await SharedPreferences.getInstance();
    final currentYear = DateTime.now().year;
    final lastCelebratedYear = prefs.getInt('yearly_goal_celebrated_year') ?? 0;

    if (lastCelebratedYear < currentYear) {
      // Goal reached for the first time this year - show celebration!
      await prefs.setInt('yearly_goal_celebrated_year', currentYear);
      _goalAnimationShown = true;

      if (mounted) {
        // Delay slightly to let the UI render first
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            GoalReachedAnimation.show(
              context,
              goalType: 'yearly',
              booksRead: _booksReadThisYear,
              customMessage: TranslationService.translate(
                context,
                'yearly_goal_reached',
              ),
            );
          }
        });
      }
    }
  }

  Future<void> _fetchData() async {
    final bookRepo = Provider.of<BookRepository>(context, listen: false);
    final tagRepo = Provider.of<TagRepository>(context, listen: false);
    final contactRepo = Provider.of<ContactRepository>(context, listen: false);
    final collectionRepo = Provider.of<CollectionRepository>(
      context,
      listen: false,
    );
    final loanRepo = Provider.of<LoanRepository>(context, listen: false);
    final api = Provider.of<ApiService>(context, listen: false);
    try {
      final books = await bookRepo.getBooks();

      // Fetch loans
      List<Loan> loans = [];
      try {
        loans = await loanRepo.getLoans();
      } catch (e) {
        debugPrint('Error fetching loans: $e');
      }

      // Fetch contacts for names
      Map<int, Contact> contactsMap = {};
      try {
        final contacts = await contactRepo.getContacts();
        for (var c in contacts) {
          if (c.id != null) {
            contactsMap[c.id!] = c;
          }
        }
      } catch (e) {}

      // Fetch tags (shelves)
      List<Tag> tags = [];
      try {
        tags = await tagRepo.getTags();
      } catch (e) {
        debugPrint('Error fetching tags: $e');
      }

      // Fetch collections
      List<Collection> collections = [];
      try {
        collections = await collectionRepo.getCollections();
      } catch (e) {
        debugPrint('Error fetching collections: $e');
      }

      // Fetch yearly reading goal data
      int yearlyGoal = 12;
      int booksReadThisYear = 0;
      try {
        final statusRes = await api.getUserStatus();
        if (statusRes.statusCode == 200) {
          final config = statusRes.data['config'] ?? {};
          yearlyGoal = config['reading_goal_yearly'] ?? 12;
          booksReadThisYear = config['reading_goal_progress'] ?? 0;
        }
      } catch (e) {
        debugPrint('Error fetching user status: $e');
      }

      Map<String, dynamic>? salesStats;
      if (Provider.of<ThemeProvider>(context, listen: false).isBookseller) {
        try {
          final statsRes = await api.getSalesStatistics();
          if (statsRes.statusCode == 200) {
            salesStats = statsRes.data;
          }
        } catch (e) {
          debugPrint('Error fetching sales stats: $e');
        }
      }

      // Fetch operation log stats if module is enabled
      frb.FrbOperationLogStats? opLogStats;
      List<String>? opLogEntityTypes;
      if (Provider.of<ThemeProvider>(
        context,
        listen: false,
      ).operationLogViewerEnabled) {
        try {
          opLogStats = await frb.operationLogStats();
          opLogEntityTypes = await frb.operationLogEntityTypes();
        } catch (e) {
          debugPrint('Error fetching operation log stats: $e');
        }
      }

      if (mounted) {
        setState(() {
          _books = books;
          _loans = loans;
          _contactsMap = contactsMap;
          _tags = tags;
          _collections = collections;
          _yearlyGoal = yearlyGoal;
          _booksReadThisYear = booksReadThisYear;
          _salesStats = salesStats;
          _opLogStats = opLogStats;
          _opLogEntityTypes = opLogEntityTypes;
          _isLoading = false;
        });
        _animController.forward();

        // Check if yearly goal was just reached and show animation
        _checkAndShowGoalAnimation();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    return Scaffold(
      appBar: GenieAppBar(
        title: TranslationService.translate(context, 'library_insights'),
        leading: buildDrawerLeading(context),
        automaticallyImplyLeading: false,
        showQuickActions: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _books.isEmpty
          ? _buildEmptyState()
          : FadeTransition(
              opacity: _fadeAnim,
              child: RefreshIndicator(
                onRefresh: _fetchData,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.only(
                    top:
                        kToolbarHeight +
                        48 +
                        MediaQuery.of(context).padding.top +
                        16,
                    left: 16.0,
                    right: 16.0,
                    bottom: 16.0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSummaryCards(),
                      // Yearly Reading Goal Section
                      const SizedBox(height: 32),
                      _buildSectionTitle(
                        TranslationService.translate(context, 'yearly_goal'),
                        Icons.emoji_events,
                        AppDesign.warningGradient,
                      ),
                      const SizedBox(height: 16),
                      _buildYearlyGoalSection(),
                      if (_salesStats != null) ...[
                        const SizedBox(height: 32),
                        _buildSectionTitle(
                          TranslationService.translate(
                            context,
                            'sales_statistics',
                          ),
                          Icons.monetization_on,
                          AppDesign.successGradient,
                        ),
                        const SizedBox(height: 16),
                        _buildSalesStatisticsSection(),
                      ],
                      _buildSectionTitle(
                        TranslationService.translate(context, 'reading_habits'),
                        Icons.pie_chart,
                        AppDesign.primaryGradient,
                      ),
                      const SizedBox(height: 16),
                      _buildStatusPieChart(),
                      const SizedBox(height: 32),
                      _buildSectionTitle(
                        TranslationService.translate(context, 'top_authors'),
                        Icons.person,
                        AppDesign.successGradient,
                      ),
                      const SizedBox(height: 16),
                      _buildTopAuthorsChart(),
                      const SizedBox(height: 32),
                      _buildSectionTitle(
                        TranslationService.translate(
                          context,
                          'publication_timeline',
                        ),
                        Icons.timeline,
                        AppDesign.oceanGradient,
                      ),
                      const SizedBox(height: 16),
                      _buildPublicationYearChart(),
                      const SizedBox(height: 32),
                      // Loan Statistics Section
                      _buildSectionTitle(
                        TranslationService.translate(
                          context,
                          'loan_statistics',
                        ),
                        Icons.swap_horiz,
                        AppDesign.accentGradient,
                      ),
                      const SizedBox(height: 16),
                      _buildLoanStatisticsSection(),
                      // Borrowed Statistics Section - shown only when the user
                      // borrows books (i.e. the borrowing module is enabled).
                      if (Provider.of<ThemeProvider>(
                        context,
                        listen: false,
                      ).canBorrowBooks) ...[
                        const SizedBox(height: 32),
                        _buildSectionTitle(
                          TranslationService.translate(
                            context,
                            'borrowed_statistics',
                          ),
                          Icons.arrow_downward,
                          AppDesign.oceanGradient,
                        ),
                        const SizedBox(height: 16),
                        _buildBorrowedStatisticsSection(),
                      ],
                      // Shelf Statistics Section - only if shelves exist
                      if (_tags.isNotEmpty) ...[
                        const SizedBox(height: 32),
                        _buildSectionTitle(
                          TranslationService.translate(
                            context,
                            'shelf_statistics',
                          ),
                          Icons.shelves,
                          AppDesign.warningGradient,
                        ),
                        const SizedBox(height: 16),
                        _buildShelfStatisticsSection(),
                      ],
                      // Collection Statistics Section - only if enabled
                      if (Provider.of<ThemeProvider>(
                        context,
                      ).collectionsEnabled) ...[
                        const SizedBox(height: 32),
                        _buildSectionTitle(
                          TranslationService.translate(
                            context,
                            'collection_statistics',
                          ),
                          Icons.collections_bookmark,
                          AppDesign.primaryGradient,
                        ),
                        const SizedBox(height: 16),
                        _buildCollectionStatisticsSection(),
                      ],
                      // Operation Log Stats - only if module enabled
                      if (Provider.of<ThemeProvider>(
                            context,
                            listen: false,
                          ).operationLogViewerEnabled &&
                          _opLogStats != null) ...[
                        const SizedBox(height: 32),
                        _buildSectionTitle(
                          TranslationService.translate(
                            context,
                            'stat_operation_log_title',
                          ),
                          Icons.sync,
                          AppDesign.cyanGradient,
                        ),
                        const SizedBox(height: 16),
                        _buildOperationLogStatsSection(),
                      ],
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.analytics_outlined,
              size: 64,
              color: Color(0xFF6366F1),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            TranslationService.translate(context, 'no_books_analyze'),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            TranslationService.translate(context, 'add_books_for_stats'),
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon, Gradient gradient) {
    return Row(
      children: [
        ExcludeSemantics(
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: Colors.white),
          ),
        ),
        const SizedBox(width: 16),
        Semantics(
          header: true,
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildYearlyGoalSection() {
    final progress = _yearlyGoal > 0
        ? (_booksReadThisYear / _yearlyGoal).clamp(0.0, 1.0)
        : 0.0;
    final isGoalReached = _booksReadThisYear >= _yearlyGoal && _yearlyGoal > 0;
    final currentYear = DateTime.now().year;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: isGoalReached
            ? const LinearGradient(
                colors: [Color(0xFFFFD700), Color(0xFFFFA500)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: isGoalReached ? null : Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
        boxShadow: isGoalReached
            ? [
                BoxShadow(
                  color: Colors.orange.withValues(alpha: 0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ]
            : AppDesign.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with year and trophy
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    isGoalReached ? Icons.emoji_events : Icons.track_changes,
                    color: isGoalReached
                        ? Colors.white
                        : const Color(0xFFF59E0B),
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$currentYear',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: isGoalReached
                              ? Colors.white.withValues(alpha: 0.8)
                              : Colors.grey[600],
                        ),
                      ),
                      Text(
                        TranslationService.translate(
                          context,
                          'reading_challenge',
                        ),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isGoalReached ? Colors.white : null,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (isGoalReached)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    TranslationService.translate(context, 'goal_completed'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),

          // Progress indicator
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Progress bar
                    Semantics(
                      label:
                          '${TranslationService.translate(context, 'stat_a11y_yearly_goal_progress')}: $_booksReadThisYear / $_yearlyGoal, ${(progress * 100).toInt()}%',
                      child: ExcludeSemantics(
                        child: Stack(
                          children: [
                            Container(
                              height: 12,
                              decoration: BoxDecoration(
                                color: isGoalReached
                                    ? Colors.white.withValues(alpha: 0.3)
                                    : Colors.grey[200],
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                            FractionallySizedBox(
                              widthFactor: progress,
                              child: Container(
                                height: 12,
                                decoration: BoxDecoration(
                                  gradient: isGoalReached
                                      ? const LinearGradient(
                                          colors: [
                                            Colors.white,
                                            Color(0xFFFFF8DC),
                                          ],
                                        )
                                      : const LinearGradient(
                                          colors: [
                                            Color(0xFFF59E0B),
                                            Color(0xFFD97706),
                                          ],
                                        ),
                                  borderRadius: BorderRadius.circular(6),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          (isGoalReached
                                                  ? Colors.white
                                                  : const Color(0xFFF59E0B))
                                              .withValues(alpha: 0.4),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Count text
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$_booksReadThisYear / $_yearlyGoal ${TranslationService.translate(context, 'books')}',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isGoalReached ? Colors.white : null,
                          ),
                        ),
                        Text(
                          '${(progress * 100).toInt()}%',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isGoalReached
                                ? Colors.white
                                : const Color(0xFFF59E0B),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Motivational message
          if (!isGoalReached && _yearlyGoal > 0) ...[
            const SizedBox(height: 16),
            Text(
              _getBooksRemainingMessage(),
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _getBooksRemainingMessage() {
    final remaining = _yearlyGoal - _booksReadThisYear;
    if (remaining <= 0) return '';
    final booksWord = remaining == 1
        ? TranslationService.translate(context, 'book')
        : TranslationService.translate(context, 'books');
    return '$remaining $booksWord ${TranslationService.translate(context, 'remaining_to_goal')}';
  }

  Widget _buildSummaryCards() {
    final totalBooks = _books.length;
    final readBooks = _books.where((b) => b.readingStatus == 'read').length;
    final borrowedBooks = _books.where((b) => !b.owned).length;

    final uniqueAuthors = _books
        .where((b) => b.author != null && b.author!.isNotEmpty)
        .map((b) => b.author!)
        .toSet()
        .length;

    final completionRate = totalBooks > 0
        ? (readBooks / totalBooks * 100).toStringAsFixed(0)
        : '0';

    final booksWithYears = _books
        .where((b) => b.publicationYear != null && b.publicationYear! > 1800)
        .toList();
    final oldestYear = booksWithYears.isEmpty
        ? null
        : booksWithYears
              .map((b) => b.publicationYear!)
              .reduce((a, b) => a < b ? a : b);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                TranslationService.translate(context, 'stat_total_books'),
                totalBooks.toString(),
                Icons.library_books,
                Colors.transparent,
                gradient: AppDesign.oceanGradient,
                textColor: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                TranslationService.translate(context, 'stat_read'),
                readBooks.toString(),
                Icons.check_circle,
                Colors.transparent,
                gradient: AppDesign.successGradient,
                textColor: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                TranslationService.translate(context, 'stat_borrowed'),
                borrowedBooks.toString(),
                Icons.people,
                Colors.transparent,
                gradient: AppDesign.flameGradient,
                textColor: Colors.white,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                TranslationService.translate(context, 'stat_unique_authors'),
                uniqueAuthors.toString(),
                Icons.person_outline,
                Colors.transparent,
                gradient: AppDesign.orangeGradient,
                textColor: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                TranslationService.translate(context, 'stat_completion'),
                "$completionRate%",
                Icons.trending_up,
                Colors.transparent,
                gradient: AppDesign.primaryGradient,
                textColor: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                TranslationService.translate(context, 'stat_oldest_book'),
                oldestYear?.toString() ?? "N/A",
                Icons.history,
                Colors.transparent,
                gradient: AppDesign.anthraciteGradient,
                textColor: Colors.white,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color backgroundColor, {
    Gradient? gradient,
    Color textColor = Colors.white,
  }) {
    // Extract accent color from gradient or fall back to backgroundColor
    final Color accentColor = gradient is LinearGradient
        ? gradient.colors.first
        : (backgroundColor == Colors.transparent
              ? Theme.of(context).colorScheme.primary
              : backgroundColor);
    final theme = Theme.of(context);

    return Semantics(
      label: '$label: $value',
      child: Container(
        height: 140,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
          boxShadow: AppDesign.cardShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
          child: Stack(
            children: [
              // Left accent bar
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 4,
                  decoration: BoxDecoration(
                    gradient:
                        gradient ??
                        LinearGradient(colors: [accentColor, accentColor]),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Icon with gradient background
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        gradient:
                            gradient ??
                            LinearGradient(
                              colors: [
                                accentColor,
                                accentColor.withValues(alpha: 0.8),
                              ],
                            ),
                        borderRadius: BorderRadius.circular(
                          AppDesign.radiusMedium,
                        ),
                      ),
                      child: Icon(icon, color: Colors.white, size: 20),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          value,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: accentColor,
                            height: 1.0,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
    );
  }

  Widget _buildStatusPieChart() {
    final statusCounts = <String, int>{};
    for (var book in _books) {
      final status = book.readingStatus ?? 'unknown';
      statusCounts[status] = (statusCounts[status] ?? 0) + 1;
    }

    final colors = {
      'read': const Color(0xFF10B981),
      'reading': const Color(0xFF0EA5E9),
      'to_read': const Color(0xFFF59E0B),
      'wanting': const Color(0xFFEC4899),
      'abandoned': const Color(0xFFEF4444),
      'owned': const Color(0xFF607D8B),
      'borrowed': const Color(0xFF8B5CF6),
      'unknown': Colors.grey,
    };

    final List<PieChartSectionData> sections = [];
    statusCounts.forEach((status, count) {
      final color = colors[status] ?? Colors.grey;
      final percentage = (count / _books.length * 100).toStringAsFixed(0);
      sections.add(
        PieChartSectionData(
          color: color,
          value: count.toDouble(),
          title: '$percentage%',
          radius: 70,
          titleStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      );
    });

    final chartDescription = statusCounts.entries
        .map((e) => '${_formatStatusLabel(e.key)}: ${e.value}')
        .join(', ');

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
        boxShadow: AppDesign.cardShadow,
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Semantics(
            label:
                '${TranslationService.translate(context, 'stat_a11y_reading_status_chart')}: $chartDescription',
            child: ExcludeSemantics(
              child: SizedBox(
                height: 200,
                child: PieChart(
                  PieChartData(
                    sections: sections,
                    centerSpaceRadius: 50,
                    sectionsSpace: 3,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: statusCounts.entries.map((e) {
              final color = colors[e.key] ?? Colors.grey;
              final label = _formatStatusLabel(e.key);
              return _buildLegendItem(color, label, e.value);
            }).toList(),
          ),
        ],
      ),
    );
  }

  String _formatStatusLabel(String status) {
    switch (status) {
      case 'read':
        return TranslationService.translate(context, 'reading_status_read');
      case 'reading':
        return TranslationService.translate(context, 'reading_status_reading');
      case 'to_read':
        return TranslationService.translate(context, 'reading_status_to_read');
      case 'wanting':
        return TranslationService.translate(context, 'reading_status_wanting');
      case 'abandoned':
        return TranslationService.translate(
          context,
          'reading_status_abandoned',
        );
      case 'owned':
        return TranslationService.translate(context, 'owned_status');
      case 'lent':
        return TranslationService.translate(context, 'reading_status_lent');
      case 'borrowed':
        return TranslationService.translate(context, 'reading_status_borrowed');
      default:
        return status.replaceAll('_', ' ');
    }
  }

  Widget _buildLegendItem(Color color, String label, int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$label ($count)',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildTopAuthorsChart() {
    final authorCounts = <String, int>{};
    for (var book in _books) {
      if (book.author != null && book.author!.isNotEmpty) {
        authorCounts[book.author!] = (authorCounts[book.author!] ?? 0) + 1;
      }
    }

    var sortedAuthors = authorCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (sortedAuthors.length > 10) {
      sortedAuthors = sortedAuthors.sublist(0, 10);
    }

    if (sortedAuthors.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
          boxShadow: AppDesign.cardShadow,
        ),
        child: Center(
          child: Text(TranslationService.translate(context, 'no_author_data')),
        ),
      );
    }

    final maxCount = sortedAuthors.first.value;
    final theme = Theme.of(context);
    final authorsDescription = sortedAuthors
        .map((e) => '${e.key}: ${e.value}')
        .join(', ');

    return Semantics(
      label:
          '${TranslationService.translate(context, 'stat_a11y_top_authors_chart')}: $authorsDescription',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
            boxShadow: AppDesign.cardShadow,
          ),
          child: Column(
            children: [
              for (var i = 0; i < sortedAuthors.length; i++) ...[
                if (i > 0) const SizedBox(height: 6),
                _buildAuthorLeaderboardRow(
                  rank: i + 1,
                  name: sortedAuthors[i].key,
                  count: sortedAuthors[i].value,
                  maxCount: maxCount,
                  theme: theme,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAuthorLeaderboardRow({
    required int rank,
    required String name,
    required int count,
    required int maxCount,
    required ThemeData theme,
  }) {
    final fraction = maxCount > 0 ? count / maxCount : 0.0;
    final podiumColors = [
      const Color(0xFFF59E0B), // gold
      const Color(0xFF94A3B8), // silver
      const Color(0xFFCD7F32), // bronze
    ];
    final barColor = rank <= 3
        ? podiumColors[rank - 1]
        : theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: rank <= 3
                ? Icon(
                    Icons.emoji_events,
                    size: 18,
                    color: podiumColors[rank - 1],
                  )
                : Text(
                    '$rank',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: Text(
              name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: rank <= 3 ? FontWeight.w600 : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 14,
                backgroundColor: theme.colorScheme.onSurface.withValues(
                  alpha: 0.06,
                ),
                valueColor: AlwaysStoppedAnimation<Color>(
                  barColor.withValues(alpha: 0.7),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 32,
            child: Text(
              '$count',
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: barColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPublicationYearChart() {
    final yearCounts = <int, int>{};
    for (var book in _books) {
      if (book.publicationYear != null && book.publicationYear! > 1800) {
        final decade = (book.publicationYear! ~/ 10) * 10;
        yearCounts[decade] = (yearCounts[decade] ?? 0) + 1;
      }
    }

    final sortedYears = yearCounts.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    if (sortedYears.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
          boxShadow: AppDesign.cardShadow,
        ),
        child: Center(
          child: Text(
            TranslationService.translate(context, 'no_pub_year_data'),
          ),
        ),
      );
    }

    final timelineDescription = sortedYears
        .map((e) => '${e.key}s: ${e.value}')
        .join(', ');

    return Semantics(
      label:
          '${TranslationService.translate(context, 'stat_a11y_publication_timeline')}: $timelineDescription',
      child: ExcludeSemantics(
        child: Container(
          height: 280,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
            boxShadow: AppDesign.cardShadow,
          ),
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: 1,
                getDrawingHorizontalLine: (value) {
                  return FlLine(
                    color: Colors.black.withValues(alpha: 0.5),
                    strokeWidth: 1,
                  );
                },
              ),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index >= 0 && index < sortedYears.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            sortedYears[index].key.toString(),
                            style: const TextStyle(fontSize: 10),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                    interval: 1,
                    reservedSize: 30,
                  ),
                ),
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  spots: sortedYears.asMap().entries.map((e) {
                    return FlSpot(e.key.toDouble(), e.value.value.toDouble());
                  }).toList(),
                  isCurved: true,
                  gradient: AppDesign.oceanGradient,
                  barWidth: 4,
                  isStrokeCapRound: true,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, barData, index) {
                      return FlDotCirclePainter(
                        radius: 5,
                        color: const Color(0xFF0EA5E9),
                        strokeWidth: 2,
                        strokeColor: Colors.white,
                      );
                    },
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF0EA5E9).withValues(alpha: 0.3),
                        const Color(0xFF0EA5E9).withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ],
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (touchedSpot) => const Color(0xFF1E293B),
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((spot) {
                      final year = sortedYears[spot.x.toInt()].key;
                      return LineTooltipItem(
                        '${year}s\n',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        children: [
                          TextSpan(
                            text:
                                '${spot.y.toInt()} ${TranslationService.translate(context, 'stat_chart_books_count')}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      );
                    }).toList();
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoanStatisticsSection() {
    final stats = LoanStatistics.fromLoans(_loans);

    // Top borrowers (contacts)
    final borrowerCounts = <String, int>{};
    for (var loan in _loans) {
      String contactName = TranslationService.translate(
        context,
        'stat_unknown_contact',
      );

      if (_contactsMap.containsKey(loan.contactId)) {
        final contact = _contactsMap[loan.contactId]!;
        contactName = contact.fullName;
      } else if (loan.contactName.isNotEmpty) {
        contactName = loan.contactName;
      }

      borrowerCounts[contactName] = (borrowerCounts[contactName] ?? 0) + 1;
    }
    var topBorrowers = borrowerCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (topBorrowers.length > 5) topBorrowers = topBorrowers.sublist(0, 5);

    // Most lent books
    final bookCounts = <String, int>{};
    for (var loan in _loans) {
      final bookTitle = loan.bookTitle.isNotEmpty
          ? loan.bookTitle
          : TranslationService.translate(context, 'stat_unknown_contact');
      bookCounts[bookTitle] = (bookCounts[bookTitle] ?? 0) + 1;
    }
    var mostLentBooks = bookCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (mostLentBooks.length > 5) mostLentBooks = mostLentBooks.sublist(0, 5);

    final isDesktop = MediaQuery.of(context).size.width > 900;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
        boxShadow: AppDesign.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary stats row
          Row(
            children: [
              Expanded(
                child: _buildMiniStat(
                  TranslationService.translate(context, 'total_loans'),
                  stats.total.toString(),
                  Icons.swap_horiz,
                  const Color(0xFF8B4513), // Bronze instead of purple
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMiniStat(
                  TranslationService.translate(context, 'active_loans'),
                  stats.active.toString(),
                  Icons.arrow_upward,
                  Colors.orange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMiniStat(
                  TranslationService.translate(context, 'return_rate'),
                  formatReturnRate(stats.returnRatePercent),
                  Icons.check_circle,
                  Colors.green,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMiniStat(
                  TranslationService.translate(context, 'avg_duration'),
                  formatAvgDuration(
                    stats.avgDurationDays,
                    lessThanOneDayLabel: TranslationService.translate(
                      context,
                      'avg_duration_under_one_day',
                    ),
                  ),
                  Icons.timer,
                  const Color(0xFFA16207), // Bronze instead of blue
                ),
              ),
            ],
          ),

          if (isDesktop &&
              (topBorrowers.isNotEmpty || mostLentBooks.isNotEmpty)) ...[
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (topBorrowers.isNotEmpty)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          TranslationService.translate(
                            context,
                            'top_borrowers',
                          ),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...topBorrowers.map((e) => _buildBorrowerRow(e)),
                      ],
                    ),
                  ),
                if (topBorrowers.isNotEmpty && mostLentBooks.isNotEmpty)
                  const SizedBox(width: 24),
                if (mostLentBooks.isNotEmpty)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          TranslationService.translate(
                            context,
                            'most_lent_books',
                          ),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...mostLentBooks.map(
                          (e) => _buildMetricRow(
                            e,
                            Icons.menu_book,
                            const Color(0xFFA16207),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ] else ...[
            if (topBorrowers.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                TranslationService.translate(context, 'top_borrowers'),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              ...topBorrowers.map((e) => _buildBorrowerRow(e)),
            ],
            if (mostLentBooks.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                TranslationService.translate(context, 'most_lent_books'),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              ...mostLentBooks.map(
                (e) => _buildMetricRow(
                  e,
                  Icons.menu_book,
                  const Color(0xFFA16207),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildBorrowerRow(MapEntry<String, int> e) {
    final isDesktop = MediaQuery.of(context).size.width > 900;
    return Padding(
      padding: EdgeInsets.only(bottom: isDesktop ? 12 : 8),
      child: Row(
        children: [
          Icon(
            Icons.person_outline,
            size: isDesktop ? 22 : 18,
            color: Colors.grey,
          ),
          SizedBox(width: isDesktop ? 12 : 8),
          Expanded(
            child: Text(
              e.key,
              style: TextStyle(fontSize: isDesktop ? 15 : 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isDesktop ? 10 : 8,
              vertical: isDesktop ? 4 : 2,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF8B4513).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${e.value} ${TranslationService.translate(context, 'loans_label')}',
              style: TextStyle(
                fontSize: isDesktop ? 13 : 11,
                color: const Color(0xFF8B4513),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricRow(MapEntry<String, int> e, IconData icon, Color color) {
    final isDesktop = MediaQuery.of(context).size.width > 900;
    return Padding(
      padding: EdgeInsets.only(bottom: isDesktop ? 12 : 8),
      child: Row(
        children: [
          Icon(icon, size: isDesktop ? 22 : 18, color: Colors.grey),
          SizedBox(width: isDesktop ? 12 : 8),
          Expanded(
            child: Text(
              e.key,
              style: TextStyle(fontSize: isDesktop ? 15 : 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isDesktop ? 10 : 8,
              vertical: isDesktop ? 4 : 2,
            ),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${e.value}x',
              style: TextStyle(fontSize: isDesktop ? 13 : 11, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    final isDesktop = MediaQuery.of(context).size.width > 900;

    return Container(
      padding: EdgeInsets.symmetric(
        vertical: isDesktop ? 16 : 12,
        horizontal: isDesktop ? 12 : 8,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
        border: Border.all(color: color.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(isDesktop ? 10 : 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppDesign.radiusSmall),
            ),
            child: Icon(icon, size: isDesktop ? 24 : 18, color: color),
          ),
          SizedBox(height: isDesktop ? 10 : 8),
          Text(
            value,
            style: TextStyle(
              fontSize: isDesktop ? 22 : 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          SizedBox(height: isDesktop ? 4 : 2),
          Text(
            label,
            style: TextStyle(
              fontSize: isDesktop ? 12 : 10,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildBorrowedStatisticsSection() {
    // Get borrowed books from library
    final borrowedBooks = _books.where((b) => !b.owned).toList();
    final totalBorrowed = borrowedBooks.length;
    final isDesktop = MediaQuery.of(context).size.width > 900;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
        boxShadow: AppDesign.cardShadow,
      ),
      child: isDesktop
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildMiniStat(
                          TranslationService.translate(
                            context,
                            'books_borrowed',
                          ),
                          totalBorrowed.toString(),
                          Icons.arrow_downward,
                          Colors.teal,
                        ),
                      ),
                    ],
                  ),
                ),
                if (borrowedBooks.isNotEmpty) ...[
                  const SizedBox(width: 24),
                  Container(
                    width: 1,
                    height: 100,
                    color: Colors.grey.withValues(alpha: 0.2),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          TranslationService.translate(
                            context,
                            'borrowed_books_list',
                          ),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...borrowedBooks
                            .take(5)
                            .map((book) => _buildBorrowedBookRow(book)),
                      ],
                    ),
                  ),
                ],
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Summary stat
                Row(
                  children: [
                    Expanded(
                      child: _buildMiniStat(
                        TranslationService.translate(context, 'books_borrowed'),
                        totalBorrowed.toString(),
                        Icons.arrow_downward,
                        Colors.teal,
                      ),
                    ),
                  ],
                ),

                if (borrowedBooks.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(
                    TranslationService.translate(
                      context,
                      'borrowed_books_list',
                    ),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...borrowedBooks
                      .take(5)
                      .map((book) => _buildBorrowedBookRow(book)),
                ] else ...[
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      TranslationService.translate(
                        context,
                        'no_borrowed_books',
                      ),
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildBorrowedBookRow(Book book) {
    final isDesktop = MediaQuery.of(context).size.width > 900;
    return Padding(
      padding: EdgeInsets.only(bottom: isDesktop ? 12 : 8),
      child: Row(
        children: [
          Icon(Icons.menu_book, size: isDesktop ? 22 : 18, color: Colors.grey),
          SizedBox(width: isDesktop ? 12 : 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.title,
                  style: TextStyle(fontSize: isDesktop ? 15 : 13),
                  overflow: TextOverflow.ellipsis,
                ),
                if (book.author != null)
                  Text(
                    book.author!,
                    style: TextStyle(
                      fontSize: isDesktop ? 13 : 11,
                      color: Colors.grey[600],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShelfStatisticsSection() {
    final totalShelves = _tags.length;
    final totalBooksInShelves = _tags.fold<int>(
      0,
      (sum, tag) => sum + tag.count,
    );
    final isDesktop = MediaQuery.of(context).size.width > 900;

    // Top shelves (by book count)
    var topShelves = _tags.toList()..sort((a, b) => b.count.compareTo(a.count));
    if (topShelves.length > 5) topShelves = topShelves.sublist(0, 5);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
        boxShadow: AppDesign.cardShadow,
      ),
      child: isDesktop
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildMiniStat(
                          TranslationService.translate(
                            context,
                            'total_shelves',
                          ),
                          totalShelves.toString(),
                          Icons.shelves,
                          const Color(0xFFF59E0B),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildMiniStat(
                          TranslationService.translate(
                            context,
                            'books_in_shelves',
                          ),
                          totalBooksInShelves.toString(),
                          Icons.menu_book,
                          const Color(0xFFD97706),
                        ),
                      ),
                    ],
                  ),
                ),
                if (topShelves.isNotEmpty) ...[
                  const SizedBox(width: 24),
                  Container(
                    width: 1,
                    height: 100,
                    color: Colors.grey.withValues(alpha: 0.2),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          TranslationService.translate(context, 'top_shelves'),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...topShelves.map((tag) => _buildShelfRow(tag)),
                      ],
                    ),
                  ),
                ],
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Summary stats row
                Row(
                  children: [
                    Expanded(
                      child: _buildMiniStat(
                        TranslationService.translate(context, 'total_shelves'),
                        totalShelves.toString(),
                        Icons.shelves,
                        const Color(0xFFF59E0B),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMiniStat(
                        TranslationService.translate(
                          context,
                          'books_in_shelves',
                        ),
                        totalBooksInShelves.toString(),
                        Icons.menu_book,
                        const Color(0xFFD97706),
                      ),
                    ),
                  ],
                ),

                if (topShelves.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(
                    TranslationService.translate(context, 'top_shelves'),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...topShelves.map((tag) => _buildShelfRow(tag)),
                ],
              ],
            ),
    );
  }

  Widget _buildShelfRow(Tag tag) {
    final isDesktop = MediaQuery.of(context).size.width > 900;
    return Padding(
      padding: EdgeInsets.only(bottom: isDesktop ? 12 : 8),
      child: Row(
        children: [
          Icon(
            Icons.label_outline,
            size: isDesktop ? 22 : 18,
            color: Colors.grey,
          ),
          SizedBox(width: isDesktop ? 12 : 8),
          Expanded(
            child: Text(
              tag.name,
              style: TextStyle(fontSize: isDesktop ? 15 : 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isDesktop ? 10 : 8,
              vertical: isDesktop ? 4 : 2,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFB45309).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${tag.count}',
              style: TextStyle(
                fontSize: isDesktop ? 13 : 11,
                color: const Color(0xFFB45309),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollectionStatisticsSection() {
    final totalCollections = _collections.length;
    final totalBooksInCollections = _collections.fold<int>(
      0,
      (sum, col) => sum + col.totalBooks,
    );
    final isDesktop = MediaQuery.of(context).size.width > 900;

    // Top collections (by book count)
    var topCollections = _collections.toList()
      ..sort((a, b) => b.totalBooks.compareTo(a.totalBooks));
    if (topCollections.length > 5)
      topCollections = topCollections.sublist(0, 5);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
        boxShadow: AppDesign.cardShadow,
      ),
      child: isDesktop
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 2,
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildMiniStat(
                          TranslationService.translate(
                            context,
                            'total_collections',
                          ),
                          totalCollections.toString(),
                          Icons.collections_bookmark,
                          const Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildMiniStat(
                          TranslationService.translate(
                            context,
                            'books_in_collections',
                          ),
                          totalBooksInCollections.toString(),
                          Icons.menu_book,
                          const Color(0xFF475569),
                        ),
                      ),
                    ],
                  ),
                ),
                if (topCollections.isNotEmpty) ...[
                  const SizedBox(width: 24),
                  Container(
                    width: 1,
                    height: 100,
                    color: Colors.grey.withValues(alpha: 0.2),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          TranslationService.translate(
                            context,
                            'top_collections',
                          ),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...topCollections.map(
                          (col) => _buildCollectionRow(col),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Summary stats row
                Row(
                  children: [
                    Expanded(
                      child: _buildMiniStat(
                        TranslationService.translate(
                          context,
                          'total_collections',
                        ),
                        totalCollections.toString(),
                        Icons.collections_bookmark,
                        const Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMiniStat(
                        TranslationService.translate(
                          context,
                          'books_in_collections',
                        ),
                        totalBooksInCollections.toString(),
                        Icons.menu_book,
                        const Color(0xFF475569),
                      ),
                    ),
                  ],
                ),

                if (topCollections.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(
                    TranslationService.translate(context, 'top_collections'),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...topCollections.map((col) => _buildCollectionRow(col)),
                ],
              ],
            ),
    );
  }

  Widget _buildCollectionRow(Collection col) {
    final isDesktop = MediaQuery.of(context).size.width > 900;
    return Padding(
      padding: EdgeInsets.only(bottom: isDesktop ? 12 : 8),
      child: Row(
        children: [
          Icon(
            Icons.bookmark_outline,
            size: isDesktop ? 22 : 18,
            color: Colors.grey,
          ),
          SizedBox(width: isDesktop ? 12 : 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  col.name,
                  style: TextStyle(fontSize: isDesktop ? 15 : 13),
                  overflow: TextOverflow.ellipsis,
                ),
                if (col.description != null && col.description!.isNotEmpty)
                  Text(
                    col.description!,
                    style: TextStyle(
                      fontSize: isDesktop ? 13 : 11,
                      color: Colors.grey[600],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isDesktop ? 10 : 8,
              vertical: isDesktop ? 4 : 2,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${col.totalBooks}',
              style: TextStyle(
                fontSize: isDesktop ? 13 : 11,
                color: const Color(0xFF1E293B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOperationLogStatsSection() {
    final stats = _opLogStats!;
    final entityTypes = _opLogEntityTypes ?? [];
    final isDesktop = MediaQuery.of(context).size.width > 900;

    // Health status
    final hasFailed = stats.failed > BigInt.zero;
    final hasPending = stats.pending > BigInt.zero;
    Color healthColor;
    String healthMessage;
    if (hasFailed) {
      healthColor = Colors.red;
      healthMessage = TranslationService.translate(
        context,
        'stat_oplog_health_error',
      ).replaceAll('%1', stats.failed.toString());
    } else if (hasPending) {
      healthColor = Colors.orange;
      healthMessage = TranslationService.translate(
        context,
        'stat_oplog_health_warning',
      ).replaceAll('%1', stats.pending.toString());
    } else {
      healthColor = Colors.green;
      healthMessage = TranslationService.translate(
        context,
        'stat_oplog_health_ok',
      );
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
        boxShadow: AppDesign.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mini stats row
          Row(
            children: [
              Expanded(
                child: _buildMiniStat(
                  'Total',
                  stats.total.toString(),
                  Icons.sync,
                  const Color(0xFF6366F1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMiniStat(
                  TranslationService.translate(context, 'today'),
                  stats.today.toString(),
                  Icons.today,
                  const Color(0xFF0EA5E9),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMiniStat(
                  TranslationService.translate(context, 'stat_oplog_pending'),
                  stats.pending.toString(),
                  Icons.pending_actions,
                  Colors.orange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMiniStat(
                  TranslationService.translate(context, 'errors'),
                  stats.failed.toString(),
                  Icons.error_outline,
                  Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Health indicator
          Row(
            children: [
              Container(
                width: isDesktop ? 12 : 10,
                height: isDesktop ? 12 : 10,
                decoration: BoxDecoration(
                  color: healthColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  healthMessage,
                  style: TextStyle(
                    fontSize: isDesktop ? 14 : 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          if (entityTypes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '${entityTypes.length} ${TranslationService.translate(context, 'stat_oplog_entity_types')}',
              style: TextStyle(
                fontSize: isDesktop ? 13 : 12,
                color: Colors.grey[600],
              ),
            ),
          ],
          const SizedBox(height: 16),
          // Link to operation log
          InkWell(
            onTap: () => context.push('/operation-log'),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.arrow_forward,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    TranslationService.translate(
                      context,
                      'stat_oplog_view_details',
                    ),
                    style: TextStyle(
                      fontSize: isDesktop ? 14 : 13,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSalesStatisticsSection() {
    if (_salesStats == null) return const SizedBox.shrink();

    final totalRevenue =
        (_salesStats!['total_revenue'] as num?)?.toDouble() ?? 0.0;
    final totalSales = (_salesStats!['total_sales'] as num?)?.toInt() ?? 0;
    final avgPrice = (_salesStats!['average_price'] as num?)?.toDouble() ?? 0.0;

    final currencyFormat = NumberFormat.currency(locale: 'fr_FR', symbol: '€');

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                TranslationService.translate(context, 'total_revenue'),
                currencyFormat.format(totalRevenue),
                Icons.euro,
                Colors.transparent,
                gradient: AppDesign.successGradient,
                textColor: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                TranslationService.translate(context, 'sales_count'),
                totalSales.toString(),
                Icons.shopping_cart,
                Colors.transparent,
                gradient: AppDesign.oceanGradient,
                textColor: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                TranslationService.translate(context, 'average_price'),
                currencyFormat.format(avgPrice),
                Icons.price_check,
                Colors.transparent,
                gradient: AppDesign.primaryGradient,
                textColor: Colors.white,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Embeddable statistics content widget (without Scaffold)
/// Used in Dashboard tabs - Now includes all statistics from StatisticsScreen
///
/// [refreshTrigger] is an optional listenable whose value-changes cause the
/// content to re-fetch data. It is used by the dashboard to refresh the stats
/// tab when the user switches to it: without this, `_fetchData` would only run
/// once in `initState` and the numbers would go stale as loans are created or
/// returned elsewhere in the app.
class StatisticsContent extends StatefulWidget {
  final Listenable? refreshTrigger;

  const StatisticsContent({super.key, this.refreshTrigger});

  @override
  State<StatisticsContent> createState() => _StatisticsContentState();
}

class _StatisticsContentState extends State<StatisticsContent>
    with TickerProviderStateMixin {
  List<Book> _books = [];
  List<Loan> _loans = [];
  Map<int, Contact> _contactsMap = {};
  List<Tag> _tags = [];
  List<Collection> _collections = [];
  Map<String, dynamic>? _salesStats;
  frb.FrbOperationLogStats? _opLogStats;
  List<String>? _opLogEntityTypes;
  List<_RatingGroup> _tagRatings = [];
  List<_RatingGroup> _collectionRatings = [];
  Map<String, int> _collectionReadCounts = {};
  bool _isLoading = true;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  // Insight card ordering
  static const _defaultInsightCardIds = [
    'avg_reading_time',
    'total_pages',
    'books_finished_year',
    'days_since_last',
  ];
  List<String> _insightCardOrder = List.from(_defaultInsightCardIds);
  Set<String> _hiddenInsightCards = {};

  // Summary card ordering
  static const _defaultSummaryCardIds = [
    'total_books',
    'read_books',
    'borrowed_books',
    'unique_authors',
    'completion',
    'oldest_book',
  ];
  List<String> _summaryCardOrder = List.from(_defaultSummaryCardIds);
  Set<String> _hiddenSummaryCards = {};
  bool _summaryEditMode = false;

  @override
  void initState() {
    super.initState();
    _loadInsightPrefs();
    _loadSummaryPrefs();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnim = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));

    _fetchData();
    widget.refreshTrigger?.addListener(_onRefreshRequested);
  }

  @override
  void didUpdateWidget(covariant StatisticsContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTrigger != widget.refreshTrigger) {
      oldWidget.refreshTrigger?.removeListener(_onRefreshRequested);
      widget.refreshTrigger?.addListener(_onRefreshRequested);
    }
  }

  @override
  void dispose() {
    widget.refreshTrigger?.removeListener(_onRefreshRequested);
    _animController.dispose();
    super.dispose();
  }

  void _onRefreshRequested() {
    if (!mounted || _isLoading) return;
    _fetchData();
  }

  Future<void> _loadSummaryPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final orderJson = prefs.getString('statistics_summary_order');
    final hiddenJson = prefs.getString('statistics_summary_hidden');
    if (!mounted) return;
    setState(() {
      if (orderJson != null) {
        final saved = List<String>.from(json.decode(orderJson) as List);
        final known = _defaultSummaryCardIds.toSet();
        final valid = saved.where(known.contains).toList();
        final newIds = known.difference(valid.toSet());
        _summaryCardOrder = [...valid, ...newIds];
      }
      if (hiddenJson != null) {
        _hiddenSummaryCards = Set<String>.from(json.decode(hiddenJson) as List);
      }
    });
  }

  Future<void> _saveSummaryOrder() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'statistics_summary_order',
      json.encode(_summaryCardOrder),
    );
  }

  Future<void> _saveSummaryHidden() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'statistics_summary_hidden',
      json.encode(_hiddenSummaryCards.toList()),
    );
  }

  Future<void> _loadInsightPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final orderJson = prefs.getString('statistics_insight_order');
    final hiddenJson = prefs.getString('statistics_insight_hidden');
    if (!mounted) return;
    setState(() {
      if (orderJson != null) {
        final saved = List<String>.from(json.decode(orderJson) as List);
        final known = _defaultInsightCardIds.toSet();
        final valid = saved.where(known.contains).toList();
        final newIds = known.difference(valid.toSet());
        _insightCardOrder = [...valid, ...newIds];
      }
      if (hiddenJson != null) {
        _hiddenInsightCards = Set<String>.from(json.decode(hiddenJson) as List);
      }
    });
  }

  Future<void> _fetchData() async {
    final bookRepo = Provider.of<BookRepository>(context, listen: false);
    final tagRepo = Provider.of<TagRepository>(context, listen: false);
    final contactRepo = Provider.of<ContactRepository>(context, listen: false);
    final collectionRepo = Provider.of<CollectionRepository>(
      context,
      listen: false,
    );
    final loanRepo = Provider.of<LoanRepository>(context, listen: false);
    final api = Provider.of<ApiService>(context, listen: false);
    try {
      final books = await bookRepo.getBooks();

      // Fetch loans
      List<Loan> loans = [];
      try {
        loans = await loanRepo.getLoans();
      } catch (e) {
        debugPrint('Error fetching loans: $e');
      }

      // Fetch contacts for names
      Map<int, Contact> contactsMap = {};
      try {
        final contacts = await contactRepo.getContacts();
        for (var c in contacts) {
          if (c.id != null) {
            contactsMap[c.id!] = c;
          }
        }
      } catch (e) {
        debugPrint('Error fetching contacts: $e');
      }

      // Fetch tags (shelves)
      List<Tag> tags = [];
      try {
        tags = await tagRepo.getTags();
      } catch (e) {
        debugPrint('Error fetching tags: $e');
      }

      // Fetch collections
      List<Collection> collections = [];
      try {
        collections = await collectionRepo.getCollections();
      } catch (e) {
        debugPrint('Error fetching collections: $e');
      }

      Map<String, dynamic>? salesStats;
      if (Provider.of<ThemeProvider>(context, listen: false).isBookseller) {
        try {
          final statsRes = await api.getSalesStatistics();
          if (statsRes.statusCode == 200) {
            salesStats = statsRes.data;
          }
        } catch (e) {
          debugPrint('Error fetching sales stats: $e');
        }
      }

      // Fetch operation log stats if module is enabled
      frb.FrbOperationLogStats? opLogStats;
      List<String>? opLogEntityTypes;
      if (Provider.of<ThemeProvider>(
        context,
        listen: false,
      ).operationLogViewerEnabled) {
        try {
          opLogStats = await frb.operationLogStats();
          opLogEntityTypes = await frb.operationLogEntityTypes();
        } catch (e) {
          debugPrint('Error fetching operation log stats: $e');
        }
      }

      // Compute average rating per tag (shelf)
      final tagRatings = <_RatingGroup>[];
      try {
        final candidateTags = tags.where((t) => t.count >= 3).toList();
        for (final tag in candidateTags) {
          final tagBooks = await bookRepo.getBooks(tag: tag.name);
          final rated = tagBooks
              .where((b) => b.userRating != null && b.userRating! > 0)
              .toList();
          if (rated.length >= 3) {
            final avg =
                rated.map((b) => b.userRating!).reduce((a, b) => a + b) /
                rated.length;
            tagRatings.add(
              _RatingGroup(
                name: tag.name,
                avgRating: avg,
                ratedCount: rated.length,
              ),
            );
          }
        }
      } catch (e) {
        debugPrint('Error computing tag ratings: $e');
      }

      // Build book map for cross-referencing
      final bookMap = <int, Book>{};
      for (final b in books) {
        if (b.id != null) bookMap[b.id!] = b;
      }

      // Compute average rating per collection and read counts
      final collectionRatings = <_RatingGroup>[];
      final collectionReadCounts = <String, int>{};
      try {
        for (final col in collections) {
          final colBooks = await collectionRepo.getCollectionBooks(col.id);
          // Count read books in this collection
          final readCount = colBooks.where((cb) {
            final book = bookMap[cb.bookId];
            return book != null && book.readingStatus == 'read';
          }).length;
          collectionReadCounts[col.id] = readCount;

          // Compute rating for collections with >= 3 rated books
          if (col.totalBooks >= 3) {
            final rated = colBooks.where((cb) {
              final book = bookMap[cb.bookId];
              return book != null &&
                  book.userRating != null &&
                  book.userRating! > 0;
            }).toList();
            if (rated.length >= 3) {
              final avg =
                  rated
                      .map((cb) => bookMap[cb.bookId]!.userRating!)
                      .reduce((a, b) => a + b) /
                  rated.length;
              collectionRatings.add(
                _RatingGroup(
                  name: col.name,
                  avgRating: avg,
                  ratedCount: rated.length,
                ),
              );
            }
          }
        }
      } catch (e) {
        debugPrint('Error computing collection stats: $e');
      }

      if (mounted) {
        setState(() {
          _books = books;
          _loans = loans;
          _contactsMap = contactsMap;
          _tags = tags;
          _collections = collections;
          _salesStats = salesStats;
          _opLogStats = opLogStats;
          _opLogEntityTypes = opLogEntityTypes;
          _tagRatings = tagRatings;
          _collectionRatings = collectionRatings;
          _collectionReadCounts = collectionReadCounts;
          _isLoading = false;
        });
        _animController.forward();
      }
    } catch (e) {
      debugPrint('Error in statistics: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_books.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.analytics_outlined,
                size: 64,
                color: Color(0xFF6366F1),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              TranslationService.translate(context, 'no_books_analyze'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8),
            Text(
              TranslationService.translate(context, 'add_books_for_stats'),
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);

    // Compute collection subtitle with completion % and read %
    String? collectionSubtitle;
    if (_collections.isNotEmpty) {
      double totalCompletionRatio = 0;
      int totalOwned = 0;
      int totalRead = 0;
      for (final col in _collections) {
        if (col.totalBooks > 0) {
          totalCompletionRatio += col.ownedBooks / col.totalBooks;
        }
        totalOwned += col.ownedBooks;
        totalRead += _collectionReadCounts[col.id] ?? 0;
      }
      final avgCompletion = (totalCompletionRatio / _collections.length * 100)
          .toStringAsFixed(0);
      final readPct = totalOwned > 0
          ? (totalRead / totalOwned * 100).toStringAsFixed(0)
          : '0';
      collectionSubtitle = TranslationService.translate(
        context,
        'stat_subtitle_collections_detail',
      ).replaceAll('%1', avgCompletion).replaceAll('%2', readPct);
    }

    // Build section list, filtering out sections with no data
    final sections = <SectionConfig>[
      if (_salesStats != null)
        SectionConfig(
          id: 'sales_statistics',
          title: TranslationService.translate(context, 'sales_statistics'),
          icon: Icons.monetization_on,
          gradient: AppDesign.successGradient,
          builder: (_) => _buildSalesStatisticsSection(),
          helpText: TranslationService.translate(
            context,
            'help_ctx_stats_sales',
          ),
          subtitle: TranslationService.translate(
            context,
            'stat_subtitle_sales',
          ),
        ),
      if (_hasReadingHistory())
        SectionConfig(
          id: 'monthly_progress',
          title: TranslationService.translate(context, 'monthly_progress'),
          icon: Icons.show_chart,
          gradient: AppDesign.oceanGradient,
          builder: (_) => _buildMonthlyProgressChart(),
          helpText: TranslationService.translate(
            context,
            'help_ctx_stats_monthly_progress',
          ),
          subtitle: TranslationService.translate(
            context,
            'stat_subtitle_monthly_progress',
          ),
        ),
      SectionConfig(
        id: 'reading_insights',
        title: TranslationService.translate(context, 'reading_insights'),
        icon: Icons.insights,
        gradient: AppDesign.primaryGradient,
        builder: (_) => _buildReadingInsightsSection(),
        helpText: TranslationService.translate(
          context,
          'help_ctx_stats_unique_stats',
        ),
        subtitle: TranslationService.translate(
          context,
          'stat_subtitle_reading_insights',
        ),
      ),
      SectionConfig(
        id: 'personal_records',
        title: TranslationService.translate(context, 'personal_records'),
        icon: Icons.emoji_events,
        gradient: AppDesign.flameGradient,
        builder: (_) => _buildPersonalRecordsSection(),
        subtitle: TranslationService.translate(
          context,
          'stat_subtitle_personal_records',
        ),
      ),
      if (_hasRatingByGroupData())
        SectionConfig(
          id: 'rating_by_group',
          title: TranslationService.translate(context, 'rating_by_group'),
          icon: Icons.star_rate,
          gradient: AppDesign.warningGradient,
          builder: (_) => _buildRatingByGroupSection(),
          helpText: TranslationService.translate(
            context,
            'help_ctx_stats_rating_by_group',
          ),
          subtitle: TranslationService.translate(
            context,
            'stat_subtitle_rating_by_group',
          ),
        ),
      SectionConfig(
        id: 'reading_habits',
        title: TranslationService.translate(context, 'reading_habits'),
        icon: Icons.pie_chart,
        gradient: AppDesign.accentGradient,
        builder: (_) => _buildStatusPieChart(),
        helpText: TranslationService.translate(
          context,
          'help_ctx_stats_reading_habits',
        ),
        subtitle: TranslationService.translate(
          context,
          'stat_subtitle_reading_habits',
        ),
      ),
      SectionConfig(
        id: 'top_authors',
        title: TranslationService.translate(context, 'top_authors'),
        icon: Icons.person,
        gradient: AppDesign.cyanGradient,
        builder: (_) => _buildTopAuthorsChart(),
        helpText: TranslationService.translate(
          context,
          'help_ctx_stats_top_authors',
        ),
        subtitle: TranslationService.translate(
          context,
          'stat_subtitle_top_authors',
        ),
      ),
      SectionConfig(
        id: 'publication_timeline',
        title: TranslationService.translate(context, 'publication_timeline'),
        icon: Icons.timeline,
        gradient: AppDesign.orangeGradient,
        builder: (_) => _buildPublicationYearChart(),
        helpText: TranslationService.translate(
          context,
          'help_ctx_stats_publication_year',
        ),
        subtitle: TranslationService.translate(
          context,
          'stat_subtitle_publication_timeline',
        ),
      ),
      SectionConfig(
        id: 'loan_statistics',
        title: TranslationService.translate(context, 'loan_statistics'),
        icon: Icons.swap_horiz,
        gradient: AppDesign.pastelOceanGradient,
        builder: (_) => _buildLoanStatisticsSection(),
        helpText: TranslationService.translate(
          context,
          'help_ctx_stats_loan_stats',
        ),
        subtitle: TranslationService.translate(
          context,
          'stat_subtitle_loan_statistics',
        ),
      ),
      if (themeProvider.canBorrowBooks)
        SectionConfig(
          id: 'borrowed_statistics',
          title: TranslationService.translate(context, 'borrowed_statistics'),
          icon: Icons.arrow_downward,
          gradient: AppDesign.pastelPrimaryGradient,
          builder: (_) => _buildBorrowedStatisticsSection(),
          subtitle: TranslationService.translate(
            context,
            'stat_subtitle_borrowed_statistics',
          ),
        ),
      if (_tags.isNotEmpty)
        SectionConfig(
          id: 'shelf_statistics',
          title: TranslationService.translate(context, 'shelf_statistics'),
          icon: Icons.shelves,
          gradient: AppDesign.anthraciteGradient,
          builder: (_) => _buildShelfStatisticsSection(),
          subtitle: TranslationService.translate(
            context,
            'stat_subtitle_shelf_statistics',
          ),
        ),
      if (_collections.isNotEmpty)
        SectionConfig(
          id: 'collection_statistics',
          title: TranslationService.translate(context, 'collection_statistics'),
          icon: Icons.collections_bookmark,
          gradient: AppDesign.primaryGradient,
          builder: (_) => _buildCollectionStatisticsSection(),
          subtitle: collectionSubtitle,
        ),
      if (themeProvider.operationLogViewerEnabled && _opLogStats != null)
        SectionConfig(
          id: 'operation_log',
          title: TranslationService.translate(
            context,
            'stat_operation_log_title',
          ),
          icon: Icons.sync,
          gradient: AppDesign.cyanGradient,
          builder: (_) => _buildOperationLogStatsSection(),
          subtitle: TranslationService.translate(
            context,
            'stat_subtitle_operation_log',
          ),
        ),
    ];

    return FadeTransition(
      opacity: _fadeAnim,
      child: RefreshIndicator(
        onRefresh: _fetchData,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(
            top: 20,
            left: 16.0,
            right: 16.0,
            bottom: 16.0,
          ),
          child: ReorderableSections(
            pageKey: 'statistics',
            sections: sections,
            onEditModeChanged: (editing) {
              setState(() => _summaryEditMode = editing);
            },
            onReset: () async {
              setState(() {
                _summaryCardOrder = List.from(_defaultSummaryCardIds);
                _hiddenSummaryCards = {};
              });
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('statistics_summary_order');
              await prefs.remove('statistics_summary_hidden');
            },
            header: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [_buildSummaryCards(), const SizedBox(height: 16)],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final totalBooks = _books.length;
    final readBooks = _books.where((b) => b.readingStatus == 'read').length;
    final uniqueAuthors = _books
        .where((b) => b.author != null && b.author!.isNotEmpty)
        .map((b) => b.author!)
        .toSet()
        .length;
    final completionRate = totalBooks > 0
        ? (readBooks / totalBooks * 100).toStringAsFixed(0)
        : '0';
    final booksWithYears = _books
        .where((b) => b.publicationYear != null && b.publicationYear! > 1800)
        .toList();
    final oldestYear = booksWithYears.isEmpty
        ? null
        : booksWithYears
              .map((b) => b.publicationYear!)
              .reduce((a, b) => a < b ? a : b);

    // Show borrowed count if borrowing is enabled, otherwise show loan count
    final String thirdCardLabel;
    final String thirdCardValue;
    final IconData thirdCardIcon;
    if (themeProvider.canBorrowBooks) {
      final borrowedBooks = _books.where((b) => !b.owned).length;
      thirdCardLabel = TranslationService.translate(context, 'stat_borrowed');
      thirdCardValue = borrowedBooks.toString();
      thirdCardIcon = Icons.people;
    } else {
      final activeLoans = _loans.where((l) => l.returnDate == null).length;
      thirdCardLabel = TranslationService.translate(context, 'stat_loans');
      thirdCardValue = activeLoans.toString();
      thirdCardIcon = Icons.swap_horiz;
    }

    final cardWidgets = <String, Widget>{
      'total_books': _buildStatCard(
        TranslationService.translate(context, 'stat_total_books'),
        totalBooks.toString(),
        Icons.library_books,
        Colors.transparent,
        gradient: AppDesign.oceanGradient,
        textColor: Colors.white,
      ),
      'read_books': _buildStatCard(
        TranslationService.translate(context, 'stat_read'),
        readBooks.toString(),
        Icons.check_circle,
        Colors.transparent,
        gradient: AppDesign.successGradient,
        textColor: Colors.white,
      ),
      'borrowed_books': _buildStatCard(
        thirdCardLabel,
        thirdCardValue,
        thirdCardIcon,
        Colors.transparent,
        gradient: AppDesign.flameGradient,
        textColor: Colors.white,
      ),
      'unique_authors': _buildStatCard(
        TranslationService.translate(context, 'stat_unique_authors'),
        uniqueAuthors.toString(),
        Icons.person_outline,
        Colors.transparent,
        gradient: AppDesign.orangeGradient,
        textColor: Colors.white,
      ),
      'completion': _buildStatCard(
        TranslationService.translate(context, 'stat_completion'),
        "$completionRate%",
        Icons.trending_up,
        Colors.transparent,
        gradient: AppDesign.primaryGradient,
        textColor: Colors.white,
      ),
      'oldest_book': _buildStatCard(
        TranslationService.translate(context, 'stat_oldest_book'),
        oldestYear?.toString() ?? "N/A",
        Icons.history,
        Colors.transparent,
        gradient: AppDesign.anthraciteGradient,
        textColor: Colors.white,
      ),
    };

    final cardLabels = <String, String>{
      'total_books': TranslationService.translate(context, 'stat_total_books'),
      'read_books': TranslationService.translate(context, 'stat_read'),
      'borrowed_books': thirdCardLabel,
      'unique_authors': TranslationService.translate(
        context,
        'stat_unique_authors',
      ),
      'completion': TranslationService.translate(context, 'stat_completion'),
      'oldest_book': TranslationService.translate(context, 'stat_oldest_book'),
    };

    final cardIcons = <String, IconData>{
      'total_books': Icons.library_books,
      'read_books': Icons.check_circle,
      'borrowed_books': thirdCardIcon,
      'unique_authors': Icons.person_outline,
      'completion': Icons.trending_up,
      'oldest_book': Icons.history,
    };

    final theme = Theme.of(context);

    if (_summaryEditMode) {
      return _buildCardEditMode(
        order: _summaryCardOrder,
        hidden: _hiddenSummaryCards,
        labels: cardLabels,
        icons: cardIcons,
        onReorder: (oldIndex, newIndex) {
          setState(() {
            if (newIndex > oldIndex) newIndex -= 1;
            final id = _summaryCardOrder.removeAt(oldIndex);
            _summaryCardOrder.insert(newIndex, id);
          });
          _saveSummaryOrder();
        },
        onToggle: (id) {
          setState(() {
            if (_hiddenSummaryCards.contains(id)) {
              _hiddenSummaryCards.remove(id);
            } else {
              _hiddenSummaryCards.add(id);
            }
          });
          _saveSummaryHidden();
        },
        theme: theme,
      );
    }

    // Normal mode: rows of 2
    final visibleIds = _summaryCardOrder
        .where((id) => !_hiddenSummaryCards.contains(id))
        .toList();

    final rows = <Widget>[];
    for (var i = 0; i < visibleIds.length; i += 2) {
      final children = <Widget>[];
      for (var j = 0; j < 2; j++) {
        if (j > 0) children.add(const SizedBox(width: 12));
        if (i + j < visibleIds.length) {
          children.add(
            Expanded(
              child: cardWidgets[visibleIds[i + j]] ?? const SizedBox.shrink(),
            ),
          );
        } else {
          children.add(const Expanded(child: SizedBox.shrink()));
        }
      }
      rows.add(Row(children: children));
    }

    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          rows[i],
        ],
      ],
    );
  }

  /// Shared edit mode UI for card grids (summary cards, insight cards).
  Widget _buildCardEditMode({
    required List<String> order,
    required Set<String> hidden,
    required Map<String, String> labels,
    required Map<String, IconData> icons,
    required void Function(int, int) onReorder,
    required void Function(String) onToggle,
    required ThemeData theme,
  }) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            TranslationService.translate(context, 'sections_drag_hint'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: order.length,
          onReorder: onReorder,
          itemBuilder: (context, index) {
            final id = order[index];
            final isHidden = hidden.contains(id);
            final isDark = theme.brightness == Brightness.dark;
            return Opacity(
              key: ValueKey(id),
              opacity: isHidden ? 0.4 : 1.0,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Material(
                  color: isDark
                      ? theme.colorScheme.surfaceContainerHighest
                      : theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        ReorderableDragStartListener(
                          index: index,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Icon(
                              Icons.drag_handle,
                              color: theme.colorScheme.onSurfaceVariant,
                              size: 20,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(icons[id] ?? Icons.help_outline, size: 16),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            labels[id] ?? id,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            isHidden
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            size: 20,
                          ),
                          tooltip: TranslationService.translate(
                            context,
                            'tooltip_toggle_section',
                          ),
                          onPressed: () => onToggle(id),
                          color: isHidden
                              ? theme.colorScheme.onSurfaceVariant
                              : theme.colorScheme.primary,
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildStatusPieChart() {
    final statusCounts = <String, int>{};
    for (var book in _books) {
      final status = book.readingStatus ?? 'unknown';
      statusCounts[status] = (statusCounts[status] ?? 0) + 1;
    }

    final colors = {
      'read': const Color(0xFF10B981),
      'reading': const Color(0xFF0EA5E9),
      'to_read': const Color(0xFFF59E0B),
      'wanting': const Color(0xFFEC4899),
      'abandoned': const Color(0xFFEF4444),
      'owned': const Color(0xFF607D8B),
      'borrowed': const Color(0xFF8B5CF6),
      'unknown': Colors.grey,
    };

    final List<PieChartSectionData> sections = [];
    statusCounts.forEach((status, count) {
      final color = colors[status] ?? Colors.grey;
      final percentage = (count / _books.length * 100).toStringAsFixed(0);
      sections.add(
        PieChartSectionData(
          color: color,
          value: count.toDouble(),
          title: '$percentage%',
          radius: 70,
          titleStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      );
    });

    final chartDescription = statusCounts.entries
        .map((e) => '${_formatStatusLabel(e.key)}: ${e.value}')
        .join(', ');

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
        boxShadow: AppDesign.cardShadow,
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Semantics(
            label:
                '${TranslationService.translate(context, 'stat_a11y_reading_status_chart')}: $chartDescription',
            child: ExcludeSemantics(
              child: SizedBox(
                height: 200,
                child: PieChart(
                  PieChartData(
                    sections: sections,
                    centerSpaceRadius: 50,
                    sectionsSpace: 3,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          Wrap(
            spacing: 16,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: statusCounts.entries.map((e) {
              final color = colors[e.key] ?? Colors.grey;
              final label = _formatStatusLabel(e.key);
              return _buildLegendItem(color, label, e.value);
            }).toList(),
          ),
        ],
      ),
    );
  }

  String _formatStatusLabel(String status) {
    switch (status) {
      case 'read':
        return TranslationService.translate(context, 'reading_status_read');
      case 'reading':
        return TranslationService.translate(context, 'reading_status_reading');
      case 'to_read':
        return TranslationService.translate(context, 'reading_status_to_read');
      case 'wanting':
        return TranslationService.translate(context, 'reading_status_wanting');
      case 'abandoned':
        return TranslationService.translate(
          context,
          'reading_status_abandoned',
        );
      case 'owned':
        return TranslationService.translate(context, 'owned_status');
      case 'lent':
        return TranslationService.translate(context, 'reading_status_lent');
      case 'borrowed':
        return TranslationService.translate(context, 'reading_status_borrowed');
      default:
        return status.replaceAll('_', ' ');
    }
  }

  Widget _buildLegendItem(Color color, String label, int count) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$label ($count)',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildTopAuthorsChart() {
    final authorCounts = <String, int>{};
    for (var book in _books) {
      if (book.author != null && book.author!.isNotEmpty) {
        authorCounts[book.author!] = (authorCounts[book.author!] ?? 0) + 1;
      }
    }

    var sortedAuthors = authorCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (sortedAuthors.length > 10) {
      sortedAuthors = sortedAuthors.sublist(0, 10);
    }

    if (sortedAuthors.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
          boxShadow: AppDesign.cardShadow,
        ),
        child: Center(
          child: Text(TranslationService.translate(context, 'no_author_data')),
        ),
      );
    }

    final maxCount = sortedAuthors.first.value;
    final theme = Theme.of(context);
    final authorsDescription = sortedAuthors
        .map((e) => '${e.key}: ${e.value}')
        .join(', ');

    return Semantics(
      label:
          '${TranslationService.translate(context, 'stat_a11y_top_authors_chart')}: $authorsDescription',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
            boxShadow: AppDesign.cardShadow,
          ),
          child: Column(
            children: [
              for (var i = 0; i < sortedAuthors.length; i++) ...[
                if (i > 0) const SizedBox(height: 6),
                _buildAuthorLeaderboardRow(
                  rank: i + 1,
                  name: sortedAuthors[i].key,
                  count: sortedAuthors[i].value,
                  maxCount: maxCount,
                  theme: theme,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAuthorLeaderboardRow({
    required int rank,
    required String name,
    required int count,
    required int maxCount,
    required ThemeData theme,
  }) {
    final fraction = maxCount > 0 ? count / maxCount : 0.0;
    final podiumColors = [
      const Color(0xFFF59E0B), // gold
      const Color(0xFF94A3B8), // silver
      const Color(0xFFCD7F32), // bronze
    ];
    final barColor = rank <= 3
        ? podiumColors[rank - 1]
        : theme.colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: rank <= 3
                ? Icon(
                    Icons.emoji_events,
                    size: 18,
                    color: podiumColors[rank - 1],
                  )
                : Text(
                    '$rank',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: Text(
              name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: rank <= 3 ? FontWeight.w600 : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 14,
                backgroundColor: theme.colorScheme.onSurface.withValues(
                  alpha: 0.06,
                ),
                valueColor: AlwaysStoppedAnimation<Color>(
                  barColor.withValues(alpha: 0.7),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 32,
            child: Text(
              '$count',
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: barColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPublicationYearChart() {
    final yearCounts = <int, int>{};
    for (var book in _books) {
      if (book.publicationYear != null && book.publicationYear! > 1800) {
        final decade = (book.publicationYear! ~/ 10) * 10;
        yearCounts[decade] = (yearCounts[decade] ?? 0) + 1;
      }
    }

    final sortedYears = yearCounts.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    if (sortedYears.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
          boxShadow: AppDesign.cardShadow,
        ),
        child: Center(
          child: Text(
            TranslationService.translate(context, 'no_pub_year_data'),
          ),
        ),
      );
    }

    final timelineDescription = sortedYears
        .map((e) => '${e.key}s: ${e.value}')
        .join(', ');

    return Semantics(
      label:
          '${TranslationService.translate(context, 'stat_a11y_publication_timeline')}: $timelineDescription',
      child: ExcludeSemantics(
        child: Container(
          height: 280,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
            boxShadow: AppDesign.cardShadow,
          ),
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: 1,
                getDrawingHorizontalLine: (value) {
                  return FlLine(
                    color: Colors.black.withValues(alpha: 0.5),
                    strokeWidth: 1,
                  );
                },
              ),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final index = value.toInt();
                      if (index >= 0 && index < sortedYears.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            sortedYears[index].key.toString(),
                            style: const TextStyle(fontSize: 10),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                    interval: 1,
                    reservedSize: 30,
                  ),
                ),
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  spots: sortedYears.asMap().entries.map((e) {
                    return FlSpot(e.key.toDouble(), e.value.value.toDouble());
                  }).toList(),
                  isCurved: true,
                  gradient: AppDesign.oceanGradient,
                  barWidth: 4,
                  isStrokeCapRound: true,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, barData, index) {
                      return FlDotCirclePainter(
                        radius: 5,
                        color: const Color(0xFF0EA5E9),
                        strokeWidth: 2,
                        strokeColor: Colors.white,
                      );
                    },
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF0EA5E9).withValues(alpha: 0.3),
                        const Color(0xFF0EA5E9).withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ],
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (touchedSpot) => const Color(0xFF1E293B),
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((spot) {
                      final year = sortedYears[spot.x.toInt()].key;
                      return LineTooltipItem(
                        '${year}s\n',
                        const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        children: [
                          TextSpan(
                            text:
                                '${spot.y.toInt()} ${TranslationService.translate(context, 'stat_chart_books_count')}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      );
                    }).toList();
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // === UNIQUE STATISTICS METHODS ===

  bool _hasReadingHistory() {
    return _books.any((b) => b.finishedReadingAt != null);
  }

  Widget _buildMonthlyProgressChart() {
    // Get books read in the last 12 months
    final now = DateTime.now();
    final monthlyData = <String, int>{};

    for (int i = 11; i >= 0; i--) {
      final month = DateTime(now.year, now.month - i, 1);
      final key = DateFormat('MMM').format(month);
      monthlyData[key] = 0;
    }

    for (var book in _books) {
      if (book.finishedReadingAt != null) {
        final finishedDate = book.finishedReadingAt!;
        final monthsDiff =
            (now.year - finishedDate.year) * 12 +
            (now.month - finishedDate.month);
        if (monthsDiff >= 0 && monthsDiff < 12) {
          final key = DateFormat('MMM').format(finishedDate);
          if (monthlyData.containsKey(key)) {
            monthlyData[key] = monthlyData[key]! + 1;
          }
        }
      }
    }

    final sortedData = monthlyData.entries.toList();
    final maxValue = sortedData
        .map((e) => e.value)
        .reduce((a, b) => a > b ? a : b);

    final monthlyDescription = sortedData
        .where((e) => e.value > 0)
        .map((e) => '${e.key}: ${e.value}')
        .join(', ');

    return Semantics(
      label:
          '${TranslationService.translate(context, 'stat_a11y_monthly_progress_chart')}: $monthlyDescription',
      child: ExcludeSemantics(
        child: Container(
          height: 220,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
            boxShadow: AppDesign.cardShadow,
          ),
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: (maxValue + 1).toDouble(),
              barTouchData: BarTouchData(
                enabled: true,
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (group) => const Color(0xFF1E293B),
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    return BarTooltipItem(
                      '${sortedData[groupIndex].key}: ${rod.toY.toInt()} ${TranslationService.translate(context, 'books')}',
                      const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      if (value.toInt() >= sortedData.length)
                        return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          sortedData[value.toInt()].key,
                          style: const TextStyle(fontSize: 11),
                        ),
                      );
                    },
                    reservedSize: 30,
                  ),
                ),
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              barGroups: sortedData.asMap().entries.map((e) {
                final isCurrentMonth = e.key == sortedData.length - 1;
                return BarChartGroupData(
                  x: e.key,
                  barRods: [
                    BarChartRodData(
                      toY: e.value.value.toDouble(),
                      gradient: isCurrentMonth
                          ? AppDesign.accentGradient
                          : AppDesign.primaryGradient,
                      width: 16,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(4),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReadingInsightsSection() {
    // Compute all card data
    final booksWithDuration = _books
        .where(
          (b) =>
              b.startedReadingAt != null &&
              b.finishedReadingAt != null &&
              b.finishedReadingAt!.isAfter(b.startedReadingAt!),
        )
        .toList();

    double avgDays = 0;
    if (booksWithDuration.isNotEmpty) {
      final totalDays = booksWithDuration
          .map(
            (b) => b.finishedReadingAt!.difference(b.startedReadingAt!).inDays,
          )
          .reduce((a, b) => a + b);
      avgDays = totalDays / booksWithDuration.length;
    }

    final currentYear = DateTime.now().year;
    final booksFinishedThisYear = _books
        .where(
          (b) =>
              b.finishedReadingAt != null &&
              b.finishedReadingAt!.year == currentYear,
        )
        .length;

    final totalPagesRead = totalPagesReadFromFinishedBooks(_books);

    DateTime? lastFinished;
    for (final book in _books) {
      if (book.finishedReadingAt != null) {
        if (lastFinished == null ||
            book.finishedReadingAt!.isAfter(lastFinished)) {
          lastFinished = book.finishedReadingAt;
        }
      }
    }
    final int? daysSinceLast = lastFinished != null
        ? DateTime.now().difference(lastFinished).inDays
        : null;

    // Card definitions keyed by ID
    final cardWidgets = <String, Widget>{
      'avg_reading_time': _buildInsightCard(
        Icons.timer,
        avgDays > 0 ? avgDays.toStringAsFixed(0) : null,
        TranslationService.translate(context, 'avg_reading_time'),
        TranslationService.translate(context, 'days'),
        const Color(0xFF0EA5E9),
        description: avgDays > 0
            ? TranslationService.translate(
                context,
                'avg_reading_time_desc',
              ).replaceAll('%1', '${booksWithDuration.length}')
            : null,
      ),
      'total_pages': _buildInsightCard(
        Icons.auto_stories,
        totalPagesRead > 0 ? totalPagesRead.toString() : null,
        TranslationService.translate(context, 'total_pages_read'),
        TranslationService.translate(context, 'pages_suffix'),
        const Color(0xFF8B5CF6),
        description: totalPagesRead > 0
            ? TranslationService.translate(context, 'total_pages_read_desc')
            : null,
      ),
      'books_finished_year': _buildInsightCard(
        Icons.calendar_today,
        booksFinishedThisYear > 0 ? booksFinishedThisYear.toString() : null,
        TranslationService.translate(context, 'books_finished_year'),
        TranslationService.translate(context, 'books_suffix'),
        const Color(0xFFF97316),
        description: booksFinishedThisYear > 0
            ? TranslationService.translate(
                context,
                'books_finished_year_desc',
              ).replaceAll('%1', '$currentYear')
            : null,
      ),
      'days_since_last': _buildInsightCard(
        Icons.schedule,
        daysSinceLast != null ? daysSinceLast.toString() : null,
        TranslationService.translate(context, 'days_since_last'),
        TranslationService.translate(context, 'days_ago_suffix'),
        const Color(0xFF14B8A6),
        description: daysSinceLast != null
            ? TranslationService.translate(context, 'days_since_last_desc')
            : null,
      ),
    };

    // Render visible cards in user-defined order, rows of 2
    final visibleIds = _insightCardOrder
        .where((id) => !_hiddenInsightCards.contains(id))
        .toList();

    final rows = <Widget>[];
    for (var i = 0; i < visibleIds.length; i += 2) {
      final first = cardWidgets[visibleIds[i]];
      final second = i + 1 < visibleIds.length
          ? cardWidgets[visibleIds[i + 1]]
          : null;
      rows.add(
        Row(
          children: [
            Expanded(child: first ?? const SizedBox.shrink()),
            const SizedBox(width: 12),
            Expanded(child: second ?? const SizedBox.shrink()),
          ],
        ),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          rows[i],
        ],
      ],
    );
  }

  Widget _buildPersonalRecordsSection() {
    final booksWithDuration = _books
        .where(
          (b) =>
              b.startedReadingAt != null &&
              b.finishedReadingAt != null &&
              b.finishedReadingAt!.isAfter(b.startedReadingAt!),
        )
        .toList();

    int? fastestDays;
    String? fastestBookTitle;
    int? fastestBookId;
    for (var book in booksWithDuration) {
      final days = book.finishedReadingAt!
          .difference(book.startedReadingAt!)
          .inDays;
      if (fastestDays == null || days < fastestDays) {
        fastestDays = days;
        fastestBookTitle = book.title;
        fastestBookId = book.id;
      }
    }

    final readingStreak = _calculateReadingStreak();

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildInsightCard(
                Icons.speed,
                fastestDays != null ? fastestDays.toString() : null,
                TranslationService.translate(context, 'fastest_read'),
                TranslationService.translate(context, 'days'),
                const Color(0xFF10B981),
                description: fastestDays != null
                    ? TranslationService.translate(context, 'fastest_read_desc')
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildInsightCard(
                Icons.local_fire_department,
                readingStreak > 0 ? readingStreak.toString() : null,
                TranslationService.translate(context, 'reading_streak'),
                TranslationService.translate(context, 'reading_streak_suffix'),
                const Color(0xFFEF4444),
                description: readingStreak > 0
                    ? TranslationService.translate(
                        context,
                        'reading_streak_desc',
                      )
                    : null,
              ),
            ),
          ],
        ),
        if (fastestBookTitle != null) ...[
          const SizedBox(height: 12),
          _buildBookMention(
            context: context,
            icon: Icons.speed,
            label: TranslationService.translate(context, 'fastest_book'),
            bookTitle: fastestBookTitle,
            bookId: fastestBookId,
            color: const Color(0xFF10B981),
          ),
        ],
      ],
    );
  }

  /// Calculates the current reading streak: consecutive days (counting
  /// backwards from today) where at least one book was "in progress".
  /// A book is in progress on a given day if:
  ///   - startedReadingAt <= day <= finishedReadingAt, OR
  ///   - readingStatus == 'reading' and startedReadingAt <= day (no end date)
  int _calculateReadingStreak() {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);

    int streak = 0;
    for (int offset = 0; offset < 365; offset++) {
      final day = todayDate.subtract(Duration(days: offset));
      bool hasBookInProgress = false;

      for (final book in _books) {
        if (book.startedReadingAt == null) continue;
        final start = DateTime(
          book.startedReadingAt!.year,
          book.startedReadingAt!.month,
          book.startedReadingAt!.day,
        );

        if (start.isAfter(day)) continue;

        if (book.finishedReadingAt != null) {
          final end = DateTime(
            book.finishedReadingAt!.year,
            book.finishedReadingAt!.month,
            book.finishedReadingAt!.day,
          );
          if (!day.isAfter(end)) {
            hasBookInProgress = true;
            break;
          }
        } else if (book.readingStatus == 'reading') {
          hasBookInProgress = true;
          break;
        }
      }

      if (hasBookInProgress) {
        streak++;
      } else {
        break;
      }
    }
    return streak;
  }

  Widget _buildBookMention({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String bookTitle,
    int? bookId,
    required Color color,
  }) {
    return Semantics(
      button: bookId != null,
      label: TranslationService.translate(
        context,
        'stat_a11y_view_book',
      ).replaceAll('%1', bookTitle),
      child: InkWell(
        onTap: bookId != null ? () => context.push('/books/$bookId') : null,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 8),
              Text(
                '$label: ',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              Expanded(
                child: Text(
                  bookTitle,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                    decoration: bookId != null
                        ? TextDecoration.underline
                        : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInsightCard(
    IconData icon,
    String? value,
    String label,
    String suffix,
    Color color, {
    bool useStarDisplay = false,
    String? helpText,
    String? description,
  }) {
    final bool isEmpty = value == null;
    final double? ratingValue = isEmpty ? null : double.tryParse(value);
    final double starRating = useStarDisplay && ratingValue != null
        ? (ratingValue / 2.0).clamp(0.0, 5.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
        boxShadow: AppDesign.subtleShadow,
        border: Border(
          left: BorderSide(
            color: color.withValues(alpha: isEmpty ? 0.2 : 0.6),
            width: 3,
          ),
        ),
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: isEmpty ? Colors.grey[400] : color, size: 22),
              const SizedBox(height: 10),
              if (isEmpty)
                Text(
                  TranslationService.translate(context, 'insight_no_data'),
                  style: TextStyle(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey[400],
                  ),
                )
              else if (useStarDisplay && ratingValue != null)
                Semantics(
                  label: TranslationService.translate(
                    context,
                    'stat_a11y_star_rating',
                  ).replaceAll('%1', starRating.toStringAsFixed(1)),
                  excludeSemantics: true,
                  child: Row(
                    children: List.generate(5, (index) {
                      final starIndex = index + 1;
                      IconData iconData;
                      if (starIndex <= starRating) {
                        iconData = Icons.star;
                      } else if (starIndex - 0.5 <= starRating) {
                        iconData = Icons.star_half;
                      } else {
                        iconData = Icons.star_outline;
                      }
                      return Icon(iconData, size: 16, color: color);
                    }),
                  ),
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Text(
                        value,
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: color,
                          height: 1.0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(
                        suffix,
                        style: TextStyle(
                          fontSize: 13,
                          color: color.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (description != null) ...[
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
          if (helpText != null)
            Positioned(
              right: 0,
              top: 0,
              child: Tooltip(
                message: helpText,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle: const TextStyle(color: Colors.white, fontSize: 12),
                triggerMode: TooltipTriggerMode.tap,
                child: Icon(
                  Icons.info_outline,
                  color: color.withValues(alpha: 0.5),
                  size: 16,
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool _hasRatingByGroupData() {
    return _tagRatings.length + _collectionRatings.length >= 2;
  }

  Widget _buildRatingByGroupSection() {
    final sortedTagRatings = List<_RatingGroup>.from(_tagRatings)
      ..sort((a, b) => b.avgRating.compareTo(a.avgRating));
    final sortedCollectionRatings = List<_RatingGroup>.from(_collectionRatings)
      ..sort((a, b) => b.avgRating.compareTo(a.avgRating));

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
        boxShadow: AppDesign.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sortedTagRatings.isNotEmpty) ...[
            Text(
              TranslationService.translate(context, 'rating_by_group_shelves'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 12),
            ...sortedTagRatings.map((group) => _buildRatingGroupRow(group)),
          ],
          if (sortedTagRatings.isNotEmpty && sortedCollectionRatings.isNotEmpty)
            const SizedBox(height: 20),
          if (sortedCollectionRatings.isNotEmpty) ...[
            Text(
              TranslationService.translate(
                context,
                'rating_by_group_collections',
              ),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 12),
            ...sortedCollectionRatings.map(
              (group) => _buildRatingGroupRow(group),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRatingGroupRow(_RatingGroup group) {
    final starRating = (group.avgRating / 2.0).clamp(0.0, 5.0);
    const starColor = Color(0xFFF59E0B);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        label:
            '${group.name}, ${TranslationService.translate(context, 'stat_a11y_star_rating').replaceAll('%1', starRating.toStringAsFixed(1))}, ${TranslationService.translate(context, 'rating_by_group_rated_books').replaceAll('%1', '${group.ratedCount}')}',
        excludeSemantics: true,
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(
                group.name,
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(5, (index) {
                final starIndex = index + 1;
                IconData iconData;
                if (starIndex <= starRating) {
                  iconData = Icons.star;
                } else if (starIndex - 0.5 <= starRating) {
                  iconData = Icons.star_half;
                } else {
                  iconData = Icons.star_outline;
                }
                return Icon(iconData, size: 14, color: starColor);
              }),
            ),
            const SizedBox(width: 6),
            Text(
              starRating.toStringAsFixed(1),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: starColor,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              TranslationService.translate(
                context,
                'rating_by_group_rated_books',
              ).replaceAll('%1', '${group.ratedCount}'),
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShelfStatisticsSection() {
    final totalShelves = _tags.length;
    final totalBooksInShelves = _tags.fold<int>(
      0,
      (sum, tag) => sum + tag.count,
    );

    var topShelves = _tags.toList()..sort((a, b) => b.count.compareTo(a.count));
    if (topShelves.length > 5) topShelves = topShelves.sublist(0, 5);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
        boxShadow: AppDesign.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildMiniStat(
                  TranslationService.translate(context, 'total_shelves'),
                  totalShelves.toString(),
                  Icons.shelves,
                  const Color(0xFFF59E0B),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMiniStat(
                  TranslationService.translate(context, 'books_in_shelves'),
                  totalBooksInShelves.toString(),
                  Icons.menu_book,
                  const Color(0xFFD97706),
                ),
              ),
            ],
          ),
          if (topShelves.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              TranslationService.translate(context, 'top_shelves'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 12),
            ...topShelves.map(
              (tag) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.label_outline,
                      size: 18,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        tag.name,
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFB45309).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${tag.count}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFFB45309),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCollectionStatisticsSection() {
    final collections = _collections;
    final totalCollections = collections.length;
    double avgCompletion = 0;
    int completedCount = 0;

    if (collections.isNotEmpty) {
      final totalCompletion = collections.fold<double>(0, (sum, collection) {
        if (collection.totalBooks == 0) return sum;
        final ratio = collection.ownedBooks / collection.totalBooks;
        if (ratio >= 1.0) completedCount++;
        return sum + ratio;
      });
      avgCompletion = (totalCompletion / totalCollections) * 100;
    }

    final theme = Theme.of(context);

    // Sort by owned ratio descending
    final sorted = collections.toList()
      ..sort((a, b) {
        final ratioA = a.totalBooks > 0 ? a.ownedBooks / a.totalBooks : 0.0;
        final ratioB = b.totalBooks > 0 ? b.ownedBooks / b.totalBooks : 0.0;
        return ratioB.compareTo(ratioA);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Summary row: total, avg completion, completed
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                TranslationService.translate(context, 'stat_total_collections'),
                totalCollections.toString(),
                Icons.collections_bookmark,
                Colors.transparent,
                gradient: AppDesign.primaryGradient,
                textColor: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                TranslationService.translate(
                  context,
                  'stat_avg_collection_completion',
                ),
                '${avgCompletion.toStringAsFixed(1)}%',
                Icons.pie_chart_outline,
                Colors.transparent,
                gradient: AppDesign.oceanGradient,
                textColor: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                TranslationService.translate(
                  context,
                  'stat_completed_collections',
                ),
                completedCount.toString(),
                Icons.check_circle_outline,
                Colors.transparent,
                gradient: AppDesign.successGradient,
                textColor: Colors.white,
              ),
            ),
          ],
        ),
        if (sorted.isNotEmpty) ...[
          const SizedBox(height: 20),
          // Collection list with progress bars
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
              boxShadow: AppDesign.cardShadow,
            ),
            child: Column(
              children: [
                for (var i = 0; i < sorted.length; i++) ...[
                  if (i > 0) const SizedBox(height: 14),
                  _buildCollectionProgressRow(sorted[i], theme),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCollectionProgressRow(Collection col, ThemeData theme) {
    final total = col.totalBooks;
    final owned = col.ownedBooks;
    final ratio = total > 0 ? owned / total : 0.0;
    final readCount = _collectionReadCounts[col.id] ?? 0;
    final isComplete = ratio >= 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              isComplete ? Icons.check_circle : Icons.bookmark_outline,
              size: 16,
              color: isComplete
                  ? const Color(0xFF10B981)
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                col.name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '$owned / $total',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 6,
                  backgroundColor: theme.colorScheme.onSurface.withValues(
                    alpha: 0.08,
                  ),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isComplete
                        ? const Color(0xFF10B981)
                        : const Color(0xFF0EA5E9),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '${(ratio * 100).toStringAsFixed(0)}%',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: isComplete
                    ? const Color(0xFF10B981)
                    : theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
        if (readCount > 0) ...[
          const SizedBox(height: 2),
          Text(
            TranslationService.translate(
              context,
              'stat_collection_read',
            ).replaceAll('%1', readCount.toString()),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildLoanStatisticsSection() {
    final stats = LoanStatistics.fromLoans(_loans);

    final borrowerCounts = <String, int>{};
    for (var loan in _loans) {
      String contactName = TranslationService.translate(
        context,
        'stat_unknown_contact',
      );

      if (_contactsMap.containsKey(loan.contactId)) {
        final contact = _contactsMap[loan.contactId]!;
        contactName = contact.fullName;
      } else if (loan.contactName.isNotEmpty) {
        contactName = loan.contactName;
      }

      borrowerCounts[contactName] = (borrowerCounts[contactName] ?? 0) + 1;
    }
    var topBorrowers = borrowerCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (topBorrowers.length > 5) topBorrowers = topBorrowers.sublist(0, 5);

    final bookCounts = <String, int>{};
    for (var loan in _loans) {
      final bookTitle = loan.bookTitle.isNotEmpty
          ? loan.bookTitle
          : TranslationService.translate(context, 'stat_unknown_contact');
      bookCounts[bookTitle] = (bookCounts[bookTitle] ?? 0) + 1;
    }
    var mostLentBooks = bookCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (mostLentBooks.length > 5) mostLentBooks = mostLentBooks.sublist(0, 5);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
        boxShadow: AppDesign.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildMiniStat(
                  TranslationService.translate(context, 'total_loans'),
                  stats.total.toString(),
                  Icons.swap_horiz,
                  const Color(0xFF8B4513),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMiniStat(
                  TranslationService.translate(context, 'active_loans'),
                  stats.active.toString(),
                  Icons.arrow_upward,
                  Colors.orange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMiniStat(
                  TranslationService.translate(context, 'return_rate'),
                  formatReturnRate(stats.returnRatePercent),
                  Icons.check_circle,
                  Colors.green,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMiniStat(
                  TranslationService.translate(context, 'avg_duration'),
                  formatAvgDuration(
                    stats.avgDurationDays,
                    lessThanOneDayLabel: TranslationService.translate(
                      context,
                      'avg_duration_under_one_day',
                    ),
                  ),
                  Icons.timer,
                  const Color(0xFFA16207),
                ),
              ),
            ],
          ),
          if (topBorrowers.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              TranslationService.translate(context, 'top_borrowers'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 12),
            ...topBorrowers.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.person_outline,
                      size: 18,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        e.key,
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B4513).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${e.value} ${TranslationService.translate(context, 'loans_label')}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF8B4513),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (mostLentBooks.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              TranslationService.translate(context, 'most_lent_books'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 12),
            ...mostLentBooks.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.menu_book, size: 18, color: Colors.grey),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        e.key,
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFA16207).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${e.value}x',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFFA16207),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMiniStat(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
        border: Border.all(color: color.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppDesign.radiusSmall),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildBorrowedStatisticsSection() {
    final borrowedBooks = _books.where((b) => !b.owned).toList();
    final totalBorrowed = borrowedBooks.length;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
        boxShadow: AppDesign.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildMiniStat(
                  TranslationService.translate(context, 'books_borrowed'),
                  totalBorrowed.toString(),
                  Icons.arrow_downward,
                  Colors.teal,
                ),
              ),
            ],
          ),
          if (borrowedBooks.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(
              TranslationService.translate(context, 'borrowed_books_list'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 12),
            ...borrowedBooks
                .take(5)
                .map(
                  (book) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.menu_book,
                          size: 18,
                          color: Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                book.title,
                                style: const TextStyle(fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (book.author != null)
                                Text(
                                  book.author!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[600],
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ] else ...[
            const SizedBox(height: 16),
            Center(
              child: Text(
                TranslationService.translate(context, 'no_borrowed_books'),
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOperationLogStatsSection() {
    final stats = _opLogStats!;
    final entityTypes = _opLogEntityTypes ?? [];

    // Health status
    final hasFailed = stats.failed > BigInt.zero;
    final hasPending = stats.pending > BigInt.zero;
    Color healthColor;
    String healthMessage;
    if (hasFailed) {
      healthColor = Colors.red;
      healthMessage = TranslationService.translate(
        context,
        'stat_oplog_health_error',
      ).replaceAll('%1', stats.failed.toString());
    } else if (hasPending) {
      healthColor = Colors.orange;
      healthMessage = TranslationService.translate(
        context,
        'stat_oplog_health_warning',
      ).replaceAll('%1', stats.pending.toString());
    } else {
      healthColor = Colors.green;
      healthMessage = TranslationService.translate(
        context,
        'stat_oplog_health_ok',
      );
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
        boxShadow: AppDesign.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mini stats row
          Row(
            children: [
              Expanded(
                child: _buildMiniStat(
                  'Total',
                  stats.total.toString(),
                  Icons.sync,
                  const Color(0xFF6366F1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMiniStat(
                  TranslationService.translate(context, 'today'),
                  stats.today.toString(),
                  Icons.today,
                  const Color(0xFF0EA5E9),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMiniStat(
                  TranslationService.translate(context, 'stat_oplog_pending'),
                  stats.pending.toString(),
                  Icons.pending_actions,
                  Colors.orange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMiniStat(
                  TranslationService.translate(context, 'errors'),
                  stats.failed.toString(),
                  Icons.error_outline,
                  Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Health indicator
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: healthColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  healthMessage,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          if (entityTypes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              '${entityTypes.length} ${TranslationService.translate(context, 'stat_oplog_entity_types')}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
          const SizedBox(height: 16),
          // Link to operation log
          InkWell(
            onTap: () => context.push('/operation-log'),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.arrow_forward,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    TranslationService.translate(
                      context,
                      'stat_oplog_view_details',
                    ),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSalesStatisticsSection() {
    if (_salesStats == null) return const SizedBox.shrink();

    final totalRevenue =
        (_salesStats!['total_revenue'] as num?)?.toDouble() ?? 0.0;
    final totalSales = (_salesStats!['total_sales'] as num?)?.toInt() ?? 0;
    final avgPrice = (_salesStats!['average_price'] as num?)?.toDouble() ?? 0.0;

    final currencyFormat = NumberFormat.currency(locale: 'fr_FR', symbol: '€');

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                TranslationService.translate(context, 'total_revenue'),
                currencyFormat.format(totalRevenue),
                Icons.euro,
                Colors.transparent,
                gradient: AppDesign.successGradient,
                textColor: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                TranslationService.translate(context, 'sales_count'),
                totalSales.toString(),
                Icons.shopping_cart,
                Colors.transparent,
                gradient: AppDesign.oceanGradient,
                textColor: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                TranslationService.translate(context, 'average_price'),
                currencyFormat.format(avgPrice),
                Icons.price_check,
                Colors.transparent,
                gradient: AppDesign.primaryGradient,
                textColor: Colors.white,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    IconData icon,
    Color backgroundColor, {
    Gradient? gradient,
    Color textColor = const Color(0xFF1E293B),
  }) {
    // Extract accent color from gradient or fall back to backgroundColor
    final Color accentColor = gradient is LinearGradient
        ? gradient.colors.first
        : (backgroundColor == Colors.transparent
              ? Theme.of(context).colorScheme.primary
              : backgroundColor);
    final theme = Theme.of(context);

    return Semantics(
      label: '$label: $value',
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
          boxShadow: AppDesign.cardShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
          child: Stack(
            children: [
              // Left accent bar
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Container(
                  width: 4,
                  decoration: BoxDecoration(
                    gradient:
                        gradient ??
                        LinearGradient(colors: [accentColor, accentColor]),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(icon, color: accentColor, size: 22),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          value,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: accentColor,
                            height: 1.0,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
    );
  }
}
