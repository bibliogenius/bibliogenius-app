import 'dart:io';
import 'dart:ui' show Rect;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/collection.dart';
import '../models/collection_book.dart';
import 'ffi_service.dart';

/// Service for exporting and sharing collections as YAML files.
class CollectionExportService {
  /// The collection data comes from the FFI, which is the source the screens
  /// display, so this service needs nothing injected.
  const CollectionExportService();

  /// Export a collection to a shareable YAML format.
  /// Returns the YAML content as a string.
  /// [collectionBooks] is typed rather than a list of maps on purpose. It used
  /// to be `List<dynamic>` and read `book['isbn']`, a key the collection DTO
  /// never carried, so every export came out with an empty `books:` and
  /// nothing complained. A type is what makes that a compile error instead of
  /// a silent one.
  String exportToYaml(
    Collection collection,
    List<CollectionBook> collectionBooks, {
    String? contributorName,
    List<String> contentLanguages = const [],
  }) {
    final buffer = StringBuffer();

    // Header comment
    buffer.writeln('# BiblioGenius Curated List');
    buffer.writeln('# Exported: ${DateTime.now().toIso8601String()}');
    buffer.writeln('');

    // Metadata
    buffer.writeln('id: ${_sanitizeId(collection.name)}');
    buffer.writeln('version: 1');
    buffer.writeln('');

    // Title (single language for user export)
    buffer.writeln('title: "${_escapeYaml(collection.name)}"');

    if (collection.description != null && collection.description!.isNotEmpty) {
      buffer.writeln('description: "${_escapeYaml(collection.description!)}"');
    }
    buffer.writeln('');

    // Contributor
    if (contributorName != null && contributorName.isNotEmpty) {
      buffer.writeln('contributor: "${_escapeYaml(contributorName)}"');
    }

    // Declared languages. Omitted when the caller knows none rather than
    // guessed: a wrong declaration is worse than an absent one, since the
    // language gate of the editorial tier reads it as eligibility. Absent,
    // the list still imports and still browses; it just cannot be suggested.
    if (contentLanguages.isNotEmpty) {
      final quoted = contentLanguages.map((l) => '"${_escapeYaml(l)}"');
      buffer.writeln('content_languages: [${quoted.join(', ')}]');
    }
    buffer.writeln('');

    // Books (ISBN list)
    buffer.writeln('books:');
    for (final book in collectionBooks) {
      final isbn = book.isbn?.trim() ?? '';
      // An entry IS an ISBN in this format, so a book without one cannot
      // travel. Skipped rather than exported half-formed, which would import
      // as a book the receiver could never resolve.
      if (isbn.isEmpty) continue;

      // The note is what the receiver reads when the ISBN resolves to
      // nothing, so it carries title THEN author, never the reverse: a note
      // written the other way round names the book after its author.
      final author = book.author?.trim() ?? '';
      final note = author.isEmpty ? book.title : '${book.title} - $author';
      // Escaped like every other value here. An ISBN is a digit string in
      // theory, but this one comes from imported metadata and travels to a
      // stranger's parser: a stray quote would break the file at their end,
      // not ours.
      buffer.writeln('  - isbn: "${_escapeYaml(isbn)}"');
      buffer.writeln('    note: "${_escapeYaml(note)}"');
    }

    return buffer.toString();
  }

  /// Share a collection via the system share sheet.
  Future<void> shareCollection(
    Collection collection, {
    String? contributorName,
    List<String> contentLanguages = const [],
    String? message,
  }) async {
    // Read through the FFI, the same source the collection screen shows.
    // The HTTP DTO it used to read carries no ISBN at all, so the export
    // silently dropped every entry; what you send must be what you see.
    final books = await FfiService().getCollectionBooks(collection.id);
    final yaml = exportToYaml(
      collection,
      books,
      contributorName: contributorName,
      contentLanguages: contentLanguages,
    );

    await shareYaml(collectionName: collection.name, yaml: yaml, message: message);
  }

  /// Share a YAML that has ALREADY been built.
  ///
  /// Split out for the share panel: it shows the reader what they are about
  /// to send, so the list is formatted before the sheet opens and re-fetching
  /// the whole collection to send the same bytes would be waste the user
  /// would feel as a delay.
  ///
  /// [message] is the accompanying text and comes from the caller, which is
  /// the only side holding a BuildContext and therefore a language. Absent,
  /// nothing is attached: an untranslated sentence is worse than none.
  ///
  /// [sharePositionOrigin] anchors the iOS popover. iOS refuses a zero or
  /// absent origin (`PlatformException(... must be non-zero ...)`), and the
  /// throw used to be swallowed by the caller: the button simply did nothing
  /// on iPhone and iPad while macOS worked.
  Future<void> shareYaml({
    required String collectionName,
    required String yaml,
    String? message,
    Rect? sharePositionOrigin,
  }) async {
    final subject = 'BiblioGenius: $collectionName';

    if (kIsWeb) {
      // On web, just share the text directly
      await Share.share(
        yaml,
        subject: subject,
        sharePositionOrigin: sharePositionOrigin,
      );
      return;
    }

    // On mobile/desktop, create a temp file and share it
    final tempDir = await getTemporaryDirectory();
    final fileName = '${_sanitizeId(collectionName)}.bibliogenius.yml';
    final file = File('${tempDir.path}/$fileName');
    await file.writeAsString(yaml);

    await Share.shareXFiles(
      [XFile(file.path)],
      subject: subject,
      text: message,
      sharePositionOrigin: sharePositionOrigin,
    );
  }

  /// Save a collection to a local file.
  Future<String> saveToFile(
    Collection collection, {
    String? contributorName,
    String? customPath,
  }) async {
    final books = await FfiService().getCollectionBooks(collection.id);
    final yaml = exportToYaml(
      collection,
      books,
      contributorName: contributorName,
    );

    final directory = customPath != null
        ? Directory(customPath)
        : await getApplicationDocumentsDirectory();

    final fileName = '${_sanitizeId(collection.name)}.bibliogenius.yml';
    final file = File('${directory.path}/$fileName');
    await file.writeAsString(yaml);

    return file.path;
  }

  /// Generate a sanitized ID from a collection name.
  String _sanitizeId(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[àáâãäå]'), 'a')
        .replaceAll(RegExp(r'[èéêë]'), 'e')
        .replaceAll(RegExp(r'[ìíîï]'), 'i')
        .replaceAll(RegExp(r'[òóôõö]'), 'o')
        .replaceAll(RegExp(r'[ùúûü]'), 'u')
        .replaceAll(RegExp(r'[ç]'), 'c')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
  }

  /// Escape special characters for YAML strings.
  ///
  /// The carriage return matters as much as the newline, and is easier to
  /// miss because it does not break the file: a double-quoted scalar folds a
  /// raw CR into a space, so "T\ritre" reaches the recipient as "T itre" with
  /// nothing to say it was mangled. Tabs likewise.
  String _escapeYaml(String value) {
    return value
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\r', '\\r')
        .replaceAll('\n', '\\n')
        .replaceAll('\t', '\\t');
  }
}
