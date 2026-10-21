import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/base_mode.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/juice_indicator.dart';
import 'package:lcs_new_age/modern/personnel_directory.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

Finder key(String name) => find.byKey(ValueKey(name));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String fixture;
  late Creature person;
  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
    final font = FontLoader(JournalPalette.serif)
      ..addFont(rootBundle.load('fonts/journal/LibreBaskerville-Variable.ttf'));
    await font.load();
  });
  setUp(() {
    engine.console = Console();
    game.gameState = decodeSaveContents(fixture).gameState!;
    game.mode = GameMode.base;
    game.activeSquadMember = null;
    journalReadingScale.value = 1;
    person = game.pool.first..juice = 160;
  });

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(1280, 800),
    double scale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildJournalTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: JuiceProgress(person: person),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Juice160 shows actual next rank and stage progress', (
    tester,
  ) async {
    await mount(tester);
    expect(find.text('Juice 160'), findsOneWidget);
    expect(find.text('Most attributes +30%'), findsOneWidget);
    expect(find.text('40 to Urban Commando (200)'), findsOneWidget);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      closeTo(.6, 1e-9),
    );
    expect(
      tester.getSize(key('juice-badge:${person.id}')).height,
      greaterThanOrEqualTo(44),
    );
  });

  testWidgets(
    'clickable help explains caps, rounding, capacity and distinct skill XP',
    (tester) async {
      await mount(tester);
      await tester.tap(key('juice-badge:${person.id}'));
      await tester.pumpAndSettle();
      expect(key('juice-help'), findsOneWidget);
      final texts = tester
          .widgetList<Text>(
            find.descendant(of: key('juice-help'), matching: find.byType(Text)),
          )
          .map((text) => text.data ?? '')
          .join('\n');
      expect(texts, contains('Wisdom is unaffected'));
      expect(texts, contains('before rounding'));
      expect(texts, contains('Direct recruits:'));
      expect(texts, contains('six-person squad limit'));
      expect(texts, contains('40 more Juice'));
      expect(texts, contains('Community Service can raise it to 10'));
      expect(texts, contains('Liberal Disobedience to 50'));
      expect(texts, contains('Hacking to 200'));
      expect(texts, contains('does not instantly add trained skill levels'));
      await tester.tap(key('juice-help-close'));
      await tester.pumpAndSettle();
      expect(key('juice-help'), findsNothing);
    },
  );

  for (final viewport in [
    (const Size(1024, 720), 1.5),
    (const Size(390, 844), 2.0),
  ]) {
    testWidgets(
      'Juice help remains readable and dismissible ${viewport.$1} ${viewport.$2}x',
      (tester) async {
        await mount(tester, size: viewport.$1, scale: viewport.$2);
        await tester.tap(key('juice-badge:${person.id}'));
        await tester.pumpAndSettle();
        final close = tester.getRect(key('juice-help-close'));
        expect(close.bottom, lessThanOrEqualTo(viewport.$1.height));
        expect(close.top, greaterThanOrEqualTo(0));
        expect(tester.takeException(), isNull);
        await tester.tap(key('juice-help-close'));
        await tester.pumpAndSettle();
        expect(key('juice-help'), findsNothing);
      },
    );
  }

  testWidgets(
    'negative, highest-rank and deceased records do not offer false progress',
    (tester) async {
      person.juice = -50;
      await mount(tester);
      expect(find.text('1 to Unstable (-49)'), findsOneWidget);
      expect(find.text('Most attributes reduced to 1'), findsOneWidget);
      person.juice = 1000;
      await tester.pumpWidget(const SizedBox.shrink());
      await mount(tester);
      expect(find.text('Highest Juice rank reached'), findsOneWidget);
      person.alive = false;
      await tester.pumpWidget(const SizedBox.shrink());
      await mount(tester);
      expect(find.text('Final Juice 1000'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.tap(key('juice-badge:${person.id}'));
      await tester.pumpAndSettle();
      expect(find.text('Earning Juice'), findsNothing);
      expect(find.textContaining('cannot act or progress'), findsOneWidget);
    },
  );

  testWidgets(
    'directory includes Juice in named rows and sorts without editing people',
    (tester) async {
      final controller = PersonnelDirectoryController();
      addTearDown(controller.dispose);
      final other =
          Creature.fromJson(
              jsonDecode(jsonEncode(person.toJson())) as Map<String, dynamic>,
            )
            ..id = 99991
            ..name = 'Veteran'
            ..juice = 500;
      final before = jsonEncode([person, other]);
      final semantics = tester.ensureSemantics();
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PersonnelDirectory(
                people: [person, other],
                controller: controller,
                onOpen: (_) {},
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Juice 160'), findsOneWidget);
        expect(
          find.bySemanticsLabel(
            RegExp('Open dossier for .*Juice 160.*Revolutionary'),
          ),
          findsOneWidget,
        );
        controller.selectSort(PersonnelSort.juice);
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(key('personnel-person:${other.id}')).dy,
          lessThan(tester.getTopLeft(key('personnel-person:${person.id}')).dy),
        );
        expect(jsonEncode([person, other]), before);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets(
    'live game help blocks game keys and preserves campaign and RNG',
    (tester) async {
      final location = game.activeSquad?.site ?? game.activeSafehouse;
      baseModeSquadSafehouseDisplay(location);
      baseModeOptionsDisplay(location);
      var consumed = false;
      late Future<int> reader;
      await tester.runAsync(() async {
        reader = engine.getKey().then((value) {
          consumed = true;
          return value;
        });
      });
      addTearDown(() async {
        if (!consumed) {
          await tester.runAsync(() async {
            engine.console.sendInput('Enter');
            await reader;
          });
        }
      });
      final before = jsonEncode(game.gameState);
      reseedRNG(seed: 69842);
      final expected = List.generate(8, (_) => lcsRandom(100000));
      reseedRNG(seed: 69842);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MainApp());
      await tester.pumpAndSettle();
      await tester.tap(key('hq-portrait:${person.id}').first);
      await tester.pumpAndSettle();
      await tester.tap(key('juice-badge:${person.id}').first);
      await tester.pumpAndSettle();
      expect(key('juice-help'), findsOneWidget);
      for (final key in [
        LogicalKeyboardKey.keyW,
        LogicalKeyboardKey.keyR,
        LogicalKeyboardKey.arrowRight,
      ]) {
        await tester.sendKeyEvent(key);
        await tester.pump();
      }
      expect(consumed, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(key('juice-help'), findsNothing);
      expect(consumed, isFalse);
      expect(jsonEncode(game.gameState), before);
      expect(List.generate(8, (_) => lcsRandom(100000)), expected);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
