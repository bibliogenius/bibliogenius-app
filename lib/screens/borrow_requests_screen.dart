import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../widgets/genie_app_bar.dart';
import '../widgets/scaffold_with_nav.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'dart:async';
import '../data/repositories/copy_repository.dart';
import '../data/repositories/loan_repository.dart';
import '../models/loan.dart';
import '../services/api_service.dart';
import '../services/ffi_service.dart';
import '../services/translation_service.dart';
import '../providers/hub_directory_provider.dart';
import '../providers/theme_provider.dart';
import '../src/rust/api/frb.dart' show FrbHubBorrowRequest;
import '../widgets/premium_empty_state.dart';

/// Screen for managing loans, borrows, and P2P requests
/// Structure:
/// - Demandes (Requests): Incoming/Outgoing/Connections (only if networkEnabled)
/// - Prêtés (Lent): Books you lent to others
/// - Empruntés (Borrowed): Books you borrowed from others (hidden if canBorrowBooks=false)
class LoansScreen extends StatefulWidget {
  final bool isTabView;

  /// Initial tab to show: 'requests', 'lent', or 'borrowed'
  final String? initialTab;

  /// Initial status filter: 'active', 'overdue', 'returned'
  final String? initialStatusFilter;

  const LoansScreen({super.key, this.isTabView = false, this.initialTab, this.initialStatusFilter});

  @override
  State<LoansScreen> createState() => _LoansScreenState();
}

class _LoansScreenState extends State<LoansScreen>
    with TickerProviderStateMixin {
  Timer? _refreshTimer;
  late TabController _mainTabController;
  late TabController _requestsTabController;
  bool _isLoading = false;

  // Requests data
  List<dynamic> _incomingRequests = [];
  List<dynamic> _outgoingRequests = [];
  List<dynamic> _connectionRequests = [];

  /// Request IDs with a pending status update (optimistic UI).
  /// While an ID is in this set, actions are disabled and a spinner is shown.
  final Set<String> _pendingActions = {};

  // Loans data
  List<Loan> _activeLoans = []; // Books I lent to others
  List<dynamic> _borrowedBooks = []; // Books I borrowed from others

  /// ISBN -> local book ID mapping for hub requests "View book" links
  Map<String, int> _isbnToLocalBookId = {};

  // Search & filters
  final _lentSearchController = TextEditingController();
  final _borrowedSearchController = TextEditingController();
  String _lentSearchQuery = '';
  String _borrowedSearchQuery = '';
  late String _lentStatusFilter; // all, active, overdue, returned
  late String _borrowedStatusFilter; // all, active, overdue
  String? _lentMonthFilter; // 'YYYY-MM' or null (all)
  String? _borrowedMonthFilter;

  @override
  void initState() {
    super.initState();
    // Apply initial status filter if provided (e.g. from dashboard "en cours" tap)
    final statusFilter = widget.initialStatusFilter;
    _lentStatusFilter = (statusFilter != null && ['active', 'overdue', 'returned'].contains(statusFilter))
        ? statusFilter
        : 'all';
    _borrowedStatusFilter = (statusFilter != null && ['active', 'overdue'].contains(statusFilter))
        ? statusFilter
        : 'all';
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final hubProvider = Provider.of<HubDirectoryProvider>(context, listen: false);
    // Show "Demandes" tab if LAN discovery, relay sharing, or hub is active
    final hasPeerNetwork =
        themeProvider.networkEnabled || themeProvider.remoteReachableEnabled || hubProvider.isRegistered;
    // Tab count depends on:
    // - hasPeerNetwork: show "Demandes" tab if any peer connectivity is active
    // - canBorrowBooks: show "Empruntés" tab only if borrowing is enabled
    int tabCount = 1; // At minimum: Prêtés
    if (hasPeerNetwork) tabCount++; // +Demandes
    if (themeProvider.canBorrowBooks) tabCount++; // +Empruntés

    // Calculate initial tab index based on initialTab parameter
    int initialIndex = 0;
    if (widget.initialTab != null) {
      if (widget.initialTab == 'lent') {
        // Lent is after Requests (if enabled), otherwise first
        initialIndex = hasPeerNetwork ? 1 : 0;
      } else if (widget.initialTab == 'borrowed' &&
          themeProvider.canBorrowBooks) {
        // Borrowed is last tab
        initialIndex = tabCount - 1;
      }
      // 'requests' stays at 0 (default)
    }

    _mainTabController = TabController(
      length: tabCount,
      vsync: this,
      initialIndex: initialIndex,
    );
    _requestsTabController = TabController(
      length: themeProvider.connectionValidationEnabled ? 3 : 2,
      vsync: this,
    );
    _fetchAllData();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _fetchAllData(silent: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _mainTabController.dispose();
    _requestsTabController.dispose();
    _lentSearchController.dispose();
    _borrowedSearchController.dispose();
    super.dispose();
  }

  Future<void> _fetchAllData({bool silent = false}) async {
    if (!silent && mounted) setState(() => _isLoading = true);
    final api = Provider.of<ApiService>(context, listen: false);
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);

    try {
      // Fetch P2P requests if any peer connectivity is active (LAN or relay)
      final hasPeerNetwork =
          themeProvider.networkEnabled || themeProvider.remoteReachableEnabled;
      if (hasPeerNetwork) {
        final inRes = await api.getIncomingRequests();
        final outRes = await api.getOutgoingRequests();
        final connRes = await api.getPendingPeers();

        if (mounted) {
          _incomingRequests = inRes.data;
          _outgoingRequests = outRes.data;
          _connectionRequests = connRes.data['requests'] ?? [];
        }
      }

      // Fetch hub borrow requests (independent from P2P network)
      final hubProvider = Provider.of<HubDirectoryProvider>(context, listen: false);
      if (hubProvider.isRegistered) {
        await Future.wait([
          hubProvider.loadIncomingHubRequests(),
          hubProvider.loadOutgoingHubRequests(),
        ]);

        // Resolve local book IDs for hub requests (enables "View book" link)
        final allHubIsbns = <String>{
          ...hubProvider.incomingHubRequests.map((r) => r.isbn),
          ...hubProvider.outgoingHubRequests.map((r) => r.isbn),
        }.where((isbn) => isbn.isNotEmpty);
        final resolvedMap = <String, int>{};
        for (final isbn in allHubIsbns) {
          final book = await api.findBookByIsbn(isbn);
          if (book != null && book.id != null) {
            resolvedMap[isbn] = book.id!;
          }
        }
        _isbnToLocalBookId = resolvedMap;
      }

      // Fetch all loans (books I lent) - enables filtering by status
      final loanRepo = Provider.of<LoanRepository>(context, listen: false);
      final activeLoans = await loanRepo.getLoans();

      List<dynamic> borrowedBooks = [];
      if (themeProvider.canBorrowBooks) {
        try {
          // Borrowed books are stored as temporary copies, not loans
          final borrowedRes = await api.getBorrowedCopies();
          borrowedBooks = borrowedRes.data['loans'] ?? [];
        } catch (e) {
          debugPrint('Could not fetch borrowed books: $e');
        }
      }

      if (mounted) {
        setState(() {
          _activeLoans = activeLoans;
          _borrowedBooks = borrowedBooks;
        });
      }
    } catch (e) {
      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              "${TranslationService.translate(context, 'snack_error_fetching')}: $e",
            ),
          ),
        );
      }
    } finally {
      if (mounted && !silent) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _updateRequestStatus(String id, String status) async {
    // Optimistic UI: mark this request as pending immediately
    if (mounted) {
      setState(() {
        _pendingActions.add(id);
        // Optimistically update the status in local lists
        _optimisticallyUpdateStatus(id, status);
      });
    }

    final api = Provider.of<ApiService>(context, listen: false);
    try {
      await api.updateRequestStatus(id, status);
      if (mounted) {
        setState(() => _pendingActions.remove(id));
        _fetchAllData(silent: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _pendingActions.remove(id));
        _fetchAllData(silent: true); // Revert to real state
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_getFriendlyErrorMessage(e))));
      }
    }
  }

  /// Optimistically update a request's status in the local lists.
  void _optimisticallyUpdateStatus(String id, String newStatus) {
    for (final req in _incomingRequests) {
      if (req['id']?.toString() == id) {
        req['status'] = newStatus;
        return;
      }
    }
    for (final req in _outgoingRequests) {
      if (req['id']?.toString() == id) {
        req['status'] = newStatus;
        return;
      }
    }
  }

  Future<void> _returnLoan(int loanId) async {
    final loanRepo = Provider.of<LoanRepository>(context, listen: false);
    try {
      await loanRepo.returnLoan(loanId);
      _fetchAllData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'snack_loan_returned'),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_getFriendlyErrorMessage(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final bool isMobile = width <= 600;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final canBorrow = themeProvider.canBorrowBooks;
    final networkEnabled =
        themeProvider.networkEnabled || themeProvider.remoteReachableEnabled;

    if (widget.isTabView) {
      return Column(
        children: [
          Container(
            color: Theme.of(context).primaryColor,
            child: TabBar(
              controller: _mainTabController,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              indicatorColor: Colors.white,
              tabs: [
                if (networkEnabled)
                  Tab(
                    key: const Key('requestsTab'),
                    icon: const Icon(Icons.mail_outline),
                    text: TranslationService.translate(context, 'tab_requests'),
                  ),
                Tab(
                  key: const Key('lentTab'),
                  icon: const Icon(Icons.arrow_upward),
                  text: TranslationService.translate(context, 'tab_lent'),
                ),
                if (canBorrow)
                  Tab(
                    key: const Key('borrowedTab'),
                    icon: const Icon(Icons.arrow_downward),
                    text: TranslationService.translate(context, 'tab_borrowed'),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _mainTabController,
                    children: [
                      if (networkEnabled) _buildRequestsTab(),
                      _buildLentTab(),
                      if (canBorrow) _buildBorrowedTab(),
                    ],
                  ),
          ),
        ],
      );
    }

    return Scaffold(
      appBar: GenieAppBar(
        title: TranslationService.translate(context, 'loans_menu'),
        leading: buildDrawerLeading(context),
        automaticallyImplyLeading: false,
        bottom: TabBar(
          controller: _mainTabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [
            if (networkEnabled)
              Tab(
                key: const Key('requestsTab'),
                icon: const Icon(Icons.mail_outline),
                text: TranslationService.translate(context, 'tab_requests'),
              ),
            Tab(
              key: const Key('lentTab'),
              icon: const Icon(Icons.arrow_upward),
              text: TranslationService.translate(context, 'tab_lent'),
            ),
            if (canBorrow)
              Tab(
                key: const Key('borrowedTab'),
                icon: const Icon(Icons.arrow_downward),
                text: TranslationService.translate(context, 'tab_borrowed'),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _fetchAllData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _mainTabController,
              children: [
                if (networkEnabled) _buildRequestsTab(),
                _buildLentTab(),
                if (canBorrow) _buildBorrowedTab(),
              ],
            ),
    );
  }

  /// Requests tab with nested tabs (Incoming/Outgoing/Connections)
  Widget _buildRequestsTab() {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final hubProvider = Provider.of<HubDirectoryProvider>(context, listen: false);
    final showConnections = themeProvider.connectionValidationEnabled;

    final incomingCount = _filterRecentP2pRequests(_incomingRequests).length
        + _filterRecentHubRequests(hubProvider.incomingHubRequests).length;
    final outgoingCount = _filterRecentP2pRequests(_outgoingRequests).length
        + _filterRecentHubRequests(hubProvider.outgoingHubRequests).length;

    return Column(
      children: [
        Material(
          color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
          child: TabBar(
            controller: _requestsTabController,
            labelColor: Theme.of(context).colorScheme.primary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Theme.of(context).colorScheme.primary,
            tabs: [
              Tab(
                text:
                    '${TranslationService.translate(context, 'tab_received')} ($incomingCount)',
              ),
              Tab(
                text:
                    '${TranslationService.translate(context, 'tab_sent')} ($outgoingCount)',
              ),
              if (showConnections)
                Tab(
                  text:
                      '${TranslationService.translate(context, 'tab_connections')} (${_connectionRequests.length})',
                ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _requestsTabController,
            children: [
              RefreshIndicator(
                onRefresh: _fetchAllData,
                child: _buildIncomingList(),
              ),
              RefreshIndicator(
                onRefresh: _fetchAllData,
                child: _buildOutgoingList(),
              ),
              if (showConnections)
                RefreshIndicator(
                  onRefresh: _fetchAllData,
                  child: _buildConnectionList(),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Lent tab - books I lent to others
  Widget _buildLentTab() {
    if (_activeLoans.isEmpty) {
      return PremiumEmptyState(
        message: TranslationService.translate(context, 'empty_no_loans'),
        description:
            TranslationService.translate(context, 'empty_no_loans_hint'),
        icon: Icons.arrow_upward,
        buttonLabel:
            TranslationService.translate(context, 'go_to_library'),
        onAction: () => context.go('/books'),
      );
    }

    final query = _lentSearchQuery.toLowerCase();
    final filtered = _activeLoans.where((loan) {
      // Status filter
      if (_lentStatusFilter == 'active') {
        if (loan.isReturned) return false;
        final overdue = loan.dueDate.isNotEmpty &&
            DateTime.tryParse(loan.dueDate)?.isBefore(DateTime.now()) == true;
        if (overdue) return false;
      } else if (_lentStatusFilter == 'overdue') {
        if (loan.isReturned) return false;
        final overdue = loan.dueDate.isNotEmpty &&
            DateTime.tryParse(loan.dueDate)?.isBefore(DateTime.now()) == true;
        if (!overdue) return false;
      } else if (_lentStatusFilter == 'returned') {
        if (!loan.isReturned) return false;
      }
      // Month filter
      if (_lentMonthFilter != null) {
        if (!loan.loanDate.startsWith(_lentMonthFilter!)) return false;
      }
      // Text search
      if (query.isNotEmpty) {
        return loan.bookTitle.toLowerCase().contains(query) ||
            loan.contactName.toLowerCase().contains(query);
      }
      return true;
    }).toList();

    // Sort: active/overdue first, returned last
    if (_lentStatusFilter == 'all') {
      filtered.sort((a, b) {
        if (a.isReturned != b.isReturned) return a.isReturned ? 1 : -1;
        return 0;
      });
    }

    return RefreshIndicator(
      onRefresh: _fetchAllData,
      child: Column(
        children: [
          _buildSearchField(
            controller: _lentSearchController,
            onChanged: (v) => setState(() => _lentSearchQuery = v),
          ),
          _buildStatusChips(
            current: _lentStatusFilter,
            options: const ['all', 'active', 'overdue', 'returned'],
            onSelected: (v) => setState(() => _lentStatusFilter = v),
          ),
          _buildMonthFilter(
            dates: _activeLoans.map((l) => l.loanDate).toList(),
            current: _lentMonthFilter,
            onSelected: (v) => setState(() => _lentMonthFilter = v),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: _cleanReturnedLoans,
                  icon: const Icon(Icons.cleaning_services, size: 18),
                  label: Text(
                    TranslationService.translate(context, 'clean_returned_loans'),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      TranslationService.translate(context, 'no_results'),
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                  )
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      return _buildLoanTile(filtered[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _cleanReturnedLoans() async {
    final ffi = FfiService();
    final count = await ffi.countReturnedLoans();

    if (!mounted) return;

    if (count == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            TranslationService.translate(context, 'clean_returned_loans_empty'),
          ),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          TranslationService.translate(context, 'clean_returned_loans'),
        ),
        content: Text(
          TranslationService.translate(context, 'clean_returned_loans_confirm')
              .replaceAll('%d', count.toString()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(TranslationService.translate(context, 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(TranslationService.translate(context, 'confirm')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final deleted = await ffi.deleteReturnedLoans();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'clean_returned_loans_success')
                  .replaceAll('%d', deleted.toString()),
            ),
            backgroundColor: Colors.green,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  Widget _buildLoanTile(Loan loan) {
    final bookTitle = loan.bookTitle.isNotEmpty ? loan.bookTitle : 'Unknown';
    final contactName = loan.contactName.isNotEmpty ? loan.contactName : 'Unknown';
    final loanDate = loan.loanDate;
    final dueDate = loan.dueDate;
    final loanId = loan.id;
    final bookId = loan.bookId;
    final returned = loan.isReturned;
    final cover = loan.resolvedCoverUrl;

    final isOverdue = !returned &&
        dueDate.isNotEmpty &&
        DateTime.tryParse(dueDate)?.isBefore(DateTime.now()) == true;

    // Status badge
    final Color statusColor;
    final String statusLabel;
    if (returned) {
      statusColor = Colors.grey;
      statusLabel = TranslationService.translate(context, 'mark_returned');
    } else if (isOverdue) {
      statusColor = Colors.red;
      statusLabel = TranslationService.translate(context, 'filter_overdue');
    } else {
      statusColor = Colors.green;
      statusLabel = TranslationService.translate(context, 'filter_active');
    }

    final theme = Theme.of(context);

    return Card(
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          if (bookId != null) {
            GoRouter.of(context).push('/books/$bookId');
          } else {
            _navigateToLoanBook(loan);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Book cover
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 52,
                  height: 72,
                  child: cover != null
                      ? CachedNetworkImage(
                          imageUrl: cover,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: Icon(Icons.menu_book, color: theme.colorScheme.onSurfaceVariant, size: 24),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: Icon(Icons.menu_book, color: theme.colorScheme.onSurfaceVariant, size: 24),
                          ),
                        )
                      : Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Icon(Icons.menu_book, color: theme.colorScheme.onSurfaceVariant, size: 24),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bookTitle,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${TranslationService.translate(context, 'lent_to')}: $contactName',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (loanDate.isNotEmpty)
                          Text(
                            _formatDate(loanDate),
                            style: TextStyle(color: Colors.grey[600], fontSize: 11),
                          ),
                        if (loanDate.isNotEmpty && dueDate.isNotEmpty)
                          Text(' - ', style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                        if (dueDate.isNotEmpty)
                          Text(
                            _formatDate(dueDate),
                            style: TextStyle(
                              color: isOverdue ? Colors.red : Colors.grey[600],
                              fontSize: 11,
                              fontWeight: isOverdue ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Status + action
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: statusColor),
                    ),
                  ),
                  if (!returned) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 30,
                      child: FilledButton.icon(
                        onPressed: () => _returnLoan(loanId),
                        icon: const Icon(Icons.check, size: 14),
                        label: Text(
                          TranslationService.translate(context, 'btn_mark_returned'),
                          style: const TextStyle(fontSize: 11),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _navigateToLoanBook(Loan loan) async {
    final bookTitle = loan.bookTitle;
    if (bookTitle.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'book_not_found'),
            ),
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      final api = Provider.of<ApiService>(context, listen: false);
      final books = await api.getBooks(title: bookTitle);
      final ownedBooks = books.where((b) => b.owned).toList();

      if (ownedBooks.length == 1) {
        final bookId = ownedBooks.first.id;
        if (mounted) {
          GoRouter.of(context).push('/books/$bookId');
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${TranslationService.translate(context, 'book_not_found')}: ${ownedBooks.length} books found with this title.',
              ),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error navigating to loan book by title: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'book_not_found'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Status filter chips (Tous / En cours / En retard / Rendus)
  Widget _buildStatusChips({
    required String current,
    required List<String> options,
    required ValueChanged<String> onSelected,
  }) {
    const labelKeys = {
      'all': 'filter_all',
      'active': 'filter_active',
      'overdue': 'filter_overdue',
      'returned': 'filter_returned',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        height: 38,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: options.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final value = options[index];
            final selected = value == current;
            return FilterChip(
              label: Text(
                TranslationService.translate(
                  context,
                  labelKeys[value] ?? value,
                ),
                style: const TextStyle(fontSize: 12),
              ),
              selected: selected,
              onSelected: (_) => onSelected(value),
              showCheckmark: false,
              visualDensity: VisualDensity.compact,
            );
          },
        ),
      ),
    );
  }

  /// Month/year dropdown filter built from actual loan dates
  Widget _buildMonthFilter({
    required List<String> dates,
    required String? current,
    required ValueChanged<String?> onSelected,
  }) {
    // Extract unique YYYY-MM values, sorted descending
    final months = <String>{};
    for (final d in dates) {
      if (d.length >= 7) months.add(d.substring(0, 7));
    }
    if (months.length <= 1) return const SizedBox.shrink();

    final sorted = months.toList()..sort((a, b) => b.compareTo(a));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(Icons.calendar_month, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 6),
          Expanded(
            child: DropdownButton<String?>(
              value: current,
              isExpanded: true,
              isDense: true,
              underline: const SizedBox.shrink(),
              hint: Text(
                TranslationService.translate(context, 'filter_all_months'),
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(
                    TranslationService.translate(context, 'filter_all_months'),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                ...sorted.map((m) {
                  final label = _formatMonth(m);
                  return DropdownMenuItem<String?>(
                    value: m,
                    child: Text(label, style: const TextStyle(fontSize: 13)),
                  );
                }),
              ],
              onChanged: onSelected,
            ),
          ),
        ],
      ),
    );
  }

  /// Format 'YYYY-MM' into a localized month name + year
  String _formatMonth(String yearMonth) {
    try {
      final date = DateTime.parse('$yearMonth-01');
      final locale = Localizations.localeOf(context).toString();
      return DateFormat.yMMMM(locale).format(date);
    } catch (_) {
      return yearMonth;
    }
  }

  Widget _buildSearchField({
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: TranslationService.translate(context, 'search_loans'),
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  tooltip: TranslationService.translate(context, 'clear'),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                )
              : null,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
    );
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final locale = Localizations.localeOf(context).toString();
      return DateFormat.yMMMd(locale).format(date);
    } catch (e) {
      return dateStr;
    }
  }

  /// Borrowed tab - books I borrowed from others
  Widget _buildBorrowedTab() {
    if (_borrowedBooks.isEmpty) {
      return PremiumEmptyState(
        message: TranslationService.translate(context, 'empty_no_borrowed'),
        description:
            TranslationService.translate(context, 'empty_no_borrowed_hint'),
        icon: Icons.arrow_downward,
      );
    }

    final query = _borrowedSearchQuery.toLowerCase();
    final filtered = _borrowedBooks.where((book) {
      // Status filter
      if (_borrowedStatusFilter == 'overdue') {
        final notes = (book['notes'] ?? '').toString();
        final dateMatch = RegExp(r"jusqu'au\s+(\S+)").firstMatch(notes);
        final dueDate = dateMatch?.group(1) ?? '';
        final overdue = dueDate.isNotEmpty &&
            DateTime.tryParse(dueDate)?.isBefore(DateTime.now()) == true;
        if (!overdue) return false;
      }
      // Month filter
      if (_borrowedMonthFilter != null) {
        final dateStr = (book['acquisition_date'] ?? '').toString();
        if (!dateStr.startsWith(_borrowedMonthFilter!)) return false;
      }
      // Text search
      if (query.isNotEmpty) {
        final title = (book['title'] ?? '').toString().toLowerCase();
        final notes = (book['notes'] ?? '').toString().toLowerCase();
        return title.contains(query) || notes.contains(query);
      }
      return true;
    }).toList();

    return RefreshIndicator(
      onRefresh: _fetchAllData,
      child: Column(
        children: [
          _buildSearchField(
            controller: _borrowedSearchController,
            onChanged: (v) => setState(() => _borrowedSearchQuery = v),
          ),
          _buildStatusChips(
            current: _borrowedStatusFilter,
            options: const ['all', 'overdue'],
            onSelected: (v) => setState(() => _borrowedStatusFilter = v),
          ),
          _buildMonthFilter(
            dates: _borrowedBooks
                .map((b) => (b['acquisition_date'] ?? '').toString())
                .toList(),
            current: _borrowedMonthFilter,
            onSelected: (v) => setState(() => _borrowedMonthFilter = v),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      TranslationService.translate(context, 'no_results'),
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                  )
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      return _buildBorrowedBookTile(filtered[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildBorrowedBookTile(Map<String, dynamic> book) {
    final title = book['title'] ?? 'Unknown';
    final notes = book['notes'] as String? ?? '';
    final acquisitionDate = book['acquisition_date'] ?? '';
    final cover = book['cover'] as String?;
    final bookId = book['book_id'] as int? ?? book['id'] as int?;

    // Extract contact name and due date from notes
    // Format: "Emprunté de Name jusqu'au YYYY-MM-DD"
    String borrowedFrom = '';
    String dueDate = '';
    if (notes.isNotEmpty) {
      final nameMatch = RegExp(
        r"(?:Emprunté de|Borrowed from|Emprunté à)[:\s]*(.+?)(?:\s+jusqu|$)",
      ).firstMatch(notes);
      if (nameMatch != null) {
        borrowedFrom = nameMatch.group(1)?.trim() ?? '';
      }
      final dateMatch = RegExp(
        r"jusqu'au\s+(\S+)",
      ).firstMatch(notes);
      if (dateMatch != null) {
        dueDate = dateMatch.group(1)?.trim() ?? '';
      }
    }

    final isOverdue = dueDate.isNotEmpty &&
        DateTime.tryParse(dueDate)?.isBefore(DateTime.now()) == true;

    final theme = Theme.of(context);

    return Card(
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            bookId != null ? GoRouter.of(context).push('/books/$bookId') : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Book cover
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 52,
                  height: 72,
                  child: cover != null && cover.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: cover,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: Icon(Icons.menu_book, color: theme.colorScheme.onSurfaceVariant, size: 24),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: Icon(Icons.menu_book, color: theme.colorScheme.onSurfaceVariant, size: 24),
                          ),
                        )
                      : Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Icon(Icons.menu_book, color: theme.colorScheme.onSurfaceVariant, size: 24),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (borrowedFrom.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${TranslationService.translate(context, 'borrowed_from')}: $borrowedFrom',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (acquisitionDate.isNotEmpty)
                          Text(
                            _formatDate(acquisitionDate),
                            style: TextStyle(color: Colors.grey[600], fontSize: 11),
                          ),
                        if (acquisitionDate.isNotEmpty && dueDate.isNotEmpty)
                          Text(' - ', style: TextStyle(color: Colors.grey[600], fontSize: 11)),
                        if (dueDate.isNotEmpty)
                          Text(
                            _formatDate(dueDate),
                            style: TextStyle(
                              color: isOverdue ? Colors.red : Colors.grey[600],
                              fontSize: 11,
                              fontWeight: isOverdue ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Action
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (isOverdue ? Colors.red : Colors.blue).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: (isOverdue ? Colors.red : Colors.blue).withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      isOverdue
                          ? TranslationService.translate(context, 'filter_overdue')
                          : TranslationService.translate(context, 'filter_active'),
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isOverdue ? Colors.red : Colors.blue),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 30,
                    child: FilledButton.icon(
                      onPressed: () => _returnBorrowedBook(book),
                      icon: const Icon(Icons.check, size: 14),
                      label: Text(
                        TranslationService.translate(context, 'btn_mark_returned'),
                        style: const TextStyle(fontSize: 11),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _returnBorrowedBook(Map<String, dynamic> book) async {
    final copyId = book['id'] as int?;
    if (copyId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          TranslationService.translate(context, 'confirm_return_title'),
        ),
        content: Text(
          TranslationService.translate(context, 'confirm_return_borrowed'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(TranslationService.translate(context, 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(TranslationService.translate(context, 'confirm')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final api = Provider.of<ApiService>(context, listen: false);
        // Notify lender and clean up via backend
        await api.returnBorrowedBook(copyId: copyId);
        _fetchAllData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                TranslationService.translate(context, 'book_returned_success'),
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(_getFriendlyErrorMessage(e))));
        }
      }
    }
  }

  // === Request list builders (from original) ===

  /// Filter out non-pending P2P requests resolved more than 30 days ago
  List<dynamic> _filterRecentP2pRequests(List<dynamic> requests) {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    return requests.where((req) {
      if (req['status'] == 'pending') return true;
      final dateStr = req['updated_at'] as String? ?? req['created_at'] as String? ?? '';
      final date = DateTime.tryParse(dateStr);
      return date == null || date.isAfter(cutoff);
    }).toList();
  }

  /// Filter out non-pending Hub requests resolved more than 30 days ago
  List<FrbHubBorrowRequest> _filterRecentHubRequests(List<FrbHubBorrowRequest> requests) {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    return requests.where((req) {
      if (req.status == 'pending') return true;
      final dateStr = req.resolvedAt ?? req.createdAt;
      final date = DateTime.tryParse(dateStr);
      return date == null || date.isAfter(cutoff);
    }).toList();
  }

  Widget _buildIncomingList() {
    final hubProvider = Provider.of<HubDirectoryProvider>(context, listen: false);
    final hubIncoming = _filterRecentHubRequests(hubProvider.incomingHubRequests);
    final p2pFiltered = _filterRecentP2pRequests(_incomingRequests);
    final hasP2p = p2pFiltered.isNotEmpty;
    final hasHub = hubIncoming.isNotEmpty;

    if (!hasP2p && !hasHub) {
      return _buildEmptyState(
        TranslationService.translate(context, 'empty_no_incoming'),
      );
    }
    return Column(
      children: [
        if (_incomingRequests.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _cleanClosedRequests(isIncoming: true),
                  icon: const Icon(Icons.cleaning_services, size: 18),
                  label: Text(
                    TranslationService.translate(context, 'clean_closed_requests'),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView(
            children: [
              // P2P requests (filtered: hides non-pending older than 30 days)
              for (final req in p2pFiltered)
                _buildRequestTile(req, isIncoming: true),
              // Hub borrow requests (filtered)
              for (final req in hubIncoming)
                _buildHubRequestTile(req, isIncoming: true),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOutgoingList() {
    final hubProvider = Provider.of<HubDirectoryProvider>(context, listen: false);
    final hubOutgoing = _filterRecentHubRequests(hubProvider.outgoingHubRequests);
    final p2pFiltered = _filterRecentP2pRequests(_outgoingRequests);
    final hasP2p = p2pFiltered.isNotEmpty;
    final hasHub = hubOutgoing.isNotEmpty;

    if (!hasP2p && !hasHub) {
      return _buildEmptyState(
        TranslationService.translate(context, 'empty_no_outgoing'),
      );
    }
    return Column(
      children: [
        if (_outgoingRequests.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _cleanClosedRequests(isIncoming: false),
                  icon: const Icon(Icons.cleaning_services, size: 18),
                  label: Text(
                    TranslationService.translate(context, 'clean_closed_requests'),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView(
            children: [
              // P2P requests (filtered: hides non-pending older than 30 days)
              for (final req in p2pFiltered)
                _buildRequestTile(req, isIncoming: false),
              // Hub borrow requests (filtered)
              for (final req in hubOutgoing)
                _buildHubRequestTile(req, isIncoming: false),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _cleanClosedRequests({required bool isIncoming}) async {
    final ffi = FfiService();
    final count = isIncoming
        ? await ffi.countClosedIncomingRequests()
        : await ffi.countClosedOutgoingRequests();

    if (!mounted) return;

    if (count == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            TranslationService.translate(context, 'clean_closed_requests_empty'),
          ),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          TranslationService.translate(context, 'clean_closed_requests'),
        ),
        content: Text(
          TranslationService.translate(context, 'clean_closed_requests_confirm')
              .replaceAll('%d', count.toString()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(TranslationService.translate(context, 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(TranslationService.translate(context, 'confirm')),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final deleted = isIncoming
            ? await ffi.deleteClosedIncomingRequests()
            : await ffi.deleteClosedOutgoingRequests();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              TranslationService.translate(context, 'clean_closed_requests_success')
                  .replaceAll('%d', deleted.toString()),
            ),
            backgroundColor: Colors.green,
          ),
        );
        _fetchAllData();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  Future<bool> _confirmDeleteRequest(String id, String title) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(TranslationService.translate(context, 'delete')),
        content: Text(
          '${TranslationService.translate(context, 'request_delete_confirm')}\n"$title"',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(TranslationService.translate(context, 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(TranslationService.translate(context, 'delete')),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _deleteRequest(String id, {required bool isIncoming}) async {
    final api = Provider.of<ApiService>(context, listen: false);
    try {
      if (isIncoming) {
        await api.deleteRequest(id);
      } else {
        await api.deleteOutgoingRequest(id);
      }
      _fetchAllData(silent: true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  // === Hub borrow request tiles (ADR-018) ===

  Widget _buildHubRequestTile(FrbHubBorrowRequest req, {required bool isIncoming}) {
    final title = req.bookTitle.isNotEmpty ? req.bookTitle : req.isbn;
    final peerName = isIncoming
        ? (req.requesterDisplayName ?? req.requesterNodeId)
        : (req.lenderDisplayName ?? req.lenderNodeId);
    final status = req.status;
    final busyKey = 'hub_borrow_${req.id}';
    final hubProvider = Provider.of<HubDirectoryProvider>(context, listen: false);
    final isPending = hubProvider.isBusy(busyKey);

    final card = Card(
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getStatusColor(status),
          child: const Icon(Icons.book, color: Colors.white),
        ),
        title: Row(
          children: [
            Expanded(child: Text(title)),
            Tooltip(
              message: TranslationService.translate(context, 'hub_borrow_via_hub'),
              child: const Icon(Icons.cloud_outlined, size: 18, color: Colors.blueGrey),
            ),
          ],
        ),
        subtitle: Text(
          isIncoming
              ? '${TranslationService.translate(context, 'request_from')}: $peerName'
              : '${TranslationService.translate(context, 'request_to')}: $peerName',
        ),
        trailing: isPending
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : _buildStatusChip(status),
        onTap: isPending ? null : () => _showHubRequestActions(req, isIncoming: isIncoming),
      ),
    );

    return Dismissible(
      key: Key('hub_request_${req.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) => _confirmDeleteRequest(req.id.toString(), title),
      onDismissed: (_) => _deleteHubRequest(req, isIncoming: isIncoming),
      child: card,
    );
  }

  Future<void> _deleteHubRequest(FrbHubBorrowRequest req, {required bool isIncoming}) async {
    final hubProvider = Provider.of<HubDirectoryProvider>(context, listen: false);
    if (req.status == 'pending') {
      // Try to cancel/reject on the Hub
      bool success;
      if (isIncoming) {
        success = await hubProvider.resolveHubBorrowRequest(req.id.toInt(), 'reject');
      } else {
        success = await hubProvider.cancelHubBorrowRequest(req.id.toInt());
      }
      if (!mounted) return;
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(hubProvider.actionError ?? 'Error'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    } else {
      // Non-pending (accepted, rejected, cancelled) - just dismiss locally
      hubProvider.dismissHubRequest(req.id.toInt());
    }
    if (mounted) setState(() {});
  }

  void _showHubRequestActions(FrbHubBorrowRequest req, {required bool isIncoming}) {
    final status = req.status;
    final localBookId = _isbnToLocalBookId[req.isbn];
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // View book (only if the book exists locally)
            if (localBookId != null)
              ListTile(
                leading: Icon(Icons.menu_book, color: Theme.of(context).colorScheme.primary),
                title: Text(
                  TranslationService.translate(context, 'action_view_book'),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/books/$localBookId');
                },
              ),
            if (status == 'pending' && isIncoming) ...[
              ListTile(
                leading: const Icon(Icons.check, color: Colors.green),
                title: Text(
                  TranslationService.translate(context, 'action_approve'),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  final hubProvider = Provider.of<HubDirectoryProvider>(context, listen: false);
                  hubProvider.resolveHubBorrowRequest(req.id.toInt(), 'accept').then((_) {
                    if (mounted) setState(() {});
                  });
                },
              ),
              ListTile(
                leading: const Icon(Icons.close, color: Colors.red),
                title: Text(
                  TranslationService.translate(context, 'action_reject'),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  final hubProvider = Provider.of<HubDirectoryProvider>(context, listen: false);
                  hubProvider.resolveHubBorrowRequest(req.id.toInt(), 'reject').then((_) {
                    if (mounted) setState(() {});
                  });
                },
              ),
            ],
            // Delete/cancel option for all statuses
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: Text(
                TranslationService.translate(context, 'delete'),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _deleteHubRequest(req, isIncoming: isIncoming);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionList() {
    if (_connectionRequests.isEmpty) {
      return _buildEmptyState(
        TranslationService.translate(context, 'empty_no_connections'),
      );
    }
    return ListView.builder(
      itemCount: _connectionRequests.length,
      itemBuilder: (context, index) {
        return _buildConnectionTile(_connectionRequests[index]);
      },
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.local_library,
                size: 64,
                color: Colors.purple,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestTile(
    Map<String, dynamic> req, {
    required bool isIncoming,
  }) {
    final title = req['book_title'] ?? 'Unknown';
    final peerName = req['peer_name'] ?? 'Unknown';
    final status = req['status'] ?? 'pending';
    final id = req['id']?.toString() ?? '';
    final isPending = _pendingActions.contains(id);
    final peerId = req['peer_id'];
    final peerUrl = req['peer_url'] as String?;
    final coverUrl = req['cover_url'] as String?;
    final bookIsbn = req['book_isbn'] as String?;

    // Resolve cover: explicit URL, or OpenLibrary fallback from ISBN
    String? resolvedCover = coverUrl;
    if ((resolvedCover == null || resolvedCover.isEmpty) &&
        bookIsbn != null && bookIsbn.isNotEmpty) {
      resolvedCover = 'https://covers.openlibrary.org/b/isbn/$bookIsbn-M.jpg';
    }

    final card = Card(
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: SizedBox(
          width: 40,
          height: 56,
          child: resolvedCover != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: CachedNetworkImage(
                    imageUrl: resolvedCover,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      color: _getStatusColor(status).withValues(alpha: 0.2),
                      child: Icon(Icons.book, color: _getStatusColor(status), size: 20),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      color: _getStatusColor(status).withValues(alpha: 0.2),
                      child: Icon(Icons.book, color: _getStatusColor(status), size: 20),
                    ),
                  ),
                )
              : Container(
                  decoration: BoxDecoration(
                    color: _getStatusColor(status).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(Icons.book, color: _getStatusColor(status), size: 20),
                ),
        ),
        title: Text(title),
        subtitle: _buildPeerSubtitle(
          isIncoming: isIncoming,
          peerName: peerName,
          peerId: peerId,
          peerUrl: peerUrl,
        ),
        trailing: isPending
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : _buildStatusChip(status),
        onTap: isPending
            ? null
            : () => _showRequestActions(req, isIncoming: isIncoming),
      ),
    );

    return Dismissible(
      key: Key('request_$id'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) => _confirmDeleteRequest(id, title),
      onDismissed: (_) => _deleteRequest(id, isIncoming: isIncoming),
    child: card,
    );
  }

  Widget _buildPeerSubtitle({
    required bool isIncoming,
    required String peerName,
    required dynamic peerId,
    required String? peerUrl,
  }) {
    final label = isIncoming
        ? '${TranslationService.translate(context, 'request_from')}: '
        : '${TranslationService.translate(context, 'request_to')}: ';

    final canNavigate = peerId != null && peerUrl != null && peerUrl.isNotEmpty;

    if (!canNavigate) {
      return Text('$label$peerName');
    }

    return GestureDetector(
      onTap: () {
        context.go('/peers/$peerId/books', extra: {
          'id': peerId,
          'name': peerName,
          'url': peerUrl,
          'hasRelayCredentials': false,
          'nodeId': null,
        });
      },
      child: Text.rich(
        TextSpan(
          text: label,
          children: [
            TextSpan(
              text: peerName,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                decoration: TextDecoration.underline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionTile(Map<String, dynamic> peer) {
    final name = peer['name'] ?? 'Unknown';
    final url = peer['url'] ?? '';

    return Card(
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person_add)),
        title: Text(name),
        subtitle: Text(url),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.check, color: Colors.green),
              onPressed: () => _acceptConnection(peer),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.red),
              onPressed: () => _rejectConnection(peer),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'accepted':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'pending':
      default:
        return Colors.orange;
    }
  }

  Widget _buildStatusChip(String status) {
    return Chip(
      label: Text(
        TranslationService.translate(context, 'status_$status'),
        style: const TextStyle(fontSize: 12, color: Colors.white),
      ),
      backgroundColor: _getStatusColor(status),
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  void _showRequestActions(
    Map<String, dynamic> req, {
    required bool isIncoming,
  }) {
    final id = req['id']?.toString() ?? '';
    final status = req['status'] ?? 'pending';
    final bookId = req['book_id'] as int?;

    if (_pendingActions.contains(id)) return;

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // View book (only if the book exists locally)
            if (bookId != null)
              ListTile(
                leading: Icon(Icons.menu_book, color: Theme.of(context).colorScheme.primary),
                title: Text(
                  TranslationService.translate(context, 'action_view_book'),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/books/$bookId');
                },
              ),
            if (status == 'pending' && isIncoming) ...[
              ListTile(
                leading: const Icon(Icons.check, color: Colors.green),
                title: Text(
                  TranslationService.translate(context, 'action_approve'),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _updateRequestStatus(id, 'accepted');
                },
              ),
              ListTile(
                leading: const Icon(Icons.close, color: Colors.red),
                title: Text(
                  TranslationService.translate(context, 'action_reject'),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _updateRequestStatus(id, 'rejected');
                },
              ),
            ] else if (status == 'pending' && !isIncoming) ...[
              ListTile(
                leading: const Icon(Icons.cancel, color: Colors.orange),
                title: Text(
                  TranslationService.translate(context, 'action_cancel'),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteRequest(id, isIncoming: false);
                },
              ),
            ],
            // Delete option for all statuses
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: Text(
                TranslationService.translate(context, 'delete'),
              ),
              onTap: () {
                Navigator.pop(ctx);
                _deleteRequest(id, isIncoming: isIncoming);
              },
            ),
          ],
        ),
      ),
    );
  }

  // Replaced by _deleteRequest(id, isIncoming:) above

  Future<void> _acceptConnection(Map<String, dynamic> peer) async {
    final api = Provider.of<ApiService>(context, listen: false);
    try {
      await api.updatePeerStatus(peer['id'], 'active');
      _fetchAllData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_getFriendlyErrorMessage(e))));
      }
    }
  }

  Future<void> _rejectConnection(Map<String, dynamic> peer) async {
    final api = Provider.of<ApiService>(context, listen: false);
    try {
      await api.updatePeerStatus(peer['id'], 'rejected');
      _fetchAllData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_getFriendlyErrorMessage(e))));
      }
    }
  }

  String _getFriendlyErrorMessage(Object error) {
    if (error is DioException) {
      if (error.response?.statusCode == 409) {
        final body = error.response?.data?['error']?.toString() ?? '';
        if (body.contains('No available copies') || body.contains('No copy found')) {
          return TranslationService.translate(context, 'error_no_available_copy');
        }
        return TranslationService.translate(context, 'error_409_conflict');
      }
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout) {
        return TranslationService.translate(context, 'error_peer_timeout');
      }
      if (error.type == DioExceptionType.connectionError) {
        return TranslationService.translate(context, 'error_peer_offline');
      }
      return error.response?.data?['error']?.toString() ??
          error.message ??
          error.toString();
    }
    return error.toString();
  }
}

// Keep old class name for backward compatibility with routing
class BorrowRequestsScreen extends LoansScreen {
  const BorrowRequestsScreen({super.key});
}
