import 'package:flutter/material.dart';
import '../models/hangman_game.dart';

/// Custom keyboard for the hangman game.
///
/// Displays digits 0-9 and letters A-Z as tappable buttons.
/// Already guessed characters are colored green (correct) or red (wrong).
class HangmanKeyboard extends StatelessWidget {
  final Set<String> guessedChars;
  final List<HangmanChar> display;
  final void Function(String) onCharTap;

  const HangmanKeyboard({
    super.key,
    required this.guessedChars,
    required this.display,
    required this.onCharTap,
  });

  /// Check if a guessed character was correct (exists in the title).
  bool _isCorrect(String char) {
    return display.any((c) => c.isGuessable && c.baseChar == char);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const digits = '1234567890';
    const row1 = 'AZERTYUIOP';
    const row2 = 'QSDFGHJKLM';
    const row3 = 'WXCVBN';

    // Longest row determines key size
    const maxKeysPerRow = 11; // QSDFGHJKLM
    const gap = 4.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth - 8; // horizontal padding
        final keyWidth = (availableWidth - gap * (maxKeysPerRow - 1)) / maxKeysPerRow;
        final keySize = keyWidth.clamp(28.0, 44.0);
        final keyHeight = (keySize * 1.2).clamp(36.0, 48.0);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildRow(theme, digits, keySize, keyHeight, gap),
            SizedBox(height: gap),
            _buildRow(theme, row1, keySize, keyHeight, gap),
            SizedBox(height: gap),
            _buildRow(theme, row2, keySize, keyHeight, gap),
            SizedBox(height: gap),
            _buildRow(theme, row3, keySize, keyHeight, gap),
          ],
        );
      },
    );
  }

  Widget _buildRow(ThemeData theme, String chars, double keySize,
      double keyHeight, double gap) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: chars.split('').map((char) {
        final lower = char.toLowerCase();
        final guessed = guessedChars.contains(lower);
        final correct = guessed && _isCorrect(lower);
        final wrong = guessed && !correct;

        Color bgColor;
        Color textColor;
        if (correct) {
          bgColor = theme.colorScheme.primaryContainer;
          textColor = theme.colorScheme.onPrimaryContainer;
        } else if (wrong) {
          bgColor = theme.colorScheme.errorContainer;
          textColor = theme.colorScheme.onErrorContainer;
        } else {
          bgColor = theme.colorScheme.surfaceContainerHighest;
          textColor = theme.colorScheme.onSurface;
        }

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: gap / 2),
          child: SizedBox(
            width: keySize,
            height: keyHeight,
            child: Material(
              color: bgColor,
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: guessed ? null : () => onCharTap(lower),
                child: Center(
                  child: Text(
                    char,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: textColor,
                      fontWeight: FontWeight.w600,
                      fontSize: keySize > 36 ? 16 : 14,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
