import 'dart:io';
import 'dart:isolate';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

  /// Preference holding the "automatic cover crop" toggle (on by default).
  static const String autoCropPrefKey = 'coverAutoCropEnabled';

  /// Preference set when the user ticked "don't show again" on the scan
  /// tips. Cleared when auto crop is switched back on.
  static const String scanTipsDismissedPrefKey = 'cover_scan_tips_dismissed';

  static const _deviceChannel = MethodChannel('com.bibliogenius.app/device');

  static Future<bool>? _scannerAvailable;

  /// Forces [isDocumentScannerAvailable] in tests, where neither VisionKit
  /// nor Play services exist.
  @visibleForTesting
  static bool? debugScannerAvailableOverride;

  /// Whether this device has a system document scanner, which finds the
  /// cover's edges, crops it and straightens the perspective: VisionKit on
  /// iOS, ML Kit on Android. ML Kit ships with Google Play services, so an
  /// Android device without them (/e/OS, GrapheneOS without Play, recent
  /// Huawei) keeps the plain camera, rather than the plugin's fallback
  /// cropper whose frame starts as a fixed rectangle. Desktop platforms
  /// keep the plain camera too.
  static Future<bool> isDocumentScannerAvailable() {
    final override = debugScannerAvailableOverride;
    if (override != null) return Future.value(override);
    return _scannerAvailable ??= _checkScannerAvailable();
  }

  static Future<bool> _checkScannerAvailable() async {
    if (Platform.isIOS) return true;
    if (!Platform.isAndroid) return false;
    try {
      return await _deviceChannel.invokeMethod<bool>(
            'isGooglePlayServicesAvailable',
          ) ??
          false;
    } catch (e) {
      debugPrint('Play services check failed, keeping the plain camera: $e');
      return false;
    }
  }

  /// Whether camera capture goes through the document scanner: available
  /// on this device and auto crop left on in the settings.
  static Future<bool> usesDocumentScanner() async {
    if (!await isDocumentScannerAvailable()) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(autoCropPrefKey) ?? true;
  }

  /// Opens the camera, saves the photo into covers/ and returns the local path.
  /// Returns null if the user cancelled or the camera is unavailable.
  static Future<String?> takePhotoAndSave({String? bookId}) async {
    if (await usesDocumentScanner()) return _scanAndSave(bookId);

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

  /// Captures one page with the document scanner. The scanner returns a
  /// full-resolution file in its own cache, so it is shrunk by
  /// [_saveToCovers] and the cache is emptied afterwards.
  static Future<String?> _scanAndSave(String? bookId) async {
    final pages = await CunningDocumentScanner.getPictures(
      noOfPages: 1,
      scannerSource: ScannerSource.camera,
      // Keeps the colours: the "full" mode may offer shadow and stain
      // removal tuned for paper documents.
      androidScannerMode: AndroidScannerMode.base,
      iosScannerOptions: IosScannerOptions(
        imageFormat: IosImageFormat.jpg,
        jpgCompressionQuality: 0.9,
      ),
    );
    if (pages == null) return null;
    try {
      return await _saveToCovers(XFile(pages.first), bookId);
    } finally {
      try {
        await CunningDocumentScanner.cleanCache();
      } catch (e) {
        debugPrint('Failed to clean the document scanner cache: $e');
      }
    }
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
    // Decoding a full-resolution scan in pure Dart takes long enough to
    // freeze the UI, so it runs off the main isolate.
    final processed = await Isolate.run(() => _encodeCoverJpeg(raw));
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
