import 'dart:async';
import 'dart:convert';
import 'dart:ui' show SemanticsAction, SemanticsRole, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/engine/organisation_context.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/gamestate/squad.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/movement_daily_plan.dart';
import 'package:lcs_new_age/modern/organisation_journal.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'support/campaign_fixture.dart';
import 'support/headquarters_test_harness.dart';

Finder _key(String value) => find.byKey(ValueKey(value));

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 35; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String value) async {
  expect(
    _key(value).hitTestable(),
    findsOneWidget,
    reason: '$value must be reachable.',
  );
  await tester.tap(_key(value));
  await _settle(tester);
}

Future<void> _focusGame(WidgetTester tester) async {
  final focus = tester
      .widgetList<Focus>(find.byType(Focus))
      .singleWhere((widget) => widget.focusNode?.debugLabel == 'Game keyboard')
      .focusNode!;
  focus.requestFocus();
  await tester.pump();
}

class _Harness extends HeadquartersTestHarness {
  Future<void> stopWidgets(WidgetTester tester) async {
    stopped = true;
    for (var i = 0; i < 50 && !finished; i++) {
      if (engine.console.awaitingInput) {
        engine.console.sendInput(engine.console.textInput ? 'Enter' : 'Escape');
      }
      await tester.pump(const Duration(milliseconds: 5));
    }
    expect(finished, true, reason: 'Actual source readers must close.');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CampaignFixture fixture;
  setUpAll(() async {
    fixture = await CampaignFixture.load('test/saves/felix_1_0.json');
    final serif = FontLoader('JournalSerif')
      ..addFont(rootBundle.load('fonts/journal/LibreBaskerville-Variable.ttf'))
      ..addFont(
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
    fixture.restoreHeadquarters(console: Console());
    journalReadingScale.value = 1;
    for (final person in game.squad) {
      person.activity = Activity(ActivityType.sellArt);
    }
  });

  Future<_Harness> mount(WidgetTester tester, {bool large = false}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = large
        ? const Size(1024, 720)
        : const Size(1280, 800);
    journalReadingScale.value = large ? 1.5 : 1;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    final harness = _Harness();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await harness.stopWidgets(tester);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
    });
    await tester.pumpWidget(const MainApp());
    await _settle(tester);
    expect(find.byType(OrganisationJournal), findsOneWidget);
    return harness;
  }

  Future<void> select(WidgetTester tester, Creature person) async {
    await tester.enterText(_key('daily-plan-search'), person.name);
    await _settle(tester);
    await _tap(tester, 'daily-plan-person:${person.id}');
  }

  for (final large in [false, true]) {
    testWidgets(
      'movement modal retains inspection and reader state, large=$large',
      (tester) async {
        final extra = List.generate(
          22,
          (i) => addTestCrewMember(name: 'Daily crew $i'),
        );
        final actor = extra[18]..activity = Activity.none();
        final harness = await mount(tester, large: large);
        final source = engine.console;
        final before = campaignSnapshot();
        final revision = source.revision.value;
        final actions = List.of(source.actions);
        final pending = source.nextKeyEvent;
        final organisation = tester.widget<OrganisationJournal>(
          find.byType(OrganisationJournal),
        );
        final selectedBefore = organisation.controller.selectedPersonId;
        final sourceActorBefore = game.activeSquadMember;
        reseedRNG(seed: 90482);
        final rolls = List.generate(12, (_) => lcsRandom(100000));
        reseedRNG(seed: 90482);
        await _focusGame(tester);
        final previousFocus = FocusManager.instance.primaryFocus;
        await _tap(tester, 'journal-daily-plan');
        final semantics = tester.ensureSemantics();
        try {
          await tester.pump();
          expect(find.bySemanticsLabel('Close daily plan'), findsOneWidget);
          expect(find.bySemanticsLabel('Search daily plan'), findsOneWidget);
          for (final filter in DailyPlanFilter.values) {
            expect(
              _key('daily-plan-filter:${filter.name}').hitTestable(),
              findsOneWidget,
            );
          }
          final listRect = tester.getRect(_key('daily-plan-list'));
          expect(
            listRect.height,
            greaterThanOrEqualTo(150),
            reason: 'Sticky controls must leave useful reading space at150%.',
          );
          final closeRect = tester.getRect(_key('daily-plan-close'));
          expect(
            closeRect.bottom,
            lessThanOrEqualTo(tester.view.physicalSize.height),
          );
          Future<void> keyboardSelect(
            Creature person,
            LogicalKeyboardKey key,
          ) async {
            await tester.enterText(_key('daily-plan-search'), person.name);
            await _settle(tester);
            final named = find.bySemanticsLabel(
              'Select daily plan for ${person.name}',
            );
            expect(named, findsOneWidget);
            final data = tester.getSemantics(named).getSemanticsData();
            expect(data.flagsCollection.isButton, true);
            expect(
              data.flagsCollection.isFocused,
              isNot(Tristate.none),
              reason:
                  'The named button must retain native focusable semantics.',
            );
            expect(data.flagsCollection.isSelected, Tristate.isFalse);
            expect(data.hasAction(SemanticsAction.tap), true);
            for (
              var step = 0;
              step < 12 &&
                  tester
                          .getSemantics(named)
                          .getSemanticsData()
                          .flagsCollection
                          .isFocused !=
                      Tristate.isTrue;
              step++
            ) {
              await tester.sendKeyEvent(LogicalKeyboardKey.tab);
              await _settle(tester);
            }
            expect(
              tester
                  .getSemantics(named)
                  .getSemanticsData()
                  .flagsCollection
                  .isFocused,
              Tristate.isTrue,
              reason: 'Tab must reach the same named selection button.',
            );
            await tester.sendKeyEvent(
              key,
              character: key == LogicalKeyboardKey.space ? ' ' : null,
            );
            await _settle(tester);
            expect(find.text('Selected: ${person.name}'), findsOneWidget);
            expect(
              tester
                  .getSemantics(named)
                  .getSemanticsData()
                  .flagsCollection
                  .isSelected,
              Tristate.isTrue,
            );
            expect(campaignSnapshot(), before);
            expect(source.revision.value, revision);
            expect(source.actions, actions);
            expect(identical(source.nextKeyEvent, pending), true);
            expect(organisation.controller.selectedPersonId, selectedBefore);
            expect(game.activeSquadMember, same(sourceActorBefore));
            expect(harness.dispatched, isEmpty);
          }

          await keyboardSelect(extra[19], LogicalKeyboardKey.enter);
          await keyboardSelect(actor, LogicalKeyboardKey.space);
          expect(
            find.bySemanticsLabel('Orders for ${actor.name}'),
            findsOneWidget,
          );
          expect(
            find.bySemanticsLabel('Profile for ${actor.name}'),
            findsOneWidget,
          );
          await _tap(tester, 'daily-plan-details:${actor.id}');
          expect(find.text('Personal order: Laying Low'), findsOneWidget);
          expect(
            find.bySemanticsLabel('Hide daily plan details for ${actor.name}'),
            findsOneWidget,
          );
          await _tap(tester, 'daily-plan-filter:needsOrder');
          int independentLabel(Finder finder, String label) {
            final node = tester.getSemantics(finder);
            expect(node.getSemanticsData().label, label);
            expect(node.getSemanticsData().role, isNot(SemanticsRole.dialog));
            var dialog = node.parent;
            while (dialog != null &&
                dialog.getSemanticsData().role != SemanticsRole.dialog) {
              dialog = dialog.parent;
            }
            expect(
              dialog,
              isNotNull,
              reason: '$label must remain a child label inside the dialog.',
            );
            return node.id;
          }

          final title = find.text('Daily plan');
          final date = find.textContaining('Living crew and sleeper agents');
          const guidance =
              'Available active crew currently Laying Low. Leaving this order in place can be intentional.';
          final labels = {
            independentLabel(title, 'Daily plan'),
            independentLabel(date, tester.widget<Text>(date).data!),
            independentLabel(find.text(guidance), guidance),
            independentLabel(
              _key('daily-plan-selected'),
              'Selected: ${actor.name}',
            ),
          };
          expect(
            labels,
            hasLength(4),
            reason: 'Static header, date, guidance and selection must have independent semantics nodes.',
          );
          expect(
            tester
                .getSemantics(title)
                .getSemanticsData()
                .flagsCollection
                .namesRoute,
            true,
          );
          await _tap(tester, 'daily-plan-close');
          await _tap(tester, 'journal-daily-plan');
          expect(
            tester
                .widget<TextField>(_key('daily-plan-search'))
                .controller!
                .text,
            actor.name,
          );
          expect(
            tester
                .widget<ChoiceChip>(_key('daily-plan-filter:needsOrder'))
                .selected,
            true,
          );
          expect(find.text('Selected: ${actor.name}'), findsOneWidget);
          expect(find.text('Personal order: Laying Low'), findsOneWidget);
          final orders = _key('daily-plan-orders:${actor.id}');
          expect(orders.hitTestable(), findsOneWidget);
          expect(
            tester.getRect(orders).bottom,
            lessThanOrEqualTo(tester.view.physicalSize.height),
          );
          // Text entry containing source command letters belongs to the search.
          await tester.enterText(_key('daily-plan-search'), 'wpd');
          for (final (key, character) in [
            (LogicalKeyboardKey.keyW, 'w'),
            (LogicalKeyboardKey.keyP, 'p'),
            (LogicalKeyboardKey.keyD, 'd'),
          ]) {
            await tester.sendKeyEvent(key, character: character);
            await _focusGame(tester);
            await tester.sendKeyEvent(key, character: character);
            await _settle(tester);
          }
          expect(campaignSnapshot(), before);
          expect(source.revision.value, revision);
          expect(source.actions, actions);
          expect(identical(source.nextKeyEvent, pending), true);
          expect(organisation.controller.selectedPersonId, selectedBefore);
          expect(game.activeSquadMember, same(sourceActorBefore));
          expect(harness.dispatched, isEmpty);
          // The forced background focus above is an adversarial probe. Return
          // to the modal's normal focus scope before its Escape dismissal.
          await tester.tap(_key('daily-plan-search'));
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await _settle(tester);
          expect(_key('daily-plan-board'), findsNothing);
          expect(previousFocus?.hasPrimaryFocus, true);
          expect(List.generate(12, (_) => lcsRandom(100000)), rolls);
          // Closing the modal leaves the original single W command available.
          await tester.sendKeyEvent(LogicalKeyboardKey.keyW, character: 'w');
          await _settle(tester);
          expect(harness.dispatched, [engine.Key.w]);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  for (final large in [false, true]) {
    for (final focus in ['initial', 'tab', 'background']) {
      final initialFocus = focus == 'initial';
      final backgroundFocus = focus == 'background';
      testWidgets(
        '${initialFocus
            ? 'Immediate Close focus'
            : backgroundFocus
            ? 'Game keyboard beneath Daily plan'
            : 'Tab to Close'} then Escape preserves the active draft, large=$large',
        (tester) async {
          final semantics = tester.ensureSemantics();
          try {
            final harness = await mount(tester, large: large);
            await _tap(tester, 'journal-orders');
            await _tap(tester, 'journal-activity:donations');
            final journal = tester.state<OrganisationJournalState>(
              find.byType(OrganisationJournal),
            );
            expect(journal.hasPreparedOrder, true);
            final source = engine.console;
            final before = campaignSnapshot();
            final revision = source.revision.value;
            final actions = List.of(source.actions);
            final pending = source.nextKeyEvent;
            final dispatched = List.of(harness.dispatched);
            reseedRNG(seed: 94312);
            final rolls = List.generate(12, (_) => lcsRandom(100000));
            reseedRNG(seed: 94312);
            await _focusGame(tester);
            final previousFocus = FocusManager.instance.primaryFocus;
            await _tap(tester, 'journal-daily-plan');
            if (!initialFocus) {
              await tester.enterText(_key('daily-plan-search'), 'wpd');
              await _settle(tester);
              await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
              try {
                await tester.sendKeyEvent(LogicalKeyboardKey.tab);
              } finally {
                await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
              }
              await _settle(tester);
            }
            final close = find.bySemanticsLabel('Close daily plan');
            expect(close, findsOneWidget);
            expect(
              tester
                  .getSemantics(close)
                  .getSemanticsData()
                  .flagsCollection
                  .isFocused,
              Tristate.isTrue,
              reason: 'The real Close button must own keyboard focus.',
            );
            if (backgroundFocus) {
              await _focusGame(tester);
              expect(
                FocusManager.instance.primaryFocus,
                same(previousFocus),
                reason: 'The adversarial key must reach the real Game keyboard focus beneath the modal.',
              );
            }
            if (!initialFocus) {
              for (final (key, character) in [
                (LogicalKeyboardKey.keyW, 'w'),
                (LogicalKeyboardKey.keyP, 'p'),
                (LogicalKeyboardKey.keyD, 'd'),
              ]) {
                await tester.sendKeyEvent(key, character: character);
                await _settle(tester);
              }
            }
            expect(
              tester
                  .widget<TextField>(_key('daily-plan-search'))
                  .controller!
                  .text,
              initialFocus ? '' : 'wpd',
            );
            if (backgroundFocus) {
              expect(FocusManager.instance.primaryFocus, same(previousFocus));
            } else {
              expect(
                tester
                    .getSemantics(close)
                    .getSemanticsData()
                    .flagsCollection
                    .isFocused,
                Tristate.isTrue,
              );
            }
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await _settle(tester);
            expect(_key('daily-plan-board'), findsNothing);
            expect(previousFocus?.hasPrimaryFocus, true);
            expect(journal.hasPreparedOrder, true);
            expect(_key('journal-confirm-order').hitTestable(), findsOneWidget);
            expect(campaignSnapshot(), before);
            expect(source.revision.value, revision);
            expect(source.actions, actions);
            expect(identical(source.nextKeyEvent, pending), true);
            expect(harness.dispatched, dispatched);
            expect(List.generate(12, (_) => lcsRandom(100000)), rolls);
            await _tap(tester, 'journal-cancel-order');
            expect(campaignSnapshot(), before);
            expect(tester.takeException(), isNull);
          } finally {
            semantics.dispose();
          }
        },
      );
    }
  }

  testWidgets(
    'deep scroll clamps after filtering and its current position survives revisit',
    (tester) async {
      List.generate(
        30,
        (i) =>
            addTestCrewMember(name: 'Scroll crew $i')
              ..activity = Activity.none(),
      );
      await mount(tester, large: true);
      await _tap(tester, 'journal-daily-plan');
      final list = tester.widget<ListView>(_key('daily-plan-list')).controller!;
      list.jumpTo(list.position.maxScrollExtent);
      await _settle(tester);
      final deepOffset = list.offset;
      expect(deepOffset, greaterThan(1000));
      await _tap(tester, 'daily-plan-close');
      await _tap(tester, 'journal-daily-plan');
      final restored = tester
          .widget<ListView>(_key('daily-plan-list'))
          .controller!;
      expect(restored.offset, closeTo(deepOffset, .1));
      await _tap(tester, 'daily-plan-filter:assigned');
      expect(
        restored.offset,
        inInclusiveRange(0, restored.position.maxScrollExtent),
      );
      expect(restored.offset, lessThan(deepOffset));
      expect(
        _key('daily-plan-person:${game.squad.last.id}').hitTestable(),
        findsOneWidget,
      );
      await tester.enterText(
        _key('daily-plan-search'),
        'No matching name anywhere',
      );
      await _settle(tester);
      expect(
        restored.offset,
        inInclusiveRange(0, restored.position.maxScrollExtent),
      );
      expect(
        find.text('No people match this view.').hitTestable(),
        findsOneWidget,
      );
      final clamped = restored.offset;
      await _tap(tester, 'daily-plan-close');
      await _tap(tester, 'journal-daily-plan');
      expect(
        tester.widget<ListView>(_key('daily-plan-list')).controller!.offset,
        closeTo(clamped, .1),
      );
      expect(
        find.text('No people match this view.').hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Orders routes unsquadded actor through original Cancel and actor-only Confirm',
    (tester) async {
      final actor = addTestCrewMember(name: 'Independent planner')
        ..activity = Activity.none();
      final queued = Squad()..name = 'Queued companions';
      game.squads.add(queued);
      final companion = addTestCrewMember(name: 'Queued companion')
        ..squad = queued;
      queued.activity = Activity(
        ActivityType.visit,
        idString: game.sites.first.idString,
      );
      await mount(tester);
      final before = jsonDecode(campaignSnapshot()) as Map<String, dynamic>;
      await _tap(tester, 'journal-daily-plan');
      await select(tester, actor);
      await _tap(tester, 'daily-plan-orders:${actor.id}');
      expect(activityOrderFrame(engine.console)?.actorId, actor.id);
      await _tap(tester, 'journal-activity:donations');
      final source = engine.console;
      final revision = source.revision.value;
      final pending = source.nextKeyEvent;
      final draft = tester
          .widget<OrganisationJournal>(find.byType(OrganisationJournal))
          .controller;
      expect(
        tester
            .state<OrganisationJournalState>(find.byType(OrganisationJournal))
            .hasPreparedOrder,
        true,
      );
      await _tap(tester, 'journal-daily-plan');
      expect(
        tester
            .widget<OutlinedButton>(_key('daily-plan-orders:${actor.id}'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(_key('daily-plan-profile:${actor.id}'))
            .onPressed,
        isNull,
      );
      expect(
        find.textContaining('Finish or cancel the current draft'),
        findsOneWidget,
      );
      await _tap(tester, 'daily-plan-close');
      expect(source.revision.value, revision);
      expect(identical(source.nextKeyEvent, pending), true);
      expect(
        tester
            .state<OrganisationJournalState>(find.byType(OrganisationJournal))
            .hasPreparedOrder,
        true,
      );
      await _tap(tester, 'journal-cancel-order');
      expect(jsonDecode(campaignSnapshot()), before);
      await _tap(tester, 'journal-daily-plan');
      await _tap(tester, 'daily-plan-orders:${actor.id}');
      expect(activityOrderFrame(engine.console)?.actorId, actor.id);
      await _tap(tester, 'journal-activity:donations');
      await _tap(tester, 'journal-confirm-order');
      expect(actor.activity.type, ActivityType.donations);
      expect(companion.squad, same(queued));
      expect(queued.activity.type, ActivityType.visit);
      final after = jsonDecode(campaignSnapshot()) as Map<String, dynamic>;
      final oldPool = (before['lcs'] as Map<String, dynamic>)['pool'] as List;
      final newPool = (after['lcs'] as Map<String, dynamic>)['pool'] as List;
      final index = game.pool.indexOf(actor);
      (oldPool[index] as Map)['activity'] = (newPool[index] as Map)['activity'];
      expect(after, before);
      expect(draft.selectedPersonId, actor.id);
      expect(tester.takeException(), isNull);
    },
  );

  for (final stale in ['revision', 'campaign', 'availability']) {
    testWidgets('captured row cannot route after changed $stale', (
      tester,
    ) async {
      final actor = game.squad.first;
      final harness = await mount(tester);
      await _tap(tester, 'journal-daily-plan');
      await select(tester, actor);
      final retained = tester
          .widget<OutlinedButton>(_key('daily-plan-orders:${actor.id}'))
          .onPressed!;
      switch (stale) {
        case 'revision':
          engine.console.revision.value++;
        case 'campaign':
          final id = game.gameState.uniqueGameId;
          fixture.restoreState();
          game.gameState.uniqueGameId = id + 1;
        case 'availability':
          actor.location = game.sites.firstWhere(
            (site) => site.type == SiteType.universityHospital,
          );
      }
      final before = campaignSnapshot();
      final revision = engine.console.revision.value;
      final pending = engine.console.nextKeyEvent;
      retained();
      await _settle(tester);
      expect(_key('daily-plan-board'), findsNothing);
      expect(activityOrderFrame(engine.console), isNull);
      expect(campaignSnapshot(), before);
      expect(engine.console.revision.value, revision);
      expect(identical(engine.console.nextKeyEvent, pending), true);
      expect(harness.dispatched, isEmpty);
      // Calling that old callback again must not close a fresh modal.
      await _tap(tester, 'journal-daily-plan');
      retained();
      await _settle(tester);
      expect(_key('daily-plan-board'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'queued crew remain inspectable and View squad preserves the departure',
    (tester) async {
      final team = game.activeSquad!;
      final actor = team.members.last;
      team.activity = Activity(
        ActivityType.visit,
        idString: game.sites.first.idString,
      );
      await mount(tester, large: true);
      final before = campaignSnapshot();
      await _tap(tester, 'journal-daily-plan');
      await select(tester, actor);
      expect(
        tester
            .widget<OutlinedButton>(_key('daily-plan-orders:${actor.id}'))
            .onPressed,
        isNull,
      );
      expect(find.textContaining('joint operation queued'), findsOneWidget);
      await _tap(tester, 'daily-plan-squad:${actor.id}');
      expect(
        tester
            .widget<OrganisationJournal>(find.byType(OrganisationJournal))
            .controller
            .selectedPersonId,
        actor.id,
      );
      expect(campaignSnapshot(), before);
      await _tap(tester, 'journal-daily-plan');
      await _tap(tester, 'daily-plan-profile:${actor.id}');
      expect(engine.console.journalProfile?.person.id, actor.id);
      expect(campaignSnapshot(), before);
      expect(team.activity.type, ActivityType.visit);
      await _focusGame(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _settle(tester);
      expect(engine.console.journalProfile, isNull);
      expect(engine.console.screen, 'personnel-directory');
      final organisation = tester.widget<OrganisationJournal>(
        find.byType(OrganisationJournal),
      );
      bool? returned;
      unawaited(
        organisation.controller.returnToHeadquarters().then(
          (value) => returned = value,
        ),
      );
      await _settle(tester);
      expect(returned, true);
      await _tap(tester, 'journal-daily-plan');
      expect(
        tester.widget<TextField>(_key('daily-plan-search')).controller!.text,
        actor.name,
      );
      expect(find.text('Selected: ${actor.name}'), findsOneWidget);
      expect(campaignSnapshot(), before);
      expect(tester.takeException(), isNull);
    },
  );
}
