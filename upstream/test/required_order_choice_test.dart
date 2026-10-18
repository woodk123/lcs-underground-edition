import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activate_regulars.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/basemode/base_mode.dart';
import 'package:lcs_new_age/basemode/liberal_agenda.dart';
import 'package:lcs_new_age/basemode/review_mode.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/daily/activities/solo_activities.dart';
import 'package:lcs_new_age/daily/recruitment.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/engine/organisation_context.dart';
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/organisation_journal.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_support.dart';

Finder _key(String value) => find.byKey(ValueKey(value));

/// Retains the real order and education readers without advancing the campaign.
class _RequiredChoiceHarness {
  _RequiredChoiceHarness({this.onDay}) {
    done = _loop();
  }
  final Future<void> Function()? onDay;
  late final Future<void> done;
  bool stopped = false, finished = false;

  Future<void> _loop() async {
    try {
      while (!stopped) {
        engine.erase();
        final home = game.activeSquad?.site ?? game.activeSafehouse;
        baseModeSquadSafehouseDisplay(home);
        baseModeOptionsDisplay(home);
        final key = await engine.getKey();
        if (stopped) break;
        switch (key) {
          case engine.Key.a:
            await activateRegulars();
          case engine.Key.r:
            await reviewAssetsAndFormSquads();
          case engine.Key.l:
            await liberalAgenda();
          case engine.Key.w:
            await onDay?.call();
        }
      }
    } finally {
      finished = true;
    }
  }

  Future<void> stop(WidgetTester tester) async {
    stopped = true;
    for (var i = 0; i < 40 && !finished; i++) {
      if (engine.console.awaitingInput) {
        engine.console.sendInput('Escape');
      }
      await tester.pump(const Duration(milliseconds: 5));
    }
    expect(finished, isTrue);
  }
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String fixture;
  late Creature actor, squadMember;
  late String memberBefore;

  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    engine.console = Console();
    journalReadingScale.value = 1;
    game.gameState = decodeSaveContents(fixture).gameState!;
    game.mode = GameMode.base;
    squadMember = game.activeSquad!.members.first;
    for (final squad in game.squads) {
      squad.activity = Activity.none();
    }
    for (final person in game.pool.where((p) => p.isActiveLiberal)) {
      person
        ..location = squadMember.base
        ..activity = Activity.none();
    }
    squadMember.name = 'Kim Squad Member';
    actor =
        Creature.fromJson(
            jsonDecode(jsonEncode(squadMember)) as Map<String, dynamic>,
          )
          ..id = game.gameState.nextCreatureId++
          ..name = 'Dagwood Outside Squad'
          ..squadId = null
          ..activity = Activity(ActivityType.donations);
    game.pool.add(actor);
    memberBefore = jsonEncode(squadMember);
  });

  Future<void> mount(
    WidgetTester tester, {
    Future<void> Function()? onDay,
  }) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    final harness = _RequiredChoiceHarness(onDay: onDay);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await harness.stop(tester);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const MainApp());
    await _settle(tester);
  }

  Future<void> chooseEducation(WidgetTester tester, ActivityType type) async {
    await _tap(tester, _key('journal-section:9'));
    await _tap(tester, _key('personnel-filter:availableOutsideSquads'));
    await _tap(tester, _key('personnel-assign-order:${actor.id}'));
    await _tap(tester, _key('journal-order-group:1'));
    await _tap(
      tester,
      find.widgetWithText(OutlinedButton, 'Education and Learning'),
    );
    await _tap(tester, _key('journal-activity:${type.name}'));
    expect(actor.activity.type, ActivityType.donations);
    await _tap(tester, _key('journal-confirm-order'));
    expect(activityOrderFrame(engine.console), isNull);
    expect(
      engine.console.actions
          .where((action) => action.entityType == 'education-skill')
          .map((action) => action.entityCategory)
          .toSet(),
      {actor.id.toString()},
    );
    expect(find.text('Individual orders'), findsOneWidget);
    expect(
      tester.widget<Text>(_key('journal-required-order-actor')).data,
      actor.name,
    );
    expect(find.text('Awaiting skill choice'), findsOneWidget);
    expect(find.text('Assigned order'), findsNothing);
    expect(actor.activity.type, ActivityType.donations);
    expect(jsonEncode(squadMember), memberBefore);
  }

  for (final type in [ActivityType.study, ActivityType.takeClass]) {
    testWidgets('$type required skill picker keeps exact outside-squad actor', (
      tester,
    ) async {
      await mount(tester);
      final date = game.date;
      await chooseEducation(tester, type);
      final skill = type == ActivityType.study
          ? Skill.persuasion
          : Skill.writing;
      ConsoleAction? selected() => engine.console.actions
          .where(
            (action) =>
                action.entityType == 'education-skill' &&
                action.entityId == skill.name,
          )
          .firstOrNull;
      for (var i = 0; i < 4 && selected() == null; i++) {
        engine.console.sendInput(']');
        await _settle(tester);
      }
      final choice = selected()!;
      await _tap(
        tester,
        _key('direct-action:${choice.y}:${choice.x}:${choice.key}'),
      );
      expect(actor.activity.type, type);
      expect(actor.activity.skill, skill);
      expect(jsonEncode(squadMember), memberBefore);
      expect(game.date, date);
      expect(_key('journal-required-order-actor'), findsNothing);
      expect(activityOrderFrame(engine.console)?.actorId, actor.id);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'real profession picker uses its recruiter instead of a different selected writer',
    (tester) async {
      actor
        ..squad = game.activeSquad
        ..activity = Activity(ActivityType.writeGuardian);
      squadMember
        ..squad = null
        ..activity = Activity(ActivityType.recruiting);
      await mount(tester, onDay: () => soloActivities(false));
      final journal = tester.state<OrganisationJournalState>(
        find.byType(OrganisationJournal),
      );
      journal.widget.controller.inspectPerson(actor.id);
      await _settle(tester);
      expect(
        tester.widget<Text>(_key('journal-selected-person')).data,
        actor.name,
      );

      engine.console.sendInput('w');
      await _settle(tester);
      expect(engine.console.recruitmentTarget?.recruiter, same(squadMember));
      expect(activityOrderFrame(engine.console), isNull);
      expect(
        tester.widget<Text>(_key('journal-selected-person')).data,
        squadMember.name,
      );
      expect(
        tester.widget<Text>(_key('journal-team-name')).data,
        'Individual orders',
      );
      expect(
        find.descendant(
          of: _key('journal-crew-list'),
          matching: find.text(actor.name),
        ),
        findsNothing,
      );
      final before = jsonEncode(game.gameState);
      final actions = List.of(engine.console.actions);
      reseedRNG(seed: 88421);
      final expectedRng = nextRngSeed;
      reseedRNG(seed: 88421);
      journal.widget.controller.inspectPerson(actor.id);
      await _settle(tester);
      expect(
        tester.widget<Text>(_key('journal-selected-person')).data,
        squadMember.name,
      );
      expect(engine.console.lastKey, isNull);
      expect(engine.console.awaitingInput, isTrue);
      expect(engine.console.actions, orderedEquals(actions));
      expect(jsonEncode(game.gameState), before);
      expect(nextRngSeed, expectedRng);

      engine.console.sendInput('Escape');
      await _settle(tester);
      expect(engine.console.recruitmentTarget, isNull);
      expect(engine.console.screen, 'headquarters');
      expect(
        tester.widget<Text>(_key('journal-selected-person')).data,
        actor.name,
      );
      expect(find.text('Individual orders'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'real recruitment follow-up keeps its recruiter and clears identity after exit',
    (tester) async {
      actor
        ..squad = game.activeSquad
        ..activity = Activity(ActivityType.writeGuardian);
      squadMember
        ..squad = null
        ..meetings = 0
        ..activity = Activity(ActivityType.recruiting);
      final prospect =
          Creature.fromJson(
              jsonDecode(jsonEncode(squadMember)) as Map<String, dynamic>,
            )
            ..id = 997766
            ..name = 'Jordan Follow-up';
      final session = RecruitmentSession(prospect, squadMember)
        ..rawEagerness = 0;
      await mount(
        tester,
        onDay: () async {
          await completeRecruitMeeting(session, squadMember);
        },
      );
      final journal = tester.state<OrganisationJournalState>(
        find.byType(OrganisationJournal),
      );
      journal.widget.controller.inspectPerson(actor.id);
      await _settle(tester);
      expect(
        tester.widget<Text>(_key('journal-selected-person')).data,
        actor.name,
      );

      engine.console.sendInput('w');
      await _settle(tester);
      expect(engine.console.recruitment?.recruiter, same(squadMember));
      expect(engine.console.recruitment?.followUp, isTrue);
      expect(activityOrderFrame(engine.console), isNull);
      expect(
        tester.widget<Text>(_key('journal-selected-person')).data,
        squadMember.name,
      );
      expect(
        tester.widget<Text>(_key('journal-team-name')).data,
        'Individual orders',
      );
      final before = jsonEncode(game.gameState);
      final actions = List.of(engine.console.actions);
      reseedRNG(seed: 75193);
      final expectedRng = nextRngSeed;
      reseedRNG(seed: 75193);
      journal.widget.controller.inspectPerson(actor.id);
      await _settle(tester);
      expect(
        tester.widget<Text>(_key('journal-selected-person')).data,
        squadMember.name,
      );
      expect(engine.console.lastKey, isNull);
      expect(engine.console.awaitingInput, isTrue);
      expect(engine.console.actions, orderedEquals(actions));
      expect(jsonEncode(game.gameState), before);
      expect(nextRngSeed, expectedRng);

      engine.console.sendInput('d');
      await _settle(tester);
      expect(engine.console.recruitment, isNull);
      expect(engine.console.screen, 'headquarters');
      expect(
        tester.widget<Text>(_key('journal-selected-person')).data,
        actor.name,
      );
      expect(find.text('Individual orders'), findsNothing);
      await _tap(tester, _key('journal-section:3'));
      expect(find.text('Individual orders'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'canceling required skill leaves orders intact and clears report identity',
    (tester) async {
      await mount(tester);
      final before = jsonEncode(game.gameState);
      await chooseEducation(tester, ActivityType.study);
      await _tap(tester, _key('journal-cancel-skill-choice'));
      expect(actor.activity.type, ActivityType.donations);
      expect(jsonEncode(game.gameState), before);
      expect(_key('journal-required-order-actor'), findsNothing);
      expect(
        engine.console.actions.any(
          (action) => action.entityType == 'education-skill',
        ),
        isFalse,
      );
      await _tap(tester, _key('journal-section:3'));
      expect(find.byType(OrganisationJournal), findsOneWidget);
      expect(find.text('Individual orders'), findsNothing);
      expect(_key('journal-required-order-actor'), findsNothing);
      expect(
        engine.console.actions.any(
          (action) => action.entityType == 'education-skill',
        ),
        isFalse,
      );
      await _tap(tester, _key('journal-section:0'));
      expect(
        tester.widget<Text>(_key('journal-team-name')).data,
        game.activeSquad!.name,
      );
      expect(jsonEncode(squadMember), memberBefore);
      expect(tester.takeException(), isNull);
    },
  );
}
