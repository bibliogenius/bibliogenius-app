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
// silently break: the prefs whitelist must mirror the writer's. PR #4
// moved the whitelist into `backup_prefs_whitelist.dart` and added a
// drift test; this pin now just guards the v1 contents.
import 'package:bibliogenius/services/backup_prefs_whitelist.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('kBackupPrefsWhitelist contains exactly the v1 user-meaningful keys',
      () {
    expect(
      kBackupPrefsWhitelist,
      equals(<String>{'themeStyle', 'languageCode', 'country'}),
    );
  });
}
