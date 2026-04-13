import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class CoverCameraHelper {
  /// Target max width (px) for stored cover thumbnails. Matches the Rust
  /// serve-side resize in `utils/cover_image.rs` so local files and peer
  /// responses stay visually aligned.
  @visibleForTesting
  static const int targetMaxWidth = 300;

  /// Target max height (px). Aspect ratio 2:3 matches most book covers.
  @visibleForTesting
  static const int targetMaxHeight = 450;

  /// JPEG quality used by ImagePicker. Matches the Rust default so a cover
  /// that came from Flutter is not unnecessarily re-compressed on serve.
  @visibleForTesting
  static const int targetQuality = 85;

  static final _picker = ImagePicker();

  /// Whether the current platform supports camera capture.
  static bool get isCameraAvailable =>
      _picker.supportsImageSource(ImageSource.camera);

  /// Opens the camera, saves the photo into covers/ and returns the local path.
  /// Returns null if the user cancelled or the camera is unavailable.
  static Future<String?> takePhotoAndSave({int? bookId}) async {
    // requestFullMetadata: false avoids PHPhotoLibrary access on iOS
    // (prevents crash when tapping "Use Photo")
    final XFile? photo = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: targetMaxWidth.toDouble(),
      maxHeight: targetMaxHeight.toDouble(),
      imageQuality: targetQuality,
      requestFullMetadata: false,
    );
    return _saveToCovers(photo, bookId);
  }

  /// Opens the gallery picker and saves the chosen image as JPEG into covers/.
  /// Returns the local path, or null if the user cancelled.
  ///
  /// Uses ImagePicker (not FilePicker) so iOS converts HEIC/HEIF to JPEG via
  /// Apple's PHPickerViewController. The Rust resize pipeline only decodes
  /// JPEG/PNG, so HEIC files would otherwise fail silently.
  static Future<String?> pickFromGalleryAndSave({int? bookId}) async {
    final XFile? picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: targetMaxWidth.toDouble(),
      maxHeight: targetMaxHeight.toDouble(),
      imageQuality: targetQuality,
      requestFullMetadata: false,
    );
    return _saveToCovers(picked, bookId);
  }

  /// Renames a temp cover file to use the real book ID after creation.
  /// Returns the new path, or null if the source file does not exist.
  static Future<String?> renameTempCover(String tempPath, int bookId) async {
    final file = File(tempPath);
    if (!await file.exists()) return null;

    final dir = file.parent.path;
    final newPath = '$dir/$bookId.jpg';
    await file.rename(newPath);
    return newPath;
  }

  /// Deletes a temp cover file (e.g. when the user cancels adding a book).
  static Future<void> cleanupTempCover(String? path) async {
    if (path == null) return;
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Failed to clean up temp cover: $e');
    }
  }

  /// Copies [picked] into `{AppSupport}/covers/` under a deterministic name.
  /// When [bookId] is known (edit flow) the file is `<bookId>.jpg`; during
  /// add flow a temp UUID name is used, and `renameTempCover` finalises it.
  static Future<String?> _saveToCovers(XFile? picked, int? bookId) async {
    if (picked == null) return null;

    final appDir = await getApplicationSupportDirectory();
    final coversDir = Directory('${appDir.path}/covers');
    if (!await coversDir.exists()) {
      await coversDir.create(recursive: true);
    }

    final fileName =
        bookId != null ? '$bookId.jpg' : 'temp_${const Uuid().v4()}.jpg';
    final targetPath = '${coversDir.path}/$fileName';

    await File(picked.path).copy(targetPath);
    return targetPath;
  }
}
