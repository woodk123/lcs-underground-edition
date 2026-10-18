import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activate_regulars.dart';
import 'package:lcs_new_age/basemode/activate_sleepers.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/basemode/base_mode.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/engine/organisation_context.dart';
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/modern/journal_network.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/organisation_journal.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_support.dart';

/// Original HQ options and sleeper readers, with no day-advance handler.
class _NetworkHarness {
  _NetworkHarness() {
    done = _loop();
  }
  late final Future<void> done;
  bool stopped = false;
  bool finished = false;

  Future<void> _loop() async {
    try {
      while (!stopped) {
        engine.erase();
        final location = game.activeSquad?.site ?? game.activeSafehouse;
        baseModeSquadSafehouseDisplay(location);
        baseModeOptionsDisplay(location);
        final key = await engine.getKey();
        if (stopped) break;
        switch (key) {
          case engine.Key.a:
            await activateRegulars();
          case engine.Key.b:
            await activateSleepers();
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
    expect(finished, isTrue, reason: 'Original order readers must close.');
  }
}

Creature _sleeper(String name, {ActivityType order = ActivityType.none}) {
  final person = Creature.fromJson(
    jsonDecode(jsonEncode(game.pool.first.toJson())) as Map<String, dynamic>,
  );
  person
    ..id = game.gameState.nextCreatureId++
    ..name = name
    ..squadId = null
    ..sleeperAgent = true
    ..activity = Activity(order);
  game.pool.add(person);
  return person;
}

String _snapshot() => jsonEncode(game.gameState.toJson());
Finder _key(String key) => find.byKey(ValueKey(key));

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 35; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  final target = _key(key);
  expect(target, findsOneWidget);
  await tester.ensureVisible(target);
  await _settle(tester);
  expect(target.hitTestable(), findsOneWidget, reason: '$key is reachable');
  await tester.tap(target);
  await _settle(tester);
}

Future<void> _keyboard(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  String? character,
}) async {
  final focus = tester
      .widgetList<Focus>(find.byType(Focus))
      .singleWhere((widget) => widget.focusNode?.debugLabel == 'Game keyboard')
      .focusNode!;
  focus.requestFocus();
  await tester.pump();
  expect(focus.hasPrimaryFocus, isTrue);
  await tester.sendKeyEvent(key, character: character);
  await _settle(tester);
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
    SharedPreferences.setMockInitialValues({});
    journalReadingScale.value = 1;
    engine.console = Console();
    game.gameState = decodeSaveContents(fixture).gameState!;
    game.mode = GameMode.base;
    game.activeSquadMember = null;
  });

  tearDown(() => journalReadingScale.value = 1);

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(1440, 1000),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    final harness = _NetworkHarness();
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
    await _tap(tester, 'journal-section:8');
    expect(find.byType(JournalNetworkView), findsOneWidget);
  }

  testWidgets(
    'Network top tab explains the empty network without changing play',
    (tester) async {
      final before = _snapshot();
      reseedRNG(seed: 814002);
      final rolls = List.generate(8, (_) => lcsRandom(100000));
      reseedRNG(seed: 814002);
      await mount(tester);
      expect(find.text('Network'), findsOneWidget);
      expect(_key('network-empty'), findsOneWidget);
      expect(find.text('No sleeper agents yet.'), findsOneWidget);
      expect(find.textContaining('monthly standing order'), findsOneWidget);
      expect(_key('journal-section:0').hitTestable(), findsOneWidget);
      expect(_snapshot(), before);
      expect(List.generate(8, (_) => lcsRandom(100000)), rolls);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('roster, dossier, mechanics and Keep Lay Low are read only', (
    tester,
  ) async {
    final person = _sleeper('Mara Undercover');
    final originalOrder = person.activity;
    final before = _snapshot();
    reseedRNG(seed: 814003);
    final rolls = List.generate(8, (_) => lcsRandom(100000));
    reseedRNG(seed: 814003);
    await mount(tester);
    expect(_key('network-agent:${person.id}'), findsOneWidget);
    expect(find.textContaining('1 to review'), findsOneWidget);
    await tester.tap(find.text('View dossier'));
    await _settle(tester);
    expect(_key('crew-inspector'), findsOneWidget);
    await _tap(tester, 'crew-inspector-close');
    await _tap(tester, 'network-order-mechanics');
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2, character: '2');
    await _settle(tester);
    expect(person.activity, same(originalOrder));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(find.byType(AlertDialog), findsNothing);
    await _tap(tester, 'network-espionage');
    expect(activityOrderFrame(engine.console)?.actorId, person.id);
    await _tap(tester, 'network-task:sleeperSpy');
    expect(find.text('Prepared change · not confirmed'), findsOneWidget);
    await _tap(tester, 'network-cancel-order');
    await _tap(tester, 'network-keep-order');
    expect(find.textContaining('to review'), findsNothing);
    expect(find.text('Current role reviewed.'), findsOneWidget);
    expect(person.activity, same(originalOrder));
    expect(_snapshot(), before);
    expect(List.generate(8, (_) => lcsRandom(100000)), rolls);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'cancel and person switching discard drafts; Enter confirms selected actor',
    (tester) async {
      final first = _sleeper('First Sleeper');
      final second = _sleeper('Second Sleeper', order: ActivityType.sleeperSpy);
      final firstOrder = first.activity;
      final secondOrder = second.activity;
      final before = _snapshot();
      await mount(tester);
      await _keyboard(tester, LogicalKeyboardKey.keyB, character: 'b');
      await _keyboard(tester, LogicalKeyboardKey.digit2, character: '2');
      expect(_key('network-confirm-order'), findsOneWidget);
      expect(_snapshot(), before);
      await _keyboard(tester, LogicalKeyboardKey.escape);
      expect(_key('network-confirm-order'), findsNothing);
      expect(_snapshot(), before);
      await _tap(tester, 'network-espionage');
      await _tap(tester, 'network-task:sleeperEmbezzle');
      await _tap(tester, 'network-agent:${second.id}');
      expect(_key('network-confirm-order'), findsNothing);
      await _keyboard(tester, LogicalKeyboardKey.enter);
      expect(first.activity, same(firstOrder));
      expect(second.activity, same(secondOrder));
      expect(_snapshot(), before);

      await _tap(tester, 'network-advocacy');
      await _tap(tester, 'network-task:sleeperLiberal');
      second.activity = Activity(ActivityType.sleeperLiberal);
      final expected = _snapshot();
      second.activity = secondOrder;
      await _keyboard(tester, LogicalKeyboardKey.enter);
      expect(first.activity, same(firstOrder));
      expect(second.activity.type, ActivityType.sleeperLiberal);
      expect(_snapshot(), expected);
      expect(engine.console.screen, 'headquarters');
      expect(
        find.text('Standing order confirmed. Repeats until changed.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('stale source revision cannot confirm a captured draft', (
    tester,
  ) async {
    final person = _sleeper('Careful Agent');
    final original = person.activity;
    await mount(tester);
    await _tap(tester, 'network-espionage');
    await _tap(tester, 'network-task:sleeperEmbezzle');
    engine.console.revision.value++;
    await _settle(tester);
    final before = _snapshot();
    expect(_key('network-confirm-order'), findsNothing);
    await _keyboard(tester, LogicalKeyboardKey.enter);
    expect(person.activity, same(original));
    expect(_snapshot(), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mechanics dialog keys cannot confirm the draft behind it', (
    tester,
  ) async {
    final person = _sleeper('Patient Planner');
    final original = person.activity;
    await mount(tester);
    await _tap(tester, 'network-espionage');
    await _tap(tester, 'network-task:sleeperEmbezzle');
    await _tap(tester, 'network-order-mechanics');
    final before = _snapshot();
    final revision = engine.console.revision.value;
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _settle(tester);
    expect(person.activity, same(original));
    expect(engine.console.revision.value, revision);
    if (find.byType(AlertDialog).evaluate().isNotEmpty) {
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(tester);
    }
    expect(find.byType(AlertDialog), findsNothing);
    expect(_key('network-confirm-order'), findsOneWidget);
    expect(_snapshot(), before);
    await _keyboard(tester, LogicalKeyboardKey.escape);
    expect(_key('network-confirm-order'), findsNothing);
    expect(_snapshot(), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'eligibility change prevents Enter from committing an open draft',
    (tester) async {
      final person = _sleeper('Interrupted Agent');
      final original = person.activity;
      await mount(tester);
      await _tap(tester, 'network-espionage');
      await _tap(tester, 'network-task:sleeperEmbezzle');
      person.hidingDaysLeft = 3;
      final before = _snapshot();
      final revision = engine.console.revision.value;
      await _keyboard(tester, LogicalKeyboardKey.enter);
      expect(person.activity, same(original));
      expect(engine.console.revision.value, revision);
      expect(_snapshot(), before);
      engine.console.revision.value++;
      await _settle(tester);
      expect(find.textContaining('Cannot change orders:'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('recall confirms its next eligible day without advancing time', (
    tester,
  ) async {
    final person = _sleeper('Returning Agent', order: ActivityType.sleeperSpy);
    final original = person.activity;
    await mount(tester);
    await _keyboard(tester, LogicalKeyboardKey.keyC, character: 'c');
    expect(find.text('Confirm recall'), findsOneWidget);
    expect(find.textContaining('Next eligible day'), findsOneWidget);
    expect(person.activity, same(original));
    person.activity = Activity(ActivityType.sleeperJoinLcs);
    final expected = _snapshot();
    person.activity = original;
    final date = game.date;
    await _keyboard(tester, LogicalKeyboardKey.enter);
    expect(person.sleeperAgent, isTrue);
    expect(person.activity.type, ActivityType.sleeperJoinLcs);
    expect(game.date, date);
    expect(_snapshot(), expected);
    expect(
      find.text('Recall confirmed. Returns on the next eligible day.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'unavailable sleepers remain visible with disabled order controls',
    (tester) async {
      final hidden = _sleeper('Hidden Agent')..hidingDaysLeft = 3;
      final vacation = _sleeper('Holiday Agent')..vacationDaysLeft = 2;
      final patient = _sleeper('Recovering Agent')
        ..location = game.sites.firstWhere(
          (site) => site.type == SiteType.universityHospital,
        );
      final before = _snapshot();
      await mount(tester);
      for (final person in [hidden, vacation, patient]) {
        await _tap(tester, 'network-agent:${person.id}');
        expect(find.textContaining('Cannot change orders:'), findsOneWidget);
        for (final key in [
          'network-lay-low',
          'network-advocacy',
          'network-espionage',
          'network-recall',
        ]) {
          expect(tester.widget<OutlinedButton>(_key(key)).onPressed, isNull);
        }
        await _keyboard(tester, LogicalKeyboardKey.keyB, character: 'b');
        await _keyboard(tester, LogicalKeyboardKey.digit2, character: '2');
        await _keyboard(tester, LogicalKeyboardKey.enter);
        expect(_key('network-confirm-order'), findsNothing);
      }
      expect(_snapshot(), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'acknowledged role stays quiet through ordinary infiltration and date drift',
    (tester) async {
      final person = _sleeper('Settled Agent');
      await mount(tester);
      expect(find.textContaining('1 to review'), findsOneWidget);
      await _tap(tester, 'network-keep-order');
      person.infiltration += 0.03;
      game.gameState.date = game.date.add(const Duration(days: 31));
      engine.console.revision.value++;
      await _settle(tester);
      expect(find.textContaining('to review'), findsNothing);
      expect(find.text('Review role'), findsNothing);
      expect(find.text('1 agent'), findsOneWidget);
      await _tap(tester, 'journal-section:0');
      await _tap(tester, 'journal-section:8');
      expect(find.text('Review role'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('800 by 600 at 150 percent keeps orders and dossier reachable', (
    tester,
  ) async {
    final person = _sleeper('Readable Agent');
    journalReadingScale.value = 1.5;
    await mount(tester, size: const Size(800, 600));
    expect(_key('network-stacked-scroll'), findsOneWidget);
    await _tap(tester, 'network-keep-order');
    await _tap(tester, 'network-espionage');
    await _tap(tester, 'network-task:sleeperSpy');
    await _tap(tester, 'network-cancel-order');
    final dossier = find.text('View dossier');
    await tester.ensureVisible(dossier);
    await _settle(tester);
    await tester.tap(dossier);
    await _settle(tester);
    expect(_key('crew-inspector'), findsOneWidget);
    await _tap(tester, 'crew-inspector-close');
    final outer = find
        .descendant(
          of: _key('network-stacked-scroll'),
          matching: find.byType(Scrollable),
        )
        .first;
    tester.state<ScrollableState>(outer).position.jumpTo(0);
    await _settle(tester);
    expect(_key('network-agent:${person.id}'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
