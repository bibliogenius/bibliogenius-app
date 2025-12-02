import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../widgets/genie_app_bar.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';
import '../models/book.dart';
import '../widgets/app_drawer.dart';
import '../providers/theme_provider.dart';
import '../services/wizard_service.dart'; // Add WizardService

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
        final booksRes = await api.getBooks();
        final configRes = await api.getLibraryConfig(); // Fetch config
        
        if (booksRes.statusCode == 200 && booksRes.data['books'] != null) {
          final List<dynamic> booksData = booksRes.data['books'];
          var books = booksData.map((json) => Book.fromJson(json)).toList();
          
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
            });
          }
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
    
    return Scaffold(
      appBar: GenieAppBar(
        title: TranslationService.translate(context, 'dashboard'),
        leading: Builder(
          builder: (context) => IconButton(
            key: _menuKey,
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
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
      drawer: const AppDrawer(),
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
                  // Stats Row (Hidden for Kids to simplify)
                  if (!isKid)
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
                  if (!isKid) const SizedBox(height: 32),

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
                    ] else ...[
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
                              Icons.upload_file, // Icon for checkout/loan
                              () => context.push('/books'), // Navigate to books to select one
                              isPrimary: true,
                            ),
                            _buildActionButton(
                              context,
                              TranslationService.translate(context, 'action_search_remote'),
                              Icons.search,
                              () => context.push('/peers'), // Navigate to peers to search
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
  
                    // Books Sections
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth > 800;
                        final children = [
                          // Recent Books
                          if (_recentBooks.isNotEmpty)
                          Expanded(
                            flex: isWide ? 1 : 0,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildSectionTitle(context, TranslationService.translate(context, 'recent_books')),
                                const SizedBox(height: 16),
                                _recentBooks.length == 1
                                    ? _buildHeroBook(context, _recentBooks.first)
                                    : _buildBookList(context, _recentBooks, TranslationService.translate(context, 'no_recent_books'), delay: 0),
                              ],
                            ),
                          ),
                          if (_recentBooks.isNotEmpty && _readingListBooks.isNotEmpty)
                            SizedBox(width: 16, height: isWide ? 0 : 32),
                          // Reading List
                          if (_readingListBooks.isNotEmpty)
                          Expanded(
                            flex: isWide ? 1 : 0,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildSectionTitle(context, TranslationService.translate(context, 'reading_list')),
                                const SizedBox(height: 16),
                                _buildBookList(context, _readingListBooks, TranslationService.translate(context, 'no_reading_list'), delay: 200),
                              ],
                            ),
                          ),
                        ];
  
                        return isWide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: children,
                               )
                            : Column(
                                children: children.map((c) {
                                  if (c is Expanded) return c.child;
                                  return c;
                                }).toList(),
                              );
                      },
                    ),

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


  Widget _buildBookList(BuildContext context, List<Book> books, String emptyMessage, {int delay = 0}) {
    final theme = Theme.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: Opacity(
            opacity: value,
            child: child,
          ),
        );
      },
      child: Container(
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
      child: books.isEmpty
          ? Center(child: Text(emptyMessage))
          : Column(
              children: books
                  .map((book) => Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: theme.cardColor,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                          border: Border.all(
                            color: theme.dividerColor.withOpacity(0.1),
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(12),
                          leading: Container(
                            width: 40,
                            height: 60,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              color: Colors.grey[200],
                              image: book.coverUrl != null
                                  ? DecorationImage(
                                      image: NetworkImage(book.coverUrl!),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                            ),
                            child: book.coverUrl == null
                                ? const Icon(Icons.book, color: Colors.grey, size: 20)
                                : null,
                          ),
                          title: Text(
                            book.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                book.author ?? TranslationService.translate(context, 'unknown_author'),
                                style: TextStyle(
                                  color: theme.textTheme.bodySmall?.color,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (book.readingStatus != null) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.primaryColor.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    book.readingStatus!
                                        .replaceAll('_', ' ')
                                        .toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: theme.primaryColor,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          onTap: () =>
                              context.push('/books/${book.id}/edit', extra: book),
                        ),
                      ))
                  .toList(),
            ),
    ),
    );
  }

  Widget _buildHeroBook(BuildContext context, Book book) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover Image
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: book.coverUrl != null
                  ? Image.network(
                      book.coverUrl!,
                      width: 100,
                      height: 150,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        width: 100,
                        height: 150,
                        color: Colors.grey[300],
                        child: const Center(
                          child: Icon(Icons.book, size: 40, color: Colors.grey),
                        ),
                      ),
                    )
                  : Container(
                      width: 100,
                      height: 150,
                      color: theme.primaryColor,
                      child: const Center(
                        child: Icon(Icons.book, size: 40, color: Colors.white),
                      ),
                    ),
            ),
            const SizedBox(width: 16),
            
            // Details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    book.author ?? TranslationService.translate(context, 'unknown_author'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.textTheme.bodySmall?.color,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (book.summary != null) ...[
                    Text(
                      book.summary!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.textTheme.bodySmall?.color,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (book.readingStatus != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: theme.primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            book.readingStatus!.replaceAll('_', ' ').toUpperCase(),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: theme.primaryColor,
                            ),
                          ),
                        ),
                      ElevatedButton(
                        onPressed: () => context.push('/books/${book.id}/edit', extra: book),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(TranslationService.translate(context, 'btn_details')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
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
