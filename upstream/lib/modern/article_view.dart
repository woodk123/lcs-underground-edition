import 'package:flutter/material.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/modern/journal_preferences.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';

const _ink = JournalPalette.ink;
const _muted = JournalPalette.muted;
const _teal = JournalPalette.olive;
const _vermilion = JournalPalette.danger;
const _rule = JournalPalette.rule;

/// A complete, scrollable article from an engine-generated story snapshot.
///
/// The parent supplies bounded height. This widget does not generate stories,
/// change their effects, consume game input or own navigation.
class ArticleView extends StatelessWidget {
  const ArticleView({super.key, required this.article});

  final ConsoleArticle article;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final narrow = constraints.maxWidth < 700;
      final compact = JournalPreferences.of(context).compact;
      final inset = compact
          ? 12.0
          : narrow
          ? 20.0
          : 38.0;
      final byline = article.byline;
      return SingleChildScrollView(
        key: const ValueKey('article-scroll'),
        padding: EdgeInsets.all(
          compact
              ? 8
              : narrow
              ? 16
              : 28,
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: DecoratedBox(
              decoration: journalPaperDecoration(),
              child: Padding(
                padding: EdgeInsets.all(inset),
                child: DefaultTextStyle(
                  style: JournalPalette.body.copyWith(
                    fontSize: 17,
                    height: 1.65,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (article.publisher.isNotEmpty) ...[
                        Text(
                          article.publisher,
                          key: const ValueKey('article-publisher'),
                          style: TextStyle(
                            fontSize: narrow ? 24 : 29,
                            fontWeight: FontWeight.w800,
                            height: 1.25,
                            letterSpacing: -.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Wrap(
                        spacing: 18,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            _date(article.date),
                            key: const ValueKey('article-date'),
                            style: const TextStyle(
                              fontSize: 13,
                              color: _muted,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (byline != null && byline.trim().isNotEmpty)
                            Text(
                              byline,
                              key: const ValueKey('article-byline'),
                              style: const TextStyle(
                                fontSize: 13,
                                color: _muted,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      const Divider(height: 1, thickness: 2, color: _ink),
                      const SizedBox(height: 28),
                      if (article.title.isNotEmpty) ...[
                        Semantics(
                          header: true,
                          child: Text(
                            article.title,
                            key: const ValueKey('article-headline'),
                            style: TextStyle(
                              fontSize: narrow ? 28 : 36,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                              letterSpacing: -.8,
                            ),
                          ),
                        ),
                        const SizedBox(height: 26),
                      ],
                      SelectableText(
                        article.body,
                        key: const ValueKey('article-body'),
                        semanticsLabel: article.body,
                        style: JournalPalette.body.copyWith(
                          fontSize: 17,
                          height: compact ? 1.5 : 1.7,
                        ),
                      ),
                      if (article.effects.isNotEmpty) ...[
                        const SizedBox(height: 32),
                        const Divider(height: 1, color: _rule),
                        const SizedBox(height: 24),
                        Semantics(
                          header: true,
                          child: const Text(
                            'Recorded impact',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                            ),
                          ),
                        ),
                        const SizedBox(height: 7),
                        const Text(
                          'Changes recorded for this story.',
                          style: TextStyle(fontSize: 13, color: _muted),
                        ),
                        const SizedBox(height: 16),
                        _effects(),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _effects() => LayoutBuilder(
    builder: (context, constraints) {
      final readingScale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final effectiveWidth = constraints.maxWidth / readingScale;
      final columns = effectiveWidth >= 700
          ? 3
          : effectiveWidth >= 430
          ? 2
          : 1;
      final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final effect in article.effects.entries)
            SizedBox(
              width: width,
              child: _Effect(
                label: effect.key,
                value: effect.value,
                compact: JournalPreferences.of(context).compact,
              ),
            ),
        ],
      );
    },
  );
}

class _Effect extends StatelessWidget {
  const _Effect({
    required this.label,
    required this.value,
    this.compact = false,
  });

  final String label;
  final double value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = value > 0
        ? _teal
        : value < 0
        ? _vermilion
        : _muted;
    final amount = _percentage(value);
    final exact = _exactPercentage(value);
    return Semantics(
      container: true,
      label: '$label: $amount',
      value: 'Exact recorded change: $exact',
      child: Tooltip(
        message: '$label: $exact',
        excludeFromSemantics: true,
        child: ExcludeSemantics(
          child: Container(
            padding: EdgeInsets.all(compact ? 8 : 15),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .055),
              border: Border.all(color: color.withValues(alpha: .18)),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _ink,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Icon(
                      value > 0
                          ? Icons.arrow_upward
                          : value < 0
                          ? Icons.arrow_downward
                          : Icons.horizontal_rule,
                      size: 16,
                      color: color,
                    ),
                    Text(
                      amount,
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        color: color,
                        height: 1.25,
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
}

String _percentage(double value) {
  return '${value > 0 ? '+' : ''}${value.toStringAsFixed(1)}%';
}

String _exactPercentage(double value) {
  if (value == 0) return '0%';
  final text = value.toString();
  final number = text.endsWith('.0')
      ? text.substring(0, text.length - 2)
      : text;
  return '${value > 0 ? '+' : ''}$number%';
}

String _date(DateTime date) {
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}
