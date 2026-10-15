import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/common_display/print_creature_info.dart';
import 'package:lcs_new_age/daily/activities/car_theft.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/modern/journal_person_summary.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

Object buffer(Console console) => [
  for (final row in console.buffer)
    [
      for (final cell in row)
        [
          cell.glyph,
          cell.foreground.toARGB32(),
          cell.background.toARGB32(),
          cell.mouseClickKey,
        ],
    ],
];

void main() {
  setUpAll(() async {
    await ensureGameDataLoaded();
    final font = FontLoader('JournalSerif')
      ..addFont(rootBundle.load('fonts/journal/LibreBaskerville-Variable.ttf'));
    await font.load();
  });
  setUp(() async {
    engine.console = Console();
    journalReadingScale.value = 1;
    game.gameState = decodeSaveContents(
      await File('test/saves/felix_1_0.json').readAsString(),
    ).gameState!;
    game.mode = GameMode.base;
  });

  for (final key in ['Enter', 'Space', 'Escape']) {
    test(
      'current report keeps one $key reader and leaves engine state intact',
      () async {
        engine.mvaddstr(0, 0, 'STALE headquarters and old money');
        engine.addOptionText(19, 0, 'f', 'F - STALE departure menu');
        final previous = engine.getKey();
        engine.console.sendInput('Enter');
        await previous;
        engine.mvaddstr(8, 1, 'A current result.');
        engine.mvaddstr(10, 1, 'A second current paragraph.');
        final originalBuffer = buffer(engine.console);
        final originalState = jsonEncode(game.gameState.toJson());
        reseedRNG(seed: 8755);
        final roll = lcsRandom(100000);
        reseedRNG(seed: 8755);
        final revision = engine.console.revision.value;
        final notice = engine.acknowledge(title: 'Daily report');
        expect(
          engine.console.eventMessage,
          'A current result.\nA second current paragraph.',
        );
        expect(engine.console.eventTitle, 'Daily report');
        expect(engine.console.revision.value, revision + 1);
        expect(buffer(engine.console), originalBuffer);
        expect(jsonEncode(game.gameState.toJson()), originalState);
        expect(lcsRandom(100000), roll);
        engine.console.sendInput(key);
        await notice;
        expect(engine.console.eventMessage, isNull);
        expect(engine.console.awaitingInput, isFalse);
        expect(engine.console.sendInput('Enter'), isFalse);
      },
    );
  }

  test(
    'results overwrite a stale choice without masking the new message',
    () async {
      engine.addOptionText(8, 1, 'a', 'A - An old choice with a long label');
      final reader = engine.getKey();
      engine.console.sendInput('a');
      await reader;
      engine.mvaddstr(8, 1, 'The new result.');
      final notice = engine.acknowledge();
      expect(engine.console.eventMessage, 'The new result.');
      engine.console.sendInput('Enter');
      await notice;
    },
  );

  test('no writes and specialized maps retain their original reader', () async {
    engine.console.screen = 'full_map';
    engine.mvaddstr(0, 0, 'Full floor map');
    final map = engine.acknowledge();
    expect(engine.console.eventMessage, isNull);
    engine.console.sendInput('Enter');
    await map;
    final empty = engine.acknowledge();
    expect(engine.console.eventMessage, isNull);
    engine.console.sendInput('Enter');
    await empty;
  });

  test(
    'field reports retain lower narrative rows and exclude the ASCII map',
    () async {
      engine.console.screen = 'field_prompt';
      engine.console.journalBodyStart = 9;
      engine.mvaddstr(9, 1, 'The encounter continues.');
      engine.mvaddstr(12, 1, 'A further spoken response.');
      engine.mvaddstr(12, 55, 'MAPXXX');
      final notice = engine.acknowledge(title: 'Operation report');
      expect(
        engine.console.eventMessage,
        'The encounter continues.\nA further spoken response.',
      );
      engine.console.sendInput('Enter');
      await notice;
    },
  );

  Future<void> mount(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    journalReadingScale.value = 1.5;
    await tester.pumpWidget(
      const RepaintBoundary(key: ValueKey('audit-capture'), child: MainApp()),
    );
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final directory = Platform.environment['JOURNAL_AUDIT_SCREENSHOTS'];
    if (directory == null) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('audit-capture')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(directory).create(recursive: true);
      await File(
        '$directory/$name.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final size in [const Size(1280, 720), const Size(800, 600)]) {
    testWidgets('crew summaries replace status furniture at $size / 150%', (
      tester,
    ) async {
      final person = game.squad.first;
      engine.mvaddstr(0, 0, 'STALE location, activity and money');
      printCreatureInfo(person, knowledge: 0);
      engine.addOptionText(10, 0, 'a', 'A - Proceed with the current choice');
      final reader = engine.getKey();
      await mount(tester, size);
      expect(find.byType(JournalPersonCard), findsOneWidget);
      expect(find.textContaining('STALE'), findsNothing);
      expect(
        find.byTooltip('Inspect ${person.name}'),
        findsNothing,
        reason: 'Restricted status does not unlock a complete dossier.',
      );
      final card = tester.widget<JournalPersonCard>(
        find.byType(JournalPersonCard),
      );
      expect(card.summary.details.any((line) => line.contains('?')), isTrue);
      await capture(tester, 'crew-${size.width.toInt()}');
      engine.console.sendInput('Enter');
      await reader;
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'real car-theft list and its reports use the journal at $size',
      (tester) async {
        var finished = false;
        final scene = CarTheftScene(
          game.squad.first,
        ).play().then((_) => finished = true);
        await mount(tester, size);
        final choice = engine.console.actions.firstWhere((a) => a.key == 'a');
        expect(choice.label, isNotEmpty);
        engine.console.sendInput('a');
        await tester.pumpAndSettle();
        expect(engine.console.eventTitle, 'Vehicle report');
        expect(
          find.textContaining('looks around for an accessible vehicle'),
          findsOneWidget,
        );
        expect(find.textContaining('Transp:'), findsNothing);
        await capture(tester, 'vehicle-report-${size.width.toInt()}');
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        expect(engine.console.eventTitle, 'Vehicle report');
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        // The next scene is the original approach/call-it-a-day decision.
        engine.console.sendInput('Enter');
        await tester.pumpAndSettle();
        await scene;
        expect(finished, isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('original personnel pages use the native dossier at $size', (
      tester,
    ) async {
      final person = game.squad.first;
      final profile = fullCreatureInfoScreen(person);
      await mount(tester, size);
      expect(
        find.byKey(const ValueKey('journal-personnel-profile')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('direct-data-table')), findsNothing);
      engine.console.sendInput('Down');
      await tester.pumpAndSettle();
      expect(engine.console.journalProfile!.page, 1);
      expect(find.text('Skills & training'), findsOneWidget);
      await capture(tester, 'profile-skills-${size.width.toInt()}');
      engine.console.sendInput('Down');
      await tester.pumpAndSettle();
      expect(engine.console.journalProfile!.page, 2);
      expect(find.text('Legal record'), findsOneWidget);
      engine.console.sendInput('Enter');
      await tester.pump();
      await profile;
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
