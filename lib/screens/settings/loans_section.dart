import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/translation_service.dart';
import '../../providers/theme_provider.dart';
import '../../services/ffi_service.dart';
import 'settings_scope.dart';
import 'settings_widgets.dart';

/// Loans accordion: lending and borrowing, and how loans behave.
class LoansSettingsSection extends StatefulWidget {
  const LoansSettingsSection({super.key});

  @override
  State<LoansSettingsSection> createState() => _LoansSettingsSectionState();
}

class _LoansSettingsSectionState extends State<LoansSettingsSection> {
  int _defaultLoanDurationDays = 21;
  bool _perBookDurationEnabled = false;
  int _reminderDaysBeforeDue = 2;
  bool _loanSettingsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadLoanSettings();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    if (!settingsMatches(context, [
      'modules_group_lending',
      'enable_lending_module',
      'lending_module_desc',
      'enable_borrowing_module',
      'borrowing_module_desc',
      'auto_approve_loans_title',
      'auto_approve_loans_desc',
      'loan_duration_settings_title',
      'loan_duration_default_label',
      'loan_duration_per_book_toggle',
      'loan_reminder_days_label',
      if (themeProvider.networkEnabled) ...[
        'settings_allow_private_books',
        'settings_allow_private_books_desc',
      ],
    ])) {
      return const SizedBox.shrink();
    }
    return SettingsAccordion(
      name: 'loans',
      icon: Icons.handshake_outlined,
      titleKey: 'modules_group_lending',
      children: [
        SettingsToggleCard(
          titleKey: 'enable_lending_module',
          descKey: 'lending_module_desc',
          icon: Icons.handshake_outlined,
          value: themeProvider.canLendBooks,
          onChanged: (value) => themeProvider.setCanLendBooks(value),
          helpTopicId: 'enable_lending',
        ),
        SettingsToggleCard(
          titleKey: 'enable_borrowing_module',
          descKey: 'borrowing_module_desc',
          icon: Icons.swap_horiz,
          value: themeProvider.canBorrowBooks,
          onChanged: (value) => themeProvider.setCanBorrowBooks(value),
          helpTopicId: 'enable_borrowing',
        ),
        SettingsToggleCard(
          titleKey: 'auto_approve_loans_title',
          descKey: 'auto_approve_loans_desc',
          icon: Icons.auto_awesome,
          value: themeProvider.autoApproveLoanRequests,
          onChanged: (value) => themeProvider.setAutoApproveLoanRequests(value),
          helpTopicId: 'auto_approve_loans',
        ),
        if (_loanSettingsLoaded) _buildLoanDurationSection(context),
        if (themeProvider.networkEnabled)
          SettingsToggleCard(
            titleKey: 'settings_allow_private_books',
            descKey: 'settings_allow_private_books_desc',
            icon: Icons.visibility_off,
            value: themeProvider.allowPrivateBooks,
            onChanged: (value) => themeProvider.setAllowPrivateBooks(value),
            helpTopicId: 'allow_private_books',
          ),
      ],
    );
  }

  Future<void> _loadLoanSettings() async {
    try {
      final ffi = FfiService();
      final settings = await ffi.getLoanSettings();
      if (mounted) {
        setState(() {
          _defaultLoanDurationDays = settings.defaultLoanDurationDays;
          _perBookDurationEnabled = settings.perBookDurationEnabled;
          _reminderDaysBeforeDue = settings.reminderDaysBeforeDue;
          _loanSettingsLoaded = true;
        });
      }
      return;
    } catch (e) {
      debugPrint('Error loading loan settings: $e');
    }
    // Show section with defaults even if FFI fails
    if (mounted) {
      setState(() => _loanSettingsLoaded = true);
    }
  }

  Widget _buildLoanDurationSection(BuildContext context) {
    if (!settingsMatches(context, [
      'loan_duration_settings_title',
      'loan_duration_default_label',
      'loan_duration_per_book_toggle',
      'loan_reminder_days_label',
    ])) {
      return const SizedBox.shrink();
    }

    final daysLabel = TranslationService.translate(
      context,
      'loan_duration_days_suffix',
    );

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: [
            // Global default duration stepper
            Row(
              children: [
                const Icon(Icons.timer_outlined),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    TranslationService.translate(
                      context,
                      'loan_duration_default_label',
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  tooltip: TranslationService.translate(
                    context,
                    'decrease_by_one',
                  ),
                  onPressed: _defaultLoanDurationDays > 1
                      ? () => _updateLoanDuration(_defaultLoanDurationDays - 1)
                      : null,
                ),
                GestureDetector(
                  // A shortcut for sighted users; the − and + buttons on
                  // either side are what a screen reader offers.
                  excludeFromSemantics: true,
                  onLongPress: () {
                    final newVal = (_defaultLoanDurationDays - 7).clamp(1, 365);
                    _updateLoanDuration(newVal);
                  },
                  child: SizedBox(
                    width: 80,
                    child: Text(
                      '$_defaultLoanDurationDays $daysLabel',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: TranslationService.translate(
                    context,
                    'increase_by_one',
                  ),
                  onPressed: _defaultLoanDurationDays < 365
                      ? () => _updateLoanDuration(_defaultLoanDurationDays + 1)
                      : null,
                ),
              ],
            ),
            const Divider(),
            // Per-book toggle
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.auto_stories),
              title: Text(
                TranslationService.translate(
                  context,
                  'loan_duration_per_book_toggle',
                ),
              ),
              subtitle: Text(
                TranslationService.translate(
                  context,
                  'loan_duration_per_book_desc',
                ),
              ),
              value: _perBookDurationEnabled,
              onChanged: (value) => _updatePerBookToggle(value),
            ),
            const Divider(),
            // Reminder days stepper
            Row(
              children: [
                const Icon(Icons.notifications_outlined),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    TranslationService.translate(
                      context,
                      'loan_reminder_days_label',
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  tooltip: TranslationService.translate(
                    context,
                    'decrease_by_one',
                  ),
                  onPressed: _reminderDaysBeforeDue > 1
                      ? () => _updateReminderDays(_reminderDaysBeforeDue - 1)
                      : null,
                ),
                SizedBox(
                  width: 80,
                  child: Text(
                    '$_reminderDaysBeforeDue $daysLabel',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: TranslationService.translate(
                    context,
                    'increase_by_one',
                  ),
                  onPressed: _reminderDaysBeforeDue < 10
                      ? () => _updateReminderDays(_reminderDaysBeforeDue + 1)
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateLoanDuration(int days) async {
    setState(() => _defaultLoanDurationDays = days);
    try {
      final ffi = FfiService();
      await ffi.updateLoanSettings(
        defaultLoanDurationDays: days,
        perBookDurationEnabled: _perBookDurationEnabled,
        reminderDaysBeforeDue: _reminderDaysBeforeDue,
      );
    } catch (e) {
      debugPrint('Error updating loan duration: $e');
    }
  }

  Future<void> _updatePerBookToggle(bool enabled) async {
    setState(() => _perBookDurationEnabled = enabled);
    try {
      final ffi = FfiService();
      await ffi.updateLoanSettings(
        defaultLoanDurationDays: _defaultLoanDurationDays,
        perBookDurationEnabled: enabled,
        reminderDaysBeforeDue: _reminderDaysBeforeDue,
      );
    } catch (e) {
      debugPrint('Error updating per-book toggle: $e');
    }
  }

  Future<void> _updateReminderDays(int days) async {
    setState(() => _reminderDaysBeforeDue = days);
    try {
      final ffi = FfiService();
      await ffi.updateLoanSettings(
        defaultLoanDurationDays: _defaultLoanDurationDays,
        perBookDurationEnabled: _perBookDurationEnabled,
        reminderDaysBeforeDue: days,
      );
    } catch (e) {
      debugPrint('Error updating reminder days: $e');
    }
  }
}
