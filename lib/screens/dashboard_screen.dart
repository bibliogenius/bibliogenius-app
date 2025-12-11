import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../widgets/genie_app_bar.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';
import '../models/book.dart';
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

    String greeting = TranslationService.translate(context, 'good_morning');
    final hour = DateTime.now().hour;
    if (hour >= 12 && hour < 17) {
      greeting = TranslationService.translate(context, 'good_afternoon');
    } else if (hour >= 17) {
      greeting = TranslationService.translate(context, 'good_evening');
    }

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
      body: Container(
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

                        // Stats Row
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          clipBehavior: Clip.none,
                          child: Row(
                            key: _statsKey,
                            children: [
                              _buildStatCard(
                                context,
                                TranslationService.translate(context, 'my_books'),
                                (_stats['total_books'] ?? 0).toString(),
                                Icons.menu_book,
                              ),
                              const SizedBox(width: 12),
                              _buildStatCard(
                                context,
                                TranslationService.translate(context, 'borrowed'),
                                (_stats['active_loans'] ?? 0).toString(),
                                Icons.outbox,
                                isAccent: true,
                              ),
                              if (!isKid) ...[
                                const SizedBox(width: 12),
                                _buildStatCard(
                                  context,
                                  themeProvider.isLibrarian ? TranslationService.translate(context, 'borrowers') : TranslationService.translate(context, 'contacts'),
                                  (_stats['contacts_count'] ?? 0).toString(),
                                  Icons.people,
                                ),
                              ],
                            ],
                          ),
                        ),

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
                                decoration: AppDesign.glassDecoration(),
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
                                      TranslationService.translate(context, 'action_ask_library'),
                                      Icons.chat,
                                      () {}, // Placeholder
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
                              _buildBookList(context, _recentBooks, TranslationService.translate(context, 'no_recent_books')),
                              const SizedBox(height: 32),
                            ],

                            // Reading List
                            if (_readingListBooks.isNotEmpty) ...[
                              _buildSectionTitle(context,
                                  TranslationService.translate(context, 'reading_list')),
                              const SizedBox(height: 16),
                              _buildBookList(context, _readingListBooks,
                                  TranslationService.translate(context, 'no_reading_list')),
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
                                      backgroundColor: Colors.black.withOpacity(0.05),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(30),
                                        side: BorderSide(color: Colors.black.withOpacity(0.1)),
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
    String greeting = TranslationService.translate(context, 'good_morning');
    final hour = DateTime.now().hour;
    if (hour >= 12 && hour < 17) {
      greeting = TranslationService.translate(context, 'good_afternoon');
    } else if (hour >= 17) {
      greeting = TranslationService.translate(context, 'good_evening');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ScaleOnTap(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$greeting,',
                style: const TextStyle(
                  fontSize: 28,
                  color: Colors.black87,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_userName != null)
                Text(
                  _userName!,
                  style: const TextStyle(
                    fontSize: 32,
                    color: Colors.black,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
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

  Widget _buildStatCard(BuildContext context, String label, String value, IconData icon, {bool isAccent = false}) {
    return Container(
      width: 110,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isAccent ? Theme.of(context).primaryColor : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isAccent ? Colors.transparent : Colors.grey.withOpacity(0.3),
        ),
        boxShadow: isAccent ? [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
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
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: Colors.black87,
          letterSpacing: 0.5,
          shadows: [
            Shadow(
              color: Colors.black12,
              offset: Offset(0, 1),
              blurRadius: 2,
            ),
          ],
        ),
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
          shadowColor: Colors.black.withOpacity(0.1),
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
        padding: const EdgeInsets.only(bottom: 16, left: 4, right: 4),
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
                color: color.withOpacity(0.1),
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
