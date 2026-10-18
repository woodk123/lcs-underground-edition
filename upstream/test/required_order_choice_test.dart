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
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/engine/organisation_context.dart';
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/organisation_journal.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_support.dart';

Finder _key(String value) => find.byKey(ValueKey(value));

/// Retains the real order and education readers without advancing the campaign.
class _RequiredChoiceHarness {
  _RequiredChoiceHarness() {
    done = _loop();
  }
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

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    final harness = _RequiredChoiceHarness();
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
