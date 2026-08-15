import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/avatar_config.dart';

/// Circular avatar for a library profile banner.
///
/// Renders the configured avatar when [config] is set, and falls back to the
/// first letter of the name otherwise - including while the remote image loads
/// and when it fails, so an offline device keeps a readable identity marker
/// instead of an empty disc.
///
/// The letter fallback is the banner's historical rendering, kept as-is: how to
/// derive better initials from a library name is an open question, since
/// generated names all read `Bibliothèque de {host}` and collapse to the same
/// letter.
///
/// The avatar is decorative: every caller displays the library name right next
/// to it, so it is excluded from the semantics tree rather than duplicating the
/// name for screen readers.
class LibraryAvatar extends StatelessWidget {
  /// Parsed avatar configuration, or null when the library has none.
  final AvatarConfig? config;

  /// Library display name, used for the letter fallback.
  final String name;

  final double radius;

  /// Background of the fallback disc, also shown behind a loading image.
  final Color backgroundColor;

  /// Color of the fallback letter.
  final Color foregroundColor;

  const LibraryAvatar({
    super.key,
    required this.config,
    required this.name,
    required this.radius,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  /// First letter of [name], taken as a rune rather than a UTF-16 code unit:
  /// letters outside the Basic Multilingual Plane (Gothic, Osage, Adlam and
  /// other scripts) are surrogate pairs, and indexing with [] would return
  /// half of one, which renders as a replacement glyph.
  static String initialFor(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return String.fromCharCode(trimmed.runes.first).toUpperCase();
  }

  Widget _letterFallback() {
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor,
      child: FittedBox(
        // Keeps the letter inside the disc when the OS text scaler is cranked
        // up, instead of overflowing it (accessibility rule A3).
        fit: BoxFit.scaleDown,
        child: Text(
          initialFor(name),
          style: TextStyle(
            color: foregroundColor,
            fontWeight: FontWeight.bold,
            fontSize: radius * 0.82,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Excluded as a whole, not per branch: the letter is as decorative as the
    // artwork, and leaving it in would make a screen reader spell it out just
    // before reading the library name that sits next to the disc.
    return ExcludeSemantics(child: _buildDisc());
  }

  Widget _buildDisc() {
    final cfg = config;
    if (cfg == null) return _letterFallback();

    final diameter = radius * 2;
    final image = cfg.isAsset
        ? Image.asset(
            cfg.assetPath,
            width: diameter,
            height: diameter,
            fit: BoxFit.cover,
            excludeFromSemantics: true,
            errorBuilder: (_, _, _) => _letterFallback(),
          )
        : CachedNetworkImage(
            // Request 2x the rendered size so the disc stays sharp on retina.
            imageUrl: cfg.toUrl(size: (radius * 4).round()),
            width: diameter,
            height: diameter,
            fit: BoxFit.cover,
            placeholder: (_, _) => _letterFallback(),
            errorWidget: (_, _, _) => _letterFallback(),
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
