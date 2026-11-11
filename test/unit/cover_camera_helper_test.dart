import 'dart:io';
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
      final ratio =
          CoverCameraHelper.targetMaxWidth / CoverCameraHelper.targetMaxHeight;
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
          final b = (128 + 60 * ((u + v) * 3.14159).abs())
              .clamp(0, 255)
              .toInt();
          image.setPixelRgb(x, y, r, g, b);
        }
      }
      return image;
    }

    test('downscales an oversized PNG to ≤ 300x450 JPEG under cap', () async {
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
      expect(
        decoded.width,
        lessThanOrEqualTo(CoverCameraHelper.targetMaxWidth),
      );
      expect(
        decoded.height,
        lessThanOrEqualTo(CoverCameraHelper.targetMaxHeight),
      );
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
      final jpegIn = Uint8List.fromList(img.encodeJpg(src, quality: 95));

      final out = await CoverCameraHelper.encodeCoverJpegForTest(jpegIn);

      final decoded = img.decodeJpg(out)!;
      expect(
        decoded.width,
        lessThanOrEqualTo(CoverCameraHelper.targetMaxWidth),
      );
      expect(out.length, lessThanOrEqualTo(CoverCameraHelper.targetMaxBytes));
    });
  });

  group('CoverCameraHelper.writeCoverFile', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('covers_test_');
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    Uint8List bigGif() =>
        Uint8List.fromList(img.encodeGif(img.Image(width: 900, height: 1350)));

    test(
      'saves a web image as <bookId>.jpg through the photo pipeline',
      () async {
        // A GIF stands for the formats a web page serves that a camera never
        // produces: they must come out as the same JPEG thumbnail as a photo.
        final path = await CoverCameraHelper.writeCoverFile(
          Directory('${dir.path}/covers'),
          bigGif(),
          bookId: 'book-1',
        );

        expect(path, '${dir.path}/covers/book-1.jpg');
        final out = await File(path).readAsBytes();
        final decoded = img.decodeJpg(out)!;
        expect(decoded.width, CoverCameraHelper.targetMaxWidth);
        expect(decoded.height, CoverCameraHelper.targetMaxHeight);
        expect(out.length, lessThanOrEqualTo(CoverCameraHelper.targetMaxBytes));
      },
    );

    test('lays a transparent image on white, not on black', () async {
      // JPEG has no alpha: dropping it naively turns transparent areas black.
      // Opaque dots in the corners keep the canvas whole through the crop to
      // opaque pixels, so the transparent area left is inside the cover.
      final src = img.Image(width: 300, height: 450, numChannels: 4);
      img.fill(src, color: img.ColorRgba8(0, 0, 0, 0));
      for (final (x, y) in [(0, 0), (299, 0), (0, 449), (299, 449)]) {
        src.setPixelRgba(x, y, 200, 30, 30, 255);
      }
      img.fillRect(
        src,
        x1: 100,
        y1: 150,
        x2: 200,
        y2: 300,
        color: img.ColorRgba8(200, 30, 30, 255),
      );
      final path = await CoverCameraHelper.writeCoverFile(
        dir,
        Uint8List.fromList(img.encodePng(src)),
        bookId: 'book-1',
      );

      final out = img.decodeJpg(await File(path).readAsBytes())!;
      final corner = out.getPixel(5, 5);
      expect(corner.r, greaterThan(240), reason: 'transparent margin is white');
      expect(corner.g, greaterThan(240));
      expect(corner.b, greaterThan(240));
      final centre = out.getPixel(150, 225);
      expect(centre.r, greaterThan(150), reason: 'the opaque cover is kept');
      expect(centre.g, lessThan(80));
    });

    test('refuses a web image whose dimensions would exhaust memory',
        () async {
      // A tiny file can declare huge dimensions (a flat image compresses to
      // almost nothing): decoding it would allocate gigabytes.
      await expectLater(
        CoverCameraHelper.writeCoverFile(
          dir,
          pngHeaderOnly(20000, 20000),
          bookId: 'book-1',
          maxPixels: CoverCameraHelper.webMaxSourcePixels,
        ),
        throwsA(isA<CoverImageTooLargeException>()),
      );
      expect(await File('${dir.path}/book-1.jpg').exists(), isFalse);
    });

    test('leaves the user\'s own files uncapped', () {
      // A large flatbed scan or a 108 MP photo picked from the gallery was
      // accepted before the web cap existed and must stay so. The header-only
      // fixture then fails in the decoder itself, never at the size check.
      expect(
        () => CoverCameraHelper.decodeCoverSource(pngHeaderOnly(12000, 9000)),
        throwsA(isNot(isA<CoverImageTooLargeException>())),
      );
    });

    test('refuses an animated WebP from the web', () {
      // Each frame's real size is in its own bitstream: the header read
      // cannot bound it.
      expect(
        () => CoverCameraHelper.decodeCoverSource(
          animatedWebpHeaderOnly(),
          maxPixels: CoverCameraHelper.webMaxSourcePixels,
        ),
        throwsA(isA<UnsupportedCoverImageException>()),
      );
      // One frame is enough to carry a bitstream bigger than the canvas.
      expect(
        () => CoverCameraHelper.decodeCoverSource(
          animatedWebpHeaderOnly(frames: 1),
          maxPixels: CoverCameraHelper.webMaxSourcePixels,
        ),
        throwsA(isA<UnsupportedCoverImageException>()),
      );
    });

    test('lays a grey image with transparency on white too', () async {
      // Grey + alpha is two channels: the white canvas used to ignore its
      // alpha, and transparent areas came out black.
      final src = img.Image(width: 300, height: 450, numChannels: 2);
      img.fill(src, color: img.ColorRgba8(0, 0, 0, 0));
      for (final (x, y) in [(0, 0), (299, 0), (0, 449), (299, 449)]) {
        src.setPixelRgba(x, y, 90, 90, 90, 255);
      }
      final path = await CoverCameraHelper.writeCoverFile(
        dir,
        Uint8List.fromList(img.encodePng(src)),
        bookId: 'grey',
      );
      final out = img.decodeJpg(await File(path).readAsBytes())!;
      expect(out.getPixel(150, 225).r, greaterThan(240));
    });

    test('decodes only the first frame of an animation', () async {
      // Each frame of an animated GIF can pass the pixel cap on its own while
      // hundreds of them add up to gigabytes: a cover needs the first one.
      final anim = img.Image(width: 60, height: 90);
      img.fill(anim, color: img.ColorRgb8(200, 30, 30));
      for (var i = 0; i < 4; i++) {
        final frame = img.Image(width: 60, height: 90);
        img.fill(frame, color: img.ColorRgb8(30, 30, 200));
        anim.addFrame(frame);
      }
      final gif = Uint8List.fromList(img.encodeGif(anim));
      expect(img.decodeGif(gif)!.numFrames, 5, reason: 'fixture is animated');

      final decoded = CoverCameraHelper.decodeCoverSource(gif);
      expect(decoded.numFrames, 1);
      expect(decoded.getPixel(30, 45).r, greaterThan(150), reason: 'frame 0');
    });

    test('crops a 16-bit mockup and keeps a half-transparent edge', () async {
      // 16-bit alpha runs to 65535: a raw threshold of 200 read the shadow as
      // opaque. And a cover whose edge fades to 60 % opacity keeps that edge.
      final src = img.Image(
        width: 1200,
        height: 1200,
        numChannels: 4,
        format: img.Format.uint16,
      );
      // Pixels written as is: fillRect would blend a translucent colour
      // into the transparent canvas and leave its alpha at zero.
      void paint(int x1, int y1, int x2, int y2, List<int> rgba) {
        for (var y = y1; y <= y2; y++) {
          for (var x = x1; x <= x2; x++) {
            src.setPixelRgba(x, y, rgba[0], rgba[1], rgba[2], rgba[3]);
          }
        }
      }

      paint(240, 340, 659, 959, [0, 0, 0, 15000]); // shadow, about 23 %
      paint(200, 300, 599, 899, [52000, 8000, 8000, 65535]);
      paint(200, 300, 599, 309, [52000, 8000, 8000, 39000]); // 60 % edge
      final path = await CoverCameraHelper.writeCoverFile(
        dir,
        Uint8List.fromList(img.encodePng(src)),
        bookId: 'book-16',
      );
      final out = img.decodeJpg(await File(path).readAsBytes())!;
      expect(out.width, CoverCameraHelper.targetMaxWidth);
      expect(out.height, CoverCameraHelper.targetMaxHeight);
      expect(out.getPixel(150, 1).r, greaterThan(150), reason: 'edge kept');
    });

    test('crops a mockup down to the opaque cover', () async {
      // Shape of a publisher mockup: the cover floats on a transparent canvas
      // with a semi-transparent drop shadow. Kept whole, it shrinks to a small
      // book in the middle of the thumbnail.
      final src = img.Image(width: 1200, height: 1200, numChannels: 4);
      img.fill(src, color: img.ColorRgba8(0, 0, 0, 0));
      img.fillRect(
        src,
        x1: 240,
        y1: 340,
        x2: 659,
        y2: 959,
        color: img.ColorRgba8(0, 0, 0, 60),
      );
      img.fillRect(
        src,
        x1: 200,
        y1: 300,
        x2: 599,
        y2: 899,
        color: img.ColorRgba8(200, 30, 30, 255),
      );
      final path = await CoverCameraHelper.writeCoverFile(
        dir,
        Uint8List.fromList(img.encodePng(src)),
        bookId: 'book-1',
      );

      final out = img.decodeJpg(await File(path).readAsBytes())!;
      expect(out.width, CoverCameraHelper.targetMaxWidth);
      expect(out.height, CoverCameraHelper.targetMaxHeight);
      for (final (x, y) in [(5, 5), (294, 5), (5, 444), (294, 444)]) {
        expect(out.getPixel(x, y).r, greaterThan(150), reason: 'cover at $x,$y');
        expect(out.getPixel(x, y).g, lessThan(80), reason: 'not white at $x,$y');
      }
    });

    test('leaves a fully transparent image to the white flattening', () async {
      final src = img.Image(width: 200, height: 300, numChannels: 4);
      img.fill(src, color: img.ColorRgba8(0, 0, 0, 0));
      final path = await CoverCameraHelper.writeCoverFile(
        dir,
        Uint8List.fromList(img.encodePng(src)),
      );
      final out = img.decodeJpg(await File(path).readAsBytes())!;
      expect(out.getPixel(10, 10).r, greaterThan(240));
    });

    test('uses a temp name while the book has no id yet', () async {
      final path = await CoverCameraHelper.writeCoverFile(dir, bigGif());
      expect(path.split('/').last, startsWith('temp_'));
      expect(await File(path).exists(), isTrue);
    });

    test('writes nothing when the bytes are not an image', () async {
      await expectLater(
        CoverCameraHelper.writeCoverFile(
          dir,
          Uint8List.fromList('<svg/>'.codeUnits),
          bookId: 'book-1',
        ),
        throwsA(isA<FormatException>()),
      );
      expect(await File('${dir.path}/book-1.jpg').exists(), isFalse);
    });
  });
}

/// A PNG made of its signature, an IHDR declaring [width] x [height] and an
/// IEND: enough for a decoder to read the dimensions, with no pixel data.
Uint8List pngHeaderOnly(int width, int height) {
  int crc32(List<int> bytes) {
    var crc = 0xFFFFFFFF;
    for (final b in bytes) {
      crc ^= b;
      for (var k = 0; k < 8; k++) {
        crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
      }
    }
    return crc ^ 0xFFFFFFFF;
  }

  List<int> be32(int v) => [v >> 24 & 0xFF, v >> 16 & 0xFF, v >> 8 & 0xFF, v & 0xFF];
  List<int> chunk(String type, List<int> data) {
    final body = [...type.codeUnits, ...data];
    return [...be32(data.length), ...body, ...be32(crc32(body))];
  }

  return Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    ...chunk('IHDR', [...be32(width), ...be32(height), 8, 6, 0, 0, 0]),
    ...chunk('IEND', const []),
  ]);
}

/// A WebP made of a VP8X header flagged as animated, an ANIM chunk and two
/// empty ANMF frames: enough for the decoder to report an animation.
Uint8List animatedWebpHeaderOnly({int frames = 2}) {
  List<int> le24(int v) => [v & 0xFF, v >> 8 & 0xFF, v >> 16 & 0xFF];
  List<int> le32(int v) => [...le24(v), v >> 24 & 0xFF];
  List<int> chunk(String type, List<int> data) => [
    ...type.codeUnits,
    ...le32(data.length),
    ...data,
    if (data.length.isOdd) 0,
  ];

  final frame = [...le24(0), ...le24(0), ...le24(0), ...le24(0), ...le24(100), 0];
  final body = [
    ...'WEBP'.codeUnits,
    ...chunk('VP8X', [0x02, 0, 0, 0, ...le24(0), ...le24(0)]),
    ...chunk('ANIM', [0, 0, 0, 0, 0, 0]),
    for (var i = 0; i < frames; i++) ...chunk('ANMF', frame),
  ];
  return Uint8List.fromList([...'RIFF'.codeUnits, ...le32(body.length), ...body]);
}
