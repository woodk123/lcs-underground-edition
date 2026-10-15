import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/engine/changelog.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/sitemode/sitemap.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(ensureGameDataLoaded);
  setUp(() async {
    journalReadingScale.value = 1;
    engine.console = Console();
    game.gameState = decodeSaveContents(
      await File('test/saves/felix_1_0.json').readAsString(),
    ).gameState!;
  });

  Future<void> mount(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(const MainApp());
    await tester.pumpAndSettle();
  }

  for (final size in [const Size(1280, 720), const Size(800, 600)]) {
    testWidgets('field plan and commands share the journal at $size/150%', (
      tester,
    ) async {
      game.mode = GameMode.site;
      game.locx = 35;
      game.locy = 11;
      game.locz = 0;
      levelMap = List.generate(
        MAPX,
        (x) => List.generate(
          MAPY,
          (y) => List.generate(MAPZ, (z) => SiteTile(x, y, z)),
        ),
      );
      levelMap[35][11][0].known = true;
      engine.console.screen = 'tactical';
      engine.mvaddstr(0, 0, 'Original field operation');
      engine.addOptionText(2, 0, '1', '1 - Felix Kobayashi');
      engine.addOptionText(23, 70, 'l', 'Reload');
      String? received;
      final reader = engine.console.getkey().then((value) => received = value);
      final before = jsonEncode(game.gameState.toJson());
      reseedRNG(seed: 8493);
      final random = lcsRandom(100000);
      reseedRNG(seed: 8493);
      await mount(tester, size);
      journalReadingScale.value = 1.5;
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('journal-specialist-shell')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('journal-operation-report')),
        findsOneWidget,
      );
      expect(find.text('Reload').hitTestable(), findsOneWidget);
      final reportScroll = tester.widget<Scrollbar>(
        find.descendant(
          of: find.byKey(const ValueKey('journal-operation-report')),
          matching: find.byType(Scrollbar),
        ),
      );
      expect(reportScroll.thumbVisibility, isTrue);
      expect(reportScroll.controller, isNotNull);
      final controls = tester.getRect(
        find.byKey(const ValueKey('journal-operation-controls')),
      );
      expect(controls.top, greaterThanOrEqualTo(0));
      expect(controls.bottom, lessThanOrEqualTo(size.height));
      expect(find.text('Headquarters'), findsNothing);
      expect(jsonEncode(game.gameState.toJson()), before);
      expect(lcsRandom(100000), random);
      await tester.tap(find.text('Reload'));
      await tester.pump();
      await reader;
      expect(received, 'l');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final mode in [
    GameMode.base,
    GameMode.site,
    GameMode.carChase,
    GameMode.footChase,
  ]) {
    testWidgets('specialist decisions use journal styling in ${mode.name}', (
      tester,
    ) async {
      game.mode = mode;
      engine.mvaddstr(0, 0, 'A source-authored decision');
      engine.addOptionText(7, 0, 'a', 'A - Original choice');
      String? received;
      final reader = engine.console.getkey().then((value) => received = value);
      await mount(tester, const Size(800, 600));
      expect(
        find.byKey(const ValueKey('journal-specialist-shell')),
        findsOneWidget,
      );
      expect(find.text('AVAILABLE CHOICES'), findsNothing);
      final text = find.text('Original choice');
      final element = text.evaluate().single;
      expect(
        DefaultTextStyle.of(
          element,
        ).style.merge((element.widget as Text).style).fontFamily,
        JournalPalette.serif,
      );
      await tester.tap(text);
      await tester.pump();
      await reader;
      expect(received, 'a');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'changelog respects large reading, closes and restores game focus',
    (tester) async {
      engine.console.screen = 'title';
      engine.addOptionText(13, 0, 'n', 'N - Start a New Game');
      String? received;
      final reader = engine.console.getkey().then((value) => received = value);
      await mount(tester, const Size(800, 600));
      journalReadingScale.value = 1.5;
      ChangelogWidget.globalKey.currentState!.show(
        '# Update\n\n${'A complete change entry.\n\n' * 30}',
      );
      await tester.pumpAndSettle();
      expect(find.text('Campaign changelog'), findsOneWidget);
      expect(find.byTooltip('Close changelog').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Close changelog'));
      await tester.pumpAndSettle();
      expect(received, isNull);
      expect(engine.console.awaitingInput, isTrue);
      await tester.tap(find.text('Start a New Game'));
      await tester.pump();
      await reader;
      expect(received, 'n');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
