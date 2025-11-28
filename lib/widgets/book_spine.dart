import 'package:flutter/material.dart';
import 'dart:math';
import '../models/book.dart';

class BookSpine extends StatelessWidget {
  final Book book;
  final double height;
  final double width;

  const BookSpine({
    super.key,
    required this.book,
    this.height = 150,
    this.width = 40,
  });

  Color _getColorFromId(int id) {
    final random = Random(id);
    return Color.fromARGB(
      255,
      random.nextInt(200), // Darker colors look more like books
      random.nextInt(200),
      random.nextInt(200),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        color: _getColorFromId(book.id ?? 0),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(4),
          topRight: Radius.circular(4),
          bottomLeft: Radius.circular(2),
          bottomRight: Radius.circular(2),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            offset: const Offset(1, 1),
            blurRadius: 2,
          ),
        ],
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            _getColorFromId(book.id ?? 0).withValues(alpha: 0.8),
            _getColorFromId(book.id ?? 0),
            _getColorFromId(book.id ?? 0).withValues(alpha: 0.9),
          ],
          stops: const [0.0, 0.2, 0.9],
        ),
      ),
      child: Center(
        child: RotatedBox(
          quarterTurns: 3, // Rotate 270 degrees (bottom to top)
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  book.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 10,
                  ),
                ),
                if (book.publisher != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    book.publisher!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                      fontSize: 8,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
