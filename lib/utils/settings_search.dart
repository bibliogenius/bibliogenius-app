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
  // "Account and devices": the encrypted account, recovery after a loss,
  // shared access and the session.
  'settings_account_devices_title':
      'compte account chiffre chiffrement encrypted recuperation recovery '
      'partage partager acces access securite security mot de passe '
      'password mfa 2fa session connexion deconnexion login logout '
      'appareil appareils device devices synchro sync',
  'backup_section_title':
      'sauvegarde sauvegarder backup restaurer restauration restore export '
      'archive copie csv tableur tableau excel spreadsheet listing liste '
      'inventaire inventory assurance',
  'content':
      'catalogue catalog import importer csv xlsx excel tableur fichier file '
      'etagere etageres shelf shelves doublon doublons duplicate duplicates '
      'fusionner merge format formats numerique ebook epub pdf couverture '
      'cover photo recadrage crop',
  'modules_group_lending':
      'pret prets preter emprunt emprunts emprunter loan loans lend lending '
      'borrow borrowing duree duration rappel reminder approbation approve '
      'prive private',
  'search_sources':
      'sources recherche search isbn google books bnf babelio scan',
  'settings_bookshops_title':
      'librairie librairies bookshop bookshops mediatheque bibliotheque '
      'library libraries acheter buy',
  'theme_title':
      'theme apparence affichage display couleur dark mode sombre clair '
      'police texte taille font lisibilite navigation menu accueil home '
      'vignette vignettes couverture couvertures cover covers grille grid '
      'bandeau activite activity grouper group etat status lecture reading '
      'lu read collection collections possede owned',
  'settings_network_title':
      'reseau network partage partager sharing share wifi lan connexion pair '
      'peer relais relay annuaire directory public portee reachability',
  'modules':
      'modules fonctionnalites features citations quotes jeux games '
      'gamification audio collections commerce dictee voix voice '
      'preconfiguration preset',
  'settings_notifications': 'notification notifications alerte alertes alert',
  'modules_group_advanced':
      'avance advanced mcp ia ai assistant claude journal log operations '
      'developpeur developer experimental version reinitialiser reset',
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
