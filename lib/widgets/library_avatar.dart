import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/avatar_config.dart';

/// Matches a word that opens with an actual letter, so a name tag such as the
/// `#A3F` suffix of a generated library name never becomes an initial.
final _startsWithLetter = RegExp(r'^\p{L}', unicode: true);

/// Word separator, hoisted like [_startsWithLetter]: initials are computed on
/// every build of every row of the contacts list, and there is no reason to
/// recompile the pattern each time.
final _whitespace = RegExp(r'\s+');

/// Circular avatar for a library (own profile, peer or directory entry).
///
/// Renders the configured avatar when [config] is set, and falls back to
/// locally drawn initials otherwise - including while the remote image loads
/// and when it fails, so an offline device keeps a readable identity marker
/// instead of an empty disc.
///
/// The fallback is drawn locally on purpose. Deriving it from a remote service
/// would mean one network round-trip per peer just to draw two letters, and
/// would send every followed library's name to a third party, which the
/// offline-first and privacy constraints of the project both rule out.
///
/// The avatar is decorative: every caller displays the library name right next
/// to it, so it is excluded from the semantics tree rather than duplicating the
/// name for screen readers.
class LibraryAvatar extends StatelessWidget {
  /// Parsed avatar configuration, or null when the library has none.
  final AvatarConfig? config;

  /// Library display name, used for the initials fallback.
  final String name;

  final double radius;

  /// Background of the fallback disc, also shown behind a loading image.
  final Color backgroundColor;

  /// Color of the fallback initials.
  final Color foregroundColor;

  const LibraryAvatar({
    super.key,
    required this.config,
    required this.name,
    required this.radius,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  /// Initials for a library name: first letter of the first word plus first
  /// letter of the last one, which is what the previously used remote renderer
  /// produced, so switching to local drawing does not change the letters users
  /// already know.
  ///
  /// Taking both ends rather than the first two words is what makes the
  /// initials useful at all: generated library names read
  /// `Bibliothèque de {host}` or `Library of {host}` (see
  /// `default_library_name.rs`), so the leading word is the same for nearly
  /// every library and the first letter alone would be "B" for all of them.
  static String initialsFor(String name) {
    final words = name
        .split(_whitespace)
        .where((w) => _startsWithLetter.hasMatch(w))
        .toList();
    if (words.isEmpty) return '?';
    final first = _firstLetter(words.first);
    if (words.length == 1) return first;
    return '$first${_firstLetter(words.last)}';
  }

  /// First letter of [word], taken as a rune rather than a UTF-16 code unit:
  /// letters outside the Basic Multilingual Plane (Gothic, Osage, Adlam and
  /// other scripts) are surrogate pairs, and indexing with [] would return
  /// half of one, which renders as a replacement glyph.
  static String _firstLetter(String word) =>
      String.fromCharCode(word.runes.first).toUpperCase();

  Widget _initialsFallback() {
    final initials = initialsFor(name);
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      child: FittedBox(
        // Keeps the initials inside the disc when the OS text scaler is
        // cranked up, instead of overflowing it (accessibility rule A3).
        fit: BoxFit.scaleDown,
        child: Text(
          initials,
          style: TextStyle(
            color: foregroundColor,
            fontWeight: FontWeight.bold,
            // Proportional to the disc, and narrower for two letters so both
            // fit across the call sites' radii.
            fontSize: radius * (initials.length > 1 ? 0.72 : 0.82),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Excluded as a whole, not per branch: the initials are as decorative as
    // the artwork, and leaving them in would make a screen reader spell "BC"
    // just before reading the library name that sits next to the disc.
    return ExcludeSemantics(child: _buildDisc());
  }

  Widget _buildDisc() {
    final cfg = config;
    if (cfg == null) return _initialsFallback();

    final diameter = radius * 2;
    final image = cfg.isAsset
        ? Image.asset(
            cfg.assetPath,
            width: diameter,
            height: diameter,
            fit: BoxFit.cover,
            excludeFromSemantics: true,
            errorBuilder: (_, _, _) => _initialsFallback(),
          )
        : CachedNetworkImage(
            // Request 2x the rendered size so the disc stays sharp on retina.
            imageUrl: cfg.toUrl(size: (radius * 4).round()),
            width: diameter,
            height: diameter,
            fit: BoxFit.cover,
            placeholder: (_, _) => _initialsFallback(),
            errorWidget: (_, _, _) => _initialsFallback(),
          );

    return CircleAvatar(
      radius: radius,
      // DiceBear avatars have a transparent background: tint the disc rather
      // than fill it, so the artwork reads the same as in the contacts list.
      backgroundColor: backgroundColor.withValues(alpha: 0.15),
      child: ClipOval(child: image),
    );
  }
}
