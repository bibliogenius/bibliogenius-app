import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:bibliogenius/services/device_service.dart';

/// Validates the string contract exposed to the hub:
///  - `${version}+${buildNumber}` when build number is present
///  - truncation at 32 chars to match the hub column width
///  - null on empty input (never overwrites a prior stored value)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = DeviceService();

  test('getAppVersion returns "version+buildNumber" when both are present', () async {
    PackageInfo.setMockInitialValues(
      appName: 'BiblioGenius',
      packageName: 'com.federico.bibliogenius',
      version: '0.9.0-alpha.1',
      buildNumber: '422',
      buildSignature: '',
    );

    expect(await service.getAppVersion(), '0.9.0-alpha.1+422');
  });

  test('getAppVersion returns plain version when buildNumber is empty', () async {
    PackageInfo.setMockInitialValues(
      appName: 'BiblioGenius',
      packageName: 'com.federico.bibliogenius',
      version: '0.9.0',
      buildNumber: '',
      buildSignature: '',
    );

    expect(await service.getAppVersion(), '0.9.0');
  });

  test('getAppVersion truncates to 32 chars', () async {
    PackageInfo.setMockInitialValues(
      appName: 'BiblioGenius',
      packageName: 'com.federico.bibliogenius',
      version: '9' * 40,
      buildNumber: '1',
      buildSignature: '',
    );

    final result = await service.getAppVersion();
    expect(result, isNotNull);
    expect(result!.length, lessThanOrEqualTo(32));
  });

  test('getAppVersion returns null on fully empty version', () async {
    PackageInfo.setMockInitialValues(
      appName: 'BiblioGenius',
      packageName: 'com.federico.bibliogenius',
      version: '',
      buildNumber: '',
      buildSignature: '',
    );

    expect(await service.getAppVersion(), isNull);
  });
}
