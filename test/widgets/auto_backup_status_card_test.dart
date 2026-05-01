import 'dart:io';

import 'package:bibliogenius/providers/theme_provider.dart';
import 'package:bibliogenius/services/auth_service.dart';
import 'package:bibliogenius/services/backup_scheduler_service.dart';
import 'package:bibliogenius/services/translation_service.dart';
import 'package:bibliogenius/widgets/auto_backup_status_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The badge reads the wall clock directly (`DateTime.now()`); plumbing
  // a clock callback through the widget tree just for tests is more
  // ceremony than the value justifies. Tests therefore anchor the
  // archive timestamp to wall-clock `DateTime.now()` at setUp time, and
  // rely on Duration arithmetic being deterministic enough that
  // `now() - (now() - 1 day)` round-trips to exactly 1 day in the
  // formatted output.
  late DateTime now;
  late SharedPreferences prefs;
  late AuthService auth;
  late ThemeProvider themeProvider;
  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    auth = AuthService();
    themeProvider = ThemeProvider();
    tmp = await Directory.systemTemp.createTemp('bg-card-test-');
    now = DateTime.now();

    // Inject just the PO entries the badge + bottom sheet read. Other
    // entries fall through to the key as-is, which is fine for tests.
    TranslationService.setPoTranslationsForTest({
      'en': {
        'auto_backup_status_title_never': 'No backup yet',
        'auto_backup_status_title_with_age': 'Last backup: {age}',
        'auto_backup_status_subtitle_amber': 'Check the auto-backup.',
        'auto_backup_status_subtitle_red': 'Not protected recently.',
        'auto_backup_status_subtitle_disabled': 'Auto-backup disabled.',
        'auto_backup_status_subtitle_never_enabled': 'First archive coming soon.',
        'auto_backup_age_minutes': '{n} min ago',
        'auto_backup_age_hours': '{n} h ago',
        'auto_backup_age_days': '{n} d ago',
        'auto_backup_sheet_title': 'Automatic backup',
        'auto_backup_sheet_toggle_label': 'Automatic backup every 24h',
        'auto_backup_sheet_toggle_subtitle': 'Daily encrypted archive.',
        'auto_backup_sheet_run_now': 'Back up now',
        'auto_backup_sheet_section_archives': 'Auto-backups on this device',
        'auto_backup_sheet_no_archives': 'No auto-backup yet.',
      },
    });
  });

  tearDown(() async {
    TranslationService.setPoTranslationsForTest({});
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  /// Build a scheduler with deps wired to no-ops, anchored at [now].
  BackupSchedulerService buildScheduler() {
    return BackupSchedulerService(
      prefs: prefs,
      authService: auth,
      clock: () => now,
      probeWatermark: () async => 'wm-test',
      runBackup: (_) async => const BackupRunResult(
        archivePath: 'unused',
        archiveSizeBytes: 0,
      ),
      resolveBackupsDir: () async => tmp,
    );
  }

  Widget wrap(BackupSchedulerService scheduler) {
    // Providers sit ABOVE MaterialApp so the bottom sheet (pushed onto
    // the root Navigator and therefore a sibling of `home:`) still
    // inherits them. Wrapping below MaterialApp leaves the modal route
    // without a Provider ancestor and the sheet build crashes.
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeProvider>.value(value: themeProvider),
        Provider<AuthService>.value(value: auth),
        ChangeNotifierProvider<BackupSchedulerService>.value(value: scheduler),
      ],
      child: const MaterialApp(
        home: Scaffold(body: AutoBackupStatusCard()),
      ),
    );
  }

  testWidgets('vert: recent backup (1 day) shows green badge with age',
      (tester) async {
    await prefs.setString(
      'auto_backup_last_ts',
      now.subtract(const Duration(days: 1)).toIso8601String(),
    );
    final scheduler = buildScheduler();
    addTearDown(scheduler.dispose);

    await tester.pumpWidget(wrap(scheduler));
    await tester.pump();

    expect(find.text('Last backup: 1 d ago'), findsOneWidget);
    // Green state has no subtitle (only amber/red/never do).
    expect(find.text('Check the auto-backup.'), findsNothing);
    expect(find.text('Not protected recently.'), findsNothing);

    final icon = tester.widget<Icon>(find.byIcon(Icons.check_circle_outline));
    expect(icon, isNotNull);
  });

  testWidgets('amber: 12-day-old backup surfaces the warning subtitle',
      (tester) async {
    await prefs.setString(
      'auto_backup_last_ts',
      now.subtract(const Duration(days: 12)).toIso8601String(),
    );
    final scheduler = buildScheduler();
    addTearDown(scheduler.dispose);

    await tester.pumpWidget(wrap(scheduler));
    await tester.pump();

    expect(find.text('Last backup: 12 d ago'), findsOneWidget);
    expect(find.text('Check the auto-backup.'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber), findsOneWidget);
  });

  testWidgets('rouge: 45-day-old backup surfaces the red subtitle',
      (tester) async {
    await prefs.setString(
      'auto_backup_last_ts',
      now.subtract(const Duration(days: 45)).toIso8601String(),
    );
    final scheduler = buildScheduler();
    addTearDown(scheduler.dispose);

    await tester.pumpWidget(wrap(scheduler));
    await tester.pump();

    expect(find.text('Last backup: 45 d ago'), findsOneWidget);
    expect(find.text('Not protected recently.'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('never: no timestamp shows the "no backup yet" title',
      (tester) async {
    final scheduler = buildScheduler();
    addTearDown(scheduler.dispose);

    await tester.pumpWidget(wrap(scheduler));
    await tester.pump();

    expect(find.text('No backup yet'), findsOneWidget);
    // Default disabled state -> the disabled subtitle copy.
    expect(find.text('Auto-backup disabled.'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('tap opens the bottom sheet with the toggle and run-now action',
      (tester) async {
    await prefs.setString(
      'auto_backup_last_ts',
      now.subtract(const Duration(days: 2)).toIso8601String(),
    );
    final scheduler = buildScheduler();
    addTearDown(scheduler.dispose);

    await tester.pumpWidget(wrap(scheduler));
    await tester.pump();

    await tester.tap(find.byType(AutoBackupStatusCard));
    // Cannot use pumpAndSettle: the sheet's loading state shows a
    // CircularProgressIndicator whose ticker never quiesces. We pump
    // enough frames to let the open animation finish; assertions cover
    // the always-rendered chrome of the sheet (header, toggle, run-now)
    // rather than the post-_refresh archive list, which races against
    // path_provider/FFI test-environment failures.
    await tester.pump(); // start the modal open animation
    await tester.pump(const Duration(milliseconds: 400)); // animation done

    expect(find.text('Automatic backup'), findsOneWidget);
    expect(find.text('Automatic backup every 24h'), findsOneWidget);
    expect(find.text('Back up now'), findsOneWidget);
    expect(
      find.byType(SwitchListTile),
      findsOneWidget,
      reason: 'the auto-backup toggle is the primary control of the sheet',
    );
  });
}
