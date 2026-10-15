import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activate_regulars.dart';
import 'package:lcs_new_age/basemode/activate_sleepers.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/basemode/base_actions.dart';
import 'package:lcs_new_age/basemode/base_mode.dart';
import 'package:lcs_new_age/basemode/liberal_agenda.dart';
import 'package:lcs_new_age/basemode/media_overview.dart';
import 'package:lcs_new_age/basemode/plan_site_visit.dart';
import 'package:lcs_new_age/basemode/review_mode.dart';
import 'package:lcs_new_age/common_actions/equipment.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/engine/ledger_context.dart';
import 'package:lcs_new_age/engine/media_context.dart';
import 'package:lcs_new_age/engine/organisation_context.dart';
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/gamestate/ledger.dart';
import 'package:lcs_new_age/gamestate/squad.dart';
import 'package:lcs_new_age/location/siege.dart';
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/modern/article_view.dart';
import 'package:lcs_new_age/modern/crew_dossier.dart';
import 'package:lcs_new_age/modern/journal_ledger.dart';
import 'package:lcs_new_age/modern/journal_media.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/mechanics_help.dart';
import 'package:lcs_new_age/modern/organisation_journal.dart';
import 'package:lcs_new_age/monthly/lcs_monthly.dart';
import 'package:lcs_new_age/newspaper/news_story.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

/// The base dispatch boundary with real source-authored options and real
/// management handlers. It never advances time during these UI tests.
class _JournalHarness {
  _JournalHarness({this.monthlyReport = false}) {
    done = _loop();
  }
  late final Future<void> done;
  bool stopped = false;
  bool finished = false;
  final bool monthlyReport;
  bool monthReset = false;
  final dispatched = <int>[];

  Future<void> _loop() async {
    try {
      while (!stopped) {
        engine.erase();
        final location = game.activeSquad?.site ?? game.activeSafehouse;
        baseModeSquadSafehouseDisplay(location);
        baseModeOptionsDisplay(location);
        final key = await engine.getKey();
        if (stopped) break;
        dispatched.add(key);
        switch (key) {
          case engine.Key.r:
            await reviewAssetsAndFormSquads();
          case engine.Key.a:
            await activateRegulars();
          case engine.Key.b:
            await activateSleepers();
          case engine.Key.f:
            await planSiteVisit();
          case engine.Key.c:
            if (game.squad.isNotEmpty) {
              game.activeSquad?.activity = Activity.none();
            }
          case engine.Key.e:
            await equip(game.activeSquad?.site?.loot);
          case engine.Key.v:
            await setVehicles();
          case engine.Key.o:
            await orderparty();
          case engine.Key.m:
            await mediaOverview();
          case engine.Key.l:
            await liberalAgenda();
          case engine.Key.w:
            if (monthlyReport) {
              await fundReport(false);
              game.ledger.resetMonthlyAmounts();
              monthReset = true;
            }
        }
      }
    } finally {
      finished = true;
    }
  }

  Future<void> stop(WidgetTester tester) async {
    stopped = true;
    for (var i = 0; i < 50 && !finished; i++) {
      if (engine.console.awaitingInput) {
        engine.console.sendInput(engine.console.textInput ? 'Enter' : 'Escape');
      }
      await tester.pump(const Duration(milliseconds: 5));
    }
    expect(finished, isTrue, reason: 'The actual source readers must close.');
    // This teardown runs outside testWidgets' fake-async zone. The completed
    // source future belongs to that zone, so completion is observed above
    // while pumping rather than awaiting it again from a different zone.
  }
}

Creature _extraPerson(String name) {
  final person = Creature.fromJson(
    jsonDecode(jsonEncode(game.pool.first.toJson())) as Map<String, dynamic>,
  );
  person.id = game.gameState.nextCreatureId++;
  person.name = name;
  person.squadId = null;
  game.pool.add(person);
  return person;
}

String _snapshot() => jsonEncode(game.gameState.toJson());

Finder _key(String value) => find.byKey(ValueKey(value));

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 35; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final target = _key(key);
  expect(
    target.hitTestable(),
    findsOneWidget,
    reason: '$key must be usable without hunting or scrolling.',
  );
  await tester.tap(target);
  await _settle(tester);
}

Future<void> _focusGame(WidgetTester tester) async {
  final focus = tester
      .widgetList<Focus>(find.byType(Focus))
      .singleWhere((widget) => widget.focusNode?.debugLabel == 'Game keyboard')
      .focusNode!;
  focus.requestFocus();
  await tester.pump();
  expect(focus.hasPrimaryFocus, isTrue);
}

void _insideViewport(
  WidgetTester tester,
  Finder finder,
  Size size,
  String what,
) {
  expect(finder, findsOneWidget, reason: what);
  final rect = tester.getRect(finder);
  expect(rect.left, greaterThanOrEqualTo(0), reason: '$what left');
  expect(rect.right, lessThanOrEqualTo(size.width), reason: '$what right');
  expect(rect.top, greaterThanOrEqualTo(0), reason: '$what top');
  expect(rect.bottom, lessThanOrEqualTo(size.height), reason: '$what bottom');
  expect(
    finder.hitTestable(),
    findsOneWidget,
    reason: '$what must be visible and reachable',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String fixture;
  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
    final serif = FontLoader('JournalSerif');
    serif.addFont(
      rootBundle.load('fonts/journal/LibreBaskerville-Variable.ttf'),
    );
    serif.addFont(
      rootBundle.load('fonts/journal/LibreBaskerville-Italic-Variable.ttf'),
    );
    await serif.load();
    final sans = FontLoader('ModernSans');
    for (final weight in ['regular', 'medium', 'bold', 'black']) {
      sans.addFont(rootBundle.load('fonts/modern/roboto-$weight.ttf'));
    }
    await sans.load();
  });
  setUp(() {
    journalReadingScale.value = 1;
    engine.console = Console();
    game.gameState = decodeSaveContents(fixture).gameState!;
    game.mode = GameMode.base;
    game.activeSquadMember = null;
    final sixth = _extraPerson('Sixth Crew Member');
    sixth.squad = game.activeSquad;
    for (final person in game.squad) {
      person.activity = Activity(ActivityType.sellArt);
    }
    expect(game.squad.length, 6);
  });

  Future<_JournalHarness> mount(
    WidgetTester tester, {
    Size size = const Size(1280, 720),
    bool monthlyReport = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    final harness = _JournalHarness(monthlyReport: monthlyReport);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await harness.stop(tester);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
    });
    await tester.pumpWidget(const MainApp());
    await _settle(tester);
    expect(find.byType(OrganisationJournal), findsOneWidget);
    return harness;
  }

  Future<void> business(WidgetTester tester) async {
    await _tap(tester, 'journal-orders');
    await _tap(tester, 'journal-order-group:0');
    expect(activityOrderFrame(engine.console)?.selectedCategoryKey, 'b');
  }

  testWidgets('crew reports has a distinct tooltip and accessible name', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await mount(tester);
      expect(find.byTooltip('Crew reports'), findsOneWidget);
      expect(
        tester.getSemantics(_key('journal-reports')).getSemanticsData().label,
        contains('Crew reports'),
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'daily orders leave a visit picker and offer explicit queued departure recovery',
    (tester) async {
      final team = game.activeSquad!;
      final destination = game.sites.firstWhere((site) => !site.hidden);
      team.activity = Activity(
        ActivityType.visit,
        idString: destination.idString,
      );
      final other = Squad()..name = 'Other team';
      game.squads.add(other);
      other.activity = Activity(
        ActivityType.visit,
        idString: destination.idString,
      );
      final originalOrders = game.squad.map((p) => p.activity).toList();
      final before = _snapshot();
      final date = game.date;
      final funds = game.ledger.funds;
      final harness = await mount(tester);
      await _tap(tester, 'journal-orders');
      await _tap(tester, 'journal-order-group:3');
      await _tap(tester, 'journal-plan-visit');
      expect(engine.console.screen, 'planning');
      await _tap(tester, 'journal-order-group:0');
      expect(engine.console.screen, 'headquarters');
      expect(_snapshot(), before);
      expect(_key('journal-confirm-order'), findsNothing);
      expect(find.text('Visit ${destination.getName()}'), findsOneWidget);
      expect(
        _key('journal-cancel-departure-edit-orders').hitTestable(),
        findsOneWidget,
      );
      await _tap(tester, 'journal-cancel-departure-edit-orders');
      expect(team.activity.type, ActivityType.none);
      expect(other.activity.type, ActivityType.visit);
      expect(harness.dispatched.where((key) => key == engine.Key.c).length, 1);
      expect(activityOrderFrame(engine.console)?.selectedCategoryKey, 'b');
      expect(_key('journal-activity:donations').hitTestable(), findsOneWidget);
      expect(game.squad.map((p) => p.activity).toList(), originalOrders);
      expect(game.date, date);
      expect(game.ledger.funds, funds);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'group browsing, task staging and Cancel leave actual assignments and RNG intact',
    (tester) async {
      await mount(tester);
      final person = game.squad.first;
      final order = person.activity;
      final before = _snapshot();
      reseedRNG(seed: 9013);
      final rolls = List.generate(12, (_) => lcsRandom(100000));
      reseedRNG(seed: 9013);
      await business(tester);
      expect(_snapshot(), before);
      expect(person.activity, same(order));
      for (final group in [1, 2, 3, 0]) {
        await _tap(tester, 'journal-order-group:$group');
        expect(_snapshot(), before);
        expect(person.activity, same(order));
      }
      final revision = engine.console.revision.value;
      await _tap(tester, 'journal-activity:donations');
      expect(_snapshot(), before);
      expect(person.activity, same(order));
      expect(
        engine.console.revision.value,
        revision,
        reason: 'Staging is local UI state.',
      );
      expect(find.text('Prepared · awaiting confirmation'), findsOneWidget);
      expect(_key('journal-confirm-order').hitTestable(), findsOneWidget);
      expect(find.textContaining('Uses: '), findsWidgets);
      await _tap(tester, 'journal-cancel-order');
      expect(_snapshot(), before);
      expect(person.activity, same(order));
      expect(_key('journal-confirm-order'), findsNothing);
      expect(find.text('Assigned order'), findsOneWidget);
      expect(engine.console.revision.value, revision);
      expect(List.generate(12, (_) => lcsRandom(100000)), rolls);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'raw journal category and task shortcuts remain previews until Enter',
    (tester) async {
      await mount(tester);
      final person = game.squad.first;
      final order = person.activity;
      await _tap(tester, 'journal-orders');
      await _focusGame(tester);
      final before = _snapshot();
      final date = game.date;
      final funds = game.ledger.funds;
      reseedRNG(seed: 81230);
      final rolls = List.generate(12, (_) => lcsRandom(100000));
      reseedRNG(seed: 81230);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB, character: 'b');
      await _settle(tester);
      expect(activityOrderFrame(engine.console)?.selectedCategoryKey, 'b');
      expect(person.activity, same(order));
      expect(_snapshot(), before);
      final revision = engine.console.revision.value;
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1, character: '1');
      await _settle(tester);
      expect(_key('journal-confirm-order').hitTestable(), findsOneWidget);
      expect(person.activity, same(order));
      expect(_snapshot(), before);
      expect(engine.console.revision.value, revision);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(tester);
      expect(_key('journal-confirm-order'), findsNothing);
      expect(person.activity, same(order));
      expect(_snapshot(), before);
      expect(engine.console.revision.value, revision);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1, character: '1');
      await _settle(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _settle(tester);
      expect(engine.console.screen, 'headquarters');
      expect(person.activity.type, ActivityType.donations);
      expect(
        game.squad
            .skip(1)
            .every((member) => member.activity.type == ActivityType.sellArt),
        isTrue,
      );
      expect(game.date, date);
      expect(game.ledger.funds, funds);
      expect(List.generate(12, (_) => lcsRandom(100000)), rolls);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('classic keyboard keeps its original immediate task behavior', (
    tester,
  ) async {
    await mount(tester);
    final person = game.squad.first;
    await _tap(tester, 'journal-orders');
    await tester.tap(find.byTooltip('Switch readable / classic view'));
    await _settle(tester);
    expect(find.byType(OrganisationJournal), findsNothing);
    await _focusGame(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyX, character: 'x');
    await _settle(tester);
    expect(person.activity.type, ActivityType.none);
    expect(activityOrderFrame(engine.console)?.actorId, person.id);
    expect(_key('journal-confirm-order'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Confirm changes only the explicitly selected person through the original handler',
    (tester) async {
      await mount(tester);
      final selected = game.squad[2];
      await _tap(tester, 'journal-member:${selected.id}');
      expect(
        tester.widget<Text>(_key('journal-selected-person')).data,
        selected.name,
      );
      final before = jsonDecode(_snapshot()) as Map<String, dynamic>;
      await business(tester);
      expect(activityOrderFrame(engine.console)?.actorId, selected.id);
      await _tap(tester, 'journal-activity:donations');
      await _tap(tester, 'journal-confirm-order');
      expect(engine.console.screen, 'headquarters');
      expect(selected.activity.type, ActivityType.donations);
      for (final person in game.squad.where((p) => p != selected)) {
        expect(person.activity.type, ActivityType.sellArt);
      }
      final after = jsonDecode(_snapshot()) as Map<String, dynamic>;
      final oldPool = (before['lcs'] as Map<String, dynamic>)['pool'] as List;
      final newPool = (after['lcs'] as Map<String, dynamic>)['pool'] as List;
      final index = game.pool.indexOf(selected);
      (oldPool[index] as Map<String, dynamic>)['activity'] =
          (newPool[index] as Map<String, dynamic>)['activity'];
      expect(
        after,
        before,
        reason: 'Only the confirmed source activity may change.',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'switching the order actor clears the previous draft without changing either assignment',
    (tester) async {
      await mount(tester);
      final next = game.squad[1];
      final before = _snapshot();
      await business(tester);
      await _tap(tester, 'journal-activity:donations');
      expect(_key('journal-confirm-order'), findsOneWidget);
      await _tap(tester, 'journal-member:${next.id}');
      expect(activityOrderFrame(engine.console)?.actorId, next.id);
      expect(_key('journal-confirm-order'), findsNothing);
      expect(find.text('Prepared · awaiting confirmation'), findsNothing);
      expect(
        tester.widget<Text>(_key('journal-selected-person')).data,
        next.name,
      );
      expect(_snapshot(), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'squad tabs select the exact team and repeated selection never opens allocation',
    (tester) async {
      final person = _extraPerson('Second Team Member');
      final team = Squad()..name = 'Second Team';
      game.squads.add(team);
      person.squad = team;
      await mount(tester);
      final time = game.date;
      final funds = game.ledger.funds;
      await _tap(tester, 'journal-squad:${team.id}');
      expect(game.activeSquad, same(team));
      expect(engine.console.screen, 'headquarters');
      expect(squadAllocationFrame(engine.console), isNull);
      expect(tester.widget<Text>(_key('journal-team-name')).data, team.name);
      final selected = _snapshot();
      await _tap(tester, 'journal-squad:${team.id}');
      expect(squadAllocationFrame(engine.console), isNull);
      expect(_snapshot(), selected);
      expect(game.date, time);
      expect(game.ledger.funds, funds);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Orders replaces the nonblocking inspector without an extra Close click',
    (tester) async {
      await mount(tester);
      final person = game.squad.first;
      final before = _snapshot();
      final revision = engine.console.revision.value;
      await _tap(tester, 'hq-dossier:${person.id}');
      expect(find.byType(CrewInspector), findsOneWidget);
      expect(engine.console.revision.value, revision);
      expect(_snapshot(), before);
      await business(tester);
      expect(activityOrderFrame(engine.console)?.actorId, person.id);
      expect(find.byType(CrewInspector), findsNothing);
      expect(_key('journal-activity:donations').hitTestable(), findsOneWidget);
      await _tap(tester, 'journal-activity:donations');
      expect(_key('journal-confirm-order').hitTestable(), findsOneWidget);
      expect(_snapshot(), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pool arrows remove and re-add a real member with no navigation confirmation',
    (tester) async {
      await mount(tester);
      final team = game.activeSquad!;
      final person = team.members[1];
      final time = game.date;
      await _tap(tester, 'journal-pool');
      expect(squadAllocationFrame(engine.console)?.squadId, team.id);
      final remove = find.byTooltip('Remove ${person.name} from this squad');
      expect(remove.hitTestable(), findsOneWidget);
      await tester.tap(remove);
      await _settle(tester);
      expect(person.squadId, isNull);
      expect(team.members, isNot(contains(person)));
      expect(
        _key('journal-pool-person:${person.id}').hitTestable(),
        findsOneWidget,
      );
      await _tap(tester, 'journal-transfer:${person.id}');
      expect(person.squad, same(team));
      expect(team.members.length, 6);
      expect(game.date, time);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Done closes existing allocation and returns to usable planning', (
    tester,
  ) async {
    await mount(tester);
    await _tap(tester, 'journal-pool');
    expect(squadAllocationFrame(engine.console), isNotNull);
    await tester.tap(find.widgetWithText(TextButton, 'Done'));
    await _settle(tester);
    expect(engine.console.screen, 'headquarters');
    expect(squadAllocationFrame(engine.console), isNull);
    expect(
      find.text('Available crew'),
      findsNothing,
      reason:
          'Done must not leave a pool page with an expired allocation behind.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'dragging a real crew member to the pool and back dispatches original allocation',
    (tester) async {
      await mount(tester);
      final team = game.activeSquad!;
      final person = team.members[1];
      final time = game.date;
      await _tap(tester, 'journal-pool');
      final poolTargets = find.descendant(
        of: _key('journal-pool-person:${person.id}'),
        matching: find.byType(DragTarget<int>),
      );
      expect(
        poolTargets,
        findsNothing,
        reason: 'A member starts on the team page.',
      );
      final targets = find.byType(DragTarget<int>);
      expect(targets, findsNWidgets(2));
      final source = tester.getCenter(_key('journal-member:${person.id}'));
      final pool = tester.getCenter(targets.last);
      final gesture = await tester.startGesture(source);
      await tester.pump();
      await gesture.moveTo(pool);
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      await _settle(tester);
      expect(person.squadId, isNull);
      expect(team.members, isNot(contains(person)));
      final returned = _key('journal-pool-person:${person.id}');
      expect(returned.hitTestable(), findsOneWidget);
      final add = await tester.startGesture(tester.getCenter(returned));
      await tester.pump();
      await add.moveTo(tester.getCenter(find.byType(DragTarget<int>).first));
      await tester.pump(const Duration(milliseconds: 50));
      await add.up();
      await _settle(tester);
      expect(person.squad, same(team));
      expect(team.members.length, 6);
      expect(game.date, time);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a full squad explains the pool restriction and disables Add', (
    tester,
  ) async {
    final extra = _extraPerson('Waiting Crew Member');
    await mount(tester);
    await _tap(tester, 'journal-pool');
    final before = _snapshot();
    final transfer = tester.widget<IconButton>(
      _key('journal-transfer:${extra.id}'),
    );
    expect(transfer.onPressed, isNull);
    await _tap(tester, 'journal-pool-person:${extra.id}');
    expect(find.text('The squad is full (six members).'), findsOneWidget);
    final add = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Add to this squad'),
    );
    expect(add.onPressed, isNull);
    expect(_snapshot(), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'sleeper orders remain reachable through source list, group and confirmed job card',
    (tester) async {
      final person = _extraPerson('Undercover Crew')..sleeperAgent = true;
      final oldOrder = Activity(ActivityType.sleeperLiberal);
      person.activity = oldOrder;
      await mount(tester);
      final before = _snapshot();
      await _tap(tester, 'journal-more-commands');
      final menu = find.text('Sleeper Agents');
      await tester.ensureVisible(menu);
      await tester.tap(menu);
      await _settle(tester);
      final choice = engine.console.actions.singleWhere(
        (action) =>
            action.entityType == 'person' &&
            action.entityId == person.id.toString(),
      );
      await _tap(tester, 'direct-action:${choice.y}:${choice.x}:${choice.key}');
      expect(activityOrderFrame(engine.console)?.actorId, person.id);
      expect(activityOrderFrame(engine.console)?.sleeper, isTrue);
      await _tap(tester, 'journal-order-group:0');
      expect(activityOrderFrame(engine.console)?.selectedCategoryKey, 'b');
      expect(_snapshot(), before);
      expect(person.activity, same(oldOrder));
      await _tap(tester, 'journal-activity:sleeperSpy');
      expect(_snapshot(), before);
      await _tap(tester, 'journal-cancel-order');
      expect(person.activity, same(oldOrder));
      await _tap(tester, 'journal-activity:sleeperSpy');
      await _tap(tester, 'journal-confirm-order');
      expect(person.activity.type, ActivityType.sleeperSpy);
      expect(engine.console.screen, 'headquarters');
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(1280, 720), const Size(800, 700)]) {
    testWidgets(
      'six crew, job card, eight sections and Confirm all fit at ${size.width}x${size.height}',
      (tester) async {
        await mount(tester, size: size);
        await business(tester);
        await _tap(tester, 'journal-activity:donations');
        for (var i = 0; i < 8; i++) {
          _insideViewport(
            tester,
            _key('journal-section:$i'),
            size,
            'Section $i',
          );
        }
        _insideViewport(tester, _key('journal-job-card'), size, 'Job card');
        _insideViewport(
          tester,
          _key('journal-confirm-order'),
          size,
          'Confirm order',
        );
        _insideViewport(
          tester,
          _key('journal-date-funds'),
          size,
          'Date and funds',
        );
        _insideViewport(tester, _key('journal-advance-day'), size, 'Run day');
        for (final person in game.squad) {
          _insideViewport(
            tester,
            _key('journal-member:${person.id}'),
            size,
            'Crew ${person.name}',
          );
        }
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '150 percent reading size retains usable controls without overflow at ${size.width}',
      (tester) async {
        await mount(tester, size: size);
        await business(tester);
        await _tap(tester, 'journal-activity:donations');
        await tester.tap(find.byTooltip('Reading size'));
        await _settle(tester);
        await tester.tap(find.text('150%'));
        await _settle(tester);
        final text = tester.element(_key('journal-selected-person'));
        expect(MediaQuery.textScalerOf(text).scale(10), 15);
        _insideViewport(
          tester,
          _key('journal-confirm-order'),
          size,
          'Scaled Confirm',
        );
        for (var i = 0; i < 8; i++) {
          _insideViewport(
            tester,
            _key('journal-section:$i'),
            size,
            'Scaled section $i',
          );
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    '800x600 at 150 percent shows prepared order timing inside its mechanics viewport',
    (tester) async {
      // Use the unchanged five-person save from the Chrome reproduction rather
      // than the six-person stress fixture used by the surrounding tests.
      game.gameState = decodeSaveContents(fixture).gameState!;
      game.mode = GameMode.base;
      game.activeSquadMember = null;
      expect(game.squad.length, 5);
      const size = Size(800, 600);
      await mount(tester, size: size);
      final before = _snapshot();
      await business(tester);
      await _tap(tester, 'journal-activity:donations');
      await tester.tap(find.byTooltip('Reading size'));
      await _settle(tester);
      await tester.tap(find.text('150%'));
      await _settle(tester);
      expect(
        MediaQuery.textScalerOf(
          tester.element(_key('journal-selected-person')),
        ).scale(10),
        15,
      );

      final card = _key('journal-job-card');
      final mechanics = find.descendant(
        of: card,
        matching: find.byType(SingleChildScrollView),
      );
      expect(mechanics, findsOneWidget);
      final timing = find.descendant(
        of: card,
        matching: find.text(
          activityMechanics(
            ActivityType.donations,
            actor: game.squad.first,
          ).timing,
        ),
      );
      _insideViewport(tester, timing, size, 'Prepared daily execution timing');
      final clip = tester.getRect(mechanics);
      final label = tester.getRect(timing);
      expect(clip.height, greaterThan(0));
      expect(label.top, greaterThanOrEqualTo(clip.top));
      expect(
        label.bottom,
        lessThanOrEqualTo(clip.bottom),
        reason:
            'Timing must be fully visible inside the mechanics scroll clip.',
      );
      expect(
        find
            .descendant(of: card, matching: find.text('Order mechanics'))
            .hitTestable(),
        findsOneWidget,
        reason: 'The actual mechanics disclosure must remain reachable.',
      );
      _insideViewport(
        tester,
        _key('journal-confirm-order'),
        size,
        'Prepared order confirmation',
      );
      _insideViewport(
        tester,
        _key('journal-cancel-order'),
        size,
        'Prepared order cancellation',
      );
      expect(_snapshot(), before);
      await _tap(tester, 'journal-cancel-order');
      expect(_snapshot(), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'uncommon HQ commands remain reachable and invoke the actual original reader',
    (tester) async {
      final harness = await mount(tester);
      final before = _snapshot();
      final choices = List<ConsoleAction>.of(engine.console.actions);
      await _tap(tester, 'journal-more-commands');
      final items = tester
          .widgetList<PopupMenuItem<ConsoleAction>>(
            find.byType(PopupMenuItem<ConsoleAction>),
          )
          .toList();
      expect(items.map((item) => item.value), unorderedEquals(choices));
      for (final item in items) {
        expect(item.enabled, item.value!.enabled);
      }
      await tester.ensureVisible(find.text('Reorder'));
      await tester.tap(find.text('Reorder'));
      await _settle(tester);
      expect(harness.dispatched.last, engine.Key.o);
      expect(engine.console.awaitingInput, isTrue);
      expect(
        engine.console.actions.any(
          (action) => action.label == game.squad.first.name,
        ),
        isTrue,
      );
      expect(engine.console.navigation, isNull);
      expect(_snapshot(), before);
      engine.console.sendInput('Enter');
      await _settle(tester);
      expect(engine.console.screen, 'headquarters');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Newspaper opens a full spread, its real article and returns to organisation',
    (tester) async {
      final article = NewsStory()
        ..headline =
            'A complete recorded headline longer than the old terminal column'
        ..publication = Publication.times
        ..body =
            'First complete paragraph.\n\n${List.filled(40, 'The complete original body stays readable.').join(' ')}'
        ..byline = 'An actual archived correspondent';
      game.gameState.newsArchive.add(article);
      await mount(tester);
      await _tap(tester, 'journal-section:4');
      expect(mediaOverviewFrame(engine.console), isNotNull);
      expect(find.byType(JournalMediaOverview), findsOneWidget);
      expect(
        tester.getRect(find.byType(JournalMediaOverview)).width,
        greaterThan(1000),
      );
      expect(find.text(article.headline), findsOneWidget);
      expect(_key('journal-media-back').hitTestable(), findsOneWidget);
      await _tap(tester, 'journal-media-story:0');
      expect(find.byType(ArticleView), findsOneWidget);
      expect(tester.getRect(find.byType(ArticleView)).width, greaterThan(1000));
      expect(
        tester.widget<SelectableText>(_key('article-body')).data,
        article.body,
      );
      expect(article.unread, isFalse);
      await _tap(tester, 'specialized-return');
      expect(find.byType(JournalMediaOverview), findsOneWidget);
      expect(
        mediaOverviewFrame(engine.console)?.entries.single.unread,
        isFalse,
      );
      await _tap(tester, 'journal-media-back');
      expect(engine.console.screen, 'headquarters');
      expect(
        _key('journal-member:${game.squad.first.id}').hitTestable(),
        findsOneWidget,
        reason:
            'Archive Back must return to the usable organisation, with its squad visible.',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'manual ledger permits a direct chapter switch without resetting recorded money',
    (tester) async {
      game.ledger.income[Income.donations] = 345;
      await mount(tester);
      final before = _snapshot();
      await _tap(tester, 'journal-section:1');
      expect(ledgerReportFrame(engine.console)?.management, isTrue);
      expect(engine.console.navigation?.section, 'ledger');
      expect(find.byType(JournalLedgerOverview), findsOneWidget);
      expect(
        tester.getRect(find.byType(JournalLedgerOverview)).width,
        greaterThan(1000),
      );
      await _tap(tester, 'journal-section:4');
      expect(mediaOverviewFrame(engine.console), isNotNull);
      expect(find.byType(JournalMediaOverview), findsOneWidget);
      expect(game.ledger.income[Income.donations], 345);
      expect(_snapshot(), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'manual ledger Back restores the organisation without an extra chapter click',
    (tester) async {
      await mount(tester);
      final before = _snapshot();
      await _tap(tester, 'journal-section:1');
      expect(ledgerReportFrame(engine.console)?.management, isTrue);
      await _tap(tester, 'journal-ledger-close');
      expect(ledgerReportFrame(engine.console), isNull);
      expect(
        _key('journal-member:${game.squad.first.id}').hitTestable(),
        findsOneWidget,
      );
      expect(_snapshot(), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'required monthly ledger stays full spread and Options cannot hide Continue',
    (tester) async {
      game.ledger.income[Income.donations] = 345;
      final harness = await mount(tester, monthlyReport: true);
      await _tap(tester, 'journal-advance-day');
      expect(ledgerReportFrame(engine.console)?.management, isFalse);
      expect(engine.console.navigation, isNull);
      expect(find.byType(JournalLedgerOverview), findsOneWidget);
      expect(
        tester.getRect(find.byType(JournalLedgerOverview)).width,
        greaterThan(1000),
      );
      expect(_key('journal-ledger-close').hitTestable(), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      final before = _snapshot();
      final revision = engine.console.revision.value;
      final optionTap = find.descendant(
        of: _key('journal-section:7'),
        matching: find.byType(InkWell),
      );
      expect(tester.widget<InkWell>(optionTap).onTap, isNull);
      await tester.tap(_key('journal-section:7'));
      await _settle(tester);
      expect(find.text('Journal options'), findsNothing);
      expect(_key('journal-ledger-close').hitTestable(), findsOneWidget);
      expect(ledgerReportFrame(engine.console)?.management, isFalse);
      expect(engine.console.revision.value, revision);
      expect(_snapshot(), before);
      expect(harness.monthReset, isFalse);
      expect(game.ledger.income[Income.donations], 345);
      await _tap(tester, 'journal-ledger-close');
      expect(harness.monthReset, isTrue);
      expect(game.ledger.income[Income.donations], 0);
      expect(engine.console.screen, 'headquarters');
      expect(
        _key('journal-member:${game.squad.first.id}').hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Newspaper to Options is one click and leaves no archive covering the settings',
    (tester) async {
      await mount(tester);
      await _tap(tester, 'journal-section:4');
      expect(find.byType(JournalMediaOverview), findsOneWidget);
      await _tap(tester, 'journal-section:7');
      expect(engine.console.screen, 'headquarters');
      expect(find.text('Journal options'), findsOneWidget);
      expect(find.byType(JournalMediaOverview), findsNothing);
      expect(_key('journal-section:0').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('raw Escape from Agenda returns to the visible organisation', (
    tester,
  ) async {
    await mount(tester);
    final before = _snapshot();
    await _tap(tester, 'journal-section:3');
    expect(engine.console.navigation?.section, 'agenda');
    await _focusGame(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(engine.console.screen, 'headquarters');
    expect(
      _key('journal-member:${game.squad.first.id}').hitTestable(),
      findsOneWidget,
    );
    expect(_snapshot(), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'phone-width journal retains readable pages and scrolls to day controls',
    (tester) async {
      await mount(tester, size: const Size(360, 640));
      final scroll = find.byKey(const ValueKey('journal-narrow-scroll'));
      expect(scroll, findsOneWidget);
      expect(tester.getSize(find.byType(OrganisationJournal)).width, 360);
      final advance = _key('journal-advance-day');
      await tester.ensureVisible(advance);
      await tester.pumpAndSettle();
      final rect = tester.getRect(advance);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(360));
      expect(advance.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an active siege cannot advertise an available day advance', (
    tester,
  ) async {
    game.activeSquad!.site!.siege
      ..activeSiegeType = SiegeType.police
      ..underAttack = true;
    await mount(tester);
    expect(engine.console.actions.any((action) => action.key == 'w'), isFalse);
    final advance = _key('journal-advance-day');
    if (advance.evaluate().isNotEmpty) {
      expect(
        tester.widget<FilledButton>(advance).onPressed,
        isNull,
        reason:
            'The real HQ has no W capability until this attack is resolved.',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Confirm paid classes leaves the required original skill choice visible',
    (tester) async {
      await mount(tester);
      final person = game.squad.first;
      final order = person.activity;
      final before = _snapshot();
      await _tap(tester, 'journal-orders');
      await _tap(tester, 'journal-order-group:1');
      await tester.tap(
        find.widgetWithText(OutlinedButton, 'Education and Learning'),
      );
      await _settle(tester);
      expect(activityOrderFrame(engine.console)?.selectedCategoryKey, 'e');
      await _tap(tester, 'journal-activity:takeClass');
      await _tap(tester, 'journal-confirm-order');
      expect(engine.console.awaitingInput, isTrue);
      expect(activityOrderFrame(engine.console), isNull);
      expect(engine.console.navigation, isNull);
      expect(find.textContaining('What skill will'), findsWidgets);
      expect(find.byType(OrganisationJournal), findsOneWidget);
      expect(person.activity, same(order));
      expect(_snapshot(), before);
      expect(tester.takeException(), isNull);
    },
  );
}
