import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/liberal_agenda.dart';
import 'package:lcs_new_age/engine/agenda_context.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/modern/journal_agenda.dart';
import 'package:lcs_new_age/modern/journal_shortcuts.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/law_help.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/politics/laws.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/interface_options.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

Future<void> ready() async {
  for (var step = 0; step < 500; step++) {
    if (engine.console.awaitingInput) return;
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  fail('The original agenda reader did not become ready.');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String fixture;
  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
    final font = FontLoader('JournalSerif')
      ..addFont(rootBundle.load('fonts/journal/LibreBaskerville-Variable.ttf'));
    await font.load();
  });
  setUp(() {
    engine.console = Console();
    game.gameState = decodeSaveContents(fixture).gameState!;
    game.mode = GameMode.base;
  });

  String snapshot() => jsonEncode(game.gameState.toJson());

  test('all law previews and comparisons preserve the save and RNG', () {
    final before = snapshot();
    reseedRNG(seed: 83214);
    final expected = List.generate(10, (_) => lcsRandom(100000));
    reseedRNG(seed: 83214);
    for (final law in Law.values) {
      final state = game.laws[law]!;
      final record = AgendaLaw(
        id: law.name,
        name: law.label,
        alignment: state,
        description: law.description[state.index + 1],
      );
      expect(lawHoverHelp(record), contains(law.label));
      expect(lawGameplayEffects(law), isNotEmpty);
      lawCombinationDetails(law);
      expect(lawPoliticalCalculations(law).join(), contains('Bill priority'));
      for (final level in DeepAlignment.values) {
        expect(lawLevelCalculations(law, level), isNotEmpty);
      }
    }
    expect(snapshot(), before);
    expect(List.generate(10, (_) => lcsRandom(100000)), expected);
  });

  test('linked authoritarian combinations require every component law', () {
    for (final law in [
      Law.military,
      Law.prisons,
      Law.privacy,
      Law.policeReform,
    ]) {
      game.laws[law] = DeepAlignment.archConservative;
    }
    expect(game.nineteenEightyFour, isTrue);
    expect(
      lawCombinationDetails(Law.military).join(),
      contains('1984 regime: conditions met'),
    );
    game.laws[Law.privacy] = DeepAlignment.conservative;
    expect(game.nineteenEightyFour, isFalse);
    expect(
      lawCombinationDetails(Law.military).join(),
      contains('1984 regime: conditions not met'),
    );
  });

  testWidgets(
    'a law guide opens without sending game input or changing state',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1024, 720);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final done = liberalAgenda();
      final sent = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildJournalTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(
            body: JournalAgendaView(
              console: engine.console,
              onAction: sent.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = snapshot();
      final target = find.byKey(const ValueKey('journal-law:drugs'));
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(find.text('Current calculations'), findsOneWidget);
      expect(find.text('Compare law levels'), findsOneWidget);
      expect(find.textContaining('Brownie income multiplier'), findsWidgets);
      expect(engine.console.awaitingInput, isTrue);
      expect(sent, isEmpty);
      expect(snapshot(), before);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Close law guide'));
      await tester.pumpAndSettle();
      engine.console.sendInput('Enter');
      await tester.pumpAndSettle();
      expect(await done, isFalse);
    },
  );

  test(
    'all five exact source pages preserve the campaign and random stream',
    () async {
      final before = snapshot();
      reseedRNG(seed: 31026);
      final rolls = List.generate(8, (_) => lcsRandom(100000));
      reseedRNG(seed: 31026);
      final done = liberalAgenda();
      for (var page = 0; page < 5; page++) {
        await ready();
        final frame = agendaOverviewFrame(engine.console)!;
        expect(frame.page, page);
        expect(frame.pageCount, 5);
        expect(frame.controls, engine.console.actions);
        expect(frame.controls.any((a) => a.key == 'd'), isTrue);
        if (page == 0) {
          expect(frame.offices.length, 4);
          expect(frame.court.length, game.politics.court.length);
          expect(
            frame.chambers.first.counts.reduce((a, b) => a + b),
            game.politics.house.length,
          );
          expect(
            frame.chambers.last.counts.reduce((a, b) => a + b),
            game.politics.senate.length,
          );
          expect(frame.laws.length, Law.values.length);
        } else if (page == 1 || page == 2) {
          expect(frame.polls, isNotEmpty);
          expect(frame.polls.every((p) => p.statement.isNotEmpty), isTrue);
          expect(
            frame.polls.every((p) => p.percentLabel.endsWith('%')),
            isTrue,
          );
          expect(frame.notes.isNotEmpty, page == 1);
        } else {
          final start = page == 3 ? 0 : 18;
          final expected = Law.values.skip(start).take(18).toList();
          expect(
            frame.laws.map((law) => law.id),
            expected.map((law) => law.name),
          );
          for (var i = 0; i < expected.length; i++) {
            final state = game.laws[expected[i]]!;
            expect(frame.laws[i].alignment, state);
            expect(
              frame.laws[i].description,
              expected[i].description[state.index + 1],
            );
          }
        }
        expect(snapshot(), before);
        engine.console.sendInput(page == 4 ? 'Enter' : interfacePgDown);
        await Future<void>.delayed(const Duration(milliseconds: 3));
      }
      expect(await done, isFalse);
      expect(agendaOverviewFrame(engine.console), isNull);
      expect(snapshot(), before);
      expect(List.generate(8, (_) => lcsRandom(100000)), rolls);
    },
  );

  for (final vibe in [
    AgendaVibe.liberalVictory,
    AgendaVibe.conservativeVictory,
  ]) {
    test(
      'forced $vibe retains its explicit original score-list exit',
      () async {
        final before = snapshot();
        final done = liberalAgenda(vibe);
        await ready();
        expect(agendaOverviewFrame(engine.console)!.endingTitle, isNotNull);
        expect(engine.console.screen, 'agenda-ending');
        expect(engine.console.navigation, isNull);
        expect(engine.console.actions.any((a) => a.key == 'l'), isTrue);
        engine.console.sendInput('l');
        expect(await done, isFalse);
        expect(snapshot(), before);
      },
    );
  }

  test(
    'disband phrase prompt never inherits an ongoing agenda frame',
    () async {
      final before = snapshot();
      final done = liberalAgenda();
      await ready();
      engine.console.sendInput('d');
      await Future<void>.delayed(const Duration(milliseconds: 3));
      await ready();
      expect(agendaOverviewFrame(engine.console), isNull);
      expect(engine.console.navigation, isNull);
      engine.console.sendInput('~');
      expect(await done, isFalse);
      expect(snapshot(), before);
    },
  );

  testWidgets('captured agenda controls reject a consumed source frame', (
    tester,
  ) async {
    final done = liberalAgenda();
    final sent = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: buildJournalTheme(),
        home: Scaffold(
          body: JournalAgendaView(console: engine.console, onAction: sent.add),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Previous page'), findsOneWidget);
    expect(find.text('Next page'), findsOneWidget);
    final button = tester.widget<OutlinedButton>(
      find.byKey(const ValueKey('journal-agenda-action:Enter')),
    );
    button.onPressed!();
    expect(sent, ['Enter']);
    engine.console.sendInput('Enter');
    await tester.pumpAndSettle();
    button.onPressed!();
    expect(sent, ['Enter']);
    expect(await done, isFalse);
  });

  for (final vibe in [
    AgendaVibe.liberalVictory,
    AgendaVibe.conservativeVictory,
  ]) {
    testWidgets(
      'ending $vibe exposes a readable score control without chapter navigation',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1024, 720);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final done = liberalAgenda(vibe);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildJournalTheme(),
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(10),
                child: JournalAgendaView(
                  console: engine.console,
                  onAction: engine.console.sendInput,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final frame = agendaOverviewFrame(engine.console)!;
        expect(frame.endingTitle, isNotNull);
        expect(engine.console.navigation, isNull);
        expect(find.text(frame.endingTitle!), findsOneWidget);
        final score = find.byKey(const ValueKey('journal-agenda-action:l'));
        expect(score.hitTestable(), findsOneWidget);
        expect(
          tester.getRect(score).bottom,
          lessThanOrEqualTo(
            tester.view.physicalSize.height / tester.view.devicePixelRatio,
          ),
        );
        expect(find.textContaining('<——'), findsNothing);
        await tester.tap(score);
        await tester.pumpAndSettle();
        expect(await done, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final size in [
    const Size(1280, 720),
    const Size(1024, 720),
    const Size(360, 640),
  ]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets(
        'all agenda pages remain readable and navigable at $size / $scale',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(() async {
            await tester.pumpWidget(const SizedBox.shrink());
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });
          final done = liberalAgenda();
          await tester.pumpWidget(
            MaterialApp(
              theme: buildJournalTheme(),
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Scaffold(
                  body: Padding(
                    padding: const EdgeInsets.all(10),
                    child: JournalAgendaView(
                      console: engine.console,
                      onAction: engine.console.sendInput,
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          for (var page = 0; page < 5; page++) {
            expect(agendaOverviewFrame(engine.console)!.page, page);
            for (final action in agendaOverviewFrame(
              engine.console,
            )!.controls) {
              expect(
                tester
                    .widget<JournalShortcutBadge>(
                      find.descendant(
                        of: find.byKey(
                          ValueKey('journal-agenda-action:${action.key}'),
                        ),
                        matching: find.byType(JournalShortcutBadge),
                      ),
                    )
                    .shortcut,
                action.key,
              );
            }
            expect(find.textContaining('<——'), findsNothing);
            expect(tester.takeException(), isNull);
            if (page == 0) expect(find.text('Supreme Court'), findsOneWidget);
            final key = page == 4 ? 'Enter' : interfacePgDown;
            final button = find.byKey(ValueKey('journal-agenda-action:$key'));
            await tester.ensureVisible(button);
            await tester.tap(button);
            await tester.pumpAndSettle();
          }
          expect(await done, isFalse);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
