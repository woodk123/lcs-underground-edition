import 'package:flutter/material.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/media_context.dart';
import 'package:lcs_new_age/modern/decision_help.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/utils/colors.dart' as source;

/// A live newspaper archive, using only the source handler's exact frame.
/// Back and paging remain fixed while full headlines and recorded facts scroll.
class JournalMediaOverview extends StatelessWidget {
  const JournalMediaOverview({
    super.key,
    required this.console,
    required this.onAction,
  });

  final Console console;
  final ValueChanged<String> onAction;

  bool _available(MediaOverviewFrame frame, ConsoleAction action) {
    if (!action.enabled) return false;
    if (const {'[', ';', ',', 'PageUp'}.contains(action.key)) {
      return frame.page > 0;
    }
    if (const {']', '.', 'PageDown'}.contains(action.key)) {
      return frame.page + 1 < frame.pageCount;
    }
    return true;
  }

  VoidCallback? _command(
    MediaOverviewFrame frame,
    ConsoleAction action,
    int revision,
  ) {
    if (!_available(frame, action)) return null;
    return () {
      if (console.revision.value != revision ||
          mediaOverviewFrame(console) != frame ||
          !console.actions.contains(action) ||
          !console.awaitingInput ||
          console.textInput ||
          console.lastKey != null) {
        return;
      }
      onAction(action.key);
    };
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: console.revision,
    builder: (context, _) {
      final frame = mediaOverviewFrame(console);
      if (frame == null) return const SizedBox.shrink();
      final revision = console.revision.value;
      return LayoutBuilder(
        builder: (context, bounds) {
          final narrow = bounds.maxWidth < 650;
          final back = frame.controls
              .where((action) => action.key == 'Enter')
              .firstOrNull;
          final pages = frame.controls.where((action) => action != back);
          return JournalSurface(
            key: const ValueKey('journal-media'),
            padding: EdgeInsets.all(narrow ? 12 : 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  key: const ValueKey('journal-media-archive'),
                  child: Scrollbar(
                    child: ListView(
                      key: ValueKey('journal-media-scroll:${frame.page}'),
                      children: [
                        Semantics(
                          header: true,
                          child: Text(
                            'Press archive',
                            key: const ValueKey('journal-media-title'),
                            style: JournalPalette.title.copyWith(
                              fontSize: narrow ? 27 : 34,
                              letterSpacing: -.6,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const DecisionGuideButton(topic: DecisionTopic.opinion),
                        Wrap(
                          spacing: 14,
                          runSpacing: 3,
                          children: [
                            const Text(
                              'Recorded news & public opinion',
                              style: JournalPalette.body,
                            ),
                            Text(
                              '${frame.totalStories} archived '
                              '${frame.totalStories == 1 ? 'report' : 'reports'}',
                              style: JournalPalette.small,
                            ),
                          ],
                        ),
                        const Divider(
                          height: 23,
                          thickness: 2,
                          color: JournalPalette.ink,
                        ),
                        _opinion(frame, narrow),
                        const SizedBox(height: 9),
                        for (final note in frame.notes)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(note, style: JournalPalette.small),
                          ),
                        const Divider(height: 22),
                        const Text(
                          'News reports',
                          style: JournalPalette.heading,
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          'Impact totals recorded opinion changes, excluding '
                          'LCS recognition. Read a report for each effect.',
                          style: JournalPalette.small,
                        ),
                        const SizedBox(height: 9),
                        if (frame.entries.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 22),
                            child: Text(
                              'No news reports have been archived yet.',
                              key: ValueKey('journal-media-empty'),
                              style: JournalPalette.body,
                            ),
                          )
                        else
                          for (final entry in frame.entries)
                            _story(frame, entry, revision, narrow),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 16),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (back != null)
                      OutlinedButton.icon(
                        key: const ValueKey('journal-media-back'),
                        onPressed: _command(frame, back, revision),
                        icon: const Icon(Icons.arrow_back, size: 17),
                        label: const Text('Back'),
                      ),
                    Text(
                      frame.pageCount == 0
                          ? 'No archived reports'
                          : 'Page ${frame.page + 1} of ${frame.pageCount}',
                      key: const ValueKey('journal-media-page'),
                      style: JournalPalette.small,
                    ),
                    for (final action in pages)
                      OutlinedButton(
                        key: ValueKey('journal-media-control:${action.key}'),
                        onPressed: _command(frame, action, revision),
                        child: Text(_label(action.label)),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    },
  );

  Widget _opinion(MediaOverviewFrame frame, bool narrow) => LayoutBuilder(
    builder: (context, bounds) {
      final stacked = bounds.maxWidth < 510;
      final width = stacked ? bounds.maxWidth : (bounds.maxWidth - 18) / 2;
      return Wrap(
        spacing: 18,
        runSpacing: 9,
        children: [
          SizedBox(
            width: width,
            child: _stat(
              'People with Liberal views',
              frame.publicMood,
              'journal-media-mood',
              narrow,
              JournalPalette.olive,
            ),
          ),
          SizedBox(
            width: width,
            child: _stat(
              'Support for the Liberal Crime Squad',
              frame.lcsSupport,
              'journal-media-support',
              narrow,
              frame.lcsSupportColorKey == source.ColorKey.red
                  ? JournalPalette.danger
                  : frame.lcsSupportColorKey == source.ColorKey.lightGreen
                  ? JournalPalette.olive
                  : JournalPalette.brassDark,
            ),
          ),
        ],
      );
    },
  );

  Widget _stat(
    String label,
    double value,
    String key,
    bool narrow,
    Color valueColor,
  ) => Container(
    padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
    decoration: BoxDecoration(
      color: JournalPalette.inset.withValues(alpha: .6),
      border: Border.all(color: JournalPalette.rule),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: JournalPalette.small.copyWith(
              fontWeight: FontWeight.w700,
              color: JournalPalette.ink,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${value.toStringAsFixed(1)}%',
          key: ValueKey(key),
          style: JournalPalette.heading.copyWith(
            fontSize: narrow ? 23 : 28,
            color: valueColor,
          ),
        ),
      ],
    ),
  );

  Widget _story(
    MediaOverviewFrame frame,
    MediaArchiveEntry entry,
    int revision,
    bool narrow,
  ) {
    final activate = _command(frame, entry.action, revision);
    final impactColor = entry.impact > 0
        ? JournalPalette.olive
        : entry.impact < 0
        ? JournalPalette.danger
        : JournalPalette.muted;
    return Semantics(
      button: true,
      enabled: activate != null,
      excludeSemantics: true,
      label:
          '${entry.unread ? 'Unread. ' : ''}${entry.headline}. '
          '${entry.publisher}. ${entry.dateLabel}. '
          'Editorial line ${entry.publisherAlignment}. '
          'Recorded impact ${entry.impactLabel}.',
      value: 'Exact recorded impact ${entry.impact}%',
      onTap: activate,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('journal-media-story:${entry.index}'),
          onTap: activate,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: JournalPalette.rule)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (entry.unread) ...[
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Icon(
                          Icons.circle,
                          size: 8,
                          color: JournalPalette.binding,
                        ),
                      ),
                      const SizedBox(width: 7),
                    ],
                    Expanded(
                      child: Text(
                        stripConsoleColors(entry.headline),
                        key: ValueKey('journal-media-headline:${entry.index}'),
                        style: JournalPalette.heading.copyWith(
                          fontSize: narrow ? 15 : 17,
                          fontWeight: entry.unread
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: narrow ? 12 : 20,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(entry.dateLabel, style: JournalPalette.small),
                    Text(
                      entry.publisher.isEmpty
                          ? 'Publisher not recorded'
                          : entry.publisher,
                      style: JournalPalette.small.copyWith(
                        color: JournalPalette.ink,
                      ),
                    ),
                    Text(
                      'Editorial line: ${entry.publisherAlignment}',
                      style: JournalPalette.small,
                    ),
                    Text(
                      'Impact ${entry.impactLabel}',
                      key: ValueKey('journal-media-impact:${entry.index}'),
                      style: JournalPalette.small.copyWith(color: impactColor),
                    ),
                    if (entry.unread)
                      Text(
                        'Unread',
                        style: JournalPalette.small.copyWith(
                          color: JournalPalette.binding,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _label(String value) =>
      stripConsoleColors(value).replaceFirst(RegExp(r'^\S+\s+-\s+'), '').trim();
}
