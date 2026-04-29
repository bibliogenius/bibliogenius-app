// Pin tests for the local-backup restore wizard (ADR-037 §5).
//
// Full behavioral coverage of the wizard (preview -> secret -> mode -> ...)
// requires mocking both flutter_rust_bridge (for FFI calls) and
// `ThemeProvider` (for `TranslationService.translate`). That is a wider
// architectural addition than this PR carries; downstream behavior is
// covered by Rust integration tests in
// `bibliogenius/tests/backup_restore_test.rs` (read_manifest,
// verify_signature, Replace/Merge round-trips). The Flutter side is a thin
// orchestrator over those FFI calls.
//
// Here we lock the one invariant a future code change is most likely to
// silently break: the prefs whitelist must mirror the writer's.
import 'package:flutter_test/flutter_test.dart';

import 'package:bibliogenius/screens/backup_restore_wizard_screen.dart';

void main() {
  test('kBackupPrefsWhitelist matches the writer whitelist exactly', () {
    // The reader's whitelist must mirror the writer (BackupActions.runFullBackup
    // in lib/utils/backup_actions.dart uses the same three keys). PR #4 will
    // formalize this in Rust with a drift test; until then this constant
    // pin avoids a silent reader/writer divergence.
    expect(
      kBackupPrefsWhitelist,
      equals(<String>['themeStyle', 'languageCode', 'country']),
    );
  });
}
