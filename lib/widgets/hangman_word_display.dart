import 'package:flutter/material.dart';
import '../models/hangman_game.dart';

/// Displays the hangman title with revealed/hidden characters.
///
/// Unrevealed guessable characters show as underscores.
/// Spaces and punctuation are always visible.
class HangmanWordDisplay extends StatelessWidget {
  final List<HangmanChar> display;

  const HangmanWordDisplay({super.key, required this.display});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 4,
      runSpacing: 8,
      children: display.map((c) {
        if (!c.isGuessable) {
          // Space or punctuation -- always visible
          return SizedBox(
            width: c.character == ' ' ? 16 : null,
            child: c.character == ' '
                ? null
                : Text(
                    c.character,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
          );
        }

        // Guessable character (letter or digit)
        return Container(
          width: 28,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: c.revealed
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
                width: 2,
              ),
            ),
          ),
          child: Text(
            c.revealed ? c.character : '',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
        );
      }).toList(),
    );
  }
}
