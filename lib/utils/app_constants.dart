class AppConstants {
  // Feature flags
  static const bool enableP2PFeatures = true;
  static bool enableHierarchicalTags = true; // Taxonomy feature (mutable)
  /// Set to true while the app is in beta. Flip to false for stable releases.
  static const bool isBeta = true;
  // App Info
  static const String appName = 'BiblioGenius';

  /// How many days a book is considered "new" after first discovery.
  static const int newBadgeDays = 7;
}
