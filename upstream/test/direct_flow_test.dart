import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activate_regulars.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/basemode/plan_site_visit.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/modern/city_planning_view.dart';
import 'package:lcs_new_age/modern/direct_content.dart';
import 'package:lcs_new_age/saveload/save_load.dart';

import 'test_support.dart';

class DirectEngineFlow {
  DirectEngineFlow(Future<void> future) {
    unawaited(
      future.then(
        (_) => done = true,
        onError: (Object error) {
          failure = error;
          done = true;
        },
      ),
    );
  }
  bool done = false;
  Object? failure;
}

Finder directAction(ConsoleAction action) =>
    find.byKey(ValueKey('direct-action:${action.y}:${action.x}:${action.key}'));

ConsoleAction actionContaining(String text, {int? minY}) =>
    engine.console.actions.singleWhere(
      (action) =>
          action.label.contains(text) && (minY == null || action.y >= minY),
    );

Future<void> mountDirectFlow(
  WidgetTester tester,
  Size size,
  DirectEngineFlow flow,
) async {
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() async {
    for (var i = 0; i < 10 && !flow.done; i++) {
      if (engine.console.awaitingInput) engine.console.sendInput('Enter');
      await tester.pump();
    }
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
  });
  await tester.pumpWidget(const MainApp());
  await tester.pumpAndSettle();
}

Future<void> inspectAndOrder(WidgetTester tester, ConsoleAction action) async {
  final revision = engine.console.revision.value;
  final date = game.date;
  final activity = game.activeSquad!.activity;
  final building = find.byKey(ValueKey('city-building:${action.entityId}'));
  expect(building, findsOneWidget);
  await tester.ensureVisible(building);
  await tester.tap(building);
  await tester.pumpAndSettle();
  expect(game.date, date);
  expect(game.activeSquad!.activity, same(activity));
  final order = find.byKey(ValueKey('city-order:${action.entityId}'));
  if (action.entityType == 'district' || action.entityType == 'city') {
    // Navigation redraws the source list after a single activation, while
    // leaving simulation time and the existing squad order untouched.
    expect(engine.console.revision.value, greaterThan(revision));
    expect(order, findsNothing);
    return;
  }
  expect(engine.console.revision.value, revision);
  expect(order, findsOneWidget);
  await tester.ensureVisible(order);
  await tester.tap(order);
  await tester.pumpAndSettle();
}

Future<void> clickDirect(WidgetTester tester, ConsoleAction action) async {
  final finder = directAction(action);
  expect(
    finder,
    findsOneWidget,
    reason: 'Missing central control ${action.label}',
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void expectCentralContent(
  WidgetTester tester,
  ConsoleAction action,
  Size size,
) {
  final finder = directAction(action);
  expect(
    find.ancestor(
      of: finder,
      matching: find.byWidgetPredicate(
        (widget) => widget is DirectContent || widget is CityPlanningView,
      ),
    ),
    findsOneWidget,
  );
  final bounds = tester.getRect(finder);
  expect(bounds.center.dx, greaterThan(size.width * .2));
  expect(bounds.center.dx, lessThan(size.width * .9));
  expect(
    find.text('AVAILABLE CHOICES'),
    findsNothing,
    reason: 'The management center must not duplicate choices in a sidebar.',
  );
  expect(
    find.byType(SelectableText),
    findsNothing,
    reason: 'Management content must render as modern controls.',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await ensureGameDataLoaded();
    final modern = FontLoader('ModernSans');
    for (final weight in ['regular', 'medium', 'bold', 'black']) {
      modern.addFont(rootBundle.load('fonts/modern/roboto-$weight.ttf'));
    }
    final original = FontLoader('SourceCodePro')
      ..addFont(rootBundle.load('fonts/SourceCodePro-Regular.ttf'));
    await Future.wait([modern.load(), original.load()]);
  });
  setUp(() async {
    engine.console = Console();
    final save = decodeSaveContents(
      await File('test/saves/felix_1_0.json').readAsString(),
    );
    game.gameState = save.gameState!;
    game.mode = GameMode.base;
    game.activeSquadMember = null;
  });

  for (final size in [const Size(1280, 800), const Size(800, 600)]) {
    final viewport = '${size.width.toInt()}x${size.height.toInt()}';
    testWidgets(
      'central roster assigns and confirms donations through original engine at $viewport',
      (tester) async {
        final founder = game.pool.first;
        final startDate = game.date;
        final flow = DirectEngineFlow(activateRegulars());
        await mountDirectFlow(tester, size, flow);
        final row = actionContaining(founder.name);
        expectCentralContent(tester, row, size);
        expect(tester.getRect(directAction(row)).width, greaterThan(300));
        await clickDirect(tester, row);
        final legal = actionContaining('Legal Fundraising');
        expectCentralContent(tester, legal, size);
        await clickDirect(tester, legal);
        // Choosing a category supplies a default. Change that default through
        // the real UI so the donations click must actually update the task.
        await clickDirect(tester, actionContaining('Make and Sell Art'));
        expect(founder.activity.type, ActivityType.sellArt);
        final donations = actionContaining('Solicit Donations');
        expect(donations.key, '1');
        await clickDirect(tester, donations);
        expect(founder.activity.type, ActivityType.donations);
        final confirm = actionContaining('Confirm Selection');
        expect(confirm.key, 'Enter');
        await clickDirect(tester, confirm);
        expect(actionContaining(founder.name).key, row.key);
        expect(founder.activity.type, ActivityType.donations);
        expect(
          game.date,
          startDate,
          reason: 'Planning a task must not advance time.',
        );
        engine.console.sendInput('Enter');
        await tester.pump();
        expect(flow.done, isTrue);
        expect(flow.failure, isNull);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'central operation controls choose a real district and queue a real site at $viewport',
      (tester) async {
        final startDate = game.date;
        final location = game.activeSquad!.site!;
        final district = location.district;
        final destination = district.sites.firstWhere(
          (site) =>
              site != location &&
              !site.hidden &&
              !site.isClosed &&
              !site.siege.underSiege &&
              site.area == location.area,
        );
        final flow = DirectEngineFlow(planSiteVisit());
        await mountDirectFlow(tester, size, flow);
        final travel = actionContaining('Travel to a Different City');
        expect(travel.enabled, isFalse);
        final originalRevision = engine.console.revision.value;
        await clickDirect(tester, travel);
        expect(
          engine.console.revision.value,
          originalRevision,
          reason: 'A disabled destination must not send a gameplay choice.',
        );
        expect(game.activeSquad!.activity.type, ActivityType.none);
        final districtChoice = actionContaining(district.getName(), minY: 10);
        await inspectAndOrder(tester, districtChoice);
        final siteChoice = actionContaining(destination.getName(), minY: 10);
        expect(siteChoice.enabled, isTrue);
        await inspectAndOrder(tester, siteChoice);
        expect(flow.done, isTrue);
        expect(flow.failure, isNull);
        expect(game.activeSquad!.activity.type, ActivityType.visit);
        expect(game.activeSquad!.activity.idString, destination.idString);
        expect(
          game.date,
          startDate,
          reason: 'Operations stay queued until End Day.',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
