/// Search index and matching logic for the Settings screen.
///
/// Extracted from `settings_screen.dart` (4600+ lines) so the synonym data and
/// the pure matching rule can be unit-tested without a widget harness.
library;

/// Hidden search synonyms: maps a section/setting i18n key to extra search
/// terms (FR + EN, accent-free) that are NEVER displayed but make a setting
/// findable by intent. Example: typing "appairage", "pairing" or "code"
/// surfaces "Synchroniser mes appareils". Kept in Dart (not .po) on purpose:
/// this is a search index, not user-facing copy, and mixing FR+EN terms lets a
/// user find a setting regardless of the current UI language.
const Map<String, String> settingsSearchSynonyms = {
  'settings_linked_devices':
      'appairage pairing jumeler jumelage code synchro synchronisation '
      'synchroniser multi appareil multi device tablette mobile bureau '
      'desktop wifi lan',
  // Merged "Backup and recovery" section: local backup terms + the former
  // "Account" accordion terms (the two sections were merged) + the
  // encrypted-account / recovery / shared-access vocabulary.
  'backup_section_title':
      'sauvegarde sauvegarder backup restaurer restauration restore export '
      'archive copie compte account chiffre chiffrement encrypted '
      'recuperation recovery partage partager acces access securite security '
      'mot de passe password mfa 2fa session connexion deconnexion login '
      'logout csv tableur tableau excel spreadsheet listing liste inventaire '
      'inventory assurance',
  'theme_title':
      'theme apparence couleur dark mode sombre clair police texte taille '
      'font lisibilite',
  'settings_network_title':
      'reseau network wifi lan connexion pair peer relais relay annuaire '
      'directory portee reachability',
  'modules':
      'modules fonctionnalites features citations quotes jeux games '
      'gamification mcp audio collections commerce',
  'search_sources':
      'sources recherche search isbn google books bnf babelio scan',
};

/// Whether a setting identified by [key] matches the [query], considering both
/// its visible [label] and any hidden synonyms registered for that key.
///
/// [query] and [label] are matched case-insensitively. The caller is expected
/// to pass an already-translated [label]; [query] may have any case.
bool settingsKeyMatches({
  required String key,
  required String label,
  required String query,
}) {
  if (query.isEmpty) return true;
  final q = query.toLowerCase();
  if (label.toLowerCase().contains(q)) return true;
  final synonyms = settingsSearchSynonyms[key];
  return synonyms != null && synonyms.contains(q);
}
