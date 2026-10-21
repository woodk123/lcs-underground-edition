import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/basemode/plan_site_visit.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/modern/city_planning_view.dart';
import 'package:lcs_new_age/modern/city_scene.dart';
import 'package:lcs_new_age/modern/crew_dossier.dart';
import 'package:lcs_new_age/modern/crew_portrait.dart';
import 'package:lcs_new_age/saveload/save_load.dart';

import 'test_support.dart';

ConsoleAction option(
  Console console,
  int y,
  String key,
  String label, {
  bool enabled = true,
  int x = 0,
  String details = '',
  String? entityType,
  String? entityId,
  String? category,
}) {
  console.move(y, x);
  console.addAction(key, label, enabled: enabled, caseSensitive: true);
  console.addstr('$label$details');
  if (entityType != null) {
    final source = console.actions.removeLast();
    console.actions.add(
      ConsoleAction(
        key: source.key,
        label: source.label,
        enabled: source.enabled,
        y: source.y,
        x: source.x,
        width: source.width,
        entityType: entityType,
        entityId: entityId,
        entityCategory: category,
      ),
    );
  }
  return console.actions.last;
}

Finder control(ConsoleAction action) =>
    find.byKey(ValueKey('direct-action:${action.y}:${action.x}:${action.key}'));
Finder building(ConsoleAction action) => find.byKey(
  ValueKey(
    'city-building:${action.entityId ?? '${action.y}:${action.key}:${action.label.replaceFirst(RegExp(r'^\s*\S+\s+[-–—]\s*'), '').trim()}'}',
  ),
);
Finder order(ConsoleAction action) => find.byKey(
  ValueKey(
    'city-order:${action.entityId ?? '${action.y}:${action.key}:${action.label.replaceFirst(RegExp(r'^\s*\S+\s+[-–—]\s*'), '').trim()}'}',
  ),
);

Console planningFixture() {
  final console = Console()..screen = 'planning';
  console.mvaddstr(8, 0, 'Seattle——————————————————————————');
  option(console, 2, '1', '1 Bernie Spitzer');
  console.mvaddstr(2, 23, '16/2');
  console.mvaddstr(2, 29, 'Unarmed');
  console.mvaddstr(2, 44, 'Clothes');
  console.mvaddstr(2, 59, '230+30');
  console.mvaddstr(2, 70, 'Foot');
  option(
    console,
    10,
    'a',
    'a - Warehouse',
    details: ' (Current Location)',
    entityType: 'site',
    entityId: 'Site10',
    category: 'Warehouse',
  );
  console.mvaddstr(10, 54, 'Heat: 3');
  console.mvaddstr(10, 66, 'Secrecy: 8');
  option(
    console,
    11,
    'b',
    'b - Factory',
    enabled: false,
    details: ' (Closed Down) (Need Car)',
    entityType: 'site',
    entityId: 'Site11',
    category: 'Dirty Industry',
  );
  option(
    console,
    12,
    'C',
    'C - Courthouse',
    details: ' (High Security)',
    entityType: 'site',
    entityId: 'Site12',
    category: 'Courthouse',
  );
  console.mvaddstr(13, 0, 'An unexposed place must not become a destination');
  option(
    console,
    21,
    'k',
    'k - Travel to a Different City',
    enabled: false,
    details: ' (Need Car) (\$300)',
  );
  option(console, 20, 'PageDown', '] - Next', x: 60);
  option(console, 24, 'Enter', 'Enter - Back one step', x: 1);
  return console;
}

Future<void> mountBoard(
  WidgetTester tester,
  Console console,
  Size size,
  ValueChanged<String> onAction, {
  double? viewportHeight,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'ModernSans'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: CityPlanningView(
            console: console,
            onAction: onAction,
            viewportHeight: viewportHeight,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> click(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late final String saveContents;
  setUpAll(() async {
    await ensureGameDataLoaded();
    saveContents = await File('test/saves/felix_1_0.json').readAsString();
    final fonts = FontLoader('ModernSans');
    for (final weight in ['regular', 'medium', 'bold', 'black']) {
      fonts.addFont(rootBundle.load('fonts/modern/roboto-$weight.ttf'));
    }
    await fonts.load();
  });
  setUp(() {
    game.gameState = game.GameState();
  });

  for (final size in [
    const Size(1280, 800),
    const Size(1280, 720),
    const Size(1024, 720),
    const Size(480, 700),
  ]) {
    testWidgets(
      'buildings inspect without input, explicit orders preserve exact case at ${size.width}',
      (tester) async {
        final console = planningFixture();
        final received = <String>[];
        final startDate = game.date;
        await mountBoard(tester, console, size, received.add);
        final warehouse = console.actions.singleWhere((a) => a.key == 'a');
        final factory = console.actions.singleWhere((a) => a.key == 'b');
        final courthouse = console.actions.singleWhere((a) => a.key == 'C');
        expect(find.byType(CityScene), findsOneWidget);
        expect(
          find.byKey(const ValueKey('city-planning-board')),
          findsOneWidget,
        );
        expect(find.textContaining('An unexposed place'), findsNothing);
        expect(find.byType(SelectableText), findsNothing);
        expect(find.text('AVAILABLE CHOICES'), findsNothing);
        expect(find.text('Success probability'), findsNothing);
        expect(find.textContaining('Health 230+30'), findsOneWidget);
        expect(order(warehouse), findsNothing);
        final idleMap = tester.getRect(
          find.byKey(const ValueKey('city-planning-board')),
        );
        final workspace = tester.getRect(
          find.byKey(const ValueKey('city-viewport')),
        );
        expect(idleMap.width, workspace.width);
        final objects = tester
            .widget<CityScene>(find.byType(CityScene))
            .buildings;
        expect(objects.map((e) => e.id), ['Site10', 'Site11', 'Site12']);
        expect(objects.map((e) => e.spriteIndex), [3, 4, 6]);
        await click(tester, building(factory));
        expect(received, isEmpty);
        expect(game.date, startDate);
        final activeMap = tester.getRect(
          find.byKey(const ValueKey('city-planning-board')),
        );
        final activeInspector = tester.getRect(
          find.byKey(const ValueKey('city-building-inspector')),
        );
        expect(activeMap.overlaps(activeInspector), isFalse);
        expect(activeMap.height, greaterThan(100));
        expect(activeMap.bottom, lessThanOrEqualTo(workspace.bottom));
        if (size.width < 740) {
          final viewport = tester.getRect(
            find.byKey(const ValueKey('city-viewport')),
          );
          expect(
            tester.getRect(order(factory)).bottom,
            lessThanOrEqualTo(viewport.bottom),
          );
          expect(
            tester.getRect(order(factory)).top,
            greaterThanOrEqualTo(viewport.top),
          );
        }
        expect(find.text('Closed Down'), findsOneWidget);
        expect(find.text('Need Car'), findsOneWidget);
        expect(find.textContaining('preferred vehicle'), findsOneWidget);
        expect(find.textContaining('cannot queue a visit'), findsOneWidget);
        expect(tester.widget<FilledButton>(order(factory)).onPressed, isNull);
        await click(tester, order(factory));
        expect(received, isEmpty);
        await click(tester, building(warehouse));
        expect(received, isEmpty);
        expect(find.text('Current Location'), findsOneWidget);
        expect(find.text('Heat: 3'), findsOneWidget);
        expect(find.text('Secrecy: 8'), findsOneWidget);
        expect(find.textContaining('not percentages'), findsOneWidget);
        await click(tester, order(warehouse));
        expect(received, ['a']);
        expect(game.date, startDate);
        await click(tester, building(courthouse));
        expect(received, ['a']);
        expect(find.text('High Security'), findsOneWidget);
        await click(tester, order(courthouse));
        expect(received, ['a', 'C']);
        await click(tester, find.text('Locations list'));
        expect(find.byType(CityScene), findsNothing);
        expect(
          find.byKey(const ValueKey('city-locations-list')),
          findsOneWidget,
        );
        await click(tester, control(warehouse));
        expect(received, ['a', 'C']);
        await click(tester, order(warehouse));
        expect(received, ['a', 'C', 'a']);
        final next = console.actions.singleWhere((a) => a.key == 'PageDown');
        final back = console.actions.singleWhere((a) => a.key == 'Enter');
        await click(tester, control(next));
        await click(tester, control(back));
        expect(received, ['a', 'C', 'a', 'PageDown', 'Enter']);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'city and district browsing uses one activation, blocked areas remain inspectable',
    (tester) async {
      final console = Console()..screen = 'planning';
      console.mvaddstr(8, 0, 'Seattle');
      final district = option(
        console,
        10,
        'D',
        'D - Industrial District',
        entityType: 'district',
        entityId: 'District2',
      );
      final city = option(
        console,
        11,
        'c',
        'c - Boston',
        entityType: 'city',
        entityId: 'City3',
      );
      final blocked = option(
        console,
        12,
        'b',
        'b - Out of town',
        entityType: 'district',
        entityId: 'District4',
        enabled: false,
        details: ' (Need Car)',
      );
      final received = <String>[];
      await mountBoard(
        tester,
        console,
        const Size(1280, 720),
        received.add,
        viewportHeight: 450,
      );
      final date = game.date;
      await click(tester, building(district));
      expect(received, ['D']);
      expect(order(district), findsNothing);
      await click(tester, building(city));
      expect(received, ['D', 'c']);
      expect(order(city), findsNothing);
      await click(tester, building(blocked));
      expect(received, ['D', 'c']);
      expect(tester.widget<FilledButton>(order(blocked)).onPressed, isNull);
      expect(find.textContaining('preferred vehicle'), findsOneWidget);
      await click(tester, find.text('Locations list'));
      await click(tester, control(district));
      expect(received, ['D', 'c', 'D']);
      expect(game.date, date);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'captured original order is inert after action removal or revision change',
    (tester) async {
      final console = planningFixture();
      final received = <String>[];
      await mountBoard(tester, console, const Size(1280, 800), received.add);
      final action = console.actions.singleWhere((a) => a.key == 'a');
      await click(tester, building(action));
      final oldPress = tester.widget<FilledButton>(order(action)).onPressed!;
      console.actions.remove(action);
      oldPress();
      expect(received, isEmpty);
      console.actions.add(action);
      console.flush();
      oldPress();
      expect(received, isEmpty);
      await tester.pumpAndSettle();
      await click(tester, order(action));
      expect(received, ['a']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'read-only inspection stays accessible when an order is disabled',
    (tester) async {
      final console = planningFixture();
      final received = <String>[];
      final semantics = tester.ensureSemantics();
      await mountBoard(tester, console, const Size(1024, 720), received.add);
      final factory = console.actions.singleWhere((a) => a.key == 'b');
      final node = tester.getSemantics(building(factory));
      expect(node.label, 'Inspect Factory');
      expect(node.value, contains('Order unavailable'));
      expect(node.value, contains('Closed Down'));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      tester.binding.renderViews.single.owner!.semanticsOwner!.performAction(
        node.id,
        SemanticsAction.tap,
      );
      await tester.pumpAndSettle();
      expect(order(factory), findsOneWidget);
      expect(tester.widget<FilledButton>(order(factory)).onPressed, isNull);
      expect(received, isEmpty);
      semantics.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('zoom, reset and keyboard inspection change presentation only', (
    tester,
  ) async {
    final console = planningFixture();
    final received = <String>[];
    await mountBoard(tester, console, const Size(1280, 800), received.add);
    final interactive = tester.widget<InteractiveViewer>(
      find.byKey(const ValueKey('city-pan-zoom')),
    );
    final initial = interactive.transformationController!.value.clone();
    await click(tester, find.byKey(const ValueKey('city-zoom-in')));
    expect(
      interactive.transformationController!.value.entry(0, 0),
      greaterThan(initial.entry(0, 0)),
    );
    await click(tester, find.byKey(const ValueKey('city-fit')));
    expect(interactive.transformationController!.value, initial);
    expect(received, isEmpty);
    FocusManager.instance.primaryFocus?.unfocus();
    var focused = false;
    for (var i = 0; i < 20 && !focused; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      focused =
          tester.widget<Text>(find.text('Factory')).style?.color ==
          Colors.white;
    }
    expect(focused, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(
      order(console.actions.singleWhere((a) => a.key == 'b')),
      findsOneWidget,
    );
    expect(received, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'real planning hides undiscovered sites; inspection and order are separate',
    (tester) async {
      engine.console = Console();
      game.gameState = decodeSaveContents(saveContents).gameState!;
      game.mode = GameMode.base;
      game.activeSquadMember = null;
      final squad = game.activeSquad!;
      final founder = squad.members.first;
      founder.name = 'A remarkably long code name to retain in the dossier';
      final district = squad.site!.district;
      final hidden = district.sites.firstWhere((site) => site != squad.site)
        ..hidden = true
        ..name = 'Undiscovered headquarters';
      final startDate = game.date;
      final startOrder = squad.activity;
      var completed = false;
      final flow = planSiteVisit();
      unawaited(flow.then((_) => completed = true));
      addTearDown(() async {
        for (var i = 0; i < 8 && !completed; i++) {
          if (engine.console.awaitingInput) engine.console.sendInput('Enter');
          await tester.pump();
        }
        expect(completed, isTrue);
      });
      await mountBoard(
        tester,
        engine.console,
        const Size(1280, 720),
        (key) => engine.console.sendInput(key),
        viewportHeight: 500,
      );
      final revision = engine.console.revision.value;
      final viewport = tester.getRect(
        find.byKey(const ValueKey('city-viewport')),
      );
      final streets = tester.getRect(
        find.byKey(const ValueKey('city-planning-board')),
      );
      expect(viewport.height, 500);
      expect(streets.bottom, lessThanOrEqualTo(viewport.bottom));
      expect(
        find.byKey(const ValueKey('city-building-inspector')),
        findsNothing,
      );
      expect(streets.width, viewport.width);
      final cancel = engine.console.actions.singleWhere(
        (action) => action.key == 'Enter',
      );
      expect(
        tester.getRect(control(cancel)).bottom,
        lessThanOrEqualTo(viewport.bottom),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('city-squad-context'))).height,
        56,
      );
      for (final action in engine.console.actions.where(
        (action) => action.entityType == 'district',
      )) {
        expect(
          tester.getRect(building(action)).bottom,
          lessThanOrEqualTo(streets.bottom),
        );
        expect(
          tester.getRect(building(action)).top,
          greaterThanOrEqualTo(streets.top),
        );
      }
      await click(tester, find.byKey(const ValueKey('city-squad-details')));
      expect(find.byType(AlertDialog), findsNothing);
      expect(
        find.byKey(const ValueKey('city-squad-inspector')),
        findsOneWidget,
      );
      expect(find.textContaining('Weapon:'), findsWidgets);
      expect(engine.console.revision.value, revision);
      expect(squad.activity, same(startOrder));
      await click(tester, find.byKey(const ValueKey('city-squad-close')));
      expect(find.byType(CrewPortrait), findsNWidgets(squad.members.length));
      await click(
        tester,
        find.byKey(ValueKey('city-crew-dossier:${founder.id}')),
      );
      expect(find.byType(CrewInspector), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(engine.console.revision.value, revision);
      expect(squad.activity, same(startOrder));
      expect(game.date, startDate);
      await click(tester, find.byKey(const ValueKey('city-zoom-in')));
      expect(find.byType(CrewInspector), findsOneWidget);
      await click(tester, find.byKey(const ValueKey('crew-inspector-close')));
      expect(find.byType(CrewInspector), findsNothing);
      expect(engine.console.revision.value, revision);
      final districtAction = engine.console.actions.singleWhere(
        (action) =>
            action.entityType == 'district' &&
            action.entityId == district.idString,
      );
      await click(tester, building(districtAction));
      expect(completed, isFalse);
      expect(squad.activity, same(startOrder));
      expect(game.date, startDate);
      expect(order(districtAction), findsNothing);
      expect(find.text('Undiscovered headquarters'), findsNothing);
      expect(hidden.hidden, isTrue);
      final sourceDestinations = engine.console.actions.where(
        (action) => action.entityType == 'site',
      );
      expect(
        tester
            .widget<CityScene>(find.byType(CityScene))
            .buildings
            .map((e) => e.id),
        sourceDestinations.map((a) => a.entityId),
      );
      final destination = squad.site!;
      final siteAction = sourceDestinations.firstWhere(
        (action) => action.enabled && action.entityId == destination.idString,
      );
      await click(tester, building(siteAction));
      expect(completed, isFalse);
      expect(squad.activity, same(startOrder));
      expect(game.date, startDate);
      expect(find.text('Queue squad visit'), findsOneWidget);
      final inspector = tester.getRect(
        find.byKey(const ValueKey('city-building-inspector')),
      );
      final map = tester.getRect(
        find.byKey(const ValueKey('city-planning-board')),
      );
      expect(inspector.top, map.top);
      expect(inspector.right, lessThanOrEqualTo(viewport.right));
      expect(
        tester.getRect(order(siteAction)).bottom,
        lessThanOrEqualTo(viewport.bottom),
      );
      await click(tester, order(siteAction));
      expect(completed, isTrue);
      expect(squad.activity.type, ActivityType.visit);
      expect(squad.activity.idString, destination.idString);
      expect(game.date, startDate);
      expect(hidden.hidden, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'duplicate crew names open distinct actual dossiers by source person ID',
    (tester) async {
      engine.console = Console();
      game.gameState = decodeSaveContents(saveContents).gameState!;
      game.mode = GameMode.base;
      game.activeSquadMember = null;
      final squad = game.activeSquad!;
      final people = squad.members.take(2).toList();
      for (final person in people) {
        person.name = 'Same code name';
      }
      expect(people[0].id, isNot(people[1].id));
      expect(people[0].blood, isNot(people[1].blood));
      final date = game.date;
      final funds = game.ledger.funds;
      final activity = squad.activity;
      var completed = false;
      final flow = planSiteVisit();
      unawaited(flow.then((_) => completed = true));
      addTearDown(() async {
        for (var i = 0; i < 8 && !completed; i++) {
          if (engine.console.awaitingInput) engine.console.sendInput('Enter');
          await tester.pump();
        }
        expect(completed, isTrue);
      });
      final received = <String>[];
      await mountBoard(tester, engine.console, const Size(1280, 720), (key) {
        received.add(key);
        engine.console.sendInput(key);
      }, viewportHeight: 500);
      final revision = engine.console.revision.value;
      for (final person in people) {
        await click(
          tester,
          find.byKey(ValueKey('city-crew-dossier:${person.id}')),
        );
        final dossier = tester.widget<CrewInspector>(
          find.byType(CrewInspector),
        );
        expect(dossier.person, same(person));
        expect(dossier.person.blood, person.blood);
        expect(received, isEmpty);
        expect(engine.console.revision.value, revision);
        expect(engine.console.awaitingInput, isTrue);
        expect(completed, isFalse);
        expect(game.date, date);
        expect(game.ledger.funds, funds);
        expect(squad.activity, same(activity));
        await click(tester, find.byKey(const ValueKey('crew-inspector-close')));
        expect(find.byType(CrewInspector), findsNothing);
      }
      expect(received, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an untyped matching name exposes no actual person dossier', (
    tester,
  ) async {
    game.gameState = decodeSaveContents(saveContents).gameState!;
    final founder = game.activeSquad!.members.first;
    founder.name = 'Bernie Spitzer';
    final console = planningFixture();
    expect(console.actions.first.entityType, isNull);
    final received = <String>[];
    await mountBoard(
      tester,
      console,
      const Size(1280, 720),
      received.add,
      viewportHeight: 500,
    );
    expect(find.text('Bernie Spitzer'), findsOneWidget);
    expect(find.byType(CrewPortrait), findsNothing);
    expect(
      find.byKey(ValueKey('city-crew-dossier:${founder.id}')),
      findsNothing,
    );
    await click(tester, find.text('Bernie Spitzer'));
    expect(find.byType(CrewDossier), findsNothing);
    expect(received, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'generated animation advances frames and reduced motion freezes them',
    (tester) async {
      const buildings = [
        CitySceneBuilding(
          id: 'one',
          name: 'Warehouse',
          spriteIndex: 3,
          enabled: true,
        ),
      ];
      Future<void> mount(bool reduced) async {
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(disableAnimations: reduced),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: CityScene(buildings: buildings, onInspect: (_) {}),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
      }

      Iterable<int> walkFrames() => tester
          .widgetList<AtlasSprite>(find.byType(AtlasSprite))
          .where((sprite) => sprite.fallbackIndex < 0)
          .map((sprite) => sprite.frame);
      await mount(false);
      expect(walkFrames(), [0, 0]);
      await tester.pump(const Duration(milliseconds: 181));
      expect(walkFrames(), [1, 1]);
      await tester.pump(const Duration(milliseconds: 181));
      expect(walkFrames(), [2, 2]);
      await mount(true);
      final frozen = walkFrames().toList();
      await tester.pump(const Duration(seconds: 2));
      expect(walkFrames(), frozen);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('offstage scene freezes animation and resumes when visible', (
    tester,
  ) async {
    Future<void> mount({required bool offstage, bool tickers = true}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(),
            child: Scaffold(
              body: TickerMode(
                enabled: tickers,
                child: Offstage(
                  offstage: offstage,
                  // A visible inner wrapper must not mask the hidden outer wrapper.
                  child: Offstage(
                    offstage: false,
                    child: SingleChildScrollView(
                      child: CityScene(
                        buildings: const [
                          CitySceneBuilding(
                            id: 'one',
                            name: 'Warehouse',
                            spriteIndex: 3,
                            enabled: true,
                          ),
                        ],
                        onInspect: (_) {},
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    Iterable<int> frames() => tester
        .widgetList<AtlasSprite>(find.byType(AtlasSprite, skipOffstage: false))
        .where((sprite) => sprite.fallbackIndex < 0)
        .map((sprite) => sprite.frame);

    await mount(offstage: true);
    expect(frames(), [0, 0]);
    await tester.pump(const Duration(milliseconds: 260));
    expect(frames(), [0, 0]);
    await mount(offstage: false);
    await tester.pump(const Duration(milliseconds: 126));
    expect(frames(), [1, 1]);
    await mount(offstage: true);
    await tester.pump(const Duration(milliseconds: 260));
    expect(frames(), [1, 1]);
    await mount(offstage: false);
    await tester.pump(const Duration(milliseconds: 260));
    expect(frames(), [3, 3]);
    await mount(offstage: false, tickers: false);
    await tester.pump(const Duration(milliseconds: 260));
    expect(frames(), [3, 3]);
    await mount(offstage: false);
    await tester.pump(const Duration(milliseconds: 126));
    expect(frames(), [4, 4]);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
}
