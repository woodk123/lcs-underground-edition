import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/basemode/base_actions.dart';
import 'package:lcs_new_age/basemode/base_mode.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/campaign_fixture.dart';
import 'support/headquarters_test_harness.dart';

class _Harness extends HeadquartersTestHarness {
  @override
  Future<void> dispatch(int key) async {
    switch (key) {
      case engine.Key.o:
        await orderparty();
      case engine.Key.s:
        await updateTheSlogan();
      default:
        await super.dispatch(key);
    }
  }
}

Finder key(String value) => find.byKey(ValueKey(value));

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 35; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String value) async {
  expect(key(value).hitTestable(), findsOneWidget, reason: value);
  await tester.tap(key(value));
  await settle(tester);
}

Future<void> sourceKey(WidgetTester tester, LogicalKeyboardKey value) async {
  final focus = tester
      .widgetList<Focus>(find.byType(Focus))
      .singleWhere((widget) => widget.focusNode?.debugLabel == 'Game keyboard')
      .focusNode!;
  focus.requestFocus();
  await tester.pump();
  await tester.sendKeyEvent(value);
  await settle(tester);
}

void main() {
  late CampaignFixture fixture;
  _Harness? harness;
  setUpAll(() async {
    fixture = await CampaignFixture.load('test/saves/felix_1_0.json');
    final font = FontLoader('JournalSerif')
      ..addFont(rootBundle.load('fonts/journal/LibreBaskerville-Variable.ttf'));
    await font.load();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    journalReadingScale.value = 1;
    fixture.restoreHeadquarters(console: Console());
    for (final squad in game.squads) {
      squad.activity = Activity.none();
    }
    for (final person in game.pool) {
      person.activity = Activity.none();
    }
  });
  tearDown(() => journalReadingScale.value = 1);

  Future<void> mount(WidgetTester tester, Size size, double scale) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    journalReadingScale.value = scale;
    harness = _Harness();
    addTearDown(() async {
      harness!.stopped = true;
      for (var i = 0; i < 60 && !harness!.finished; i++) {
        if (engine.console.awaitingInput) {
          engine.console.sendInput(
            engine.console.textInput ? 'Enter' : 'Escape',
          );
        }
        await tester.pump(const Duration(milliseconds: 5));
      }
      expect(harness!.finished, isTrue);
    });
    await tester.pumpWidget(
      const RepaintBoundary(
        key: ValueKey('command-access-capture'),
        child: MainApp(),
      ),
    );
    await settle(tester);
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final out = Platform.environment['LCS_COMMAND_ACCESS_CAPTURES'];
    if (out == null) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      key('command-access-capture'),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(out).create(recursive: true);
      await File('$out/$name.png').writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
    });
  }

  for (final (size, scale) in [
    (const Size(1440, 1000), 1.0),
    (const Size(1024, 720), 1.5),
  ]) {
    final variant = '${size.width.toInt()}-$scale';
    testWidgets(
      'direct squad reorder cancels, revisits and swaps at $variant',
      (tester) async {
        await mount(tester, size, scale);
        final before = campaignSnapshot();
        reseedRNG(seed: 7051);
        final nextRoll = lcsRandom(100000);
        reseedRNG(seed: 7051);
        await capture(tester, '$variant-roster');
        final stale = tester
            .widget<TextButton>(key('journal-reorder-squad'))
            .onPressed!;
        await tap(tester, 'journal-reorder-squad');
        expect(harness!.dispatched.last, engine.Key.o);
        expect(engine.console.screen, 'squad_choice');
        expect(campaignSnapshot(), before);
        expect(lcsRandom(100000), nextRoll);
        stale();
        await settle(tester);
        expect(
          harness!.dispatched.where((value) => value == engine.Key.o),
          hasLength(1),
        );
        await sourceKey(tester, LogicalKeyboardKey.escape);
        expect(campaignSnapshot(), before);
        await tap(tester, 'journal-reorder-squad');
        await sourceKey(tester, LogicalKeyboardKey.digit1);
        await capture(tester, '$variant-reorder-target');
        await sourceKey(tester, LogicalKeyboardKey.escape);
        expect(campaignSnapshot(), before);
        final ids = game.squad.map((p) => p.id).toList();
        await tap(tester, 'journal-reorder-squad');
        await sourceKey(tester, LogicalKeyboardKey.digit1);
        await sourceKey(tester, LogicalKeyboardKey.digit2);
        expect(game.squad[0].id, ids[1]);
        expect(game.squad[1].id, ids[0]);
        await sourceKey(tester, LogicalKeyboardKey.escape);
        expect(engine.console.screen, 'headquarters');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'People bulk orders retain search and change only chosen crew at $variant',
      (tester) async {
        await mount(tester, size, scale);
        await tap(tester, 'journal-section:9');
        await capture(tester, '$variant-people-return');
        expect(engine.console.screen, 'personnel-directory');
        await tester.enterText(key('personnel-search'), game.pool.first.name);
        await settle(tester);
        final before = campaignSnapshot();
        final day = game.date;
        await capture(tester, '$variant-people');
        await tap(tester, 'journal-bulk-orders');
        expect(
          engine.console.actions.any(
            (a) => a.entityType == 'bulk-activity-selected',
          ),
          isTrue,
        );
        expect(campaignSnapshot(), before);
        final firstPerson = engine.console.actions.firstWhere(
          (a) => a.entityType == 'person',
        );
        expect(
          tester.getRect(key('journal-bulk-orders-view')).width,
          greaterThan(size.width * .8),
        );
        expect(key('bulk-task:1').hitTestable(), findsOneWidget);
        expect(
          key('bulk-person:${firstPerson.entityId}').hitTestable(),
          findsOneWidget,
        );
        final pendingRevision = engine.console.revision.value;
        final retainedPerson = tester
            .widget<OutlinedButton>(key('bulk-person:${firstPerson.entityId}'))
            .onPressed!;
        await tap(tester, 'bulk-orders-details');
        await sourceKey(tester, LogicalKeyboardKey.keyA);
        await sourceKey(tester, LogicalKeyboardKey.digit8);
        retainedPerson();
        await settle(tester);
        expect(campaignSnapshot(), before);
        expect(engine.console.revision.value, pendingRevision);
        await tap(tester, 'journal-order-details-close');
        await capture(tester, '$variant-bulk-crew');
        await sourceKey(tester, LogicalKeyboardKey.escape);
        await sourceKey(tester, LogicalKeyboardKey.escape);
        await tap(tester, 'journal-section:9');
        expect(
          tester.widget<TextField>(key('personnel-search')).controller!.text,
          game.pool.first.name,
        );
        await tap(tester, 'journal-bulk-orders');
        await sourceKey(tester, LogicalKeyboardKey.digit8);
        final personAction = engine.console.actions.firstWhere(
          (a) => a.entityType == 'person',
        );
        final person = game.pool.singleWhere(
          (p) => p.id.toString() == personAction.entityId,
        );
        final original = person.activity;
        person.activity = Activity(ActivityType.stealCars);
        final expected = campaignSnapshot();
        person.activity = original;
        engine.console.sendInput(personAction.key);
        await settle(tester);
        expect(campaignSnapshot(), expected);
        expect(game.date, day);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Network bulk picker stays visible and changes only selected sleeper at $variant',
      (tester) async {
        final sleeper = addTestCrewMember(name: 'Prepared sleeper')
          ..sleeperAgent = true;
        await mount(tester, size, scale);
        await tap(tester, 'journal-section:8');
        final before = campaignSnapshot();
        await capture(tester, '$variant-network');
        await tap(tester, 'network-bulk-orders');
        expect(
          engine.console.actions.any(
            (a) => a.entityType == 'sleeper-bulk-selected',
          ),
          isTrue,
        );
        expect(
          find.textContaining('Activate Sleeper Agents in Bulk'),
          findsWidgets,
        );
        expect(campaignSnapshot(), before);
        await capture(tester, '$variant-bulk-sleepers');
        await sourceKey(tester, LogicalKeyboardKey.escape);
        await sourceKey(tester, LogicalKeyboardKey.escape);
        await tap(tester, 'journal-section:8');
        await tap(tester, 'network-bulk-orders');
        await sourceKey(tester, LogicalKeyboardKey.digit2);
        final personAction = engine.console.actions.singleWhere(
          (a) => a.entityId == sleeper.id.toString(),
        );
        final original = sleeper.activity;
        sleeper.activity = Activity(ActivityType.sleeperLiberal);
        final expected = campaignSnapshot();
        sleeper.activity = original;
        engine.console.sendInput(personAction.key);
        await settle(tester);
        expect(campaignSnapshot(), expected);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('a prepared personal order blocks direct reorder callbacks', (
    tester,
  ) async {
    await mount(tester, const Size(1440, 1000), 1);
    final retained = tester
        .widget<TextButton>(key('journal-reorder-squad'))
        .onPressed!;
    await tap(tester, 'journal-orders');
    await tap(tester, 'journal-order-group:0');
    await tap(tester, 'journal-activity:donations');
    final before = campaignSnapshot();
    expect(key('journal-reorder-squad'), findsNothing);
    retained();
    await settle(tester);
    expect(harness!.dispatched.contains(engine.Key.o), isFalse);
    expect(campaignSnapshot(), before);
    expect(key('journal-confirm-order'), findsOneWidget);
  });

  testWidgets('bulk crew orders use the source unavailable capability', (
    tester,
  ) async {
    for (final person in game.pool) {
      person.hidingDaysLeft = 1;
    }
    await mount(tester, const Size(1440, 1000), 1);
    await tap(tester, 'journal-section:9');
    expect(
      tester.widget<OutlinedButton>(key('journal-bulk-orders')).onPressed,
      isNull,
    );
    expect(harness!.dispatched.contains(engine.Key.a), isFalse);
  });

  testWidgets(
    'bulk pages preserve source eligibility and reject old person callbacks',
    (tester) async {
      for (var i = 0; i < 20; i++) {
        addTestCrewMember(name: 'Prepared crew $i');
      }
      await mount(tester, const Size(1440, 1000), 1);
      await tap(tester, 'journal-section:9');
      await tap(tester, 'journal-bulk-orders');
      final before = campaignSnapshot();
      final first = engine.console.actions.firstWhere(
        (a) => a.entityType == 'person',
      );
      final retained = tester
          .widget<OutlinedButton>(key('bulk-person:${first.entityId}'))
          .onPressed!;
      final next = engine.console.actions.firstWhere(
        (a) => a.key == ']' || a.key == '.' || a.key == 'PageDown',
      );
      await tap(tester, 'bulk-page:${next.key}');
      expect(
        engine.console.actions
            .where((a) => a.entityType == 'person')
            .map((a) => a.entityId),
        isNot(contains(first.entityId)),
      );
      retained();
      await settle(tester);
      expect(campaignSnapshot(), before);
      await sourceKey(tester, LogicalKeyboardKey.digit7);
      for (final action in engine.console.actions.where(
        (a) => a.entityType == 'person',
      )) {
        expect(
          action.enabled,
          isFalse,
          reason: 'The prepared homeless crew have no Hacker Den.',
        );
        final target = key('bulk-person:${action.entityId}');
        if (target.evaluate().isNotEmpty) {
          expect(tester.widget<OutlinedButton>(target).onPressed, isNull);
        }
      }
      expect(campaignSnapshot(), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Options exposes the original slogan editor', (tester) async {
    await mount(tester, const Size(1024, 720), 1.5);
    await tester.ensureVisible(key('journal-section:7'));
    await settle(tester);
    await tap(tester, 'journal-section:7');
    await tester.ensureVisible(key('journal-change-slogan'));
    await settle(tester);
    await tap(tester, 'journal-change-slogan');
    expect(harness!.dispatched.last, engine.Key.s);
    expect(engine.console.textInput, isTrue);
    await sourceKey(tester, LogicalKeyboardKey.enter);
    expect(game.slogan, isNotEmpty);
    expect(tester.takeException(), isNull);
  });
}
