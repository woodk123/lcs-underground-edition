import 'package:lcs_new_age/engine/console.dart';

/// Current authored presentation only. A child acknowledgement must never be
/// described using its retained parent article or legislative context.
Map<String, dynamic>? reportObservation(Console console) {
  if (console.eventMessage case final message?) {
    return {'kind': 'message', 'title': console.eventTitle, 'text': message};
  }
  final article = console.article;
  if (console.screen == 'article' && article != null) {
    return {
      'kind': 'article',
      'title': article.title,
      'publisher': article.publisher,
      'date': article.date.toIso8601String(),
      'byline': article.byline,
      'body': article.body,
      'text': [
        article.title,
        '${article.publisher} · ${article.date.toIso8601String()}',
        if (article.byline != null) article.byline!,
        article.body,
      ].join('\n\n'),
    };
  }
  final legislation = console.legislation;
  if (legislation != null) {
    String cells(int row, int start, int end) => row >= console.height
        ? ''
        : console.buffer[row]
              .skip(start)
              .take(end - start)
              .map((cell) => cell.glyph)
              .join()
              .trim();
    final hasVotes = cells(0, 62, 70) == 'House';
    final title = 'Legislation ${legislation.year} · ${legislation.stage.name}';
    final bills = [
      for (final (index, bill) in legislation.bills.indexed)
        {
          'law': bill.law.name,
          'title': bill.law.label,
          'before': bill.before.label,
          'proposed': bill.after.label,
          'enacted': bill.enacted,
          'outcome': bill.outcome,
          if (hasVotes)
            'house': [
              cells(2 + index * 3, 62, 70),
              cells(3 + index * 3, 62, 70),
            ].where((text) => text.isNotEmpty).join(' · '),
          if (hasVotes)
            'senate': [
              cells(2 + index * 3, 70, 80),
              cells(3 + index * 3, 70, 80),
            ].where((text) => text.isNotEmpty).join(' · '),
          if (hasVotes && cells(0, 35, 62) == 'President')
            'president': cells(2 + index * 3, 35, 62),
        },
    ];
    final authored = console.currentReportText();
    return {
      'kind': 'legislation',
      'title': title,
      'stage': legislation.stage.name,
      'bills': bills,
      'text': [
        title,
        for (final bill in bills)
          '${bill['title']}: ${bill['before']} → proposed ${bill['proposed']}. ${bill['outcome'] ?? 'Decision pending.'}'
              '${bill['house'] == null ? '' : '\nHouse: ${bill['house']} · Senate: ${bill['senate']}'}'
              '${bill['president'] == null ? '' : '\nPresident: ${bill['president']}'}',
        if (authored.isNotEmpty) authored,
      ].join('\n'),
    };
  }
  final text = console.currentReportText();
  return text.isEmpty
      ? null
      : {'kind': 'source_report', 'title': console.eventTitle, 'text': text};
}
