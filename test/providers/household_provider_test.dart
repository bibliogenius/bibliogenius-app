import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bibliogenius/providers/household_provider.dart';
import 'package:bibliogenius/services/ffi_service.dart';
import 'package:bibliogenius/src/rust/api/frb.dart'
    show FrbReader, FrbReadingImportReport;

/// Fake FFI holding the readers in memory, the way the Rust side does.
class _FakeFfi extends FfiService {
  _FakeFfi() : super.forTest();

  final List<FrbReader> readers = [];
  String? currentId;
  Object? failWith;

  void _maybeFail() {
    if (failWith != null) throw failWith!;
  }

  @override
  Future<FrbReadingImportReport> importHouseholdReadings(String json) async {
    _maybeFail();
    return const FrbReadingImportReport(
      matched: 1,
      created: 2,
      ambiguous: 0,
      ambiguousTitles: [],
      skipped: 0,
    );
  }

  @override
  Future<List<FrbReader>> listHouseholdReaders() async {
    _maybeFail();
    return List.of(readers);
  }

  @override
  Future<FrbReader?> getCurrentHouseholdReader() async {
    for (final r in readers) {
      if (r.id == currentId) return r;
    }
    return null;
  }

  @override
  Future<FrbReader> createHouseholdReader(String name) async {
    _maybeFail();
    final reader = FrbReader(id: 'r${readers.length + 1}', name: name);
    readers.add(reader);
    currentId = reader.id;
    return reader;
  }

  @override
  Future<void> setCurrentHouseholdReader(String readerId) async {
    _maybeFail();
    currentId = readerId;
  }

  @override
  Future<void> clearCurrentHouseholdReader() async {
    _maybeFail();
    currentId = null;
  }

  @override
  Future<void> renameHouseholdReader(String readerId, String name) async {
    _maybeFail();
    final i = readers.indexWhere((r) => r.id == readerId);
    readers[i] = FrbReader(id: readerId, name: name);
  }

  @override
  Future<void> deleteHouseholdReader(String readerId) async {
    _maybeFail();
    readers.removeWhere((r) => r.id == readerId);
    if (currentId == readerId) currentId = null;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('a device with no readers has nothing to choose', () async {
    final ffi = _FakeFfi();
    final provider = HouseholdProvider(ffi: ffi);
    await provider.load();
    expect(provider.isLoaded, isTrue);
    expect(provider.readers, isEmpty);
    expect(provider.needsReaderChoice, isFalse);
  });

  // The other device created the readers; this one is still on the shared
  // state and should be invited to pick one.
  test('readers without a current one call for a choice', () async {
    final ffi = _FakeFfi()
      ..readers.addAll(const [
        FrbReader(id: 'r1', name: 'Alice'),
        FrbReader(id: 'r2', name: 'Bruno'),
      ]);
    final provider = HouseholdProvider(ffi: ffi);
    await provider.load();
    expect(provider.needsReaderChoice, isTrue);

    expect(await provider.selectReader('r2'), isTrue);
    expect(provider.currentReader?.name, 'Bruno');
    expect(provider.needsReaderChoice, isFalse);

    // Stepping back to the shared view is a choice too: the invitation
    // must not come back, on this launch or the next.
    expect(await provider.leaveReader(), isTrue);
    expect(provider.currentReaderId, isNull);
    expect(provider.readers, hasLength(2));
    expect(provider.needsReaderChoice, isFalse);
    final relaunched = HouseholdProvider(ffi: ffi);
    await relaunched.load();
    expect(relaunched.needsReaderChoice, isFalse);

    // Picking a reader again re-arms the invitation for a later step back.
    expect(await relaunched.selectReader('r1'), isTrue);
    expect(relaunched.needsReaderChoice, isFalse);
  });

  test('importing readings hands back the report, or the refusal', () async {
    final ffi = _FakeFfi();
    final provider = HouseholdProvider(ffi: ffi);
    await provider.load();

    final report = await provider.importReadings('{}');
    expect(report.created, 2);
    expect(provider.busy, isFalse);

    // The backend's message is what the summary shows: it must come through,
    // and the provider must not stay busy behind it.
    ffi.failWith = 'Unreadable catalogue export';
    await expectLater(
      provider.importReadings('{}'),
      throwsA('Unreadable catalogue export'),
    );
    expect(provider.busy, isFalse);
  });

  test('creating and renaming a reader keep the list current', () async {
    final ffi = _FakeFfi();
    final provider = HouseholdProvider(ffi: ffi);
    await provider.load();

    expect(await provider.createReader('Alice'), isTrue);
    expect(provider.currentReader?.name, 'Alice');

    expect(await provider.renameReader('r1', 'Alicia'), isTrue);
    expect(provider.currentReader?.name, 'Alicia');
  });

  test(
    'deleting the chosen reader puts the device on the shared view',
    () async {
      final ffi = _FakeFfi()
        ..readers.addAll(const [
          FrbReader(id: 'r1', name: 'Alice'),
          FrbReader(id: 'r2', name: 'Bruno'),
        ])
        ..currentId = 'r1';
      final provider = HouseholdProvider(ffi: ffi);
      await provider.load();

      expect(await provider.deleteReader('r1'), isTrue);
      expect(provider.readers.single.name, 'Bruno');
      expect(provider.currentReaderId, isNull);
      // Not a choice to stay on the shared view: the invitation may show.
      expect(provider.needsReaderChoice, isTrue);
    },
  );

  test('a refused change reports false and reloads what holds', () async {
    final ffi = _FakeFfi()
      ..readers.add(const FrbReader(id: 'r1', name: 'Alice'));
    final provider = HouseholdProvider(ffi: ffi);
    await provider.load();

    ffi.failWith = StateError('too long');
    expect(await provider.renameReader('r1', 'x' * 80), isFalse);
    expect(provider.busy, isFalse);
    ffi.failWith = null;
    await provider.load();
    expect(provider.readers.single.name, 'Alice');
  });

  test('a failing backend leaves the device on the shared state', () async {
    final ffi = _FakeFfi()..failWith = StateError('no ffi');
    final provider = HouseholdProvider(ffi: ffi);
    await provider.load();
    expect(provider.isLoaded, isTrue);
    expect(provider.readers, isEmpty);
    expect(provider.needsReaderChoice, isFalse);
  });
}
