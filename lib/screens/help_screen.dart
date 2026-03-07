import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/genie_app_bar.dart';
import '../widgets/scaffold_with_nav.dart';
import '../services/translation_service.dart';
import '../theme/app_design.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  int? _expandedIndex;
  late List<_HelpTopic> _topics;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final themeProvider = Provider.of<ThemeProvider>(context);
    final collectionsEnabled = themeProvider.collectionsEnabled;
    final audioEnabled = themeProvider.audioEnabled;
    final memoryGameEnabled = themeProvider.memoryGameEnabled;
    final slidingPuzzleEnabled = themeProvider.slidingPuzzleEnabled;

    _topics = [
      // --- Getting Started ---
      _HelpTopic(
        icon: Icons.add_circle_outline,
        titleKey: 'help_topic_add_book',
        descKey: 'help_desc_add_book',
        gradient: AppDesign.successGradient,
        ctaKey: 'help_cta_go_to_library',
        ctaRoute: '/books',
      ),
      _HelpTopic(
        icon: Icons.qr_code_scanner,
        titleKey: 'help_topic_scan',
        descKey: 'help_desc_scan',
        gradient: AppDesign.warningGradient,
        ctaKey: 'help_cta_scan',
        ctaRoute: '/scan',
      ),
      _HelpTopic(
        icon: Icons.search,
        titleKey: 'help_topic_external_search',
        descKey: 'help_desc_external_search',
        gradient: AppDesign.oceanGradient,
        ctaKey: 'help_cta_search_catalogs',
        ctaRoute: '/search/external',
      ),
      _HelpTopic(
        icon: Icons.sort,
        titleKey: 'help_topic_organize_shelf',
        descKey: 'help_desc_organize_shelf',
        gradient: AppDesign.accentGradient,
        ctaKey: 'help_cta_manage_shelves',
        ctaRoute: '/shelves-management',
      ),
      _HelpTopic(
        icon: Icons.auto_stories,
        titleKey: 'help_topic_reading_progress',
        descKey: 'help_desc_reading_progress',
        gradient: AppDesign.primaryGradient,
        ctaKey: 'help_cta_go_to_library',
        ctaRoute: '/books',
      ),

      // --- Network & Sharing ---
      _HelpTopic(
        icon: Icons.qr_code,
        titleKey: 'help_topic_connect',
        descKey: 'help_desc_connect',
        gradient: AppDesign.oceanGradient,
        ctaKey: 'help_cta_go_to_network',
        ctaRoute: '/network',
      ),
      _HelpTopic(
        icon: Icons.import_contacts,
        titleKey: 'help_topic_lend',
        descKey: 'help_desc_lend',
        gradient: AppDesign.successGradient,
        ctaKey: 'help_cta_go_to_library',
        ctaRoute: '/books',
      ),
      _HelpTopic(
        icon: Icons.swap_horiz,
        titleKey: 'help_topic_requests',
        descKey: 'help_desc_requests',
        gradient: AppDesign.warningGradient,
        ctaKey: 'help_cta_view_requests',
        ctaRoute: '/requests',
      ),

      // --- Advanced (conditional) ---
      if (collectionsEnabled)
        _HelpTopic(
          icon: Icons.inventory_2_outlined,
          titleKey: 'help_topic_collections',
          descKey: 'help_desc_collections',
          gradient: AppDesign.primaryGradient,
          ctaKey: 'help_cta_go_to_collections',
          ctaRoute: '/collections',
        ),
      if (audioEnabled)
        _HelpTopic(
          icon: Icons.headphones,
          titleKey: 'help_topic_audio',
          descKey: 'help_desc_audio',
          gradient: AppDesign.accentGradient,
          ctaKey: 'help_cta_go_to_profile',
          ctaRoute: '/profile',
        ),
      if (memoryGameEnabled)
        _HelpTopic(
          icon: Icons.grid_view_rounded,
          titleKey: 'help_topic_memory_game',
          descKey: 'help_desc_memory_game',
          gradient: const LinearGradient(
            colors: [Color(0xFFEA580C), Color(0xFFFB923C)],
          ),
          ctaKey: 'help_cta_play_memory',
          ctaRoute: '/memory-game',
        ),
      if (slidingPuzzleEnabled)
        _HelpTopic(
          icon: Icons.grid_view,
          titleKey: 'help_topic_sliding_puzzle',
          descKey: 'help_desc_sliding_puzzle',
          gradient: const LinearGradient(
            colors: [Color(0xFF2563EB), Color(0xFF60A5FA)],
          ),
          ctaKey: 'help_cta_play_puzzle',
          ctaRoute: '/sliding-puzzle',
        ),

      // --- Data & Settings ---
      _HelpTopic(
        icon: Icons.get_app_outlined,
        titleKey: 'help_topic_import',
        descKey: 'help_desc_import',
        gradient: AppDesign.accentGradient,
        ctaKey: 'help_cta_import',
        ctaRoute: '/settings/migration-wizard',
      ),
      _HelpTopic(
        icon: Icons.bar_chart,
        titleKey: 'help_topic_statistics',
        descKey: 'help_desc_statistics',
        gradient: const LinearGradient(
          colors: [Color(0xFF7C3AED), Color(0xFFA78BFA)],
        ),
        ctaKey: 'help_cta_go_to_stats',
        ctaRoute: '/statistics',
      ),
      _HelpTopic(
        icon: Icons.person_outline,
        titleKey: 'help_topic_profile',
        descKey: 'help_desc_profile',
        gradient: AppDesign.darkGradient,
        ctaKey: 'help_cta_profile',
        ctaRoute: '/profile',
      ),
      _HelpTopic(
        icon: Icons.shield_outlined,
        titleKey: 'help_topic_data_privacy',
        descKey: 'help_desc_data_privacy',
        gradient: AppDesign.darkGradient,
        ctaKey: 'help_cta_go_to_profile',
        ctaRoute: '/profile',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GenieAppBar(
        title: TranslationService.translate(context, 'help_title'),
        leading: buildDrawerLeading(context),
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: AppDesign.primaryGradient,
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
                Text(
                  TranslationService.translate(context, 'help_welcome_title'),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  TranslationService.translate(
                    context,
                    'help_welcome_subtitle',
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Section title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text(
              TranslationService.translate(context, 'help_faq_title'),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),

          // Help Topics
          ...List.generate(_topics.length, (index) {
            final topic = _topics[index];
            final isExpanded = _expandedIndex == index;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildHelpCard(context, topic, index, isExpanded),
            );
          }),

          const SizedBox(height: 24),

          // Quick Actions
          _buildQuickActions(context),
        ],
      ),
    );
  }

  Widget _buildHelpCard(
    BuildContext context,
    _HelpTopic topic,
    int index,
    bool isExpanded,
  ) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _expandedIndex = isExpanded ? null : index;
        });
      },
      child: AnimatedContainer(
        duration: AppDesign.standardDuration,
        curve: AppDesign.standardCurve,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
          boxShadow: isExpanded ? AppDesign.cardShadow : AppDesign.subtleShadow,
          border: Border.all(
            color: isExpanded
                ? (topic.gradient.colors.first).withValues(alpha: 0.5)
                : Colors.grey.withValues(alpha: 0.1),
            width: isExpanded ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: topic.gradient,
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
                            foregroundColor: topic.gradient.colors.first,
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

  Widget _buildQuickActions(BuildContext context) {
    // Check if dev tools should be shown (via .env flag)
    final showDevTools = dotenv.env['SHOW_DEV_TOOLS']?.toLowerCase() == 'true';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(
            TranslationService.translate(context, 'help_quick_actions'),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        // First row: Quick Tour + Contact Us
        Row(
          children: [
            Expanded(
              child: _buildActionCard(
                context,
                icon: Icons.explore,
                label: TranslationService.translate(context, 'help_quick_tour'),
                gradient: AppDesign.primaryGradient,
                onTap: () => context.push('/onboarding'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildActionCard(
                context,
                icon: Icons.mail_outline,
                label: TranslationService.translate(context, 'help_contact_us'),
                gradient: AppDesign.oceanGradient,
                onTap: () async {
                  final Uri emailUri = Uri(
                    scheme: 'mailto',
                    path: 'contact@bibliogenius.org',
                    queryParameters: {'subject': 'BiblioGenius - Contact'},
                  );
                  if (await canLaunchUrl(emailUri)) {
                    await launchUrl(emailUri);
                  }
                },
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Second row: Report a Problem & Import from App
        Row(
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
                label: TranslationService.translate(context, 'help_import_app'),
                gradient: AppDesign.accentGradient,
                onTap: () => context.push('/settings/migration-wizard'),
              ),
            ),
          ],
        ),

        // Developer Tools Section (only shown if SHOW_DEV_TOOLS=true in .env)
        if (showDevTools) ...[
          const SizedBox(height: 24),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text(
                  TranslationService.translate(context, 'help_tests_title'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
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
    required Gradient gradient,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(AppDesign.radiusMedium),
          boxShadow: AppDesign.cardShadow,
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HelpTopic {
  final IconData icon;
  final String titleKey;
  final String descKey;
  final LinearGradient gradient;
  final String? ctaKey; // Translation key for CTA button
  final String? ctaRoute; // Route to navigate to

  const _HelpTopic({
    required this.icon,
    required this.titleKey,
    required this.descKey,
    required this.gradient,
    this.ctaKey,
    this.ctaRoute,
  });
}
