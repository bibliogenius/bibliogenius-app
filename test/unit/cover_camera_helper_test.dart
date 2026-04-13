import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:bibliogenius/utils/cover_camera_helper.dart';

/// Regression + contract tests for cover upload sizing.
///
/// The constants are part of the bandwidth/storage contract with the Rust
/// serve pipeline. Bumping them back up (e.g. to 1200x1800 @ 85) would
/// re-introduce ~2 MB covers on disk and on peer responses. The encoder
/// tests guard against the real-world bug we hit: image_picker silently
/// passes large PNGs through unchanged on macOS, so the helper must do
/// its own decode/resize/encode rather than trusting the picker's hints.
void main() {
  group('CoverCameraHelper constants', () {
    test('target dimensions match the Rust serve target (300x450)', () {
      expect(CoverCameraHelper.targetMaxWidth, 300);
      expect(CoverCameraHelper.targetMaxHeight, 450);
    });

    test('aspect ratio is 2:3 (standard book cover)', () {
      final ratio = CoverCameraHelper.targetMaxWidth /
          CoverCameraHelper.targetMaxHeight;
      expect(ratio, closeTo(2 / 3, 0.01));
    });

    test('JPEG quality matches the Rust default (85)', () {
      expect(CoverCameraHelper.targetQuality, 85);
    });

    test('quality stays in a sensible range to avoid pixelation', () {
      expect(CoverCameraHelper.targetQuality, inInclusiveRange(75, 95));
    });

    test('byte cap matches the Rust soft cap (50 KB)', () {
      expect(CoverCameraHelper.targetMaxBytes, 50 * 1024);
    });
  });

  group('CoverCameraHelper.encodeCoverJpegForTest', () {
    /// Build a deterministic cover-like image with smooth gradients.
    /// Compresses to JPEG at rates comparable to real-world photos.
    img.Image coverLikeImage(int w, int h) {
      final image = img.Image(width: w, height: h);
      for (var y = 0; y < h; y++) {
        final v = y / h;
        for (var x = 0; x < w; x++) {
          final u = x / w;
          final r = (128 + 80 * (u * 3.14159).abs()).clamp(0, 255).toInt();
          final g = (128 + 80 * (v * 6.283).abs()).clamp(0, 255).toInt();
          final b = (128 + 60 * ((u + v) * 3.14159).abs()).clamp(0, 255).toInt();
          image.setPixelRgb(x, y, r, g, b);
        }
      }
      return image;
    }

    test('downscales an oversized PNG to ≤ 300x450 JPEG under cap',
        () async {
      // Mirrors the bug we hit: a large PNG that image_picker would
      // pass through untouched on macOS.
      final big = coverLikeImage(931, 827);
      final pngBytes = Uint8List.fromList(img.encodePng(big));

      final out = await CoverCameraHelper.encodeCoverJpegForTest(pngBytes);

      // Output is JPEG (SOI marker FF D8 FF).
      expect(out.length, greaterThanOrEqualTo(3));
      expect(out[0], 0xFF);
      expect(out[1], 0xD8);
      expect(out[2], 0xFF);

      final decoded = img.decodeJpg(out)!;
      expect(decoded.width, lessThanOrEqualTo(CoverCameraHelper.targetMaxWidth));
      expect(decoded.height,
          lessThanOrEqualTo(CoverCameraHelper.targetMaxHeight));
      expect(out.length, lessThanOrEqualTo(CoverCameraHelper.targetMaxBytes));
    });

    test('preserves aspect ratio (no stretching)', () async {
      final landscape = coverLikeImage(1200, 800);
      final pngBytes = Uint8List.fromList(img.encodePng(landscape));

      final out = await CoverCameraHelper.encodeCoverJpegForTest(pngBytes);
      final decoded = img.decodeJpg(out)!;

      // Original ratio = 1200/800 = 1.5. Allow 1px rounding tolerance.
      final originalRatio = 1200 / 800;
      final outRatio = decoded.width / decoded.height;
      expect(outRatio, closeTo(originalRatio, 0.02));
    });

    test('passes through a small image without enlarging it', () async {
      // Tiny source already under the target box.
      final small = coverLikeImage(120, 180);
      final pngBytes = Uint8List.fromList(img.encodePng(small));

      final out = await CoverCameraHelper.encodeCoverJpegForTest(pngBytes);
      final decoded = img.decodeJpg(out)!;

      expect(decoded.width, 120, reason: 'must not upscale');
      expect(decoded.height, 180, reason: 'must not upscale');
    });

    test('rejects garbage bytes with a clear error', () async {
      final garbage = Uint8List.fromList([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]);
      expect(
        CoverCameraHelper.encodeCoverJpegForTest(garbage),
        throwsA(isA<FormatException>()),
      );
    });

    test('accepts an already-JPEG input and re-encodes under cap', () async {
      final src = coverLikeImage(800, 1200);
      final jpegIn =
          Uint8List.fromList(img.encodeJpg(src, quality: 95));

      final out = await CoverCameraHelper.encodeCoverJpegForTest(jpegIn);

      final decoded = img.decodeJpg(out)!;
      expect(decoded.width, lessThanOrEqualTo(CoverCameraHelper.targetMaxWidth));
      expect(out.length, lessThanOrEqualTo(CoverCameraHelper.targetMaxBytes));
    });
  });
}
