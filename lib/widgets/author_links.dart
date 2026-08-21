import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/translation_service.dart';
import '../utils/author_identity.dart';

/// The author line of a book, each name routing to its author page
/// (ADR-061).
///
/// `Book.author` is one flattened string, so the names are recovered
/// through [AuthorIdentity], which only splits on a comma when the library
/// vocabulary recognizes every part: "Le Guin, Ursula K." stays one person,
/// "Ursula K. Le Guin, Alia Sun" becomes two. An empty [vocabulary] (the
/// index is not loaded yet, or the library sits below the profile floor)
/// therefore renders the whole string as a single link, which is narrow but
/// never names the wrong person.
///
/// Each name is a semantic button with a translated label (Rules A1/A4).
/// Deliberately NOT used inside `SuggestionTile`: that tile announces
/// through a single composed label under `excludeSemantics`, which cannot
/// be re-enabled from a descendant, so a link nested there would be mute
/// for screen readers (ADR-061 section 7, decision A2).
class AuthorLinks extends StatelessWidget {
  const AuthorLinks({
    super.key,
    required this.flattenedAuthor,
    required this.vocabulary,
    this.style,
  });

  /// The book's `author` field, as the FFI flattened it.
  final String flattenedAuthor;

  /// Individual author names the library knows, as [AuthorIdentity] match
  /// keys.
  final Set<String> vocabulary;

  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final names = AuthorIdentity.split(flattenedAuthor, vocabulary);
    if (names.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final effective =
        style ??
        theme.textTheme.titleLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        );

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < names.length; i++) ...[
          // Punctuation between two author buttons: excluded, or a screen
          // reader announces a bare comma between them.
          if (i > 0) ExcludeSemantics(child: Text(', ', style: effective)),
          _AuthorNameLink(name: names[i], style: effective),
        ],
      ],
    );
  }
}

/// One tappable author name.
///
/// Colour and weight carry the affordance persistently; the underline is an
/// accent added while the name is hovered OR keyboard-focused. A static
/// underline reads as heavy under a book title, and doubly so when two
/// co-authors each carry one.
///
/// Focus matters as much as hover here: hover is pointer-only, so without
/// the focus half a keyboard user would get nothing but the InkWell's
/// default highlight, and the two modalities would not be at parity.
/// Touch devices show neither and lose nothing, the tap ripple answers.
///
/// Stateful per name rather than one flag for the whole line, so pointing
/// at one co-author does not underline the other.
class _AuthorNameLink extends StatefulWidget {
  const _AuthorNameLink({required this.name, required this.style});

  final String name;
  final TextStyle? style;

  @override
  State<_AuthorNameLink> createState() => _AuthorNameLinkState();
}

class _AuthorNameLinkState extends State<_AuthorNameLink> {
  bool _hovering = false;
  bool _focused = false;

  bool get _accented => _hovering || _focused;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: TranslationService.translate(
        context,
        'author_page_open_semantic',
        params: {'author': widget.name},
      ),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: InkWell(
          onTap: () =>
              context.push('/authors/${Uri.encodeComponent(widget.name)}'),
          onFocusChange: (focused) => setState(() => _focused = focused),
          borderRadius: BorderRadius.circular(4),
          child: Text(
            widget.name,
            style: _accented
                ? widget.style?.copyWith(
                    decoration: TextDecoration.underline,
                    decorationColor: theme.colorScheme.primary.withValues(
                      alpha: 0.4,
                    ),
                  )
                : widget.style,
          ),
        ),
      ),
    );
  }
}
