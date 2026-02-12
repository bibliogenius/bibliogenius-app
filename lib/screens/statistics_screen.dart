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
import '../widgets/goal_reached_animation.dart';
import '../theme/app_design.dart';
import '../providers/theme_provider.dart';
import 'package:intl/intl.dart';

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
    final collectionRepo = Provider.of<CollectionRepository>(context, listen: false);
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
    final bool isMobile = width <= 600;

    return Scaffold(
      appBar: GenieAppBar(
        title: TranslationService.translate(context, 'library_insights'),
        leading: isMobile
            ? IconButton(
                icon: const Icon(Icons.menu, color: Colors.white),
                onPressed: () => Scaffold.of(context).openDrawer(),
              )
            : null,
        automaticallyImplyLeading: false,
        showQuickActions: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _books.isEmpty
          ? _buildEmptyState()
          : FadeTransition(
              opacity: _fadeAnim,
              child: SingleChildScrollView(
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
                      TranslationService.translate(context, 'loan_statistics'),
                      Icons.swap_horiz,
                      AppDesign.accentGradient,
                    ),
                    const SizedBox(height: 16),
                    _buildLoanStatisticsSection(),
                    // Borrowed Statistics Section - hidden for librarians
                    if (!Provider.of<ThemeProvider>(
                      context,
                      listen: false,
                    ).isLibrarian) ...[
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
                        AppDesign.darkGradient,
                      ),
                      const SizedBox(height: 16),
                      _buildCollectionStatisticsSection(),
                    ],
                    const SizedBox(height: 40),
                  ],
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
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
        const SizedBox(width: 16),
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
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
                    Stack(
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
                                      colors: [Colors.white, Color(0xFFFFF8DC)],
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
                gradient: AppDesign.refinedPrimaryGradient,
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
                gradient: AppDesign.refinedSuccessGradient,
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
                gradient: AppDesign.refinedAccentGradient,
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
                gradient: AppDesign.refinedWarningGradient,
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
                gradient: AppDesign.refinedOceanGradient,
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
    return Container(
      height: 140,
      decoration: BoxDecoration(
        color: gradient != null ? null : backgroundColor,
        gradient: gradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: backgroundColor.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Decorative background icon
          Positioned(
            right: -15,
            top: -15,
            child: ShaderMask(
              shaderCallback: (rect) => LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.4),
                  Colors.white.withValues(alpha: 0.1),
                ],
              ).createShader(rect),
              child: Icon(icon, size: 100, color: Colors.white),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Icon wrapper
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: textColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: textColor.withValues(alpha: 0.1)),
                  ),
                  child: Icon(icon, color: textColor, size: 20),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                        height: 1.0,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: textColor.withValues(alpha: 0.8),
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

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
        boxShadow: AppDesign.cardShadow,
      ),
      child: Column(
        children: [
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                sections: sections,
                centerSpaceRadius: 50,
                sectionsSpace: 3,
              ),
            ),
          ),
          const SizedBox(height: 24),
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

    if (sortedAuthors.length > 5) {
      sortedAuthors = sortedAuthors.sublist(0, 5);
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

    return Container(
      height: 280,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
        boxShadow: AppDesign.cardShadow,
      ),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: sortedAuthors.first.value.toDouble() + 1,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (group) => const Color(0xFF1E293B),
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                return BarTooltipItem(
                  '${sortedAuthors[groupIndex].key}\n',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  children: [
                    TextSpan(
                      text: '${rod.toY.toInt()} books',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (double value, TitleMeta meta) {
                  if (value.toInt() >= sortedAuthors.length) {
                    return const SizedBox.shrink();
                  }
                  final author = sortedAuthors[value.toInt()].key;
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      author.length > 10
                          ? '${author.substring(0, 8)}...'
                          : author,
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                },
                reservedSize: 40,
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
          barGroups: sortedAuthors.asMap().entries.map((e) {
            final gradient = AppDesign.featureGradient(e.key);
            return BarChartGroupData(
              x: e.key,
              barRods: [
                BarChartRodData(
                  toY: e.value.value.toDouble(),
                  gradient: gradient,
                  width: 24,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(6),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
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

    return Container(
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
                        text: '${spot.y.toInt()} books',
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
    );
  }

  Widget _buildLoanStatisticsSection() {
    // Calculate loan statistics
    final totalLoans = _loans.length;
    final activeLoans = _loans.where((l) => l.returnDate == null).length;
    final returnedLoans = _loans.where((l) => l.returnDate != null).length;

    // Calculate average loan duration (for returned loans)
    double avgDuration = 0;
    final returnedWithDates = _loans
        .where((l) => l.returnDate != null)
        .toList();

    if (returnedWithDates.isNotEmpty) {
      int totalDays = 0;
      for (var loan in returnedWithDates) {
        try {
          final loanDate = DateTime.parse(loan.loanDate);
          final returnDate = DateTime.parse(loan.returnDate!);
          totalDays += returnDate.difference(loanDate).inDays;
        } catch (_) {}
      }
      avgDuration = totalDays / returnedWithDates.length;
    }

    // Top borrowers (contacts)
    final borrowerCounts = <String, int>{};
    for (var loan in _loans) {
      String contactName = 'Unknown';

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
      final bookTitle = loan.bookTitle.isNotEmpty ? loan.bookTitle : 'Unknown';
      bookCounts[bookTitle] = (bookCounts[bookTitle] ?? 0) + 1;
    }
    var mostLentBooks = bookCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (mostLentBooks.length > 5) mostLentBooks = mostLentBooks.sublist(0, 5);

    // Return rate
    final returnRate = totalLoans > 0
        ? (returnedLoans / totalLoans * 100).toStringAsFixed(0)
        : '0';

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
                  totalLoans.toString(),
                  Icons.swap_horiz,
                  const Color(0xFF8B4513), // Bronze instead of purple
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMiniStat(
                  TranslationService.translate(context, 'active_loans'),
                  activeLoans.toString(),
                  Icons.arrow_upward,
                  Colors.orange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMiniStat(
                  TranslationService.translate(context, 'return_rate'),
                  '$returnRate%',
                  Icons.check_circle,
                  Colors.green,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMiniStat(
                  TranslationService.translate(context, 'avg_duration'),
                  '${avgDuration.toStringAsFixed(0)}j',
                  Icons.timer,
                  const Color(0xFFD4A855), // Bronze instead of blue
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
                            const Color(0xFFD4A855),
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
                  const Color(0xFFD4A855),
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

    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(isDesktop ? 12 : 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: isDesktop ? 28 : 18, color: color),
        ),
        SizedBox(height: isDesktop ? 12 : 8),
        Text(
          value,
          style: TextStyle(
            fontSize: isDesktop ? 24 : 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        SizedBox(height: isDesktop ? 4 : 2),
        Text(
          label,
          style: TextStyle(
            fontSize: isDesktop ? 13 : 10,
            color: Colors.grey[600],
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
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
              color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${tag.count}',
              style: TextStyle(
                fontSize: isDesktop ? 13 : 11,
                color: const Color(0xFFF59E0B),
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
                AppDesign.pastelGreen,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                TranslationService.translate(context, 'sales_count'),
                totalSales.toString(),
                Icons.shopping_cart,
                AppDesign.pastelBlue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                TranslationService.translate(context, 'average_price'),
                currencyFormat.format(avgPrice),
                Icons.price_check,
                AppDesign.pastelCyan,
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
class StatisticsContent extends StatefulWidget {
  const StatisticsContent({super.key});

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
  bool _isLoading = true;
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

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
    super.dispose();
  }

  Future<void> _fetchData() async {
    final bookRepo = Provider.of<BookRepository>(context, listen: false);
    final tagRepo = Provider.of<TagRepository>(context, listen: false);
    final contactRepo = Provider.of<ContactRepository>(context, listen: false);
    final collectionRepo = Provider.of<CollectionRepository>(context, listen: false);
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

      if (mounted) {
        setState(() {
          _books = books;
          _loans = loans;
          _contactsMap = contactsMap;
          _tags = tags;
          _collections = collections;
          _salesStats = salesStats;
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSummaryCards(),
              // Monthly Reading Progress
              if (_hasReadingHistory()) ...[
                const SizedBox(height: 32),
                _buildSectionTitle(
                  TranslationService.translate(context, 'monthly_progress'),
                  Icons.show_chart,
                  AppDesign.successGradient,
                  helpText: TranslationService.translate(
                    context,
                    'help_ctx_stats_monthly_progress',
                  ),
                ),
                const SizedBox(height: 16),
                _buildMonthlyProgressChart(),
              ],
              // Average Rating & Reading Speed
              const SizedBox(height: 32),
              _buildSectionTitle(
                TranslationService.translate(context, 'reading_insights'),
                Icons.insights,
                AppDesign.primaryGradient,
                helpText: TranslationService.translate(
                  context,
                  'help_ctx_stats_unique_stats',
                ),
              ),
              const SizedBox(height: 16),
              _buildReadingInsightsSection(),
              // Sales Statistics (for booksellers)
              if (_salesStats != null) ...[
                const SizedBox(height: 32),
                _buildSectionTitle(
                  TranslationService.translate(context, 'sales_statistics'),
                  Icons.monetization_on,
                  AppDesign.successGradient,
                  helpText: TranslationService.translate(
                    context,
                    'help_ctx_stats_sales',
                  ),
                ),
                const SizedBox(height: 16),
                _buildSalesStatisticsSection(),
              ],
              // Reading Habits
              const SizedBox(height: 32),
              _buildSectionTitle(
                TranslationService.translate(context, 'reading_habits'),
                Icons.pie_chart,
                AppDesign.primaryGradient,
                helpText: TranslationService.translate(
                  context,
                  'help_ctx_stats_reading_habits',
                ),
              ),
              const SizedBox(height: 16),
              _buildStatusPieChart(),
              // Top Authors
              const SizedBox(height: 32),
              _buildSectionTitle(
                TranslationService.translate(context, 'top_authors'),
                Icons.person,
                AppDesign.successGradient,
                helpText: TranslationService.translate(
                  context,
                  'help_ctx_stats_top_authors',
                ),
              ),
              const SizedBox(height: 16),
              _buildTopAuthorsChart(),
              // Publication Timeline
              const SizedBox(height: 32),
              _buildSectionTitle(
                TranslationService.translate(context, 'publication_timeline'),
                Icons.timeline,
                AppDesign.oceanGradient,
                helpText: TranslationService.translate(
                  context,
                  'help_ctx_stats_publication_year',
                ),
              ),
              const SizedBox(height: 16),
              _buildPublicationYearChart(),
              // Loan Statistics
              const SizedBox(height: 32),
              _buildSectionTitle(
                TranslationService.translate(context, 'loan_statistics'),
                Icons.swap_horiz,
                AppDesign.accentGradient,
                helpText: TranslationService.translate(
                  context,
                  'help_ctx_stats_loan_stats',
                ),
              ),
              const SizedBox(height: 16),
              _buildLoanStatisticsSection(),
              // Borrowed Statistics - hidden for librarians
              if (!Provider.of<ThemeProvider>(
                context,
                listen: false,
              ).isLibrarian) ...[
                const SizedBox(height: 32),
                _buildSectionTitle(
                  TranslationService.translate(context, 'borrowed_statistics'),
                  Icons.arrow_downward,
                  AppDesign.pastelPrimaryGradient,
                ),
                const SizedBox(height: 16),
                _buildBorrowedStatisticsSection(),
              ],
              // Shelf Statistics - only if shelves exist
              if (_tags.isNotEmpty) ...[
                const SizedBox(height: 32),
                _buildSectionTitle(
                  TranslationService.translate(context, 'shelf_statistics'),
                  Icons.shelves,
                  AppDesign.warningGradient,
                ),
                const SizedBox(height: 16),
                _buildShelfStatisticsSection(),
              ],
              // Collection Statistics - only if collections exist
              if (_collections.isNotEmpty) ...[
                const SizedBox(height: 32),
                _buildSectionTitle(
                  TranslationService.translate(
                    context,
                    'collection_statistics',
                  ),
                  Icons.collections_bookmark,
                  AppDesign.darkGradient,
                ),
                const SizedBox(height: 16),
                _buildCollectionStatisticsSection(),
              ],
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(
    String title,
    IconData icon,
    Gradient gradient, {
    String? helpText,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
        const SizedBox(width: 16),
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        if (helpText != null) ...[
          const SizedBox(width: 8),
          Tooltip(
            message: helpText,
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: const TextStyle(color: Colors.white, fontSize: 13),
            triggerMode: TooltipTriggerMode.tap,
            child: Icon(
              Icons.info_outline,
              size: 18,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ],
    );
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
                gradient: AppDesign.refinedPrimaryGradient,
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
                gradient: AppDesign.refinedSuccessGradient,
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
                gradient: AppDesign.refinedAccentGradient,
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
                gradient: AppDesign.refinedWarningGradient,
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
                gradient: AppDesign.refinedOceanGradient,
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

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
        boxShadow: AppDesign.cardShadow,
      ),
      child: Column(
        children: [
          SizedBox(
            height: 200,
            child: PieChart(
              PieChartData(
                sections: sections,
                centerSpaceRadius: 50,
                sectionsSpace: 3,
              ),
            ),
          ),
          const SizedBox(height: 24),
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

    if (sortedAuthors.length > 5) {
      sortedAuthors = sortedAuthors.sublist(0, 5);
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

    return Container(
      height: 280,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
        boxShadow: AppDesign.cardShadow,
      ),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: sortedAuthors.first.value.toDouble() + 1,
          barTouchData: BarTouchData(
            enabled: true,
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (group) => const Color(0xFF1E293B),
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                return BarTooltipItem(
                  '${sortedAuthors[groupIndex].key}\n',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  children: [
                    TextSpan(
                      text: '${rod.toY.toInt()} books',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (double value, TitleMeta meta) {
                  if (value.toInt() >= sortedAuthors.length) {
                    return const SizedBox.shrink();
                  }
                  final author = sortedAuthors[value.toInt()].key;
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      author.length > 10
                          ? '${author.substring(0, 8)}...'
                          : author,
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                },
                reservedSize: 40,
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
          barGroups: sortedAuthors.asMap().entries.map((e) {
            final gradient = AppDesign.featureGradient(e.key);
            return BarChartGroupData(
              x: e.key,
              barRods: [
                BarChartRodData(
                  toY: e.value.value.toDouble(),
                  gradient: gradient,
                  width: 24,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(6),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
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

    return Container(
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
                        text: '${spot.y.toInt()} books',
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

    return Container(
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
    );
  }

  Widget _buildReadingInsightsSection() {
    // Calculate average rating
    final ratedBooks = _books
        .where((b) => b.userRating != null && b.userRating! > 0)
        .toList();
    final avgRating = ratedBooks.isNotEmpty
        ? ratedBooks.map((b) => b.userRating!).reduce((a, b) => a + b) /
              ratedBooks.length
        : 0.0;

    // Calculate average reading duration
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

    // Fastest book read
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

    // Highest rated book - tie break with most recent finished date
    Book? highestRatedBook;
    for (var book in ratedBooks) {
      if (highestRatedBook == null) {
        highestRatedBook = book;
      } else {
        if ((book.userRating ?? 0) > (highestRatedBook.userRating ?? 0)) {
          highestRatedBook = book;
        } else if (book.userRating == highestRatedBook.userRating) {
          // Tie break: most recently finished
          if (book.finishedReadingAt != null &&
              (highestRatedBook.finishedReadingAt == null ||
                  book.finishedReadingAt!.isAfter(
                    highestRatedBook.finishedReadingAt!,
                  ))) {
            highestRatedBook = book;
          }
        }
      }
    }

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
        boxShadow: AppDesign.cardShadow,
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildInsightCard(
                  Icons.star_rate,
                  avgRating > 0 ? avgRating.toStringAsFixed(1) : '-',
                  TranslationService.translate(context, 'avg_rating'),
                  avgRating > 0 ? ' stars' : '',
                  const Color(0xFFF59E0B),
                  useStarDisplay: avgRating > 0,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildInsightCard(
                  Icons.timer,
                  avgDays > 0 ? avgDays.toStringAsFixed(0) : '-',
                  TranslationService.translate(context, 'avg_reading_time'),
                  TranslationService.translate(context, 'days'),
                  const Color(0xFF0EA5E9),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildInsightCard(
                  Icons.speed,
                  fastestDays?.toString() ?? '-',
                  TranslationService.translate(context, 'fastest_read'),
                  TranslationService.translate(context, 'days'),
                  const Color(0xFF10B981),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildInsightCard(
                  Icons.workspace_premium,
                  highestRatedBook?.userRating?.toString() ?? '-',
                  TranslationService.translate(context, 'best_rated'),
                  highestRatedBook != null ? ' stars' : '',
                  const Color(0xFFEC4899),
                  useStarDisplay: highestRatedBook != null,
                ),
              ),
            ],
          ),
          // Show book titles if available
          if (fastestBookTitle != null || highestRatedBook != null) ...[
            if (fastestBookTitle != null)
              _buildBookMention(
                context: context,
                icon: Icons.speed,
                label: TranslationService.translate(context, 'fastest_book'),
                bookTitle: fastestBookTitle,
                bookId: fastestBookId,
                color: const Color(0xFF10B981),
              ),
            if (highestRatedBook != null) ...[
              const SizedBox(height: 8),
              _buildBookMention(
                context: context,
                icon: Icons.workspace_premium,
                label: TranslationService.translate(context, 'favorite_book'),
                bookTitle: highestRatedBook.title,
                bookId: highestRatedBook.id,
                color: const Color(0xFFEC4899),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildBookMention({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String bookTitle,
    int? bookId,
    required Color color,
  }) {
    return InkWell(
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
                  decoration: bookId != null ? TextDecoration.underline : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInsightCard(
    IconData icon,
    String value,
    String label,
    String suffix,
    Color color, {
    bool useStarDisplay = false,
    String? helpText,
  }) {
    final double? ratingValue = double.tryParse(value);
    final double starRating = useStarDisplay && ratingValue != null
        ? (ratingValue / 2.0).clamp(0.0, 5.0)
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 12),
              if (useStarDisplay && ratingValue != null)
                Row(
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
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Flexible(
                      child: Text(
                        value,
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: color,
                          height: 1.0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        suffix,
                        style: TextStyle(
                          fontSize: 14,
                          color: color.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
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

  Widget _buildCollectionStatisticsSection() {
    final collections = _collections;
    final totalCollections = collections.length;
    double avgCompletion = 0;

    if (collections.isNotEmpty) {
      final totalCompletion = collections.fold<double>(0, (sum, collection) {
        if (collection.totalBooks == 0) return sum;
        return sum + (collection.ownedBooks / collection.totalBooks);
      });
      avgCompletion = (totalCompletion / totalCollections) * 100;
    }

    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            TranslationService.translate(context, 'stat_total_collections'),
            totalCollections.toString(),
            Icons.collections_bookmark,
            AppDesign.pastelPurple,
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
            AppDesign.pastelBlue,
          ),
        ),
      ],
    );
  }

  Widget _buildLoanStatisticsSection() {
    final totalLoans = _loans.length;
    final activeLoans = _loans.where((l) => l.returnDate == null).length;
    final returnedLoans = _loans.where((l) => l.returnDate != null).length;

    double avgDuration = 0;
    final returnedWithDates = _loans
        .where((l) => l.returnDate != null)
        .toList();

    if (returnedWithDates.isNotEmpty) {
      int totalDays = 0;
      for (var loan in returnedWithDates) {
        try {
          final loanDate = DateTime.parse(loan.loanDate);
          final returnDate = DateTime.parse(loan.returnDate!);
          totalDays += returnDate.difference(loanDate).inDays;
        } catch (_) {}
      }
      avgDuration = totalDays / returnedWithDates.length;
    }

    final borrowerCounts = <String, int>{};
    for (var loan in _loans) {
      String contactName = 'Unknown';

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
      final bookTitle = loan.bookTitle.isNotEmpty ? loan.bookTitle : 'Unknown';
      bookCounts[bookTitle] = (bookCounts[bookTitle] ?? 0) + 1;
    }
    var mostLentBooks = bookCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (mostLentBooks.length > 5) mostLentBooks = mostLentBooks.sublist(0, 5);

    final returnRate = totalLoans > 0
        ? (returnedLoans / totalLoans * 100).toStringAsFixed(0)
        : '0';

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
                  totalLoans.toString(),
                  Icons.swap_horiz,
                  const Color(0xFF8B4513),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMiniStat(
                  TranslationService.translate(context, 'active_loans'),
                  activeLoans.toString(),
                  Icons.arrow_upward,
                  Colors.orange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMiniStat(
                  TranslationService.translate(context, 'return_rate'),
                  '$returnRate%',
                  Icons.check_circle,
                  Colors.green,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMiniStat(
                  TranslationService.translate(context, 'avg_duration'),
                  '${avgDuration.toStringAsFixed(0)}j',
                  Icons.timer,
                  const Color(0xFFD4A855),
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
                        color: const Color(0xFFD4A855).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${e.value}x',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFFD4A855),
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
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey[600]),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
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
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${tag.count}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFFF59E0B),
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
                AppDesign.pastelGreen,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                TranslationService.translate(context, 'sales_count'),
                totalSales.toString(),
                Icons.shopping_cart,
                Colors.transparent,
                gradient: AppDesign.primaryGradient,
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
                gradient: AppDesign.oceanGradient,
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
    return Container(
      height: 140,
      decoration: BoxDecoration(
        color: gradient != null ? null : backgroundColor,
        gradient: gradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: backgroundColor.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Decorative background icon
          Positioned(
            right: -15,
            top: -15,
            child: Icon(
              icon,
              size: 100,
              color: Colors.white.withValues(alpha: 0.3),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Icon wrapper
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: textColor, size: 20),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                        height: 1.0,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: textColor.withValues(alpha: 0.7),
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
    );
  }
}
