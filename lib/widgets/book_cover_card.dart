import 'package:flutter/material.dart';
import '../models/book.dart';
import 'dart:math';

class BookCoverCard extends StatelessWidget {
  final Book book;
  final VoidCallback onTap;

  const BookCoverCard({
    super.key,
    required this.book,
    required this.onTap,
  });

  Color _getColorFromId(int id) {
    final random = Random(id);
    return Color.fromARGB(
      255,
      random.nextInt(200),
      random.nextInt(200),
      random.nextInt(200),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              offset: const Offset(0, 2),
              blurRadius: 4,
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Background / Cover
            if (book.coverUrl != null && book.coverUrl!.isNotEmpty)
              Image.network(
                book.coverUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return _buildFallbackCover();
                },
              )
            else
              _buildFallbackCover(),

            // Gradient overlay for text readability (only if using fallback or if needed)
            if (book.coverUrl == null || book.coverUrl!.isEmpty)
              Container(
                 // Fallback cover already has color, but we can add specific styling here if needed
              ),
              
            // Reading Status Indicator
             if (book.readingStatus != null)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _formatStatus(book.readingStatus!),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatStatus(String status) {
    switch(status) {
      case 'to_read': return 'TO READ';
      case 'reading': return 'READING';
      case 'read': return 'READ';
      case 'borrowed': return 'BORROWED';
      default: return status.toUpperCase();
    }
  }

  Widget _buildFallbackCover() {
    final color = _getColorFromId(book.id ?? 0);
    return Container(
      decoration: BoxDecoration(
        color: color,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withOpacity(0.8),
            color,
          ],
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            book.title,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
              shadows: [
                Shadow(
                  offset: Offset(0, 1),
                  blurRadius: 2,
                  color: Colors.black45,
                ),
              ],
            ),
          ),
          if (book.author != null) ...[
            const SizedBox(height: 8),
            Text(
              book.author!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
