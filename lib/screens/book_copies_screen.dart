import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;
import '../data/repositories/copy_repository.dart';
import '../models/copy.dart';
import '../services/translation_service.dart';
import '../providers/theme_provider.dart';

class BookCopiesScreen extends StatefulWidget {
  final int bookId;
  final String bookTitle;

  const BookCopiesScreen({
    super.key,
    required this.bookId,
    required this.bookTitle,
  });

  @override
  State<BookCopiesScreen> createState() => _BookCopiesScreenState();
}

class _BookCopiesScreenState extends State<BookCopiesScreen>
    with SingleTickerProviderStateMixin {
  List<Copy> _copies = [];
  bool _isLoading = true;
  late AnimationController _animController;

  // Vintage library color palette
  // static const Color woodDark = Color(0xFF3D2314);
  // static const Color woodMedium = Color(0xFF5D3A1A);
  // Unused colors commented out or removed to clean up
  // static const Color woodLight = Color(0xFF8B5A2B);
  // static const Color woodHighlight = Color(0xFFA0724A);
  static const Color leather = Color(0xFF8B4513);
  static const Color goldAccent = Color(0xFFD4AF37);
  // static const Color parchment = Color(0xFFC4A35A);
  // static const Color inkBlack = Color(0xFF1F1F1F);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fetchCopies();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _fetchCopies() async {
    final copyRepo = Provider.of<CopyRepository>(context, listen: false);
    try {
      final copies = await copyRepo.getBookCopies(widget.bookId);
      setState(() {
        _copies = copies;
        _isLoading = false;
      });
      _animController.forward();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      _animController.forward();
    }
  }

  Future<void> _addCopy() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _StandardAddCopySheet(bookId: widget.bookId),
    );

    if (result != null) {
      if (!mounted) return;
      final copyRepo = Provider.of<CopyRepository>(context, listen: false);
      try {
        await copyRepo.createCopy({
          'book_id': widget.bookId,
          'library_id': 1,
          ...result,
        });
        _fetchCopies();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${TranslationService.translate(context, 'error')}: $e',
              ),
            ),
          );
        }
      }
    }
  }

  Future<void> _deleteCopy(int copyId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _StandardDeleteDialog(),
    );

    if (confirmed == true) {
      if (!mounted) return;
      final copyRepo = Provider.of<CopyRepository>(context, listen: false);
      try {
        await copyRepo.deleteCopy(copyId);
        _fetchCopies();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${TranslationService.translate(context, 'error')}: $e',
              ),
            ),
          );
        }
      }
    }
  }

  void _editCopy(Copy copy) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _StandardAddCopySheet(bookId: widget.bookId, existingCopy: copy),
    );

    if (result != null) {
      if (!mounted) return;
      final copyRepo = Provider.of<CopyRepository>(context, listen: false);
      try {
        await copyRepo.updateCopy(copy.id!, {
          'book_id': widget.bookId,
          ...result,
        });
        _fetchCopies();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${TranslationService.translate(context, 'error_updating_copy')}: $e',
              ),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Sorbonne theme colors are handled by the theme system, no special display needed

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.bookTitle),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'copies_add_fab',
        key: const Key('addCopyFab'),
        onPressed: _addCopy,
        child: const Icon(Icons.add),
      ),
      body: Container(
        // Use theme background for all themes
        child: SafeArea(
          child: _isLoading
              ? _buildLoadingState(false) // Always use standard loading
              : _copies.isEmpty
              ? _buildStandardEmptyState() // Always use standard empty state
              : _buildStandardList(), // Always use standard list
        ),
      ),
    );
  }

  Widget _buildLoadingState(bool isVintageTheme) {
    return Center(
      child: isVintageTheme
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(color: Color(0xFFD4A855)),
                const SizedBox(height: 16),
                Text(
                  'Consulting the archives...',
                  style: TextStyle(
                    color: const Color(0xFFD4A855).withValues(alpha: 0.8),
                    fontFamily: 'Serif',
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            )
          : const CircularProgressIndicator(),
    );
  }

  Widget _buildVintageFab() {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: FloatingActionButton.extended(
        heroTag: 'copies_add_vintage_fab',
        key: const Key('addCopyFab'),
        onPressed: _addCopy,
        backgroundColor: leather,
        icon: const Icon(Icons.add, color: goldAccent),
        label: Text(
          TranslationService.translate(context, 'add_copy_title'),
          style: const TextStyle(
            color: goldAccent,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }

  Widget _buildStandardList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _copies.length,
      itemBuilder: (context, index) {
        final copy = _copies[index];
        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: copy.isTemporary
                  ? Colors.orange
                  : Theme.of(context).primaryColor,
              child: Icon(
                copy.isTemporary ? Icons.watch_later_outlined : Icons.book,
                color: Colors.white,
              ),
            ),
            title: Text(
              '${TranslationService.translate(context, 'copy_label')} #${copy.id}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Chip(
                    label: Text(
                      TranslationService.translate(
                            context,
                            'status_${copy.status}',
                          ) ??
                          copy.status,
                      style: const TextStyle(fontSize: 10),
                    ),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                if (Provider.of<ThemeProvider>(context).isBookseller &&
                    copy.price != null &&
                    copy.price! > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${copy.price!.toStringAsFixed(2)} ${Provider.of<ThemeProvider>(context).currency}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).primaryColor,
                      ),
                    ),
                  ),
                if (copy.notes != null && copy.notes!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      copy.notes!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'edit') {
                  _editCopy(copy);
                } else if (value == 'delete') {
                  _deleteCopy(copy.id!);
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      const Icon(Icons.edit, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        TranslationService.translate(context, 'edit') ?? 'Edit',
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      const Icon(Icons.delete, color: Colors.red, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        TranslationService.translate(context, 'delete') ??
                            'Delete',
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStandardEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.library_books_outlined,
            size: 64,
            color: Colors.grey.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            TranslationService.translate(context, 'no_copies_found') ??
                'No copies found',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Text(
              TranslationService.translate(context, 'add_copy_hint') ??
                  'Add a copy to start tracking this book',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVintageBookshelf() {
    return Container(
      decoration: const BoxDecoration(color: Color(0xFF1A0F0A)),
      child: Stack(
        children: [
          // Background texture
          Positioned.fill(
            child: Opacity(
              opacity: 0.1,
              child: CachedNetworkImage(
                imageUrl:
                    'https://www.transparenttextures.com/patterns/wood-pattern.png',
                imageBuilder: (context, imageProvider) =>
                    Image(image: imageProvider, repeat: ImageRepeat.repeat),
                errorWidget: (c, e, s) => const SizedBox(),
              ),
            ),
          ),

          // Main Bookshelf View
          ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            itemCount: (_copies.length / 2).ceil() + 1, // Shelves + bottom
            itemBuilder: (context, shelfIndex) {
              if (shelfIndex == (_copies.length / 2).ceil()) {
                // Bottom decorative element
                return const SizedBox(height: 40);
              }

              final startIndex = shelfIndex * 2;
              final endIndex = math.min(startIndex + 2, _copies.length);
              final shelfCopies = _copies.sublist(startIndex, endIndex);

              return _WoodenShelf(
                copies: shelfCopies,
                shelfIndex: shelfIndex,
                onDelete: _deleteCopy,
                onEdit: _editCopy,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildVintageEmptyState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.blur_on, size: 80, color: Color(0xFF3D2314)),
        const SizedBox(height: 20),
        const Text(
          'The archival shelves are bare...',
          style: TextStyle(
            fontFamily: 'Serif',
            fontSize: 20,
            color: Color(0xFFD4AF37),
            shadows: [
              Shadow(blurRadius: 2, color: Colors.black, offset: Offset(1, 1)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF5D3A1A)),
            borderRadius: BorderRadius.circular(8),
            color: const Color(0xFF2D1810).withValues(alpha: 0.5),
          ),
          child: const Text(
            'Acquire new manuscripts to fill this void.',
            style: TextStyle(
              fontFamily: 'Serif',
              color: Color(0xFFA0724A),
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }
}

// ============== WOODEN SHELF WIDGET ==============
class _WoodenShelf extends StatelessWidget {
  final List<Copy> copies;
  final int shelfIndex;
  final Function(int) onDelete;
  final Function(Copy) onEdit;

  const _WoodenShelf({
    required this.copies,
    required this.shelfIndex,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 600 + (shelfIndex * 150)),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 30 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          children: [
            // Books on shelf
            Container(
              height: 160,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: copies.map((copy) {
                  return _Book3D(
                    copy: copy,
                    onTap: () => onEdit(copy),
                    onDelete: () => onDelete(copy.id!),
                  );
                }).toList(),
              ),
            ),
            // Wooden shelf
            _ShelfBoard(),
          ],
        ),
      ),
    );
  }
}

// ============== 3D BOOK WIDGET ==============
class _Book3D extends StatefulWidget {
  final Copy copy;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _Book3D({
    required this.copy,
    required this.onTap,
    required this.onDelete,
  });

  @override
  State<_Book3D> createState() => _Book3DState();
}

class _Book3DState extends State<_Book3D> {
  bool _isHovered = false;

  List<Color> get _bookColors {
    final colors = [
      [const Color(0xFF8B0000), const Color(0xFF5C0000)], // Dark red leather
      [const Color(0xFF1B4D3E), const Color(0xFF0D2818)], // Forest green
      [const Color(0xFF2C3E50), const Color(0xFF1A252F)], // Navy blue
      [const Color(0xFF6B4423), const Color(0xFF3D2614)], // Brown leather
      [const Color(0xFF4A0E4E), const Color(0xFF2A0830)], // Purple
      [const Color(0xFF8B4513), const Color(0xFF5D2E0C)], // Saddle brown
    ];
    return colors[(widget.copy.id ?? 0) % colors.length];
  }

  IconData get _statusIcon {
    switch (widget.copy.status) {
      case 'available':
        return Icons.check_circle;
      case 'borrowed':
        return Icons.swap_horiz;
      case 'loaned':
        return Icons.output;
      case 'lost':
        return Icons.error;
      default:
        return Icons.book;
    }
  }

  Color get _statusColor {
    switch (widget.copy.status) {
      case 'available':
        return Colors.green;
      case 'borrowed':
        return Colors.orange;
      case 'loaned':
        return Colors.purple;
      case 'lost':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookWidth = 100.0;
    final bookHeight = 140.0;
    final spineWidth = 25.0;

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onDelete,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(_isHovered ? -0.15 : 0),
          transformAlignment: Alignment.centerRight,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          child: Stack(
            children: [
              // Book shadow
              Positioned(
                bottom: -5,
                left: 10,
                right: 10,
                child: Container(
                  height: 10,
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),

              // Main book body with 3D effect
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Spine
                  Container(
                    width: spineWidth,
                    height: bookHeight,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [_bookColors[1], _bookColors[0]],
                      ),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(3),
                        bottomLeft: Radius.circular(3),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          blurRadius: 4,
                          offset: const Offset(-2, 0),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 15,
                          height: 2,
                          color: const Color(0xFFD4AF37),
                        ),
                        const SizedBox(height: 8),
                        RotatedBox(
                          quarterTurns: 3,
                          child: Text(
                            '#${widget.copy.id}', // Actually using ID for copy number
                            style: const TextStyle(
                              color: Color(0xFFD4AF37),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: 15,
                          height: 2,
                          color: const Color(0xFFD4AF37),
                        ),
                      ],
                    ),
                  ),

                  // Front cover
                  Container(
                    width: bookWidth - spineWidth,
                    height: bookHeight,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          _bookColors[0],
                          _bookColors[0].withValues(alpha: 0.9),
                          _bookColors[1],
                        ],
                      ),
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(3),
                        bottomRight: Radius.circular(3),
                      ),
                      border: Border.all(
                        color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Stack(
                      children: [
                        // Leather texture
                        Positioned.fill(
                          child: CustomPaint(painter: _LeatherTexturePainter()),
                        ),

                        // Gold frame decoration
                        Positioned(
                          top: 8,
                          left: 8,
                          right: 8,
                          bottom: 8,
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: const Color(
                                  0xFFD4AF37,
                                ).withValues(alpha: 0.3),
                                width: 1,
                              ),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),

                        // Central emblem
                        Center(
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: _bookColors[1].withValues(alpha: 0.5),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(
                                  0xFFD4AF37,
                                ).withValues(alpha: 0.5),
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              Icons.auto_stories,
                              color: const Color(
                                0xFFD4AF37,
                              ).withValues(alpha: 0.8),
                              size: 20,
                            ),
                          ),
                        ),

                        // Status indicator
                        Positioned(
                          bottom: 12,
                          right: 12,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: _statusColor.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                              border: Border.all(color: _statusColor, width: 1),
                            ),
                            child: Icon(
                              _statusIcon,
                              color: _statusColor,
                              size: 12,
                            ),
                          ),
                        ),

                        // Temporary badge
                        if (widget.copy.isTemporary)
                          Positioned(
                            top: 12,
                            right: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'TEMP',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),

                        // Price tag
                        if (Provider.of<ThemeProvider>(context).isBookseller &&
                            widget.copy.price != null &&
                            widget.copy.price! > 0)
                          Positioned(
                            bottom: 12,
                            left: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFD4AF37),
                                borderRadius: BorderRadius.circular(4),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.3),
                                    blurRadius: 2,
                                    offset: const Offset(1, 1),
                                  ),
                                ],
                              ),
                              child: Text(
                                '${widget.copy.price!.toStringAsFixed(2)} ${Provider.of<ThemeProvider>(context).currency}',
                                style: TextStyle(
                                  color: _bookColors[0],
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),

                        // Pages effect
                        Positioned(
                          top: 3,
                          bottom: 3,
                          right: 0,
                          child: Container(
                            width: 3,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  const Color(
                                    0xFFC4A35A,
                                  ).withValues(alpha: 0.8),
                                  const Color(
                                    0xFFB8860B,
                                  ).withValues(alpha: 0.8),
                                  const Color(
                                    0xFFC4A35A,
                                  ).withValues(alpha: 0.8),
                                ],
                              ),
                              borderRadius: const BorderRadius.only(
                                topRight: Radius.circular(2),
                                bottomRight: Radius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ],
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
}

class _ShelfBoard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 20,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFF5D3A1A),
            Color(0xFF8B5A2B),
            Color(0xFF6B4423),
            Color(0xFF5D3A1A),
          ],
          stops: [0.0, 0.3, 0.7, 1.0],
        ),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFA0724A).withValues(alpha: 0.5),
            blurRadius: 2,
            offset: const Offset(0, -1),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _WoodGrainPainter())),
          Positioned(left: 20, top: 4, bottom: 4, child: _ShelfBracket()),
          Positioned(right: 20, top: 4, bottom: 4, child: _ShelfBracket()),
        ],
      ),
    );
  }
}

class _ShelfBracket extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 16,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4A3728), Color(0xFF6B5344), Color(0xFF4A3728)],
        ),
        borderRadius: BorderRadius.circular(2),
        border: Border.all(color: const Color(0xFF2D1810)),
      ),
    );
  }
}

class _OrnamentalDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  const Color(0xFFD4AF37).withValues(alpha: 0.5),
                ],
              ),
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Icon(Icons.auto_stories, color: Color(0xFFD4AF37), size: 20),
        ),
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFD4AF37).withValues(alpha: 0.5),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _VintageButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String label;
  final IconData icon;

  const _VintageButton({
    required this.onPressed,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF8B4513), Color(0xFF6B3410)],
            ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: const Color(0xFFD4AF37).withValues(alpha: 0.5),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: const Color(0xFFD4AF37)),
              const SizedBox(width: 12),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFFD4AF37),
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VintageDeleteDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF3D2314), Color(0xFF2D1810)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 20,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Color(0xFFD4AF37),
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              TranslationService.translate(context, 'delete_copy_title'),
              style: const TextStyle(
                color: Color(0xFFC4A35A),
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              TranslationService.translate(context, 'delete_copy_confirm'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: const Color(0xFFC4A35A).withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(
                    TranslationService.translate(context, 'cancel'),
                    style: TextStyle(
                      color: const Color(0xFFC4A35A).withValues(alpha: 0.7),
                    ),
                  ),
                ),
                _VintageButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  label: TranslationService.translate(
                    context,
                    'delete_copy_btn',
                  ),
                  icon: Icons.delete,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StandardDeleteDialog extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(TranslationService.translate(context, 'delete_copy_title')),
      content: Text(
        TranslationService.translate(context, 'delete_copy_confirm'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(TranslationService.translate(context, 'cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            TranslationService.translate(context, 'delete_copy_btn'),
            style: const TextStyle(color: Colors.red),
          ),
        ),
      ],
    );
  }
}

class _VintageAddCopySheet extends StatefulWidget {
  final Copy? existingCopy;

  const _VintageAddCopySheet({this.existingCopy});

  @override
  State<_VintageAddCopySheet> createState() => _VintageAddCopySheetState();
}

class _VintageAddCopySheetState extends State<_VintageAddCopySheet> {
  late TextEditingController _notesController;
  late TextEditingController _dateController;
  late String _selectedStatus;
  late bool _isTemporary;

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController(
      text: widget.existingCopy?.notes ?? '',
    );
    _dateController = TextEditingController(
      text: widget.existingCopy?.acquisitionDate ?? '',
    );
    _selectedStatus = widget.existingCopy?.status ?? 'available';
    _isTemporary = widget.existingCopy?.isTemporary ?? false;
  }

  @override
  void dispose() {
    _notesController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existingCopy != null;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: EdgeInsets.only(bottom: bottomPadding),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF3D2314), Color(0xFF2D1810)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4AF37).withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                isEditing
                    ? TranslationService.translate(context, 'edit_copy_title')
                    : TranslationService.translate(context, 'add_copy_title'),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              _OrnamentalDivider(),
              const SizedBox(height: 24),
              // Status
              Text(
                TranslationService.translate(context, 'copy_status'),
                style: const TextStyle(
                  color: Color(0xFFC4A35A),
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              _VintageStatusSelector(
                selectedStatus: _selectedStatus,
                onChanged: (status) => setState(() => _selectedStatus = status),
              ),
              const SizedBox(height: 24),

              // Date
              _VintageTextField(
                controller: _dateController,
                label: TranslationService.translate(
                  context,
                  'acquisition_date',
                ),
                hint: 'YYYY-MM-DD',
                icon: Icons.calendar_today,
                readOnly: true,
                onTap: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(1900),
                    lastDate: DateTime.now(),
                    builder: (context, child) => Theme(
                      data: ThemeData.dark().copyWith(
                        colorScheme: const ColorScheme.dark(
                          primary: Color(0xFFD4AF37),
                          surface: Color(0xFF3D2314),
                        ),
                      ),
                      child: child!,
                    ),
                  );
                  if (date != null) {
                    _dateController.text =
                        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                  }
                },
              ),
              const SizedBox(height: 16),

              // Temporary
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.schedule, color: Color(0xFFD4AF37)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        TranslationService.translate(
                          context,
                          'is_temporary_copy',
                        ),
                        style: const TextStyle(color: Color(0xFFC4A35A)),
                      ),
                    ),
                    Switch(
                      value: _isTemporary,
                      onChanged: (v) => setState(() => _isTemporary = v),
                      activeThumbColor: const Color(0xFFD4AF37),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Notes
              _VintageTextField(
                controller: _notesController,
                label: TranslationService.translate(context, 'notes_label'),
                icon: Icons.notes,
                maxLines: 3,
              ),
              const SizedBox(height: 32),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(
                        TranslationService.translate(context, 'cancel'),
                        style: TextStyle(
                          color: const Color(0xFFC4A35A).withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: _VintageButton(
                      onPressed: () {
                        Navigator.of(context).pop({
                          'acquisition_date': _dateController.text.isEmpty
                              ? null
                              : _dateController.text,
                          'notes': _notesController.text.isEmpty
                              ? null
                              : _notesController.text,
                          'status': _selectedStatus,
                          'is_temporary': _isTemporary,
                        });
                      },
                      label: isEditing
                          ? TranslationService.translate(context, 'save')
                          : TranslationService.translate(
                              context,
                              'add_peer_btn',
                            ),
                      icon: isEditing ? Icons.save : Icons.add,
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
}

class _StandardAddCopySheet extends StatefulWidget {
  final int bookId;
  final Copy? existingCopy;
  const _StandardAddCopySheet({required this.bookId, this.existingCopy});

  @override
  State<_StandardAddCopySheet> createState() => _StandardAddCopySheetState();
}

class _StandardAddCopySheetState extends State<_StandardAddCopySheet> {
  late TextEditingController _notesController;
  late TextEditingController _dateController;
  late TextEditingController _priceController;
  String _selectedStatus = 'available';
  bool _isTemporary = false;

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController(
      text: widget.existingCopy?.notes ?? '',
    );
    _dateController = TextEditingController(
      text: widget.existingCopy?.acquisitionDate ?? '',
    );
    _priceController = TextEditingController(
      text: widget.existingCopy?.price?.toString() ?? '',
    );
    _selectedStatus = widget.existingCopy?.status ?? 'available';
    _isTemporary = widget.existingCopy?.isTemporary ?? false;
  }

  @override
  void dispose() {
    _notesController.dispose();
    _dateController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    TranslationService.translate(context, 'cancel') ?? 'Cancel',
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary, // Ensure visibility
                      fontSize: 16,
                    ),
                  ),
                ),
                Text(
                  widget.existingCopy == null
                      ? TranslationService.translate(
                              context,
                              'add_copy_title',
                            ) ??
                            'Add Copy'
                      : TranslationService.translate(
                              context,
                              'edit_copy_title',
                            ) ??
                            'Edit Copy',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                TextButton(
                  onPressed: () {
                    // Return map of data
                    Navigator.pop(context, {
                      'acquisition_date': _dateController.text.isEmpty
                          ? null
                          : _dateController.text,
                      'notes': _notesController.text.isEmpty
                          ? null
                          : _notesController.text,
                      'status': _selectedStatus,
                      'is_temporary': _isTemporary,
                      'price': _priceController.text.isNotEmpty
                          ? double.tryParse(
                              _priceController.text.replaceAll(',', '.'),
                            )
                          : null,
                    });
                  },
                  child: Text(
                    widget.existingCopy == null
                        ? TranslationService.translate(context, 'save') ??
                              'Save'
                        : TranslationService.translate(context, 'save') ??
                              'Save',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Theme.of(context)
                          .colorScheme
                          .primary, // Check if primary is visible on scaffold background
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            DropdownButtonFormField<String>(
              value: _selectedStatus,
              decoration: InputDecoration(
                labelText:
                    TranslationService.translate(context, 'copy_status') ??
                    'Status',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              items: [
                DropdownMenuItem(
                  value: 'available',
                  child: Text(
                    TranslationService.translate(context, 'status_available') ??
                        'Available',
                  ),
                ),
                DropdownMenuItem(
                  value: 'borrowed',
                  child: Text(
                    TranslationService.translate(context, 'status_borrowed') ??
                        'Borrowed',
                  ),
                ),
                DropdownMenuItem(
                  value: 'loaned',
                  child: Text(
                    TranslationService.translate(context, 'status_loaned') ??
                        'Loaned',
                  ),
                ),
                DropdownMenuItem(
                  value: 'lost',
                  child: Text(
                    TranslationService.translate(context, 'status_lost') ??
                        'Lost',
                  ),
                ),
                DropdownMenuItem(
                  value: 'damaged',
                  child: Text(
                    TranslationService.translate(context, 'status_damaged') ??
                        'Damaged',
                  ),
                ),
              ],
              onChanged: (v) => setState(() => _selectedStatus = v!),
            ),
            const SizedBox(height: 16),
            if (Provider.of<ThemeProvider>(context).isBookseller) ...[
              TextFormField(
                controller: _priceController,
                decoration: InputDecoration(
                  labelText: TranslationService.translate(
                    context,
                    'price_label',
                  ),
                  suffixText:
                      ' ${Provider.of<ThemeProvider>(context).currency}',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _dateController,
              decoration: InputDecoration(
                labelText:
                    TranslationService.translate(context, 'acquisition_date') ??
                    'Acquisition Date',
                suffixIcon: const Icon(Icons.calendar_today),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              readOnly: true,
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(1900),
                  lastDate: DateTime.now(),
                );
                if (date != null) {
                  _dateController.text =
                      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                }
              },
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.withValues(alpha: 0.5)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SwitchListTile(
                title: Text(
                  TranslationService.translate(context, 'is_temporary_copy') ??
                      'Temporary Copy',
                ),
                value: _isTemporary,
                onChanged: (v) => setState(() => _isTemporary = v),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              decoration: InputDecoration(
                labelText:
                    TranslationService.translate(context, 'notes_label') ??
                    'Notes',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _VintageTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData icon;
  final int maxLines;
  final bool readOnly;
  final VoidCallback? onTap;

  const _VintageTextField({
    required this.controller,
    required this.label,
    this.hint,
    required this.icon,
    this.maxLines = 1,
    this.readOnly = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      readOnly: readOnly,
      onTap: onTap,
      style: const TextStyle(color: Color(0xFFC4A35A)),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Color(0xFFD4AF37)),
        hintStyle: TextStyle(
          color: const Color(0xFFC4A35A).withValues(alpha: 0.3),
        ),
        prefixIcon: Padding(
          padding: EdgeInsets.only(bottom: maxLines > 1 ? 48.0 : 0),
          child: Icon(icon, color: const Color(0xFFD4AF37)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 2),
        ),
      ),
    );
  }
}

class _VintageStatusSelector extends StatelessWidget {
  final String selectedStatus;
  final ValueChanged<String> onChanged;

  const _VintageStatusSelector({
    required this.selectedStatus,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final statuses = [
      (
        'available',
        Icons.check_circle,
        Colors.green,
        TranslationService.translate(context, 'status_available'),
      ),
      (
        'borrowed',
        Icons.swap_horiz,
        const Color(0xFFD4A855),
        TranslationService.translate(context, 'status_borrowed'),
      ),
      (
        'lent',
        Icons.output,
        Colors.purple,
        TranslationService.translate(context, 'status_lent'),
      ),
      (
        'lost',
        Icons.error_outline,
        Colors.red,
        TranslationService.translate(context, 'status_lost'),
      ),
      (
        'damaged',
        Icons.warning_amber,
        Colors.amber,
        TranslationService.translate(context, 'status_damaged'),
      ),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: statuses.map((s) {
        final (status, icon, color, label) = s;
        final isSelected = selectedStatus == status;

        return GestureDetector(
          onTap: () => onChanged(status),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF3D2314)
                  : const Color(0xFF2D1810),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? color : const Color(0xFF5D3A1A),
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.3),
                        blurRadius: 8,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: isSelected ? color : Colors.grey),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                    color: isSelected
                        ? color
                        : const Color(0xFFC4A35A).withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _WoodGrainPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF4A3020).withValues(alpha: 0.3)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < 8; i++) {
      final y = size.height * (i / 8);
      final path = Path();
      path.moveTo(0, y);
      for (double x = 0; x < size.width; x += 20) {
        path.quadraticBezierTo(x + 10, y + (i.isEven ? 2 : -2), x + 20, y);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LeatherTexturePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    final random = math.Random(42);
    for (int i = 0; i < 50; i++) {
      final x = random.nextDouble() * size.width;
      final y = random.nextDouble() * size.height;
      final length = random.nextDouble() * 5 + 2;
      final angle = random.nextDouble() * math.pi;

      canvas.drawLine(
        Offset(x, y),
        Offset(x + math.cos(angle) * length, y + math.sin(angle) * length),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
