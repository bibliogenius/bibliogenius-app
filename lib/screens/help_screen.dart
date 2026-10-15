import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/theme_provider.dart';
import '../widgets/genie_app_bar.dart';
import '../widgets/scaffold_with_nav.dart';
import '../services/help_registry.dart';
import '../services/translation_service.dart';
import '../theme/app_design.dart';
import '../utils/accessible_color.dart';

class HelpScreen extends StatefulWidget {
  /// Optional topic id to expand on first display (deep link target).
  final String? initialTopicId;

  const HelpScreen({super.key, this.initialTopicId});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  int? _expandedIndex;
  late List<HelpTopic> _topics;
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _cardKeys = {};
  bool _initialScrollScheduled = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _topics = HelpRegistry.getAllForUser(context);

    if (!_initialScrollScheduled && widget.initialTopicId != null) {
      final index = _topics.indexWhere((t) => t.id == widget.initialTopicId);
      if (index >= 0) {
        _initialScrollScheduled = true;
        _expandedIndex = index;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToCard(index);
        });
      }
    }
  }

  void _scrollToCard(int index) {
    final key = _cardKeys[index];
    final ctx = key?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: AppDesign.standardDuration,
      curve: AppDesign.standardCurve,
      alignment: 0.1,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GenieAppBar(
        title: TranslationService.translate(context, 'help_title'),
        leading: buildDrawerLeading(context),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: AppDesign.maxContentWidth,
          ),
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              // Header Card
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: _readableUnderWhite(AppDesign.primaryGradient),
                  borderRadius: BorderRadius.circular(AppDesign.radiusLarge),
                  boxShadow: AppDesign.cardShadow,
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.help_outline,
                        size: 40,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Semantics(
                      header: true,
                      child: Text(
                        TranslationService.translate(
                          context,
                          'help_welcome_title',
                        ),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      TranslationService.translate(
                        context,
                        'help_welcome_subtitle',
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Section title
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: _sectionTitle(context, 'help_faq_title'),
              ),

              // Help Topics
              ...List.generate(_topics.length, (index) {
                final topic = _topics[index];
                final isExpanded = _expandedIndex == index;
                final cardKey = _cardKeys.putIfAbsent(index, () => GlobalKey());

                return Padding(
                  key: cardKey,
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildHelpCard(context, topic, index, isExpanded),
                );
              }),

              const SizedBox(height: 24),

              // Quick Actions
              _buildQuickActions(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHelpCard(
    BuildContext context,
    HelpTopic topic,
    int index,
    bool isExpanded,
  ) {
    final radius = BorderRadius.circular(AppDesign.radiusMedium);
    return AnimatedContainer(
      duration: AppDesign.standardDuration,
      curve: AppDesign.standardCurve,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: radius,
        boxShadow: isExpanded ? AppDesign.cardShadow : AppDesign.subtleShadow,
        border: Border.all(
          color: isExpanded
              ? (topic.gradient.colors.first).withValues(alpha: 0.5)
              : Colors.grey.withValues(alpha: 0.1),
          width: isExpanded ? 2 : 1,
        ),
      ),
      // Transparent Material so the header's ink and focus highlight paint
      // above the card colour instead of under it.
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            // Header: the only tap target, so the CTA below keeps its own.
            Semantics(
              button: true,
              expanded: isExpanded,
              child: InkWell(
                onTap: () {
                  setState(() {
                    _expandedIndex = isExpanded ? null : index;
                  });
                },
                borderRadius: isExpanded
                    ? BorderRadius.vertical(top: radius.topLeft)
                    : radius,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          // Flat solid badge, consistent with the section header
                          // icons elsewhere in the app (no gradient).
                          color: topic.gradient.colors.first,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(topic.icon, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          TranslationService.translate(context, topic.titleKey),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0,
                        duration: AppDesign.quickDuration,
                        child: Icon(
                          Icons.keyboard_arrow_down,
                          color: Colors.grey[400],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Expandable content
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(
                          AppDesign.radiusSmall,
                        ),
                      ),
                      child: Text(
                        TranslationService.translate(context, topic.descKey),
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                        ),
                      ),
                    ),
                    // Call to Action button
                    if (topic.ctaKey != null && topic.ctaRoute != null) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => context.push(topic.ctaRoute!),
                          icon: const Icon(Icons.arrow_forward, size: 18),
                          label: Text(
                            TranslationService.translate(
                                  context,
                                  topic.ctaKey!,
                                ) ??
                                '',
                          ),
                          style: TextButton.styleFrom(
                            foregroundColor: _ctaInk(
                              context,
                              topic.gradient.colors.first,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              crossFadeState: isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: AppDesign.standardDuration,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String key) {
    return Semantics(
      header: true,
      child: Text(
        TranslationService.translate(context, key),
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  /// The topic colour as CTA text, deepened until it reads on the card.
  ///
  /// [inkOn] only darkens, which suits the light card. On a dark card the
  /// topic colours mostly read as they are; one that does not falls back to
  /// the theme's text colour rather than being lightened by hand.
  Color _ctaInk(BuildContext context, Color topicColor) {
    final theme = Theme.of(context);
    final card = theme.cardColor;
    if (card.computeLuminance() > 0.5) return inkOn(card, topicColor);
    return contrastRatio(topicColor, card) >= 4.5
        ? topicColor
        : theme.colorScheme.onSurface;
  }

  /// The online guides exist in French (site root) and English only, so any
  /// other locale goes to the English set rather than to a 404.
  String _docsUrlForLocale(BuildContext context) {
    // The app language, not the device one: a user reading BiblioGenius in
    // French wants the French guides whatever the system locale says.
    final String code = Provider.of<ThemeProvider>(
      context,
      listen: false,
    ).locale.languageCode;
    return code == 'fr'
        ? 'https://bibliogenius.org/docs/'
        : 'https://bibliogenius.org/en/docs/';
  }

  Widget _buildQuickActions(BuildContext context) {
    // Check if dev tools should be shown (via .env flag)
    final showDevTools = dotenv.env['SHOW_DEV_TOOLS']?.toLowerCase() == 'true';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: _sectionTitle(context, 'help_quick_actions'),
        ),
        // First row: Quick Tour + Contact Us. IntrinsicHeight + stretch keep
        // both cards the same height when one label wraps.
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _buildActionCard(
                  context,
                  icon: Icons.explore,
                  label: TranslationService.translate(
                    context,
                    'help_quick_tour',
                  ),
                  gradient: AppDesign.primaryGradient,
                  onTap: () => context.push('/onboarding'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionCard(
                  context,
                  icon: Icons.mail_outline,
                  label: TranslationService.translate(
                    context,
                    'help_contact_us',
                  ),
                  gradient: AppDesign.oceanGradient,
                  onTap: () async {
                    final String subject = TranslationService.translate(
                      context,
                      'help_contact_subject',
                    );
                    // Build the query manually so the space encodes as %20, not
                    // the form-style '+' that Uri.queryParameters produces (mail
                    // clients render that literally, e.g. 'BiblioGenius+-+Contact').
                    final Uri emailUri = Uri(
                      scheme: 'mailto',
                      path: 'contact@bibliogenius.org',
                      query: 'subject=${Uri.encodeComponent(subject)}',
                    );
                    if (await canLaunchUrl(emailUri)) {
                      await launchUrl(emailUri);
                    }
                  },
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Second row: Report a Problem & Import from App
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _buildActionCard(
                  context,
                  icon: Icons.bug_report,
                  label: TranslationService.translate(
                    context,
                    'help_report_problem',
                  ),
                  gradient: AppDesign.warningGradient,
                  onTap: () => context.push('/feedback'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildActionCard(
                  context,
                  icon: Icons.input_rounded,
                  label: TranslationService.translate(
                    context,
                    'help_import_app',
                  ),
                  gradient: AppDesign.accentGradient,
                  onTap: () => context.push('/settings/migration-wizard'),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Third row: the online guides. Full width, since it opens the
        // browser rather than an in-app screen like the four cards above.
        SizedBox(
          width: double.infinity,
          child: _buildActionCard(
            context,
            icon: Icons.menu_book,
            label: TranslationService.translate(context, 'help_online_docs'),
            gradient: AppDesign.darkGradient,
            hint: TranslationService.translate(context, 'open_in_browser'),
            onTap: () async {
              final Uri docsUri = Uri.parse(_docsUrlForLocale(context));
              if (await canLaunchUrl(docsUri)) {
                await launchUrl(docsUri, mode: LaunchMode.externalApplication);
              }
            },
          ),
        ),

        // Developer Tools Section (only shown if SHOW_DEV_TOOLS=true in .env)
        if (showDevTools) ...[
          const SizedBox(height: 24),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: _sectionTitle(context, 'help_tests_title'),
              ),
              _buildActionCard(
                context,
                icon: Icons.animation,
                label: TranslationService.translate(
                  context,
                  'help_animation_tests',
                ),
                gradient: AppDesign.accentGradient,
                onTap: () => context.push('/animations-test'),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildActionCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required LinearGradient gradient,
    required VoidCallback onTap,
    String? hint,
  }) {
    return _QuickActionCard(
      icon: icon,
      label: label,
      gradient: _readableUnderWhite(gradient),
      onTap: onTap,
      hint: hint,
    );
  }
}

/// [gradient] with each stop deepened just enough for white text to clear AA.
///
/// The shared gradients stay as they are: elsewhere they carry no text, or
/// large text that only needs 3:1.
LinearGradient _readableUnderWhite(LinearGradient gradient) {
  return LinearGradient(
    begin: gradient.begin,
    end: gradient.end,
    colors: [
      for (final color in gradient.colors)
        shiftUntilReadable(color, Colors.white),
    ],
  );
}

/// A gradient shortcut card: a button for screen readers, reachable and
/// activable from the keyboard, with a focus ring drawn on the card itself
/// since the default ink highlight barely shows on a saturated gradient.
class _QuickActionCard extends StatefulWidget {
  // Fits the icon plus a two-line label at the default text scale.
  static const double _minHeight = 116;

  final IconData icon;
  final String label;
  final LinearGradient gradient;
  final VoidCallback onTap;
  final String? hint;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.gradient,
    required this.onTap,
    this.hint,
  });

  @override
  State<_QuickActionCard> createState() => _QuickActionCardState();
}

class _QuickActionCardState extends State<_QuickActionCard> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppDesign.radiusMedium);
    return Semantics(
      button: true,
      hint: widget.hint,
      child: Container(
        decoration: BoxDecoration(
          gradient: widget.gradient,
          borderRadius: radius,
          boxShadow: AppDesign.cardShadow,
        ),
        foregroundDecoration: _focused
            ? BoxDecoration(
                borderRadius: radius,
                border: Border.all(color: Colors.white, width: 3),
              )
            : null,
        // Transparent Material so the ripple paints above the gradient.
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: widget.onTap,
            onFocusChange: (focused) => setState(() => _focused = focused),
            borderRadius: radius,
            child: Container(
              // Shared floor so single-line cards match the height of a card
              // whose label wraps on two lines; content stays centered.
              constraints: const BoxConstraints(
                minHeight: _QuickActionCard._minHeight,
              ),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(widget.icon, color: Colors.white, size: 28),
                  const SizedBox(height: 8),
                  Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
