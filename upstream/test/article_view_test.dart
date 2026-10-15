import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/modern/article_view.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';

Future<void> mountArticle(
  WidgetTester tester,
  ConsoleArticle article, {
  Size size = const Size(1280, 800),
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'ModernSans'),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: ArticleView(article: article),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ConsoleArticle story({
  String? byline,
  String? body,
  Map<String, double>? effects,
}) => ConsoleArticle(
  title: 'A city responds to a growing movement',
  publisher: 'The Seattle Herald',
  body:
      body ??
      'The first paragraph contains the complete opening report.\n\nThe second paragraph retains its own break and context.',
  byline: byline,
  date: DateTime(2026, 10, 13),
  effects:
      effects ??
      const {'Free speech': 2.5, 'LCS approval': -1.25, 'Animal rights': 0},
);

void main() {
  setUpAll(() async {
    final font = FontLoader('ModernSans');
    for (final weight in ['regular', 'medium', 'bold', 'black']) {
      font.addFont(rootBundle.load('fonts/modern/roboto-$weight.ttf'));
    }
    await font.load();
    final journalFont = FontLoader(JournalPalette.serif)
      ..addFont(rootBundle.load('fonts/journal/LibreBaskerville-Variable.ttf'));
    await journalFont.load();
  });

  testWidgets(
    'presents actual story, date, byline and source-precision effects',
    (tester) async {
      final article = story(
        byline: 'By Alex Rivera',
        effects: const {
          'Free speech': 2.5,
          'LCS approval': -1.25,
          'Animal rights': 0,
          'Corporate accountability': 0.025,
        },
      );
      await mountArticle(tester, article);
      expect(find.text(article.publisher), findsOneWidget);
      expect(find.bySemanticsLabel(article.body), findsOneWidget);
      expect(find.text(article.title), findsOneWidget);
      expect(find.text('October 13, 2026'), findsOneWidget);
      expect(find.text('By Alex Rivera'), findsOneWidget);
      expect(
        tester
            .widget<SelectableText>(find.byKey(const ValueKey('article-body')))
            .data,
        article.body,
      );
      for (final value in ['+2.5%', '-1.3%', '0.0%', '+0.0%']) {
        expect(find.text(value), findsOneWidget);
      }
      for (final issue in article.effects.keys) {
        expect(find.text(issue), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'long fractional impact remains readable without changing source value',
    (tester) async {
      const original = 12.803436977924854;
      final article = story(
        body: 'A complete report.',
        effects: const {'Genetics': original},
      );
      await mountArticle(
        tester,
        article,
        size: const Size(800, 600),
        textScale: 1.5,
      );
      await tester.ensureVisible(find.text('+12.8%'));
      await tester.pumpAndSettle();
      expect(find.text('+12.8%'), findsOneWidget);
      expect(find.text('+12.803436977924854%'), findsNothing);
      expect(find.byTooltip('Genetics: +12.803436977924854%'), findsOneWidget);
      final semantics = tester
          .getSemantics(find.bySemanticsLabel('Genetics: +12.8%'))
          .getSemanticsData();
      expect(semantics.value, 'Exact recorded change: +12.803436977924854%');
      expect(article.effects['Genetics'], original);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('omits absent byline and empty impact section', (tester) async {
    await mountArticle(tester, story(effects: const {}));
    expect(find.byKey(const ValueKey('article-byline')), findsNothing);
    expect(find.text('Recorded impact'), findsNothing);
    expect(find.textContaining('By '), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(800, 600), const Size(1280, 800)]) {
    testWidgets(
      'retains and scrolls full long article at ${size.width.toInt()}px',
      (tester) async {
        final body = List.generate(
          35,
          (i) =>
              'Paragraph ${i + 1}. The city, its people and the movement have a complete story to tell. This sentence should wrap naturally without truncating any of the report.',
        ).join('\n\n');
        final article = story(
          body: body,
          byline:
              'By an unusually long newsroom byline that must wrap without clipping',
        );
        await mountArticle(tester, article, size: size, textScale: 1.5);
        final selectable = tester.widget<SelectableText>(
          find.byKey(const ValueKey('article-body')),
        );
        expect(selectable.data, body);
        expect(selectable.maxLines, isNull);
        expect(selectable.style?.fontFamily, JournalPalette.serif);
        final scroll = tester.widget<SingleChildScrollView>(
          find.byKey(const ValueKey('article-scroll')),
        );
        expect(scroll.scrollDirection, Axis.vertical);
        await tester.drag(
          find.byKey(const ValueKey('article-scroll')),
          const Offset(0, -10000),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Recorded impact'));
        await tester.pumpAndSettle();
        expect(find.text('Recorded impact').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
