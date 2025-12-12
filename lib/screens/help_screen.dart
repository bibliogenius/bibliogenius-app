import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/genie_app_bar.dart';
import '../services/translation_service.dart';
import '../theme/app_design.dart';

class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key});

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  int? _expandedIndex;

  final List<_HelpTopic> _topics = [
    _HelpTopic(
      icon: Icons.add_circle_outline,
      titleKey: 'help_topic_add_book',
      descKey: 'help_desc_add_book',
      gradient: AppDesign.successGradient,
    ),
    _HelpTopic(
      icon: Icons.import_contacts,
      titleKey: 'help_topic_lend',
      descKey: 'help_desc_lend',
      gradient: AppDesign.oceanGradient,
    ),
    _HelpTopic(
      icon: Icons.qr_code,
      titleKey: 'help_topic_connect',
      descKey: 'help_desc_connect',
      gradient: AppDesign.warningGradient,
    ),
    _HelpTopic(
      icon: Icons.people,
      titleKey: 'help_topic_contacts',
      descKey: 'help_desc_contacts',
      gradient: AppDesign.primaryGradient,
    ),
    _HelpTopic(
      icon: Icons.cloud_sync,
      titleKey: 'help_topic_network',
      descKey: 'help_desc_network_p2p',  // Updated for P2P roadmap
      gradient: AppDesign.accentGradient,
    ),
    _HelpTopic(
      icon: Icons.swap_horiz,
      titleKey: 'help_topic_requests',
      descKey: 'help_desc_requests_p2p',  // Updated for P2P roadmap
      gradient: AppDesign.darkGradient,
    ),
    _HelpTopic(
      icon: Icons.sort,
      titleKey: 'help_topic_organize_shelf',
      descKey: 'help_desc_organize_shelf',
      gradient: AppDesign.successGradient,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GenieAppBar(
        title: TranslationService.translate(context, 'help_title'),
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
                  TranslationService.translate(context, 'help_welcome_subtitle'),
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
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
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
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(AppDesign.radiusSmall),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(
            TranslationService.translate(context, 'help_quick_actions'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _buildActionCard(
                context,
                icon: Icons.school,
                label: TranslationService.translate(context, 'menu_tutorial'),
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
                    queryParameters: {
                      'subject': 'BiblioGenius - Contact',
                    },
                  );
                  if (await canLaunchUrl(emailUri)) {
                    await launchUrl(emailUri);
                  }
                },
              ),
            ),
          ],
        ),
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

  const _HelpTopic({
    required this.icon,
    required this.titleKey,
    required this.descKey,
    required this.gradient,
  });
}
