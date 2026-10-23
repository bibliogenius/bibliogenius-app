import 'package:bibliogenius/utils/cover_camera_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

// On Android the document scanner ships with Google Play services, so the
// helper asks the platform before using it. A "yes" holds for the life of
// the process; a "no" may be temporary (Play services updating, channel
// error), so the next capture asks again instead of keeping the plain
// camera until a restart. Kept in its own file: the answer is cached in a
// static for the whole test isolate.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.bibliogenius.app/device');

  test(
    'asks Play services on Android and keeps only a positive answer',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      var calls = 0;
      Object? answer = false;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'isGooglePlayServicesAvailable');
        calls++;
        if (answer is Exception) throw answer;
        return answer;
      });

      expect(await CoverCameraHelper.isDocumentScannerAvailable(), isFalse);

      answer = PlatformException(code: 'boom');
      expect(await CoverCameraHelper.isDocumentScannerAvailable(), isFalse);

      answer = true;
      expect(await CoverCameraHelper.isDocumentScannerAvailable(), isTrue);

      answer = false;
      expect(await CoverCameraHelper.isDocumentScannerAvailable(), isTrue);
      expect(calls, 3);
    },
  );
}
