
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

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  bool _isLoading = true;
  int _totalBooks = 0;
  int _activeLoans = 0;
  int _contactsCount = 0;
  List<Book> _recentBooks = [];
  List<Book> _readingListBooks = [];
  Book? _heroBook; // New state variable for the hero book

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
      // Fetch Books
      try {
        var books = await api.getBooks();
        final configRes = await api.getLibraryConfig(); // Fetch config
        
        // Filter based on config
        if (configRes.statusCode == 200) {
             final config = configRes.data;
             if (config['show_borrowed_books'] != true) {
               books = books.where((b) => b.readingStatus != 'borrowed').toList();
             }
        }

          if (mounted) {
            setState(() {
              _totalBooks = books.length;
              
              // 1. Define Reading List (Priority: Reading > To Read)
              final readingListCandidates = books.where((b) => 
                ['reading', 'to_read'].contains(b.readingStatus)
              ).toList();
              
              readingListCandidates.sort((a, b) {
                // 'reading' comes before 'to_read'
                if (a.readingStatus == 'reading' && b.readingStatus != 'reading') return -1;
                if (a.readingStatus != 'reading' && b.readingStatus == 'reading') return 1;
                return 0;
              });
              
              _readingListBooks = readingListCandidates.take(3).toList();

              // 2. Define Recent Books (Everything else, sorted by ID desc)
              // Exclude books already in reading list to avoid duplication
              final readingListIds = _readingListBooks.map((b) => b.id).toSet();
              
              final recentCandidates = books.where((b) => !readingListIds.contains(b.id)).toList();
              // Assuming higher ID is newer. If you have created_at, use that.
              recentCandidates.sort((a, b) => (b.id ?? 0).compareTo(a.id ?? 0));
              
              _recentBooks = recentCandidates.take(3).toList();

              // Set hero book (e.g., the first book in the reading list if available, otherwise the first recent book)
              _heroBook = _readingListBooks.isNotEmpty ? _readingListBooks.first : (_recentBooks.isNotEmpty ? _recentBooks.first : null);
              // Remove hero book from its original list to avoid duplication in display
              if (_heroBook != null) {
                _readingListBooks.removeWhere((book) => book.id == _heroBook!.id);
                _recentBooks.removeWhere((book) => book.id == _heroBook!.id);
              }
            });
          }
      } catch (e) {
        debugPrint('Error fetching books: $e');
      }

      // Fetch Contacts
      try {
        final contactsRes = await api.getContacts();
        if (contactsRes.statusCode == 200) {
          final List<dynamic> contactsData = contactsRes.data['contacts'];
          if (mounted) {
            setState(() {
              _contactsCount = contactsData.length;
            });
          }
        }
      } catch (e) {
        debugPrint('Error fetching contacts: $e');
      }

      // Fetch User Status
      try {
        final statusRes = await api.getUserStatus();
        if (statusRes.statusCode == 200) {
          final statusData = statusRes.data;
          if (mounted) {
            setState(() {
              _activeLoans = statusData['loans_count'] ?? 0;
            });
          }
        }
      } catch (e) {
        debugPrint('Error fetching user status: $e');
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
    final theme = Theme.of(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isKid = themeProvider.isKid;
    
    final width = MediaQuery.of(context).size.width;
    final isWide = width > 600;

    return Scaffold(
      appBar: GenieAppBar(
        title: TranslationService.translate(context, 'dashboard'),
        leading: isWide 
          ? null 
          : IconButton(
              key: _menuKey,
              icon: const Icon(Icons.menu),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
        automaticallyImplyLeading: false, // Prevent default back button if any
        actions: [
          IconButton(
            key: _searchKey,
            icon: const Icon(Icons.search),
            onPressed: () {
               context.push('/books'); 
            },
          ),
        ],
      ),
      // drawer: const AppDrawer(), // Removed, handled by parent ScaffoldWithNav
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchDashboardData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Stats Row (Visible for everyone now)
                  Row(
                    key: _statsKey,
                    children: [
                      Expanded(
                        child: _buildStatCard(
                          context,
                          TranslationService.translate(context, 'total_books'),
                          _totalBooks.toString(),
                          Icons.book,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildStatCard(
                          context,
                          TranslationService.translate(context, 'active_loans'),
                          _activeLoans.toString(),
                          Icons.swap_horiz,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildStatCard(
                          context,
                          themeProvider.isLibrarian ? TranslationService.translate(context, 'borrowers') : TranslationService.translate(context, 'contacts'),
                          _contactsCount.toString(),
                          Icons.people,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

                  if (_totalBooks == 0) ...[
                    // Empty State / Get Started
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(32),
                        decoration: BoxDecoration(
                          color: theme.cardTheme.color,
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 20,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.library_books, size: 64, color: theme.primaryColor.withOpacity(0.5)),
                            const SizedBox(height: 24),
                            Text(
                              TranslationService.translate(context, 'welcome_title'),
                              style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              TranslationService.translate(context, 'welcome_subtitle'),
                              style: theme.textTheme.bodyLarge?.copyWith(color: theme.textTheme.bodySmall?.color),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 32),
                            Wrap(
                              spacing: 16,
                              runSpacing: 16,
                              alignment: WrapAlignment.center,
                              children: [
                                ElevatedButton.icon(
                                  key: _addKey,
                                  onPressed: () => context.push('/books/add'),
                                  icon: const Icon(Icons.add),
                                  label: Text(TranslationService.translate(context, 'btn_add_manually')),
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () => context.push('/search/external'),
                                  icon: const Icon(Icons.public),
                                  label: Text(TranslationService.translate(context, 'btn_search_online')),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    // Quick Actions
                    if (isKid) ...[
                       // Kid Friendly Large Actions
                       Row(
                         children: [
                           Expanded(
                             child: _buildKidActionCard(
                               context, 
                               TranslationService.translate(context, 'action_add_book'), 
                               Icons.add_a_photo, 
                               Colors.orange,
                               () => context.push('/books/add'),
                               key: _addKey,
                             ),
                           ),
                           const SizedBox(width: 16),
                           Expanded(
                             child: _buildKidActionCard(
                               context, 
                               TranslationService.translate(context, 'search_books'), 
                               Icons.search, 
                               Colors.blue,
                               () => context.push('/books'),
                             ),
                           ),
                         ],
                       ),
                       const SizedBox(height: 16),
                       Row(
                         children: [
                           Expanded(
                             child: _buildKidActionCard(
                               context, 
                               TranslationService.translate(context, 'nav_contacts'), // My Friends
                               Icons.face, 
                               Colors.green,
                               () => context.push('/contacts'),
                             ),
                           ),
                           const SizedBox(width: 16),
                           Expanded(
                             child: _buildKidActionCard(
                               context, 
                               TranslationService.translate(context, 'nav_network'), // Network
                               Icons.public, 
                               Colors.purple,
                               () => context.push('/peers'),
                             ),
                           ),
                         ],
                       ),
                       const SizedBox(height: 32),
                    ] else if (_heroBook != null)
                // Hero Section (Top Logic)
                _buildHeroBook(context, _heroBook!),
                    if (!isKid) ...[
                      _buildSectionTitle(context, TranslationService.translate(context, 'quick_actions')),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: theme.cardTheme.color,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: theme.dividerColor.withOpacity(0.1)),
                          boxShadow: [
                             BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                          ]
                        ),
                        child: Wrap(
                          spacing: 16,
                          runSpacing: 16,
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
                              isPrimary: true,
                            ),
                            _buildActionButton(
                              context,
                              TranslationService.translate(context, 'action_ask_library'),
                              Icons.chat,
                              () {}, // Placeholder
                              isPrimary: true,
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
                      // If only 1 book, user sees Hero. If more, he sees Hero + List effectively?
                      // Actually, let's keep it simple: Show most recent as Hero ALWAYS if available?
                      // Or just list? 
                      // Decision: Use the first book as Hero, others in list if multiple?
                      // Actually user prompt implies "Recent Books" AND "Reading List" appear.
                      // Let's make "Continue Reading" the Hero section (most recent 'reading' book).
                      
                      // For now, let's stick to the current data logic but improve presentation.
                      _buildBookList(context, _recentBooks, TranslationService.translate(context, 'no_recent_books')),
                         
                      const SizedBox(height: 32),
                    ],

                    // Reading List (All books with 'reading' status)
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
                      child: TextButton.icon(
                        onPressed: () => context.push('/statistics'),
                        icon: const Icon(Icons.insights),
                        label: Text(TranslationService.translate(context, 'view_insights')),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildStatCard(BuildContext context, String label, String value, IconData icon) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.textTheme.bodyLarge?.color,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label.toUpperCase(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.textTheme.bodySmall?.color?.withOpacity(0.6),
              fontWeight: FontWeight.w600,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
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
    final theme = Theme.of(context);
    return ElevatedButton.icon(
      key: key,
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: isPrimary ? theme.primaryColor : theme.cardColor,
        foregroundColor: isPrimary ? Colors.white : theme.textTheme.bodyLarge?.color,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }


  Widget _buildBookList(BuildContext context, List<Book> books, String emptyMessage,
      {int delay = 0}) {
    // If we have books, show them in a horizontal list (Netflix style)
    if (books.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: Theme.of(context).dividerColor.withOpacity(0.1)),
        ),
        child: Center(child: Text(emptyMessage)),
      );
    }

    return SizedBox(
      height: 260, // Height for card + shadow/padding
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: books.length,
        padding: const EdgeInsets.only(bottom: 16, left: 4, right: 4),
        itemBuilder: (context, index) {
          return PremiumBookCard(book: books[index]);
        },
      ),
    );
  }

  Widget _buildHeroBook(BuildContext context, Book book) {
    // Use the premium card in hero mode
    return PremiumBookCard(
      book: book,
      isHero: true,
      width: double.infinity,
      height: 300,
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        key: key,
        height: 120,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.3), width: 2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: color),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
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
