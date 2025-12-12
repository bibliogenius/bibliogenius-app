import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../widgets/genie_app_bar.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';
import '../models/book.dart';
import '../models/gamification_status.dart';
// import 'genie_chat_screen.dart'; // Removed as we use route string
import '../providers/theme_provider.dart';
import '../services/wizard_service.dart';
import '../widgets/premium_book_card.dart';
import '../services/quote_service.dart';
import '../models/quote.dart';
import '../theme/app_design.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isLoading = true;
  Quote? _dailyQuote;
  String? _userName;
  Map<String, dynamic> _stats = {};
  List<Book> _recentBooks = [];
  List<Book> _readingListBooks = [];
  Book? _heroBook;
  GamificationStatus? _gamificationStatus;
  String? _libraryName;

  final GlobalKey _addKey = GlobalKey();
  final GlobalKey _searchKey = GlobalKey();
  final GlobalKey _statsKey = GlobalKey();
  final GlobalKey _menuKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _fetchDashboardData();
    _checkWizard();
  }

  void _checkWizard() async {
    if (!await WizardService.hasSeenDashboardWizard()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        WizardService.showDashboardWizard(
          context: context,
          addKey: _addKey,
          searchKey: _searchKey,
          statsKey: _statsKey,
          menuKey: _menuKey,
          onFinish: () {},
        );
      });
    }
  }

  Future<void> _fetchDashboardData() async {
    final api = Provider.of<ApiService>(context, listen: false);
    // Background fetch of translations
    TranslationService.fetchTranslations(context);
    
    setState(() => _isLoading = true);
    
    try {
      try {
        var books = await api.getBooks();
        final configRes = await api.getLibraryConfig();
        
        if (configRes.statusCode == 200) {
             final config = configRes.data;
             if (config['show_borrowed_books'] != true) {
               books = books.where((b) => b.readingStatus != 'borrowed').toList();
             }
             // Store library name
             if (mounted) {
               setState(() {
                 _libraryName = config['library_name'] ?? config['name'];
               });
             }
        }

          if (mounted) {
            setState(() {
              _stats['total_books'] = books.length;
              
              final readingListCandidates = books.where((b) => 
                ['reading', 'to_read'].contains(b.readingStatus)
              ).toList();
              
              readingListCandidates.sort((a, b) {
                if (a.readingStatus == 'reading' && b.readingStatus != 'reading') return -1;
                if (a.readingStatus != 'reading' && b.readingStatus == 'reading') return 1;
                return 0;
              });
              
              _readingListBooks = readingListCandidates.take(3).toList();

              final readingListIds = _readingListBooks.map((b) => b.id).toSet();
              
              final recentCandidates = books.where((b) => !readingListIds.contains(b.id)).toList();
              recentCandidates.sort((a, b) => (b.id ?? 0).compareTo(a.id ?? 0));
              
              _recentBooks = recentCandidates.take(3).toList();

              _heroBook = _readingListBooks.isNotEmpty ? _readingListBooks.first : (_recentBooks.isNotEmpty ? _recentBooks.first : null);
              if (_heroBook != null) {
                _readingListBooks.removeWhere((book) => book.id == _heroBook!.id);
                _recentBooks.removeWhere((book) => book.id == _heroBook!.id);
              }
            });
          }
      } catch (e) {
        debugPrint('Error fetching books: $e');
      }

      try {
        final contactsRes = await api.getContacts();
        if (contactsRes.statusCode == 200) {
          final List<dynamic> contactsData = contactsRes.data['contacts'];
          if (mounted) {
            setState(() {
              _stats['contacts_count'] = contactsData.length;
            });
          }
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
              _stats['active_loans'] = statusData['loans_count'] ?? 0;
              _userName = statusData['name'];
              _gamificationStatus = GamificationStatus.fromJson(statusData);
            });
          }
        }
      } catch (e) {
        debugPrint('Error fetching user status: $e');
      }

      // Fetch Quote
      if (mounted) {
         final allBooks = [..._recentBooks, ..._readingListBooks]; 
         if (allBooks.isNotEmpty) {
           final quoteService = QuoteService();
           final quote = await quoteService.fetchRandomQuote(allBooks);
           if (mounted) {
              setState(() {
                _dailyQuote = quote;
              });
           }
         }
      }

    } catch (e) {
       if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${TranslationService.translate(context, 'error_loading_dashboard')}: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isKid = themeProvider.isKid;
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 600;

    // Greeting logic removed as per user request


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
        actions: [
          IconButton(
            key: _searchKey,
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: () {
               context.push('/books'); 
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          context.push('/genie-chat');
        },
        backgroundColor: Colors.blueAccent,
        child: const Icon(Icons.auto_awesome, color: Colors.white),
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          gradient: AppDesign.pageGradient, // Discrete light background
        ),
        child: SafeArea(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchDashboardData,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 1. Header with Quote
                        _buildHeader(context),
                        const SizedBox(height: 24),

                        // Stats Row - Full Width
                        Row(
                          key: _statsKey,
                          children: [
                            Expanded(
                              child: _buildStatCard(
                                context,
                                TranslationService.translate(context, 'my_books'),
                                (_stats['total_books'] ?? 0).toString(),
                                Icons.menu_book,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildStatCard(
                                context,
                                TranslationService.translate(context, 'borrowed'),
                                (_stats['active_loans'] ?? 0).toString(),
                                Icons.outbox,
                                isAccent: true,
                              ),
                            ),
                            if (!isKid) ...[
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildStatCard(
                                  context,
                                  themeProvider.isLibrarian ? TranslationService.translate(context, 'borrowers') : TranslationService.translate(context, 'contacts'),
                                  (_stats['contacts_count'] ?? 0).toString(),
                                  Icons.people,
                                ),
                              ),
                            ],
                          ],
                        ),

                        const SizedBox(height: 24),

                        // Gamification Mini-Widget
                        if (_gamificationStatus != null && !isKid)
                          _buildGamificationMini(context),

                        const SizedBox(height: 32),

                        // Main Content Container
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (isKid) ...[
                              _buildSectionTitle(context, TranslationService.translate(context, 'quick_actions')),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildKidActionCard(
                                      context,
                                      TranslationService.translate(context, 'action_scan_barcode'),
                                      Icons.qr_code_scanner,
                                      Colors.orange,
                                      () => context.push('/scan'),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: _buildKidActionCard(
                                      context,
                                      TranslationService.translate(context, 'action_search_online'),
                                      Icons.search,
                                      Colors.blue,
                                      () => context.push('/books/add'),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 32),
                            ] else if (_heroBook != null)
                              // Hero Section
                              _buildHeroBook(context, _heroBook!),
                            
                            if (!isKid) ...[
                              _buildSectionTitle(context, TranslationService.translate(context, 'quick_actions')),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.08),
                                      blurRadius: 15,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                  border: Border.all(
                                    color: const Color(0xFF667eea).withValues(alpha: 0.1),
                                    width: 1,
                                  ),
                                ),
                                child: Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    _buildActionButton(
                                      context,
                                      TranslationService.translate(context, 'action_add_book'),
                                      Icons.add,
                                      () => context.push('/books/add'),
                                      isPrimary: true,
                                      key: _addKey,
                                    ),
                                    _buildActionButton(
                                      context,
                                      TranslationService.translate(context, 'action_checkout_book'),
                                      Icons.upload_file,
                                      () => context.push('/network-search'),
                                    ),
                                    _buildActionButton(
                                      context,
                                      TranslationService.translate(context, 'ask_genie'), // Translated
                                      Icons.auto_awesome,
                                      () => context.push(
                                        '/genie-chat', 
                                      ), 
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 32),
                            ],

                            // Recent Books
                            if (_recentBooks.isNotEmpty) ...[
                              _buildSectionTitle(context,
                                  TranslationService.translate(context, 'recent_books')),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.08),
                                      blurRadius: 15,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: _buildBookList(context, _recentBooks, TranslationService.translate(context, 'no_recent_books')),
                              ),
                              const SizedBox(height: 32),
                            ],

                            // Reading List
                            if (_readingListBooks.isNotEmpty) ...[
                              _buildSectionTitle(context,
                                  TranslationService.translate(context, 'reading_list')),
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.08),
                                      blurRadius: 15,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: _buildBookList(context, _readingListBooks,
                                    TranslationService.translate(context, 'no_reading_list')),
                              ),
                            ],

                            const SizedBox(height: 32),
                            if (!isKid)
                              Center(
                                child: ScaleOnTap(
                                  child: TextButton.icon(
                                    onPressed: () => context.push('/statistics'),
                                    icon: const Icon(Icons.insights, color: Colors.black54),
                                    label: Text(
                                      TranslationService.translate(context, 'view_insights'),
                                      style: const TextStyle(color: Colors.black54),
                                    ),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                      backgroundColor: Colors.black.withValues(alpha: 0.05),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(30),
                                        side: BorderSide(color: Colors.black.withValues(alpha: 0.1)),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 32),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    // Greeting logic removed as per user request


    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Welcome Banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF667eea), Color(0xFF764ba2)],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF667eea).withValues(alpha: 0.3),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              // Logo
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              // Name and streak
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _libraryName ?? _userName ?? 'BiblioGenius',
                      style: const TextStyle(
                        fontSize: 24,
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        height: 1.1,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_gamificationStatus != null && _gamificationStatus!.streak.hasStreak)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.local_fire_department, color: Colors.orange, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              '${_gamificationStatus!.streak.current} ${TranslationService.translate(context, 'days')}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (_dailyQuote != null) ...[
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
              boxShadow: AppDesign.subtleShadow,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _dailyQuote!.text,
                  style: const TextStyle(
                    fontSize: 16,
                    fontStyle: FontStyle.italic,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Text(
                    '- ${_dailyQuote!.author}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _getGreeting(BuildContext context) {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return TranslationService.translate(context, 'greeting_morning');
    } else if (hour < 18) {
      return TranslationService.translate(context, 'greeting_afternoon');
    } else {
      return TranslationService.translate(context, 'greeting_evening');
    }
  }

  Widget _buildGamificationMini(BuildContext context) {
    if (_gamificationStatus == null) return const SizedBox.shrink();
    
    return GestureDetector(
      onTap: () => context.push('/profile'),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppDesign.subtleShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.emoji_events, color: Colors.white, size: 14),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      TranslationService.translate(context, 'your_progress'),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMiniTrack(
                  context,
                  Icons.library_books,
                  _gamificationStatus!.collector,
                  Colors.blue,
                ),
                _buildMiniTrack(
                  context,
                  Icons.menu_book,
                  _gamificationStatus!.reader,
                  Colors.green,
                ),
                _buildMiniTrack(
                  context,
                  Icons.handshake,
                  _gamificationStatus!.lender,
                  Colors.orange,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniTrack(BuildContext context, IconData icon, TrackProgress track, Color color) {
    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 50,
              height: 50,
              child: CircularProgressIndicator(
                value: track.progress,
                strokeWidth: 4,
                backgroundColor: color.withValues(alpha: 0.2),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.1),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            if (track.level > 0)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: _getLevelColor(track.level),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Center(
                    child: Text(
                      '${track.level}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${track.current}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: color,
          ),
        ),
      ],
    );
  }

  Color _getLevelColor(int level) {
    switch (level) {
      case 1: return const Color(0xFFCD7F32); // Bronze
      case 2: return const Color(0xFFC0C0C0); // Silver
      case 3: return const Color(0xFFFFD700); // Gold
      default: return Colors.grey;
    }
  }

  Widget _buildStatCard(BuildContext context, String label, String value, IconData icon, {bool isAccent = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isAccent ? Theme.of(context).primaryColor : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isAccent ? Colors.transparent : Colors.grey.withValues(alpha: 0.3),
        ),
        boxShadow: isAccent ? [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          )
        ] : AppDesign.subtleShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: isAccent ? Colors.white : Theme.of(context).primaryColor, size: 24),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: isAccent ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isAccent ? Colors.white70 : Colors.black54,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    IconData icon = Icons.auto_stories;
    if (title.toLowerCase().contains('recent') || title.toLowerCase().contains('récent')) {
      icon = Icons.history;
    } else if (title.toLowerCase().contains('reading') || title.toLowerCase().contains('lecture')) {
      icon = Icons.bookmark;
    } else if (title.toLowerCase().contains('action')) {
      icon = Icons.bolt;
    }
    
    return Container(
      margin: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 28,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF667eea), Color(0xFF764ba2)],
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF667eea).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: const Color(0xFF667eea)),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context,
    String label,
    IconData icon,
    VoidCallback onPressed, {
    bool isPrimary = false,
    Key? key,
  }) {
    return ScaleOnTap(
      child: ElevatedButton.icon(
        key: key,
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary ? Theme.of(context).primaryColor : Colors.white,
          foregroundColor: isPrimary ? Colors.white : Theme.of(context).primaryColor,
          elevation: isPrimary ? 4 : 2,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
          ),
          shadowColor: Colors.black.withValues(alpha: 0.1),
        ),
      ),
    );
  }


  Widget _buildBookList(BuildContext context, List<Book> books, String emptyMessage) {
    if (books.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: AppDesign.glassDecoration(),
        child: Center(
          child: Text(
            emptyMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54),
          )
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

  Widget _buildHeroBook(BuildContext context, Book book) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 32),
      child: PremiumBookCard(
        book: book,
        isHero: true,
        width: double.infinity,
        height: 300,
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
                color: color.withValues(alpha: 0.1),
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
