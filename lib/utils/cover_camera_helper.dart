import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
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

  /// Default JPEG quality. Matches the Rust default so a cover that came
  /// from Flutter is not unnecessarily re-compressed on serve.
  @visibleForTesting
  static const int targetQuality = 85;

  /// Hard cap on encoded cover size. If quality 85 exceeds this, we step
  /// down through 75 then 65 before giving up. Matches `COVER_SIZE_CAP_BYTES`
  /// in the Rust pipeline.
  @visibleForTesting
  static const int targetMaxBytes = 50 * 1024;

  /// Quality fallback ladder, mirrored from `utils/cover_image.rs::QUALITY_STEPS`.
  static const List<int> _qualitySteps = [targetQuality, 75, 65];

  static final _picker = ImagePicker();

  /// Whether the current platform supports camera capture.
  static bool get isCameraAvailable =>
      _picker.supportsImageSource(ImageSource.camera);

  /// Opens the camera, saves the photo into covers/ and returns the local path.
  /// Returns null if the user cancelled or the camera is unavailable.
  static Future<String?> takePhotoAndSave({String? bookId}) async {
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
  static Future<String?> pickFromGalleryAndSave({String? bookId}) async {
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
  static Future<String?> renameTempCover(String tempPath, String bookId) async {
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
  ///
  /// The picked image is decoded, resized to fit within the 300x450 box
  /// (preserving aspect ratio), EXIF orientation is baked in, and the
  /// result is re-encoded as JPEG with a quality ladder that caps the
  /// output at ~50 KB. ImagePicker's own maxWidth/imageQuality hints are
  /// not relied upon — they are silently ignored on macOS for PNG
  /// sources, which would otherwise leave 300+ KB files on disk.
  static Future<String?> _saveToCovers(XFile? picked, String? bookId) async {
    if (picked == null) return null;

    final appDir = await getApplicationSupportDirectory();
    final coversDir = Directory('${appDir.path}/covers');
    if (!await coversDir.exists()) {
      await coversDir.create(recursive: true);
    }

    final fileName = bookId != null
        ? '$bookId.jpg'
        : 'temp_${const Uuid().v4()}.jpg';
    final targetPath = '${coversDir.path}/$fileName';

    final raw = await File(picked.path).readAsBytes();
    final processed = await _encodeCoverJpeg(raw);
    await File(targetPath).writeAsBytes(processed, flush: true);
    return targetPath;
  }

  /// Decode → orient → resize-to-fit → JPEG-encode pipeline.
  ///
  /// Public-on-test (`@visibleForTesting`) so unit tests can feed
  /// synthetic bytes without going through `image_picker`.
  @visibleForTesting
  static Future<Uint8List> encodeCoverJpegForTest(Uint8List raw) =>
      _encodeCoverJpeg(raw);

  static Future<Uint8List> _encodeCoverJpeg(Uint8List raw) async {
    final decoded = img.decodeImage(raw);
    if (decoded == null) {
      throw const FormatException('Could not decode picked image');
    }

    // Apply EXIF rotation so portrait shots don't end up sideways on disk.
    final oriented = img.bakeOrientation(decoded);
    final fitted = _fitWithin(oriented, targetMaxWidth, targetMaxHeight);

    Uint8List? smallest;
    for (final quality in _qualitySteps) {
      final encoded = Uint8List.fromList(
        img.encodeJpg(fitted, quality: quality),
      );
      if (encoded.length <= targetMaxBytes) {
        return encoded;
      }
      if (smallest == null || encoded.length < smallest.length) {
        smallest = encoded;
      }
    }
    // None of the quality steps fit — return the smallest produced. The
    // Rust serve-side resize will trim further if needed.
    return smallest!;
  }

  /// Returns [src] downscaled so it fits within [maxW]x[maxH] while
  /// preserving aspect ratio. Returns [src] untouched if already small.
  static img.Image _fitWithin(img.Image src, int maxW, int maxH) {
    if (src.width <= maxW && src.height <= maxH) return src;
    final ratioW = maxW / src.width;
    final ratioH = maxH / src.height;
    final ratio = ratioW < ratioH ? ratioW : ratioH;
    final newW = (src.width * ratio).round().clamp(1, maxW);
    final newH = (src.height * ratio).round().clamp(1, maxH);
    return img.copyResize(src, width: newW, height: newH);
  }
}
