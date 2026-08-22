import 'package:flutter/widgets.dart';

import '../models/collection.dart';
import '../services/translation_service.dart';

/// Display name of a collection (single source of truth, ADR-064).
///
/// Typed favorites collections derive their label from the TYPE via i18n,
/// never from the stored string: a lazily created one stores the technical
/// sentinel `__favorites__` (which must never reach the screen), and even
/// an adopted one shows the translated label so the name is consistent
/// across the 11 UI languages.
/// The technical stored name of a lazily created favorites collection.
/// Mirrors `FAVORITES_SENTINEL_NAME` on the Rust side.
const String favoritesSentinelName = '__favorites__';

String collectionDisplayName(BuildContext context, Collection collection) {
  if (collection.isFavorites || collection.name == favoritesSentinelName) {
    // The sentinel arm covers a collection whose `source` was lost (an old
    // build's series flip): its raw technical name must never surface,
    // adoption is its way back to the typed source.
    return TranslationService.translate(context, 'favorites_collection_name');
  }
  return collection.name;
}
