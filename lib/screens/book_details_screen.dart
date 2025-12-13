import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/book.dart';
import '../models/contact.dart';
import '../services/api_service.dart';
import '../services/translation_service.dart';
import '../widgets/genie_app_bar.dart'; // Assuming we might want to use common widgets, but for this specific design we want a SliverAppBar
import '../widgets/star_rating_widget.dart';
import '../widgets/loan_dialog.dart';

class BookDetailsScreen extends StatefulWidget {
  final Book book;

  const BookDetailsScreen({super.key, required this.book});

  @override
  State<BookDetailsScreen> createState() => _BookDetailsScreenState();
}

class _BookDetailsScreenState extends State<BookDetailsScreen> {
  late Book _book;

  @override
  void initState() {
    super.initState();
    _book = widget.book;
    _fetchBookDetails();
  }

  Future<void> _fetchBookDetails() async {
    final api = Provider.of<ApiService>(context, listen: false);
    try {
      if (_book.id == null) return;
      
      final freshBook = await api.getBook(_book.id!);
      if (mounted) {
        setState(() {
          _book = freshBook;
        });
      }
    } catch (e) {
      debugPrint('Error fetching book details: $e');
    }
  }

  Future<void> _updateRating(int? newRating) async {
    final api = Provider.of<ApiService>(context, listen: false);
    try {
      await api.updateBook(_book.id!, {
        'title': _book.title,
        'user_rating': newRating,
      });
      setState(() {
        _book = _book.copyWithRating(newRating);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating rating: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Use large cover URL if available, otherwise fallback
    final coverUrl = _book.largeCoverUrl ?? _book.coverUrl;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(context, coverUrl),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(context),
                  const SizedBox(height: 24),
                  _buildActionButtons(context),
                  const SizedBox(height: 32),
                  _buildMetadataGrid(context),
                  const SizedBox(height: 32),
                  if (_book.summary != null && _book.summary!.isNotEmpty) ...[
                    Text(
                      TranslationService.translate(context, 'book_summary') ?? 'Summary',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _book.summary!,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            height: 1.6,
                            color: Colors.grey[700],
                          ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar(BuildContext context, String? coverUrl) {
    return SliverAppBar(
      expandedHeight: 400.0,
      pinned: true,
      stretch: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Blurry Background
            if (coverUrl != null)
              Image.network(
                coverUrl,
                fit: BoxFit.cover,
              )
            else
              Container(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                child: Center(
                  child: Icon(
                    Icons.book,
                    size: 100,
                    color: Theme.of(context).primaryColor.withValues(alpha: 0.3),
                  ),
                ),
              ),
            // Blur Effect
            if (coverUrl != null)
              BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  color: Colors.black.withValues(alpha: 0.4),
                ),
              ),
            
            // Hero Image
            Center(
              child: Hero(
                tag: 'book_cover_${_book.id}',
                child: Container(
                  width: 200,
                  height: 300,
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ], 
                    borderRadius: BorderRadius.circular(8), // Book-like rounded corners
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: coverUrl != null
                        ? Image.network(
                            coverUrl,
                            fit: BoxFit.cover,
                          )
                        : Container(
                            color: Colors.grey[300],
                            child: const Icon(Icons.book, size: 64, color: Colors.grey),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _book.title,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: Theme.of(context).textTheme.titleLarge?.color,
              ),
        ),
        if (_book.author != null) ...[
          const SizedBox(height: 8),
          Text(
            _book.author!,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final isReading = _book.readingStatus == 'reading';
    final isToRead = _book.readingStatus == 'to_read' || _book.readingStatus == null;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
                child: Tooltip(
                  message: TranslationService.translate(context, 'menu_edit') ?? 'Edit Book',
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final result = await context.push('/books/${_book.id}/edit', extra: _book);
                      if (result == true && context.mounted) {
                         Navigator.of(context).pop(true);
                      }
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(TranslationService.translate(context, 'menu_edit') ?? 'Edit'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Tooltip(
                  message: TranslationService.translate(context, 'menu_manage_copies') ?? 'Manage Copies',
                  child: OutlinedButton.icon(
                    onPressed: () {
                       context.push(
                        '/books/${_book.id}/copies',
                        extra: {
                          'bookId': _book.id,
                          'bookTitle': _book.title
                        },
                      );
                    },
                    icon: const Icon(Icons.library_books_outlined),
                    label: Text(TranslationService.translate(context, 'menu_manage_copies') ?? 'Copies'),
                     style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
            ),
            const SizedBox(width: 12),
            Tooltip(
              message: TranslationService.translate(context, 'menu_delete') ?? 'Delete Book',
              child: IconButton(
                onPressed: () => _confirmDelete(context),
                icon: const Icon(Icons.delete_outline, color: Colors.deepOrange),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.deepOrange.withValues(alpha: 0.1),
                  padding: const EdgeInsets.all(12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
        if (isToRead) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _startReading(context),
              icon: const Icon(Icons.play_circle_outline),
              label: Text(TranslationService.translate(context, 'start_reading') ?? 'Start Reading'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
        if (isReading) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _markAsFinished(context),
              icon: const Icon(Icons.check_circle_outline),
              label: Text(TranslationService.translate(context, 'mark_as_finished') ?? 'Mark as Finished'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
        // Lend book button - only visible when book is not borrowed
        if (_book.readingStatus != 'borrowed') ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _lendBook(context),
              icon: const Icon(Icons.handshake_outlined),
              label: Text(TranslationService.translate(context, 'lend_book_btn') ?? 'Lend this book'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.purple,
                side: const BorderSide(color: Colors.purple),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
        // Return book button - only visible when book is borrowed
        if (_book.readingStatus == 'borrowed') ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _returnBook(context),
              icon: const Icon(Icons.assignment_return_outlined),
              label: Text(TranslationService.translate(context, 'return_book_btn') ?? 'Return this book'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMetadataGrid(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _buildMetadataItem(
                context, 
                TranslationService.translate(context, 'year_label') ?? 'Year', 
                _book.publicationYear?.toString() ?? '-'
              ),
              _buildMetadataItem(
                context, 
                TranslationService.translate(context, 'publisher_label') ?? 'Publisher', 
                _book.publisher ?? '-'
              ),
            ],
          ),
          const Divider(height: 32),
          Row(
            children: [
               _buildMetadataItem(context, 'ISBN', _book.isbn ?? '-'),
               _buildMetadataItem(
                 context, 
                 TranslationService.translate(context, 'status_label') ?? 'Status', 
                 _translateStatus(context, _book.readingStatus)
               ),
            ],
          ),
          // Rating section
          const Divider(height: 32),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (TranslationService.translate(context, 'rating_label') ?? 'MY RATING').toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.0,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    StarRatingWidget(
                      rating: _book.userRating,
                      onRatingChanged: _updateRating,
                      size: 32,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if ((_book.readingStatus == 'reading' || _book.readingStatus == 'read') && _book.startedReadingAt != null) ...[
            const Divider(height: 32),
            Row(
              children: [
                _buildMetadataItem(
                  context, 
                  TranslationService.translate(context, 'started_on') ?? 'Started', 
                  _formatDate(_book.startedReadingAt!)
                ),
              ],
            ),
          ],
          if (_book.readingStatus == 'read' && _book.finishedReadingAt != null) ...[
            const Divider(height: 32),
            Row(
              children: [
                _buildMetadataItem(
                  context, 
                  TranslationService.translate(context, 'finished_on') ?? 'Finished', 
                  _formatDate(_book.finishedReadingAt!)
                ),
              ],
            ),
          ],
          if (_book.subjects != null && _book.subjects!.isNotEmpty) ...[
            const Divider(height: 32),
            SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.local_offer_outlined, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 6),
                      Text(
                        (TranslationService.translate(context, 'tags') ?? 'TAGS').toUpperCase(),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 10,
                    children: _book.subjects!.asMap().entries.map((entry) {
                      final index = entry.key;
                      final subject = entry.value;
                      // Cycle through colors for visual variety
                      final colors = [
                        Colors.blue,
                        Colors.teal,
                        Colors.purple,
                        Colors.orange,
                        Colors.pink,
                        Colors.indigo,
                      ];
                      final chipColor = colors[index % colors.length];
                      
                      return Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () {
                            context.go(Uri(path: '/books', queryParameters: {'tag': subject}).toString());
                          },
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  chipColor.withValues(alpha: 0.15),
                                  chipColor.withValues(alpha: 0.08),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: chipColor.withValues(alpha: 0.3),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.tag,
                                  size: 14,
                                  color: chipColor,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  subject,
                                  style: TextStyle(
                                    color: chipColor.shade700,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],

        ],
      ),
    );
  }

  String _translateStatus(BuildContext context, String? status) {
    if (status == 'read') return TranslationService.translate(context, 'reading_status_read') ?? 'Read';
    if (status == 'reading') return TranslationService.translate(context, 'reading_status_reading') ?? 'Reading';
    if (status == 'to_read') return TranslationService.translate(context, 'reading_status_to_read') ?? 'To Read';
    if (status == 'wanted' || status == 'wanting') return TranslationService.translate(context, 'reading_status_wanting') ?? 'Wanted';
    if (status == 'borrowed') return TranslationService.translate(context, 'borrowed_label') ?? 'Borrowed';
    return status?.replaceAll('_', ' ').toUpperCase() ?? '-';
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  Widget _buildMetadataItem(BuildContext context, String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.0,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
             maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Future<void> _startReading(BuildContext context) async {
    await _showStatusChangeOptions(
      context,
      'reading',
      TranslationService.translate(context, 'start_reading') ?? 'Start Reading',
    );
  }

  Future<void> _markAsFinished(BuildContext context) async {
    await _showStatusChangeOptions(
      context,
      'read',
      TranslationService.translate(context, 'mark_as_finished') ?? 'Mark as Finished',
    );
  }

  Future<void> _showStatusChangeOptions(BuildContext context, String newStatus, String title) async {
    final option = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.today),
              title: Text(TranslationService.translate(context, 'date_select_option_today') ?? 'Today'),
              onTap: () => Navigator.pop(context, 'today'),
            ),
            ListTile(
              leading: const Icon(Icons.calendar_month),
              title: Text(TranslationService.translate(context, 'date_select_option_pick') ?? 'Pick a date'),
              onTap: () => Navigator.pop(context, 'pick'),
            ),
            ListTile(
              leading: const Icon(Icons.history),
              title: Text(TranslationService.translate(context, 'date_select_option_none') ?? 'No date'),
              onTap: () => Navigator.pop(context, 'none'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );

    if (option == null || !context.mounted) return;

    DateTime? selectedDate;
    final now = DateTime.now();

    if (option == 'today') {
      selectedDate = now;
    } else if (option == 'pick') {
      selectedDate = await showDatePicker(
        context: context,
        initialDate: now,
        firstDate: DateTime(1900),
        lastDate: now,
      );
      if (selectedDate == null) return; // User cancelled picker
    } else {
      selectedDate = null;
    }

    if (!context.mounted) return;

    final apiService = Provider.of<ApiService>(context, listen: false);
    try {
      final Map<String, dynamic> updateData = {
        'title': _book.title,
        'reading_status': newStatus,
      };

      if (newStatus == 'reading') {
        // If we have a date, set it. If we chose 'none', we might want to explicity set it to null 
        // OR just omit it? If we omit it, previous value remains. 
        // If the user explicitly chose 'No Date', they likely want to clear it or set it empty.
        // But the API might not support clearing if we just omit.
        // Let's send the date if we have it. If 'none', we explicitly send null? 
        // The backend logic: `if let Some(started_at) = book_data.started_reading_at`.
        // To clear it, we might need to send `null` in JSON. 
        // Dart `toIso8601String()` is only for non-null.
        // Let's check api_service.dart again. It takes Map<String, dynamic>.
        // JSON `null` is valid.
        updateData['started_reading_at'] = selectedDate?.toIso8601String();
      } else if (newStatus == 'read') {
        updateData['finished_reading_at'] = selectedDate?.toIso8601String();
      }

      await apiService.updateBook(_book.id!, updateData);
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(TranslationService.translate(context, 'status_updated') ?? 'Status updated')),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating status: $e')),
        );
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(TranslationService.translate(context, 'delete_book_title') ?? 'Delete Book'),
        content: Text(TranslationService.translate(context, 'delete_book_confirm') ?? 'Are you sure you want to delete this book?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(TranslationService.translate(context, 'cancel') ?? 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(TranslationService.translate(context, 'delete') ?? 'Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final apiService = Provider.of<ApiService>(context, listen: false);
      try {
        await apiService.deleteBook(_book.id!);
        if (context.mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text(TranslationService.translate(context, 'book_deleted') ?? 'Book deleted')),
           );
           // Navigate back to list and refresh
           Navigator.of(context).pop(true);
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting book: $e')),
          );
        }
      }
    }
  }

  Future<void> _lendBook(BuildContext context) async {
    final selectedContact = await showDialog<Contact>(
      context: context,
      builder: (context) => const LoanDialog(),
    );

    if (selectedContact == null || !context.mounted) return;

    final apiService = Provider.of<ApiService>(context, listen: false);
    try {
      // 1. Get existing copies for this book
      final copiesResponse = await apiService.getBookCopies(_book.id!);
      List<dynamic> copies = copiesResponse.data['copies'] ?? [];
      
      int copyId;
      
      if (copies.isEmpty) {
        // 2. Create a copy if none exists
        final newCopyResponse = await apiService.createCopy({
          'book_id': _book.id,
          'library_id': 1, // Default library
          'status': 'available',
          'is_temporary': false,
        });
        copyId = newCopyResponse.data['copy']['id'];
      } else {
        // Find an available copy
        final availableCopy = copies.firstWhere(
          (c) => c['status'] == 'available',
          orElse: () => copies.first,
        );
        copyId = availableCopy['id'];
      }

      // 3. Calculate due date (30 days from now)
      final now = DateTime.now();
      final dueDate = now.add(const Duration(days: 30));

      // 4. Create the loan with correct fields
      await apiService.createLoan({
        'copy_id': copyId,
        'contact_id': selectedContact.id,
        'library_id': 1, // Default library
        'loan_date': now.toIso8601String().split('T')[0],
        'due_date': dueDate.toIso8601String().split('T')[0],
      });

      // 5. Update book reading status to 'borrowed'
      await apiService.updateBook(_book.id!, {
        'title': _book.title,
        'reading_status': 'borrowed',
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${TranslationService.translate(context, 'book_lent_to') ?? 'Book lent to'} ${selectedContact.displayName}',
            ),
          ),
        );
        // Refresh the book details from API
        _fetchBookDetails();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${TranslationService.translate(context, 'error_lending_book') ?? 'Error lending book'}: $e')),
        );
      }
    }
  }

  Future<void> _returnBook(BuildContext context) async {
    final apiService = Provider.of<ApiService>(context, listen: false);
    
    try {
      // Find active loan for this book's copy
      final copiesResponse = await apiService.getBookCopies(_book.id!);
      List<dynamic> copies = copiesResponse.data['copies'] ?? [];
      
      if (copies.isEmpty) {
        throw Exception('No copy found for this book');
      }

      // Get the borrowed copy
      final borrowedCopy = copies.firstWhere(
        (c) => c['status'] == 'borrowed',
        orElse: () => copies.first,
      );

      // Find active loan for this copy
      final loansResponse = await apiService.getLoans(status: 'active');
      List<dynamic> loans = loansResponse.data['loans'] ?? [];
      
      final activeLoan = loans.firstWhere(
        (l) => l['copy_id'] == borrowedCopy['id'],
        orElse: () => null,
      );

      if (activeLoan != null) {
        // Return the loan
        await apiService.returnLoan(activeLoan['id']);
      }

      // Update book reading status
      await apiService.updateBook(_book.id!, {
        'title': _book.title,
        'reading_status': 'read', // or 'to_read' based on preference
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(TranslationService.translate(context, 'book_returned') ?? 'Book returned'),
          ),
        );
        _fetchBookDetails();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${TranslationService.translate(context, 'error_returning_book') ?? 'Error returning book'}: $e')),
        );
      }
    }
  }
}
