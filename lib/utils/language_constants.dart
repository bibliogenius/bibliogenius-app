import 'package:flutter/widgets.dart';

/// Normalize a BCP 47 language tag (e.g. "pt-BR", "zh_TW") to its
/// base ISO 639-1 language code (e.g. "pt", "zh").
/// Already-simple codes like "fr" pass through unchanged.
String normalizeLanguageCode(String code) {
  // Split on hyphen or underscore, take the language part, lowercase it.
  final base = code.split(RegExp(r'[-_]')).first.toLowerCase();
  return base;
}

/// Parse a BCP 47 tag string into a [Locale].
///
/// Examples:
///   'pt-BR' → Locale('pt', 'BR')
///   'zh-TW' → Locale('zh', 'TW')
///   'en'    → Locale('en')
Locale parseLocaleTag(String tag) {
  final parts = tag.split(RegExp(r'[-_]'));
  if (parts.length >= 2) {
    return Locale(parts[0].toLowerCase(), parts[1].toUpperCase());
  }
  return Locale(parts[0].toLowerCase());
}

/// Convert a [Locale] back to a BCP 47 tag string.
///
/// Examples:
///   Locale('pt', 'BR') → 'pt-BR'
///   Locale('en')        → 'en'
String localeToTag(Locale locale) {
  if (locale.countryCode != null && locale.countryCode!.isNotEmpty) {
    return '${locale.languageCode}-${locale.countryCode}';
  }
  return locale.languageCode;
}

/// Normalize a locale tag to the closest key in [kLanguageNativeNames].
/// 'fr-FR' → 'fr' (exact 'fr-FR' not in map, but 'fr' is).
/// 'pt-BR' → 'pt-BR' (exact match exists).
/// 'zh-Hans-CN' → 'zh-CN' (fallback to base-region).
/// Returns the original tag if no mapping is found.
String normalizeToKnownLanguage(String tag) {
  if (kLanguageNativeNames.containsKey(tag)) return tag;
  // Try base language code
  final base = tag.split(RegExp(r'[-_]')).first.toLowerCase();
  if (kLanguageNativeNames.containsKey(base)) return base;
  return tag;
}

/// Shared map of language codes to their native display names.
/// Used by settings_screen.dart and external_search_screen.dart.
///
/// Regional variants use BCP 47 tags (e.g. 'pt-BR') and appear as
/// distinct entries. Generic codes (e.g. 'pt') remain for users who
/// don't need a regional distinction.
const Map<String, String> kLanguageNativeNames = {
  'fr': 'Français',
  'en': 'English',
  'es': 'Español',
  'de': 'Deutsch',
  'it': 'Italiano',
  'pt': 'Português',
  'pt-BR': 'Português (Brasil)',
  'pt-PT': 'Português (Portugal)',
  'nl': 'Nederlands',
  'ru': 'Русский',
  'ja': '日本語',
  'zh-CN': '中文 (简体)',
  'zh-TW': '中文 (繁體)',
  'ar': 'العربية',
  'ko': '한국어',
  'pl': 'Polski',
  'sv': 'Svenska',
  'da': 'Dansk',
  'nb': 'Norsk',
  'fi': 'Suomi',
  'cs': 'Čeština',
  'el': 'Ελληνικά',
  'tr': 'Türkçe',
  'he': 'עברית',
  'la': 'Latina',
  'ro': 'Română',
  'hu': 'Magyar',
  'ca': 'Català',
  'uk': 'Українська',
  'bg': 'Български',
};
