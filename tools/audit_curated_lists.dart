#!/usr/bin/env dart

/// Corpus audit for the curated lists (ADR-066 section 8b).
///
/// Offline hygiene is already cheap to check and decent. The failure class
/// that actually costs trust is invisible offline: a checksum-valid ISBN
/// behind which sits the WRONG book, a note whose title and author are
/// reversed, a cover URL that 404s. This resolves every ISBN against the
/// sources and reports what disagrees.
///
/// It exists to make promoting a list a decision rather than a guess: audit
/// the list, read the report, then write `curation_status: reviewed`.
///
/// Usage (from bibliogenius-app/):
///   dart tools/audit_curated_lists.dart                # everything
///   dart tools/audit_curated_lists.dart --list goncourt
///   dart tools/audit_curated_lists.dart --category awards
///   dart tools/audit_curated_lists.dart --offline      # no network at all
///   dart tools/audit_curated_lists.dart --json report.json
///   dart tools/audit_curated_lists.dart --no-cache --delay 500
///
/// Export GOOGLE_BOOKS_API_KEY to raise the Google Books ceiling; without it that
/// source runs on the keyless per-day quota and refuses calls once spent.
///
/// Politeness is not optional here. This walks hundreds of ISBNs across
/// public catalogues that owe us nothing: requests are SEQUENTIAL, spaced by
/// [_defaultDelayMs], carry an identifying User-Agent, and every resolution
/// is cached on disk so a second run costs nothing. Never wire this into a
/// test run or CI; it is a deliberate, human-launched pass.
library;

import 'dart:convert';
import 'dart:io';

import 'package:yaml/yaml.dart';

const String _userAgent =
    'BiblioGenius-CorpusAudit/1.0 (+https://bibliogenius.org)';

/// Milliseconds between two outbound calls. The sources are free and
/// unpaid; this is the rate a human browsing would produce.
const int _defaultDelayMs = 250;

const String _corpusRoot = 'assets/curated_lists';
const String _cachePath = 'tools/.curated_audit_cache.json';

/// Environment variable holding a Google Books API key.
///
/// Keyless, Google allows a per-DAY quota that a single full pass over this
/// corpus can exhaust, and the calls it refuses come back as `unverified`
/// findings that hold a list back from promotion for reasons that say nothing
/// about the list. A key raises the ceiling. It is read from the environment
/// and NEVER written to the report, the cache or the console: the app stores
/// its own copy in `installation_profile.api_keys`, which is the user's to
/// hand over, not this script's to go and read.
const String _googleKeyEnv = 'GOOGLE_BOOKS_API_KEY';

/// The key for this run, or null when none was exported.
final String? _googleBooksKey = () {
  final value = Platform.environment[_googleKeyEnv]?.trim();
  return (value == null || value.isEmpty) ? null : value;
}();

/// Token overlap below which two titles are called different.
const double _titleOverlapFloor = 0.34;

/// Token overlap at or above which two titles are the SAME work, whatever
/// the rest of the entry says. Higher than [_titleOverlapFloor] on purpose:
/// this one exonerates an entry, so it has to be hard to reach.
const double _titleAgreementFloor = 0.6;

/// A note's second half that designates a volume rather than an author.
final RegExp _volumeMarker = RegExp(
  r'^(tome|tom\.|vol\.|volume|t\.|livre|partie|#)\s*\d+',
  caseSensitive: false,
);

/// A second half that is a volume designation and NOTHING else, so the entry
/// names no author at all.
///
/// The distinction is load-bearing. "Tome 1 - Hajime Isayama" carries a real
/// author claim after the volume and a source that answers Naoko Takeuchi
/// contradicts it; "Tome 52" claims nothing, and holding it against Masashi
/// Kishimoto accuses a correct entry of being a wrong book.
final RegExp _volumeOnly = RegExp(
  r'^(tome|tom\.|vol\.|volume|t\.|livre|partie|#)\s*\d+$',
  caseSensitive: false,
);

void main(List<String> args) async {
  if (args.contains('--self-test')) {
    exit(_selfTest() ? 0 : 1);
  }
  final options = _Options.parse(args);
  if (options.help) {
    _printUsage();
    exit(0);
  }

  final index = _readIndex();
  final lists = _readLists(index, options);
  if (lists.isEmpty) {
    stderr.writeln('No list matched. Try --list <id> or --category <id>.');
    exit(2);
  }

  final cache = _Cache(File(_cachePath), enabled: options.useCache);
  await cache.load();

  final client = HttpClient()..userAgent = _userAgent;
  final report = _Report();

  stdout.writeln(
    'Auditing ${lists.length} list(s), '
    '${lists.fold<int>(0, (n, l) => n + l.books.length)} entries'
    '${options.offline ? ' (offline: no network)' : ''}.',
  );
  if (!options.offline) {
    stdout.writeln(
      _googleBooksKey == null
          ? 'Google Books: no $_googleKeyEnv exported, keyless per-day quota.'
          : 'Google Books: using the key in $_googleKeyEnv.',
    );
  }
  stdout.writeln();

  for (final list in lists) {
    final findings = <_Finding>[];
    _auditOffline(list, findings);
    if (!options.offline) {
      await _auditOnline(client, cache, list, findings, options, report);
    }
    report.add(list, findings);
    _printList(list, findings);
  }

  client.close(force: true);
  await cache.save();

  _printSummary(report);
  if (options.jsonPath != null) {
    File(options.jsonPath!).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(report.toJson()),
    );
    stdout.writeln('\nJSON report written to ${options.jsonPath}');
  }

  // Non-zero when a REACHABLE list carries a blocking finding, so this can
  // gate a promotion. A withdrawn list being broken is expected, not news.
  exit(report.blockingOnReachable > 0 ? 1 : 0);
}

// ── Findings ────────────────────────────────────────────────────────────

/// `blocking` means "do not promote this list": the entry resolves to
/// nothing, or to a book by a different author. `warn` means "look at it",
/// typically a title that differs because the record is a translation.
enum _Severity { blocking, warn, info }

class _Finding {
  _Finding(this.severity, this.code, this.where, this.detail);

  final _Severity severity;
  final String code;
  final String where;
  final String detail;

  Map<String, dynamic> toJson() => {
    'severity': severity.name,
    'code': code,
    'where': where,
    'detail': detail,
  };
}

// ── Offline checks ──────────────────────────────────────────────────────

void _auditOffline(_List list, List<_Finding> findings) {
  final seen = <String, int>{};
  for (var i = 0; i < list.books.length; i++) {
    final book = list.books[i];
    final where = '${list.id}[$i] ${book.isbn}';

    for (final raw in book.allIsbns) {
      final canonical = _toIsbn13(raw);
      if (canonical == null) {
        findings.add(
          _Finding(
            _Severity.blocking,
            'isbn_invalid',
            where,
            '"$raw" fails ISBN-10/13 format or checksum',
          ),
        );
      }
    }

    final canonical = _toIsbn13(book.isbn);
    if (canonical != null) {
      final first = seen[canonical];
      if (first != null) {
        findings.add(
          _Finding(
            _Severity.warn,
            'isbn_duplicate_in_list',
            where,
            'same ISBN as entry $first of this list',
          ),
        );
      }
      seen[canonical] = i;
    }

    if (book.identityTitle == null) {
      findings.add(
        _Finding(
          _Severity.info,
          'no_local_title',
          where,
          'no title/authors and no "Title - Author" note: nothing to '
              'cross-check the resolved record against',
        ),
      );
    }

    final cover = book.coverUrl;
    if (cover != null && !cover.startsWith('https://')) {
      findings.add(
        _Finding(_Severity.blocking, 'cover_not_https', where, cover),
      );
    }
  }

  final listCover = list.coverUrl;
  if (listCover != null && !listCover.startsWith('https://')) {
    findings.add(
      _Finding(_Severity.blocking, 'cover_not_https', list.id, listCover),
    );
  }
  if (list.contentLanguages.isEmpty) {
    findings.add(
      _Finding(
        _Severity.warn,
        'no_content_languages',
        list.id,
        'the affinity tier can never suggest a list with no declared '
            'languages (the language gate is eligibility, not a booster)',
      ),
    );
  }
}

// ── Online checks ───────────────────────────────────────────────────────

Future<void> _auditOnline(
  HttpClient client,
  _Cache cache,
  _List list,
  List<_Finding> findings,
  _Options options,
  _Report report,
) async {
  for (var i = 0; i < list.books.length; i++) {
    final book = list.books[i];
    final where = '${list.id}[$i] ${book.isbn}';
    final canonical = _toIsbn13(book.isbn);
    if (canonical == null) continue; // already reported offline

    final unverifiedBefore = report.unverified;
    final resolved = await _resolve(client, cache, canonical, options, report);
    if (resolved == null) {
      final unverified = report.unverified > unverifiedBefore;
      findings.add(
        unverified
            ? _Finding(
                _Severity.warn,
                'unverified',
                where,
                'a source was rate-limited or down, so this ISBN could not '
                    'be checked (${book.identityTitle ?? book.note ?? "?"}); '
                    're-run later',
              )
            : _Finding(
                _Severity.blocking,
                'unresolved',
                where,
                'no source knows this ISBN '
                    '(${book.identityTitle ?? book.note ?? "?"})',
              ),
      );
      continue;
    }

    _compareIdentity(book, resolved, where, findings, list.contentLanguages);

    final cover = book.coverUrl;
    if (cover != null && cover.startsWith('https://')) {
      final alive = await _isAlive(client, cover, options, report);
      if (!alive) {
        findings.add(_Finding(_Severity.blocking, 'cover_dead', where, cover));
      }
    } else {
      // The entry brings no artwork of its own, so the card will show
      // whatever the sources can find for this ISBN. When they find nothing,
      // the reader gets a grey rectangle for a book that is otherwise right.
      resolved.hasCover ??= await _hasCover(client, canonical, options, report);
      cache.put(canonical, resolved);
      if (resolved.hasCover == false) {
        findings.add(
          _Finding(
            _Severity.warn,
            'no_cover',
            where,
            'the entry carries no cover_url and neither Open Library nor '
                'Inventaire illustrates this ISBN ("${resolved.title}"); '
                'another edition of the same work would give the card a cover',
          ),
        );
      }
    }
  }

  final listCover = list.coverUrl;
  if (listCover != null && listCover.startsWith('https://')) {
    if (!await _isAlive(client, listCover, options, report)) {
      findings.add(
        _Finding(_Severity.blocking, 'cover_dead', list.id, listCover),
      );
    }
  }
}

/// Compare what the corpus claims against what the source returns.
///
/// The author is the load-bearing signal. A wrong book behind an ISBN
/// almost always carries a different author, while a title legitimately
/// differs whenever a French entry resolves to an English record, which is
/// the common case on this corpus. Treating a title difference as blocking
/// would drown the real findings in translations.
void _compareIdentity(
  _Book book,
  _Resolved resolved,
  String where,
  List<_Finding> findings,
  List<String> listLanguages,
) {
  final localTitle = _norm(book.identityTitle ?? '');
  final localAuthors = book.identityAuthors
      .map(_norm)
      .where((a) => a.isNotEmpty);
  if (localTitle.isEmpty && localAuthors.isEmpty) return;

  final remoteTitle = _norm(resolved.title);
  final remoteAuthors = resolved.authors.map(_norm).where((a) => a.isNotEmpty);

  // The note was written the wrong way round, so its "title" half is really
  // the author.
  //
  // Titles that CONTAIN their author's name are exempt ("Moi, Malala -
  // Malala Yousafzai", "Le Journal d'Anne Frank - Anne Frank"): both halves
  // then overlap the record on both sides, and a correct note reads as
  // reversed. There is no signal left to tell the orders apart, so the
  // honest answer is to say nothing rather than accuse a good entry.
  final authorInsideTitle = remoteAuthors.any(
    (a) => _overlap(a, remoteTitle) >= _titleOverlapFloor,
  );
  if (localAuthors.isNotEmpty &&
      remoteAuthors.isNotEmpty &&
      !authorInsideTitle) {
    final reversedTitle = localAuthors.any(
      (a) => _overlap(a, remoteTitle) >= _titleOverlapFloor,
    );
    final reversedAuthor = remoteAuthors.any(
      (a) => _overlap(localTitle, a) >= _titleOverlapFloor,
    );
    if (reversedTitle && reversedAuthor) {
      findings.add(
        _Finding(
          _Severity.blocking,
          'note_reversed',
          where,
          'note reads "title - author" backwards: source says '
              '"${resolved.title}" by ${resolved.authors.join(", ")}',
        ),
      );
      return;
    }
  }

  // Some notes read "Series - Tome 3", where the half after the dash is a
  // volume number and not an author. Comparing it to the real author fails
  // while the ISBN is perfectly correct, so those entries are exonerated.
  //
  // The exemption requires the second half to BE a volume marker, and a
  // strong title agreement is not enough on its own. A study guide about a
  // novel carries the novel's title and a different author, so title-only
  // exoneration let "The Lord of the Rings - J.R.R. Tolkien" pass while its
  // ISBN pointed at a commentary by someone else: a wrong book wearing the
  // label of a formatting nit.
  final secondHalfIsVolume = book.identityAuthors.any(
    (a) => _volumeMarker.hasMatch(a.trim()),
  );

  // When the second half is a volume and nothing else, the entry makes NO
  // author claim, so there is nothing for the source's author to
  // contradict and the comparison below must not run at all.
  //
  // What sent this class blocking was not a wrong ISBN but a cataloguing
  // habit: a national library files a series volume under the volume's own
  // title, so `Naruto - Tome 52` resolves to "Realites multiples" by
  // Masashi Kishimoto, the title agreement that would have exonerated it
  // fails, and a correct entry is reported as a wrong book. Eight of them
  // were, on one list, on 2026-08-23.
  //
  // The entry is still worth a warning rather than silence: its second half
  // is not an author, so it yields a garbage "title|author" identity key
  // and the affinity membrane can only ever match it by ISBN.
  final claimsNoAuthor =
      book.identityAuthors.isNotEmpty &&
      book.identityAuthors.every((a) => _volumeOnly.hasMatch(a.trim()));
  if (claimsNoAuthor) {
    findings.add(
      _Finding(
        _Severity.warn,
        'note_not_title_author',
        where,
        'the note names no author, only "${book.identityAuthors.join(", ")}"; '
            'the source has "${resolved.title}"'
            '${resolved.authors.isEmpty ? '' : ' by ${resolved.authors.join(", ")}'}, '
            'which nothing in the entry can confirm or deny',
      ),
    );
    return;
  }
  final titleAgrees =
      secondHalfIsVolume &&
      localTitle.isNotEmpty &&
      remoteTitle.isNotEmpty &&
      _overlap(localTitle, remoteTitle) >= _titleAgreementFloor;

  if (localAuthors.isNotEmpty && remoteAuthors.isNotEmpty) {
    final matches = localAuthors.any(
      (local) => remoteAuthors.any(
        (remote) =>
            _sortWords(local) == _sortWords(remote) ||
            _overlap(local, remote) >= 0.5,
      ),
    );
    if (!matches) {
      findings.add(
        titleAgrees
            ? _Finding(
                _Severity.warn,
                'note_not_title_author',
                where,
                'the ISBN is right ("${resolved.title}"), but the note\'s '
                    'second half is "${book.identityAuthors.join(", ")}", '
                    'not the author ${resolved.authors.join(", ")}',
              )
            : _Finding(
                _Severity.blocking,
                'author_mismatch',
                where,
                'corpus says ${book.identityAuthors.join(", ")}, source says '
                    '${resolved.authors.join(", ")} for "${resolved.title}"',
              ),
      );
      return;
    }
  }

  if (localTitle.isNotEmpty && remoteTitle.isNotEmpty) {
    if (_overlap(localTitle, remoteTitle) < _titleOverlapFloor) {
      findings.add(_titleFinding(book, resolved, where, listLanguages));
    }
  }
}

/// A title the source does not recognise, sorted into the three things it
/// can mean.
///
/// The class used to be one warning, and that is what let four wrong books
/// through in a single day: a French entry against an English record
/// legitimately differs, so calling every difference blocking would bury the
/// real findings, and calling none of them blocking buries the real findings
/// the other way. The record itself says which case it is.
///
/// A VOLUME catalogued under its own title (461 links it to the set our
/// entry names) and a TRANSLATION (101 is not one of the list's languages)
/// are both normal and stay warnings. What is left is a record in the SAME
/// language, in no series of ours, sharing no word with our title: that is a
/// different book, and it is exactly the shape of "Pour qui sonne le glas"
/// resolving to "Le Soleil se leve aussi".
///
/// Only the UNIMARC sources report 101 and 461. Without them the old warning
/// stands, because an absent field is not evidence.
_Finding _titleFinding(
  _Book book,
  _Resolved resolved,
  String where,
  List<String> listLanguages,
) {
  final series = resolved.seriesTitle;
  final volumeOfOurSeries =
      series != null &&
      series.trim().isNotEmpty &&
      _overlap(_norm(book.identityTitle ?? ''), _norm(series)) >=
          _titleOverlapFloor;

  final language = resolved.language?.trim().toLowerCase();
  final sameLanguage =
      language != null &&
      language.isNotEmpty &&
      listLanguages.any((l) => _sameLanguage(l, language));

  if (!volumeOfOurSeries && sameLanguage) {
    return _Finding(
      _Severity.blocking,
      'different_work',
      where,
      'corpus says "${book.identityTitle}", source says "${resolved.title}" '
          'in the same language, in no series of ours: this is another book '
          'by the same author, not a translation',
    );
  }

  return _Finding(
    _Severity.warn,
    'title_differs',
    where,
    'corpus says "${book.identityTitle}", source says "${resolved.title}"'
        '${volumeOfOurSeries ? ' (a volume of "$series", catalogued under its own title)' : ' (often a translation, check it is the same work)'}',
  );
}

/// UNIMARC writes a language as a three-letter code ("fre"), a list writes it
/// as two ("fr"). Compared on the prefix, which is all these two vocabularies
/// share.
bool _sameLanguage(String listCode, String recordCode) {
  final a = listCode.trim().toLowerCase();
  final b = recordCode.trim().toLowerCase();
  if (a.isEmpty || b.isEmpty) return false;
  const equivalents = {
    'fr': ['fre', 'fra'],
    'en': ['eng'],
    'es': ['spa', 'esp'],
    'de': ['ger', 'deu'],
    'it': ['ita'],
    'pt': ['por'],
  };
  if (a == b) return true;
  return (equivalents[a] ?? const []).contains(b);
}

// ── Sources ─────────────────────────────────────────────────────────────

class _Resolved {
  _Resolved(
    this.title,
    this.authors,
    this.source, {
    this.hasCover,
    this.language,
    this.seriesTitle,
  });

  final String title;
  final List<String> authors;
  final String source;

  /// UNIMARC 101$a, the language of the RECORD. Null from a source that does
  /// not report one, which is every non-UNIMARC source.
  final String? language;

  /// UNIMARC 461$t, the set this record is a volume of. Null when it is not
  /// part of one, or when the source does not say.
  final String? seriesTitle;

  /// Whether a cover was found for this ISBN, or null when nobody asked yet.
  ///
  /// Cached like the rest, so the probe is paid once. Null rather than false
  /// on an entry cached before this check existed: "not asked" and "asked and
  /// there is none" are different answers, and only one of them is a finding.
  bool? hasCover;

  Map<String, dynamic> toJson() => {
    'title': title,
    'authors': authors,
    'source': source,
    if (hasCover != null) 'hasCover': hasCover,
    if (language != null) 'language': language,
    if (seriesTitle != null) 'seriesTitle': seriesTitle,
  };

  static _Resolved? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    return _Resolved(
      json['title'] as String? ?? '',
      (json['authors'] as List? ?? const []).map((a) => '$a').toList(),
      json['source'] as String? ?? '?',
      hasCover: json['hasCover'] as bool?,
      language: json['language'] as String?,
      seriesTitle: json['seriesTitle'] as String?,
    );
  }
}

/// Three sources, tried sequentially with early exit, never in parallel.
///
/// Order follows the ISBN's registration agency: `978-2` is French and goes
/// to the BnF first, everything else starts with Open Library. The corpus is
/// mostly French, and the anglophone sources do not cover it. Each falls
/// through to the others, since a French publisher can register an English
/// book and a French edition can be catalogued abroad.
Future<_Resolved?> _resolve(
  HttpClient client,
  _Cache cache,
  String isbn,
  _Options options,
  _Report report,
) async {
  if (cache.has(isbn)) return cache.get(isbn);

  // Google Books is LAST for a French ISBN, and that placement is the whole
  // point of having a fourth source. Its keyless quota is per day and a full
  // pass over 815 entries exhausts it, so leaning on it for the French half
  // of the corpus buys a report that says "could not check" 40 times and
  // tells the curator to come back tomorrow. The SUDOC costs nothing, has no
  // key and no quota, and answers for a third of the ISBNs the BnF and Open
  // Library both miss.
  final french = isbn.startsWith('9782');
  final List<_Source> order = french
      ? [_bnf, _sudoc, _openLibrary, _googleBooks]
      : [_openLibrary, _googleBooks, _bnf, _sudoc];

  final before = report.rateLimited + report.transportErrors;
  _Resolved? resolved;
  for (final source in order) {
    resolved = await source(client, isbn, options, report);
    if (resolved != null) break;
  }

  // "Nobody knows this ISBN" is only sayable when every source answered. If
  // one was rate-limited or down, the absence proves nothing, so it is
  // neither reported nor cached.
  final disturbed = (report.rateLimited + report.transportErrors) > before;
  if (resolved == null && disturbed) {
    report.unverified++;
    return null;
  }

  cache.put(isbn, resolved);
  return resolved;
}

typedef _Source =
    Future<_Resolved?> Function(HttpClient, String, _Options, _Report);

/// The French national bibliography, over SRU/UNIMARC. Read with regexes
/// rather than an XML parser: only 200$a (title), 700$b/$a (authors) and
/// 200$f (fallback) are needed.
///
/// Both ISBN forms are tried. The BnF indexes an older edition under the
/// ISBN-10 that was PRINTED on it and does not answer for the ISBN-13 that
/// designates the same book: `2070501698` returns Les Raisins de la colere
/// where `9782070501694` returns nothing at all. A 13-only lookup therefore
/// reports correct French entries as "no source knows this ISBN", which is
/// the one verdict that sends a curator hunting for a replacement that does
/// not need replacing.
Future<_Resolved?> _bnf(
  HttpClient client,
  String isbn,
  _Options options,
  _Report report,
) async {
  for (final form in _isbnForms(isbn)) {
    final resolved = await _bnfOneForm(client, form, options, report);
    if (resolved != null) return resolved;
  }
  return null;
}

/// The ISBN-13 first, then its ISBN-10 form when there is one. Never more
/// than two, and the second is only paid for when the first found nothing.
List<String> _isbnForms(String isbn13) {
  final ten = _toIsbn10(isbn13);
  return ten == null ? [isbn13] : [isbn13, ten];
}

/// The ISBN-10 of a 978-prefixed ISBN-13, check digit RECOMPUTED.
///
/// Never carry the 13's check digit onto the 10: the two use different
/// algorithms and the copy produces a checksum-valid ISBN for another book.
String? _toIsbn10(String isbn13) {
  if (isbn13.length != 13 || !isbn13.startsWith('978')) return null;
  final core = isbn13.substring(3, 12);
  if (!RegExp(r'^[0-9]{9}$').hasMatch(core)) return null;
  var sum = 0;
  for (var i = 0; i < 9; i++) {
    sum += int.parse(core[i]) * (10 - i);
  }
  final check = (11 - (sum % 11)) % 11;
  return '$core${check == 10 ? 'X' : check}';
}

Future<_Resolved?> _bnfOneForm(
  HttpClient client,
  String isbn,
  _Options options,
  _Report report,
) async {
  final uri = Uri.parse(
    'https://catalogue.bnf.fr/api/SRU?version=1.2&operation=searchRetrieve'
    '&query=bib.isbn%20adj%20%22$isbn%22&recordSchema=unimarcxchange',
  );
  final xml = await _getText(client, uri, options, report);
  if (xml == null) return null;
  if (xml.contains('<srw:numberOfRecords>0</srw:numberOfRecords>')) return null;

  final title = _unimarcSubfields(xml, '200')['a'];
  if (title == null || title.trim().isEmpty) return null;

  final authors = <String>[];
  for (final tag in const ['700', '701', '702']) {
    for (final field in _unimarcFields(xml, tag)) {
      final subfields = _subfieldsOf(field);
      final surname = subfields['a'];
      final given = subfields['b'];
      if (surname == null || surname.trim().isEmpty) continue;
      authors.add(
        given == null || given.trim().isEmpty ? surname : '$given $surname',
      );
    }
  }
  if (authors.isEmpty) {
    final responsibility = _unimarcSubfields(xml, '200')['f'];
    if (responsibility != null && responsibility.trim().isNotEmpty) {
      authors.add(responsibility);
    }
  }
  return _Resolved(title, authors, 'bnf');
}

Iterable<String> _unimarcFields(String xml, String tag) sync* {
  final pattern = RegExp(
    'datafield tag="$tag"[^>]*>(.*?)</[a-z]*:?datafield>',
    dotAll: true,
  );
  for (final match in pattern.allMatches(xml)) {
    yield match.group(1) ?? '';
  }
}

Map<String, String> _subfieldsOf(String field) {
  final subfields = <String, String>{};
  for (final match in RegExp(
    'code="([a-z0-9])"[^>]*>([^<]*)<',
  ).allMatches(field)) {
    subfields.putIfAbsent(match.group(1)!, () => match.group(2)!);
  }
  return subfields;
}

Map<String, String> _unimarcSubfields(String xml, String tag) {
  final first = _unimarcFields(
    xml,
    tag,
  ).firstWhere((f) => true, orElse: () => '');
  return _subfieldsOf(first);
}

/// The French academic union catalogue, over its two little services:
/// `isbn2ppn` maps an ISBN to a record id, then `<ppn>.xml` returns UNIMARC
/// with the same shape the BnF serves, so the same subfields are read.
///
/// Both ISBN forms are tried for the same reason they are at the BnF: an
/// older edition is indexed under the ISBN-10 that was printed on it.
Future<_Resolved?> _sudoc(
  HttpClient client,
  String isbn,
  _Options options,
  _Report report,
) async {
  for (final form in _isbnForms(isbn)) {
    final lookup = await _getText(
      client,
      Uri.parse('https://www.sudoc.fr/services/isbn2ppn/$form'),
      options,
      report,
    );
    if (lookup == null) continue;
    final ppn = RegExp(r'<ppn[^>]*>([0-9Xx]+)</ppn>').firstMatch(lookup);
    if (ppn == null) continue;

    final xml = await _getText(
      client,
      Uri.parse('https://www.sudoc.fr/${ppn.group(1)}.xml'),
      options,
      report,
    );
    if (xml == null) continue;

    final title = _unimarcSubfields(xml, '200')['a'];
    if (title == null || title.trim().isEmpty) continue;

    final authors = <String>[];
    for (final tag in const ['700', '701', '702']) {
      for (final field in _unimarcFields(xml, tag)) {
        final subfields = _subfieldsOf(field);
        final surname = subfields['a'];
        final given = subfields['b'];
        if (surname == null || surname.trim().isEmpty) continue;
        authors.add(
          given == null || given.trim().isEmpty ? surname : '$given $surname',
        );
      }
    }
    if (authors.isEmpty) {
      final responsibility = _unimarcSubfields(xml, '200')['f'];
      if (responsibility != null && responsibility.trim().isNotEmpty) {
        authors.add(responsibility);
      }
    }
    return _Resolved(
      title,
      authors,
      'sudoc',
      language: _unimarcSubfields(xml, '101')['a'],
      seriesTitle: _unimarcSubfields(xml, '461')['t'],
    );
  }
  return null;
}

/// Whether ANY source can put a cover on this book.
///
/// An entry can resolve to exactly the right book and still render as a grey
/// rectangle, and a curated list is judged on the card it produces. For a
/// curated list the exact edition is not the point: the reader wants the
/// work, so an ISBN nobody illustrates should be swapped for one of the same
/// work that somebody does.
///
/// Deliberately a WARNING and never blocking: a missing cover is a poor card,
/// not a wrong book. Deliberately incomplete too, and the finding says so:
/// this asks Open Library and Inventaire, while the app also tries the BnF
/// and Google Books, so a flagged entry is a candidate for re-editioning
/// rather than a proven blank.
Future<bool> _hasCover(
  HttpClient client,
  String isbn,
  _Options options,
  _Report report,
) async {
  // The BnF first for a French ISBN, because it is what the app asks first
  // and because it answers where the others do not: 4 of 6 entries this
  // check had flagged as coverless are illustrated there. Asking only the
  // anglophone sources measures the sources, not the corpus, exactly as the
  // resolution order had to learn.
  if (isbn.startsWith('9782') || isbn.startsWith('9791')) {
    for (final form in _isbnForms(isbn)) {
      final xml = await _getText(
        client,
        Uri.parse(
          'https://catalogue.bnf.fr/api/SRU?version=1.2'
          '&operation=searchRetrieve&query=bib.isbn%20adj%20%22$form%22'
          '&recordSchema=unimarcxchange',
        ),
        options,
        report,
      );
      final ark = xml == null
          ? null
          : RegExp(r'(ark:/12148/[a-z0-9]+)').firstMatch(xml);
      if (ark == null) continue;
      // Its cover endpoint answers 500 often enough that bnf.rs validates
      // the URL before keeping it; a 500 here means no cover, not an outage.
      final alive = await _isAlive(
        client,
        'https://catalogue.bnf.fr/couverture?&appName=NE'
        '&idArk=${ark.group(1)}&couverture=1',
        options,
        report,
      );
      if (alive) return true;
      break;
    }
  }

  final ol = await _getJson(
    client,
    Uri.parse(
      'https://openlibrary.org/api/books'
      '?bibkeys=ISBN:$isbn&format=json&jscmd=data',
    ),
    options,
    report,
  );
  if (ol is Map) {
    final entry = ol['ISBN:$isbn'];
    if (entry is Map && entry['cover'] is Map) return true;
  }

  final inv = await _getJson(
    client,
    Uri.parse(
      'https://inventaire.io/api/entities?action=by-uris&uris=isbn:$isbn',
    ),
    options,
    report,
  );
  if (inv is Map) {
    final entities = inv['entities'];
    if (entities is Map) {
      for (final value in entities.values.whereType<Map>()) {
        final claims = value['claims'];
        if (claims is Map && claims['invp:P2'] != null) return true;
        if (value['image'] != null) return true;
      }
    }
  }
  return false;
}

Future<_Resolved?> _openLibrary(
  HttpClient client,
  String isbn,
  _Options options,
  _Report report,
) async {
  final uri = Uri.parse(
    'https://openlibrary.org/api/books'
    '?bibkeys=ISBN:$isbn&format=json&jscmd=data',
  );
  final body = await _getJson(client, uri, options, report);
  if (body is! Map) return null;
  final entry = body['ISBN:$isbn'];
  if (entry is! Map) return null;
  final title = entry['title'];
  if (title is! String || title.trim().isEmpty) return null;
  final authors = (entry['authors'] as List? ?? const [])
      .whereType<Map>()
      .map((a) => '${a['name'] ?? ''}')
      .where((a) => a.trim().isNotEmpty)
      .toList();
  return _Resolved(title, authors, 'openlibrary');
}

Future<_Resolved?> _googleBooks(
  HttpClient client,
  String isbn,
  _Options options,
  _Report report,
) async {
  final key = _googleBooksKey;
  final uri = Uri.parse(
    'https://www.googleapis.com/books/v1/volumes?q=isbn:$isbn'
    '${key == null ? '' : '&key=$key'}',
  );
  final body = await _getJson(client, uri, options, report);
  if (body is! Map) return null;
  final items = body['items'];
  if (items is! List || items.isEmpty) return null;
  final info = (items.first as Map)['volumeInfo'];
  if (info is! Map) return null;
  final title = info['title'];
  if (title is! String || title.trim().isEmpty) return null;
  final authors = (info['authors'] as List? ?? const [])
      .map((a) => '$a')
      .where((a) => a.trim().isNotEmpty)
      .toList();
  return _Resolved(title, authors, 'googlebooks');
}

Future<dynamic> _getJson(
  HttpClient client,
  Uri uri,
  _Options options,
  _Report report,
) async {
  final body = await _getText(client, uri, options, report);
  if (body == null) return null;
  try {
    return jsonDecode(body);
  } catch (_) {
    return null;
  }
}

Future<String?> _getText(
  HttpClient client,
  Uri uri,
  _Options options,
  _Report report,
) async {
  await _throttle(options);
  report.calls++;
  try {
    final request = await client.getUrl(uri);
    request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
    final response = await request.close();
    if (response.statusCode != 200) {
      await response.drain<void>();
      // A 4xx is an answer ("nothing found"), not an outage. A 429 is
      // neither: it is back-pressure, and a negative cached from one would
      // be a permanent lie.
      if (response.statusCode == 429) report.rateLimited++;
      if (response.statusCode >= 500) report.transportErrors++;
      return null;
    }
    return await response.transform(utf8.decoder).join();
  } catch (e) {
    report.transportErrors++;
    return null;
  }
}

Future<bool> _isAlive(
  HttpClient client,
  String url,
  _Options options,
  _Report report,
) async {
  await _throttle(options);
  report.calls++;
  try {
    final request = await client.headUrl(Uri.parse(url));
    request.headers.set(HttpHeaders.userAgentHeader, _userAgent);
    final response = await request.close();
    await response.drain<void>();
    return response.statusCode >= 200 && response.statusCode < 400;
  } catch (e) {
    report.transportErrors++;
    // Unreachable is not the same as dead; do not accuse a URL because the
    // machine running the audit lost its network.
    return true;
  }
}

DateTime? _lastCall;

Future<void> _throttle(_Options options) async {
  final last = _lastCall;
  final now = DateTime.now();
  if (last != null) {
    final elapsed = now.difference(last).inMilliseconds;
    if (elapsed < options.delayMs) {
      await Future<void>.delayed(
        Duration(milliseconds: options.delayMs - elapsed),
      );
    }
  }
  _lastCall = DateTime.now();
}

// ── Resolution cache ────────────────────────────────────────────────────

/// On-disk memo of every resolution, so a second pass costs the sources
/// nothing. Negative answers are cached too, since an ISBN nobody knows is
/// a stable fact.
class _Cache {
  _Cache(this._file, {required this.enabled});

  final File _file;
  final bool enabled;
  final Map<String, _Resolved?> _entries = {};
  bool _dirty = false;

  Future<void> load() async {
    if (!enabled || !_file.existsSync()) return;
    try {
      final json = jsonDecode(_file.readAsStringSync()) as Map<String, dynamic>;
      json.forEach((isbn, value) {
        _entries[isbn] = _Resolved.fromJson(value as Map<String, dynamic>?);
      });
      stdout.writeln('Cache: ${_entries.length} known ISBNs.');
    } catch (_) {
      // A corrupt cache is not worth a failure: start over.
    }
  }

  bool has(String isbn) => enabled && _entries.containsKey(isbn);
  _Resolved? get(String isbn) => _entries[isbn];

  void put(String isbn, _Resolved? resolved) {
    if (!enabled) return;
    _entries[isbn] = resolved;
    _dirty = true;
  }

  Future<void> save() async {
    if (!enabled || !_dirty) return;
    _file.writeAsStringSync(
      jsonEncode(_entries.map((k, v) => MapEntry(k, v?.toJson()))),
    );
  }
}

// ── Corpus reading ──────────────────────────────────────────────────────

class _Book {
  _Book({
    required this.isbn,
    this.note,
    this.title,
    this.authors = const [],
    this.altEditions = const {},
    this.coverUrl,
  });

  final String isbn;
  final String? note;
  final String? title;
  final List<String> authors;
  final Map<String, String> altEditions;
  final String? coverUrl;

  List<String> get allIsbns =>
      [isbn, ...altEditions.values].where((v) => v.trim().isNotEmpty).toList();

  /// Mirrors `CuratedBook.identityTitle`: the explicit title, else the
  /// "Title - Author" note form, else nothing rather than a wrong title.
  String? get identityTitle {
    final explicit = title?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final raw = note;
    if (raw == null) return null;
    final dash = raw.indexOf(' - ');
    if (dash <= 0) return null;
    return raw.substring(0, dash).trim();
  }

  List<String> get identityAuthors {
    if (authors.isNotEmpty) return authors;
    final raw = note;
    if (raw == null) return const [];
    final dash = raw.indexOf(' - ');
    if (dash <= 0) return const [];
    final tail = raw
        .substring(dash + 3)
        .replaceAll(RegExp(r'\(\s*\d{3,4}\s*\)'), '')
        .trim();
    return tail.isEmpty ? const [] : [tail];
  }
}

class _List {
  _List({
    required this.id,
    required this.path,
    required this.reachable,
    required this.curationStatus,
    required this.contentLanguages,
    required this.books,
    this.coverUrl,
  });

  final String id;
  final String path;

  /// Whether `index.yml` still points at this list. Nine files sit on disk
  /// while withdrawn for failed audits; a finding on one of those is
  /// expected and must not gate anything.
  final bool reachable;
  final String curationStatus;
  final List<String> contentLanguages;
  final List<_Book> books;
  final String? coverUrl;
}

/// list id to its category directory, read from `index.yml`.
Map<String, String> _readIndex() {
  final file = File('$_corpusRoot/index.yml');
  if (!file.existsSync()) {
    stderr.writeln('ERROR: run this from bibliogenius-app/ (no $_corpusRoot).');
    exit(2);
  }
  final parsed = loadYaml(file.readAsStringSync()) as YamlMap;
  final index = <String, String>{};
  for (final category in (parsed['categories'] as YamlList)) {
    final id = '${(category as YamlMap)['id']}';
    for (final listId in (category['lists'] as YamlList)) {
      index['$listId'] = id;
    }
  }
  return index;
}

List<_List> _readLists(Map<String, String> index, _Options options) {
  final lists = <_List>[];
  for (final entity in Directory(_corpusRoot).listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.yml')) continue;
    if (entity.path.endsWith('index.yml')) continue;

    final YamlMap parsed;
    try {
      parsed = loadYaml(entity.readAsStringSync()) as YamlMap;
    } catch (e) {
      stderr.writeln('SKIP ${entity.path}: unparseable YAML ($e)');
      continue;
    }
    final id = '${parsed['id'] ?? ''}';
    if (id.isEmpty) continue;

    final category = index[id];
    if (options.listId != null && options.listId != id) continue;
    if (options.category != null && options.category != category) continue;
    // Withdrawn lists are audited only when explicitly asked for: they are
    // known-broken by construction, and auditing them by default would
    // spend the sources' patience on entries nobody can see.
    if (category == null &&
        options.listId == null &&
        !options.includeWithdrawn) {
      continue;
    }

    lists.add(
      _List(
        id: id,
        path: entity.path,
        reachable: category != null,
        curationStatus: '${parsed['curation_status'] ?? 'draft'}',
        contentLanguages: (parsed['content_languages'] as YamlList? ?? [])
            .map((l) => '$l')
            .toList(),
        coverUrl: parsed['cover_url'] as String?,
        books: _readBooks(parsed['books']),
      ),
    );
  }
  lists.sort((a, b) => a.id.compareTo(b.id));
  return lists;
}

List<_Book> _readBooks(dynamic raw) {
  if (raw is! YamlList) return const [];
  final books = <_Book>[];
  for (final entry in raw) {
    if (entry is String) {
      books.add(_Book(isbn: entry));
    } else if (entry is YamlMap) {
      books.add(
        _Book(
          isbn: '${entry['isbn'] ?? ''}',
          note: entry['note'] as String?,
          title: entry['title'] as String?,
          authors: (entry['authors'] as YamlList? ?? [])
              .map((a) => '$a')
              .toList(),
          altEditions: {
            for (final e
                in (entry['alt_editions'] as YamlMap? ?? YamlMap()).entries)
              '${e.key}': '${e.value}',
          },
          coverUrl: entry['cover_url'] as String?,
        ),
      );
    }
  }
  return books;
}

// ── Reporting ───────────────────────────────────────────────────────────

class _Report {
  final Map<String, List<_Finding>> byList = {};
  final Map<String, bool> reachable = {};
  int calls = 0;
  int transportErrors = 0;

  /// Calls refused with 429. The keyless Google Books quota is per day and
  /// a full corpus pass exhausts it, so this is expected, not exceptional.
  int rateLimited = 0;

  /// ISBNs that no source could be made to answer about. Counted apart from
  /// [transportErrors] because it is the number that makes a verdict unsafe.
  int unverified = 0;

  void add(_List list, List<_Finding> findings) {
    byList[list.id] = findings;
    reachable[list.id] = list.reachable;
  }

  int get blockingOnReachable => byList.entries
      .where((e) => reachable[e.key] ?? false)
      .expand((e) => e.value)
      .where((f) => f.severity == _Severity.blocking)
      .length;

  int count(_Severity severity) => byList.values
      .expand((f) => f)
      .where((f) => f.severity == severity)
      .length;

  List<String> get cleanReachableLists => byList.entries
      .where(
        (e) =>
            (reachable[e.key] ?? false) &&
            !e.value.any((f) => f.severity != _Severity.info),
      )
      .map((e) => e.key)
      .toList();

  /// Lists a curator may promote: nothing wrong, and nothing unchecked.
  ///
  /// Deliberately NOT the same set as [cleanReachableLists]. Promotion is a
  /// judgement about CORRECTNESS, so it turns on blocking findings and on
  /// `unverified`, where a source could not answer and the entry is simply
  /// unknown. A `no_cover` is a poor card and not a wrong book, and a
  /// `title_differs` needs a human to read it: neither belongs in a
  /// mechanical gate, and holding promotion on `no_cover` would block a
  /// correct list over its artwork.
  List<String> get promoteReadyLists => byList.entries
      .where(
        (e) =>
            (reachable[e.key] ?? false) &&
            !e.value.any(
              (f) =>
                  f.severity == _Severity.blocking ||
                  f.code == 'unverified' ||
                  f.code == 'title_differs',
            ),
      )
      .map((e) => e.key)
      .toList();

  Map<String, dynamic> toJson() => {
    'outbound_calls': calls,
    'transport_errors': transportErrors,
    'blocking_on_reachable': blockingOnReachable,
    'clean_reachable_lists': cleanReachableLists,
    'promote_ready_lists': promoteReadyLists,
    'lists': {
      for (final entry in byList.entries)
        entry.key: {
          'reachable': reachable[entry.key],
          'findings': entry.value.map((f) => f.toJson()).toList(),
        },
    },
  };
}

void _printList(_List list, List<_Finding> findings) {
  final blocking = findings.where((f) => f.severity == _Severity.blocking);
  final warn = findings.where((f) => f.severity == _Severity.warn);
  final mark = blocking.isNotEmpty
      ? 'BLOCKING'
      : (warn.isNotEmpty ? 'warn' : 'clean');
  final tag = list.reachable ? '' : ' [withdrawn]';
  stdout.writeln(
    '${list.id.padRight(32)} ${list.books.length.toString().padLeft(3)} '
    'entries  $mark$tag',
  );
  for (final finding in findings) {
    if (finding.severity == _Severity.info) continue;
    stdout.writeln(
      '    ${finding.severity.name.toUpperCase().padRight(8)} '
      '${finding.code.padRight(24)} ${finding.where}\n'
      '        ${finding.detail}',
    );
  }
}

void _printSummary(_Report report) {
  stdout.writeln('\n${'-' * 72}');
  stdout.writeln(
    'Lists audited: ${report.byList.length}   '
    'outbound calls: ${report.calls}   '
    'transport errors: ${report.transportErrors}   '
    'rate-limited: ${report.rateLimited}',
  );
  stdout.writeln(
    'Blocking: ${report.count(_Severity.blocking)}   '
    'Warnings: ${report.count(_Severity.warn)}   '
    'Info: ${report.count(_Severity.info)}',
  );
  final promotable = report.promoteReadyLists;
  stdout.writeln(
    '\nReachable lists a curator may promote (${promotable.length}): no '
    'blocking finding, nothing left unverified, no title to read by hand. '
    'A `no_cover` does not hold a list back.',
  );
  for (final id in promotable) {
    stdout.writeln('  $id');
  }

  final clean = report.cleanReachableLists;
  stdout.writeln(
    '\nReachable lists with nothing at all to fix (${clean.length}), '
    'artwork included:',
  );
  stdout.writeln(clean.isEmpty ? '  (none)' : '  ${clean.join('\n  ')}');
  if (report.unverified > 0 || report.rateLimited > 0) {
    stdout.writeln(
      '\nNOTE: ${report.rateLimited} call(s) rate-limited, '
      '${report.transportErrors} transport error(s), '
      '${report.unverified} ISBN(s) left UNVERIFIED. Those are reported as '
      'warnings, never as "unresolved", and are not cached. The keyless '
      'Google Books quota is per day: re-run tomorrow to settle them.',
    );
  } else if (report.transportErrors > 0) {
    stdout.writeln(
      '\nNOTE: ${report.transportErrors} transport error(s). Findings from '
      'this run may be incomplete; re-run before acting on them.',
    );
  }
}

// ── Text helpers (mirror of the membrane normalization) ─────────────────

String _norm(String value) {
  final folded = value.toLowerCase().split('').map((c) => _fold[c] ?? c).join();
  return folded
      .split(RegExp(r'[^0-9a-z]+'))
      .where((w) => w.isNotEmpty)
      .join(' ');
}

String _sortWords(String value) {
  final words = value.split(' ')..sort();
  return words.join(' ');
}

/// Share of the shorter side's words that both strings share. Symmetric
/// enough for "is this the same work", and forgiving of the subtitle one
/// side carries and the other drops.
double _overlap(String a, String b) {
  var wa = a.split(' ').where((w) => w.length > 2).toSet();
  var wb = b.split(' ').where((w) => w.length > 2).toSet();

  // Dropping the short words is what lets "Le Seigneur des anneaux" agree
  // with "Seigneur des anneaux", but a title that is ITSELF two letters long
  // ("Ça", "Oh") ends up with an empty set and can then agree with nothing,
  // ever: every edition of "Ça" would be reported as a different work for as
  // long as the corpus carries it. When BOTH sides vanish that way, compare
  // them whole. Only when both do: one short title against a real one
  // ("Ça" against "Ca ne fait rien") is a difference worth reporting, and
  // widening it there would exonerate a genuinely wrong book.
  if (wa.isEmpty && wb.isEmpty) {
    wa = a.split(' ').where((w) => w.isNotEmpty).toSet();
    wb = b.split(' ').where((w) => w.isNotEmpty).toSet();
  }

  if (wa.isEmpty || wb.isEmpty) return 0;
  final shared = wa.intersection(wb).length;
  return shared / (wa.length < wb.length ? wa.length : wb.length);
}

const Map<String, String> _fold = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'ç': 'c',
  'ñ': 'n',
  'œ': 'oe',
  'æ': 'ae',
  'ß': 'ss',
};

String? _toIsbn13(String raw) {
  final cleaned = raw.replaceAll(RegExp(r'[^0-9Xx]'), '').toUpperCase();
  if (cleaned.length == 13) {
    var sum = 0;
    for (var i = 0; i < 12; i++) {
      final digit = int.tryParse(cleaned[i]);
      if (digit == null) return null;
      sum += digit * (i.isEven ? 1 : 3);
    }
    final check = (10 - sum % 10) % 10;
    return '$check' == cleaned[12] ? cleaned : null;
  }
  if (cleaned.length == 10) {
    var sum = 0;
    for (var i = 0; i < 9; i++) {
      final digit = int.tryParse(cleaned[i]);
      if (digit == null) return null;
      sum += digit * (10 - i);
    }
    final last = cleaned[9];
    sum += last == 'X' ? 10 : (int.tryParse(last) ?? -1000);
    if (sum % 11 != 0) return null;
    final core = '978${cleaned.substring(0, 9)}';
    var s = 0;
    for (var i = 0; i < 12; i++) {
      s += int.parse(core[i]) * (i.isEven ? 1 : 3);
    }
    return '$core${(10 - s % 10) % 10}';
  }
  return null;
}

// ── CLI ─────────────────────────────────────────────────────────────────

class _Options {
  _Options({
    this.listId,
    this.category,
    this.offline = false,
    this.useCache = true,
    this.includeWithdrawn = false,
    this.delayMs = _defaultDelayMs,
    this.jsonPath,
    this.help = false,
  });

  final String? listId;
  final String? category;
  final bool offline;
  final bool useCache;
  final bool includeWithdrawn;
  final int delayMs;
  final String? jsonPath;
  final bool help;

  static _Options parse(List<String> args) {
    String? listId, category, jsonPath;
    var offline = false, useCache = true, withdrawn = false, help = false;
    var delay = _defaultDelayMs;
    for (var i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--list':
          listId = args[++i];
        case '--category':
          category = args[++i];
        case '--json':
          jsonPath = args[++i];
        case '--delay':
          delay = int.tryParse(args[++i]) ?? _defaultDelayMs;
        case '--offline':
          offline = true;
        case '--no-cache':
          useCache = false;
        case '--include-withdrawn':
          withdrawn = true;
        case '-h' || '--help':
          help = true;
        default:
          stderr.writeln('Unknown option: ${args[i]}');
          help = true;
      }
    }
    return _Options(
      listId: listId,
      category: category,
      offline: offline,
      useCache: useCache,
      includeWithdrawn: withdrawn,
      delayMs: delay,
      jsonPath: jsonPath,
      help: help,
    );
  }
}

void _printUsage() {
  stdout.writeln('''
Corpus audit for the curated lists (ADR-066 section 8b).

  dart tools/audit_curated_lists.dart [options]

  --list <id>            audit one list (withdrawn ones included)
  --category <id>        audit one category
  --include-withdrawn    also audit lists commented out of index.yml
  --offline              structural checks only, no network
  --no-cache             ignore $_cachePath
  --delay <ms>           milliseconds between calls (default $_defaultDelayMs)
  --json <path>          also write a machine-readable report
  -h, --help             this

Exit code 1 when a REACHABLE list carries a blocking finding.
Run it deliberately: it walks hundreds of ISBNs across public catalogues.
''');
}

/// Offline proof of the severity rule of [_titleFinding].
///
/// A flag rather than a test file because every member here is private to a
/// single-file CLI, and because the rule has to be checkable when the
/// catalogues are unreachable, which is exactly when it was written. Run it
/// with `dart tools/audit_curated_lists.dart --self-test`.
bool _selfTest() {
  var failures = 0;
  void check(String name, bool ok) {
    stdout.writeln('${ok ? "  ok  " : "  FAIL"} $name');
    if (!ok) failures++;
  }

  _Book entry(String title, String author) =>
      _Book(isbn: '9782000000001', note: '$title - $author');

  // A volume catalogued under its own title, tied to our series by 461.
  final volume = _titleFinding(
    entry('One Piece - Tome 1', 'Eiichiro Oda'),
    _Resolved(
      'Romance dawn',
      const ['Eiichiro Oda'],
      'bnf',
      language: 'fre',
      seriesTitle: 'One piece',
    ),
    'x[0] 1',
    const ['fr'],
  );
  check(
    'a volume of our series stays a warning',
    volume.severity == _Severity.warn,
  );

  // A translation: the record is in a language the list does not carry.
  final translated = _titleFinding(
    entry('1984', 'George Orwell'),
    _Resolved(
      'Nineteen Eighty-Four',
      const ['George Orwell'],
      'bnf',
      language: 'eng',
    ),
    'x[1] 1',
    const ['fr'],
  );
  check('a translation stays a warning', translated.severity == _Severity.warn);

  // Same language, no series of ours, nothing in common: another book.
  final other = _titleFinding(
    entry('Pour qui sonne le glas', 'Ernest Hemingway'),
    _Resolved(
      'Le Soleil se leve aussi',
      const ['Ernest Hemingway'],
      'bnf',
      language: 'fre',
    ),
    'x[2] 1',
    const ['fr'],
  );
  check(
    'another work by the same author blocks',
    other.severity == _Severity.blocking && other.code == 'different_work',
  );

  // No language reported: an absent field is not evidence.
  final unknown = _titleFinding(
    entry('Le Chevalier Cheval', 'Emmanuel Guibert'),
    _Resolved('Ariol', const ['Emmanuel Guibert'], 'openlibrary'),
    'x[3] 1',
    const ['fr'],
  );
  check(
    'a source that reports no language cannot block',
    unknown.severity == _Severity.warn,
  );

  // A title too short to survive the stop-word filter on BOTH sides. These
  // never reach _titleFinding: they have to AGREE, at or above the floor that
  // exonerates an entry outright.
  check(
    'a two-letter title agrees with its unaccented twin',
    _overlap(_norm('Ça'), _norm('Ca')) >= _titleAgreementFloor,
  );
  check(
    'an ellipsis is not a difference',
    _overlap(_norm('Oh...'), _norm('Oh')) >= _titleAgreementFloor,
  );

  // ... but a short title against a real one still differs, or the widening
  // would exonerate a wrong book.
  check(
    'a short title does not dissolve into a longer one',
    _overlap('ca', 'ca ne fait rien') == 0,
  );

  // The two vocabularies disagree on how to spell a language.
  check('fr matches fre', _sameLanguage('fr', 'fre'));
  check('fr does not match eng', !_sameLanguage('fr', 'eng'));

  stdout.writeln(
    failures == 0 ? '\nself-test: ok' : '\nself-test: $failures FAILED',
  );
  return failures == 0;
}
