import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activate_regulars.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/basemode/base_mode.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/engine/organisation_context.dart';
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/modern/journal_city_plan.dart';
import 'package:lcs_new_age/modern/journal_preferences.dart';
import 'package:lcs_new_age/modern/journal_shortcuts.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/organisation_journal.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

/// Real headquarters and task readers; no days or outcomes are simulated.
class _OrdersReader {
  _OrdersReader() {
    unawaited(_run());
  }

  bool stopped = false, finished = false;
  final commands = <int>[];

  Future<void> _run() async {
    try {
      while (!stopped) {
        engine.erase();
        final site = game.activeSquad?.site ?? game.activeSafehouse;
        baseModeSquadSafehouseDisplay(site);
        baseModeOptionsDisplay(site);
        final key = await engine.getKey();
        if (stopped) break;
        commands.add(key);
        if (key == engine.Key.a) await activateRegulars();
      }
    } finally {
      finished = true;
    }
  }

  Future<void> stop(WidgetTester tester) async {
    stopped = true;
    for (var step = 0; step < 60 && !finished; step++) {
      if (engine.console.awaitingInput) {
        engine.console.sendInput('Escape');
      }
      await tester.pump(const Duration(milliseconds: 5));
    }
    expect(finished, isTrue);
  }
}

Finder _key(String key) => find.byKey(ValueKey(key));
String _snapshot() => jsonEncode(game.gameState.toJson());

Future<void> _settle(WidgetTester tester) async {
  for (var step = 0; step < 35; step++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  await tester.pumpAndSettle();
}

Future<void> _gameKey(
  WidgetTester tester,
  LogicalKeyboardKey key, [
  String? character,
]) async {
  final focus = tester
      .widgetList<Focus>(find.byType(Focus))
      .singleWhere((widget) => widget.focusNode?.debugLabel == 'Game keyboard')
      .focusNode!;
  focus.requestFocus();
  await tester.pump();
  await tester.sendKeyEvent(key, character: character);
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String fixture;

  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
    final serif = FontLoader('JournalSerif')
      ..addFont(rootBundle.load('fonts/journal/LibreBaskerville-Variable.ttf'));
    final sans = FontLoader('ModernSans');
    for (final weight in ['regular', 'medium', 'bold', 'black']) {
      sans.addFont(rootBundle.load('fonts/modern/roboto-$weight.ttf'));
    }
    await Future.wait([serif.load(), sans.load()]);
  });

  setUp(() {
    journalReadingScale.value = 1;
    journalPresentation.value = const JournalPreferenceValues();
    engine.console = Console();
    game.gameState = decodeSaveContents(fixture).gameState!;
    game.mode = GameMode.base;
    game.activeSquadMember = null;
    for (final person in game.squad) {
      person.activity = Activity(ActivityType.sellArt);
    }
  });

  Future<_OrdersReader> mount(
    WidgetTester tester,
    Size size, {
    double readingScale = 1,
    bool compact = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    journalReadingScale.value = readingScale;
    journalPresentation.value = JournalPreferenceValues(
      compact: compact,
      showGuidance: !compact,
    );
    final reader = _OrdersReader();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await reader.stop(tester);
      journalReadingScale.value = 1;
      journalPresentation.value = const JournalPreferenceValues();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
    });
    await tester.pumpWidget(const MainApp());
    await _settle(tester);
    return reader;
  }

  for (final layout in [
    (const Size(1280, 800), 1.0, false),
    (const Size(800, 600), 1.5, true),
    (const Size(720, 600), 1.5, true),
  ]) {
    testWidgets(
      'keyboard assignment keeps concise choices and cancellation at ${layout.$1}',
      (tester) async {
        final reader = await mount(
          tester,
          layout.$1,
          readingScale: layout.$2,
          compact: layout.$3,
        );
        final actor = game.squad.first;
        final before = _snapshot();
        reseedRNG(seed: 20261020);
        final expectedRolls = List.generate(8, (_) => lcsRandom(100000));
        reseedRNG(seed: 20261020);

        // Same source route as Classic: A opens assignments, A picks actor,
        // B opens legal fundraising, 1 chooses donations.
        await _gameKey(tester, LogicalKeyboardKey.keyA, 'a');
        await _gameKey(tester, LogicalKeyboardKey.keyA, 'a');
        await _gameKey(tester, LogicalKeyboardKey.keyB, 'b');
        expect(activityOrderFrame(engine.console)?.actorId, actor.id);
        expect(activityOrderFrame(engine.console)?.selectedCategoryKey, 'b');
        expect(find.byType(OrganisationJournal), findsOneWidget);
        if (layout.$3) {
          final name = _key('journal-member-name:${actor.id}');
          final renderedName = tester.renderObject<RenderParagraph>(
            find.descendant(of: name, matching: find.byType(RichText)),
          );
          expect(
            renderedName.didExceedMaxLines,
            isFalse,
            reason: 'Enlarged compact roster names must remain readable.',
          );
          for (final rail in [
            'journal-reports',
            'journal-orders',
            'journal-order-group:0',
            'journal-order-group:1',
            'journal-order-group:2',
            'journal-order-group:3',
          ]) {
            final renderedLabel = tester.renderObject<RenderParagraph>(
              find.descendant(of: _key(rail), matching: find.byType(RichText)),
            );
            expect(
              renderedLabel.didExceedMaxLines,
              isFalse,
              reason: '$rail must show its complete label.',
            );
          }
        }
        expect(_key('journal-order-map'), findsNothing);
        final choice = _key('journal-activity:donations');
        expect(choice.hitTestable(), findsOneWidget);
        final workspaceWidth = tester
            .getSize(_key('journal-order-workspace'))
            .width;
        expect(tester.getSize(choice).width, greaterThan(workspaceWidth * .9));
        final source = engine.console.actions.singleWhere(
          (action) => action.entityId == ActivityType.donations.name,
        );
        expect(
          find.descendant(
            of: choice,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is JournalShortcutBadge &&
                  widget.shortcut == source.key,
            ),
          ),
          findsOneWidget,
        );

        final revision = engine.console.revision.value;
        await _gameKey(tester, LogicalKeyboardKey.digit1, '1');
        expect(_key('journal-confirm-order').hitTestable(), findsOneWidget);
        expect(_key('journal-assigned-order'), findsOneWidget);
        expect(_snapshot(), before);
        expect(engine.console.revision.value, revision);
        await _gameKey(tester, LogicalKeyboardKey.escape);
        expect(_key('journal-confirm-order'), findsNothing);
        expect(_snapshot(), before);
        expect(activityOrderFrame(engine.console)?.selectedCategoryKey, 'b');

        await _gameKey(tester, LogicalKeyboardKey.digit1, '1');
        await _gameKey(tester, LogicalKeyboardKey.enter);
        expect(actor.activity.type, ActivityType.donations);
        expect(
          game.squad
              .skip(1)
              .every((person) => person.activity.type == ActivityType.sellArt),
          isTrue,
        );
        expect(activityOrderFrame(engine.console)?.actorId, actor.id);
        expect(activityOrderFrame(engine.console)?.selectedCategoryKey, 'b');
        expect(reader.commands, isNot(contains(engine.Key.w)));
        expect(List.generate(8, (_) => lcsRandom(100000)), expectedRolls);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('optional map returns to the same task list without game input', (
    tester,
  ) async {
    await mount(tester, const Size(1280, 800));
    await _gameKey(tester, LogicalKeyboardKey.keyA, 'a');
    await _gameKey(tester, LogicalKeyboardKey.keyA, 'a');
    await _gameKey(tester, LogicalKeyboardKey.keyB, 'b');
    final before = _snapshot();
    final revision = engine.console.revision.value;
    final list = find.byKey(const PageStorageKey('journal-tasks:0:legal'));
    final listState = tester.state(
      find.descendant(of: list, matching: find.byType(Scrollable)),
    );
    await tester.tap(_key('journal-orders-map-toggle'));
    await _settle(tester);
    expect(_key('journal-order-map'), findsOneWidget);
    expect(_key('journal-activity:donations'), findsNothing);
    final mapState = tester.state(find.byType(JournalCityPlan));
    await tester.tap(find.byTooltip('Show location index'));
    await _settle(tester);
    expect(find.byTooltip('Show city plan'), findsOneWidget);
    journalReadingScale.value = 1.5;
    tester.view.physicalSize = const Size(800, 600);
    await _settle(tester);
    expect(tester.state(find.byType(JournalCityPlan)), same(mapState));
    expect(
      _key('journal-location-index'),
      findsOneWidget,
      reason: 'The same index must survive reading and viewport changes.',
    );
    expect(find.byTooltip('Show city plan'), findsOneWidget);
    await tester.tap(_key('journal-orders-map-toggle'));
    await _settle(tester);
    expect(_key('journal-order-map'), findsNothing);
    expect(
      tester.state(
        find.descendant(of: list, matching: find.byType(Scrollable)),
      ),
      same(listState),
    );
    expect(_snapshot(), before);
    expect(engine.console.revision.value, revision);
    expect(tester.takeException(), isNull);
  });
}
