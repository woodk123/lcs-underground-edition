import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activate_regulars.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/basemode/plan_site_visit.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/saveload/save_load.dart';

import 'test_support.dart';

void headquarters() {
  engine.erase();
  engine.console.screen = 'headquarters';
  engine.addOptionText(22, 0, 'm', 'M - Media Overview & Impact');
}

Future<void> mount(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
  });
  await tester.pumpWidget(const MainApp());
  await tester.pumpAndSettle();
}

Future<void> finishRouting(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String fixture;
  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
  });
  setUp(() {
    game.gameState = decodeSaveContents(fixture).gameState!;
    game.mode = GameMode.base;
    game.activeSquadMember = null;
    engine.console = Console();
  });

  for (final width in [1280.0, 800.0]) {
    testWidgets(
      'one section click leaves nested original assignments at $width',
      (tester) async {
        final before = jsonEncode(game.gameState.toJson());
        int? received;
        final flow = () async {
          await activateRegulars();
          headquarters();
          received = await engine.getKey();
        }();
        await mount(tester, Size(width, 720));
        final person = engine.console.actions.firstWhere(
          (action) => action.entityType == 'person' && action.enabled,
        );
        await tester.tap(
          find.byKey(
            ValueKey('direct-action:${person.y}:${person.x}:${person.key}'),
          ),
        );
        await tester.pumpAndSettle();
        expect(engine.console.navigation?.section, 'assignments');
        expect(
          find.text('Continue'),
          findsNothing,
          reason: 'Activity Done must not be duplicated by a generic footer.',
        );
        await tester.tap(find.byKey(const ValueKey('section:5')));
        await finishRouting(tester);
        await flow;
        expect(received, 'm'.codeUnitAt(0));
        expect(jsonEncode(game.gameState.toJson()), before);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'one section click preserves actual queued Operations destination',
    (tester) async {
      final target = game.activeSquad!.site!;
      final queued = Activity(ActivityType.visit, idString: target.idString);
      game.activeSquad!.activity = queued;
      final before = jsonEncode(game.gameState.toJson());
      int? received;
      final flow = () async {
        await planSiteVisit();
        headquarters();
        received = await engine.getKey();
      }();
      await mount(tester, const Size(1280, 720));
      expect(
        engine.console.navigation?.backKey,
        String.fromCharCode(engine.Key.menuExit),
      );
      await tester.tap(find.byKey(const ValueKey('section:5')));
      await finishRouting(tester);
      await flow;
      expect(received, 'm'.codeUnitAt(0));
      expect(game.activeSquad!.activity, same(queued));
      expect(jsonEncode(game.gameState.toJson()), before);
      expect(tester.takeException(), isNull);
    },
  );

  for (final tactical in [false, true]) {
    testWidgets('section switching cannot dismiss an unaudited '
        '${tactical ? 'tactical' : 'management'} choice', (tester) async {
      if (tactical) game.mode = GameMode.site;
      engine.mvaddstr(0, 0, 'Choose a squad member');
      engine.addOptionText(3, 0, 'a', 'A - A specific choice');
      int? received;
      final input = engine.getKey().then((value) => received = value);
      await mount(tester, const Size(1280, 720));
      expect(find.byKey(const ValueKey('section:5')), findsNothing);
      await finishRouting(tester);
      expect(received, isNull);
      engine.console.sendInput('Escape');
      await tester.pump();
      await input;
      expect(received, engine.Key.escape);
    });
  }

  testWidgets(
    'task header keeps Done visible and original facts expand in place',
    (tester) async {
      final person = game.pool.first;
      final flow = assignTask(person);
      await mount(tester, const Size(1280, 720));
      final before = jsonEncode(game.gameState.toJson());
      final revision = engine.console.revision.value;
      final done = find.text('Done');
      expect(done.hitTestable(), findsOneWidget);
      expect(tester.getRect(done).bottom, lessThan(280));
      expect(find.textContaining('Str:'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('assignment-person-details')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Str:'), findsWidgets);
      expect(jsonEncode(game.gameState.toJson()), before);
      expect(engine.console.revision.value, revision);
      expect(engine.console.awaitingInput, isTrue);
      await tester.tap(done);
      await tester.pumpAndSettle();
      await flow;
      expect(jsonEncode(game.gameState.toJson()), before);
      expect(tester.takeException(), isNull);
    },
  );
}
