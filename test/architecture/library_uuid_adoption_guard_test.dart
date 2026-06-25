// Architecture guard for ADR-042 §13.3 (cross-device identity invariant).
//
// `library_uuid` is the Argon2 passphrase that encrypts the device identity
// (`crypto_keys`, see identity_service.rs). Adopting ANOTHER device's
// `library_uuid` makes the local `crypto_keys` undecryptable (identity reset)
// and, under the account-sync model, collides two devices on a single hub lane
// `(opaque_id, device_id)`. ADR-039 (Option B) removed the only pairing path
// that adopted `library_uuid` (the orphan `link_device_screen`).
//
// This guard fails if any code path writes or clears `library_uuid` outside the
// two legitimate writers, so a future pairing/sync flow cannot silently
// re-introduce the adoption hazard. It is a textual scan of `lib/`, deliberately
// conservative: any new writer must be reviewed and explicitly allowlisted.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // The ONLY files allowed to mutate `library_uuid` in the secure stores:
  //  - auth_service.dart: defines the mutators and the boot reconcile path.
  //  - backup_restore_wizard_screen.dart: restore (ADR-037), an explicit,
  //    user-driven migration/clone covered by the matrix in ADR-042 §13.2.
  const allowlist = <String>{
    'lib/services/auth_service.dart',
    'lib/screens/backup_restore_wizard_screen.dart',
  };

  // Calls that WRITE or CLEAR a specific `library_uuid` value (the adoption
  // surface). `getOrCreateLibraryUuid` is intentionally excluded: it is a
  // read-accessor that mints the device's OWN uuid on a miss, never adopting a
  // foreign one, and is called from many legitimate sites.
  final mutatorCall = RegExp(
    r'\b(setLibraryUuidDualWrite|setLibraryUuid|clearLibraryUuidBothStores)\s*\(',
  );

  test('library_uuid mutators stay confined to the allowlist (ADR-042 §13.3)', () {
    final libDir = Directory('lib');
    expect(
      libDir.existsSync(),
      isTrue,
      reason: 'Guard must run from the package root (where lib/ lives). '
          'Run it via `flutter test`.',
    );

    final dartFiles = libDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    String rel(File f) => f.path.replaceAll(r'\', '/');

    // Self-check: the scan actually reached the source tree, so an empty
    // `offenders` means "no offenders", not "scanned nothing".
    expect(
      dartFiles.any((f) => rel(f) == 'lib/services/auth_service.dart'),
      isTrue,
      reason: 'Scan did not find auth_service.dart; the working directory or '
          'lib/ layout changed and the guard would pass vacuously.',
    );

    final offenders = <String>[
      for (final f in dartFiles)
        if (!allowlist.contains(rel(f)) && mutatorCall.hasMatch(f.readAsStringSync()))
          rel(f),
    ]..sort();

    expect(
      offenders,
      isEmpty,
      reason: 'These files write or clear library_uuid outside the allowlist, '
          'which is the cross-device identity adoption hazard (ADR-042 §13.3, '
          'ADR-039 Option B). A pairing/sync path must NEVER adopt another '
          "device's library_uuid. If this is a genuinely new legitimate writer, "
          'add it to the allowlist in this test with a justification:\n'
          '${offenders.join('\n')}',
    );
  });
}
