import 'package:flutter/material.dart';

import '../services/translation_service.dart';

/// Rotated paper-band "new" marker, matching the shelf-view spine band
/// (same deep red, same tilt). Shared by the cover card and the collection
/// stack so the vocabulary stays identical across views.
class NewCornerBand extends StatelessWidget {
  const NewCornerBand({super.key});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.10, // slight tilt like a real paper band
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFFC62828), // deep red, matches the spine band
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              offset: const Offset(0, 1),
              blurRadius: 2,
            ),
          ],
        ),
        child: Text(
          TranslationService.translate(context, 'badge_new').toUpperCase(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            height: 1,
          ),
        ),
      ),
    );
  }
}
