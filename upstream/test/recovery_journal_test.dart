import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/daily/advance_day.dart';
import 'package:lcs_new_age/daily/shopsnstuff.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/engine/recovery_context.dart';
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/gamestate/ledger.dart';
import 'package:lcs_new_age/justice/crimes.dart';
import 'package:lcs_new_age/justice/trial.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/modern/crew_portrait.dart';
import 'package:lcs_new_age/modern/journal_recovery.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/organisation_journal.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/game_version.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

String _snapshot() => jsonEncode(game.gameState.toJson());
Finder _action(String key) =>
    find.byKey(ValueKey('journal-recovery-action:$key'));

Future<void> _drive(
  Future<void> Function() operation,
  String Function(RecoveryContext? frame, int prompt) choose,
) async {
  var prompt = 0;
  final failed = Completer<void>();
  void respond() {
    if (!engine.console.awaitingInput || engine.console.lastKey != null) return;
    try {
      if (prompt >= 100) throw StateError('Unexpected recovery input loop.');
      final key = choose(recoveryContext(engine.console), prompt++);
      expect(engine.console.sendInput(key), isTrue);
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

Creature _hospitalPatient({int bill = 250}) {
  final patient = game.squad.last;
  patient.squad = null;
  patient.location = game.sites.firstWhere(
    (site) =>
        site.type == SiteType.universityHospital &&
        site.city == patient.base!.city,
  );
  patient.activity = Activity(ActivityType.clinic);
  patient.daysHospitalized = 9;
  patient.medicalBills = bill;
  return patient;
}

void _roundTrip() {
  final before = _snapshot();
  game.gameState = game.GameState.fromJson(
    jsonDecode(before) as Map<String, dynamic>,
  );
  expect(_snapshot(), before);
  final exported = jsonEncode(
    SaveFile(
      version: saveCompatibilityVersion,
      saveData: game.gameState.toJson(),
      gameId: game.gameState.uniqueGameId.toString(),
      lastPlayed: DateTime(2026, 10, 16),
    ).toJson(),
  );
  final imported = decodeSaveContents(exported);
  expect(imported.gameState, isNotNull);
  game.gameState = imported.gameState!;
  expect(_snapshot(), before);
}

class _RecoveryHarness {
  _RecoveryHarness(Future<void> Function() operation) {
    // Court charge acknowledgements precede the required defense reader. Only
    // those authored announcements are advanced before the widget is mounted.
    void initialAnnouncements() {
      if (!engine.console.awaitingInput || engine.console.lastKey != null) {
        return;
      }
      if (recoveryContext(engine.console) != null) {
        engine.console.revision.removeListener(initialAnnouncements);
      } else if (engine.console.eventMessage != null) {
        engine.console.sendInput('Enter');
      }
    }

    engine.console.revision.addListener(initialAnnouncements);
    unawaited(
      _run(operation).whenComplete(
        () => engine.console.revision.removeListener(initialAnnouncements),
      ),
    );
  }

  bool returned = false, finished = false;
  Future<void> _run(Future<void> Function() operation) async {
    try {
      await operation();
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
        final scene = recoveryContext(engine.console)?.scene;
        engine.console.sendInput(
          scene == RecoveryScene.discharge
              ? 'b'
              : scene == RecoveryScene.defense
              ? 'c'
              : 'Enter',
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
    game.activeSquadMemberIndex = -1;
    engine.console = Console();
    journalReadingScale.value = 1;
    reseedRNG(seed: 20261016);
  });

  test(
    'paid discharge settles the exact debt and retains patient identity',
    () async {
      final patient = _hospitalPatient();
      game.ledger.forceSetFunds(1000);
      final date = game.date;
      final portrait = patient.portraitId;
      final equipment = jsonEncode([
        patient.equippedWeapon?.toJson(),
        patient.spareAmmo?.toJson(),
        patient.equippedClothing?.toJson(),
      ]);
      final bills = game.ledger.expense[Expense.hospitalBills] ?? 0;
      late RecoveryContext first;
      late ConsoleAction firstPayment;
      var decisions = 0;
      await _drive(() => dischargeHospitalPatient(patient), (frame, _) {
        expect(frame!.scene, RecoveryScene.discharge);
        expect(frame.note, contains('outside all squads'));
        expect(frame.note, contains('Join squad'));
        expect(frame.people.single.person, same(patient));
        expect(frame.actions.map((action) => action.key), ['a', 'b']);
        final payment = frame.actions.first;
        expect(payment.enabled, isTrue);
        if (decisions++ == 0) {
          first = frame;
          firstPayment = payment;
          return 'Enter'; // Invalid input must reauthor the exact bill choices.
        }
        expect(frame, isNot(same(first)));
        expect(payment, isNot(same(firstPayment)));
        expect(
          recoveryActionIsCurrent(
            engine.console,
            first,
            firstPayment,
            engine.console.revision.value,
          ),
          isFalse,
        );
        return payment.key;
      });
      expect(decisions, 2);
      expect(patient.medicalBills, 0);
      expect(patient.daysHospitalized, 0);
      expect(patient.location, patient.base);
      expect(patient.squad, isNull);
      expect(patient.activity.type, ActivityType.none);
      expect(game.ledger.funds, 750);
      expect(game.ledger.expense[Expense.hospitalBills], bills + 250);
      expect(game.date, date);
      expect(patient.portraitId, portrait);
      expect(
        jsonEncode([
          patient.equippedWeapon?.toJson(),
          patient.spareAmmo?.toJson(),
          patient.equippedClothing?.toJson(),
        ]),
        equipment,
      );
      _roundTrip();
      final reloaded = game.pool.singleWhere(
        (person) => person.id == patient.id,
      );
      expect(reloaded.medicalBills, 0);
      expect(reloaded.location, reloaded.base);
      expect(reloaded.portraitId, portrait);
    },
  );

  for (final cash in [7, 1000]) {
    test(
      'leaving hospital retains debt at cash $cash, with source affordability',
      () async {
        final patient = _hospitalPatient();
        game.ledger.forceSetFunds(cash);
        final ledger = jsonEncode(game.ledger.toJson());
        var decisions = 0;
        await _drive(() => dischargeHospitalPatient(patient), (frame, _) {
          expect(frame!.actions.first.enabled, cash >= 250);
          expect(frame.actions.last.intentLabel, contains('250 still owed'));
          if (decisions++ == 0 && cash < 250) return 'a';
          return 'b';
        });
        expect(decisions, cash < 250 ? 2 : 1);
        expect(patient.medicalBills, 250);
        expect(patient.location, patient.base);
        expect(patient.squad, isNull);
        expect(jsonEncode(game.ledger.toJson()), ledger);
        _roundTrip();
        expect(
          game.pool
              .singleWhere((person) => person.id == patient.id)
              .medicalBills,
          250,
        );
      },
    );
  }

  test(
    'hospital menu retries remain exact, then admit only the injured member',
    () async {
      final patient = game.squad.last;
      patient.blood = patient.maxBlood - 20;
      final hospitalSite = game.sites.firstWhere(
        (site) =>
            site.type == SiteType.universityHospital &&
            site.city == patient.base!.city,
      );
      final memberIds = game.squad.map((person) => person.id).toList();
      final equipment = jsonEncode(patient.equippedWeapon?.toJson());
      final before = _snapshot();
      var menus = 0;
      await _drive(() => hospital(hospitalSite), (frame, _) {
        if (frame == null) {
          expect(engine.console.eventTitle, 'Hospital admission');
          return 'Enter';
        }
        expect(frame.scene, RecoveryScene.hospital);
        expect(frame.people.map((summary) => summary.person.id), [
          patient.id,
          ...memberIds.where((id) => id != patient.id),
        ]);
        expect(frame.people.first.choiceKey, '5');
        expect(frame.note, contains('1 squad member needs care'));
        expect(frame.note, contains('until reassigned'));
        expect(frame.actions.map((action) => action.key).toSet(), {
          'f',
          'Enter',
          '0',
          '1',
          '2',
          '3',
          '4',
          '5',
        });
        expect(
          frame.actions.singleWhere((action) => action.key == '0').enabled,
          isFalse,
        );
        if (menus++ == 0) {
          // Describing or retrying the menu does not reroll or mutate crew data.
          expect(game.pool.last.blood, patient.maxBlood - 20);
          return '?';
        }
        return 'f';
      });
      expect(menus, 2);
      expect(_snapshot(), isNot(before));
      expect(patient.location, hospitalSite);
      expect(patient.squad, isNull);
      expect(patient.activity.type, ActivityType.none);
      expect(
        game.squad.map((person) => person.id),
        memberIds..remove(patient.id),
      );
      expect(jsonEncode(patient.equippedWeapon?.toJson()), equipment);
      _roundTrip();
    },
  );

  test(
    'court defense reauthors disabled attorney choices without changing the plea',
    () async {
      final defendant = game.squad.last;
      defendant.wantedForCrimes.updateAll((crime, count) => 0);
      criminalize(defendant, Crime.theft);
      criminalize(defendant, Crime.theft);
      defendant.squad = null;
      defendant.location = game.sites.firstWhere(
        (site) => site.type == SiteType.courthouse,
      );
      final ledger = jsonEncode(game.ledger.toJson());
      var defenses = 0;
      RecoveryContext? old;
      await _drive(() => trial(defendant), (frame, _) {
        if (frame == null) return 'Enter';
        expect(frame.scene, RecoveryScene.defense);
        expect(frame.actions.map((action) => action.key), ['a', 'b', 'c', 'd']);
        expect(frame.actions.last.enabled, isFalse);
        expect(frame.details.single, contains('2 counts of theft'));
        expect(
          frame.bodyRows.every((row) => row < engine.console.height),
          isTrue,
        );
        if (defenses++ == 0) {
          old = frame;
          return 'd';
        }
        expect(frame, isNot(same(old)));
        return 'c';
      });
      expect(defenses, 2);
      expect(defendant.isCriminal, isFalse);
      expect(defendant.squad, isNull);
      expect(jsonEncode(game.ledger.toJson()), ledger);
      _roundTrip();
    },
  );

  for (final cash in [4999, 5000]) {
    test(
      'court uses the original elite attorney threshold at cash $cash',
      () async {
        final defendant = game.squad.last;
        defendant.wantedForCrimes.updateAll((crime, count) => 0);
        criminalize(defendant, Crime.theft);
        defendant.squad = null;
        game.ledger.forceSetFunds(cash);
        final legalFees = game.ledger.expense[Expense.legalFees] ?? 0;
        var defenses = 0;
        await _drive(() => trial(defendant), (frame, _) {
          if (frame == null) return 'Enter';
          expect(frame.scene, RecoveryScene.defense);
          final attorney = frame.actions.singleWhere(
            (action) => action.key == 'd',
          );
          expect(attorney.enabled, cash == 5000);
          defenses++;
          return cash == 5000 ? 'd' : 'c';
        });
        expect(defenses, 1);
        expect(game.ledger.funds, cash == 5000 ? 0 : cash);
        expect(
          game.ledger.expense[Expense.legalFees] ?? 0,
          legalFees + (cash == 5000 ? 5000 : 0),
        );
        _roundTrip();
      },
    );
  }

  for (final seed in [0, 1]) {
    test(
      'actual guilty plea records full counts once and accumulates prior convictions at seed $seed',
      () async {
        var defendant = game.squad.last;
        defendant.squad = null;
        defendant.wantedForCrimes.updateAll((crime, count) => 0);
        defendant.pastConvictions.updateAll((crime, count) => 0);
        defendant.pastConvictions[Crime.theft] = 3;
        defendant.pastConvictions[Crime.vandalism] = 4;
        for (var count = 0; count < 12; count++) {
          criminalize(defendant, Crime.theft);
        }
        criminalize(defendant, Crime.resistingArrest);
        criminalize(defendant, Crime.resistingArrest);
        final oldRecord = Map.of(defendant.pastConvictions);
        var defenses = 0;
        var guiltyReports = 0;
        reseedRNG(seed: seed);
        await _drive(() => trial(defendant), (frame, _) {
          if (frame != null) {
            expect(defendant.pastConvictions, oldRecord);
            return defenses++ == 0 ? '?' : 'c';
          }
          if (engine.console.eventMessage?.contains('GUILTY!') == true) {
            guiltyReports++;
            expect(defendant.wantedForCrimes[Crime.theft], 12);
            expect(defendant.pastConvictions[Crime.theft], 15);
            expect(defendant.pastConvictions[Crime.resistingArrest], 2);
          }
          return 'Enter';
        });
        expect(defenses, 2);
        expect(guiltyReports, 1);
        expect(defendant.pastConvictions, {
          ...oldRecord,
          Crime.theft: 15,
          Crime.resistingArrest: 2,
        });
        expect(
          defendant.wantedForCrimes.values.every((count) => count == 0),
          isTrue,
        );
        expect(defendant.heat, 0);
        expect(defendant.confessions, 0);
        expect(defendant.site?.type, SiteType.prison);
        final id = defendant.id;
        _roundTrip();
        defendant = game.pool.singleWhere((person) => person.id == id);
        expect(defendant.pastConvictions[Crime.theft], 15);

        // A later actual case adds only its own charged counts to that record.
        criminalize(defendant, Crime.theft);
        criminalize(defendant, Crime.theft);
        await _drive(
          () => trial(defendant),
          (frame, _) => frame == null ? 'Enter' : 'c',
        );
        expect(defendant.pastConvictions[Crime.theft], 17);
        expect(defendant.pastConvictions[Crime.vandalism], 4);
        expect(defendant.pastConvictions[Crime.resistingArrest], 2);
        expect(
          defendant.wantedForCrimes.values.every((count) => count == 0),
          isTrue,
        );
        _roundTrip();
      },
    );
  }

  for (final scenario in [
    (4, 'NOT GUILTY!'),
    (104, 'case will be re-tried next month'),
  ]) {
    test(
      'actual trial outcome ${scenario.$2} does not add convictions',
      () async {
        final defendant = game.squad.last;
        defendant.squad = null;
        defendant.wantedForCrimes.updateAll((crime, count) => 0);
        defendant.pastConvictions[Crime.theft] = 3;
        criminalize(defendant, Crime.theft);
        final oldRecord = Map.of(defendant.pastConvictions);
        var outcomeSeen = false;
        reseedRNG(seed: scenario.$1);
        await _drive(() => trial(defendant), (frame, _) {
          expect(defendant.pastConvictions, oldRecord);
          if (engine.console.eventMessage?.contains(scenario.$2) == true) {
            outcomeSeen = true;
          }
          return frame == null ? 'Enter' : 'a';
        });
        expect(outcomeSeen, isTrue);
        expect(defendant.pastConvictions, oldRecord);
        _roundTrip();
      },
    );
  }

  Future<_RecoveryHarness> mount(
    WidgetTester tester,
    Future<void> Function() operation, {
    Size size = const Size(1200, 600),
    double scale = 1,
    ValueChanged<String>? onAction,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    final harness = _RecoveryHarness(operation);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await harness.stop(tester);
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
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
            child: JournalRecoveryView(
              console: engine.console,
              onAction: onAction ?? (key) => engine.console.sendInput(key),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return harness;
  }

  testWidgets(
    'discharge inspection and stale callbacks cannot settle a later reader',
    (tester) async {
      final patient = _hospitalPatient();
      game.ledger.forceSetFunds(1000);
      final commands = <String>[];
      await mount(
        tester,
        () => dischargeHospitalPatient(patient),
        onAction: commands.add,
      );
      final before = _snapshot();
      reseedRNG(seed: 9086);
      final roll = lcsRandom(100000);
      reseedRNG(seed: 9086);
      final old = tester.widget<OutlinedButton>(_action('a')).onPressed!;
      await tester.tap(find.byTooltip('Inspect ${patient.name}'));
      await tester.pumpAndSettle();
      expect(_snapshot(), before);
      expect(lcsRandom(100000), roll);
      expect(commands, isEmpty);
      await tester.tap(find.byTooltip('Close dossier'));
      await tester.pumpAndSettle();
      engine.console.flush();
      old();
      expect(commands, isEmpty);
      await tester.pumpAndSettle();
      final current = tester.widget<OutlinedButton>(_action('a')).onPressed!;
      engine.console.actions[0] = const ConsoleAction(
        key: 'a',
        label: 'Another reader',
        enabled: true,
        y: 0,
        x: 0,
        width: 14,
      );
      current();
      expect(commands, isEmpty);
      engine.console.screen = 'headquarters';
      current();
      expect(commands, isEmpty);
      expect(_snapshot(), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'injured hospital member leads the first 800x600 viewport at 150 percent',
    (tester) async {
      final patient = game.squad.last;
      patient.blood = patient.maxBlood - 20;
      final site = game.sites.firstWhere(
        (site) =>
            site.type == SiteType.universityHospital &&
            site.city == patient.base!.city,
      );
      await mount(
        tester,
        () => hospital(site),
        size: const Size(800, 600),
        scale: 1.5,
      );
      final firstPortrait = tester
          .widgetList<CrewPortrait>(find.byType(CrewPortrait))
          .first;
      expect(firstPortrait.person, same(patient));
      expect(
        find.byTooltip('Inspect ${patient.name}').hitTestable(),
        findsOneWidget,
      );
      expect(
        find.text('Admit injured squad members').hitTestable(),
        findsOneWidget,
      );
      expect(recoveryContext(engine.console)!.people.first.choiceKey, '5');
      expect(tester.takeException(), isNull);
    },
  );

  for (final cash in [7, 1000]) {
    testWidgets(
      'discharge choices fit 800x600 at 150 percent with cash $cash',
      (tester) async {
        final patient = _hospitalPatient();
        game.ledger.forceSetFunds(cash);
        final harness = await mount(
          tester,
          () => dischargeHospitalPatient(patient),
          size: const Size(800, 600),
          scale: 1.5,
        );
        expect(find.text('Hospital discharge'), findsOneWidget);
        expect(find.textContaining('250 still owed'), findsOneWidget);
        expect(_action('a').hitTestable(), findsOneWidget);
        expect(_action('b').hitTestable(), findsOneWidget);
        expect(
          tester.widget<OutlinedButton>(_action('a')).onPressed != null,
          cash >= 250,
        );
        expect(tester.getRect(_action('b')).bottom, lessThanOrEqualTo(600));
        await tester.tap(_action('b'));
        await tester.pumpAndSettle();
        expect(harness.returned, isTrue);
        expect(patient.medicalBills, 250);
        expect(patient.location, patient.base);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'court choices and adjacent skill values fit 800x600 at 150 percent',
    (tester) async {
      final defendant = game.squad.last;
      defendant.wantedForCrimes.updateAll((crime, count) => 0);
      criminalize(defendant, Crime.theft);
      defendant.squad = null;
      await mount(
        tester,
        () => trial(defendant),
        size: const Size(800, 600),
        scale: 1.5,
      );
      expect(find.text('Court defense'), findsOneWidget);
      expect(
        find.textContaining(RegExp(r'Law: \d+ Persuasion: \d+')),
        findsOneWidget,
      );
      expect(_action('a').hitTestable(), findsOneWidget);
      expect(_action('c').hitTestable(), findsOneWidget);
      expect(tester.widget<OutlinedButton>(_action('d')).onPressed, isNull);
      final before = _snapshot();
      await tester.tap(find.text('Case details'));
      await tester.pumpAndSettle();
      expect(find.textContaining('charged with theft'), findsOneWidget);
      expect(_snapshot(), before);
      expect(tester.takeException(), isNull);
    },
  );

  for (final fromHeadquarters in [true, false]) {
    testWidgets(
      'shell recovery route from headquarters $fromHeadquarters at 800x600 / 150 percent',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(800, 600);
        journalReadingScale.value = 1.5;
        final patient = _hospitalPatient();
        game.ledger.forceSetFunds(1000);
        _RecoveryHarness? harness;
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox.shrink());
          await harness?.stop(tester);
          journalReadingScale.value = 1;
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        if (fromHeadquarters) {
          engine.console.screen = 'headquarters';
          engine.addOptionText(23, 0, 'w', 'W - Wait a day');
          final headquartersReader = engine.console.getkey();
          await tester.pumpWidget(const MainApp());
          await tester.pumpAndSettle();
          engine.console.sendInput('w');
          await headquartersReader;
        }
        harness = _RecoveryHarness(() => dischargeHospitalPatient(patient));
        await tester.pumpWidget(const MainApp());
        await tester.pumpAndSettle();
        expect(find.byType(JournalRecoveryView), findsOneWidget);
        expect(find.text('Hospital discharge'), findsOneWidget);
        expect(
          find.byType(OrganisationJournal),
          fromHeadquarters ? findsOneWidget : findsNothing,
        );
        expect(_action('b').hitTestable(), findsOneWidget);
        final before = _snapshot();
        final inspect = find.byTooltip('Inspect ${patient.name}');
        await tester.ensureVisible(inspect);
        await tester.tap(inspect);
        await tester.pumpAndSettle();
        expect(find.byTooltip('Close dossier'), findsOneWidget);
        expect(_snapshot(), before);
        await tester.tap(find.byTooltip('Close dossier'));
        await tester.pumpAndSettle();
        await tester.tap(_action('a'));
        await tester.pumpAndSettle();
        expect(harness.returned, isTrue);
        expect(patient.medicalBills, 0);
        expect(game.ledger.funds, 750);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
