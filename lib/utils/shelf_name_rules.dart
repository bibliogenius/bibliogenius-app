import 'package:flutter/widgets.dart';

import '../models/tag.dart';
import '../services/translation_service.dart';

/// The longest name a reader may give a shelf, in characters as they see
/// them. The core accepts longer names, up to its own ceiling, so a name
/// already stored or synced from elsewhere can exceed this: it is shown whole
/// and refused in words, never cut to fit.
const int maxShelfNameLength = 60;

/// Whether [name], trimmed as it would be saved, is over
/// [maxShelfNameLength].
bool shelfNameTooLong(String name) =>
    name.trim().characters.length > maxShelfNameLength;

/// The sentence that says a name is too long.
String shelfNameTooLongMessage(BuildContext context) =>
    TranslationService.translate(
      context,
      'shelf_name_too_long',
    ).replaceAll('%d', '$maxShelfNameLength');

/// What is wrong with [value] as the name of a shelf among [tags], if anything.
/// The shelf being renamed may keep its name in another case.
String? shelfNameError(
  BuildContext context,
  String? value,
  List<Tag> tags, {
  Tag? renaming,
}) {
  final name = value?.trim() ?? '';
  if (name.isEmpty) {
    return TranslationService.translate(context, 'field_required');
  }
  if (shelfNameTooLong(name)) return shelfNameTooLongMessage(context);
  final others = tags.where((t) => t.name != renaming?.name).toList();
  return shelfTakenBy(others, name) == null
      ? null
      : TranslationService.translate(context, 'shelf_already_exists');
}
