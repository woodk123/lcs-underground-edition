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
import 'package:lcs_new_age/modern/journal_city_plan.dart';
import 'package:lcs_new_age/modern/journal_ledger.dart';
import 'package:lcs_new_age/modern/journal_media.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/mechanics_help.dart';
import 'package:lcs_new_age/modern/organisation_journal.dart';
import 'package:lcs_new_age/modern/personnel_directory.dart';
import 'package:lcs_new_age/monthly/lcs_monthly.dart';
import 'package:lcs_new_age/newspaper/news_story.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

/// The base dispatch boundary with real source-authored options and real
/// management handlers. It never advances time during these UI tests.
class _JournalHarness {
  _JournalHarness({this.monthlyReport = false, this.shopVisit = false}) {
    done = _loop();
  }
  late final Future<void> done;
  bool stopped = false;
  bool finished = false;
  final bool monthlyReport;
  final bool shopVisit;
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
    bool shopVisit = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    final harness = _JournalHarness(
      monthlyReport: monthlyReport,
      shopVisit: shopVisit,
    );
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

  for (final size in [const Size(2200, 1200), const Size(800, 600)]) {
    testWidgets('Clipboard and equipment use journal pages at $size', (
      tester,
    ) async {
      await mount(tester, size: size);
      if (size.width == 800) {
        await tester.tap(find.byTooltip('Reading size'));
        await _settle(tester);
        await tester.tap(find.text('150%'));
        await _settle(tester);
      }
      final before = _snapshot();
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
      expect(_snapshot(), before);
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
      await mount(tester, size: const Size(800, 600));
      await tester.tap(find.byTooltip('Reading size'));
      await _settle(tester);
      await tester.tap(find.text('150%'));
      await _settle(tester);
      final before = _snapshot();
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
        expect(_snapshot(), before);
      }
      await _tap(tester, 'journal-profile-action:n');
      expect(engine.console.textInput, isTrue);
      await tester.enterText(find.byType(TextField), person.name);
      await tester.tap(find.text('Confirm text'));
      await _settle(tester);
      expect(engine.console.textInput, isFalse);
      expect(_snapshot(), before);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(2200, 1200), const Size(800, 600)]) {
    testWidgets(
      'left crew selection retains profile page and scroll at $size',
      (tester) async {
        await mount(tester, size: size);
        if (size.width == 800) {
          await tester.tap(find.byTooltip('Reading size'));
          await _settle(tester);
          await tester.tap(find.text('150%'));
          await _settle(tester);
        }
        await _tap(tester, 'journal-clipboard');
        final first = game.squad.first;
        final second = game.squad[1];
        await _openPersonnel(tester, first.id);
        final before = _snapshot();
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
            closeTo(offset, .01),
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
        expect(_snapshot(), before);
        expect(List.generate(10, (_) => lcsRandom(100000)), rolls);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'equipment follows left selection without dispatch or scroll reset at $size',
      (tester) async {
        await mount(tester, size: size);
        if (size.width == 800) {
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
        final before = _snapshot();
        final revision = engine.console.revision.value;
        final scroll = find.descendant(
          of: find.byKey(
            const PageStorageKey('journal-management-scroll:equipment'),
          ),
          matching: find.byType(Scrollable),
        );
        final position = tester.state<ScrollableState>(scroll).position;
        final offset = position.maxScrollExtent.clamp(0, 90).toDouble();
        position.jumpTo(offset);
        await _settle(tester);
        reseedRNG(seed: 29471);
        final rolls = List.generate(10, (_) => lcsRandom(100000));
        reseedRNG(seed: 29471);
        await tester.ensureVisible(_key('journal-member:${second.id}'));
        await _settle(tester);
        await _tap(tester, 'journal-member:${second.id}');
        expect(
          tester
              .widget<Semantics>(_key('journal-person-row:${second.id}'))
              .properties
              .selected,
          isTrue,
        );
        expect(
          tester
              .widget<Semantics>(
                _key('journal-person-row:${game.squad.first.id}'),
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
        expect(_snapshot(), before);
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
    final before = _snapshot();
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
    expect(_snapshot(), before);
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
              _key('journal-person-row:${original.members.first.id}'),
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

  for (final size in [const Size(1280, 720), const Size(800, 600)]) {
    testWidgets(
      'City maps prepares the selected squad visit before source confirmation at $size',
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
        final before = _snapshot();
        final originalDate = game.date;
        final originalOrder = team.activity;
        final harness = await mount(tester, size: size);
        if (size.width == 800) {
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
        expect(_snapshot(), before);
        expect(
          tester.widget<Text>(_key('journal-city-map-squad')).data,
          'Squad: ${team.name}',
        );
        _insideViewport(
          tester,
          _key('journal-city-map-prepare-visit'),
          size,
          'Prepare the selected squad visit',
        );
        await _tap(tester, 'journal-city-map-prepare-visit');
        expect(engine.console.screen, 'planning');
        expect(
          engine.console.actions.any(
            (action) =>
                action.entityType == 'site' &&
                action.entityId == destination.idString &&
                action.enabled,
          ),
          isTrue,
        );
        expect(_key('journal-confirm-order'), findsOneWidget);
        expect(find.text('Confirm or cancel draft'), findsOneWidget);
        expect(
          tester.widget<FilledButton>(_key('journal-advance-day')).onPressed,
          isNull,
        );
        expect(_snapshot(), before);
        await _tap(tester, 'journal-cancel-order');
        expect(engine.console.screen, 'headquarters');
        expect(
          tester
              .widget<OrganisationJournal>(find.byType(OrganisationJournal))
              .section,
          6,
          reason: 'Cancelling the draft must retain its City maps origin.',
        );
        expect(_snapshot(), before);
        expect(find.text('Confirm or cancel draft'), findsNothing);
        await _tap(tester, 'journal-city-map-prepare-visit');
        expect(_snapshot(), before);
        team.activity = Activity(
          ActivityType.visit,
          idString: destination.idString,
        );
        final queued = _snapshot();
        team.activity = originalOrder;
        await _tap(tester, 'journal-confirm-order');
        expect(team.activity.type, ActivityType.visit);
        expect(
          tester
              .widget<OrganisationJournal>(find.byType(OrganisationJournal))
              .section,
          6,
          reason: 'Confirming a map visit must retain the City maps context.',
        );
        expect(team.activity.idString, destination.idString);
        expect(other.activity.type, ActivityType.none);
        expect(game.activeSquad, same(team));
        expect(_snapshot(), queued);
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
      expect(engine.console.screen, 'activity-orders');
      expect(activityOrderFrame(engine.console)?.selectedCategoryKey, 'b');
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
      expect(engine.console.screen, 'activity-orders');
      expect(activityOrderFrame(engine.console)?.actorId, selected.id);
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

  for (final size in [const Size(1280, 720), const Size(800, 600)]) {
    testWidgets(
      'member changes retain nested category and map state at $size',
      (tester) async {
        await mount(tester, size: size);
        if (size.width == 800) {
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
        final before = _snapshot();
        final districtId = game.activeSquad!.site!.district.idString;
        await _tap(tester, 'journal-map-place:$districtId');
        final mapState = tester.state(find.byType(JournalCityPlan));
        final viewer = tester.widget<InteractiveViewer>(
          find.byType(InteractiveViewer),
        );
        viewer.transformationController!.value = Matrix4.identity()
          ..scaleByDouble(1.4, 1.4, 1, 1);
        await tester.tap(find.byTooltip('Show location index'));
        await _settle(tester);
        await _tap(tester, 'journal-activity:teachLiberalArts');
        await tester.ensureVisible(_key('journal-member:${next.id}'));
        await _settle(tester);
        await tester.tap(_key('journal-member:${next.id}'));
        for (var frame = 0; frame < 80; frame++) {
          await tester.pump(const Duration(milliseconds: 1));
          expect(tester.state(find.byType(JournalCityPlan)), same(mapState));
          expect(_key('journal-location-index'), findsOneWidget);
        }
        await _settle(tester);
        expect(activityOrderFrame(engine.console)?.actorId, next.id);
        expect(activityOrderFrame(engine.console)?.selectedCategoryKey, 't');
        expect(
          _key('journal-activity:teachLiberalArts').hitTestable(),
          findsOneWidget,
        );
        expect(_key('journal-confirm-order'), findsNothing);
        expect(tester.state(find.byType(JournalCityPlan)), same(mapState));
        expect(_key('journal-location-index'), findsOneWidget);
        expect(viewer.transformationController!.value.entry(0, 0), 1.4);
        await tester.tap(find.byTooltip('Show city plan'));
        await _settle(tester);
        final third = game.squad[2];
        await tester.ensureVisible(_key('journal-member:${third.id}'));
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
        expect(_snapshot(), before);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('switching members retains the scrolled task list', (
    tester,
  ) async {
    await mount(tester, size: const Size(800, 600));
    await tester.tap(find.byTooltip('Reading size'));
    await _settle(tester);
    await tester.tap(find.text('150%'));
    await _settle(tester);
    await business(tester);
    final list = find.byKey(const PageStorageKey('journal-tasks:0:legal'));
    final scroll = find.descendant(of: list, matching: find.byType(Scrollable));
    await tester.drag(list, const Offset(0, -160));
    await _settle(tester);
    final offset = tester.state<ScrollableState>(scroll).position.pixels;
    expect(offset, greaterThan(0));
    final next = game.squad[1];
    await tester.ensureVisible(_key('journal-member:${next.id}'));
    await _settle(tester);
    await _tap(tester, 'journal-member:${next.id}');
    expect(
      tester.state<ScrollableState>(scroll).position.pixels,
      closeTo(offset, .01),
    );
    expect(tester.takeException(), isNull);
  });

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
    final before = _snapshot();
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
    priorConfirm();
    await _settle(tester);
    expect(
      _snapshot(),
      before,
      reason:
          'Even a captured confirmation cannot apply the previous actor’s draft.',
    );
    expect(tester.takeException(), isNull);
  });

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
      final before = jsonDecode(_snapshot()) as Map<String, dynamic>;
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
      final after = jsonDecode(_snapshot()) as Map<String, dynamic>;
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
      expect(engine.console.screen, 'activity-orders');
      expect(activityOrderFrame(engine.console)?.selectedCategoryKey, 'b');
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(1280, 720), const Size(800, 700)]) {
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
        final beforeTabScroll = _snapshot();
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
        expect(_snapshot(), beforeTabScroll);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'order formulas are disclosed on request without changing assignments, input or RNG',
    (tester) async {
      await mount(tester, size: const Size(800, 600));
      await business(tester);
      await _tap(tester, 'journal-activity:donations');
      await tester.tap(find.byTooltip('Reading size'));
      await _settle(tester);
      await tester.tap(find.text('150%'));
      await _settle(tester);
      final before = _snapshot();
      final revision = engine.console.revision.value;
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
        expect(MediaQuery.textScalerOf(tester.element(dialog)).scale(10), 15);
        expect(_snapshot(), before);
        expect(engine.console.revision.value, revision);
        if (dismissWithEscape) {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        } else {
          await tester.tap(find.text('Close'));
        }
        await _settle(tester);
        expect(dialog, findsNothing);
        expect(find.text(formula), findsNothing);
        expect(_key('journal-confirm-order').hitTestable(), findsOneWidget);
        expect(_snapshot(), before);
        expect(engine.console.revision.value, revision);
      }
      expect(List.generate(8, (_) => lcsRandom(100000)), rolls);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a prepared personal order blocks day and HQ shortcuts until cancel or confirm',
    (tester) async {
      final harness = await mount(tester);
      final actor = game.squad.first;
      final originalOrder = actor.activity;
      final before = _snapshot();
      final originalDate = game.date;
      final retainedAdvance = tester
          .widget<FilledButton>(_key('journal-advance-day'))
          .onPressed!;
      final retainedCommands = tester
          .widget<IconButton>(_key('journal-more-commands'))
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
        tester.widget<IconButton>(_key('journal-more-commands')).onPressed,
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
      expect(_snapshot(), before);
      expect(game.date, originalDate);
      expect(List.generate(8, (_) => lcsRandom(100000)), rolls);

      await _tap(tester, 'journal-cancel-order');
      expect(find.text('Confirm or cancel draft'), findsNothing);
      expect(
        tester.widget<FilledButton>(_key('journal-advance-day')).onPressed,
        isNotNull,
      );
      expect(_snapshot(), before);
      await _tap(tester, 'journal-activity:donations');
      expect(find.text('Confirm or cancel draft'), findsOneWidget);
      actor.activity = Activity(ActivityType.donations);
      final confirmed = _snapshot();
      actor.activity = originalOrder;
      await _tap(tester, 'journal-confirm-order');
      expect(_snapshot(), confirmed);
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
      expect(
        find.descendant(
          of: _key('journal-ledger-close'),
          matching: find.text('Continue'),
        ),
        findsOneWidget,
      );
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
      expect(
        tester
            .widget<TextButton>(_key('journal-member:${game.squad[1].id}'))
            .onPressed,
        isNull,
        reason: 'A required skill choice stays with its original actor.',
      );
      expect(person.activity, same(order));
      expect(_snapshot(), before);
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
      final before = _snapshot();
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
      expect(_snapshot(), before);
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
      final before = _snapshot();
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
      expect(_snapshot(), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Roster tools retain original sorting and cancelled reorder with a clear return',
    (tester) async {
      await mount(tester, size: const Size(1280, 900));
      final before = _snapshot();
      await _tap(tester, 'journal-clipboard');
      await _tap(tester, 'personnel-tools');
      expect(find.text('Roster tools'), findsOneWidget);
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
      await _tap(tester, 'personnel-back-directory');
      expect(_key('personnel-directory'), findsOneWidget);
      expect(_snapshot(), before);
      expect(tester.takeException(), isNull);
    },
  );
}
