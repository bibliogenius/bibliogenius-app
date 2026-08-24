import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/recommendation_provider.dart';
import '../services/translation_service.dart';

/// Direct path from the library screen to the reading suggestions
/// (ADR-062 R4), independent of the top slot and of which segment shows.
///
/// The floors split mirrors ADR-061 A4: gated on the PROFILE floor, so it
/// can never lead to a screen with nothing on it (the "never a dead end"
/// rule of ADR-060), but NOT on the visible-suggestions floor, so it does
/// not appear and disappear as the reader dismisses cards. A blinking
/// entry point is exactly the restlessness the product positioning rejects.
class SuggestionsAppBarAction extends StatelessWidget {
  const SuggestionsAppBarAction({super.key, this.color, this.style});

  /// App bars in this app tint their actions white over the header
  /// gradient; other hosts pass nothing and inherit the theme.
  final Color? color;

  /// Hosts whose neighbouring header icons wear the translucent chip
  /// (`AppDesign.headerIconButtonStyle()`) pass it here so this action
  /// does not read as a stray icon in an otherwise uniform row.
  final ButtonStyle? style;

  @override
  Widget build(BuildContext context) {
    final reachedFloor = context.select<RecommendationProvider, bool>(
      (provider) => provider.hasReachedProfileFloor,
    );
    if (!reachedFloor) return const SizedBox.shrink();

    return IconButton(
      icon: Icon(Icons.auto_awesome, color: color),
      tooltip: TranslationService.translate(
        context,
        'tooltip_open_recommendations',
      ),
      onPressed: () => context.push('/recommendations'),
      style: style,
    );
  }
}
