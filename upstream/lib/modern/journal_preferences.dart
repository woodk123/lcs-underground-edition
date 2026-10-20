import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/utils/game_options.dart';

/// Local presentation settings, independent of reading size and campaign saves.
@immutable
class JournalPreferenceValues {
  const JournalPreferenceValues({
    this.compact = false,
    this.showGuidance = true,
  });

  final bool compact;
  final bool showGuidance;

  JournalPreferenceValues copyWith({bool? compact, bool? showGuidance}) =>
      JournalPreferenceValues(
        compact: compact ?? this.compact,
        showGuidance: showGuidance ?? this.showGuidance,
      );
}

final journalPresentation = ValueNotifier<JournalPreferenceValues>(
  const JournalPreferenceValues(),
);

class JournalPreferencesClosedNotification extends Notification {
  const JournalPreferencesClosedNotification();
}

class JournalPreferences extends InheritedWidget {
  const JournalPreferences({
    super.key,
    this.compact = false,
    this.showGuidance = true,
    required super.child,
  });

  final bool compact;
  final bool showGuidance;

  static JournalPreferences of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<JournalPreferences>() ??
      const JournalPreferences(child: SizedBox.shrink());

  @override
  bool updateShouldNotify(JournalPreferences oldWidget) =>
      compact != oldWidget.compact || showGuidance != oldWidget.showGuidance;
}

void _updatePreferences(JournalPreferenceValues values) {
  journalPresentation.value = values;
  gameOptions.journalCompact = values.compact;
  gameOptions.journalGuidance = values.showGuidance;
  unawaited(gameOptions.saveJournalPresentation());
}

/// The same controls are available in Options and during any graphical reader.
class JournalPreferencesControls extends StatelessWidget {
  const JournalPreferencesControls({super.key});

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<JournalPreferenceValues>(
    valueListenable: journalPresentation,
    builder: (context, values, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Layout', style: JournalPalette.heading),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final compact in [false, true])
              ChoiceChip(
                key: ValueKey(
                  compact ? 'journal-layout-compact' : 'journal-layout-roomy',
                ),
                selected: values.compact == compact,
                label: Text(compact ? 'Compact' : 'Comfortable'),
                onSelected: (_) =>
                    _updatePreferences(values.copyWith(compact: compact)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Compact uses smaller illustrations and closer rows. Reading size stays the same.',
          style: JournalPalette.small,
        ),
        const SizedBox(height: 12),
        Material(
          color: Colors.transparent,
          child: SwitchListTile.adaptive(
            key: const ValueKey('journal-show-guidance'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Show explanations'),
            subtitle: const Text(
              'Show introductory descriptions. Values, costs, warnings and keyboard shortcuts stay visible.',
            ),
            value: values.showGuidance,
            onChanged: (value) =>
                _updatePreferences(values.copyWith(showGuidance: value)),
          ),
        ),
      ],
    ),
  );
}

class JournalPreferencesButton extends StatelessWidget {
  const JournalPreferencesButton({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Interface preferences',
    icon: Icon(Icons.tune, color: color),
    onPressed: () async {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Interface preferences'),
          content: const SizedBox(
            width: 420,
            child: SingleChildScrollView(child: JournalPreferencesControls()),
          ),
          actions: [
            TextButton(
              autofocus: true,
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      if (context.mounted) {
        const JournalPreferencesClosedNotification().dispatch(context);
      }
    },
  );
}
