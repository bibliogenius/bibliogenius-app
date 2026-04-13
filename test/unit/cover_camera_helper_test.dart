import 'package:flutter_test/flutter_test.dart';
import 'package:bibliogenius/utils/cover_camera_helper.dart';

/// Regression guard: the cover upload dimensions and quality are part of the
/// bandwidth/storage contract with the Rust serve pipeline. Bumping them back
/// up (e.g. to 1200x1800 @ 85) would re-introduce ~2 MB covers on disk and
/// on peer responses. This test locks the agreed-upon values.
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
  });
}
