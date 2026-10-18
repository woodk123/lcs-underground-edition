import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activate_regulars.dart';
import 'package:lcs_new_age/basemode/activate_sleepers.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/modern/direct_content.dart';
import 'package:lcs_new_age/modern/mechanics_help.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

Future<void> mountMechanicsFlow(WidgetTester tester, Future<void> flow) async {
  var done = false;
  unawaited(flow.then((_) => done = true));
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 900);
  addTearDown(() async {
    for (var i = 0; i < 4 && !done; i++) {
      if (engine.console.awaitingInput) engine.console.sendInput('Escape');
      await tester.pump();
    }
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ValueListenableBuilder<int>(
            valueListenable: engine.console.revision,
            builder: (context, value, child) => DirectContent(
              console: engine.console,
              onAction: engine.console.sendInput,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(ensureGameDataLoaded);
  setUp(() async {
    engine.console = Console();
    game.gameState = decodeSaveContents(
      await File('test/saves/felix_1_0.json').readAsString(),
    ).gameState!;
  });

  test(
    'mechanics use explicit activity identities, never labels or shortcuts',
    () {
      const action = ConsoleAction(
        key: '3',
        label: '3 - Misleading text',
        enabled: true,
        y: 1,
        x: 0,
        width: 22,
        entityType: 'activity',
        entityId: 'sellMusic',
      );
      expect(activityTypeForAction(action), ActivityType.sellMusic);
      const unannotated = ConsoleAction(
        key: '3',
        label: '3 - Perform Live Music',
        enabled: true,
        y: 1,
        x: 0,
        width: 22,
      );
      expect(activityTypeForAction(unannotated), isNull);
      const unknown = ConsoleAction(
        key: '3',
        label: 'Sell Art',
        enabled: true,
        y: 1,
        x: 0,
        width: 8,
        entityType: 'activity',
        entityId: 'not-an-activity',
      );
      expect(activityTypeForAction(unknown), isNull);
    },
  );

  test('implemented music formula and actual course limits are explained', () {
    final music = activityMechanics(ActivityType.sellMusic);
    expect(music.factors, 'Music · Street Smarts');
    expect(music.details, contains('one quarter'));
    expect(music.details, contains('(not Business)'));
    final classes = activityMechanics(ActivityType.takeClass);
    expect(classes.cost, '\$30 per training day');
    expect(classes.requirements, contains('below level 10'));
    expect(classes.details, contains('50 minus 5 times current skill'));
    expect(
      activityMechanics(ActivityType.teachLiberalArts).cost,
      contains('up to \$20'),
    );
    expect(
      activityMechanics(ActivityType.teachCovert).cost,
      contains('up to \$60'),
    );
    expect(
      activityMechanics(ActivityType.teachFighting).cost,
      contains('up to \$100'),
    );
  });

  test(
    'current skill values and precise blocking requirements are read-only',
    () {
      final actor = game.pool.first;
      actor.rawSkill[Skill.computers] = 0;
      expect(
        activityMechanics(ActivityType.hacking, actor: actor).unavailableReason,
        'Requires at least 1 Computers skill.',
      );
      actor.rawSkill[Skill.computers] = 3;
      expect(
        activityMechanics(ActivityType.hacking, actor: actor).unavailableReason,
        'Requires a Hacker Den at this location.',
      );
      expect(
        activityMechanics(ActivityType.hacking, actor: actor).factors,
        'Computers 3',
      );
      actor.site!.compound.hackerDen = true;
      expect(
        activityMechanics(ActivityType.hacking, actor: actor).unavailableReason,
        isNull,
      );
    },
  );

  test('all help previews preserve campaign state and the random stream', () {
    final before = jsonEncode(game.gameState.toJson());
    final actor = game.pool.first;
    reseedRNG(seed: 91562);
    final expected = List.generate(12, (_) => lcsRandom(100000));
    reseedRNG(seed: 91562);
    for (final type in ActivityType.values) {
      final help = activityMechanics(
        type,
        actor: actor,
        activity: actor.activity,
      );
      expect(help.summary, isNotEmpty);
      expect(help.type, type);
      expect(
        activityMechanics(type, actor: actor, sleeper: true).summary,
        isNotEmpty,
      );
    }
    for (final policy in BulkActivity.values) {
      expect(bulkActivityMechanics(policy.mechanicsId), isNotNull);
    }
    for (final feature in FeatureMechanic.values) {
      expect(featureMechanics(feature), isNotEmpty);
    }
    expect(List.generate(12, (_) => lcsRandom(100000)), expected);
    expect(jsonEncode(game.gameState.toJson()), before);
    expect(engine.console.awaitingInput, isFalse);
  });

  test(
    'sleeper Lay Low explains monthly infiltration and possible daily care',
    () {
      final actor = game.pool.first;
      actor.sleeperAgent = false;
      expect(
        activityMechanics(ActivityType.none, actor: actor).summary,
        contains('wash or mend'),
      );
      actor.sleeperAgent = true;
      final help = activityMechanics(ActivityType.none, actor: actor);
      expect(help.summary, contains('rebuild infiltration'));
      expect(help.details, contains('1–5 percentage points'));
      expect(help.details, contains('clothing care may also run'));
      expect(help.timing, contains('month end'));
      expect(
        activityMechanics(ActivityType.none, sleeper: true).summary,
        help.summary,
      );
    },
  );

  test('prisoner and sleeper explanations follow actual handlers', () {
    final prisoner = activityMechanics(ActivityType.interrogation);
    expect(prisoner.factors, 'Psychology · Business · Religion · Science');
    expect(
      prisoner.details,
      contains('twice Psychology plus clothing base power selects the lead'),
    );
    expect(prisoner.details, contains('Psychology + 2d6 + round(5 × rapport)'));
    expect(
      activityMechanics(ActivityType.sleeperSpy).details,
      contains('costs 20 infiltration percentage points'),
    );
    expect(
      activityMechanics(ActivityType.sleeperRecruit).details,
      contains('workplace encounters and remaining subordinate capacity'),
    );
    expect(
      activityMechanics(ActivityType.sleeperRecruit).details,
      isNot(contains('infiltration')),
    );
    expect(
      activityMechanics(ActivityType.sleeperJoinLcs).details,
      contains('Without one, the assignment waits'),
    );
    final legal = bulkActivityMechanics('legalFundraising')!;
    expect(legal.title, 'Legal Fundraising · best fit per person');
    expect(legal.summary, contains('best internal estimate for each person'));
    expect(bulkActivityMechanics('not-a-policy'), isNull);
  });

  testWidgets(
    'real sleeper menu exposes current monthly help and exact commands',
    (tester) async {
      final actor = game.pool.first;
      actor.sleeperAgent = true;
      actor.activity = Activity.none();
      final date = game.date;
      final flow = activateSleeper(actor);
      await mountMechanicsFlow(tester, flow);
      expect(engine.console.navigation?.section, 'assignments');
      expect(find.textContaining('rebuild infiltration'), findsOneWidget);
      expect(
        find.textContaining('Infiltration improves at month end'),
        findsOneWidget,
      );
      expect(find.text('Done'), findsOneWidget);
      engine.console.sendInput('b');
      await tester.pumpAndSettle();
      final spy = engine.console.actions.singleWhere(
        (action) =>
            action.entityType == 'sleeper-activity' &&
            action.entityId == 'sleeperSpy',
      );
      expect(spy.key, '1');
      expect(spy.label, '1 - Uncover Secrets');
      expect(spy.entityCategory, actor.id.toString());
      engine.console.sendInput(spy.key);
      await tester.pumpAndSettle();
      expect(actor.activity.type, ActivityType.sleeperSpy);
      expect(
        find.byKey(const ValueKey('activity-mechanics:sleeperSpy')),
        findsOneWidget,
      );
      final state = jsonEncode(game.gameState.toJson());
      final revision = engine.console.revision.value;
      await tester.ensureVisible(find.text('How it works'));
      await tester.tap(find.text('How it works'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('costs 20 infiltration percentage points'),
        findsOneWidget,
      );
      expect(engine.console.revision.value, revision);
      expect(jsonEncode(game.gameState.toJson()), state);
      expect(game.date, date);
      engine.console.sendInput('Escape');
      await tester.pumpAndSettle();
      await flow;
      expect(actor.activity.type, ActivityType.sleeperSpy);
      expect(game.date, date);
    },
  );

  testWidgets(
    'real sleeper bulk task selection explains monthly context before applying',
    (tester) async {
      final actor = game.pool.first;
      actor.sleeperAgent = true;
      actor.activity = Activity.none();
      final date = game.date;
      final flow = activateSleepersBulk();
      await mountMechanicsFlow(tester, flow);
      expect(find.text('Bulk task: Laying Low'), findsOneWidget);
      expect(find.textContaining('rebuild infiltration'), findsWidgets);
      expect(
        find.textContaining('Selecting a bulk task changes no person'),
        findsOneWidget,
      );
      final embezzle = engine.console.actions.singleWhere(
        (action) =>
            action.entityType == 'sleeper-bulk-activity' &&
            action.entityId == 'sleeperEmbezzle',
      );
      engine.console.sendInput(embezzle.key);
      await tester.pumpAndSettle();
      expect(actor.activity.type, ActivityType.none);
      expect(
        find.byKey(const ValueKey('activity-mechanics:sleeperEmbezzle')),
        findsOneWidget,
      );
      final person = engine.console.actions.singleWhere(
        (action) =>
            action.entityType == 'person' &&
            action.entityId == actor.id.toString(),
      );
      engine.console.sendInput(person.key);
      await tester.pumpAndSettle();
      expect(actor.activity.type, ActivityType.sleeperEmbezzle);
      expect(game.date, date);
      engine.console.sendInput('Escape');
      await tester.pumpAndSettle();
      await flow;
      expect(actor.activity.type, ActivityType.sleeperEmbezzle);
    },
  );

  testWidgets(
    'real regular bulk policy explains per-person choice without predicting income',
    (tester) async {
      final actor = game.pool.first;
      actor.activity = Activity.none();
      final date = game.date;
      final flow = activateRegulars();
      await mountMechanicsFlow(tester, flow);
      engine.console.sendInput('z');
      await tester.pumpAndSettle();
      final policy = engine.console.actions.singleWhere(
        (action) =>
            action.entityType == 'bulk-activity' &&
            action.entityId == 'legalFundraising',
      );
      expect(policy.key, '4');
      expect(policy.label, '4 - Legal Fundraising');
      engine.console.sendInput(policy.key);
      await tester.pumpAndSettle();
      expect(
        find.text('Bulk task: Legal Fundraising · best fit per person'),
        findsOneWidget,
      );
      expect(actor.activity.type, ActivityType.none);
      expect(game.date, date);
      final state = jsonEncode(game.gameState.toJson());
      final revision = engine.console.revision.value;
      await tester.ensureVisible(find.text('How it works'));
      await tester.tap(find.text('How it works'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('daily rolls still determine the result'),
        findsOneWidget,
      );
      expect(engine.console.revision.value, revision);
      expect(jsonEncode(game.gameState.toJson()), state);
      engine.console.sendInput('Escape');
      await tester.pumpAndSettle();
      engine.console.sendInput('Escape');
      await tester.pumpAndSettle();
      await flow;
      expect(actor.activity.type, ActivityType.none);
    },
  );

  test('sleeper effects and safehouse numbers explain their actual timing', () {
    expect(
      activityMechanics(ActivityType.sleeperSpy).timing,
      'Sleeper effects are processed at month end.',
    );
    expect(
      activityMechanics(ActivityType.sellArt).timing,
      'Runs each day until changed, completed or interrupted.',
    );
    final visit = activityMechanics(ActivityType.visit);
    expect(visit.timing, contains('Reassign afterward'));
    expect(visit.details, contains('do not resume automatically'));
    final recruiting = activityMechanics(ActivityType.recruiting);
    expect(
      recruiting.timing,
      contains('Choose a profession when the day runs'),
    );
    expect(recruiting.details, contains('pending meetings in People'));
    expect(
      featureMechanics(FeatureMechanic.heat),
      contains('not a percentage'),
    );
    expect(
      featureMechanics(FeatureMechanic.heat),
      contains('does not guarantee an immediate raid'),
    );
    expect(
      featureMechanics(FeatureMechanic.squadOrder),
      contains('Inspecting changes no orders or time'),
    );
  });

  testWidgets('real task changes update inline help, Done only exits', (
    tester,
  ) async {
    final actor = game.pool.first;
    actor.activity = Activity(ActivityType.none);
    final beforeDate = game.date;
    final flow = assignTask(actor);
    var done = false;
    unawaited(flow.then((_) => done = true));
    addTearDown(() async {
      if (!done && engine.console.awaitingInput) {
        engine.console.sendInput('Enter');
        await tester.pump();
      }
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 900);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ValueListenableBuilder<int>(
              valueListenable: engine.console.revision,
              builder: (context, value, child) => DirectContent(
                console: engine.console,
                onAction: engine.console.sendInput,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('activity-mechanics:none')),
      findsOneWidget,
    );
    expect(find.text('Done'), findsOneWidget);
    final category = engine.console.actions.singleWhere(
      (action) =>
          action.entityType == 'activity-category' &&
          action.entityId == 'legal',
    );
    engine.console.sendInput(category.key);
    await tester.pumpAndSettle();
    final art = engine.console.actions.singleWhere(
      (action) =>
          action.entityType == 'activity' && action.entityId == 'sellArt',
    );
    expect(art.label, '3 - Make and Sell Art');
    expect(art.entityCategory, actor.id.toString());
    engine.console.sendInput(art.key);
    await tester.pumpAndSettle();
    expect(actor.activity.type, ActivityType.sellArt);
    expect(
      find.byKey(const ValueKey('activity-mechanics:sellArt')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('activity-mechanics:none')), findsNothing);
    expect(
      find.textContaining('Choosing a task updates the assignment now'),
      findsOneWidget,
    );
    final revision = engine.console.revision.value;
    final state = jsonEncode(game.gameState.toJson());
    await tester.ensureVisible(find.text('How it works'));
    await tester.tap(find.text('How it works'));
    await tester.pumpAndSettle();
    expect(engine.console.revision.value, revision);
    expect(jsonEncode(game.gameState.toJson()), state);
    expect(engine.console.awaitingInput, isTrue);
    expect(game.date, beforeDate);
    final doneButton = find.text('Done');
    await tester.ensureVisible(doneButton);
    await tester.tap(doneButton);
    await tester.pumpAndSettle();
    expect(done, isTrue);
    expect(actor.activity.type, ActivityType.sellArt);
    expect(game.date, beforeDate);
    expect(tester.takeException(), isNull);
  });
}
