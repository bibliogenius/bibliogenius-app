import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../providers/theme_provider.dart';
import '../services/api_service.dart';

class TranslationService {
  static Map<String, Map<String, String>> _dynamicTranslations = {};
  static const String _storageKey = 'cached_translations';

  static Future<void> loadFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? cached = prefs.getString(_storageKey);
      if (cached != null) {
        final Map<String, dynamic> decoded = json.decode(cached);
        _dynamicTranslations = decoded.map(
          (key, value) => MapEntry(key, Map<String, String>.from(value as Map)),
        );
      }
    } catch (e) {
      debugPrint('Error loading cached translations: $e');
    }
  }

  static Future<void> fetchTranslations(BuildContext context) async {
    try {
      final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
      final api = Provider.of<ApiService>(context, listen: false);
      final locale = themeProvider.locale.languageCode;

      final response = await api.getTranslations(locale);
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = response.data;
        final Map<String, String> newTranslations = data.map(
          (k, v) => MapEntry(k, v.toString()),
        );

        _dynamicTranslations[locale] = {
          ...(_dynamicTranslations[locale] ?? {}),
          ...newTranslations,
        };

        // Cache
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_storageKey, json.encode(_dynamicTranslations));
      }
    } catch (e) {
      debugPrint('Error fetching translations: $e');
    }
  }

  // --- PO-based translations (loaded from assets/i18n/*.po) ---

  /// Single source of truth for supported UI languages.
  /// To add a language: add its code here and drop a .po file in assets/i18n/.
  static const List<String> supportedLocales = ['en', 'fr', 'es', 'de'];

  static final Map<String, Map<String, String>> _poTranslations = {};

  static Future<void> loadTranslations() async {
    for (final locale in supportedLocales) {
      try {
        final content = await rootBundle.loadString('assets/i18n/$locale.po');
        _poTranslations[locale] = _parsePo(content);
      } catch (e) {
        _poTranslations[locale] = {};
      }
    }
  }

  // Parses a .po file content into a map of msgid to msgstr.
  static Map<String, String> _parsePo(String content) {
    final result = <String, String>{};
    final lines = content.split('\n');

    String? currentMsgId;
    String currentMsgStr = '';
    bool inMsgId = false;
    bool inMsgStr = false;

    void flush() {
      if (currentMsgId != null && currentMsgId!.isNotEmpty && currentMsgStr.isNotEmpty) {
        result[currentMsgId!] = _unescapePo(currentMsgStr);
      }
      currentMsgId = null;
      currentMsgStr = '';
      inMsgId = false;
      inMsgStr = false;
    }

    for (final line in lines) {
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        flush();
        continue;
      }
      if (trimmed.startsWith('#')) continue;

      if (trimmed.startsWith('msgid ')) {
        flush();
        final value = _extractQuoted(trimmed.substring(6));
        if (value != null) {
          currentMsgId = value;
          inMsgId = true;
          inMsgStr = false;
        }
      } else if (trimmed.startsWith('msgstr ')) {
        final value = _extractQuoted(trimmed.substring(7));
        if (value != null) {
          currentMsgStr = value;
          inMsgId = false;
          inMsgStr = true;
        }
      } else if (trimmed.startsWith('"') && trimmed.endsWith('"')) {
        // Multi-line continuation
        final value = trimmed.substring(1, trimmed.length - 1);
        if (inMsgId) {
          currentMsgId = (currentMsgId ?? '') + value;
        } else if (inMsgStr) {
          currentMsgStr += value;
        }
      }
    }
    flush();

    return result;
  }

  static String? _extractQuoted(String s) {
    final trimmed = s.trim();
    if (trimmed.length >= 2 && trimmed.startsWith('"') && trimmed.endsWith('"')) {
      return trimmed.substring(1, trimmed.length - 1);
    }
    return null;
  }

  static String _unescapePo(String s) {
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (s[i] == '\\' && i + 1 < s.length) {
        final next = s[i + 1];
        switch (next) {
          case 'n':
            buf.write('\n');
            break;
          case 't':
            buf.write('\t');
            break;
          case '"':
            buf.write('"');
            break;
          case '\\':
            buf.write('\\');
            break;
          default:
            buf.write('\\');
            buf.write(next);
        }
        i++;
      } else {
        buf.write(s[i]);
      }
    }
    return buf.toString();
  }

  static String translate(
    BuildContext context,
    String key, {
    Map<String, String>? params,
  }) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final lang = themeProvider.locale.languageCode;

    String text = key;

    // 1. Check dynamic translations for current lang
    if (_dynamicTranslations.containsKey(lang) &&
        _dynamicTranslations[lang]!.containsKey(key)) {
      text = _dynamicTranslations[lang]![key]!;
    }
    // 2. Check PO translations for current lang
    else if (_poTranslations.containsKey(lang) &&
        _poTranslations[lang]!.containsKey(key)) {
      text = _poTranslations[lang]![key]!;
    }
    // 3. Fallback to English dynamic
    else if (_dynamicTranslations.containsKey('en') &&
        _dynamicTranslations['en']!.containsKey(key)) {
      text = _dynamicTranslations['en']![key]!;
    }
    // 4. Fallback to English PO
    else {
      text = _poTranslations['en']?[key] ?? key;
    }

    if (params != null) {
      params.forEach((k, v) {
        text = text.replaceAll('{$k}', v);
      });
    }

    return text;
  }
}
