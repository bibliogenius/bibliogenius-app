import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/services/device_service.dart';

/// Pins the fingerprint contract exposed to the hub:
///  - release builds report exactly sha256(platform id), byte for byte what
///    every shipped version already sends, so no published profile changes
///  - non-release builds report a different, still deterministic, fingerprint
///    so a `flutter run` build never collides with the store build installed
///    on the same machine (the hub deletes the other profile on collision)
///  - both stay 64 lowercase hex chars, the format the hub validates
void main() {
  const platformId = '8D5E1F2A-1B2C-4D3E-9F0A-ABCDEF123456';
  final plainSha256 = sha256.convert(utf8.encode(platformId)).toString();
  final hex64 = RegExp(r'^[0-9a-f]{64}$');

  test('release build fingerprint is the plain sha256 of the platform id', () {
    expect(
      DeviceService.fingerprintFor(platformId, releaseBuild: true),
      plainSha256,
    );
  });

  test('non-release build fingerprint differs from the release one', () {
    final dev = DeviceService.fingerprintFor(platformId, releaseBuild: false);
    expect(dev, isNot(plainSha256));
    expect(dev, matches(hex64));
  });

  test('non-release build fingerprint is stable across calls', () {
    expect(
      DeviceService.fingerprintFor(platformId, releaseBuild: false),
      DeviceService.fingerprintFor(platformId, releaseBuild: false),
    );
  });

  test('default mode under flutter test is the non-release path', () {
    // kReleaseMode is false in tests: the default must take the salted
    // branch, which is what a `flutter run` build gets.
    expect(
      DeviceService.fingerprintFor(platformId),
      DeviceService.fingerprintFor(platformId, releaseBuild: false),
    );
  });
}
