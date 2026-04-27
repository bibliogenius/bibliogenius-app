import 'package:flutter/material.dart';

class Avatar {
  final String id;
  final String assetPath;
  final String label;
  final Color themeColor;

  const Avatar({
    required this.id,
    required this.assetPath,
    required this.label,
    required this.themeColor,
  });
}

// Legacy avatar images have been removed - using customizable avatar system instead
const List<Avatar> availableAvatars = [];
