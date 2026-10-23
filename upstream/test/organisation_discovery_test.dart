import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/basemode/invest_in_location.dart';
import 'package:lcs_new_age/basemode/liberal_agenda.dart';
import 'package:lcs_new_age/common_actions/equipment.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/engine/base_management_context.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/engine/ledger_context.dart';
import 'package:lcs_new_age/engine/organisation_context.dart';
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/gamestate/ledger.dart';
import 'package:lcs_new_age/gamestate/squad.dart';
import 'package:lcs_new_age/items/item.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/siege.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/modern/journal_bases.dart';
import 'package:lcs_new_age/modern/journal_people.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/organisation_journal.dart';
import 'package:lcs_new_age/monthly/lcs_monthly.dart';
import 'package:lcs_new_age/politics/alignment.dart' as politics;
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/headquarters_test_harness.dart';
import 'test_support.dart';

/// The HQ dispatch boundary is controlled here; all order, promotion, profile,
/// allocation, media, investment and equipment readers are the original ones.
/// There is deliberately no automatic day advancement or player-save write.
class _DiscoveryHarness extends HeadquartersTestHarness {
  _DiscoveryHarness({this.onWait});

  final Future<void> Function()? onWait;

  @override
  Future<void> dispatch(int key) async {
    switch (key) {
      case engine.Key.w:
        await onWait?.call();
      case engine.Key.l:
        await liberalAgenda();
      case engine.Key.e:
        if (game.activeSquad?.members.isNotEmpty == true &&
            game.activeSquad?.site != null) {
          final previous = game.activeSquadMember;
          game.activeSquadMember = null;
          await equip(game.activeSquad?.site?.loot);
          game.activeSquadMember = previous;
        }
      case engine.Key.z:
        final bases = game.sites.where((site) => site.isSafehouse).toList();
        if (bases.isNotEmpty) {
          final index = bases.indexOf(game.activeSafehouse ?? bases.first);
          game.activeSquad = null;
          game.activeSafehouse = bases[(index + 1) % bases.length];
        }
      case engine.Key.i:
        final base = game.activeSafehouse;
        if (base != null && base.upgradable && !base.siege.underSiege) {
          await investInLocation(base);
        }
      default:
        await super.dispatch(key);
    }
  }

  /// Widget teardown pumps the source readers in its own fake-time zone.
  Future<void> stopWidgets(WidgetTester tester) async {
    stopped = true;
    for (var i = 0; i < 60 && !finished; i++) {
      if (engine.console.awaitingInput) {
        engine.console.sendInput(engine.console.textInput ? 'Enter' : 'Escape');
      }
      await tester.pump(const Duration(milliseconds: 5));
    }
    expect(finished, isTrue, reason: 'Original source readers must close.');
  }
}

Finder _key(String value) => find.byKey(ValueKey(value));
String _snapshot() => jsonEncode(game.gameState.toJson());

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  await tester.pumpAndSettle();
}

Future<void> _tapFinder(
  WidgetTester tester,
  Finder target, {
  String? reason,
}) async {
  expect(target, findsOneWidget, reason: reason);
  await tester.ensureVisible(target);
  await _settle(tester);
  expect(
    target.hitTestable(),
    findsOneWidget,
    reason: reason ?? 'The action must be reachable',
  );
  await tester.tap(target);
  await _settle(tester);
}

Future<void> _tap(WidgetTester tester, String value) =>
    _tapFinder(tester, _key(value), reason: value);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String fixture;
  late String template;

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
    template = jsonEncode(game.pool.first.toJson());
    final home = game.sites.firstWhere(
      (s) => s.type == SiteType.homelessEncampment,
    );
    for (final squad in game.squads) {
      squad.activity = Activity.none();
    }
    for (final person in game.pool.where((p) => p.isActiveLiberal)) {
      person
        ..location = home
        ..base = home
        ..activity = Activity.none();
    }
  });
  tearDown(() => journalReadingScale.value = 1);

  Creature addPerson(String name) {
    final person = Creature.fromJson(
      jsonDecode(template) as Map<String, dynamic>,
    );
    final home = game.sites.firstWhere(
      (s) => s.type == SiteType.homelessEncampment,
    );
    person
      ..id = game.gameState.nextCreatureId++
      ..name = name
      ..squadId = null
      ..hireId = null
      ..alive = true
      ..sleeperAgent = false
      ..align = game.pool.first.align
      ..seduced = false
      ..brainwashed = false
      ..hidingDaysLeft = 0
      ..vacationDaysLeft = 0
      ..location = home
      ..base = home
      ..juice = 1000
      ..activity = Activity.none();
    game.pool.add(person);
    return person;
  }

  Site addWarehouse(String name) {
    final base = Site.fromJson(
      jsonDecode(jsonEncode(organisationBases().first.toJson()))
          as Map<String, dynamic>,
    );
    base
      ..id = game.gameState.nextSiteId++
      ..name = name
      ..shortName = name
      ..frontName = null
      ..frontShortName = null
      ..type = SiteType.warehouse
      ..loot = []
      ..siege = Siege();
    base.district.sites.add(base);
    return base;
  }

  Future<_DiscoveryHarness> mount(
    WidgetTester tester, {
    Size size = const Size(1440, 1000),
    double scale = 1,
    Future<void> Function()? onWait,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    journalReadingScale.value = scale;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    final harness = _DiscoveryHarness(onWait: onWait);
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

  testWidgets(
    'first available person exposes order and squad actions without scrolling at 1280 by 720',
    (tester) async {
      final person = addPerson('A Available Recruit');
      final before = _snapshot();
      await mount(tester, size: const Size(1280, 720));
      await _tap(tester, 'journal-section:9');
      final filter = _key('personnel-filter:availableOutsideSquads');
      expect(filter.hitTestable(), findsOneWidget);
      await tester.tap(filter);
      await _settle(tester);
      // Neither action is revealed with ensureVisible or a list scroll. Their
      // complete touch areas must fit above the persistent journal footer.
      final assign = _key('personnel-assign-order:${person.id}');
      final join = _key('personnel-join-squad:${person.id}');
      final footerTop = tester.getTopLeft(_key('journal-save-exit')).dy;
      for (final action in [assign, join]) {
        expect(action.hitTestable(), findsOneWidget);
        expect(tester.getRect(action).bottom, lessThanOrEqualTo(footerTop));
      }
      expect(
        (tester.getCenter(_key('personnel-tools')).dy -
                tester.getCenter(_key('personnel-sort')).dy)
            .abs(),
        lessThan(1),
      );
      await tester.tap(assign);
      await _settle(tester);
      expect(activityOrderFrame(engine.console)?.actorId, person.id);
      expect(_snapshot(), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'People and Bases top tabs expose the complete directories without changing play',
    (tester) async {
      final person = addPerson('A New Recruit');
      final before = _snapshot();
      reseedRNG(seed: 901133);
      final rolls = List.generate(8, (_) => lcsRandom(100000));
      reseedRNG(seed: 901133);
      await mount(tester);
      await _tap(tester, 'journal-section:9');
      expect(find.byType(JournalPeopleView), findsOneWidget);
      expect(engine.console.screen, 'personnel-directory');
      await _tap(tester, 'personnel-filter:availableOutsideSquads');
      expect(_key('personnel-person:${person.id}'), findsOneWidget);
      expect(_key('personnel-assign-order:${person.id}'), findsOneWidget);
      expect(_key('personnel-join-squad:${person.id}'), findsOneWidget);
      await _tap(tester, 'journal-section:10');
      expect(find.byType(JournalBasesView), findsOneWidget);
      expect(find.text('Bases & Stores'), findsOneWidget);
      expect(_snapshot(), before);
      expect(List.generate(8, (_) => lcsRandom(100000)), rolls);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'People search leaves physical character keys to the text input system',
    (tester) async {
      await mount(tester);
      await _tap(tester, 'journal-section:9');
      final before = _snapshot();
      await _tap(tester, 'personnel-search');
      expect(
        await tester.sendKeyEvent(LogicalKeyboardKey.keyW, character: 'w'),
        isFalse,
      );
      expect(
        await tester.sendKeyEvent(LogicalKeyboardKey.keyR, character: 'r'),
        isFalse,
      );
      expect(engine.console.screen, 'personnel-directory');
      expect(_snapshot(), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'outside-squad orders select the exact actor and joining uses source allocation',
    (tester) async {
      final person = addPerson('A Unassigned Recruit');
      final other = addPerson('B Other Recruit');
      final before = _snapshot();
      await mount(tester);
      await _tap(tester, 'journal-section:9');
      await _tap(tester, 'personnel-filter:availableOutsideSquads');
      await _tap(tester, 'personnel-assign-order:${person.id}');
      expect(activityOrderFrame(engine.console)?.actorId, person.id);
      expect(find.text('Individual orders'), findsOneWidget);
      expect(_key('journal-member:${person.id}'), findsOneWidget);
      expect(_key('journal-member:${other.id}'), findsNothing);
      await _tap(tester, 'journal-activity:donations');
      expect(
        _key('journal-confirm-order'),
        findsOneWidget,
        reason:
            'Prepared=${tester.state<OrganisationJournalState>(find.byType(OrganisationJournal)).hasPreparedOrder}; source=${engine.console.screen}; actions=${engine.console.actions.map((a) => '${a.entityType}:${a.entityId}:${a.entityCategory}:${a.enabled}').join(', ')}',
      );
      expect(_snapshot(), before);
      await _tap(tester, 'journal-cancel-order');
      expect(person.activity.type, ActivityType.none);
      await _tap(tester, 'journal-section:9');
      await _tap(tester, 'personnel-join-squad:${person.id}');
      expect(squadAllocationFrame(engine.console), isNotNull);
      expect(person.squadId, isNull);
      await _tap(tester, 'journal-transfer:${person.id}');
      expect(person.squadId, game.activeSquad?.id);
      expect(person.squadId, isNotNull);
      expect(other.squadId, isNull);
      expect(other.activity.type, ActivityType.none);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'People retains source roster tools and equipment access from the directory and profile',
    (tester) async {
      final team = game.activeSquad!;
      final member = team.members.first;
      final weapons = team.members.map((p) => p.equippedWeapon).toList();
      await mount(tester);
      await _tap(tester, 'journal-section:9');
      await _tap(tester, 'personnel-tools');
      expect(_key('personnel-back-directory'), findsOneWidget);
      final sort = engine.console.actions.singleWhere(
        (a) => a.key == 't' && a.label.contains('Sort Liberals'),
      );
      await _tap(tester, 'direct-action:${sort.y}:${sort.x}:${sort.key}');
      expect(find.textContaining('Choose how to sort'), findsWidgets);
      engine.console.sendInput('Escape');
      await _settle(tester);
      await _tap(tester, 'personnel-back-directory');
      expect(find.byType(JournalPeopleView), findsOneWidget);
      await _tap(tester, 'journal-equipment');
      expect(engine.console.navigation?.section, 'equipment');
      expect(game.activeSquad, same(team));
      await _tap(tester, 'journal-section:9');
      await _tap(tester, 'personnel-person:${member.id}');
      expect(engine.console.journalProfile?.person.id, member.id);
      await _tap(tester, 'journal-equipment');
      expect(engine.console.navigation?.section, 'equipment');
      expect(game.activeSquad, same(team));
      for (var i = 0; i < weapons.length; i++) {
        expect(team.members[i].equippedWeapon, same(weapons[i]));
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'off-page promotion cancel and confirm retain the exact source person',
    (tester) async {
      final founder = game.pool.first
        ..juice = 1000
        ..hireId = null;
      final contact = addPerson('Z Contact')..hireId = founder.id;
      for (var i = 0; i < 23; i++) {
        addPerson('Recruit $i').hireId = contact.id;
      }
      final target = game.pool.last..name = 'A Selected Recruit';
      final before = _snapshot();
      await mount(tester);
      await _tap(tester, 'journal-section:9');
      await _tap(tester, 'people-scope:leadership');
      await _tap(tester, 'leadership-promote:${target.id}');
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(engine.console.screen, 'leadership');
      expect(
        engine.console.actions.any(
          (a) =>
              a.entityType == 'promotion-person' &&
              a.entityId == target.id.toString(),
        ),
        isTrue,
      );
      expect(_snapshot(), before);
      await _tapFinder(tester, find.widgetWithText(TextButton, 'Cancel'));
      expect(target.hireId, contact.id);
      expect(_snapshot(), before);
      await _tap(tester, 'leadership-promote:${target.id}');
      await _tapFinder(tester, find.widgetWithText(FilledButton, 'Promote'));
      expect(target.hireId, founder.id);
      expect(
        game.pool
            .where((p) => p.hireId == founder.id && p.id != target.id)
            .map((p) => p.id),
        contains(contact.id),
      );
      expect(engine.console.screen, 'personnel-directory');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'captive staffing drafts an order and preserves the required target picker',
    (tester) async {
      final tender = addPerson('A Tender');
      final captive = addPerson('B Captive');
      final secondCaptive = addPerson('C Captive');
      // Explicit fixture setup: the source tending reader accepts Conservatives.
      captive.align = secondCaptive.align = politics.Alignment.conservative;
      final before = _snapshot();
      await mount(tester);
      await _tap(tester, 'journal-section:9');
      await _tap(tester, 'people-scope:captives');
      await _tap(tester, 'captive-staff:${captive.id}');
      await _tap(tester, 'captive-choose-tender:${captive.id}:${tender.id}');
      expect(activityOrderFrame(engine.console)?.actorId, tender.id);
      expect(_key('journal-confirm-order'), findsOneWidget);
      expect(_snapshot(), before);
      await _tap(tester, 'journal-confirm-order');
      expect(engine.console.awaitingInput, isTrue);
      expect(activityOrderFrame(engine.console), isNull);
      expect(find.textContaining('Which hostage will'), findsWidgets);
      expect(tender.activity.type, ActivityType.none);
      expect(_snapshot(), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Newspaper Production prepares writing for its selected source actor',
    (tester) async {
      final writer = addPerson('Z Selected Writer');
      final before = _snapshot();
      await mount(tester);
      await _tap(tester, 'journal-section:4');
      await _tap(tester, 'media-production-tab');
      await _tap(tester, 'media-production-person');
      await _tapFinder(tester, find.text(writer.name).last);
      await _tap(tester, 'media-production-assign:writeGuardian');
      expect(activityOrderFrame(engine.console)?.actorId, writer.id);
      expect(
        _key('journal-confirm-order'),
        findsOneWidget,
        reason:
            'Prepared=${tester.state<OrganisationJournalState>(find.byType(OrganisationJournal)).hasPreparedOrder}; source=${engine.console.screen}; actions=${engine.console.actions.map((a) => '${a.entityType}:${a.entityId}:${a.entityCategory}:${a.enabled}').join(', ')}',
      );
      expect(_snapshot(), before);
      await _tap(tester, 'journal-confirm-order');
      expect(writer.activity.type, ActivityType.writeGuardian);
      expect(
        game.pool
            .where((p) => p.id != writer.id)
            .every((p) => p.activity.type == ActivityType.none),
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'day command from Newspaper returns to Organisation after the controller finishes',
    (tester) async {
      final harness = await mount(tester);
      await _tap(tester, 'journal-section:4');
      await _tap(tester, 'media-production-tab');
      expect(
        tester
            .widget<OrganisationJournal>(find.byType(OrganisationJournal))
            .section,
        4,
      );
      expect(engine.console.screen, 'media-archive');
      await _tap(tester, 'journal-advance-day');
      expect(
        harness.dispatched.where((key) => key == engine.Key.w),
        hasLength(1),
      );
      expect(engine.console.screen, 'headquarters');
      expect(
        tester
            .widget<OrganisationJournal>(find.byType(OrganisationJournal))
            .section,
        0,
      );
      expect(_key('journal-team-name'), findsOneWidget);
      expect(_key('journal-crew-list'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'return to Organisation waits for the real required month-end reader',
    (tester) async {
      final harness = await mount(
        tester,
        onWait: () async {
          // The daily simulation is outside this UI harness; its monthly report is
          // the real required source reader, with the date already advanced.
          game.gameState.date = DateTime(2023, 2, 1);
          game.ledger.income[Income.donations] = 345;
          await fundReport(false);
          game.ledger.resetMonthlyAmounts();
        },
      );
      await _tap(tester, 'journal-section:4');
      await _tap(tester, 'media-production-tab');
      await _tap(tester, 'journal-advance-day');
      expect(
        harness.dispatched.where((key) => key == engine.Key.w),
        hasLength(1),
      );
      expect(ledgerReportFrame(engine.console)!.management, isFalse);
      expect(
        tester
            .widget<OrganisationJournal>(find.byType(OrganisationJournal))
            .section,
        1,
      );
      expect(
        find.text('January 2023 · month-end financial report'),
        findsOneWidget,
      );
      expect(_key('journal-ledger-close').hitTestable(), findsOneWidget);
      expect(game.ledger.income[Income.donations], 345);
      await _tap(tester, 'journal-ledger-close');
      expect(engine.console.screen, 'headquarters');
      expect(
        tester
            .widget<OrganisationJournal>(find.byType(OrganisationJournal))
            .section,
        0,
      );
      expect(_key('journal-team-name'), findsOneWidget);
      expect(game.ledger.income[Income.donations], 0);
      expect(
        harness.dispatched.where((key) => key == engine.Key.w),
        hasLength(1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'explicit HQ chapters and custom management tabs survive their intended routes',
    (tester) async {
      final harness = await mount(tester);
      for (final section in [
        5,
        6,
        7,
        networkJournalSection,
        peopleJournalSection,
        basesJournalSection,
      ]) {
        await _tap(tester, 'journal-section:4');
        expect(engine.console.screen, 'media-archive');
        await _tap(tester, 'journal-section:$section');
        expect(
          tester
              .widget<OrganisationJournal>(find.byType(OrganisationJournal))
              .section,
          section,
        );
      }
      // Custom management chapters stay selected when their own original source
      // readers return to HQ as part of carrying out a day command.
      for (final section in [
        networkJournalSection,
        peopleJournalSection,
        basesJournalSection,
      ]) {
        await _tap(tester, 'journal-section:$section');
        await _tap(tester, 'journal-advance-day');
        expect(engine.console.screen, 'headquarters');
        expect(
          tester
              .widget<OrganisationJournal>(find.byType(OrganisationJournal))
              .section,
          section,
        );
      }
      expect(
        harness.dispatched.where((key) => key == engine.Key.w),
        hasLength(3),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Bases stages and confirms the original purchase and moves stored stock',
    (tester) async {
      final source = addWarehouse('A Upgrade Warehouse');
      final destination = addWarehouse('B Destination Warehouse');
      final stock = Item('WEAPON_22_REVOLVER');
      source.loot.add(stock);
      game.ledger.forceSetFunds(5000);
      final harness = await mount(tester);
      await _tap(tester, 'journal-section:10');
      await _tapFinder(
        tester,
        find.text(source.getName(includeCity: true)).first,
      );
      await _tapFinder(
        tester,
        find.widgetWithText(OutlinedButton, 'Buy supplies & improve base'),
      );
      expect(engine.console.screen, 'base-investment');
      expect(game.activeSafehouse, source);
      final rations = source.compound.rations;
      final funds = game.ledger.funds;
      final beforePurchase = _snapshot();
      final originalDate = game.date;
      final retainedAdvance = tester
          .widget<FilledButton>(_key('journal-advance-day'))
          .onPressed!;
      final retainedCommands = tester
          .widget<TextButton>(_key('journal-more-commands'))
          .onPressed!;
      reseedRNG(seed: 181006);
      final rolls = List.generate(8, (_) => lcsRandom(100000));
      reseedRNG(seed: 181006);
      final rationAction = engine.console.actions.singleWhere(
        (a) => a.entityType == 'base-supplies' && a.entityId == 'rations',
      );
      final label = stripConsoleColors(rationAction.label)
          .replaceFirst(RegExp(r'^\S+\s*-\s*'), '');
      await _tapFinder(tester, find.widgetWithText(OutlinedButton, label));
      expect(source.compound.rations, rations);
      expect(game.ledger.funds, funds);
      expect(find.text('Confirm or cancel draft'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(_key('journal-advance-day')).onPressed,
        isNull,
      );
      expect(
        tester.widget<TextButton>(_key('journal-more-commands')).onPressed,
        isNull,
      );
      retainedAdvance();
      retainedCommands();
      await _settle(tester);
      expect(engine.console.screen, 'base-investment');
      expect(find.byType(PopupMenuItem<ConsoleAction>), findsNothing);
      expect(
        find.widgetWithText(FilledButton, 'Confirm purchase'),
        findsOneWidget,
      );
      expect(harness.dispatched, isNot(contains(engine.Key.w)));
      expect(game.date, originalDate);
      expect(_snapshot(), beforePurchase);
      expect(List.generate(8, (_) => lcsRandom(100000)), rolls);
      await _tapFinder(tester, find.widgetWithText(TextButton, 'Cancel'));
      expect(find.text('Confirm or cancel draft'), findsNothing);
      expect(
        tester.widget<FilledButton>(_key('journal-advance-day')).onPressed,
        isNotNull,
      );
      expect(
        tester.widget<TextButton>(_key('journal-more-commands')).onPressed,
        isNotNull,
      );
      expect(_snapshot(), beforePurchase);
      await _tapFinder(tester, find.widgetWithText(OutlinedButton, label));
      expect(find.text('Confirm or cancel draft'), findsOneWidget);
      await _tapFinder(
        tester,
        find.widgetWithText(FilledButton, 'Confirm purchase'),
      );
      expect(source.compound.rations, rations + 20);
      expect(game.ledger.funds, funds - 150);
      expect(game.date, originalDate);
      expect(find.text('Confirm or cancel draft'), findsNothing);
      expect(
        tester.widget<FilledButton>(_key('journal-advance-day')).onPressed,
        isNotNull,
      );
      await _tapFinder(tester, find.text('Done purchasing'));
      await _tapFinder(
        tester,
        find.widgetWithText(OutlinedButton, 'Move equipment between bases'),
      );
      expect(engine.console.screen, 'equipment-transfer');
      final destinationAction = engine.console.actions.singleWhere(
        (a) =>
            a.entityType?.startsWith('equipment-transfer-destination') ==
                true &&
            a.entityId == destination.idString,
      );
      final destinationLabel = stripConsoleColors(destinationAction.label)
          .replaceFirst(RegExp(r'^\S+\s*-\s*'), '');
      await _tapFinder(
        tester,
        find.widgetWithText(ChoiceChip, destinationLabel),
      );
      await _tapFinder(
        tester,
        find.widgetWithText(OutlinedButton, 'Move stack'),
      );
      expect(source.loot, isEmpty);
      expect(destination.loot, contains(same(stock)));
      expect(game.ledger.funds, funds - 150);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'observed return persists a People badge until Keep resting is chosen',
    (tester) async {
      final returning = addPerson('Returned Crew')..sleeperAgent = true;
      await mount(tester, size: const Size(1024, 720), scale: 1.5);
      // Explicit simulated event fixture. A fresh awaited HQ frame is published
      // through the same source boundary the real end-of-day handler returns to.
      returning.sleeperAgent = false;
      game.gameState.date = game.date.add(const Duration(days: 1));
      engine.console.sendInput('Escape');
      await _settle(tester);
      expect(
        find.descendant(
          of: _key('journal-section:9'),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      await _tap(tester, 'journal-section:9');
      expect(find.textContaining('Sleeper recalled'), findsOneWidget);
      expect(find.text('1 change to review'), findsOneWidget);
      await _tap(tester, 'journal-section:10');
      await _tap(tester, 'journal-section:9');
      expect(find.textContaining('Sleeper recalled'), findsOneWidget);
      final before = _snapshot();
      await _tapFinder(tester, find.text('Keep resting'));
      expect(find.textContaining('Sleeper recalled'), findsNothing);
      expect(
        find.descendant(
          of: _key('journal-section:9'),
          matching: find.text('1'),
        ),
        findsNothing,
      );
      expect(_snapshot(), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'three persisted review notices keep expansion and scroll storage separate',
    (tester) async {
      final visitors = Squad()..name = 'Returning visitors';
      game.squads.add(visitors);
      for (var i = 1; i <= 3; i++) {
        addPerson('Returning visitor $i').squad = visitors;
      }
      final destination = game.sites.firstWhere(
        (site) => site.type == SiteType.departmentStore,
      );
      visitors.activity = Activity(
        ActivityType.visit,
        idString: destination.idString,
      );
      await mount(tester);
      visitors.activity = Activity.none();
      game.gameState.date = game.date.add(const Duration(days: 1));
      engine.console.sendInput('Escape');
      await _settle(tester);
      final controller = tester
          .widget<OrganisationJournal>(find.byType(OrganisationJournal))
          .controller;
      expect(controller.organisationReviews.notices, hasLength(3));
      final preferences = await SharedPreferences.getInstance();
      final saved = jsonDecode(
        preferences.getString(
          'organisationReview.v1.${game.gameState.uniqueGameId}',
        )!,
      ) as Map<String, dynamic>;
      expect(saved['notices'], hasLength(3));
      final before = _snapshot();
      reseedRNG(seed: 181008);
      final rolls = List.generate(8, (_) => lcsRandom(100000));
      reseedRNG(seed: 181008);

      await _tap(tester, 'journal-section:9');
      final changes = find.text('3 changes to review');
      await _tapFinder(tester, changes);
      expect(tester.takeException(), isNull);
      final reviewList = find.byKey(
        const PageStorageKey('people-changes-review-list'),
      );
      expect(reviewList, findsOneWidget);
      final reviewScroll = find.descendant(
        of: reviewList,
        matching: find.byType(Scrollable),
      );
      await tester.drag(reviewList, const Offset(0, -130));
      await _settle(tester);
      final offset = tester
          .state<ScrollableState>(reviewScroll)
          .position
          .pixels;
      expect(offset, greaterThan(0));
      await _tapFinder(tester, changes);
      await _tap(tester, 'journal-section:10');
      await _tap(tester, 'journal-section:9');
      expect(reviewList, findsNothing);
      await _tapFinder(tester, changes);
      expect(tester.takeException(), isNull);
      expect(
        tester.state<ScrollableState>(reviewScroll).position.pixels,
        closeTo(offset, .1),
      );
      await _tap(tester, 'journal-section:10');
      await _tap(tester, 'journal-section:9');
      expect(reviewList, findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(
        tester.state<ScrollableState>(reviewScroll).position.pixels,
        closeTo(offset, .1),
      );

      // A new app/controller reads the persisted notices, while its fresh
      // route storage starts collapsed and remains safe to expand again.
      await _tap(tester, 'journal-section:0');
      expect(engine.console.screen, 'headquarters');
      await tester.pumpWidget(const SizedBox.shrink());
      await _settle(tester);
      await tester.pumpWidget(const MainApp());
      await _settle(tester);
      await _tap(tester, 'journal-section:9');
      expect(changes, findsOneWidget);
      await _tapFinder(tester, changes);
      expect(reviewList, findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(_snapshot(), before);
      expect(List.generate(8, (_) => lcsRandom(100000)), rolls);
    },
  );

  testWidgets(
    'all eleven top tabs remain reachable at 1024 by 720 and 150 percent',
    (tester) async {
      await mount(tester, size: const Size(1024, 720), scale: 1.5);
      for (final section in [0, 9, 8, 10, 1, 2, 3, 4, 5, 6, 7]) {
        await _tap(tester, 'journal-section:$section');
        expect(
          tester.takeException(),
          isNull,
          reason: 'Section $section must fit',
        );
      }
    },
  );
}
