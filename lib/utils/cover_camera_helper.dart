import 'dart:io';
import 'dart:isolate';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../services/device_service.dart';

/// Thrown when an image declares more pixels than the cover pipeline agrees
/// to decode. Nothing is written then.
class CoverImageTooLargeException implements Exception {
  final int width;
  final int height;

  const CoverImageTooLargeException(this.width, this.height);

  @override
  String toString() => 'CoverImageTooLargeException(${width}x$height)';
}

/// Thrown for an image the pipeline cannot vouch for before decoding it (an
/// animated WebP from the web). Nothing is written then.
class UnsupportedCoverImageException implements Exception {
  final String reason;

  const UnsupportedCoverImageException(this.reason);

  @override
  String toString() => 'UnsupportedCoverImageException($reason)';
}

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

  /// Largest image, in pixels, decoded when it comes from the web. A small
  /// compressed file can declare far more pixels than its size suggests (a
  /// flat image compresses to almost nothing), and the decoder allocates up
  /// to 8 bytes per pixel (16-bit RGBA PNG): 12 MP stays under 100 MB. A book
  /// cover rarely exceeds 3 MP. Mirrored by `WEB_MAX_SOURCE_PIXELS` in the
  /// engine. Photos and gallery files are the user's own and stay uncapped.
  static const int webMaxSourcePixels = 12 * 1000 * 1000;

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

  // Only a positive answer is kept: a negative one may be temporary (Play
  // services updating, channel error), so the next capture asks again.
  static bool _scannerAvailable = false;

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
  static Future<bool> isDocumentScannerAvailable() async {
    final override = debugScannerAvailableOverride;
    if (override != null) return override;
    if (_scannerAvailable) return true;
    final available = switch (defaultTargetPlatform) {
      TargetPlatform.iOS => true,
      TargetPlatform.android =>
        await DeviceService.isGooglePlayServicesAvailable(),
      _ => false,
    };
    _scannerAvailable = available;
    return available;
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

    final newPath = coverPathBeside(tempPath, bookId);
    await file.rename(newPath);
    return newPath;
  }

  /// The final path of [bookId]'s cover, in the directory of [siblingPath]
  /// (typically a temp cover): `<dir>/<bookId>.jpg`.
  static String coverPathBeside(String siblingPath, String bookId) =>
      '${File(siblingPath).parent.path}/$bookId.jpg';

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
    final raw = await File(picked.path).readAsBytes();
    return saveBytesToCovers(raw, bookId: bookId);
  }

  /// Runs [raw] (any format the `image` package decodes: JPEG, PNG, WebP,
  /// GIF...) through the cover pipeline and saves it into covers/, under the
  /// same naming rule as a photo. Used for covers fetched from a web page, so
  /// they end up exactly like a photographed one.
  ///
  /// [maxPixels] caps the source for untrusted bytes, see
  /// [decodeCoverSource]. Throws [FormatException] when [raw] is not a
  /// decodable image, [CoverImageTooLargeException] or
  /// [UnsupportedCoverImageException] when it fails the cap; nothing is
  /// written then.
  static Future<String> saveBytesToCovers(
    Uint8List raw, {
    String? bookId,
    int? maxPixels,
  }) async {
    final appDir = await getApplicationSupportDirectory();
    return writeCoverFile(
      Directory('${appDir.path}/covers'),
      raw,
      bookId: bookId,
      maxPixels: maxPixels,
    );
  }

  /// [saveBytesToCovers] with the covers directory as a parameter, so tests
  /// can point it at a temporary directory.
  @visibleForTesting
  static Future<String> writeCoverFile(
    Directory coversDir,
    Uint8List raw, {
    String? bookId,
    int? maxPixels,
  }) async {
    // Decoding a full-resolution scan in pure Dart takes long enough to
    // freeze the UI, so it runs off the main isolate.
    final processed = await Isolate.run(
      () => _encodeCoverJpeg(raw, maxPixels),
    );

    if (!await coversDir.exists()) {
      await coversDir.create(recursive: true);
    }
    final fileName = bookId != null
        ? '$bookId.jpg'
        : 'temp_${const Uuid().v4()}.jpg';
    final targetPath = '${coversDir.path}/$fileName';
    await File(targetPath).writeAsBytes(processed, flush: true);
    return targetPath;
  }

  /// Decode → orient → resize-to-fit → JPEG-encode pipeline.
  ///
  /// Public-on-test (`@visibleForTesting`) so unit tests can feed
  /// synthetic bytes without going through `image_picker`.
  @visibleForTesting
  static Future<Uint8List> encodeCoverJpegForTest(Uint8List raw) =>
      _encodeCoverJpeg(raw, null);

  /// Decodes the first frame of [raw]: a cover is a still image, and the
  /// frames of an animation add up.
  ///
  /// With [maxPixels] (untrusted bytes), the image is refused before any
  /// pixel is allocated when its canvas or any declared frame exceeds the
  /// cap. An animated WebP is refused outright: each frame's real size sits in
  /// its own bitstream, out of reach of the header read.
  @visibleForTesting
  static img.Image decodeCoverSource(Uint8List raw, {int? maxPixels}) {
    final decoder = img.findDecoderForData(raw);
    final info = decoder?.startDecode(raw);
    if (info != null && maxPixels != null) {
      _checkDeclaredSize(info, maxPixels);
    }
    final decoded = decoder?.decode(raw, frame: 0);
    if (decoded == null) {
      throw const FormatException('Could not decode picked image');
    }
    return decoded;
  }

  static void _checkDeclaredSize(img.DecodeInfo info, int maxPixels) {
    // hasAnimation, not a frame count: a single animation frame already
    // carries its own bitstream, sized independently of the canvas.
    if (info is img.WebPInfo && info.hasAnimation) {
      throw const UnsupportedCoverImageException('animated WebP');
    }
    final sizes = <(int, int)>[
      (info.width, info.height),
      if (info is img.GifInfo) ...info.frames.map((f) => (f.width, f.height)),
      if (info is img.PngInfo) ...info.frames.map((f) => (f.width, f.height)),
    ];
    for (final (w, h) in sizes) {
      if (w * h > maxPixels) throw CoverImageTooLargeException(w, h);
    }
  }

  static Future<Uint8List> _encodeCoverJpeg(Uint8List raw, int? maxPixels) async {
    final decoded = decodeCoverSource(raw, maxPixels: maxPixels);

    // Apply EXIF rotation so portrait shots don't end up sideways on disk.
    // bakeOrientation always copies the image, so only when there is one.
    final ifd = decoded.exif.imageIfd;
    final oriented = ifd.hasOrientation && ifd.orientation != 1
        ? img.bakeOrientation(decoded)
        : decoded;
    // Flattened once small: a full-size canvas would double the memory of a
    // large transparent source.
    final fitted = _flattenOnWhite(
      _fitWithin(oriented, targetMaxWidth, targetMaxHeight),
    );

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

  /// Lays an image with transparency on a white canvas. JPEG has no alpha
  /// channel and the encoder drops it, which turns transparent areas black:
  /// the usual case being a publisher's PNG cover floating on a transparent
  /// background. Opaque images are returned untouched.
  static img.Image _flattenOnWhite(img.Image src) {
    if (!src.hasAlpha) return src;
    // As 8-bit RGBA: compositing ignores the alpha of a grey + alpha image
    // (two channels), which then came out black.
    final rgba = src.numChannels == 4 && src.format == img.Format.uint8
        ? src
        : src.convert(format: img.Format.uint8, numChannels: 4);
    final canvas = img.Image(width: src.width, height: src.height);
    img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
    return img.compositeImage(canvas, rgba);
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
