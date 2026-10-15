import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' hide View;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/media_overview.dart';
import 'package:lcs_new_age/common_display/common_display.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/engine/media_context.dart';
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/modern/journal_media.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/newspaper/news_story.dart';
import 'package:lcs_new_age/politics/views.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

NewsStory _story(int index) => NewsStory()
  ..headline =
      'Actual archived report $index with a full headline that exceeds the old terminal column'
  ..body =
      'Complete report $index.\n\n${List.filled(30, 'The original article body remains available.').join(' ')}'
  ..byline = 'Recorded correspondent $index'
  ..publication = index.isEven ? Publication.times : Publication.cableNews
  ..date = DateTime(2026, 9, index + 1)
  ..effects = {View.freeSpeech: 2.5, View.lcsLiked: -.25, View.lcsKnown: 90};

void _archive(int count) =>
    game.gameState.newsArchive.addAll(List.generate(count, _story));

String _snapshot() => jsonEncode(game.gameState.toJson());
Finder _key(String value) => find.byKey(ValueKey(value));

typedef _Step = String Function();

Future<void> _drive(List<_Step> steps, {Future<void> Function()? menu}) async {
  var index = 0;
  void respond() {
    if (!engine.console.awaitingInput || engine.console.lastKey != null) return;
    expect(index, lessThan(steps.length));
    expect(engine.console.sendInput(steps[index++]()), isTrue);
  }

  engine.console.revision.addListener(respond);
  try {
    await (menu ?? mediaOverview)().timeout(const Duration(seconds: 5));
  } finally {
    engine.console.revision.removeListener(respond);
  }
  expect(index, steps.length);
}

ConsoleAction _next(MediaOverviewFrame frame) => frame.controls.singleWhere(
  (action) => const {']', '.', 'PageDown'}.contains(action.key),
);

ConsoleAction _back(MediaOverviewFrame frame) =>
    frame.controls.singleWhere((action) => action.key == 'Enter');

class _MediaHarness {
  _MediaHarness() {
    unawaited(_run());
  }
  bool returned = false;
  bool finished = false;
  Future<void> _run() async {
    try {
      await mediaOverview();
      returned = true;
      engine.erase();
      engine.console.screen = 'headquarters';
      await engine.getKey();
    } finally {
      finished = true;
    }
  }

  Future<void> stop(WidgetTester tester) async {
    for (var i = 0; i < 50 && !finished; i++) {
      if (engine.console.awaitingInput) engine.console.sendInput('Escape');
      await tester.pump(const Duration(milliseconds: 5));
    }
    expect(finished, isTrue);
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String fixture;
  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
    final font = FontLoader('JournalSerif');
    font.addFont(
      rootBundle.load('fonts/journal/LibreBaskerville-Variable.ttf'),
    );
    await font.load();
  });
  setUp(() {
    game.gameState = decodeSaveContents(fixture).gameState!;
    game.mode = GameMode.base;
    game.gameState.newsArchive.clear();
    engine.console = Console();
  });

  test(
    'source snapshot keeps exact mood, full rows, impact and actual page commands without mutations',
    () async {
      _archive(22);
      final archive = game.gameState.newsArchive;
      final mood = game.politics.publicMood();
      final support = game.politics.lcsApproval();
      final before = _snapshot();
      reseedRNG(seed: 112032);
      final rolls = List.generate(8, (_) => lcsRandom(100000));
      reseedRNG(seed: 112032);
      await _drive([
        () {
          final frame = mediaOverviewFrame(engine.console)!;
          expect(frame.publicMood, mood);
          expect(frame.lcsSupport, support);
          expect(frame.page, 0);
          expect(frame.pageCount, 2);
          expect(frame.totalStories, 22);
          expect(frame.entries.length, 17);
          final first = frame.entries.first;
          expect(first.headline, archive.last.headline);
          expect(first.headline.length, greaterThan(32));
          expect(first.action.label, isNot(contains(first.headline)));
          expect(
            first.impact,
            2.25,
            reason:
                'Recognition must be excluded; LCS approval remains included.',
          );
          expect(first.impactLabel, '+2.3%');
          expect(first.date, archive.last.date);
          expect(first.publisher, archive.last.publicationName);
          expect(
            first.publisherAlignment,
            archive.last.publicationAlignment.label,
          );
          expect(frame.controls.length, 3);
          for (final entry in frame.entries) {
            expect(engine.console.actions, contains(entry.action));
            expect(entry.action.entityId, entry.index.toString());
          }
          return _next(frame).key;
        },
        () {
          final frame = mediaOverviewFrame(engine.console)!;
          expect(frame.page, 1);
          expect(frame.pageCount, 2);
          expect(frame.entries.length, 5);
          expect(frame.entries.first.index, 17);
          expect(frame.entries.first.headline, archive[4].headline);
          expect(_snapshot(), before);
          return _back(frame).key;
        },
      ]);
      expect(mediaOverviewFrame(engine.console), isNull);
      expect(_snapshot(), before);
      expect(List.generate(8, (_) => lcsRandom(100000)), rolls);
    },
  );

  test(
    'reading uses the actual article and changes only its original unread field',
    () async {
      _archive(2);
      final chosen = game.gameState.newsArchive.last;
      final before = jsonDecode(_snapshot()) as Map<String, dynamic>;
      await _drive([
        () => mediaOverviewFrame(engine.console)!.entries.first.action.key,
        () {
          expect(mediaOverviewFrame(engine.console), isNull);
          expect(engine.console.article?.title, chosen.headline);
          expect(engine.console.article?.body, chosen.body);
          expect(engine.console.article?.byline, chosen.byline);
          expect(engine.console.article?.publisher, chosen.publicationName);
          expect(chosen.unread, isFalse);
          return engine.console.actions
              .singleWhere((action) => action.key == 'Enter')
              .key;
        },
        () {
          final frame = mediaOverviewFrame(engine.console)!;
          expect(frame.entries.first.unread, isFalse);
          expect(frame.entries[1].unread, isTrue);
          return _back(frame).key;
        },
      ]);
      final after = jsonDecode(_snapshot()) as Map<String, dynamic>;
      final oldArchive = before['newsArchive'] as List;
      (oldArchive.last as Map<String, dynamic>)['unread'] = false;
      expect(after, before);
    },
  );

  test(
    'optional generic metadata callback runs after all actions and before the reader',
    () async {
      var called = 0;
      await _drive(
        [
          () {
            expect(called, 1);
            expect(mediaOverviewFrame(engine.console), isNull);
            return 'Enter';
          },
        ],
        menu: () => pagedInterface(
          count: 1,
          lineBuilder: (y, key, index) =>
              engine.addOptionText(y, 0, key, '$key - Original choice'),
          onChoice: (index) async => true,
          onAwait: (page, count) {
            called++;
            expect(engine.console.awaitingInput, isFalse);
            expect(page, 0);
            expect(count, 1);
            expect(engine.console.actions.any((a) => a.key == 'a'), isTrue);
            expect(engine.console.actions.any((a) => a.key == 'Enter'), isTrue);
          },
        ),
      );
    },
  );

  Future<_MediaHarness> mount(
    WidgetTester tester, {
    Size size = const Size(1200, 560),
    double scale = 1,
    ValueChanged<String>? onAction,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    final harness = _MediaHarness();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await harness.stop(tester);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildJournalTheme(),
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(scale),
            ),
            child: JournalMediaOverview(
              console: engine.console,
              onAction: onAction ?? (key) => engine.console.sendInput(key),
            ),
          ),
        ),
      ),
    );
    await _settle(tester);
    return harness;
  }

  testWidgets(
    'newspaper has typed readable facts, complete headlines and a separate fixed Back',
    (tester) async {
      _archive(2);
      await mount(tester);
      final frame = mediaOverviewFrame(engine.console)!;
      expect(
        tester.widget<Text>(_key('journal-media-mood')).data,
        '${frame.publicMood.toStringAsFixed(1)}%',
      );
      expect(
        tester.widget<Text>(_key('journal-media-support')).data,
        '${frame.lcsSupport.toStringAsFixed(1)}%',
      );
      expect(find.text(frame.entries.first.headline), findsOneWidget);
      expect(
        find.text('Editorial line: ${frame.entries.first.publisherAlignment}'),
        findsWidgets,
      );
      expect(
        find.descendant(
          of: _key('journal-media-back'),
          matching: _key('journal-media-mood'),
        ),
        findsNothing,
      );
      expect(_key('journal-media-back').hitTestable(), findsOneWidget);
      expect(tester.getRect(_key('journal-media-back')).height, lessThan(70));
      expect(tester.getRect(_key('journal-media-back')).width, lessThan(180));
      expect(find.text('HEADLINE'), findsNothing);
      expect(find.textContaining('CODE NAME'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'actual source Next and Back work without scrolling or affecting the simulation',
    (tester) async {
      _archive(22);
      final before = _snapshot();
      final harness = await mount(tester);
      final next = _next(mediaOverviewFrame(engine.console)!);
      final previous = mediaOverviewFrame(engine.console)!.controls.singleWhere(
        (action) => const {'[', ';', ',', 'PageUp'}.contains(action.key),
      );
      expect(
        tester
            .widget<OutlinedButton>(
              _key('journal-media-control:${previous.key}'),
            )
            .onPressed,
        isNull,
        reason: 'Page one must not offer a highlighted no-op Previous action.',
      );
      final button = _key('journal-media-control:${next.key}');
      expect(button.hitTestable(), findsOneWidget);
      await tester.tap(button);
      await _settle(tester);
      expect(mediaOverviewFrame(engine.console)?.page, 1);
      expect(find.text('Page 2 of 2'), findsOneWidget);
      expect(
        tester.widget<OutlinedButton>(button).onPressed,
        isNull,
        reason: 'The last page must not offer a highlighted no-op Next action.',
      );
      expect(_snapshot(), before);
      await tester.tap(_key('journal-media-back'));
      await _settle(tester);
      expect(harness.returned, isTrue);
      expect(engine.console.screen, 'headquarters');
      expect(_snapshot(), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('actual report click opens its full original article', (
    tester,
  ) async {
    _archive(1);
    final chosen = game.gameState.newsArchive.single;
    await mount(tester);
    await tester.ensureVisible(_key('journal-media-story:0'));
    await tester.tap(_key('journal-media-story:0'));
    await _settle(tester);
    expect(engine.console.article?.title, chosen.headline);
    expect(engine.console.article?.body, chosen.body);
    expect(chosen.unread, isFalse);
    expect(mediaOverviewFrame(engine.console), isNull);
    engine.console.sendInput('Enter');
    await _settle(tester);
    expect(mediaOverviewFrame(engine.console)?.entries.single.unread, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('captured stale report and Back callbacks cannot dispatch', (
    tester,
  ) async {
    _archive(1);
    final received = <String>[];
    await mount(tester, onAction: received.add);
    final report = tester.widget<InkWell>(_key('journal-media-story:0')).onTap!;
    final back = tester
        .widget<OutlinedButton>(_key('journal-media-back'))
        .onPressed!;
    engine.console.flush();
    report();
    back();
    expect(received, isEmpty);
    await _settle(tester);
    final fresh = tester.widget<InkWell>(_key('journal-media-story:0')).onTap!;
    final entry = mediaOverviewFrame(engine.console)!.entries.single;
    engine.console.actions.remove(entry.action);
    fresh();
    expect(received, isEmpty);
    expect(game.gameState.newsArchive.single.unread, isTrue);
    expect(tester.takeException(), isNull);
  });

  for (final layout in [
    (const Size(1200, 560), 1.0),
    (const Size(760, 500), 1.5),
    (const Size(360, 500), 1.5),
  ]) {
    testWidgets(
      'empty archive and its Back stay usable at ${layout.$1} scale ${layout.$2}',
      (tester) async {
        final harness = await mount(tester, size: layout.$1, scale: layout.$2);
        expect(mediaOverviewFrame(engine.console)?.entries, isEmpty);
        expect(find.text('No archived reports'), findsOneWidget);
        expect(_key('journal-media-back').hitTestable(), findsOneWidget);
        expect(
          tester.getRect(_key('journal-media-back')).bottom,
          lessThanOrEqualTo(layout.$1.height),
        );
        await tester.scrollUntilVisible(
          _key('journal-media-empty'),
          160,
          scrollable: find.byType(Scrollable),
        );
        await _settle(tester);
        expect(_key('journal-media-empty').hitTestable(), findsOneWidget);
        await tester.tap(_key('journal-media-back'));
        await _settle(tester);
        expect(harness.returned, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
