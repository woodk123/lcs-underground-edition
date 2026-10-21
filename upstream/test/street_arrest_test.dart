import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/daily/activities/fundraising.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/engine/pursuit_context.dart';
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/justice/crimes.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/modern/journal_pursuit.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

String _snapshot() => jsonEncode(game.gameState.toJson());
Finder _action(String key) =>
    find.byKey(ValueKey('journal-pursuit-action:$key'));

Future<void> _drive(
  Future<void> Function() operation,
  String Function(PursuitContext? frame) choose,
) async {
  var prompt = 0;
  final failed = Completer<void>();
  void respond() {
    if (!engine.console.awaitingInput || engine.console.lastKey != null) return;
    try {
      if (prompt++ > 100) throw StateError('Unexpected street arrest reader.');
      expect(
        engine.console.sendInput(choose(pursuitContext(engine.console))),
        isTrue,
      );
    } catch (error, stack) {
      if (!failed.isCompleted) failed.completeError(error, stack);
    }
  }

  engine.console.revision.addListener(respond);
  try {
    await Future.any([
      operation(),
      failed.future,
    ]).timeout(const Duration(seconds: 5));
  } finally {
    engine.console.revision.removeListener(respond);
  }
}

/// Calls the original daily activity repeatedly. Only clothing is prepared;
/// the game's ordinary draws decide which attempt encounters the police.
Future<void> _fundraiseUntilArrest(
  Creature person, {
  void Function(int funds, int income)? beforeAttempt,
}) async {
  for (var attempt = 0; attempt < 40 && !person.imprisoned; attempt++) {
    beforeAttempt?.call(game.ledger.funds, person.income);
    await doActivitySolicitDonations([person]);
  }
  if (!person.imprisoned) {
    throw StateError(
      'Natural indecency checks did not reach a police pursuit.',
    );
  }
}

class _StreetHarness {
  _StreetHarness(Creature person) {
    void initialReports() {
      if (!engine.console.awaitingInput || engine.console.lastKey != null) {
        return;
      }
      if (pursuitContext(engine.console) != null) {
        engine.console.revision.removeListener(initialReports);
      } else if (engine.console.eventMessage != null) {
        engine.console.sendInput('Enter');
      }
    }

    engine.console.revision.addListener(initialReports);
    unawaited(
      _run(person).whenComplete(
        () => engine.console.revision.removeListener(initialReports),
      ),
    );
  }

  bool returned = false, finished = false;
  Future<void> _run(Creature person) async {
    try {
      await _fundraiseUntilArrest(person);
      returned = true;
      engine.erase();
      engine.console.screen = 'headquarters';
      await engine.getKey();
    } finally {
      finished = true;
    }
  }

  Future<void> stop(WidgetTester tester) async {
    for (var i = 0; i < 100 && !finished; i++) {
      if (engine.console.awaitingInput) {
        engine.console.sendInput(
          pursuitContext(engine.console) == null ? 'Enter' : 'g',
        );
      }
      await tester.pump(const Duration(milliseconds: 5));
    }
    expect(finished, isTrue);
  }
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
    game.gameState = decodeSaveContents(fixture).gameState!;
    game.mode = GameMode.base;
    game.activeSquadMemberIndex = 1;
    engine.console = Console();
    journalReadingScale.value = 1;
    for (final person in game.pool) {
      person.wantedForCrimes.updateAll((crime, count) => 0);
      person.heat = 0;
      person.activity = Activity.none();
    }
    game.squad.last.equippedClothing = null;
    game.squad.last.activity = Activity(ActivityType.donations);
    reseedRNG(seed: 20261016);
  });

  for (final seed in [0, 20261016]) {
    test(
      'natural street arrest confiscates equipment and restores the squad at seed $seed',
      () async {
        final person = game.squad.last;
        final founder = game.pool.first;
        final oldSquad = game.activeSquad!;
        final oldSelection = game.activeSquadMemberIndex;
        final oldSquads = game.squads.toList();
        final portrait = person.portraitId;
        expect(person.equippedWeapon, isNotNull);
        expect(person.spareAmmo, isNotNull);
        expect(person.imprisoned, isFalse);
        var fundsBeforeAttempt = 0, incomeBeforeAttempt = 0;
        var pursuitReaders = 0, equipmentReaders = 0;
        var accostSeen = false, soloIntroSeen = false, arrestSeen = false;
        late PursuitContext firstFrame;
        late ConsoleAction firstSurrender;
        reseedRNG(seed: seed);
        await _drive(
          () => _fundraiseUntilArrest(
            person,
            beforeAttempt: (funds, income) {
              fundsBeforeAttempt = funds;
              incomeBeforeAttempt = income;
            },
          ),
          (frame) {
            if (frame != null) {
              expect(frame.people.single.person, same(person));
              expect(frame.encounterLines, isNotEmpty);
              expect(
                frame.actions.map((action) => action.key),
                containsAll(['d', 'f', 'e', 'o', 'g', '0', '1']),
              );
              expect(
                frame.actions
                    .singleWhere((action) => action.key == 'o')
                    .enabled,
                isFalse,
              );
              expect(game.ledger.funds, fundsBeforeAttempt);
              expect(person.income, incomeBeforeAttempt);
              if (pursuitReaders++ == 0) {
                firstFrame = frame;
                firstSurrender = frame.actions.singleWhere(
                  (action) => action.key == 'g',
                );
                return '?';
              }
              expect(identical(frame, firstFrame), isFalse);
              expect(frame.actions.contains(firstSurrender), isFalse);
              expect(
                pursuitActionIsCurrent(
                  engine.console,
                  firstFrame,
                  firstSurrender,
                  engine.console.revision.value,
                ),
                isFalse,
              );
              return pursuitReaders == 2 ? 'e' : 'g';
            }
            final report = engine.console.eventMessage;
            if (report != null) {
              accostSeen |= report.contains(
                'accosted by police while soliciting',
              );
              soloIntroSeen |= report.contains('is being pursued on foot');
              arrestSeen |= report.contains('You stop and are arrested.');
              expect(report, isNot(contains('As you exit the site')));
            } else if (engine.console.actions.any(
              (action) =>
                  action.key == 'Enter' && action.label.contains('Done'),
            )) {
              equipmentReaders++;
              expect(engine.console.pursuit, isNull);
              expect(
                engine.console.actions.any((action) => action.key == 'g'),
                isFalse,
              );
            } else {
              fail(
                'Unexpected input outside pursuit or its equipment/report readers.',
              );
            }
            return 'Enter';
          },
        );
        expect(pursuitReaders, 3);
        expect(equipmentReaders, 1);
        expect(accostSeen && soloIntroSeen && arrestSeen, isTrue);
        expect(person.wantedForCrimes[Crime.disturbingThePeace], 1);
        expect(person.wantedForCrimes[Crime.resistingArrest], 0);
        expect(person.site!.type, SiteType.policeStation);
        expect(person.squad, isNull);
        expect(person.carId, isNull);
        expect(person.equippedWeapon, isNull);
        expect(person.spareAmmo, isNull);
        expect(person.activity.type, ActivityType.none);
        expect(person.portraitId, portrait);
        expect(person.income, incomeBeforeAttempt);
        expect(game.ledger.funds, fundsBeforeAttempt);
        expect(founder.imprisoned, isFalse);
        expect(founder.location, founder.base);
        expect(game.activeSquad, same(oldSquad));
        expect(game.activeSquadMemberIndex, oldSelection);
        expect(oldSquad.members.contains(person), isFalse);
        expect(game.squads, oldSquads);
        expect(game.mode, GameMode.base);
        expect(pursuitContext(engine.console), isNull);
      },
    );
  }

  Future<_StreetHarness> mount(
    WidgetTester tester, {
    Size size = const Size(1200, 800),
    double scale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    journalReadingScale.value = scale;
    final harness = _StreetHarness(game.squad.last);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await harness.stop(tester);
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(const MainApp());
    await tester.pumpAndSettle();
    expect(find.byType(JournalPursuitView), findsOneWidget);
    return harness;
  }

  testWidgets(
    'pursuit modal inspection blocks keys and consumes no state or rolls',
    (tester) async {
      await mount(tester);
      final person = game.squad.single;
      final before = _snapshot();
      final revision = engine.console.revision.value;
      reseedRNG(seed: 9086);
      final expectedRoll = lcsRandom(100000);
      reseedRNG(seed: 9086);
      final surrender = tester.widget<OutlinedButton>(_action('g')).onPressed!;
      await tester.tap(find.byTooltip('Inspect ${person.name}'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Close dossier'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      surrender();
      await tester.pumpAndSettle();
      expect(engine.console.revision.value, revision);
      expect(_snapshot(), before);
      expect(lcsRandom(100000), expectedRoll);
      await tester.tap(find.byTooltip('Close dossier'));
      await tester.pumpAndSettle();
      expect(_action('g').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pursuit rejects callbacks from earlier revisions and action objects',
    (tester) async {
      await mount(tester);
      final before = _snapshot();
      final first = tester.widget<OutlinedButton>(_action('g')).onPressed!;
      engine.console.flush();
      first();
      expect(engine.console.lastKey, isNull);
      await tester.pumpAndSettle();
      final current = tester.widget<OutlinedButton>(_action('g')).onPressed!;
      final index = engine.console.actions.indexWhere(
        (action) => action.key == 'g',
      );
      engine.console.actions[index] = const ConsoleAction(
        key: 'g',
        label: 'A later reader',
        enabled: true,
        y: 0,
        x: 0,
        width: 14,
      );
      current();
      expect(engine.console.lastKey, isNull);
      expect(_snapshot(), before);
      // Restore via an actual invalid input, republishing the original reader.
      engine.console.sendInput('?');
      await tester.pumpAndSettle();
      expect(_action('g').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'real surrender remains visible at 1024x720 with 150 percent text',
    (tester) async {
      final harness = await mount(
        tester,
        size: const Size(1024, 720),
        scale: 1.5,
      );
      expect(find.text('On-foot pursuit'), findsOneWidget);
      expect(find.text('Give up and surrender').hitTestable(), findsOneWidget);
      expect(_action('e').hitTestable(), findsOneWidget);
      expect(
        tester.getRect(_action('g')).bottom,
        lessThanOrEqualTo(
          tester.view.physicalSize.height / tester.view.devicePixelRatio,
        ),
      );
      engine.console.sendInput('?');
      await tester.pumpAndSettle();
      expect(_action('g').hitTestable(), findsOneWidget);
      await tester.tap(_action('g'));
      await tester.pumpAndSettle();
      expect(find.byType(JournalPursuitView), findsNothing);
      expect(find.text('You stop and are arrested.'), findsOneWidget);
      expect(find.text('Give up and surrender'), findsNothing);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(harness.returned, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
