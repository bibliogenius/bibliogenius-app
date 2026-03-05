import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/quick_action_registry.dart';
import '../services/translation_service.dart';

/// Styled card for a quick action (icon + label).
/// Used for both fixed actions and configurable slots.
class QuickActionCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool showCustomizeHint;

  const QuickActionCard({
    super.key,
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
    this.onLongPress,
    this.showCustomizeHint = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          decoration: BoxDecoration(
            color: isDark
                ? color.withValues(alpha: 0.15)
                : color.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border:
                Border.all(color: color.withValues(alpha: 0.2), width: 1),
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Icon(icon, color: color, size: 24),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : Colors.grey[800],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (showCustomizeHint)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Icon(
                    Icons.tune,
                    size: 11,
                    color: isDark
                        ? Colors.white24
                        : Colors.grey.withValues(alpha: 0.35),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A quick action card whose action is configurable by the user.
/// Persists the choice in SharedPreferences.
/// Long-press opens a picker dialog to change the action.
class ConfigurableActionCard extends StatefulWidget {
  /// SharedPreferences key for this slot.
  final String slotKey;

  /// Default action ID when no preference is saved.
  final String defaultActionId;

  /// Which actions from the registry are available for this slot.
  final List<String> allowedActionIds;

  /// Tap handler for each action ID.
  final Map<String, VoidCallback> handlers;

  const ConfigurableActionCard({
    super.key,
    required this.slotKey,
    required this.defaultActionId,
    required this.allowedActionIds,
    required this.handlers,
  });

  @override
  State<ConfigurableActionCard> createState() =>
      _ConfigurableActionCardState();
}

class _ConfigurableActionCardState extends State<ConfigurableActionCard> {
  late String _currentActionId;

  @override
  void initState() {
    super.initState();
    _currentActionId = widget.defaultActionId;
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(widget.slotKey);
    if (saved != null &&
        widget.allowedActionIds.contains(saved) &&
        mounted) {
      setState(() => _currentActionId = saved);
    }
  }

  Future<void> _savePreference(String actionId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(widget.slotKey, actionId);
    if (mounted) {
      setState(() => _currentActionId = actionId);
    }
  }

  void _showPicker() {
    final actions = QuickActionRegistry.byIds(widget.allowedActionIds);
    showDialog(
      context: context,
      builder: (dialogContext) {
        return SimpleDialog(
          title: Text(
            TranslationService.translate(context, 'quick_action_choose') ??
                'Choose shortcut',
          ),
          children: actions.map((action) {
            final isSelected = action.id == _currentActionId;
            return SimpleDialogOption(
              onPressed: () {
                Navigator.pop(dialogContext);
                _savePreference(action.id);
              },
              child: Row(
                children: [
                  Icon(action.icon, color: action.color, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      TranslationService.translate(context, action.labelKey),
                      style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (isSelected)
                    Icon(Icons.check, size: 18, color: action.color),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final action = QuickActionRegistry.byId(_currentActionId);
    if (action == null) return const SizedBox.shrink();

    return QuickActionCard(
      icon: action.icon,
      color: action.color,
      label: TranslationService.translate(context, action.labelKey),
      onTap: () {
        final handler = widget.handlers[_currentActionId];
        handler?.call();
      },
      onLongPress: _showPicker,
      showCustomizeHint: true,
    );
  }
}
