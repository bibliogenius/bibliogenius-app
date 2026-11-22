import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A size setting picked on a slider of a few steps: a title, a preview of
/// the current step with its label, the slider, and a small and a large
/// mark at its two ends. Shared by the text size and the cover size of
/// Settings > Display, so that both read and handle the same way.
class SettingsStepSlider extends StatelessWidget {
  const SettingsStepSlider({
    super.key,
    required this.title,
    required this.preview,
    required this.stepCount,
    required this.index,
    required this.valueLabel,
    required this.onChanged,
    required this.smallMark,
    required this.largeMark,
  });

  final String title;

  /// Drawing of the current step, above its label. Decorative: the label
  /// says the same thing to a screen reader.
  final Widget preview;

  final int stepCount;

  /// The current step, from 0 to [stepCount] - 1.
  final int index;

  /// Label of a step, shown under the preview and read out as the slider's
  /// value.
  final String Function(int index) valueLabel;

  /// Called once per step reached, not on every drag update.
  final ValueChanged<int> onChanged;

  /// Decorative marks at the two ends of the slider.
  final Widget smallMark;
  final Widget largeMark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mutedColor = theme.textTheme.bodySmall?.color;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              ExcludeSemantics(child: preview),
              const SizedBox(height: 4),
              ExcludeSemantics(
                child: Text(
                  valueLabel(index),
                  style: TextStyle(fontSize: 12, color: mutedColor),
                ),
              ),
              const SizedBox(height: 8),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 8,
                  ),
                ),
                // The title above is a separate node: without this label a
                // screen reader announces the step ("Large, slider") but not
                // the setting it changes. Merged, so the label and the
                // slider are one node and not two stops.
                child: MergeSemantics(
                  child: Semantics(
                    label: title,
                    child: Slider(
                      value: index.toDouble(),
                      min: 0,
                      max: (stepCount - 1).toDouble(),
                      divisions: stepCount - 1,
                      activeColor: theme.colorScheme.primary,
                      semanticFormatterCallback: (value) =>
                          valueLabel(value.round()),
                      onChanged: (value) {
                        final step = value.round();
                        if (step == index) return;
                        HapticFeedback.lightImpact();
                        onChanged(step);
                      },
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: ExcludeSemantics(
                  child: IconTheme(
                    data: IconThemeData(color: mutedColor),
                    child: DefaultTextStyle.merge(
                      style: TextStyle(color: mutedColor),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [smallMark, largeMark],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
