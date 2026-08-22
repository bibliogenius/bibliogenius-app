import 'package:flutter/material.dart';

import '../models/book.dart';
import '../theme/app_design.dart';
import 'book_recommendations_section.dart';

/// The "just finished a book" moment (ADR-062 R5).
///
/// It does NOT add a block. It PROMOTES the page's existing "You might also
/// like" section to the top, under the controls the reader just used, and
/// reframes its heading as "Continue with". The page renders it in one
/// place or the other, never both.
///
/// Two earlier forms failed, and the reasons are worth keeping. A
/// `SnackBarAction` left after three seconds and its label sat at poor
/// contrast, so the one moment a reader asks "what next?" was answered by
/// something barely visible and impossible to return to. A second block
/// carrying the personal taste blend then read as duplication: the two
/// sections hold different data, but on screen they are two rows of covers
/// on one page, and no reader parses "similar to this book" against "from
/// your profile".
///
/// Promoting also improves the answer. After finishing a book, "more like
/// this one" is a better reply than "based on your tastes in general", and
/// it is what the word "continue" promises.
///
/// It fades in, because the reader did not ask for it: it should arrive as
/// an offer rather than as a layout jolt. Reduced-motion settings are
/// honoured, in which case it simply is there. Never an interruption:
/// nothing overlays, nothing steals focus, nothing has to be dismissed, and
/// the section's own two-suggestion floor still decides whether it exists.
class ReadingCompletionSuggestions extends StatefulWidget {
  const ReadingCompletionSuggestions({super.key, required this.book});

  final Book book;

  @override
  State<ReadingCompletionSuggestions> createState() =>
      _ReadingCompletionSuggestionsState();
}

class _ReadingCompletionSuggestionsState
    extends State<ReadingCompletionSuggestions> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    // One frame at zero opacity, so the first build has something to fade
    // FROM. Without it AnimatedOpacity starts at its target and nothing
    // animates.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;

    return AnimatedOpacity(
      opacity: _visible || reduceMotion ? 1 : 0,
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 450),
      curve: Curves.easeOut,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppDesign.spacingLg),
        child: BookRecommendationsSection(
          book: widget.book,
          titleKey: 'reading_completion_continue_with',
        ),
      ),
    );
  }
}
