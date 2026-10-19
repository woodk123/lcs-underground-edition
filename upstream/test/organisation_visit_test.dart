import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activate_regulars.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/basemode/base_mode.dart';
import 'package:lcs_new_age/basemode/plan_site_visit.dart';
import 'package:lcs_new_age/basemode/review_mode.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/siege.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/location_details.dart';
import 'package:lcs_new_age/modern/location_effects.dart';
import 'package:lcs_new_age/modern/location_help.dart';
import 'package:lcs_new_age/modern/travel_help.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/sitemode/sitemap.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';
import 'package:lcs_new_age/vehicles/vehicle.dart';
import 'package:lcs_new_age/vehicles/vehicle_type.dart';

import 'test_support.dart';

class _VisitHarness {
  _VisitHarness() {
    done = _loop();
  }
  late final Future<void> done;
  bool stopped = false, finished = false;
  final commands = <int>[];
  Future<void> _loop() async {
    try {
      while (!stopped) {
        engine.erase();
        final location = game.activeSquad?.site ?? game.activeSafehouse;
        baseModeSquadSafehouseDisplay(location);
        baseModeOptionsDisplay(location);
        final key = await engine.getKey();
        if (stopped) break;
        commands.add(key);
        switch (key) {
          case engine.Key.a:
            await activateRegulars();
          case engine.Key.f:
            await planSiteVisit();
          case engine.Key.r:
            await reviewAssetsAndFormSquads();
        }
      }
    } finally {
      finished = true;
    }
  }

  Future<void> stop(WidgetTester tester) async {
    stopped = true;
    for (var i = 0; i < 50 && !finished; i++) {
      if (engine.console.awaitingInput) engine.console.sendInput('Escape');
      await tester.pump(const Duration(milliseconds: 5));
    }
    expect(finished, isTrue);
  }
}

Finder _key(String value) => find.byKey(ValueKey(value));
String _snapshot() => jsonEncode(game.gameState.toJson());

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 50; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String key) async {
  expect(_key(key).hitTestable(), findsOneWidget, reason: key);
  await tester.tap(_key(key));
  await _settle(tester);
}

void main() {
  late String fixture;
  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
    final serif = FontLoader('JournalSerif');
    serif.addFont(
      rootBundle.load('fonts/journal/LibreBaskerville-Variable.ttf'),
    );
    await serif.load();
  });
  setUp(() {
    journalReadingScale.value = 1;
    engine.console = Console();
    game.gameState = decodeSaveContents(fixture).gameState!;
    game.mode = GameMode.base;
  });

  Future<_VisitHarness> mount(
    WidgetTester tester, {
    Size size = const Size(1280, 720),
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    final harness = _VisitHarness();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await harness.stop(tester);
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(const MainApp());
    await _settle(tester);
    return harness;
  }

  Site target() => game.sites.firstWhere(
    (site) =>
        site.type == SiteType.publicPark &&
        site.city == game.activeSquad!.site!.city,
  );

  Future<void> inspectFromBusiness(WidgetTester tester, Site site) async {
    await _tap(tester, 'journal-orders');
    await _tap(tester, 'journal-order-group:0');
    await _tap(tester, 'journal-map-place:${site.district.idString}');
    expect(
      _key('journal-selected-destination'),
      findsNothing,
      reason: 'A district opens its sites but is not a destination.',
    );
    await _tap(tester, 'journal-map-place:${site.idString}');
    expect(find.text(site.getName()), findsWidgets);
    expect(
      tester.widget<Text>(_key('journal-destination-purpose')).data,
      locationPurpose(site.type),
    );
    expect(
      tester.widget<Text>(_key('journal-destination-access')).data,
      locationAccess(site),
    );
    expect(_key('journal-prepare-map-visit').hitTestable(), findsOneWidget);
  }

  Future<void> reviewVisit(WidgetTester tester, Site site) async {
    await _tap(tester, 'journal-orders');
    await _tap(tester, 'journal-order-group:3');
    await _tap(tester, 'journal-plan-visit');
    await _tap(tester, 'journal-map-place:${site.district.idString}');
    await _tap(tester, 'journal-map-place:${site.idString}');
  }

  test('travel notes apply only to the route and preserve state and RNG', () {
    final team = game.activeSquad!;
    for (final member in team.members) {
      member.preferredCarId = null;
    }
    final local = target();
    local.district.area = team.site!.area;
    final outskirts = team.site!.city.districts.firstWhere(
      (d) => d.area != team.site!.area,
    );
    final remote = game.cities.firstWhere((city) => city != team.site!.city);
    game.ledger.forceSetFunds(-10);
    final before = _snapshot();
    reseedRNG(seed: 21567);
    final rolls = List.generate(12, (_) => lcsRandom(100000));
    reseedRNG(seed: 21567);
    expect(travelNotices(local, team), isEmpty);
    expect(travelNotices(outskirts, team), ['needs car']);
    expect(travelNotices(remote, team), [
      '\$${team.members.length * 100}',
      'needs car',
      'not enough cash',
    ]);
    for (final site in game.sites) {
      travelNotices(site, team);
    }
    expect(_snapshot(), before);
    expect(List.generate(12, (_) => lcsRandom(100000)), rolls);

    final car = Vehicle(vehicleTypes.keys.first);
    game.vehiclePool.add(car);
    team.members.first.preferredCarId = car.id;
    game.ledger.forceSetFunds(team.members.length * 100);
    expect(travelNotices(outskirts, team), isEmpty);
    expect(travelNotices(remote, team), ['\$${team.members.length * 100}']);
    // The daily travel fee follows the home base, even while away from it.
    final away = remote.sites.first;
    for (final member in team.members) {
      member.location = away;
    }
    expect(travelNotices(away, team), ['\$${team.members.length * 100}']);
    expect(travelNotices(local, team), isEmpty);
    local.closed = 5;
    local.siege.activeSiegeType = SiegeType.police;
    expect(travelNotices(local, team), ['closed', 'under siege']);
  });

  testWidgets(
    'a nearby free visit has no generic travel warnings in the job card',
    (tester) async {
      for (final member in game.squad) {
        member.preferredCarId = null;
      }
      final site = target();
      site.district.area = game.activeSquad!.site!.area;
      await mount(tester);
      final before = _snapshot();
      await reviewVisit(tester, site);
      final card = _key('journal-job-card');
      final text = tester
          .widgetList<Text>(
            find.descendant(of: card, matching: find.byType(Text)),
          )
          .map((widget) => widget.data ?? '')
          .join('\n');
      expect(
        text,
        isNot(
          matches(
            RegExp(
              r'car|cash|intercity|Travel cost|Needs:',
              caseSensitive: false,
            ),
          ),
        ),
      );
      expect(_key('journal-travel-notices'), findsNothing);
      expect(_key('journal-calculation-result'), findsNothing);
      expect(_key('journal-confirm-order').hitTestable(), findsOneWidget);
      await _tap(tester, 'journal-order-details');
      expect(
        find.textContaining('Travel to another area needs a car'),
        findsOneWidget,
      );
      expect(find.textContaining('Intercity travel ='), findsOneWidget);
      expect(_snapshot(), before);
      expect(tester.takeException(), isNull);
    },
  );

  for (final (haveCar, enoughCash) in [
    (false, true),
    (true, true),
    (true, false),
  ]) {
    testWidgets(
      'Other cities shows price and source availability with car=$haveCar, cash=$enoughCash',
      (tester) async {
        for (final member in game.squad) {
          member.preferredCarId = null;
        }
        if (haveCar) {
          final car = Vehicle(vehicleTypes.keys.first);
          game.vehiclePool.add(car);
          game.squad.first.preferredCarId = car.id;
        }
        game.ledger.forceSetFunds(enoughCash ? game.squad.length * 100 : 0);
        await mount(tester);
        final before = _snapshot();
        await _tap(tester, 'journal-orders');
        await _tap(tester, 'journal-order-group:3');
        await _tap(tester, 'journal-plan-visit');
        final source = engine.console.actions.singleWhere(
          (action) => action.entityType == 'intercity-travel',
        );
        expect(source.enabled, haveCar && enoughCash);
        final button = find.widgetWithText(
          TextButton,
          'Other cities (\$${game.squad.length * 100})${haveCar ? '' : ' (needs car)'}${enoughCash ? '' : ' (not enough cash)'}',
        );
        expect(button, findsOneWidget);
        expect(
          tester.widget<TextButton>(button).onPressed != null,
          haveCar && enoughCash,
        );
        expect(_snapshot(), before);
        expect(tester.takeException(), isNull);
      },
    );
  }

  test(
    'people previews expose current weighted mixes without changing state or RNG',
    () {
      final site = target();
      site.type = SiteType.sweatshop;
      site.controller = SiteController.unaligned;
      final before = _snapshot();
      reseedRNG(seed: 24680);
      final rolls = List.generate(12, (_) => lcsRandom(100000));
      reseedRNG(seed: 24680);
      final ordinary = locationPeople(site, highSecurity: false);
      expect(ordinary.first.id, 'CREATURE_WORKER_SWEATSHOP');
      expect(ordinary.first.chance, closeTo(800 / 905 * 100, .00001));
      final security = locationPeople(site, highSecurity: true);
      expect(security.first.id, 'CREATURE_SECURITYGUARD');
      expect(security.first.chance, closeTo(1000 / 1805 * 100, .00001));
      for (final location in game.sites) {
        for (final area in [true, false]) {
          final people = locationPeople(location, publicArea: area);
          if (people.isNotEmpty) {
            expect(
              people.fold<double>(0, (sum, p) => sum + p.chance),
              closeTo(100, .00001),
            );
          }
        }
        locationPeopleSummary(location);
      }
      expect(_snapshot(), before);
      expect(List.generate(12, (_) => lcsRandom(100000)), rolls);
    },
  );

  for (final size in [const Size(1280, 720), const Size(800, 600)]) {
    testWidgets('location guide is readable and passive at $size', (
      tester,
    ) async {
      final harness = await mount(tester, size: size);
      if (size.width == 800) {
        await tester.tap(find.byTooltip('Reading size'));
        await _settle(tester);
        await tester.tap(find.text('150%'));
        await _settle(tester);
      }
      final site = target()..type = SiteType.insuranceOffice;
      await inspectFromBusiness(tester, site);
      final before = _snapshot();
      final revision = engine.console.revision.value;
      final actions = List<ConsoleAction>.of(engine.console.actions);
      final commandCount = harness.commands.length;
      reseedRNG(seed: 84271);
      final rolls = List.generate(12, (_) => lcsRandom(100000));
      reseedRNG(seed: 84271);
      await _tap(tester, 'journal-location-details');
      expect(find.text('What your actions can change'), findsOneWidget);
      expect(find.text('Normal clothing and disguises'), findsOneWidget);
      expect(find.text('Clothing in public areas'), findsOneWidget);
      expect(find.text('Clothing in restricted areas'), findsOneWidget);
      expect(
        find.textContaining('Approve members of the public’s denied claims'),
        findsOneWidget,
      );
      expect(find.textContaining('hospital debt'), findsOneWidget);
      expect(find.text('People and likelihood'), findsOneWidget);
      expect(find.textContaining('chance of a person type'), findsOneWidget);
      final guideScroll = find
          .descendant(
            of: find.byType(Dialog),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('Clothing in restricted areas'),
        150,
        scrollable: guideScroll,
      );
      await tester.tap(find.text('Clothing in restricted areas'));
      await _settle(tester);
      expect(find.text('Blends in · no clothing penalty'), findsOneWidget);
      expect(find.text('Authority role · −2 to Disguise'), findsOneWidget);
      expect(find.textContaining('Cheap Suit'), findsWidgets);
      await tester.tap(find.text('Clothing in restricted areas'));
      await _settle(tester);
      await tester.scrollUntilVisible(
        find.text('What can still give you away?'),
        150,
        scrollable: guideScroll,
      );
      await tester.tap(find.text('What can still give you away?'));
      await _settle(tester);
      expect(find.textContaining('not success chances'), findsOneWidget);
      await tester.tap(find.text('What can still give you away?'));
      await _settle(tester);
      await tester.scrollUntilVisible(
        find.text('Restricted areas'),
        150,
        scrollable: guideScroll,
      );
      await tester.tap(find.text('Restricted areas'));
      await _settle(tester);
      final facility = find.byKey(
        PageStorageKey(
          'location-facility:${site.idString}:insuranceClaimsTerminal',
        ),
      );
      await tester.scrollUntilVisible(facility, 200, scrollable: guideScroll);
      await _settle(tester);
      await tester.tap(find.text('Insurance claims terminal'));
      await _settle(tester);
      final help = locationFeatureHelp(TileSpecial.insuranceClaimsTerminal)!;
      expect(find.text(help), findsOneWidget);
      final tooltip = tester.state<TooltipState>(
        find.descendant(of: facility, matching: find.byType(Tooltip)),
      );
      tooltip.ensureTooltipVisible();
      await _settle(tester);
      final hint =
          '${locationFeatureSummary(TileSpecial.insuranceClaimsTerminal)}\nExpand for checks, rewards and consequences.';
      expect(find.text(help), findsOneWidget);
      expect(find.text(hint), findsOneWidget);
      final hintBounds = tester.getRect(find.text(hint));
      expect(hintBounds.top, greaterThanOrEqualTo(0));
      expect(hintBounds.bottom, lessThanOrEqualTo(size.height));
      expect(hintBounds.left, greaterThanOrEqualTo(0));
      expect(hintBounds.right, lessThanOrEqualTo(size.width));
      Tooltip.dismissAllToolTips();
      await _settle(tester);
      // Keyboard activation while inspecting must never reach the game reader.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyW, character: 'w');
      await _settle(tester);
      expect(_snapshot(), before);
      expect(engine.console.revision.value, revision);
      expect(engine.console.actions, orderedEquals(actions));
      expect(engine.console.awaitingInput, isTrue);
      expect(harness.commands.length, commandCount);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Close location details'));
      await _settle(tester);
      expect(find.byType(Dialog), findsNothing);
      expect(_snapshot(), before);
      // Reopen in the same application lifetime: saved expansion/scroll keys
      // must not collide, and the underlying selected destination must survive.
      await _tap(tester, 'journal-location-details');
      expect(find.text('What your actions can change'), findsOneWidget);
      await tester.tap(find.byTooltip('Close location details'));
      await _settle(tester);
      expect(find.text(site.getName()), findsWidgets);
      expect(_snapshot(), before);
      final gameFocus = tester
          .widgetList<Focus>(find.byType(Focus))
          .singleWhere((item) => item.focusNode?.debugLabel == 'Game keyboard')
          .focusNode!;
      expect(gameFocus.hasPrimaryFocus, isTrue);
      expect(List.generate(12, (_) => lcsRandom(100000)), rolls);
    });
  }

  testWidgets(
    'Operations visit prepares the same Squad card and preserves prior orders and RNG',
    (tester) async {
      final site = target();
      final old = Activity(
        ActivityType.visit,
        idString: game.activeSquad!.site!.idString,
      );
      game.activeSquad!.activity = old;
      game.pool.first.activity = Activity(ActivityType.donations);
      await mount(tester);
      final before = _snapshot();
      reseedRNG(seed: 9147);
      final rolls = List.generate(20, (_) => lcsRandom(100000));
      reseedRNG(seed: 9147);
      await _tap(tester, 'journal-orders');
      await _tap(tester, 'journal-order-group:3');
      expect(find.text('Visit a location'), findsOneWidget);
      await _tap(tester, 'journal-plan-visit');
      expect(engine.console.screen, 'planning');
      expect(_snapshot(), before);
      await _tap(tester, 'journal-map-place:${site.district.idString}');
      await _tap(tester, 'journal-map-place:${site.idString}');
      expect(_key('journal-destination-purpose'), findsOneWidget);
      expect(find.text('Visit ${site.getName()}'), findsOneWidget);
      expect(find.textContaining('Squad order'), findsWidgets);
      expect(find.text('Confirm order'), findsOneWidget);
      expect(_key('journal-visit-members'), findsNothing);
      await _tap(tester, 'journal-order-details');
      expect(_key('journal-visit-members'), findsOneWidget);
      expect(find.text('Combat readiness'), findsOneWidget);
      expect(find.textContaining('compatible spare rounds'), findsWidgets);
      expect(_snapshot(), before);
      await tester.tap(find.text('Close'));
      await _settle(tester);
      expect(_key('journal-prepare-map-visit'), findsNothing);
      expect(find.text('Visit with selected squad'), findsNothing);
      expect(_snapshot(), before);
      await _tap(tester, 'journal-cancel-order');
      expect(_snapshot(), before);
      expect(game.activeSquad!.activity, same(old));
      expect(List.generate(20, (_) => lcsRandom(100000)), rolls);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Operations confirms only after reviewing destination and Escape preserves prior visit',
    (tester) async {
      final site = target();
      await mount(tester);
      await _tap(tester, 'journal-orders');
      await _tap(tester, 'journal-order-group:3');
      await _tap(tester, 'journal-plan-visit');
      await _tap(tester, 'journal-map-place:${site.district.idString}');
      final source = engine.console.actions.singleWhere(
        (a) => a.entityId == site.idString,
      );
      final before = _snapshot();
      await tester.sendKeyEvent(
        LogicalKeyboardKey(source.key.toLowerCase().codeUnitAt(0)),
        character: source.key.toLowerCase(),
      );
      await _settle(tester);
      expect(_snapshot(), before);
      expect(find.text('Visit ${site.getName()}'), findsOneWidget);
      await _tap(tester, 'journal-confirm-order');
      expect(game.activeSquad!.activity.idString, site.idString);
      expect(find.textContaining('Visit queued'), findsWidgets);
      final queued = _snapshot();
      await _tap(tester, 'journal-orders');
      await _tap(tester, 'journal-order-group:3');
      await _tap(tester, 'journal-plan-visit');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(tester);
      expect(engine.console.screen, 'headquarters');
      expect(_snapshot(), queued);
      for (final (key, character) in [
        (LogicalKeyboardKey.keyX, 'x'),
        (LogicalKeyboardKey.space, ' '),
      ]) {
        await _tap(tester, 'journal-orders');
        await _tap(tester, 'journal-order-group:3');
        await _tap(tester, 'journal-plan-visit');
        await tester.sendKeyEvent(key, character: character);
        await _settle(tester);
        expect(engine.console.screen, 'headquarters');
        expect(_snapshot(), queued);
      }
    },
  );

  testWidgets(
    'Business map inspection is read-only, then one action queues the exact destination',
    (tester) async {
      final harness = await mount(tester);
      final site = target();
      final before = _snapshot();
      reseedRNG(seed: 53219);
      final rolls = List.generate(20, (_) => lcsRandom(100000));
      reseedRNG(seed: 53219);
      await inspectFromBusiness(tester, site);
      expect(_snapshot(), before);
      expect(engine.console.screen, 'activity-orders');
      await _tap(tester, 'journal-prepare-map-visit');
      expect(engine.console.screen, 'headquarters');
      expect(game.activeSquad!.activity.type, ActivityType.visit);
      expect(game.activeSquad!.activity.idString, site.idString);
      final after = jsonDecode(_snapshot()) as Map<String, dynamic>;
      final expected = jsonDecode(before) as Map<String, dynamic>;
      final oldSquads =
          (expected['lcs'] as Map<String, dynamic>)['squads'] as List;
      final newSquads =
          (after['lcs'] as Map<String, dynamic>)['squads'] as List;
      (oldSquads[0] as Map<String, dynamic>)['activity'] =
          (newSquads[0] as Map<String, dynamic>)['activity'];
      expect(
        after,
        expected,
        reason: 'Only the original squad destination changes.',
      );
      expect(harness.commands, isNot(contains(engine.Key.w)));
      expect(List.generate(20, (_) => lcsRandom(100000)), rolls);
      expect(find.textContaining('Visit queued'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'cancel prepared visit preserves existing squad and personal orders',
    (tester) async {
      final site = target();
      final squad = game.activeSquad!;
      final old = Activity(ActivityType.visit, idString: squad.site!.idString);
      squad.activity = old;
      game.pool.first.activity = Activity(ActivityType.donations);
      await mount(tester);
      final before = _snapshot();
      await reviewVisit(tester, site);
      expect(squad.activity, same(old));
      await _tap(tester, 'journal-cancel-order');
      expect(engine.console.screen, 'headquarters');
      expect(squad.activity, same(old));
      expect(_snapshot(), before);
      expect(game.pool.first.activity.type, ActivityType.donations);
      expect(
        _key('journal-prepare-map-visit').hitTestable(),
        findsOneWidget,
        reason: 'The same inspected target remains available after cancelling.',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'retained map queue callbacks cannot target a different selection',
    (tester) async {
      await mount(tester);
      final site = target();
      await _tap(tester, 'journal-map-place:${site.district.idString}');
      await _tap(tester, 'journal-map-place:${site.idString}');
      final retained = tester
          .widget<TextButton>(_key('journal-prepare-map-visit'))
          .onPressed!;
      final next = site.district.sites.firstWhere(
        (s) => s.id != site.id && !s.hidden,
      );
      await _tap(tester, 'journal-map-place:${next.idString}');
      final before = _snapshot();
      retained();
      await _settle(tester);
      expect(_snapshot(), before);
      expect(engine.console.screen, 'headquarters');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Enter queues the inspected headquarters destination without advancing a day',
    (tester) async {
      final harness = await mount(tester);
      final site = target();
      await _tap(tester, 'journal-map-place:${site.district.idString}');
      await _tap(tester, 'journal-map-place:${site.idString}');
      final date = game.date;
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _settle(tester);
      expect(game.activeSquad!.activity.idString, site.idString);
      expect(engine.console.screen, 'headquarters');
      expect(game.date, date);
      expect(harness.commands, isNot(contains(engine.Key.w)));
      expect(_key('journal-confirm-order'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'source-disabled closed destination is inspectable but cannot be confirmed',
    (tester) async {
      final site = target()..closed = 5;
      await mount(tester);
      final before = _snapshot();
      await inspectFromBusiness(tester, site);
      await _tap(tester, 'journal-prepare-map-visit');
      final source = engine.console.actions.singleWhere(
        (a) => a.entityType == 'site' && a.entityId == site.idString,
      );
      expect(source.enabled, isFalse);
      expect(
        tester.widget<FilledButton>(_key('journal-confirm-order')).onPressed,
        isNull,
      );
      expect(find.textContaining('Closed Down'), findsWidgets);
      expect(_snapshot(), before);
      expect(game.activeSquad!.activity.type, ActivityType.none);
    },
  );

  testWidgets(
    'pagination finds the selected exact source site without another map click',
    (tester) async {
      final district = target().district;
      for (var i = 0; i < 12; i++) {
        game.sites.add(
          Site(SiteType.publicPark, district.city, district)
            ..name = 'Additional source park $i',
        );
      }
      final site = district.sites.last;
      await mount(tester);
      final before = _snapshot();
      await _tap(tester, 'journal-orders');
      await _tap(tester, 'journal-order-group:0');
      await _tap(tester, 'journal-map-place:${district.idString}');
      await tester.tap(find.byTooltip('Show location index'));
      await _settle(tester);
      await tester.ensureVisible(_key('journal-map-index:${site.idString}'));
      await tester.tap(_key('journal-map-index:${site.idString}'));
      await _settle(tester);
      await _tap(tester, 'journal-prepare-map-visit');
      expect(engine.console.screen, 'headquarters');
      expect(game.activeSquad!.activity.idString, site.idString);
      expect(game.date.toIso8601String(), jsonDecode(before)['date']);
    },
  );

  testWidgets(
    '800x600 at 150 percent keeps destination action and useful map space',
    (tester) async {
      await mount(tester, size: const Size(800, 600));
      await tester.tap(find.byTooltip('Reading size'));
      await _settle(tester);
      await tester.tap(find.text('150%'));
      await _settle(tester);
      await inspectFromBusiness(tester, target());
      expect(_key('journal-prepare-map-visit').hitTestable(), findsOneWidget);
      final viewport = tester.getSize(_key('journal-city-pan-zoom'));
      expect(
        viewport.height,
        greaterThan(120),
        reason: 'Inspection metadata must not consume the actual map viewport.',
      );
      expect(
        find.text('Known places only · illustrative block layout'),
        findsNothing,
      );
      await _tap(tester, 'journal-prepare-map-visit');
      expect(_key('journal-confirm-order'), findsNothing);
      expect(game.activeSquad!.activity.idString, target().idString);
      final focus = tester
          .widgetList<Focus>(find.byType(Focus))
          .singleWhere((item) => item.focusNode?.debugLabel == 'Game keyboard')
          .focusNode!;
      expect(focus.hasPrimaryFocus, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
