import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../models/memory_game.dart';
import '../widgets/cached_book_cover.dart';

/// Tells whether the cover at a URL will actually draw on this device.
typedef CoverCheck = Future<bool> Function(String coverUrl);

/// Raised when the reserve runs out before every failing pair is replaced.
class NotEnoughDrawableCoversException implements Exception {
  final int missing;

  const NotEnoughDrawableCoversException(this.missing);

  @override
  String toString() =>
      'NotEnoughDrawableCoversException: $missing pair(s) without a drawable cover';
}

/// Swaps every pair of [cards] whose cover does not draw for a book of
/// [reserve] whose cover does, keeping the board's positions.
///
/// A stored cover URL is no promise: a dead Open Library ISBN, a timeout or a
/// local file absent on this device all fall back to the same grey card, and
/// two such pairs are impossible to tell apart. The board covers are checked
/// together, then the reserve is walked in its (random) order, as many books
/// at a time as pairs are still missing.
///
/// At most [maxReserveRounds] batches of the reserve are tried: on a slow
/// network every check can run to [coverCheckTimeout], and walking a reserve
/// of hundreds of books that way would hold the spinner for minutes.
///
/// Throws [NotEnoughDrawableCoversException] when the reserve or the rounds
/// run out first.
Future<List<MemoryCard>> keepDrawablePairs({
  required List<MemoryCard> cards,
  required List<MemoryCard> reserve,
  required CoverCheck isDrawable,
  int maxReserveRounds = 2,
}) async {
  final boardBooks = <String, MemoryCard>{};
  for (final card in cards) {
    boardBooks.putIfAbsent(card.bookId, () => card);
  }

  final books = boardBooks.values.toList();
  final drawable = await Future.wait(books.map((b) => isDrawable(b.coverUrl)));
  final failing = [
    for (var i = 0; i < books.length; i++)
      if (!drawable[i]) books[i].bookId,
  ];
  if (failing.isEmpty) return cards;

  final replacements = <String, MemoryCard>{};
  var next = 0;
  var rounds = 0;
  while (replacements.length < failing.length &&
      next < reserve.length &&
      rounds < maxReserveRounds) {
    rounds++;
    final wanted = failing.length - replacements.length;
    final end = (next + wanted).clamp(0, reserve.length);
    final batch = reserve.sublist(next, end);
    next = end;
    final ok = await Future.wait(batch.map((b) => isDrawable(b.coverUrl)));
    for (var i = 0; i < batch.length; i++) {
      if (ok[i]) replacements[failing[replacements.length]] = batch[i];
    }
  }

  if (replacements.length < failing.length) {
    throw NotEnoughDrawableCoversException(
      failing.length - replacements.length,
    );
  }

  return [
    for (final card in cards)
      switch (replacements[card.bookId]) {
        // A fresh instance per card: flip state lives on the card.
        final book? => MemoryCard(
          bookId: book.bookId,
          title: book.title,
          coverUrl: book.coverUrl,
        ),
        null => card,
      },
  ];
}

/// Longest wait for one cover. Open Library can take 6-11 s on a cold fetch;
/// a cover slower than this is swapped for another book rather than holding
/// the deal back, and its download still lands in the cache for next time.
const Duration coverCheckTimeout = Duration(seconds: 5);

/// Narrower than this, the "image" is a stand-in, such as the 1x1 pixel Open
/// Library serves for an ISBN it has no cover for.
const int minDrawableCoverWidth = 10;

/// The production [CoverCheck]: fetches the cover through the same cache
/// [CachedBookCover] reads, so a passing cover is already on disk when the
/// card turns, and reads its header to reject stand-in pixels.
Future<bool> isCoverDrawable(String coverUrl) async {
  if (coverUrl.isEmpty) return false;
  // This device's own cover route: resolving it needs the API base URL and
  // the bytes are served by this very backend, so it is trusted as is.
  if (coverUrl.startsWith('/api')) return true;

  try {
    final Uint8List bytes;
    if (coverUrl.startsWith('http')) {
      final file = await BookCoverCacheManager.instance
          .getSingleFile(coverUrl)
          .timeout(coverCheckTimeout);
      bytes = await file.readAsBytes();
    } else {
      final file = File(coverUrl);
      if (!await file.exists()) return false;
      bytes = await file.readAsBytes();
    }
    return await hasDrawableWidth(bytes);
  } catch (e) {
    debugPrint('Memory game: cover not drawable ($coverUrl): $e');
    return false;
  }
}

/// Reads the encoded image header only (no pixel decode) and checks its width.
@visibleForTesting
Future<bool> hasDrawableWidth(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  try {
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final width = descriptor.width;
    descriptor.dispose();
    return width >= minDrawableCoverWidth;
  } finally {
    buffer.dispose();
  }
}
