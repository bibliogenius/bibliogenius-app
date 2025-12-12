import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/book.dart';
import '../models/quote.dart';

/// QuoteService with Wikiquote API integration and 24h caching.
/// 
/// Uses locale-specific Wikiquote endpoints:
/// - fr.wikiquote.org for French
/// - en.wikiquote.org for English
/// - es.wikiquote.org for Spanish
/// - de.wikiquote.org for German
class QuoteService {
  static const String _cacheKeyPrefix = 'quote_cache_';
  static const Duration _cacheExpiry = Duration(hours: 24);

  // Fallback multilingual quotes (always available offline)
  static final Map<String, List<Quote>> _fallbackQuotes = {
    'en': [
      Quote(text: "A room without books is like a body without a soul.", author: "Cicero", source: "Philosophy", locale: 'en'),
      Quote(text: "The person, be it gentleman or lady, who has not pleasure in a good novel, must be intolerably stupid.", author: "Jane Austen", source: "Northanger Abbey", locale: 'en'),
      Quote(text: "Good friends, good books, and a sleepy conscience: this is the ideal life.", author: "Mark Twain", source: "Literature", locale: 'en'),
      Quote(text: "I have always imagined that Paradise will be a kind of library.", author: "Jorge Luis Borges", source: "Poem of the Gifts", locale: 'en'),
      Quote(text: "A book is a dream that you hold in your hand.", author: "Neil Gaiman", source: "Literature", locale: 'en'),
    ],
    'fr': [
      Quote(text: "Une pièce sans livres est comme un corps sans âme.", author: "Cicéron", source: "Philosophie", locale: 'fr'),
      Quote(text: "Lire, c'est boire et manger. L'esprit qui ne lit pas maigrit comme le corps qui ne mange pas.", author: "Victor Hugo", source: "Littérature", locale: 'fr'),
      Quote(text: "Le paradis à mon avis est une bibliothèque.", author: "Jorge Luis Borges", source: "Poème des Dons", locale: 'fr'),
      Quote(text: "Un livre est un jardin que l'on porte dans sa poche.", author: "Proverbe arabe", source: "Sagesse", locale: 'fr'),
      Quote(text: "La lecture est une amitié.", author: "Marcel Proust", source: "Sur la lecture", locale: 'fr'),
    ],
    'es': [
      Quote(text: "Una habitación sin libros es como un cuerpo sin alma.", author: "Cicerón", source: "Filosofía", locale: 'es'),
      Quote(text: "El que lee mucho y anda mucho, ve mucho y sabe mucho.", author: "Miguel de Cervantes", source: "Don Quijote", locale: 'es'),
      Quote(text: "Siempre imaginé que el Paraíso sería algún tipo de biblioteca.", author: "Jorge Luis Borges", source: "Poema de los Dones", locale: 'es'),
      Quote(text: "Un libro abierto es un cerebro que habla.", author: "Proverbio", source: "Sabiduría", locale: 'es'),
    ],
    'de': [
      Quote(text: "Ein Zimmer ohne Bücher ist wie ein Körper ohne Seele.", author: "Cicero", source: "Philosophie", locale: 'de'),
      Quote(text: "Ein Buch ist ein Spiegel, in dem wir nur sehen, was wir bereits in uns haben.", author: "Carlos Ruiz Zafón", source: "Der Schatten des Windes", locale: 'de'),
      Quote(text: "Ich habe mir das Paradies immer als eine Art Bibliothek vorgestellt.", author: "Jorge Luis Borges", source: "Gedicht der Gaben", locale: 'de'),
      Quote(text: "Lesen ist Denken mit fremdem Gehirn.", author: "Jorge Luis Borges", source: "Literatur", locale: 'de'),
    ],
  };

  /// Get a quote for the specified locale with caching.
  /// Falls back to English if locale not supported.
  Future<Quote> getQuoteForLocale(String locale) async {
    final normalizedLocale = _normalizeLocale(locale);
    
    // Try to get from cache first
    final cachedQuote = await _getCachedQuote(normalizedLocale);
    if (cachedQuote != null && !cachedQuote.isExpired) {
      debugPrint('QuoteService: Using cached quote for $normalizedLocale');
      return cachedQuote;
    }

    // Try Wikiquote API
    try {
      final quote = await _fetchFromWikiquote(normalizedLocale);
      if (quote != null) {
        await _cacheQuote(quote, normalizedLocale);
        return quote;
      }
    } catch (e) {
      debugPrint('QuoteService: Wikiquote fetch failed: $e');
    }

    // Fallback to local quotes
    return _getRandomFallback(normalizedLocale);
  }

  /// Legacy method for backward compatibility with dashboard
  Future<Quote> fetchRandomQuote(List<Book> userBooks) async {
    // Get system locale (default to 'en')
    const locale = 'fr'; // TODO: Get from app settings
    return getQuoteForLocale(locale);
  }

  String _normalizeLocale(String locale) {
    final lang = locale.split('_').first.toLowerCase();
    if (_fallbackQuotes.containsKey(lang)) {
      return lang;
    }
    return 'en';
  }

  Future<Quote?> _getCachedQuote(String locale) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '$_cacheKeyPrefix$locale';
      final cachedJson = prefs.getString(cacheKey);
      
      if (cachedJson != null) {
        final data = json.decode(cachedJson) as Map<String, dynamic>;
        return Quote.fromJson(data);
      }
    } catch (e) {
      debugPrint('QuoteService: Cache read error: $e');
    }
    return null;
  }

  Future<void> _cacheQuote(Quote quote, String locale) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '$_cacheKeyPrefix$locale';
      final quoteWithTimestamp = Quote(
        text: quote.text,
        author: quote.author,
        source: quote.source,
        coverUrl: quote.coverUrl,
        locale: locale,
        cachedAt: DateTime.now(),
      );
      await prefs.setString(cacheKey, json.encode(quoteWithTimestamp.toJson()));
      debugPrint('QuoteService: Cached quote for $locale');
    } catch (e) {
      debugPrint('QuoteService: Cache write error: $e');
    }
  }

  Future<Quote?> _fetchFromWikiquote(String locale) async {
    // Wikiquote API endpoint varies by language
    final baseUrl = 'https://$locale.wikiquote.org/w/api.php';
    
    // Step 1: Get a random page from the main namespace
    // Added origin=* for CORS support (required by MediaWiki API for anonymous cross-site requests)
    final randomUrl = Uri.parse('$baseUrl?action=query&format=json&list=random&rnnamespace=0&rnlimit=1&origin=*');
    
    try {
      final headers = {
        'User-Agent': 'BiblioGenius/1.0 (contact@bibliogenius.org)',
      };
      
      final randomResponse = await http.get(randomUrl, headers: headers).timeout(const Duration(milliseconds: 1500));
      if (randomResponse.statusCode != 200) return null;
      
      final randomData = json.decode(randomResponse.body) as Map<String, dynamic>;
      final randomPages = randomData['query']?['random'] as List?;
      if (randomPages == null || randomPages.isEmpty) return null;
      
      final pageTitle = randomPages.first['title'] as String?;
      if (pageTitle == null) return null;
      
      // Step 2: Get the page content (extract first quote)
      final contentUrl = Uri.parse(
        '$baseUrl?action=query&format=json&prop=extracts&exintro=true&explaintext=true&titles=${Uri.encodeComponent(pageTitle)}'
      );
      
      final contentResponse = await http.get(contentUrl, headers: headers).timeout(const Duration(milliseconds: 1500));
      if (contentResponse.statusCode != 200) return null;
      
      final contentData = json.decode(contentResponse.body) as Map<String, dynamic>;
      final pages = contentData['query']?['pages'] as Map<String, dynamic>?;
      if (pages == null || pages.isEmpty) return null;
      
      final pageContent = pages.values.first as Map<String, dynamic>;
      final extract = pageContent['extract'] as String?;
      
      if (extract != null && extract.length > 20 && extract.length < 500) {
        return Quote(
          text: _cleanQuoteText(extract),
          author: pageTitle,
          source: 'Wikiquote',
          locale: locale,
        );
      }
    } catch (e) {
      debugPrint('QuoteService: Wikiquote API error: $e');
    }
    
    return null;
  }

  String _cleanQuoteText(String text) {
    // Clean up wikitext artifacts
    var cleaned = text
        .replaceAll(RegExp(r'\[\[.*?\]\]'), '')
        .replaceAll(RegExp(r'\{\{.*?\}\}'), '')
        .replaceAll(RegExp(r"'''"), '')
        .replaceAll(RegExp(r"''"), '')
        .trim();
    
    // Limit length
    if (cleaned.length > 300) {
      cleaned = '${cleaned.substring(0, 297)}...';
    }
    
    return cleaned;
  }

  Quote _getRandomFallback(String locale) {
    final quotes = _fallbackQuotes[locale] ?? _fallbackQuotes['en']!;
    return quotes[Random().nextInt(quotes.length)];
  }

  /// Clear cached quotes (for testing/debugging)
  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((k) => k.startsWith(_cacheKeyPrefix));
    for (final key in keys) {
      await prefs.remove(key);
    }
    debugPrint('QuoteService: Cache cleared');
  }
}
