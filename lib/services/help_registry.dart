import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../theme/app_design.dart';

/// A single help entry shown in the /help screen and/or surfaced
/// contextually next to settings entries.
///
/// [id] is a stable identifier used for deep-linking
/// (`/help?topic=device_sync`) and for the contextual help sheet
/// to look up the right topic from anywhere in the app.
///
/// Two named constructors enforce the FAQ vs inline-help distinction:
/// - [HelpTopic.faq] creates a topic that appears both in `/help`
///   accordion AND via the contextual sheet. Requires a visual identity
///   (icon + gradient) since it has its own card on the help screen.
/// - [HelpTopic.inline] creates a lightweight entry surfaced ONLY via
///   the contextual sheet next to a setting. It never appears in
///   `/help`, so icon/gradient are placeholders that are never rendered.
class HelpTopic {
  final String id;
  final IconData icon;
  final String titleKey;
  final String descKey;
  final LinearGradient gradient;
  final String? ctaKey;
  final String? ctaRoute;

  /// Whether this topic shows up in the `/help` FAQ accordion.
  /// `true` for [HelpTopic.faq], `false` for [HelpTopic.inline].
  final bool inFaq;

  /// FAQ topic — appears both in `/help` and via the contextual sheet.
  const HelpTopic.faq({
    required this.id,
    required this.icon,
    required this.titleKey,
    required this.descKey,
    required this.gradient,
    this.ctaKey,
    this.ctaRoute,
  }) : inFaq = true;

  /// Inline-only help — surfaced via the contextual sheet next to a
  /// setting, never listed in `/help`. Use for short explanations
  /// (1-3 sentences) that don't warrant a full FAQ entry.
  ///
  /// `icon` and `gradient` are placeholders required by the data class
  /// but never rendered, since inline topics never appear in `/help`.
  const HelpTopic.inline({
    required this.id,
    required this.titleKey,
    required this.descKey,
  }) : icon = Icons.info_outline,
       gradient = AppDesign.primaryGradient,
       ctaKey = null,
       ctaRoute = null,
       inFaq = false;
}

/// A topic + an optional visibility predicate driven by the user's
/// enabled modules (collections, audio, games...).
class _GatedTopic {
  final HelpTopic topic;
  final bool Function(ThemeProvider)? gate;
  const _GatedTopic({required this.topic, this.gate});
}

/// Single source of truth for the help catalogue.
///
/// Two access patterns are exposed:
/// - [getAllForUser] returns the ordered list shown in /help, filtered
///   by which optional modules are currently enabled.
/// - [findById] looks up a topic by its stable id (used by
///   ContextualHelpSheet and by the /help?topic=... deep link).
///   Module gating is intentionally NOT applied here: callers reference
///   topics from screens that already know the relevant module is on.
class HelpRegistry {
  HelpRegistry._();

  static final List<_GatedTopic> _registry = _buildRegistry();

  static List<_GatedTopic> _buildRegistry() {
    return const [
      // --- Getting Started ---
      _GatedTopic(
        topic: HelpTopic.faq(
          id: 'add_book',
          icon: Icons.add_circle_outline,
          titleKey: 'help_topic_add_book',
          descKey: 'help_desc_add_book',
          gradient: AppDesign.successGradient,
          ctaKey: 'help_cta_go_to_library',
          ctaRoute: '/books',
        ),
      ),
      _GatedTopic(
        topic: HelpTopic.faq(
          id: 'scan',
          icon: Icons.qr_code_scanner,
          titleKey: 'help_topic_scan',
          descKey: 'help_desc_scan',
          gradient: AppDesign.warningGradient,
          ctaKey: 'help_cta_scan',
          ctaRoute: '/scan',
        ),
      ),
      _GatedTopic(
        topic: HelpTopic.faq(
          id: 'external_search',
          icon: Icons.search,
          titleKey: 'help_topic_external_search',
          descKey: 'help_desc_external_search',
          gradient: AppDesign.oceanGradient,
          ctaKey: 'help_cta_search_catalogs',
          ctaRoute: '/search/external',
        ),
      ),
      _GatedTopic(
        topic: HelpTopic.faq(
          id: 'organize_shelf',
          icon: Icons.sort,
          titleKey: 'help_topic_organize_shelf',
          descKey: 'help_desc_organize_shelf',
          gradient: AppDesign.accentGradient,
          ctaKey: 'help_cta_manage_shelves',
          ctaRoute: '/shelves-management',
        ),
      ),
      _GatedTopic(
        topic: HelpTopic.faq(
          id: 'reading_progress',
          icon: Icons.auto_stories,
          titleKey: 'help_topic_reading_progress',
          descKey: 'help_desc_reading_progress',
          gradient: AppDesign.primaryGradient,
          ctaKey: 'help_cta_go_to_library',
          ctaRoute: '/books',
        ),
      ),

      // --- Network & Sharing ---
      _GatedTopic(
        topic: HelpTopic.faq(
          id: 'connect',
          icon: Icons.qr_code,
          titleKey: 'help_topic_connect',
          descKey: 'help_desc_connect',
          gradient: AppDesign.oceanGradient,
          ctaKey: 'help_cta_go_to_network',
          ctaRoute: '/network',
        ),
      ),
      _GatedTopic(
        topic: HelpTopic.faq(
          id: 'lend',
          icon: Icons.import_contacts,
          titleKey: 'help_topic_lend',
          descKey: 'help_desc_lend',
          gradient: AppDesign.successGradient,
          ctaKey: 'help_cta_go_to_library',
          ctaRoute: '/books',
        ),
      ),
      _GatedTopic(
        topic: HelpTopic.faq(
          id: 'requests',
          icon: Icons.swap_horiz,
          titleKey: 'help_topic_requests',
          descKey: 'help_desc_requests',
          gradient: AppDesign.warningGradient,
          ctaKey: 'help_cta_view_requests',
          ctaRoute: '/requests',
        ),
      ),

      // --- Advanced (conditional) ---
      _GatedTopic(
        topic: HelpTopic.faq(
          id: 'collections',
          icon: Icons.inventory_2_outlined,
          titleKey: 'help_topic_collections',
          descKey: 'help_desc_collections',
          gradient: AppDesign.primaryGradient,
          ctaKey: 'help_cta_go_to_collections',
          ctaRoute: '/collections',
        ),
        gate: _collectionsEnabled,
      ),
      _GatedTopic(
        topic: HelpTopic.faq(
          id: 'audio',
          icon: Icons.headphones,
          titleKey: 'help_topic_audio',
          descKey: 'help_desc_audio',
          gradient: AppDesign.accentGradient,
          ctaKey: 'help_cta_go_to_profile',
          ctaRoute: '/profile',
        ),
        gate: _audioEnabled,
      ),
      _GatedTopic(
        topic: HelpTopic.faq(
          id: 'memory_game',
          icon: Icons.grid_view_rounded,
          titleKey: 'help_topic_memory_game',
          descKey: 'help_desc_memory_game',
          gradient: LinearGradient(
            colors: [Color(0xFFEA580C), Color(0xFFFB923C)],
          ),
          ctaKey: 'help_cta_play_memory',
          ctaRoute: '/memory-game',
        ),
        gate: _memoryGameEnabled,
      ),
      _GatedTopic(
        topic: HelpTopic.faq(
          id: 'sliding_puzzle',
          icon: Icons.grid_view,
          titleKey: 'help_topic_sliding_puzzle',
          descKey: 'help_desc_sliding_puzzle',
          gradient: LinearGradient(
            colors: [Color(0xFF2563EB), Color(0xFF60A5FA)],
          ),
          ctaKey: 'help_cta_play_puzzle',
          ctaRoute: '/sliding-puzzle',
        ),
        gate: _slidingPuzzleEnabled,
      ),
      _GatedTopic(
        topic: HelpTopic.faq(
          id: 'hangman',
          icon: Icons.text_fields,
          titleKey: 'help_topic_hangman',
          descKey: 'help_desc_hangman',
          gradient: LinearGradient(
            colors: [Color(0xFF7C3AED), Color(0xFFA78BFA)],
          ),
          ctaKey: 'help_cta_play_hangman',
          ctaRoute: '/hangman',
        ),
        gate: _hangmanEnabled,
      ),

      // --- Data & Settings ---
      _GatedTopic(
        topic: HelpTopic.faq(
          id: 'device_sync',
          icon: Icons.devices_rounded,
          titleKey: 'help_topic_device_sync',
          descKey: 'help_desc_device_sync',
          gradient: AppDesign.oceanGradient,
          ctaKey: 'help_cta_open_device_sync',
          ctaRoute: '/device-pairing',
        ),
      ),
      _GatedTopic(
        topic: HelpTopic.faq(
          id: 'import',
          icon: Icons.get_app_outlined,
          titleKey: 'help_topic_import',
          descKey: 'help_desc_import',
          gradient: AppDesign.accentGradient,
          ctaKey: 'help_cta_import',
          ctaRoute: '/settings/migration-wizard',
        ),
      ),
      _GatedTopic(
        topic: HelpTopic.faq(
          id: 'statistics',
          icon: Icons.bar_chart,
          titleKey: 'help_topic_statistics',
          descKey: 'help_desc_statistics',
          gradient: LinearGradient(
            colors: [Color(0xFF7C3AED), Color(0xFFA78BFA)],
          ),
          ctaKey: 'help_cta_go_to_stats',
          ctaRoute: '/statistics',
        ),
      ),
      _GatedTopic(
        topic: HelpTopic.faq(
          id: 'profile',
          icon: Icons.person_outline,
          titleKey: 'help_topic_profile',
          descKey: 'help_desc_profile',
          gradient: AppDesign.darkGradient,
          ctaKey: 'help_cta_profile',
          ctaRoute: '/profile',
        ),
      ),
      _GatedTopic(
        topic: HelpTopic.faq(
          id: 'data_privacy',
          icon: Icons.shield_outlined,
          titleKey: 'help_topic_data_privacy',
          descKey: 'help_desc_data_privacy',
          gradient: AppDesign.darkGradient,
          ctaKey: 'help_cta_go_to_profile',
          ctaRoute: '/profile',
        ),
      ),

      // --- Inline help for Settings > Modules toggles (Phase 1) ---
      // These entries never appear in /help — only via the contextual
      // sheet when the user taps the "?" next to a module toggle.
      _GatedTopic(
        topic: HelpTopic.inline(
          id: 'quotes_module',
          titleKey: 'quotes_module',
          descKey: 'quotes_module_help',
        ),
      ),
      _GatedTopic(
        topic: HelpTopic.inline(
          id: 'gamification_module',
          titleKey: 'gamification_module',
          descKey: 'gamification_module_help',
        ),
      ),
      _GatedTopic(
        topic: HelpTopic.inline(
          id: 'games_module',
          titleKey: 'games_module',
          descKey: 'games_module_help',
        ),
      ),
      _GatedTopic(
        topic: HelpTopic.inline(
          id: 'network_gamification',
          titleKey: 'network_gamification',
          descKey: 'network_gamification_help',
        ),
      ),
      _GatedTopic(
        topic: HelpTopic.inline(
          id: 'share_gamification_stats',
          titleKey: 'share_gamification_stats',
          descKey: 'share_gamification_stats_help',
        ),
      ),
      _GatedTopic(
        topic: HelpTopic.inline(
          id: 'group_by_collections',
          titleKey: 'group_by_collections_title',
          descKey: 'group_by_collections_help',
        ),
      ),
      _GatedTopic(
        topic: HelpTopic.inline(
          id: 'commerce_module',
          titleKey: 'commerce_module',
          descKey: 'commerce_module_help',
        ),
      ),
      _GatedTopic(
        topic: HelpTopic.inline(
          id: 'speech_to_text',
          titleKey: 'speech_to_text_setting',
          descKey: 'speech_to_text_setting_help',
        ),
      ),
      _GatedTopic(
        topic: HelpTopic.inline(
          id: 'auto_approve_loans',
          titleKey: 'auto_approve_loans_title',
          descKey: 'auto_approve_loans_help',
        ),
      ),
      _GatedTopic(
        topic: HelpTopic.inline(
          id: 'enable_borrowing',
          titleKey: 'enable_borrowing_module',
          descKey: 'enable_borrowing_module_help',
        ),
      ),
      _GatedTopic(
        topic: HelpTopic.inline(
          id: 'allow_private_books',
          titleKey: 'settings_allow_private_books',
          descKey: 'settings_allow_private_books_help',
        ),
      ),
      _GatedTopic(
        topic: HelpTopic.inline(
          id: 'digital_formats',
          titleKey: 'module_digital_formats',
          descKey: 'module_digital_formats_help',
        ),
      ),

      // --- Inline help for Settings > Backup & export tiles ---
      _GatedTopic(
        topic: HelpTopic.inline(
          id: 'backup_export_catalog',
          titleKey: 'backup_export_catalog_title',
          descKey: 'backup_export_catalog_help',
        ),
      ),
      _GatedTopic(
        topic: HelpTopic.inline(
          id: 'backup_full',
          titleKey: 'backup_full_title',
          descKey: 'backup_full_help',
        ),
      ),
      _GatedTopic(
        topic: HelpTopic.inline(
          id: 'backup_restore_full',
          titleKey: 'backup_restore_full_title',
          descKey: 'backup_restore_full_help',
        ),
      ),
      _GatedTopic(
        topic: HelpTopic.inline(
          id: 'backup_restore_json',
          titleKey: 'backup_restore_title',
          descKey: 'backup_restore_help',
        ),
      ),

      // --- Inline help for Settings > Account / Data / Search (Phase 1) ---
      _GatedTopic(
        topic: HelpTopic.inline(
          id: 'auto_backup',
          titleKey: 'settings_auto_backup',
          descKey: 'settings_auto_backup_help',
        ),
      ),
      _GatedTopic(
        topic: HelpTopic.inline(
          id: 'search_sources',
          titleKey: 'search_sources',
          descKey: 'search_sources_help',
        ),
      ),
      _GatedTopic(
        topic: HelpTopic.inline(
          id: 'password_setting',
          titleKey: 'password',
          descKey: 'settings_password_help',
        ),
      ),
      _GatedTopic(
        topic: HelpTopic.inline(
          id: 'two_factor_auth_setting',
          titleKey: 'two_factor_auth',
          descKey: 'two_factor_auth_help',
        ),
      ),

      // --- Inline help for Settings > Notifications toggles (Phase 1) ---
      _GatedTopic(
        topic: HelpTopic.inline(
          id: 'notif_enabled',
          titleKey: 'settings_notif_enabled',
          descKey: 'notif_enabled_help',
        ),
      ),
      _GatedTopic(
        topic: HelpTopic.inline(
          id: 'notif_connections',
          titleKey: 'settings_notif_connections',
          descKey: 'notif_connections_help',
        ),
      ),
      _GatedTopic(
        topic: HelpTopic.inline(
          id: 'notif_loans',
          titleKey: 'settings_notif_loans',
          descKey: 'notif_loans_help',
        ),
      ),
      _GatedTopic(
        topic: HelpTopic.inline(
          id: 'notif_discoveries',
          titleKey: 'settings_notif_discoveries',
          descKey: 'notif_discoveries_help',
        ),
      ),
    ];
  }

  /// Returns the FAQ topics shown in `/help`, in registry order,
  /// filtered by which optional modules are currently enabled.
  /// Inline-only topics (`HelpTopic.inline`) are excluded.
  static List<HelpTopic> getAllForUser(BuildContext context) {
    final theme = Provider.of<ThemeProvider>(context, listen: false);
    return _registry
        .where((g) => g.topic.inFaq)
        .where((g) => g.gate == null || g.gate!(theme))
        .map((g) => g.topic)
        .toList();
  }

  /// Looks up a topic by its stable id without applying module gating.
  /// Returns null if no topic with that id exists.
  static HelpTopic? findById(String id) {
    for (final g in _registry) {
      if (g.topic.id == id) return g.topic;
    }
    return null;
  }

  // --- gate predicates (extracted to top-level functions so the
  //     _GatedTopic literals can stay const) ---

  static bool _collectionsEnabled(ThemeProvider t) => t.collectionsEnabled;
  static bool _audioEnabled(ThemeProvider t) => t.audioEnabled;
  static bool _memoryGameEnabled(ThemeProvider t) => t.memoryGameEnabled;
  static bool _slidingPuzzleEnabled(ThemeProvider t) => t.slidingPuzzleEnabled;
  static bool _hangmanEnabled(ThemeProvider t) => t.hangmanEnabled;
}
