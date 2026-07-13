import 'package:flutter/material.dart';

import '../data/repositories/collection_repository.dart';
import '../models/collection_book.dart';
import '../services/translation_service.dart';
import '../widgets/app_snack_bar.dart';

/// Outcome of [showVolumeEditor]. `null` from the editor means "cancelled, no
/// change"; a result with a `null` volumeNumber means "clear to unnumbered".
class VolumeEditResult {
  final int? volumeNumber;
  const VolumeEditResult(this.volumeNumber);
}

/// Shared dialog to set (or clear) a volume's reading-order number. Returns
/// `null` when cancelled or when the input is invalid (an error snackbar is
/// shown in that case), otherwise a [VolumeEditResult].
Future<VolumeEditResult?> showVolumeEditor(
  BuildContext context, {
  required int? current,
}) async {
  final controller = TextEditingController(text: current?.toString() ?? '');
  try {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(TranslationService.translate(ctx, 'series_edit_volume')),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: TranslationService.translate(ctx, 'series_volume_number'),
            hintText: TranslationService.translate(ctx, 'series_volume_hint'),
          ),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(TranslationService.translate(ctx, 'cancel')),
          ),
          if (current != null)
            TextButton(
              onPressed: () {
                // Clear = save an empty value, i.e. an unnumbered volume.
                controller.clear();
                Navigator.pop(ctx, true);
              },
              child: Text(
                TranslationService.translate(ctx, 'series_clear_volume'),
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(TranslationService.translate(ctx, 'save')),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return null;

    final raw = controller.text.trim();
    if (raw.isEmpty) return const VolumeEditResult(null);
    final value = int.tryParse(raw);
    if (value == null || value < 0) {
      AppSnackBar.error(
        context,
        TranslationService.translate(context, 'series_invalid_volume'),
      );
      return null;
    }
    return VolumeEditResult(value);
  } finally {
    controller.dispose();
  }
}

/// Pure reorder: move an item using Flutter's `ReorderableList` index
/// convention and renumber the volumes 1..N in the new order. Returns the new
/// list with updated volume numbers, for instant optimistic display. No IO.
List<CollectionBook> reorderedSequentialVolumes(
  List<CollectionBook> books,
  int oldIndex,
  int newIndex,
) {
  if (newIndex > oldIndex) newIndex -= 1;
  final moved = List<CollectionBook>.from(books);
  final item = moved.removeAt(oldIndex);
  moved.insert(newIndex, item);
  return [
    for (var i = 0; i < moved.length; i++) moved[i].copyWith(volumeNumber: i + 1),
  ];
}

/// Persist the volume numbers of an already-ordered list (1..N by position),
/// writing only the positions whose number actually changed relative to
/// [previous] (the pre-reorder order). Throws if a write fails.
Future<void> persistVolumeNumbers(
  CollectionRepository repo,
  String collectionId,
  List<CollectionBook> ordered,
  List<CollectionBook> previous,
) async {
  final oldNumberByBook = {
    for (final b in previous) b.bookId: b.volumeNumber,
  };
  for (var i = 0; i < ordered.length; i++) {
    if (oldNumberByBook[ordered[i].bookId] != i + 1) {
      await repo.setBookVolumeNumber(collectionId, ordered[i].bookId, i + 1);
    }
  }
}
