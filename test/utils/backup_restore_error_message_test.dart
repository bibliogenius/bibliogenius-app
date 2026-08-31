import 'package:flutter_test/flutter_test.dart';
import 'package:bibliogenius/utils/backup_actions.dart';

/// The restore path turns the code [ApiService.importBackup] returns into the
/// one sentence the user gets. That translation, not the request itself, is
/// what a failed restore is judged on.
void main() {
  const messages = {
    'unreadable_file': 'unreadable',
    'incompatible_backup': 'incompatible',
    'network_error': 'unreachable',
    'generic': 'failed ({error})',
  };

  group('BackupActions.restoreErrorMessage', () {
    test('each known code gets its own message', () {
      for (final code in const [
        'unreadable_file',
        'incompatible_backup',
        'network_error',
      ]) {
        expect(
          BackupActions.restoreErrorMessage(messages, {'error': code}, '500'),
          messages[code],
          reason: 'code $code',
        );
      }
    });

    test('a code with no message of its own falls back to the status', () {
      expect(
        BackupActions.restoreErrorMessage(
          messages,
          {'error': 'server_error'},
          '500',
        ),
        'failed (500)',
      );
    });

    test('a body that is not a map falls back too', () {
      expect(
        BackupActions.restoreErrorMessage(messages, 'plain text', '503'),
        'failed (503)',
      );
    });

    test('no body at all falls back to the exception text', () {
      expect(
        BackupActions.restoreErrorMessage(messages, null, 'PathNotFound'),
        'failed (PathNotFound)',
      );
    });
  });
}
