import 'package:flutter/material.dart';
import '../services/translation_service.dart';

class Avatar {
  final String id;
  final String assetPath;
  final String label;
  final Color themeColor;
  final String profileType; // 'librarian', 'individual', or 'kid'

  const Avatar({
    required this.id,
    required this.assetPath,
    required this.label,
    required this.themeColor,
    required this.profileType,
  });
}

// Current avatars - keeping junior reader, will add others when images are generated
const List<Avatar> availableAvatars = [
  // Kid Avatars
  Avatar(
    id: 'junior_reader',
    assetPath: 'assets/avatars/profile_kid_1764454336588.png',
    label: 'avatar_junior_reader',
    themeColor: Colors.orange,
    profileType: 'kid',
  ),
  // TODO: Add dinosaur avatar (for kid)
  // TODO: Add dragon avatar (for kid)
  // TODO: Add unicorn avatar (for kid)
  
  // Individual Avatars
  Avatar(
    id: 'bookworm',
    assetPath: 'assets/avatars/profile_individual_1764454364353.png',
    label: 'avatar_bookworm',
    themeColor: Colors.indigo,
    profileType: 'individual',
  ),
  Avatar(
    id: 'young_girl',
    assetPath: 'assets/avatars/avatar_asian_girl_1764454514931.png',
    label: 'avatar_young_reader',
    themeColor: Colors.pinkAccent,
    profileType: 'individual',
  ),
  Avatar(
    id: 'grandmother',
    assetPath: 'assets/avatars/avatar_elderly_woman_1764454487281.png',
    label: 'avatar_grandmother',
    themeColor: Colors.brown,
    profileType: 'individual',
  ),
  // TODO: Add circular grandmother avatar
  // TODO: Add grandfather avatar
  // TODO: Add man avatar
  // TODO: Add woman avatar
  
  // Librarian Avatars
  Avatar(
    id: 'head_librarian',
    assetPath: 'assets/avatars/profile_librarian_1764454351246.png',
    label: 'avatar_head_librarian',
    themeColor: Colors.teal,
    profileType: 'librarian',
  ),
  Avatar(
    id: 'professional',
    assetPath: 'assets/avatars/avatar_muslim_woman_1764454528472.png',
    label: 'avatar_professional_librarian',
    themeColor: Colors.cyan,
    profileType: 'librarian',
  ),
];

// Get avatars filtered by profile type
List<Avatar> getAvatarsByProfileType(BuildContext context, String profileType) {
  return availableAvatars.where((a) => a.profileType == profileType).map((a) => Avatar(
    id: a.id,
    assetPath: a.assetPath,
    label: TranslationService.translate(context, a.label),
    themeColor: a.themeColor,
    profileType: a.profileType,
  )).toList();
}
