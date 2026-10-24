import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/basemode/base_actions.dart';
import 'package:lcs_new_age/basemode/base_mode.dart';
import 'package:lcs_new_age/basemode/liberal_agenda.dart';
import 'package:lcs_new_age/common_actions/equipment.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/daily/shopsnstuff.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/engine/ledger_context.dart';
import 'package:lcs_new_age/engine/media_context.dart';
import 'package:lcs_new_age/engine/organisation_context.dart';
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/gamestate/ledger.dart';
import 'package:lcs_new_age/gamestate/squad.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/siege.dart';
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/modern/article_view.dart';
import 'package:lcs_new_age/modern/crew_dossier.dart';
import 'package:lcs_new_age/modern/injury_status.dart';
import 'package:lcs_new_age/modern/journal_city_plan.dart';
import 'package:lcs_new_age/modern/journal_ledger.dart';
import 'package:lcs_new_age/modern/journal_media.dart';
import 'package:lcs_new_age/modern/journal_navigation_shortcuts.dart';
import 'package:lcs_new_age/modern/journal_preferences.dart';
import 'package:lcs_new_age/modern/journal_shortcuts.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/mechanics_help.dart';
import 'package:lcs_new_age/modern/organisation_crew_pool.dart';
import 'package:lcs_new_age/modern/organisation_journal.dart';
import 'package:lcs_new_age/modern/personnel_directory.dart';
import 'package:lcs_new_age/modern/skill_help.dart';
import 'package:lcs_new_age/monthly/lcs_monthly.dart';
import 'package:lcs_new_age/newspaper/news_story.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'support/campaign_fixture.dart';
import 'support/headquarters_test_harness.dart';

/// The base dispatch boundary with real source-authored options and real
/// management handlers. It never advances time during these UI tests.
class _StopHeadquarters implements Exception {}

class _HeadquartersConsole extends Console {
  bool stopped = false;

  @override
  Future<String> getkey() async {
    final key = await super.getkey();
    if (stopped) throw _StopHeadquarters();
    return key;
  }
}

class _JournalHarness extends HeadquartersTestHarness {
  _JournalHarness({
    this.monthlyReport = false,
    this.shopVisit = false,
    this.realHeadquarters = false,
  }) : super(reader: realHeadquarters ? _runHeadquarters : null);

  final bool realHeadquarters;
  final bool monthlyReport;
  final bool shopVisit;
  bool monthReset = false;

  static Future<void> _runHeadquarters() async {
    try {
      await baseMode();
    } on _StopHeadquarters {
      return;
    }
  }

  @override
  Future<void> dispatch(int key) async {
    switch (key) {
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
      case engine.Key.l:
        await liberalAgenda();
      case engine.Key.w:
        if (shopVisit) {
          final team = game.activeSquad!;
          final destination = team.activity.location!;
          // This is the original day boundary before a service visit:
          // its squad order becomes each traveller's activity, then the
          // actual department-store reader relocates and receives input.
          for (final person in team.members) {
            person.activity = team.activity;
          }
          await deptstore(destination);
          team.activity = Activity.none();
          for (final person in team.members) {
            person.location = person.base;
            person.activity = Activity.none();
          }
        }
        if (monthlyReport) {
          await fundReport(false);
          game.ledger.resetMonthlyAmounts();
          monthReset = true;
        }
      default:
        await super.dispatch(key);
    }
  }

  Future<void> stopWidgets(WidgetTester tester) async {
    stopped = true;
    if (realHeadquarters) {
      (engine.console as _HeadquartersConsole).stopped = true;
    }
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

Creature _extraPerson(String name) => addTestCrewMember(name: name);

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

Future<void> _openPersonnel(WidgetTester tester, int personId) async {
  final list = find
      .descendant(
        of: _key('personnel-directory'),
        matching: find.byType(Scrollable),
      )
      .first;
  tester.state<ScrollableState>(list).position.jumpTo(0);
  await _settle(tester);
  await tester.scrollUntilVisible(
    _key('personnel-person:$personId'),
    100,
    scrollable: list,
  );
  await _settle(tester);
  await _tap(tester, 'personnel-person:$personId');
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

Future<void> _altShortcut(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool focusGame = true,
}) async {
  if (focusGame) await _focusGame(tester);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
  try {
    await tester.sendKeyEvent(key);
  } finally {
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
  }
  await _settle(tester);
}

Future<void> _showCrewMember(WidgetTester tester, int id) async {
  final target = _key('journal-member:$id');
  final scroll = find.descendant(
    of: _key('journal-crew-list'),
    matching: find.byType(Scrollable),
  );
  tester.state<ScrollableState>(scroll).position.jumpTo(0);
  await _settle(tester);
  await tester.scrollUntilVisible(target, 30, scrollable: scroll);
  await _settle(tester);
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
  late CampaignFixture fixture;
  setUpAll(() async {
    fixture = await CampaignFixture.load('test/saves/felix_1_0.json');
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
    fixture.restoreHeadquarters(console: _HeadquartersConsole());
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
    bool shopVisit = false,
    bool realHeadquarters = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    final harness = _JournalHarness(
      monthlyReport: monthlyReport,
      shopVisit: shopVisit,
      realHeadquarters: realHeadquarters,
    );
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

  Future<void> business(WidgetTester tester) async {
    await _tap(tester, 'journal-orders');
    await _tap(tester, 'journal-order-group:0');
    expect(activityOrderFrame(engine.console)?.selectedCategoryKey, 'b');
  }

  for (final large in [false, true]) {
    testWidgets('squad number keys follow the real HQ reader, large=$large', (
      tester,
    ) async {
      journalReadingScale.value = large ? 1.5 : 1;
      await mount(
        tester,
        realHeadquarters: true,
        size: large ? const Size(1024, 720) : const Size(1280, 800),
      );
      final before = campaignSnapshot();
      reseedRNG(seed: 62401);
      final rolls = List.generate(12, (_) => lcsRandom(100000));
      reseedRNG(seed: 62401);
      Future<void> press(LogicalKeyboardKey key, String character) async {
        await _focusGame(tester);
        await tester.sendKeyEvent(key, character: character);
        await _settle(tester);
      }

      final keys = [
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
        LogicalKeyboardKey.digit5,
        LogicalKeyboardKey.digit6,
      ];
      for (var i = 0; i < keys.length; i++) {
        await press(keys[i], '${i + 1}');
        expect(game.activeSquadMember, same(game.squad[i]));
        expect(
          tester.widget<Text>(_key('journal-selected-person')).data,
          game.squad[i].name,
        );
        await _showCrewMember(tester, game.squad[i].id);
        expect(_key('journal-shortcut:${i + 1}'), findsWidgets);
      }
      // Pointer inspection and repainting do not silently restore the last key choice.
      await _showCrewMember(tester, game.squad[1].id);
      await _tap(tester, 'journal-member:${game.squad[1].id}');
      engine.console.revision.value++;
      await _settle(tester);
      expect(
        tester.widget<Text>(_key('journal-selected-person')).data,
        game.squad[1].name,
      );
      await press(LogicalKeyboardKey.digit3, '3');
      expect(
        tester.widget<Text>(_key('journal-selected-person')).data,
        game.squad[2].name,
      );
      // The selected key opens the original profile; Escape returns to HQ.
      await press(LogicalKeyboardKey.digit3, '3');
      expect(engine.console.journalProfile?.person.id, game.squad[2].id);
      await press(LogicalKeyboardKey.escape, 'Escape');
      expect(engine.console.screen, 'headquarters');
      await press(LogicalKeyboardKey.digit0, '0');
      expect(game.activeSquadMember, isNull);
      expect(
        tester.widget<Text>(_key('journal-selected-person')).data,
        game.squad.first.name,
      );
      await press(LogicalKeyboardKey.digit9, '9');
      expect(game.activeSquadMember, isNull);
      // Read-only dossiers retain their keyboard boundary.
      await _showCrewMember(tester, game.squad.first.id);
      await _tap(tester, 'hq-dossier:${game.squad.first.id}');
      final revision = engine.console.revision.value;
      await press(LogicalKeyboardKey.digit2, '2');
      expect(engine.console.revision.value, revision);
      expect(game.activeSquadMember, isNull);
      await press(LogicalKeyboardKey.escape, 'Escape');
      await press(LogicalKeyboardKey.digit2, '2');
      expect(game.activeSquadMember, same(game.squad[1]));
      expect(campaignSnapshot(), before);
      expect(List.generate(12, (_) => lcsRandom(100000)), rolls);
      expect(tester.takeException(), isNull);
    });
  }

  for (final large in [false, true]) {
    testWidgets(
      'selected header and visible skills follow original HQ actor keys, large=$large',
      (tester) async {
        final first = game.squad.first;
        final second = game.squad[1];
        // Prepared display differences; no training, injury or earnings are earned.
        for (final actor in [first, second]) {
          for (final skill in Skill.values) {
            actor.rawSkill[skill] = 0;
          }
        }
        first.rawSkill[Skill.art] = 12;
        first.rawSkill[Skill.music] = 2;
        first.rawSkillXP[Skill.art] = 25;
        first.juice = 120;
        second.rawSkill[Skill.art] = 2;
        second.rawSkill[Skill.music] = 10;
        second.rawSkillXP[Skill.art] = 75;
        second.juice = -3;
        second.blood = second.maxBlood ~/ 2;
        final previousPresentation = journalPresentation.value;
        journalReadingScale.value = large ? 1.5 : 1;
        journalPresentation.value = JournalPreferenceValues(
          compact: large,
          showGuidance: !large,
        );
        addTearDown(() {
          journalReadingScale.value = 1;
          journalPresentation.value = previousPresentation;
        });
        await mount(
          tester,
          realHeadquarters: true,
          size: large ? const Size(1024, 720) : const Size(1280, 720),
        );
        final before = campaignSnapshot();
        reseedRNG(seed: 40261);
        final rolls = List.generate(12, (_) => lcsRandom(100000));
        reseedRNG(seed: 40261);
        await _tap(tester, 'journal-skills');
        for (final selection in [
          (first, LogicalKeyboardKey.digit1, '1'),
          (second, LogicalKeyboardKey.digit2, '2'),
          (first, LogicalKeyboardKey.digit1, '1'),
        ]) {
          final actor = selection.$1;
          await _focusGame(tester);
          await tester.sendKeyEvent(selection.$2, character: selection.$3);
          await _settle(tester);
          expect(game.activeSquadMember, same(actor));
          expect(engine.console.screen, 'headquarters');
          expect(_key('journal-crew-list'), findsNothing);
          expect(find.text('${actor.name} · Skills'), findsOneWidget);
          expect(
            tester.widget<Text>(_key('journal-selected-person')).data,
            actor.name,
          );
          final portrait = _key('hq-portrait:${actor.id}');
          expect(portrait.hitTestable(), findsOneWidget);
          final status = find.text(
            'Juice ${actor.juice} · ${actor.blood}/${actor.maxBlood} blood',
          );
          expect(status, findsOneWidget);
          expect(
            tester.widget<Text>(status).style!.color,
            actor == second ? JournalPalette.danger : JournalPalette.ink,
          );
          expect(
            find.byTooltip(
              actor.location!.getName(short: true, includeCity: true),
            ),
            findsOneWidget,
          );
          final art = _key('journal-skill:art');
          final music = _key('journal-skill:music');
          for (final skill in [Skill.art, Skill.music]) {
            expect(
              find.descendant(
                of: _key('journal-skill:${skill.name}'),
                matching: find.text('${actor.skill(skill)}'),
              ),
              findsOneWidget,
            );
          }
          expect(
            tester.getTopLeft(art).dy < tester.getTopLeft(music).dy,
            actor == first,
            reason: 'The visible level ordering follows the selected actor.',
          );
          final revision = engine.console.revision.value;
          final navigation = engine.console.navigation;
          final actions = List<ConsoleAction>.of(engine.console.actions);
          void expectReaderUnchanged() {
            expect(engine.console.screen, 'headquarters');
            expect(engine.console.revision.value, revision);
            expect(engine.console.navigation, same(navigation));
            expect(engine.console.actions, actions);
            expect(engine.console.awaitingInput, isTrue);
            expect(engine.console.lastKey, isNull);
            expect(engine.console.textInput, isFalse);
            expect(campaignSnapshot(), before);
          }

          final hint = find.descendant(of: art, matching: find.byType(Tooltip));
          final help = skillHelp(Skill.art, actor: actor);
          expect(tester.widget<Tooltip>(hint).message, help);
          tester.state<TooltipState>(hint).ensureTooltipVisible();
          await tester.pump(const Duration(milliseconds: 650));
          expect(find.text(help), findsOneWidget);
          expectReaderUnchanged();
          Tooltip.dismissAllToolTips();
          await _settle(tester);
          await _tap(tester, 'journal-skills');
          await _tap(tester, 'journal-skills');
          expect(find.text('${actor.name} · Skills'), findsOneWidget);
          expectReaderUnchanged();
          await _tap(tester, 'hq-portrait:${actor.id}');
          expect(
            tester.widget<CrewInspector>(find.byType(CrewInspector)).person,
            same(actor),
          );
          expectReaderUnchanged();
          await _tap(tester, 'crew-inspector-close');
          expect(find.text('${actor.name} · Skills'), findsOneWidget);
          expectReaderUnchanged();
        }
        expect(List.generate(12, (_) => lcsRandom(100000)), rolls);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('previous visit job is a cancellable draft bound to its actor', (
    tester,
  ) async {
    await mount(tester);
    final journal = tester.widget<OrganisationJournal>(
      find.byType(OrganisationJournal),
    );
    final review = journal.controller.organisationReviews;
    final actor = game.squad.first;
    actor.activity = Activity(ActivityType.stealCars);
    game.activeSquad!.activity = Activity(
      ActivityType.visit,
      idString: actor.base!.idString,
    );
    await review.observe(game.gameState.uniqueGameId, game.pool, game.date);
    game.activeSquad!.activity = Activity.none();
    actor.activity = Activity.none();
    game.gameState.date = game.date.add(const Duration(days: 1));
    await review.observe(game.gameState.uniqueGameId, game.pool, game.date);
    expect(
      review.notices
          .where((n) => n.personId == actor.id)
          .single
          .previousActivity,
      ActivityType.stealCars,
    );
    // Republish the source HQ reader for the explicitly prepared next date.
    engine.console.sendInput('Enter');
    await _settle(tester);
    final button = _key('journal-previous-order:${actor.id}');
    expect(button, findsOneWidget);
    expect(button.hitTestable(), findsOneWidget);
    final retained = tester.widget<TextButton>(button).onPressed!;
    final before = campaignSnapshot();
    reseedRNG(seed: 23011);
    final roll = lcsRandom(100000);
    reseedRNG(seed: 23011);
    await tester.tap(button);
    await _settle(tester);
    expect(activityOrderFrame(engine.console)?.actorId, actor.id);
    expect(_key('journal-confirm-order'), findsOneWidget);
    expect(campaignSnapshot(), before);
    await _tap(tester, 'journal-cancel-order');
    expect(campaignSnapshot(), before);
    expect(lcsRandom(100000), roll);
    await _tap(tester, 'journal-finish-orders');
    expect(button.hitTestable(), findsOneWidget);
    await tester.tap(button);
    await _settle(tester);
    await _tap(tester, 'journal-confirm-order');
    expect(actor.activity.type, ActivityType.stealCars);
    for (final other in game.squad.where((p) => p != actor)) {
      expect(other.activity.type, ActivityType.sellArt);
    }
    final confirmed = campaignSnapshot();
    retained();
    await _settle(tester);
    expect(campaignSnapshot(), confirmed);
    expect(tester.takeException(), isNull);
  });

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

  for (final size in [const Size(2200, 1200), const Size(1024, 720)]) {
    testWidgets('Clipboard and equipment use journal pages at $size', (
      tester,
    ) async {
      await mount(tester, size: size);
      if (size.width == 1024) {
        await tester.tap(find.byTooltip('Reading size'));
        await _settle(tester);
        await tester.tap(find.text('150%'));
        await _settle(tester);
      }
      final before = campaignSnapshot();
      reseedRNG(seed: 26840);
      final rolls = List.generate(12, (_) => lcsRandom(100000));
      reseedRNG(seed: 26840);
      await _tap(tester, 'journal-clipboard');
      expect(_key('personnel-directory'), findsOneWidget);
      expect(
        find.text('Personnel directory'),
        findsOneWidget,
        reason: 'One page heading, without a nested fallback panel.',
      );
      expect(find.byType(PersonnelDirectory), findsOneWidget);
      final sourcePerson = engine.console.actions.firstWhere(
        (action) => action.entityType == 'person',
      );
      final personId = int.parse(sourcePerson.entityId!);
      await _openPersonnel(tester, personId);
      expect(engine.console.journalProfile?.person.id, personId);
      expect(_key('journal-personnel-profile'), findsOneWidget);
      expect(find.text('Profile of a Liberal'), findsNothing);
      expect(
        find.byKey(const PageStorageKey('journal-profile-order-mechanics')),
        findsOneWidget,
      );
      expect(find.byType(ActivityMechanicsPanel), findsNothing);
      for (final (label, index) in [
        ('Skills', 1),
        ('Campaign record', 2),
        ('Overview', 0),
      ]) {
        final tab = _key('journal-profile-tab:$index');
        expect(
          find.descendant(of: tab, matching: find.text(label)),
          findsOneWidget,
        );
        await tester.ensureVisible(tab);
        await _settle(tester);
        await tester.tap(tab);
        await _settle(tester);
        expect(engine.console.journalProfile?.page, index);
      }
      final close = _key('journal-profile-action:Enter');
      await tester.ensureVisible(close);
      await _settle(tester);
      await _tap(tester, 'journal-profile-action:Enter');
      expect(engine.console.journalProfile, isNull);
      expect(_key('personnel-directory'), findsOneWidget);
      expect(campaignSnapshot(), before);
      expect(List.generate(12, (_) => lcsRandom(100000)), rolls);
      await _tap(tester, 'journal-equipment');
      expect(
        tester.widget<Text>(_key('journal-management-heading')).data,
        'Equipment',
      );
      expect(find.text('Crew & choices'), findsNothing);
      expect(find.text('Equip the Squad'), findsNothing);
      final weaponAction = engine.console.actions.firstWhere(
        (a) => a.intentLabel == 'Unequip weapon',
      );
      final control = _key(
        'direct-action:${weaponAction.y}:${weaponAction.x}:${weaponAction.key}',
      );
      expect(
        find.descendant(of: control, matching: find.text('Unequip weapon')),
        findsOneWidget,
      );
      for (final key in ['Up', 'Down']) {
        final action = engine.console.actions.singleWhere((a) => a.key == key);
        expect(
          _key('direct-action:${action.y}:${action.x}:${action.key}'),
          findsOneWidget,
          reason: 'Keep both original ammo controls.',
        );
      }
      expect(find.textContaining('Cursors -'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'native Clipboard profiles retain rename and management confirmations',
    (tester) async {
      final person = game.squad[1];
      person.hireId = game.squad.first.id;
      person.location = game.squad.first.location;
      await mount(tester, size: const Size(1024, 720));
      await tester.tap(find.byTooltip('Reading size'));
      await _settle(tester);
      await tester.tap(find.text('150%'));
      await _settle(tester);
      final before = campaignSnapshot();
      await _tap(tester, 'journal-clipboard');
      await _openPersonnel(tester, person.id);
      for (final (key, prompt) in [
        ('r', 'permanently release'),
        ('k', 'kill this squad member?'),
      ]) {
        await _tap(tester, 'journal-profile-action:$key');
        expect(engine.console.journalProfile?.confirming, isTrue);
        expect(find.textContaining(prompt), findsOneWidget);
        final cancel = engine.console.actions.singleWhere(
          (a) => a.key == 'Enter',
        );
        await _tap(
          tester,
          'direct-action:${cancel.y}:${cancel.x}:${cancel.key}',
        );
        expect(engine.console.journalProfile?.confirming, isFalse);
        expect(campaignSnapshot(), before);
      }
      await _tap(tester, 'journal-profile-action:n');
      expect(engine.console.textInput, isTrue);
      await tester.enterText(find.byType(TextField), person.name);
      await tester.tap(find.text('Confirm text'));
      await _settle(tester);
      expect(engine.console.textInput, isFalse);
      expect(campaignSnapshot(), before);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(2200, 1200), const Size(1024, 720)]) {
    testWidgets(
      'left crew selection retains profile page and scroll at $size',
      (tester) async {
        final first = game.squad.first;
        final second = game.squad[1];
        final outfit = first.equippedClothing!;
        outfit.bloody = true;
        outfit.damaged = true;
        second.equippedClothing = null;
        first.body.parts.first.bleeding = 2;
        second.blood = second.maxBlood ~/ 2;
        await mount(tester, size: size);
        if (size.width == 1024) {
          await tester.tap(find.byTooltip('Reading size'));
          await _settle(tester);
          await tester.tap(find.text('150%'));
          await _settle(tester);
        }
        await _tap(tester, 'journal-clipboard');
        await _openPersonnel(tester, first.id);
        final before = campaignSnapshot();
        final dossier = tester.state(find.byType(CrewDossier));
        final scroller = find.descendant(
          of: _key('journal-personnel-profile'),
          matching: find.byType(Scrollable),
        );
        reseedRNG(seed: 94162);
        final rolls = List.generate(10, (_) => lcsRandom(100000));
        reseedRNG(seed: 94162);
        for (final page in [0, 1, 2]) {
          final tab = _key('journal-profile-tab:$page');
          await tester.ensureVisible(tab);
          await _settle(tester);
          await tester.tap(tab);
          await _settle(tester);
          final position = tester.state<ScrollableState>(scroller).position;
          final offset = position.maxScrollExtent.clamp(0, 90).toDouble();
          position.jumpTo(offset);
          await _settle(tester);
          final next = engine.console.journalProfile!.person.id == first.id
              ? second
              : first;
          await _showCrewMember(tester, next.id);
          final clothingLabel = next.id == first.id
              ? '${outfit.type.name} · Bloodstained · Damaged'
              : 'No equipped clothing';
          expect(
            tester
                .widget<Text>(_key('journal-member-clothing:${next.id}'))
                .data,
            clothingLabel,
          );
          expect(find.byTooltip('Wearing: $clothingLabel'), findsOneWidget);
          expect(_key('journal-member-injury:${next.id}'), findsOneWidget);
          expect(
            find.byTooltip(crewInjurySummary(next)!.details),
            findsOneWidget,
          );
          await _tap(tester, 'journal-member:${next.id}');
          expect(engine.console.journalProfile!.person.id, next.id);
          expect(engine.console.journalProfile!.page, page);
          expect(
            tester.widget<Text>(_key('journal-selected-person')).data,
            next.name,
          );
          expect(tester.state(find.byType(CrewDossier)), same(dossier));
          expect(
            tester.state<ScrollableState>(scroller).position.pixels,
            closeTo(
              offset.clamp(
                0,
                tester
                    .state<ScrollableState>(scroller)
                    .position
                    .maxScrollExtent,
              ),
              .01,
            ),
            reason:
                'Retain the offset up to the shorter profile’s scroll limit.',
          );
          final ids = engine.console.journalProfile!.personIds;
          final afterFooter = ids[(ids.indexOf(next.id) + 1) % ids.length];
          await _tap(tester, 'journal-profile-action:Right');
          expect(engine.console.journalProfile!.person.id, afterFooter);
          expect(
            tester.widget<Text>(_key('journal-selected-person')).data,
            game.pool.firstWhere((p) => p.id == afterFooter).name,
          );
          expect(engine.console.journalProfile!.page, page);
        }
        expect(campaignSnapshot(), before);
        expect(List.generate(10, (_) => lcsRandom(100000)), rolls);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'equipment follows left selection without dispatch or scroll reset at $size',
      (tester) async {
        await mount(tester, size: size);
        if (size.width == 1024) {
          await tester.tap(find.byTooltip('Reading size'));
          await _settle(tester);
          await tester.tap(find.text('150%'));
          await _settle(tester);
        }
        await business(tester);
        await _tap(tester, 'journal-activity:donations');
        await _tap(tester, 'journal-equipment');
        expect(_key('journal-confirm-order'), findsNothing);
        final second = game.squad[1];
        final before = campaignSnapshot();
        final revision = engine.console.revision.value;
        final scroll = find
            .descendant(
              of: find.byKey(
                const PageStorageKey('journal-management-scroll:equipment'),
              ),
              matching: find.byType(Scrollable),
            )
            .first; // The loadout panel and filter editor scroll independently.
        final position = tester.state<ScrollableState>(scroll).position;
        final offset = position.maxScrollExtent.clamp(0, 90).toDouble();
        position.jumpTo(offset);
        await _settle(tester);
        reseedRNG(seed: 29471);
        final rolls = List.generate(10, (_) => lcsRandom(100000));
        reseedRNG(seed: 29471);
        await _showCrewMember(tester, second.id);
        await _settle(tester);
        await _tap(tester, 'journal-member:${second.id}');
        expect(
          tester
              .widget<Semantics>(_key('equipment-person-row:${second.id}'))
              .properties
              .selected,
          isTrue,
        );
        expect(
          tester
              .widget<Semantics>(
                _key('equipment-person-row:${game.squad.first.id}'),
              )
              .properties
              .selected,
          isFalse,
        );
        expect(
          tester.widget<Text>(_key('journal-selected-person')).data,
          second.name,
        );
        expect(
          tester.state<ScrollableState>(scroll).position.pixels,
          closeTo(offset, .01),
        );
        expect(
          engine.console.revision.value,
          revision,
          reason: 'Selection must never send the numbered unequip command.',
        );
        expect(campaignSnapshot(), before);
        expect(List.generate(10, (_) => lcsRandom(100000)), rolls);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('left selection keeps an open crew inspector and its scroll', (
    tester,
  ) async {
    await mount(tester);
    final first = game.squad.first;
    final second = game.squad[1];
    await _tap(tester, 'hq-dossier:${first.id}');
    final scroll = find.descendant(
      of: _key('crew-inspector'),
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scroll).position;
    final offset = position.maxScrollExtent.clamp(0, 80).toDouble();
    position.jumpTo(offset);
    await _settle(tester);
    final before = campaignSnapshot();
    final revision = engine.console.revision.value;
    await _showCrewMember(tester, second.id);
    await _tap(tester, 'journal-member:${second.id}');
    expect(
      tester.widget<CrewInspector>(find.byType(CrewInspector)).person.id,
      second.id,
    );
    expect(
      tester.widget<Text>(_key('journal-selected-person')).data,
      second.name,
    );
    expect(
      tester.state<ScrollableState>(scroll).position.pixels,
      closeTo(offset, .01),
    );
    expect(engine.console.revision.value, revision);
    expect(campaignSnapshot(), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'equipment restores the active squad selection after an outside profile',
    (tester) async {
      final original = game.activeSquad!;
      final outside = _extraPerson('Other Squad Profile');
      final other = Squad()..name = 'Other squad';
      game.squads.add(other);
      outside.squad = other;
      await mount(tester, size: const Size(2200, 1200));
      await _tap(tester, 'journal-clipboard');
      await _openPersonnel(tester, outside.id);
      expect(
        tester.widget<Text>(_key('journal-selected-person')).data,
        outside.name,
      );
      final weapons = original.members.map((p) => p.equippedWeapon).toList();
      await _tap(tester, 'journal-equipment');
      expect(game.activeSquad, same(original));
      expect(
        tester.widget<Text>(_key('journal-selected-person')).data,
        original.members.first.name,
      );
      expect(
        tester
            .widget<Semantics>(
              _key('equipment-person-row:${original.members.first.id}'),
            )
            .properties
            .selected,
        isTrue,
      );
      for (var i = 0; i < weapons.length; i++) {
        expect(original.members[i].equippedWeapon, same(weapons[i]));
      }
      await _tap(tester, 'journal-member:${original.members.first.id}');
      expect(
        tester
            .widget<OrganisationJournal>(find.byType(OrganisationJournal))
            .controller
            .selectedPersonId,
        original.members.first.id,
      );
      expect(tester.takeException(), isNull);
    },
  );

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
      final before = campaignSnapshot();
      final date = game.date;
      final funds = game.ledger.funds;
      final harness = await mount(tester);
      await _tap(tester, 'journal-orders');
      await _tap(tester, 'journal-order-group:3');
      await _tap(tester, 'journal-plan-visit');
      expect(engine.console.screen, 'planning');
      await _tap(tester, 'journal-order-group:0');
      expect(engine.console.screen, 'headquarters');
      expect(campaignSnapshot(), before);
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

  for (final size in [const Size(1280, 720), const Size(1024, 720)]) {
    testWidgets(
      'City maps queues the selected squad visit with one source-routed action at $size',
      (tester) async {
        final team = game.activeSquad!..name = 'Map travellers';
        final other = Squad()..name = 'Stays at home';
        game.squads.add(other);
        _extraPerson('Other team member').squad = other;
        final destination = game.sites.firstWhere(
          (site) =>
              site.type == SiteType.pawnShop &&
              site.city == team.site?.city &&
              site.area == team.site?.area &&
              !site.hidden &&
              !site.isClosed,
        );
        final before = campaignSnapshot();
        final originalDate = game.date;
        final harness = await mount(tester, size: size);
        if (size.width == 1024) {
          await tester.tap(find.byTooltip('Reading size'));
          await _settle(tester);
          await tester.tap(find.text('150%'));
          await _settle(tester);
        }
        reseedRNG(seed: 181007);
        final rolls = List.generate(8, (_) => lcsRandom(100000));
        reseedRNG(seed: 181007);
        await tester.ensureVisible(_key('journal-section:6'));
        await _settle(tester);
        await _tap(tester, 'journal-section:6');
        await _tap(
          tester,
          'journal-map-place:${destination.district.idString}',
        );
        await _tap(tester, 'journal-map-place:${destination.idString}');
        expect(engine.console.screen, 'headquarters');
        expect(campaignSnapshot(), before);
        expect(
          tester.widget<Text>(_key('journal-city-map-squad')).data,
          'Squad: ${team.name}',
        );
        final retainedQueue = tester
            .widget<FilledButton>(_key('journal-city-map-prepare-visit'))
            .onPressed!;
        // The map survives rebuilding, but a retained queue callback belongs
        // to the squad and source revision that originally displayed it.
        await _altShortcut(tester, LogicalKeyboardKey.digit1);
        await _tap(tester, 'journal-squad:${other.id}');
        await _altShortcut(tester, LogicalKeyboardKey.digit0);
        expect(_key('journal-destination-name'), findsNothing);
        final otherSelected = campaignSnapshot();
        final otherRevision = engine.console.revision.value;
        retainedQueue();
        await _settle(tester);
        expect(campaignSnapshot(), otherSelected);
        expect(engine.console.revision.value, otherRevision);
        expect(other.activity.type, ActivityType.none);
        await _altShortcut(tester, LogicalKeyboardKey.digit1);
        await _tap(tester, 'journal-squad:${team.id}');
        await _altShortcut(tester, LogicalKeyboardKey.digit0);
        expect(
          tester.widget<Text>(_key('journal-destination-name')).data,
          destination.getName(),
        );
        expect(campaignSnapshot(), before);
        // Prepare and cancel through the actual planner before revisiting and
        // queuing. Nothing travels or advances a day during the local draft.
        await _altShortcut(tester, LogicalKeyboardKey.digit1);
        await _tap(tester, 'journal-orders');
        await _tap(tester, 'journal-order-group:3');
        await _tap(tester, 'journal-plan-visit');
        await _tap(
          tester,
          'journal-map-place:${destination.district.idString}',
        );
        await _tap(tester, 'journal-map-place:${destination.idString}');
        expect(_key('journal-confirm-order'), findsOneWidget);
        expect(campaignSnapshot(), before);
        await _tap(tester, 'journal-cancel-order');
        expect(engine.console.screen, 'headquarters');
        expect(campaignSnapshot(), before);
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'Game keyboard');
        await _altShortcut(tester, LogicalKeyboardKey.digit0);
        expect(
          tester.widget<Text>(_key('journal-destination-name')).data,
          destination.getName(),
        );
        expect(campaignSnapshot(), before);
        retainedQueue();
        await _settle(tester);
        expect(campaignSnapshot(), before);
        _insideViewport(
          tester,
          _key('journal-city-map-prepare-visit'),
          size,
          'Prepare the selected squad visit',
        );
        await _tap(tester, 'journal-city-map-prepare-visit');
        expect(engine.console.screen, 'headquarters');
        expect(_key('journal-confirm-order'), findsNothing);
        expect(find.text('Confirm or cancel draft'), findsNothing);
        expect(team.activity.type, ActivityType.visit);
        expect(
          tester
              .widget<OrganisationJournal>(find.byType(OrganisationJournal))
              .section,
          6,
          reason: 'Queuing a map visit must retain the City maps context.',
        );
        expect(team.activity.idString, destination.idString);
        expect(other.activity.type, ActivityType.none);
        expect(game.activeSquad, same(team));
        final expected = jsonDecode(before) as Map<String, dynamic>;
        final expectedSquads =
            ((expected['lcs'] as Map<String, dynamic>)['squads'] as List)
                .cast<Map<String, dynamic>>();
        expectedSquads.firstWhere((s) => s['id'] == team.id)['activity'] = team
            .activity
            .toJson();
        expect(jsonDecode(campaignSnapshot()), expected);
        expect(game.date, originalDate);
        expect(harness.dispatched, isNot(contains(engine.Key.w)));
        expect(List.generate(8, (_) => lcsRandom(100000)), rolls);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'an actual shop visit shows present services instead of future travel',
    (tester) async {
      final team = game.activeSquad!;
      final destination = game.sites.firstWhere(
        (site) =>
            site.type == SiteType.departmentStore &&
            site.city == team.site?.city &&
            !site.hidden,
      );
      team.activity = Activity(
        ActivityType.visit,
        idString: destination.idString,
      );
      await mount(tester, shopVisit: true);
      expect(
        find.text('Visit queued · advance the day to travel'),
        findsOneWidget,
      );
      await _tap(tester, 'journal-advance-day');
      expect(team.site, same(destination));
      expect(engine.console.screen, 'generic');
      expect(
        engine.console.actions.any(
          (action) => action.label.contains('Choose a buyer'),
        ),
        isTrue,
      );
      expect(find.text('Visit in progress'), findsOneWidget);
      expect(
        find.text('Visit queued · advance the day to travel'),
        findsNothing,
      );
      expect(
        find.text('Use the location’s services or leave to finish this visit.'),
        findsOneWidget,
      );
      expect(find.text('Choose care or return to headquarters.'), findsNothing);
      final leave = engine.console.actions.singleWhere(
        (action) => action.key == 'Enter',
      );
      final leaveControl = _key(
        'direct-action:${leave.y}:${leave.x}:${leave.key}',
      );
      await tester.ensureVisible(leaveControl);
      await _settle(tester);
      await tester.tap(leaveControl);
      await _settle(tester);
      expect(engine.console.screen, 'headquarters');
      expect(find.text('Visit in progress'), findsNothing);
      expect(team.activity.type, ActivityType.none);
      expect(tester.takeException(), isNull);
    },
  );

  for (final large in [false, true]) {
    testWidgets(
      'task search crosses categories with safe drafts and retained query, large=$large',
      (tester) async {
        journalReadingScale.value = large ? 1.5 : 1;
        await mount(
          tester,
          size: large ? const Size(1024, 720) : const Size(1280, 900),
        );
        await business(tester);
        if (large) {
          for (final key in [
            'journal-pool',
            'journal-clipboard',
            'journal-equipment',
            'journal-order-group:0',
            'journal-order-group:1',
            'journal-order-group:2',
            'journal-order-group:3',
          ]) {
            _insideViewport(tester, _key(key), const Size(1024, 720), key);
            final text = find
                .descendant(of: _key(key), matching: find.byType(Text))
                .first;
            expect(
              tester.renderObject<RenderParagraph>(text).didExceedMaxLines,
              isFalse,
              reason:
                  '$key must show its complete label at enlarged reading size.',
            );
          }
        }
        final actor = game.squad.first;
        final before = campaignSnapshot();
        final revision = engine.console.revision.value;
        reseedRNG(seed: 9614);
        final rolls = List.generate(12, (_) => lcsRandom(100000));
        reseedRNG(seed: 9614);
        await tester.enterText(_key('journal-order-search'), 'training');
        await _settle(tester);
        expect(engine.console.revision.value, revision);
        expect(_key('journal-activity:study'), findsOneWidget);
        expect(_key('journal-activity:donations'), findsNothing);
        await _tap(tester, 'journal-activity:study');
        expect(find.text('Prepared · awaiting confirmation'), findsOneWidget);
        expect(activityOrderFrame(engine.console)?.selectedCategoryKey, 'e');
        expect(campaignSnapshot(), before);
        await _tap(tester, 'journal-cancel-order');
        expect(campaignSnapshot(), before);
        expect(
          tester
              .widget<TextField>(_key('journal-order-search'))
              .controller!
              .text,
          'training',
        );
        await tester.enterText(_key('journal-order-search'), 'hacking');
        await _settle(tester);
        final unavailable = tester.widget<TextButton>(
          _key('journal-activity:hacking'),
        );
        expect(unavailable.onPressed, isNull);
        expect(campaignSnapshot(), before);
        await tester.enterText(_key('journal-order-search'), 'money');
        await _settle(tester);
        await _tap(tester, 'journal-activity:donations');
        final retained = tester
            .widget<TextButton>(_key('journal-activity:donations'))
            .onPressed;
        await _tap(tester, 'journal-cancel-order');
        await _tap(tester, 'journal-member:${game.squad[1].id}');
        retained?.call();
        await _settle(tester);
        expect(_key('journal-confirm-order'), findsNothing);
        expect(
          tester
              .widget<TextField>(_key('journal-order-search'))
              .controller!
              .text,
          'money',
        );
        expect(campaignSnapshot(), before);
        expect(List.generate(12, (_) => lcsRandom(100000)), rolls);
        await _tap(tester, 'journal-activity:donations');
        await _tap(tester, 'journal-confirm-order');
        expect(game.squad[1].activity.type, ActivityType.donations);
        expect(actor.activity.type, ActivityType.sellArt);
        // Returning to the task browser retains search; typing never answers the game.
        expect(
          tester
              .widget<TextField>(_key('journal-order-search'))
              .controller!
              .text,
          'money',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'group browsing, task staging and Cancel leave actual assignments and RNG intact',
    (tester) async {
      await mount(tester);
      final person = game.squad.first;
      final order = person.activity;
      final before = campaignSnapshot();
      reseedRNG(seed: 9013);
      final rolls = List.generate(12, (_) => lcsRandom(100000));
      reseedRNG(seed: 9013);
      await business(tester);
      expect(campaignSnapshot(), before);
      expect(person.activity, same(order));
      for (final group in [1, 2, 3, 0]) {
        await _tap(tester, 'journal-order-group:$group');
        expect(campaignSnapshot(), before);
        expect(person.activity, same(order));
      }
      final revision = engine.console.revision.value;
      await _tap(tester, 'journal-activity:donations');
      expect(campaignSnapshot(), before);
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
      expect(campaignSnapshot(), before);
      expect(person.activity, same(order));
      expect(_key('journal-confirm-order'), findsNothing);
      expect(find.text('Assigned order'), findsOneWidget);
      expect(engine.console.revision.value, revision);
      expect(List.generate(12, (_) => lcsRandom(100000)), rolls);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'raw journal category and task keys retain immediate source assignments and Back',
    (tester) async {
      await mount(tester);
      final person = game.squad.first;
      person.activity = Activity.none();
      await _tap(tester, 'journal-orders');
      await _focusGame(tester);
      final before = jsonDecode(campaignSnapshot()) as Map<String, dynamic>;
      final date = game.date;
      final funds = game.ledger.funds;
      reseedRNG(seed: 81230);
      final rolls = List.generate(12, (_) => lcsRandom(100000));
      reseedRNG(seed: 81230);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB, character: 'b');
      await _settle(tester);
      expect(activityOrderFrame(engine.console)?.selectedCategoryKey, 'b');
      expect(person.activity.type, isNot(ActivityType.none));
      expect(_key('journal-confirm-order'), findsNothing);
      final revision = engine.console.revision.value;
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1, character: '1');
      await _settle(tester);
      expect(person.activity.type, ActivityType.donations);
      expect(_key('journal-confirm-order'), findsNothing);
      expect(engine.console.revision.value, greaterThan(revision));
      final people = ((before['lcs'] as Map<String, dynamic>)['pool'] as List)
          .cast<Map<String, dynamic>>();
      people.singleWhere((entry) => entry['id'] == person.id)['activity'] = {
        'type': 'donations',
      };
      expect(jsonDecode(campaignSnapshot()), before);
      final assigned = campaignSnapshot();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(tester);
      expect(activityOrderFrame(engine.console), isNull);
      expect(engine.console.navigation?.section, 'assignments');
      expect(campaignSnapshot(), assigned);
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
      final before = jsonDecode(campaignSnapshot()) as Map<String, dynamic>;
      await business(tester);
      expect(activityOrderFrame(engine.console)?.actorId, selected.id);
      await _tap(tester, 'journal-activity:donations');
      await _tap(tester, 'journal-confirm-order');
      expect(engine.console.screen, 'activity-orders');
      expect(activityOrderFrame(engine.console)?.actorId, selected.id);
      expect(selected.activity.type, ActivityType.donations);
      for (final person in game.squad.where((p) => p != selected)) {
        expect(person.activity.type, ActivityType.sellArt);
      }
      final after = jsonDecode(campaignSnapshot()) as Map<String, dynamic>;
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
      final before = campaignSnapshot();
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
      expect(campaignSnapshot(), before);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(1280, 720), const Size(1024, 720)]) {
    testWidgets(
      'member changes retain nested category and optional map state at $size',
      (tester) async {
        await mount(tester, size: size);
        if (size.width == 1024) {
          await tester.tap(find.byTooltip('Reading size'));
          await _settle(tester);
          await tester.tap(find.text('150%'));
          await _settle(tester);
        }
        await _tap(tester, 'journal-orders');
        await _tap(tester, 'journal-order-group:1');
        await tester.tap(
          find.widgetWithText(OutlinedButton, 'Teaching Classes'),
        );
        await _settle(tester);
        final next = game.squad[1];
        final before = campaignSnapshot();
        final districtId = game.activeSquad!.site!.district.idString;
        await _tap(tester, 'journal-orders-map-toggle');
        await _tap(tester, 'journal-map-place:$districtId');
        final mapState = tester.state(find.byType(JournalCityPlan));
        final retainedMap = find.byType(JournalCityPlan, skipOffstage: false);
        final retainedIndex = find.byKey(
          const ValueKey('journal-location-index'),
          skipOffstage: false,
        );
        final viewer = tester.widget<InteractiveViewer>(
          find.byType(InteractiveViewer),
        );
        viewer.transformationController!.value = Matrix4.identity()
          ..scaleByDouble(1.4, 1.4, 1, 1);
        await tester.tap(find.byTooltip('Show location index'));
        await _settle(tester);
        await _tap(tester, 'journal-orders-map-toggle');
        await _tap(tester, 'journal-activity:teachLiberalArts');
        await _showCrewMember(tester, next.id);
        await _settle(tester);
        await tester.tap(_key('journal-member:${next.id}'));
        for (var frame = 0; frame < 80; frame++) {
          await tester.pump(const Duration(milliseconds: 1));
          expect(tester.state(retainedMap), same(mapState));
          expect(retainedIndex, findsOneWidget);
        }
        await _settle(tester);
        expect(activityOrderFrame(engine.console)?.actorId, next.id);
        expect(activityOrderFrame(engine.console)?.selectedCategoryKey, 't');
        expect(
          _key('journal-activity:teachLiberalArts').hitTestable(),
          findsOneWidget,
        );
        expect(_key('journal-confirm-order'), findsNothing);
        expect(tester.state(retainedMap), same(mapState));
        expect(retainedIndex, findsOneWidget);
        expect(viewer.transformationController!.value.entry(0, 0), 1.4);
        await _tap(tester, 'journal-orders-map-toggle');
        await tester.tap(find.byTooltip('Show city plan'));
        await _settle(tester);
        final third = game.squad[2];
        await _showCrewMember(tester, third.id);
        await _settle(tester);
        viewer.transformationController!.value = Matrix4.identity()
          ..scaleByDouble(1.7, 1.7, 1, 1);
        await tester.tap(_key('journal-member:${third.id}'));
        for (var frame = 0; frame < 80; frame++) {
          await tester.pump(const Duration(milliseconds: 1));
          expect(tester.state(find.byType(JournalCityPlan)), same(mapState));
          expect(viewer.transformationController!.value.entry(0, 0), 1.7);
        }
        await _settle(tester);
        expect(activityOrderFrame(engine.console)?.actorId, third.id);
        expect(activityOrderFrame(engine.console)?.selectedCategoryKey, 't');
        expect(viewer.transformationController!.value.entry(0, 0), 1.7);
        expect(campaignSnapshot(), before);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'below-minimum stress: switching members retains the scrolled task list',
    (tester) async {
      await mount(tester, size: const Size(800, 600));
      await tester.tap(find.byTooltip('Reading size'));
      await _settle(tester);
      await tester.tap(find.text('150%'));
      await _settle(tester);
      await _tap(tester, 'journal-orders');
      // This unsupported 800x600 stress layout may scroll its navigation rail.
      await tester.ensureVisible(_key('journal-order-group:0'));
      await _settle(tester);
      await _tap(tester, 'journal-order-group:0');
      final list = find.byKey(const PageStorageKey('journal-tasks:0:legal'));
      final scroll = find.descendant(
        of: list,
        matching: find.byType(Scrollable),
      );
      await tester.drag(list, const Offset(0, -160));
      await _settle(tester);
      final offset = tester.state<ScrollableState>(scroll).position.pixels;
      expect(offset, greaterThan(0));
      final next = game.squad[1];
      await _showCrewMember(tester, next.id);
      await _settle(tester);
      await _tap(tester, 'journal-member:${next.id}');
      expect(
        tester.state<ScrollableState>(scroll).position.pixels,
        closeTo(offset, .01),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('retained categories refresh availability for the new member', (
    tester,
  ) async {
    final next = game.squad[1];
    next.birthDate = DateTime(
      game.date.year - 17,
      game.date.month,
      game.date.day,
    );
    await mount(tester);
    await business(tester);
    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Illegal Fundraising'),
    );
    await _settle(tester);
    final before = campaignSnapshot();
    await _tap(tester, 'journal-activity:prostitution');
    final priorConfirm = tester
        .widget<FilledButton>(_key('journal-confirm-order'))
        .onPressed!;
    await _tap(tester, 'journal-member:${next.id}');
    expect(activityOrderFrame(engine.console)?.selectedCategoryKey, 'c');
    expect(
      engine.console.actions
          .singleWhere((a) => a.entityId == ActivityType.prostitution.name)
          .enabled,
      isFalse,
    );
    expect(_key('journal-confirm-order'), findsNothing);
    final unavailable = _key('journal-activity:prostitution');
    expect(unavailable, findsOneWidget);
    expect(tester.widget<TextButton>(unavailable).onPressed, isNull);
    await tester.ensureVisible(unavailable);
    await _settle(tester);
    final revision = engine.console.revision.value;
    await tester.tap(unavailable);
    await _settle(tester);
    expect(engine.console.revision.value, revision);
    expect(_key('journal-confirm-order'), findsNothing);
    priorConfirm();
    await _settle(tester);
    expect(
      campaignSnapshot(),
      before,
      reason:
          'Even a captured confirmation cannot apply the previous actor’s draft.',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'retained task and category callbacks cannot replace the current actor draft',
    (tester) async {
      await mount(tester);
      await business(tester);
      final first = game.squad.first;
      final next = game.squad[1];
      final oldTask = tester
          .widget<TextButton>(_key('journal-activity:donations'))
          .onPressed!;
      final oldCategory = tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Illegal Fundraising'),
          )
          .onPressed!;
      final before = campaignSnapshot();
      reseedRNG(seed: 42061);
      final rolls = List.generate(8, (_) => lcsRandom(100000));
      reseedRNG(seed: 42061);
      await _tap(tester, 'journal-member:${next.id}');
      await _tap(tester, 'journal-activity:donations');
      final revision = engine.console.revision.value;
      final confirm = tester
          .widget<FilledButton>(_key('journal-confirm-order'))
          .onPressed!;
      for (final retained in [oldTask, oldCategory]) {
        retained();
        await _settle(tester);
        expect(activityOrderFrame(engine.console)?.actorId, next.id);
        expect(activityOrderFrame(engine.console)?.selectedCategoryKey, 'b');
        expect(_key('journal-confirm-order'), findsOneWidget);
        expect(find.text('Prepared · awaiting confirmation'), findsOneWidget);
        expect(engine.console.revision.value, revision);
        expect(campaignSnapshot(), before);
      }
      confirm();
      await _settle(tester);
      expect(first.activity.type, ActivityType.sellArt);
      expect(next.activity.type, ActivityType.donations);
      expect(activityOrderFrame(engine.console)?.actorId, next.id);
      expect(activityOrderFrame(engine.console)?.selectedCategoryKey, 'b');
      expect(List.generate(8, (_) => lcsRandom(100000)), rolls);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'busy actor navigation displays cached tasks with no dispatch authority',
    (tester) async {
      await mount(tester);
      await business(tester);
      final journal = tester.widget<OrganisationJournal>(
        find.byType(OrganisationJournal),
      );
      final previousTask = tester
          .widget<TextButton>(_key('journal-activity:donations'))
          .onPressed!;
      final previousCategory = tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Illegal Fundraising'),
          )
          .onPressed!;
      final searchBounds = tester.getRect(_key('journal-order-search'));
      final taskBounds = tester.getRect(
        find.byKey(const PageStorageKey('journal-tasks:0:legal')),
      );
      final before = campaignSnapshot();
      final next = game.squad[1];
      await tester.tap(_key('journal-member:${next.id}'));
      expect(journal.controller.busy, isTrue);
      var busyFrames = 0;
      for (var frame = 0; frame < 60; frame++) {
        await tester.pump(const Duration(milliseconds: 1));
        if (!journal.controller.busy) continue;
        busyFrames++;
        expect(_key('journal-order-search'), findsOneWidget);
        expect(tester.getRect(_key('journal-order-search')), searchBounds);
        expect(
          tester.getRect(
            find.byKey(const PageStorageKey('journal-tasks:0:legal')),
          ),
          taskBounds,
        );
        expect(
          tester
              .widget<TextButton>(_key('journal-activity:donations'))
              .onPressed,
          isNull,
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Illegal Fundraising'),
              )
              .onPressed,
          isNull,
        );
        previousTask();
        previousCategory();
        expect(campaignSnapshot(), before);
      }
      expect(busyFrames, greaterThan(0));
      await _settle(tester);
      expect(activityOrderFrame(engine.console)?.actorId, next.id);
      expect(activityOrderFrame(engine.console)?.selectedCategoryKey, 'b');
      expect(_key('journal-confirm-order'), findsNothing);
      expect(campaignSnapshot(), before);
      await _tap(tester, 'journal-activity:donations');
      await _tap(tester, 'journal-confirm-order');
      expect(next.activity.type, ActivityType.donations);
      expect(
        game.squad
            .where((person) => person != next)
            .every((person) => person.activity.type == ActivityType.sellArt),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'enlarged task scroll survives category browsing, actor changes, map and revisit',
    (tester) async {
      await mount(tester, size: const Size(1024, 720));
      await tester.tap(find.byTooltip('Reading size'));
      await _settle(tester);
      await tester.tap(find.text('150%'));
      await _settle(tester);
      await _tap(tester, 'journal-orders');
      await _tap(tester, 'journal-order-group:1');
      final before = campaignSnapshot();
      final list = find.byKey(
        const PageStorageKey('journal-tasks:1:acquisition'),
      );
      ScrollPosition position() => tester
          .state<ScrollableState>(
            find.descendant(of: list, matching: find.byType(Scrollable)),
          )
          .position;
      expect(position().maxScrollExtent, greaterThan(0));
      // Switch categories during a real scroll, before its end notification
      // would normally persist the offset to PageStorage (as in web scrolling).
      unawaited(
        position().animateTo(
          position().maxScrollExtent,
          duration: const Duration(seconds: 1),
          curve: Curves.linear,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      var offset = position().pixels;
      expect(offset, greaterThan(0));
      expect(position().isScrollingNotifier.value, isTrue);
      final controller = tester
          .widget<OrganisationJournal>(find.byType(OrganisationJournal))
          .controller;
      Future<void> browse(String label, String cachedCategory) async {
        await tester.tap(find.widgetWithText(OutlinedButton, label));
        var busyFrames = 0;
        for (var frame = 0; frame < 60; frame++) {
          await tester.pump(const Duration(milliseconds: 1));
          if (!controller.busy) continue;
          busyFrames++;
          expect(
            find.byKey(PageStorageKey('journal-tasks:1:$cachedCategory')),
            findsOneWidget,
            reason: 'Cached rows retain their own category scroll identity.',
          );
        }
        expect(busyFrames, greaterThan(0));
        await _settle(tester);
      }

      await browse('Teaching Classes', 'acquisition');
      await browse('Recruitment and Acquisition', 'teaching');
      expect(position().pixels, closeTo(offset, .01));
      // Also retain the full end offset through the hidden-pane/group path.
      position().jumpTo(position().maxScrollExtent);
      await _settle(tester);
      offset = position().pixels;
      final row = _key('journal-activity:makeFlag');
      final taskFocus = Focus.of(
        tester.element(
          find.descendant(of: row, matching: find.byType(JournalShortcutBadge)),
        ),
      );
      expect(taskFocus.canRequestFocus, isTrue);
      await _tap(tester, 'journal-orders-map-toggle');
      expect(taskFocus.canRequestFocus, isFalse);
      taskFocus.requestFocus();
      await tester.pump();
      expect(taskFocus.hasFocus, isFalse);
      final mapButton = find.byTooltip('Show location index');
      final mapFocus = Focus.of(
        tester.element(
          find.descendant(of: mapButton, matching: find.byType(Icon)).first,
        ),
      );
      expect(mapFocus.canRequestFocus, isTrue);
      await _tap(tester, 'journal-order-group:0');
      expect(_key('journal-order-map'), findsOneWidget);
      await _tap(tester, 'journal-order-group:1');
      expect(_key('journal-order-map'), findsOneWidget);
      expect(activityOrderFrame(engine.console)?.selectedCategoryKey, 'd');
      await _tap(tester, 'journal-orders-map-toggle');
      expect(mapFocus.canRequestFocus, isFalse);
      mapFocus.requestFocus();
      await tester.pump();
      expect(mapFocus.hasFocus, isFalse);
      expect(position().pixels, closeTo(offset, .01));
      final next = game.squad[1];
      await _showCrewMember(tester, next.id);
      await _tap(tester, 'journal-member:${next.id}');
      expect(position().pixels, closeTo(offset, .01));
      await _tap(tester, 'journal-reports');
      await _tap(tester, 'journal-orders');
      expect(activityOrderFrame(engine.console)?.actorId, next.id);
      expect(activityOrderFrame(engine.console)?.selectedCategoryKey, 'd');
      expect(position().pixels, closeTo(offset, .01));
      expect(campaignSnapshot(), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'repeated assignments keep the nested category and affect only confirmed members',
    (tester) async {
      await mount(tester);
      await _tap(tester, 'journal-orders');
      await _tap(tester, 'journal-order-group:1');
      await tester.tap(find.widgetWithText(OutlinedButton, 'Teaching Classes'));
      await _settle(tester);
      final first = game.squad.first;
      final second = game.squad[1];
      final before = jsonDecode(campaignSnapshot()) as Map<String, dynamic>;
      reseedRNG(seed: 85612);
      final rolls = List.generate(12, (_) => lcsRandom(100000));
      reseedRNG(seed: 85612);
      for (final member in [first, second]) {
        await _tap(tester, 'journal-member:${member.id}');
        expect(activityOrderFrame(engine.console)?.selectedCategoryKey, 't');
        await _tap(tester, 'journal-activity:teachLiberalArts');
        await _tap(tester, 'journal-confirm-order');
        expect(activityOrderFrame(engine.console)?.actorId, member.id);
        expect(activityOrderFrame(engine.console)?.selectedCategoryKey, 't');
        expect(_key('journal-confirm-order'), findsNothing);
        expect(
          _key('journal-activity:teachLiberalArts').hitTestable(),
          findsOneWidget,
        );
        expect(member.activity.type, ActivityType.teachLiberalArts);
      }
      final after = jsonDecode(campaignSnapshot()) as Map<String, dynamic>;
      final oldPool = (before['lcs'] as Map<String, dynamic>)['pool'] as List;
      final newPool = (after['lcs'] as Map<String, dynamic>)['pool'] as List;
      for (final member in [first, second]) {
        final index = game.pool.indexOf(member);
        (oldPool[index] as Map<String, dynamic>)['activity'] =
            (newPool[index] as Map<String, dynamic>)['activity'];
      }
      expect(
        after,
        before,
        reason: 'Only the two explicitly confirmed assignments change.',
      );
      expect(List.generate(12, (_) => lcsRandom(100000)), rolls);
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
      final selected = campaignSnapshot();
      await _tap(tester, 'journal-squad:${team.id}');
      expect(squadAllocationFrame(engine.console), isNull);
      expect(campaignSnapshot(), selected);
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
      final before = campaignSnapshot();
      final revision = engine.console.revision.value;
      await _tap(tester, 'hq-dossier:${person.id}');
      expect(find.byType(CrewInspector), findsOneWidget);
      expect(engine.console.revision.value, revision);
      expect(campaignSnapshot(), before);
      await business(tester);
      expect(activityOrderFrame(engine.console)?.actorId, person.id);
      expect(find.byType(CrewInspector), findsNothing);
      expect(_key('journal-activity:donations').hitTestable(), findsOneWidget);
      await _tap(tester, 'journal-activity:donations');
      expect(_key('journal-confirm-order').hitTestable(), findsOneWidget);
      expect(campaignSnapshot(), before);
      expect(tester.takeException(), isNull);
    },
  );

  for (final large in [false, true]) {
    testWidgets(
      'pool inspection survives rebuild and sorting survives revisit, large=$large',
      (tester) async {
        final candidate = _extraPerson('Waiting Pool Candidate');
        journalReadingScale.value = large ? 1.5 : 1;
        await mount(
          tester,
          size: large ? const Size(1024, 720) : const Size(1280, 800),
        );
        final before = campaignSnapshot();
        reseedRNG(seed: 41926);
        final rolls = List.generate(12, (_) => lcsRandom(100000));
        reseedRNG(seed: 41926);
        await _tap(tester, 'journal-pool');
        await _tap(tester, 'journal-pool-person:${candidate.id}');

        final sort = find.descendant(
          of: find.byType(OrganisationCrewPoolView),
          matching: find.byType(DropdownButton<Skill>),
        );
        await tester.tap(sort);
        await _settle(tester);
        final art = find.text('Sort: Art').last;
        await tester.scrollUntilVisible(
          find.text('Sort: Art'),
          -100,
          scrollable: find.byType(Scrollable).last,
        );
        await _settle(tester);
        await tester.tap(art);
        await _settle(tester);

        void expectRetainedPreview() {
          expect(tester.widget<DropdownButton<Skill>>(sort).value, Skill.art);
          expect(find.text(candidate.name), findsNWidgets(2));
          expect(
            find.widgetWithText(FilledButton, 'Add to this squad'),
            findsOneWidget,
          );
        }

        expectRetainedPreview();
        // Rebuild the surrounding journal without replacing its reader.
        final revision = engine.console.revision.value;
        await _tap(tester, 'journal-skills');
        expect(engine.console.revision.value, revision);
        expectRetainedPreview();
        await _tap(tester, 'journal-skills');
        expectRetainedPreview();
        await tester.tap(find.widgetWithText(TextButton, 'Done'));
        await _settle(tester);
        expect(squadAllocationFrame(engine.console), isNull);
        await _tap(tester, 'journal-pool');
        expect(tester.widget<DropdownButton<Skill>>(sort).value, Skill.art);
        expect(
          find.widgetWithText(FilledButton, 'Add to this squad'),
          findsNothing,
          reason: 'Done clears inspection while retaining the sort choice.',
        );
        await _tap(tester, 'journal-pool-person:${candidate.id}');
        expectRetainedPreview();
        expect(campaignSnapshot(), before);
        expect(List.generate(12, (_) => lcsRandom(100000)), rolls);
        expect(tester.takeException(), isNull);
      },
    );
  }

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
    final before = campaignSnapshot();
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
    expect(campaignSnapshot(), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'sleeper orders remain reachable through source list, group and confirmed job card',
    (tester) async {
      final person = _extraPerson('Undercover Crew')..sleeperAgent = true;
      final oldOrder = Activity(ActivityType.sleeperLiberal);
      person.activity = oldOrder;
      await mount(tester);
      final before = campaignSnapshot();
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
      expect(campaignSnapshot(), before);
      expect(person.activity, same(oldOrder));
      await _tap(tester, 'journal-activity:sleeperSpy');
      expect(campaignSnapshot(), before);
      await _tap(tester, 'journal-cancel-order');
      expect(person.activity, same(oldOrder));
      await _tap(tester, 'journal-activity:sleeperSpy');
      await _tap(tester, 'journal-confirm-order');
      expect(person.activity.type, ActivityType.sleeperSpy);
      expect(engine.console.screen, 'activity-orders');
      expect(activityOrderFrame(engine.console)?.selectedCategoryKey, 'b');
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(1280, 720), const Size(1024, 720)]) {
    testWidgets(
      'six crew, job card, eleven reachable sections and Confirm fit at ${size.width}x${size.height}',
      (tester) async {
        await mount(tester, size: size);
        await business(tester);
        await _tap(tester, 'journal-activity:donations');
        for (var i = 0; i <= basesJournalSection; i++) {
          await tester.ensureVisible(_key('journal-section:$i'));
          await _settle(tester);
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
        final beforeTabScroll = campaignSnapshot();
        for (var i = 0; i <= basesJournalSection; i++) {
          // Enlarged reading keeps eleven readable tabs in a horizontal strip.
          // Each destination must remain reachable without dispatching it.
          await tester.ensureVisible(_key('journal-section:$i'));
          await _settle(tester);
          _insideViewport(
            tester,
            _key('journal-section:$i'),
            size,
            'Scaled section $i',
          );
        }
        expect(campaignSnapshot(), beforeTabScroll);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final enlarged in [false, true]) {
    testWidgets(
      'order formulas retain draft, scroll and focus without changing assignments, input or RNG, enlarged=$enlarged',
      (tester) async {
        await mount(
          tester,
          size: enlarged ? const Size(1024, 720) : const Size(1280, 720),
        );
        await business(tester);
        await _tap(tester, 'journal-activity:donations');
        if (enlarged) {
          await tester.tap(find.byTooltip('Reading size'));
          await _settle(tester);
          await tester.tap(find.text('150%'));
          await _settle(tester);
        }
        final before = campaignSnapshot();
        final revision = engine.console.revision.value;
        final actor = game.squad.first;
        final title = tester.widget<Text>(_key('journal-current-order')).data;
        final mechanics = find.descendant(
          of: _key('journal-order-mechanics'),
          matching: find.byType(Scrollable),
        );
        ScrollPosition mechanicsPosition() =>
            tester.state<ScrollableState>(mechanics).position;
        expect(mechanicsPosition().maxScrollExtent, greaterThan(0));
        mechanicsPosition().jumpTo(
          mechanicsPosition().maxScrollExtent.clamp(0, 24),
        );
        await _settle(tester);
        final offset = mechanicsPosition().pixels;
        void expectRetainedDraft() {
          expect(
            tester.widget<Text>(_key('journal-current-order')).data,
            title,
          );
          expect(
            tester.widget<Text>(_key('journal-selected-person')).data,
            actor.name,
          );
          expect(find.text('Prepared · awaiting confirmation'), findsOneWidget);
          expect(mechanicsPosition().pixels, closeTo(offset, .01));
          expect(_key('journal-confirm-order').hitTestable(), findsOneWidget);
          expect(campaignSnapshot(), before);
          expect(engine.console.revision.value, revision);
        }

        final help = activityMechanics(
          ActivityType.donations,
          actor: game.squad.first,
        );
        final formula = 'Calculation: ${help.calculation!.formula}';
        expect(find.byType(ActivityCalculationView), findsNothing);
        expect(find.text(formula), findsNothing);
        expect(_key('journal-order-details').hitTestable(), findsOneWidget);
        expect(_key('journal-confirm-order').hitTestable(), findsOneWidget);
        reseedRNG(seed: 412);
        final rolls = List.generate(8, (_) => lcsRandom(100000));
        reseedRNG(seed: 412);
        for (final dismissWithEscape in [false, true]) {
          await _tap(tester, 'journal-order-details');
          final dialog = _key('journal-order-details-dialog');
          expect(dialog, findsOneWidget);
          expect(find.text(formula), findsOneWidget);
          expect(find.byType(ActivityCalculationView), findsOneWidget);
          expect(
            MediaQuery.textScalerOf(tester.element(dialog)).scale(10),
            enlarged ? 15 : 10,
          );
          expect(campaignSnapshot(), before);
          expect(engine.console.revision.value, revision);
          if (dismissWithEscape) {
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          } else {
            await tester.tap(find.text('Close'));
          }
          await _settle(tester);
          expect(dialog, findsNothing);
          expect(find.text(formula), findsNothing);
          expectRetainedDraft();
          final gameFocus = tester
              .widgetList<Focus>(find.byType(Focus))
              .singleWhere(
                (widget) => widget.focusNode?.debugLabel == 'Game keyboard',
              )
              .focusNode!;
          expect(
            gameFocus.hasPrimaryFocus,
            isTrue,
            reason:
                'Closing mechanics must restore the original game keyboard reader.',
          );
          await _tap(tester, 'journal-skills');
          expectRetainedDraft();
          await _tap(tester, 'journal-skills');
          expectRetainedDraft();
        }
        await _tap(tester, 'journal-cancel-order');
        expect(find.text('Prepared · awaiting confirmation'), findsNothing);
        expect(campaignSnapshot(), before);
        expect(engine.console.revision.value, revision);
        expect(List.generate(8, (_) => lcsRandom(100000)), rolls);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'a prepared personal order blocks day and HQ shortcuts until cancel or confirm',
    (tester) async {
      final harness = await mount(tester);
      final actor = game.squad.first;
      final originalOrder = actor.activity;
      final before = campaignSnapshot();
      final originalDate = game.date;
      final retainedAdvance = tester
          .widget<FilledButton>(_key('journal-advance-day'))
          .onPressed!;
      final retainedCommands = tester
          .widget<TextButton>(_key('journal-more-commands'))
          .onPressed!;
      reseedRNG(seed: 181004);
      final rolls = List.generate(8, (_) => lcsRandom(100000));
      reseedRNG(seed: 181004);

      await business(tester);
      await _tap(tester, 'journal-activity:donations');
      expect(find.text('Confirm or cancel draft'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(_key('journal-advance-day')).onPressed,
        isNull,
      );
      expect(
        tester.widget<TextButton>(_key('journal-more-commands')).onPressed,
        isNull,
      );
      // Old footer callbacks must recheck local state, even though preparing a
      // task intentionally leaves the source revision and campaign unchanged.
      retainedAdvance();
      retainedCommands();
      await _settle(tester);
      expect(find.byType(PopupMenuItem<ConsoleAction>), findsNothing);
      expect(_key('journal-confirm-order'), findsOneWidget);
      expect(harness.dispatched, isNot(contains(engine.Key.w)));
      expect(campaignSnapshot(), before);
      expect(game.date, originalDate);
      expect(List.generate(8, (_) => lcsRandom(100000)), rolls);

      await _tap(tester, 'journal-cancel-order');
      expect(find.text('Confirm or cancel draft'), findsNothing);
      expect(
        tester.widget<FilledButton>(_key('journal-advance-day')).onPressed,
        isNotNull,
      );
      expect(campaignSnapshot(), before);
      await _tap(tester, 'journal-activity:donations');
      expect(find.text('Confirm or cancel draft'), findsOneWidget);
      actor.activity = Activity(ActivityType.donations);
      final confirmed = campaignSnapshot();
      actor.activity = originalOrder;
      await _tap(tester, 'journal-confirm-order');
      expect(campaignSnapshot(), confirmed);
      expect(game.date, originalDate);
      expect(find.text('Confirm or cancel draft'), findsNothing);
      expect(
        tester.widget<FilledButton>(_key('journal-advance-day')).onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '1024x720 at 150 percent shows prepared order timing inside its mechanics viewport',
    (tester) async {
      // Use the unchanged five-person save from the Chrome reproduction rather
      // than the six-person stress fixture used by the surrounding tests.
      fixture.restoreState();
      game.mode = GameMode.base;
      game.activeSquadMember = null;
      expect(game.squad.length, 5);
      const size = Size(1024, 720);
      await mount(tester, size: size);
      final before = campaignSnapshot();
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
            .descendant(of: card, matching: find.byTooltip('Order mechanics'))
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
      expect(campaignSnapshot(), before);
      await _tap(tester, 'journal-cancel-order');
      expect(campaignSnapshot(), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('HQ reorder keeps both decisions visible at 150 percent', (
    tester,
  ) async {
    const size = Size(1024, 720);
    await mount(tester, size: size);
    await tester.tap(find.byTooltip('Reading size'));
    await _settle(tester);
    await tester.tap(find.text('150%'));
    await _settle(tester);
    final before = campaignSnapshot();
    await _tap(tester, 'journal-more-commands');
    await tester.ensureVisible(find.text('Reorder'));
    await tester.tap(find.text('Reorder'));
    await _settle(tester);
    for (var step = 0; step < 2; step++) {
      expect(engine.console.screen, 'squad_choice');
      for (final action in engine.console.actions) {
        final button = _key(
          'direct-action:${action.y}:${action.x}:${action.key}',
        );
        _insideViewport(
          tester,
          button,
          size,
          'Reorder step $step / ${action.key}',
        );
        expect(button.hitTestable(), findsOneWidget);
      }
      if (step == 0) {
        final first = engine.console.actions.first;
        await _tap(tester, 'direct-action:${first.y}:${first.x}:${first.key}');
      }
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(engine.console.screen, 'headquarters');
    expect(campaignSnapshot(), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'uncommon HQ commands remain reachable and invoke the actual original reader',
    (tester) async {
      final harness = await mount(tester);
      final before = campaignSnapshot();
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
          (action) =>
              action.key == '1' &&
              action.label == '1 - ${game.squad.first.name}',
        ),
        isTrue,
      );
      expect(engine.console.navigation, isNull);
      expect(campaignSnapshot(), before);
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
      await _tap(tester, 'journal-advance-day');
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
      final before = campaignSnapshot();
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
      expect(campaignSnapshot(), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'manual ledger Back returns to its original asset-review parent',
    (tester) async {
      await mount(tester);
      final before = campaignSnapshot();
      await _tap(tester, 'journal-section:1');
      expect(ledgerReportFrame(engine.console)?.management, isTrue);
      await _tap(tester, 'journal-ledger-close');
      expect(ledgerReportFrame(engine.console), isNull);
      expect(engine.console.screen, 'organisation');
      expect(engine.console.navigation?.section, 'people');
      expect(engine.console.actions.any((action) => action.key == 'v'), isTrue);
      expect(campaignSnapshot(), before);
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
      expect(
        find.descendant(
          of: _key('journal-ledger-close'),
          matching: find.text('Continue'),
        ),
        findsOneWidget,
      );
      final before = campaignSnapshot();
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
      expect(campaignSnapshot(), before);
      expect(harness.monthReset, isFalse);
      expect(game.ledger.income[Income.donations], 345);
      expect(find.text('Continue'), findsOneWidget);
      expect(_key('journal-advance-day'), findsNothing);
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

  for (final large in [false, true]) {
    testWidgets(
      'day from Newspaper keeps the required report before returning to Organisation, large=$large',
      (tester) async {
        journalReadingScale.value = large ? 1.5 : 1;
        game.ledger.income[Income.donations] = 345;
        final harness = await mount(
          tester,
          monthlyReport: true,
          size: large ? const Size(1024, 720) : const Size(1280, 800),
        );
        await _altShortcut(tester, LogicalKeyboardKey.digit8);
        expect(find.byType(JournalMediaOverview), findsOneWidget);
        await _tap(tester, 'journal-advance-day');
        expect(ledgerReportFrame(engine.console)?.management, isFalse);
        expect(harness.monthReset, isFalse);
        final report = campaignSnapshot();
        final revision = engine.console.revision.value;
        await _altShortcut(tester, LogicalKeyboardKey.keyO);
        expect(find.text('Journal options'), findsNothing);
        expect(engine.console.revision.value, revision);
        expect(campaignSnapshot(), report);
        expect(harness.monthReset, isFalse);
        _insideViewport(
          tester,
          _key('journal-ledger-close'),
          large ? const Size(1024, 720) : const Size(1280, 800),
          'Required Continue',
        );
        await _tap(tester, 'journal-ledger-close');
        expect(harness.monthReset, isTrue);
        expect(engine.console.screen, 'headquarters');
        expect(game.ledger.income[Income.donations], 0);
        expect(
          tester
              .widget<OrganisationJournal>(find.byType(OrganisationJournal))
              .section,
          0,
        );
        expect(
          _key('journal-member:${game.squad.first.id}').hitTestable(),
          findsOneWidget,
        );
        expect(find.byType(JournalMediaOverview), findsNothing);
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'Game keyboard');
        expect(tester.takeException(), isNull);
      },
    );
  }

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
    final before = campaignSnapshot();
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
    expect(campaignSnapshot(), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'optional Alt routes retain original labels, real readers and campaign state',
    (tester) async {
      await mount(tester);
      final before = campaignSnapshot();
      reseedRNG(seed: 201017);
      final rolls = List.generate(8, (_) => lcsRandom(100000));
      reseedRNG(seed: 201017);
      const routes = <(LogicalKeyboardKey, int, String)>[
        (LogicalKeyboardKey.digit1, 0, 'Organisation'),
        (LogicalKeyboardKey.digit2, 9, 'People'),
        (LogicalKeyboardKey.digit3, 8, 'Network'),
        (LogicalKeyboardKey.digit4, 10, 'Bases'),
        (LogicalKeyboardKey.digit5, 1, 'Ledger'),
        (LogicalKeyboardKey.digit6, 2, 'Justice'),
        (LogicalKeyboardKey.digit7, 3, 'Agenda'),
        (LogicalKeyboardKey.digit8, 4, 'Newspaper'),
        (LogicalKeyboardKey.digit9, 5, 'Reports'),
        (LogicalKeyboardKey.digit0, 6, 'City maps'),
        (LogicalKeyboardKey.keyO, 7, 'Options'),
      ];
      for (final (key, section, name) in routes) {
        await _altShortcut(tester, key);
        expect(
          tester
              .widget<OrganisationJournal>(find.byType(OrganisationJournal))
              .section,
          section,
          reason: '$name must use the same route as its pointer control.',
        );
        final badge = find.descendant(
          of: _key('journal-section:$section'),
          matching: find.byType(JournalShortcutBadge),
        );
        final original = journalOriginalSectionRoutes[section];
        if (original == null) {
          expect(badge, findsNothing);
        } else {
          expect(badge, findsOneWidget);
          final shortcut = tester.widget<JournalShortcutBadge>(badge).shortcut;
          final direct = switch (section) {
            1 => 'v',
            2 => '4',
            9 => '0',
            _ => null,
          };
          expect({original, 'HQ: $original', direct}, contains(shortcut));
          expect(shortcut, isNot(contains('Alt+')));
        }
        expect(
          tester
              .getSemantics(_key('journal-section:$section'))
              .getSemanticsData()
              .hint,
          contains(
            'Optional global shortcut: ${journalSectionShortcuts[section]}',
          ),
        );
        expect(
          tester
              .getSemantics(_key('journal-section:$section'))
              .getSemanticsData()
              .label,
          startsWith(name),
        );
        expect(campaignSnapshot(), before);
      }
      await _altShortcut(tester, LogicalKeyboardKey.digit7);
      expect(engine.console.navigation?.section, 'agenda');
      await _altShortcut(tester, LogicalKeyboardKey.keyO);
      expect(find.text('Journal options'), findsOneWidget);
      expect(engine.console.screen, 'headquarters');
      await _altShortcut(tester, LogicalKeyboardKey.digit1);
      expect(_key('journal-member:${game.squad.first.id}'), findsOneWidget);
      expect(campaignSnapshot(), before);
      expect(List.generate(8, (_) => lcsRandom(100000)), rolls);
      expect(tester.takeException(), isNull);
    },
  );

  for (final (size, reading) in [
    (const Size(1280, 720), 1.0),
    (const Size(1024, 720), 1.5),
  ]) {
    testWidgets(
      'original LCS routes lead labels and retain reader meanings at $size/$reading',
      (tester) async {
        final harness = await mount(tester, size: size);
        journalReadingScale.value = reading;
        await _settle(tester);
        final before = campaignSnapshot();
        reseedRNG(seed: 20261021);
        final rolls = List.generate(8, (_) => lcsRandom(100000));
        reseedRNG(seed: 20261021);
        String badge(String key) => tester
            .widget<JournalShortcutBadge>(
              find.descendant(
                of: _key(key),
                matching: find.byType(JournalShortcutBadge),
              ),
            )
            .shortcut;
        Future<void> sourceKey(LogicalKeyboardKey key, String character) async {
          await _focusGame(tester);
          await tester.sendKeyEvent(key, character: character);
          await _settle(tester);
        }

        expect(badge('journal-section:3'), 'l');
        expect(journalShortcutLabel(badge('journal-section:3')), 'L');
        expect(badge('journal-section:4'), 'm');
        expect(badge('journal-section:1'), 'r → v');
        expect(badge('journal-section:9'), 'r → 0');
        expect(badge('journal-save-exit'), 'x');
        expect(badge('journal-advance-day'), 'w');
        for (final section in [0, 8, 10, 5, 6, 7]) {
          expect(
            find.descendant(
              of: _key('journal-section:$section'),
              matching: find.byType(JournalShortcutBadge),
            ),
            findsNothing,
          );
        }

        await sourceKey(LogicalKeyboardKey.keyL, 'l');
        expect(engine.console.navigation?.section, 'agenda');
        _insideViewport(
          tester,
          _key('journal-section:3'),
          size,
          'Original L reveals the selected Agenda tab',
        );
        expect(badge('journal-section:3'), 'HQ: l');
        expect(journalShortcutLabel(badge('journal-section:3')), 'HQ: L');
        expect(badge('journal-save-exit'), 'HQ: x');
        expect(badge('journal-advance-day'), 'HQ: w');
        final dispatched = List<int>.of(harness.dispatched);
        // The original Agenda reader treats W as Back. It must not become an HQ
        // day command just because the graphical footer also offers day advance.
        await sourceKey(LogicalKeyboardKey.keyW, 'w');
        expect(engine.console.screen, 'headquarters');
        expect(harness.dispatched, dispatched);
        expect(campaignSnapshot(), before);

        await sourceKey(LogicalKeyboardKey.keyM, 'm');
        expect(mediaOverviewFrame(engine.console), isNotNull);
        _insideViewport(
          tester,
          _key('journal-section:4'),
          size,
          'Original M reveals the selected Newspaper tab',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await _settle(tester);
        expect(engine.console.screen, 'headquarters');
        await sourceKey(LogicalKeyboardKey.keyR, 'r');
        expect(engine.console.screen, 'organisation');
        expect(badge('journal-section:1'), 'v');
        expect(badge('journal-section:9'), '0');
        await sourceKey(LogicalKeyboardKey.keyV, 'v');
        expect(ledgerReportFrame(engine.console)?.management, isTrue);
        await _tap(tester, 'journal-section:0');
        expect(engine.console.screen, 'headquarters');
        await sourceKey(LogicalKeyboardKey.keyR, 'r');
        await sourceKey(LogicalKeyboardKey.digit0, '0');
        expect(engine.console.screen, 'personnel-directory');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await _settle(tester);
        expect(engine.console.screen, 'organisation');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await _settle(tester);
        expect(engine.console.screen, 'headquarters');
        expect(campaignSnapshot(), before);
        expect(List.generate(8, (_) => lcsRandom(100000)), rolls);
        await sourceKey(LogicalKeyboardKey.keyX, 'x');
        expect(harness.dispatched.last, engine.Key.x);
        expect(campaignSnapshot(), before);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'modified footer commands safely leave Agenda before dispatching HQ keys',
    (tester) async {
      final harness = await mount(tester);
      final before = campaignSnapshot();
      await _altShortcut(tester, LogicalKeyboardKey.digit7);
      expect(engine.console.navigation?.section, 'agenda');
      final saveBadge = find.descendant(
        of: _key('journal-save-exit'),
        matching: find.byType(JournalShortcutBadge),
      );
      expect(
        find.descendant(
          of: _key('journal-save-exit'),
          matching: find.text('Save & exit'),
        ),
        findsOneWidget,
      );
      expect(tester.widget<JournalShortcutBadge>(saveBadge).shortcut, 'HQ: x');
      expect(
        tester.getSemantics(_key('journal-save-exit')).getSemanticsData().label,
        startsWith('Save & exit'),
      );
      await _altShortcut(tester, LogicalKeyboardKey.keyX);
      expect(harness.dispatched.last, engine.Key.x);
      expect(engine.console.screen, 'headquarters');
      expect(campaignSnapshot(), before);

      await _altShortcut(tester, LogicalKeyboardKey.digit7);
      expect(engine.console.navigation?.section, 'agenda');
      final dayBadge = find.descendant(
        of: _key('journal-advance-day'),
        matching: find.byType(JournalShortcutBadge),
      );
      expect(tester.widget<JournalShortcutBadge>(dayBadge).shortcut, 'HQ: w');
      expect(
        tester
            .getSemantics(_key('journal-advance-day'))
            .getSemanticsData()
            .label,
        startsWith('Wait a day'),
      );
      await _altShortcut(tester, LogicalKeyboardKey.keyW);
      expect(harness.dispatched.last, engine.Key.w);
      expect(engine.console.screen, 'headquarters');
      // This harness records the real HQ command without running a daily turn.
      expect(campaignSnapshot(), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a prepared order blocks Alt day advance and stale footer callbacks',
    (tester) async {
      final harness = await mount(tester);
      final before = campaignSnapshot();
      await business(tester);
      final retained = tester
          .widget<FilledButton>(_key('journal-advance-day'))
          .onPressed!;
      final beforePrepareRevision = engine.console.revision.value;
      await _tap(tester, 'journal-activity:donations');
      final revision = engine.console.revision.value;
      expect(revision, beforePrepareRevision);
      final dispatched = List<int>.of(harness.dispatched);
      await _altShortcut(tester, LogicalKeyboardKey.keyW);
      retained();
      await _settle(tester);
      expect(harness.dispatched, dispatched);
      expect(_key('journal-confirm-order'), findsOneWidget);
      expect(engine.console.revision.value, revision);
      expect(campaignSnapshot(), before);
      await _tap(tester, 'journal-cancel-order');
      await _altShortcut(tester, LogicalKeyboardKey.keyW);
      expect(harness.dispatched.last, engine.Key.w);
      expect(campaignSnapshot(), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('global chords cannot acknowledge a required monthly report', (
    tester,
  ) async {
    game.ledger.income[Income.donations] = 345;
    final harness = await mount(tester, monthlyReport: true);
    await _altShortcut(tester, LogicalKeyboardKey.keyW);
    expect(ledgerReportFrame(engine.console)?.management, isFalse);
    final before = campaignSnapshot();
    final revision = engine.console.revision.value;
    final dispatched = List<int>.of(harness.dispatched);
    for (final key in [
      LogicalKeyboardKey.keyW,
      LogicalKeyboardKey.keyX,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.keyO,
    ]) {
      await _altShortcut(tester, key);
    }
    expect(harness.monthReset, isFalse);
    expect(harness.dispatched, dispatched);
    expect(ledgerReportFrame(engine.console)?.management, isFalse);
    expect(engine.console.revision.value, revision);
    expect(campaignSnapshot(), before);
    expect(game.ledger.income[Income.donations], 345);
    expect(_key('journal-ledger-close').hitTestable(), findsOneWidget);
    await _tap(tester, 'journal-ledger-close');
    expect(harness.monthReset, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('search, edited names and read-only dialogs keep Alt chords', (
    tester,
  ) async {
    final harness = await mount(tester, size: const Size(1280, 900));
    final before = campaignSnapshot();
    await _altShortcut(tester, LogicalKeyboardKey.digit2);
    await tester.enterText(_key('personnel-search'), 'Felix');
    await _settle(tester);
    final searchRevision = engine.console.revision.value;
    final dispatched = List<int>.of(harness.dispatched);
    for (final key in [LogicalKeyboardKey.digit7, LogicalKeyboardKey.keyX]) {
      await _altShortcut(tester, key, focusGame: false);
    }
    expect(engine.console.screen, 'personnel-directory');
    expect(engine.console.revision.value, searchRevision);
    expect(
      tester.widget<TextField>(_key('personnel-search')).controller!.text,
      'Felix',
    );
    expect(harness.dispatched, dispatched);

    await _openPersonnel(tester, game.squad.first.id);
    await _tap(tester, 'journal-profile-action:n');
    expect(engine.console.textInput, isTrue);
    final nameField = find.byType(TextField);
    await tester.enterText(nameField, 'Edited but unconfirmed');
    final nameRevision = engine.console.revision.value;
    for (final key in [LogicalKeyboardKey.digit7, LogicalKeyboardKey.keyW]) {
      await _altShortcut(tester, key, focusGame: false);
    }
    expect(engine.console.textInput, isTrue);
    expect(engine.console.revision.value, nameRevision);
    expect(
      tester.widget<TextField>(nameField).controller!.text,
      'Edited but unconfirmed',
    );
    await tester.tap(find.widgetWithText(TextButton, 'Cancel edits'));
    await _settle(tester);
    expect(campaignSnapshot(), before);

    await _altShortcut(tester, LogicalKeyboardKey.digit1);
    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await _settle(tester);
    expect(find.text('A small movement. A long game.'), findsOneWidget);
    final dialogRevision = engine.console.revision.value;
    final dialogCommands = List<int>.of(harness.dispatched);
    for (final key in [
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.keyW,
      LogicalKeyboardKey.keyX,
    ]) {
      await _altShortcut(tester, key, focusGame: false);
    }
    expect(find.text('A small movement. A long game.'), findsOneWidget);
    expect(engine.console.revision.value, dialogRevision);
    expect(harness.dispatched, dialogCommands);
    expect(campaignSnapshot(), before);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(tester.takeException(), isNull);
  });

  for (final (size, reading) in [
    (const Size(1280, 720), 1.0),
    (const Size(1024, 720), 1.5),
  ]) {
    testWidgets('labelled journal shortcuts fit Agenda at $size/$reading', (
      tester,
    ) async {
      await mount(tester, size: size);
      journalReadingScale.value = reading;
      await _settle(tester);
      await _altShortcut(tester, LogicalKeyboardKey.digit7);
      expect(engine.console.navigation?.section, 'agenda');
      _insideViewport(
        tester,
        _key('journal-section:3'),
        size,
        'Selected Agenda tab',
      );
      _insideViewport(tester, _key('journal-save-exit'), size, 'Save & exit');
      _insideViewport(tester, _key('journal-advance-day'), size, 'Wait a day');
      for (final (key, shortcut, caption) in [
        ('journal-save-exit', 'HQ: x', 'Save & exit'),
        ('journal-advance-day', 'HQ: w', 'Wait a day'),
      ]) {
        final badge = find.descendant(
          of: _key(key),
          matching: find.byType(JournalShortcutBadge),
        );
        expect(badge, findsOneWidget);
        expect(tester.widget<JournalShortcutBadge>(badge).shortcut, shortcut);
        final label = find.descendant(
          of: _key(key),
          matching: find.text(caption),
        );
        expect(label, findsOneWidget);
        expect(label.hitTestable(), findsOneWidget);
        expect(
          tester.getSemantics(_key(key)).getSemanticsData().label,
          startsWith(caption),
        );
      }
      await _altShortcut(tester, LogicalKeyboardKey.keyO);
      expect(find.text('Journal options'), findsOneWidget);
      _insideViewport(
        tester,
        _key('journal-section:7'),
        size,
        'Selected Options tab',
      );
      expect(tester.takeException(), isNull);
    });
  }

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
      final before = campaignSnapshot();
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
      expect(
        tester
            .widget<TextButton>(_key('journal-member:${game.squad[1].id}'))
            .onPressed,
        isNull,
        reason: 'A required skill choice stays with its original actor.',
      );
      expect(person.activity, same(order));
      expect(campaignSnapshot(), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Clipboard finds hospitalized Chaz and returns to his searched category without changing campaign',
    (tester) async {
      final chaz = game.squad.first;
      chaz
        ..name = 'Chaz Reasoner'
        ..squad = null
        ..location = game.sites.firstWhere(
          (site) => site.type == SiteType.universityHospital,
        )
        ..medicalBills = 1360;
      await mount(tester, size: const Size(1280, 900));
      final before = campaignSnapshot();
      reseedRNG(seed: 28144);
      final rolls = List.generate(12, (_) => lcsRandom(100000));
      reseedRNG(seed: 28144);
      await _tap(tester, 'journal-clipboard');
      expect(_key('personnel-directory'), findsOneWidget);
      await _tap(tester, 'personnel-filter:active');
      expect(_key('personnel-person:${chaz.id}'), findsNothing);
      await tester.enterText(_key('personnel-search'), 'Chaz');
      await _settle(tester);
      expect(_key('personnel-person:${chaz.id}'), findsOneWidget);
      await _tap(tester, 'personnel-filter:hospital');
      await _openPersonnel(tester, chaz.id);
      expect(engine.console.journalProfile?.person.id, chaz.id);
      final close = _key('journal-profile-action:Enter');
      await tester.ensureVisible(close);
      await _settle(tester);
      await _tap(tester, 'journal-profile-action:Enter');
      expect(_key('personnel-directory'), findsOneWidget);
      expect(
        find.text('1 of ${game.pool.length} people · Hospital'),
        findsOneWidget,
      );
      expect(
        tester.widget<TextField>(_key('personnel-search')).controller!.text,
        'Chaz',
      );
      await tester.tap(_key('personnel-search'));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
      await _settle(tester);
      expect(engine.console.screen, 'personnel-directory');
      expect(campaignSnapshot(), before);
      expect(List.generate(12, (_) => lcsRandom(100000)), rolls);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'directory opens an off-page original person then resolves an earlier source page',
    (tester) async {
      final first = game.pool.first;
      Creature? last;
      for (var i = 0; i < 42; i++) {
        last = _extraPerson('Zed ${i.toString().padLeft(2, '0')}');
      }
      await mount(tester, size: const Size(1280, 900));
      final before = campaignSnapshot();
      await _tap(tester, 'journal-clipboard');
      await tester.enterText(_key('personnel-search'), last!.name);
      await _settle(tester);
      await _openPersonnel(tester, last.id);
      expect(engine.console.journalProfile?.person.id, last.id);
      await tester.ensureVisible(_key('journal-profile-action:Enter'));
      await _settle(tester);
      await _tap(tester, 'journal-profile-action:Enter');
      final scroll = find
          .descendant(
            of: _key('personnel-directory'),
            matching: find.byType(Scrollable),
          )
          .first;
      tester.state<ScrollableState>(scroll).position.jumpTo(0);
      await _settle(tester);
      await tester.enterText(_key('personnel-search'), first.name);
      await _settle(tester);
      await _openPersonnel(tester, first.id);
      expect(engine.console.journalProfile?.person.id, first.id);
      expect(campaignSnapshot(), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Roster tools retain original sorting and cancelled reorder with a clear return',
    (tester) async {
      await mount(tester, size: const Size(1280, 900));
      final before = campaignSnapshot();
      await _tap(tester, 'journal-clipboard');
      await _tap(tester, 'personnel-tools');
      expect(find.text('Sort & reorder crew'), findsOneWidget);
      final sort = engine.console.actions.firstWhere(
        (action) => action.key == 't',
      );
      await tester.ensureVisible(
        _key('direct-action:${sort.y}:${sort.x}:${sort.key}'),
      );
      await _settle(tester);
      await _tap(tester, 'direct-action:${sort.y}:${sort.x}:${sort.key}');
      expect(find.textContaining('Choose how to sort'), findsWidgets);
      engine.console.sendInput('Escape');
      await _settle(tester);
      await _tap(tester, 'personnel-back-directory');
      expect(_key('personnel-directory'), findsOneWidget);
      await _tap(tester, 'personnel-tools');
      final reorder = engine.console.actions.firstWhere(
        (action) => action.key == 'z',
      );
      await tester.ensureVisible(
        _key('direct-action:${reorder.y}:${reorder.x}:${reorder.key}'),
      );
      await _settle(tester);
      await _tap(
        tester,
        'direct-action:${reorder.y}:${reorder.x}:${reorder.key}',
      );
      expect(
        find.textContaining('Choose squad member to replace'),
        findsWidgets,
      );
      engine.console.sendInput('Escape');
      await _settle(tester);
      expect(engine.console.screen, 'organisation');
      await _focusGame(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit0, character: '0');
      await _settle(tester);
      expect(engine.console.screen, 'personnel-directory');
      await _tap(tester, 'personnel-back-directory');
      expect(_key('personnel-directory'), findsOneWidget);
      expect(campaignSnapshot(), before);
      expect(tester.takeException(), isNull);
    },
  );
}
