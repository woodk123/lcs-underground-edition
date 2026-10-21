import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' hide Alignment;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activate_regulars.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/basemode/liberal_agenda.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/daily/dating.dart';
import 'package:lcs_new_age/daily/hostages/tend_hostage.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/saveload/storage/game_storage.dart';
import 'package:lcs_new_age/title_screen/game_over.dart';
import 'package:lcs_new_age/title_screen/high_scores.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screen_capture_support.dart';
import 'test_support.dart';

class _ScreenStorage implements GameStorage {
  @override
  Future<void> init() async {}
  @override
  Future<void> close() async {}
  @override
  Future<List<String>> listGameIds() async => [];
  @override
  Future<SaveFile?> loadGame(String id) async => null;
  @override
  Future<void> saveGame(SaveFile file) async {}
  @override
  Future<void> deleteGame(String id) async {}
  @override
  Future<void> updateLastGameId(String id) async {}
}

void main() {
  late String fixture;
  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
    final font = FontLoader('JournalSerif')
      ..addFont(rootBundle.load('fonts/journal/LibreBaskerville-Variable.ttf'));
    await font.load();
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initStorage(storage: _ScreenStorage());
    engine.console = Console();
    game.gameState = decodeSaveContents(fixture).gameState!;
    game.mode = GameMode.base;
    game.activeSquadMember = null;
    journalReadingScale.value = 1;
  });
  Future<void> mount(WidgetTester tester, Size size, double scale) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    journalReadingScale.value = scale;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      journalReadingScale.value = 1;
    });
    await tester.pumpWidget(
      const RepaintBoundary(key: screenCaptureKey, child: MainApp()),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await capturePlaytestScreen(tester, 'orders-social');
  }

  Future<void> key(WidgetTester tester, String key) async {
    expect(engine.console.sendInput(key), isTrue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await capturePlaytestScreen(tester, 'orders-social');
  }

  Future<void> action(WidgetTester tester, String key) async {
    final source = engine.console.actions.firstWhere(
      (a) => a.key == normalizeConsoleKey(key) && a.enabled,
    );
    final direct = find.byKey(
      ValueKey('direct-action:${source.y}:${source.x}:${source.key}'),
    );
    final cleaned =
        source.intentLabel ??
        source.label.replaceFirst(RegExp(r'^\S+\s+-\s*'), '').trim();
    final finder = direct.evaluate().isNotEmpty
        ? direct
        : find.text(cleaned, findRichText: true).first;
    expect(
      finder,
      findsOneWidget,
      reason: '${source.label} must have a visible control',
    );
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await capturePlaytestScreen(tester, 'orders-social');
  }

  for (final (size, scale) in [
    (const Size(1280, 800), 1.0),
    (const Size(1024, 720), 1.5),
  ]) {
    final variant = '${size.width} / $scale';
    for (final vibe in [
      AgendaVibe.liberalVictory,
      AgendaVibe.conservativeVictory,
    ]) {
      testWidgets('$vibe ending pages and source score exit at $variant', (
        tester,
      ) async {
        final flow = liberalAgenda(vibe);
        await mount(tester, size, scale);
        for (var page = 0; page < 5; page++) {
          expect(engine.console.screen, 'agenda-ending');
          await action(tester, ']');
        }
        await action(tester, 'l');
        expect(await flow, isFalse);
      });
    }
    testWidgets(
      'completed high scores render and Continue returns at $variant',
      (tester) async {
        await saveHighScore(Ending.victory);
        await saveHighScore(Ending.dead);
        final flow = viewHighScores();
        await mount(tester, size, scale);
        expect(
          find.textContaining('Liberal ELITE', findRichText: true),
          findsWidgets,
        );
        final continueButton = find.text('Continue').first;
        await tester.ensureVisible(continueButton);
        await tester.tap(continueButton);
        await tester.pumpAndSettle();
        await flow;
      },
    );
    for (final (label, category, choice, expected) in [
      ('free practice', 'e', '1', ActivityType.study),
      ('paid classes', 'e', '2', ActivityType.takeClass),
      ('clothing crafting', 'd', '3', ActivityType.makeClothing),
      ('flag crafting', 'd', '4', ActivityType.makeFlag),
    ]) {
      testWidgets('$label real selector and confirmation at $variant', (
        tester,
      ) async {
        final actor = game.pool.first;
        final flow = assignTask(actor);
        await mount(tester, size, scale);
        await key(tester, category);
        await key(tester, choice);
        expect(engine.console.awaitingInput, isTrue);
        expect(
          find.text('Press a Letter to sel', findRichText: true),
          findsNothing,
        );
        expect(find.text('ect a', findRichText: true), findsNothing);
        expect(engine.console.actions.where((a) => a.enabled), isNotEmpty);
        final next = engine.console.actions.where(
          (a) => a.key == 'PageDown' || a.key == ']',
        );
        if (next.isNotEmpty) {
          await action(tester, next.first.key);
          final previous = engine.console.actions.firstWhere(
            (a) => a.key == 'PageUp' || a.key == '[',
          );
          await action(tester, previous.key);
        }
        await action(tester, 'a');
        if (expected == ActivityType.makeClothing ||
            expected == ActivityType.makeFlag) {
          await key(tester, 'Enter');
        }
        expect(actor.activity.type, expected);
        await key(tester, 'Enter');
        await flow;
      });
    }

    for (final remote in [false, true]) {
      testWidgets(
        '${remote ? 'remote' : 'local'} date choices and breakup at $variant',
        (tester) async {
          final actor = game.pool.first;
          // A declared eligible adult date at a valid workplace, not an earned relationship.
          final date = Creature.fromJson(
            jsonDecode(jsonEncode(game.pool.last.toJson()))
                as Map<String, dynamic>,
          )..id = game.gameState.nextCreatureId++;
          date.align = Alignment.moderate;
          if (remote) {
            date.location = game.sites.firstWhere(
              (s) => s.city != actor.location!.city,
            );
          }
          final session = DatingSession(actor.id, actor.location!.city)
            ..dates.add(date);
          final beforeFunds = game.ledger.funds;
          final flow = completeDate(session, actor);
          await mount(tester, size, scale);
          await key(tester, 'Enter');
          expect(engine.console.actions.any((a) => a.key == 'd'), isTrue);
          expect(
            engine.console.actions.firstWhere((a) => a.key == 'a').enabled,
            isFalse,
          );
          await action(tester, 'd');
          // The original breakup produces a report before returning.
          if (engine.console.awaitingInput) await key(tester, 'Enter');
          await flow;
          expect(session.dates, isEmpty);
          expect(game.ledger.funds, beforeFunds);
        },
      );
    }

    testWidgets('hostage plan toggles and release at $variant', (tester) async {
      final actor = game.pool.first;
      final hostage = game.pool.last;
      hostage.align = Alignment.conservative;
      hostage.squad = null;
      hostage.location = actor.location;
      actor.activity = Activity(ActivityType.interrogation, idInt: hostage.id);
      final session = InterrogationSession(hostage.id)
        ..techniques[Technique.restrain] = true;
      final flow = tendHostage(session);
      await mount(tester, size, scale);
      final release = engine.console.actions.firstWhere((a) => a.key == 'f');
      await action(tester, release.key);
      expect(session.techniques[Technique.free], isTrue);
      await action(tester, 'Enter');
      // Release may author several reports; acknowledge each current reader.
      var finished = false;
      unawaited(flow.then((_) => finished = true));
      for (var i = 0; i < 12 && !finished; i++) {
        await tester.pump();
        if (engine.console.awaitingInput) await key(tester, 'Enter');
      }
      expect(finished, isTrue);
      await flow;
      expect(game.pool.contains(hostage), isFalse);
    });
  }
}
