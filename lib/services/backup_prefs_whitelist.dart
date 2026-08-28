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
/// Conservative v1 policy: the whitelist holds only the keys that answer
/// "who and where am I" (theme, language, country, city). Anything else
/// stays in the blacklist until we have user-research evidence that it is
/// meaningful to restore. Widening the whitelist must come with a migration
/// discussion: "is the user happier or more confused if this value is
/// silently overwritten on restore?"
///
/// A value and the consent to publish it are separate arbitrations. The
/// city is restored; the toggle that shares it in the public directory is
/// not (see `hub_share_city` in the blacklist).
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
  // The city the user picked for themselves. Local data by construction
  // (ADR-035 §3 as amended): it exists on the device whether or not it is
  // published. Someone restoring a backup obviously wants their city back,
  // exactly as they want their country back - the two are the same kind of
  // answer to "where am I". The companion country code is the alpha-2 the
  // picker resolved for that city; it travels with the id or the restored
  // value cannot be resolved without re-downloading the right country file.
  // ADR-067: the owner's contact card. User-authored, answers "who am I", and
  // carried nowhere else in the archive. Classified here explicitly because the
  // drift test cannot see it: the key sits behind a const identifier, not a
  // literal `prefs.setString('...')` call.
  'hub_contact_info', // HubDirectoryProvider._kContactInfoKey
  'hub_local_location_city_id',
  'hub_local_location_city_country',
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
  // Dashboard suggestions the user has waved away; feature-discovery state,
  // meaningful only on the install that saw the suggestion.
  'dashboard_discover_dismissed_ids', // DiscoverDismissalService.dismissedIdsKey
  'dashboard_discover_dismissed', // legacy global flag, migrated then removed
  // Recommendations the user marked "Not interested" (ADR-059 follow-up).
  // Device-local by decision: replicating dismissals would need its own ADR.
  'dismissed_recommendation_book_uuids', // RecommendationDismissalService.dismissedBookIdsKey
  // External discovery dismissals (ADR-060): namespaced keys for cards
  // that have no local uuid. Device-local by the same decision as the
  // uuid-keyed sibling above.
  'dismissed_external_suggestion_keys', // ExternalSuggestionDismissalService.dismissedKeysKey
  // Pooled-resolver answers cached per series and per author lookup
  // (ADR-060): bounded device-local caches the next install rebuilds by
  // asking the hub again.
  'discovery_series_cache_v1', // DiscoveryService.cacheKey
  'discovery_author_cache_v1', // DiscoveryService.authorCacheKey
  // Consent to publish the city in the public directory. Deliberately NOT
  // whitelisted alongside the city itself: restoring an archive must give
  // the user their data back, never re-consent on their behalf. Silently
  // inheriting "yes, publish where I live" from an old install is the one
  // outcome this whole split exists to prevent.
  // ADR-067 D9: whether the user waved away the invitation to fill their
  // contact card. A dismissal is a fact about this install's UI, not about the
  // library, and a restored device deserves to be asked again if its card is
  // still empty.
  'hub_contact_prompt_dismissed', // NetworkScreen._contactPromptDismissedKey

  // Bookshop/library linking (POC). Conservative v1 call: dropped on
  // restore. The three JSON lists are String-restorable and could be
  // promoted once the feature's ADR arbitrates it; the two dismissal
  // flags are bools, which the restorer does not re-apply anyway.
  'bookshop_finder_dismissed', // ThemeProvider.setShowBookshopFinder
  'library_intro_dismissed', // ThemeProvider.setShowLibraryIntro
  'my_bookshop_ids', // ThemeProvider my registry portal selection
  'my_custom_bookshops', // ThemeProvider hand-added bookshops
  'my_library_portals', // ThemeProvider connected library catalogues
  'hub_share_city', // HubDirectoryProvider._kShareCityKey
  // One-shot marker: this install has already asked the hub whether it holds
  // a city to recover locally. Bookkeeping about a probe that happened on
  // this device, meaningless anywhere else, and a restored install should
  // run its own probe rather than inherit someone else's answer.
  'hub_city_backfill_probed', // HubDirectoryProvider._kCityBackfillProbedKey
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
