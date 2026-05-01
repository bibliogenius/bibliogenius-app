/// Formal whitelist (and blacklist) of `SharedPreferences` keys for the
/// `.bgbackup` writer + reader (ADR-037 §6).
///
/// **Whitelist** = keys the writer captures into `prefs.json` and the
/// reader re-applies on restore. Round-trip lossless.
///
/// **Blacklist** = keys the writer deliberately drops because they are
/// install-specific (push tokens, scheduler bookkeeping, FFI cache,
/// onboarding flags) or already represented elsewhere in the archive
/// (anything mirrored from the SQLite catalog).
///
/// Every literal `prefs.setX('key', ...)` call in `lib/` MUST belong to
/// one of these two sets. The test
/// `test/services/backup_prefs_whitelist_test.dart` enforces that
/// invariant by static-grepping the source tree and failing CI on any
/// unclassified key. Adding a new pref therefore requires an explicit
/// arbitration decision: user-meaningful (whitelist) or install-only
/// (blacklist)?
///
/// Conservative v1 policy: only the three keys the writer captured before
/// this commit live in the whitelist (theme, language, country). Anything
/// else stays in the blacklist until we have user-research evidence that
/// it is meaningful to restore. Widening the whitelist must come with a
/// migration discussion: "is the user happier or more confused if this
/// value is silently overwritten on restore?"
///
/// Dynamically computed keys (e.g. `prefs.setString(_versionKey, ...)`
/// where `_versionKey = 'last_app_version'`) are NOT enumerated by the
/// drift test. Known dynamic keys are still listed in the blacklist below
/// for review-trail completeness.
library;

import 'dart:convert';

/// Keys exported by the writer and re-applied on restore. Stay
/// conservative when adding -- a wrong addition silently overwrites the
/// user's local preference on restore.
const Set<String> kBackupPrefsWhitelist = <String>{
  'themeStyle',
  'languageCode',
  'country',
};

/// Keys the writer deliberately drops. Inclusion here is documentation:
/// "this key was reviewed, it is install-specific or mirrored elsewhere".
const Set<String> kBackupPrefsBlacklist = <String>{
  // Auto-backup scheduler bookkeeping (install-local).
  'auto_backup_enabled',
  'auto_backup_last_watermark',
  'auto_backup_last_ts',
  'auto_backup_consecutive_failures',
  'auto_backup_unlock_mode',
  'auto_backup_clone_nudge_snoozed_at',
  // Manual clone-export reminder timestamp; install-local UX trail.
  'last_full_export_with_identity_at',

  // FFI cache (sourced from `library_config` SQL row, install-local).
  'ffi_api_keys',
  'ffi_fallback_preferences',
  'ffi_latitude',
  'ffi_library_description',
  'ffi_library_name',
  'ffi_longitude',
  'ffi_profile_type',
  'ffi_share_location',
  'ffi_show_borrowed_books',
  'ffi_tags',

  // Onboarding / install state (mirrored in DB or device-specific).
  'isSetupComplete',
  'libraryName',
  'libraryNameCustomized',
  'libraryTag',
  'username',
  'userLanguages',

  // UI memory (transient, device-local).
  'carousel_hidden_own_lib',
  'carousel_hidden_peer_lib',
  'streak_celebration_last_shown',
  'streak_last_celebrated_milestone',
  'yearly_goal_celebrated_year',

  // Stats / profile card layout (candidates for promotion to whitelist
  // after UX review: "do users expect their card layout to follow them
  // across devices?"). Default to install-local for v1.
  'statistics_summary_hidden',
  'statistics_summary_order',
  'profile_stats_card_order',
  'profile_stats_card_hidden',

  // Per-game cosmetic preferences (visual modes etc.); device-local.
  'hangmanVisualMode',

  // Profile cosmetic state (could be promoted later after UX review).
  'avatarConfig',
  'avatarId',
  'bannerColor',
  'currency',
  'textScaleFactor',

  // Feature toggles (could be promoted later). Each candidate needs an
  // explicit "do I want my restored Mac to silently inherit these toggles
  // from my old phone?" discussion. Default: keep device-local until that
  // discussion happens.
  'allowLibraryCaching',
  'allowPrivateBooks',
  'audioEnabled',
  'autoApproveLoanRequests',
  'autoBackupEnabled',
  'bottomNavEnabled',
  'canBorrowBooks',
  'canLendBooks',
  'collectionsEnabled',
  'commerceEnabled',
  'connectionValidationEnabled',
  'digitalFormatsEnabled',
  'enableHierarchicalTags',
  'gamesEnabled',
  'gamificationEnabled',
  'groupByCollections',
  'hangmanEnabled',
  'inventoryStatusesEnabled',
  'mcpEnabled',
  'memoryGameEnabled',
  'networkDiscoveryEnabled',
  'networkGamificationEnabled',
  'notifConnectionsEnabled',
  'notifDiscoveriesEnabled',
  'notifLoansEnabled',
  'notificationsEnabled',
  'operationLogViewerEnabled',
  'peerCoverCacheCapMb',
  'peerCoverDisplayEnabled',
  'peerOfflineCachingEnabled',
  'quotesEnabled',
  'remoteReachableEnabled',
  'shareGamificationStats',
  'showViewCount',
  'slidingPuzzleEnabled',
  'speechToTextEnabled',
  'syncSafetyEnabled',

  // Known dynamic keys (computed at the call site, not literal-grepped).
  // Listed here for review trail.
  'last_app_version', // BackupReminderService._lastVersionKey
  'last_backup_reminder', // BackupReminderService._lastReminderKey
};

/// Encode the user-meaningful subset of the caller's preferences store
/// as a compact JSON string suitable for embedding in a `.bgbackup`
/// archive. The caller passes a `lookup` function -- typically
/// `SharedPreferences.get` -- so this helper stays decoupled from the
/// shared_preferences package. Keys whose value is `null` are omitted,
/// keeping reader-side `null`-vs-missing semantics trivial.
String exportWhitelistedPrefs(Object? Function(String key) lookup) {
  final out = <String, Object>{};
  for (final key in kBackupPrefsWhitelist) {
    final value = lookup(key);
    if (value != null) {
      out[key] = value;
    }
  }
  return jsonEncode(out);
}
