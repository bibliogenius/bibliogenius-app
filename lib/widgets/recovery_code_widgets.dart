import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../providers/hub_directory_provider.dart';
import '../services/auth_service.dart';
import '../services/translation_service.dart';

/// Bottom sheet shown once after first registration to display the recovery code.
Future<void> showRecoveryCodeFirstSheet(
  BuildContext context,
  String recoveryCode,
) async {
  String t(String key) =>
      TranslationService.translate(context, key);

  final formatted = HubDirectoryProvider.formatRecoveryCode(recoveryCode);

  await showModalBottomSheet<void>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(ctx).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.key, size: 40),
          const SizedBox(height: 12),
          Text(
            t('recovery_code_first_title'),
            style: Theme.of(ctx).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          Text(
            t('recovery_code_first_explanation'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            t('recovery_code_first_save_notice'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          _RecoveryCodeBox(code: formatted, context: ctx),
          const SizedBox(height: 12),
          Text(
            t('recovery_code_first_auto_notice'),
            textAlign: TextAlign.center,
            style: Theme.of(ctx).textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(t('recovery_code_first_confirm')),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    ),
  );
}

/// Screen that displays the recovery code (accessed from Settings > Directory).
class RecoveryCodeDisplaySheet extends StatelessWidget {
  final String recoveryCode;

  const RecoveryCodeDisplaySheet({super.key, required this.recoveryCode});

  @override
  Widget build(BuildContext context) {
    String t(String key) =>
        TranslationService.translate(context, key);

    final formatted = HubDirectoryProvider.formatRecoveryCode(recoveryCode);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            t('recovery_code_display_title'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          Text(
            t('recovery_code_display_explanation'),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          _RecoveryCodeBox(code: formatted, context: context),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t('recovery_code_scope_covers') ??
                            'Covers: your public directory profile, followers and following.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        t('recovery_code_scope_excludes') ??
                            'Not affected: your local library and books.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            t('recovery_code_save_advice'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

/// Dialog shown after 3 consecutive 401 failures.
/// Offers: recovery code input, new profile, or dismiss.
Future<String?> showConnectionLostDialog(BuildContext context) async {
  String t(String key) =>
      TranslationService.translate(context, key);

  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(t('connection_lost_title')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(t('connection_lost_body')),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            icon: const Icon(Icons.key),
            label: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('connection_lost_recovery_option')),
                Text(
                  t('connection_lost_recovery_subtitle'),
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ],
            ),
            onPressed: () => Navigator.of(ctx).pop('recover'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.person_add),
            label: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t('connection_lost_new_profile')),
                Text(
                  t('connection_lost_new_profile_warning'),
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(ctx).colorScheme.error,
                      ),
                ),
              ],
            ),
            onPressed: () => Navigator.of(ctx).pop('new_profile'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(null),
          child: Text(t('connection_lost_later')),
        ),
      ],
    ),
  );
}

/// Bottom sheet for entering a recovery code.
Future<bool> showRecoveryCodeInputSheet(
  BuildContext context,
  HubDirectoryProvider dirProvider,
) async {
  String t(String key) =>
      TranslationService.translate(context, key);

  final controllers = List.generate(3, (_) => TextEditingController());
  final focusNodes = List.generate(3, (_) => FocusNode());
  bool loading = false;
  String? error;

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 24,
            right: 24,
            top: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                t('recovery_input_title'),
                style: Theme.of(ctx).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                t('recovery_input_instructions'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (i) {
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: i > 0 ? 8 : 0,
                      ),
                      child: TextField(
                        controller: controllers[i],
                        focusNode: focusNodes[i],
                        textCapitalization: TextCapitalization.characters,
                        textAlign: TextAlign.center,
                        maxLength: 4,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                        decoration: InputDecoration(
                          counterText: '',
                          border: const OutlineInputBorder(),
                          hintText: i == 0
                              ? 'ABCD'
                              : i == 1
                                  ? 'EFGH'
                                  : 'JKLM',
                        ),
                        onChanged: (value) {
                          if (value.length == 4 && i < 2) {
                            focusNodes[i + 1].requestFocus();
                          }
                        },
                      ),
                    ),
                  );
                }),
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: loading
                      ? null
                      : () async {
                          final code = controllers
                              .map((c) => c.text.trim().toUpperCase())
                              .join();
                          if (code.length < 12) {
                            setState(() => error = t('recovery_input_error'));
                            return;
                          }

                          setState(() {
                            loading = true;
                            error = null;
                          });

                          final nodeId =
                              await AuthService().getOrCreateLibraryUuid();
                          final ok = await dirProvider.recoverWithCode(
                            nodeId,
                            code,
                          );

                          if (!ctx.mounted) return;

                          if (ok) {
                            Navigator.of(ctx).pop(true);
                          } else {
                            setState(() {
                              loading = false;
                              error = t('recovery_input_error');
                            });
                          }
                        },
                  child: loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(t('recovery_input_submit')),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    ),
  );

  for (final c in controllers) {
    c.dispose();
  }
  for (final f in focusNodes) {
    f.dispose();
  }

  return result ?? false;
}

// ---------------------------------------------------------------------------
// Shared
// ---------------------------------------------------------------------------

class _RecoveryCodeBox extends StatelessWidget {
  final String code;
  final BuildContext context;

  const _RecoveryCodeBox({required this.code, required this.context});

  @override
  Widget build(BuildContext context) {
    String t(String key) =>
        TranslationService.translate(context, key);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: SelectableText(
              code,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                letterSpacing: 3,
                fontFamily: 'monospace',
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: t('recovery_code_copy'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(t('recovery_code_copied'))),
              );
            },
          ),
        ],
      ),
    );
  }
}
