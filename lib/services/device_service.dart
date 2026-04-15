import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Encapsulates device identification logic for hub directory profiles.
///
/// - [deviceModel]: human-readable hardware model (all platforms)
/// - [deviceFingerprint]: SHA-256 hash of a platform-stable ID (Android/Linux/Windows only)
///
/// On iOS/macOS the keychain persists `library_uuid` across reinstalls,
/// so no fingerprint is needed.
class DeviceService {
  static const _channel = MethodChannel('com.bibliogenius.app/device');

  final _deviceInfo = DeviceInfoPlugin();

  /// Returns a human-readable device model string.
  Future<String?> getDeviceModel() async {
    try {
      if (Platform.isAndroid) {
        final info = await _deviceInfo.androidInfo;
        return info.model; // e.g. "SM-A405FN"
      } else if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        return info.utsname.machine; // e.g. "iPhone14,2"
      } else if (Platform.isMacOS) {
        final info = await _deviceInfo.macOsInfo;
        return info.model; // e.g. "MacBook Pro"
      } else if (Platform.isLinux) {
        final info = await _deviceInfo.linuxInfo;
        return info.prettyName; // e.g. "Ubuntu 22.04"
      } else if (Platform.isWindows) {
        final info = await _deviceInfo.windowsInfo;
        return info.productName; // e.g. "Windows 11"
      }
    } catch (e) {
      debugPrint('DeviceService.getDeviceModel error: $e');
    }
    return null;
  }

  /// Returns a SHA-256 fingerprint for hub profile deduplication.
  ///
  /// - Android: `sha256(ANDROID_ID)` via MethodChannel (survives reinstall)
  /// - iOS: `sha256(identifierForVendor)` (stable per install, resets on reinstall)
  /// - macOS: `sha256(serialNumber)` (stable hardware ID)
  /// - Linux: `sha256(machineId)`
  /// - Windows: `sha256(deviceId)`
  Future<String?> getDeviceFingerprint() async {
    try {
      if (Platform.isAndroid) {
        final androidId = await _channel.invokeMethod<String>('getAndroidId');
        if (androidId != null && androidId.isNotEmpty) {
          return _sha256(androidId);
        }
      } else if (Platform.isIOS) {
        final info = await _deviceInfo.iosInfo;
        final vendorId = info.identifierForVendor;
        if (vendorId != null && vendorId.isNotEmpty) {
          return _sha256(vendorId);
        }
      } else if (Platform.isMacOS) {
        final info = await _deviceInfo.macOsInfo;
        final guid = info.systemGUID;
        if (guid != null && guid.isNotEmpty) {
          return _sha256(guid);
        }
      } else if (Platform.isLinux) {
        final info = await _deviceInfo.linuxInfo;
        if (info.machineId != null && info.machineId!.isNotEmpty) {
          return _sha256(info.machineId!);
        }
      } else if (Platform.isWindows) {
        final info = await _deviceInfo.windowsInfo;
        return _sha256(info.deviceId);
      }
    } catch (e) {
      debugPrint('DeviceService.getDeviceFingerprint error: $e');
    }
    return null;
  }

  /// Returns the client app version reported to the hub (e.g. "0.9.0+422").
  /// Capped at 32 chars to match the hub column width.
  Future<String?> getAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final v = info.buildNumber.isNotEmpty
          ? '${info.version}+${info.buildNumber}'
          : info.version;
      if (v.isEmpty) return null;
      return v.length > 32 ? v.substring(0, 32) : v;
    } catch (e) {
      debugPrint('DeviceService.getAppVersion error: $e');
      return null;
    }
  }

  static String _sha256(String input) {
    return sha256.convert(utf8.encode(input)).toString();
  }
}
