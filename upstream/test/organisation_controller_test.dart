import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activate_regulars.dart';
import 'package:lcs_new_age/basemode/activate_sleepers.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/basemode/base_mode.dart';
import 'package:lcs_new_age/basemode/media_overview.dart';
import 'package:lcs_new_age/basemode/plan_site_visit.dart';
import 'package:lcs_new_age/basemode/review_mode.dart';
import 'package:lcs_new_age/common_display/print_creature_info.dart';
import 'package:lcs_new_age/creature/body.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/engine/organisation_context.dart';
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/gamestate/squad.dart';
import 'package:lcs_new_age/location/siege.dart';
import 'package:lcs_new_age/modern/organisation_controller.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

/// Keeps only the original base menu's dispatch boundary. All squad, order,
/// location and media handlers exercised below are the real source functions.
class _BaseHarness {
  _BaseHarness() {
    done = _loop();
  }
  late final Future<void> done;
  bool stopped = false;
  bool finished = false;

  Future<void> _loop() async {
    try {
      while (!stopped) {
        engine.erase();
        final location = game.activeSquad?.site ?? game.activeSafehouse;
        baseModeSquadSafehouseDisplay(location);
        baseModeOptionsDisplay(location);
        final key = await engine.getKey();
        if (stopped) break;
        switch (key) {
          case engine.Key.r:
            await reviewAssetsAndFormSquads();
          case engine.Key.a:
            await activateRegulars();
          case engine.Key.b:
            await activateSleepers();
          case engine.Key.f:
            await planSiteVisit();
          case engine.Key.m:
            await mediaOverview();
        }
      }
    } finally {
      finished = true;
    }
  }

  Future<void> stop() async {
    stopped = true;
    for (var step = 0; step < 40 && !finished; step++) {
      if (engine.console.awaitingInput) {
        engine.console.sendInput(engine.console.textInput ? 'Enter' : 'Escape');
      }
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    await done.timeout(const Duration(seconds: 2));
  }
}

Creature _extraPerson({String? name}) {
  final person = Creature.fromJson(
    jsonDecode(jsonEncode(game.pool.first.toJson())),
  );
  person.id = game.gameState.nextCreatureId++;
  person.name = name ?? 'Crew ${person.id}';
  person.squadId = null;
  game.pool.add(person);
  return person;
}

Squad _extraSquad() {
  final person = _extraPerson();
  final squad = Squad()..name = 'Squad ${game.squads.length + 1}';
  game.squads.add(squad);
  person.squad = squad;
  return squad;
}

String _snapshot() => jsonEncode(game.gameState.toJson());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String saveContents;
  OrganisationController? controller;
  _BaseHarness? harness;
  Future<void>? profileReader;
  bool profileFinished = false;
  setUpAll(() async {
    await ensureGameDataLoaded();
    saveContents = await File('test/saves/felix_1_0.json').readAsString();
  });
  setUp(() {
    engine.console = Console();
    game.gameState = decodeSaveContents(saveContents).gameState!;
    game.mode = GameMode.base;
    game.activeSquadMember = null;
  });
  tearDown(() async {
    controller?.dispose();
    controller = null;
    await harness?.stop();
    harness = null;
    for (
      var step = 0;
      profileReader != null && step < 8 && !profileFinished;
      step++
    ) {
      if (engine.console.awaitingInput) {
        engine.console.sendInput(engine.console.textInput ? 'Enter' : 'Escape');
      }
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    await profileReader?.timeout(const Duration(seconds: 2));
    profileReader = null;
    profileFinished = false;
  });

  OrganisationController start() {
    harness = _BaseHarness();
    return controller = OrganisationController(console: engine.console);
  }

  OrganisationController startProfile(Future<void> reader) {
    profileReader = reader.whenComplete(() => profileFinished = true);
    return controller = OrganisationController(console: engine.console);
  }

  Future<void> sendProfileKey(
    OrganisationController journal,
    String key,
  ) async {
    final action = engine.console.actions.singleWhere((a) => a.key == key);
    expect(
      await journal.sendAction(action, revision: engine.console.revision.value),
      isTrue,
    );
  }

  test(
    'profile selection follows source arrows and retains every tab',
    () async {
      final people = game.activeSquad!.members;
      expect(people.length, greaterThan(2));
      final before = _snapshot();
      reseedRNG(seed: 40991);
      final rolls = List.generate(8, (_) => lcsRandom(100000));
      reseedRNG(seed: 40991);
      final journal = startProfile(fullCreatureInfoScreen(people.first));
      final ids = people.map((p) => p.id).toList();
      expect(engine.console.journalProfile!.personIds, ids);
      expect(
        () => engine.console.journalProfile!.personIds.add(123),
        throwsUnsupportedError,
      );
      for (var page = 0; page < 3; page++) {
        if (page != 0) await sendProfileKey(journal, 'Down');
        for (final target in [people[2], people.last, people.first]) {
          expect(journal.canSelectProfilePerson(target.id), isTrue);
          expect(await journal.selectProfilePerson(target.id), isTrue);
          expect(engine.console.journalProfile!.person, same(target));
          expect(engine.console.journalProfile!.page, page);
          expect(journal.selectedPersonId, target.id);
          expect(engine.console.journalProfile!.personIds, ids);
        }
      }
      expect(_snapshot(), before);
      expect(List.generate(8, (_) => lcsRandom(100000)), rolls);
    },
  );

  test(
    'footer profile arrows synchronise selected person without new squad',
    () async {
      final people = game.activeSquad!.members;
      final squadId = game.activeSquad!.id;
      final journal = startProfile(fullCreatureInfoScreen(people.first));
      expect(journal.selectedPersonId, people.first.id);
      await sendProfileKey(journal, 'Down');
      await sendProfileKey(journal, 'Right');
      expect(journal.selectedPersonId, people[1].id);
      expect(engine.console.journalProfile!.page, 1);
      expect(journal.selectedSquadId, squadId);
      await sendProfileKey(journal, 'Left');
      expect(journal.selectedPersonId, people.first.id);
      expect(engine.console.journalProfile!.page, 1);
    },
  );

  test(
    'profile selection rejects people outside the original roster',
    () async {
      final outside = _extraPerson();
      final journal = startProfile(fullCreatureInfoScreen(game.squad.first));
      final before = _snapshot();
      final revision = engine.console.revision.value;
      for (final id in [outside.id, 999999]) {
        expect(journal.canSelectProfilePerson(id), isFalse);
        expect(await journal.selectProfilePerson(id), isFalse);
      }
      expect(engine.console.revision.value, revision);
      expect(_snapshot(), before);
    },
  );

  test(
    'Clipboard selection uses its full source roster across squads',
    () async {
      final outside = _extraSquad().members.single;
      final originalSquadId = game.activeSquad!.id;
      final journal = startProfile(reviewMode(ReviewMode.liberals));
      final open = engine.console.actions.firstWhere(
        (a) => a.entityType == 'person',
      );
      expect(
        await journal.sendAction(open, revision: engine.console.revision.value),
        isTrue,
      );
      await sendProfileKey(journal, 'Down');
      final before = _snapshot();
      expect(await journal.selectProfilePerson(outside.id), isTrue);
      expect(engine.console.journalProfile!.person, same(outside));
      expect(engine.console.journalProfile!.page, 1);
      expect(journal.selectedPersonId, outside.id);
      expect(journal.selectedSquadId, originalSquadId);
      expect(game.activeSquad!.id, originalSquadId);
      expect(_snapshot(), before);
    },
  );

  test('sleeper profiles navigate only their source sleeper roster', () async {
    final first = _extraPerson()..sleeperAgent = true;
    final second = _extraPerson()..sleeperAgent = true;
    final journal = startProfile(reviewMode(ReviewMode.sleepers));
    final open = engine.console.actions.firstWhere(
      (a) => a.entityType == 'person' && a.entityId == first.id.toString(),
    );
    expect(
      await journal.sendAction(open, revision: engine.console.revision.value),
      isTrue,
    );
    final before = _snapshot();
    expect(await journal.selectProfilePerson(second.id), isTrue);
    expect(journal.selectedPerson, same(second));
    expect(journal.canSelectProfilePerson(game.squad.first.id), isFalse);
    expect(_snapshot(), before);
  });

  test('rename input cannot be consumed by profile selection', () async {
    final people = game.activeSquad!.members;
    final journal = startProfile(fullCreatureInfoScreen(people.first));
    await sendProfileKey(journal, 'n');
    expect(engine.console.textInput, isTrue);
    final before = _snapshot();
    final revision = engine.console.revision.value;
    expect(journal.canSelectProfilePerson(people.last.id), isFalse);
    expect(await journal.selectProfilePerson(people.last.id), isFalse);
    expect(engine.console.revision.value, revision);
    expect(engine.console.textInput, isTrue);
    expect(_snapshot(), before);
  });

  for (final key in ['r', 'k']) {
    test('profile selection cannot dismiss $key confirmation', () async {
      final person = game.pool.firstWhere(
        (p) =>
            p.isActiveLiberal &&
            p.hireId != null &&
            p.boss?.location == p.location,
      );
      final journal = startProfile(reviewMode(ReviewMode.liberals));
      final open = engine.console.actions.firstWhere(
        (a) => a.entityType == 'person' && a.entityId == person.id.toString(),
      );
      expect(
        await journal.sendAction(open, revision: engine.console.revision.value),
        isTrue,
      );
      await sendProfileKey(journal, key);
      expect(engine.console.journalProfile!.confirming, isTrue);
      expect(engine.console.journalProfile!.canSelectPerson, isFalse);
      final target = game.squad.firstWhere((p) => p.id != person.id);
      final before = _snapshot();
      final revision = engine.console.revision.value;
      expect(journal.canSelectProfilePerson(target.id), isFalse);
      expect(await journal.selectProfilePerson(target.id), isFalse);
      expect(engine.console.revision.value, revision);
      expect(engine.console.journalProfile!.confirming, isTrue);
      expect(_snapshot(), before);
    });
  }

  test(
    'tab selection uses the original squad key and never opens assembly',
    () async {
      final target = _extraSquad();
      final date = game.date;
      final funds = game.ledger.funds;
      final members = {
        for (final s in game.squads) s.id: s.members.map((p) => p.id).toList(),
      };
      reseedRNG(seed: 20261);
      final rolls = List.generate(8, (_) => lcsRandom(100000));
      reseedRNG(seed: 20261);
      final journal = start();

      expect(await journal.selectSquad(target.id), isTrue);
      expect(game.activeSquad, same(target));
      expect(engine.console.screen, 'headquarters');
      expect(journal.assembly, isNull);
      final selected = _snapshot();
      expect(await journal.selectSquad(target.id), isTrue);
      expect(_snapshot(), selected);
      expect(journal.assembly, isNull);
      expect(game.date, date);
      expect(game.ledger.funds, funds);
      expect({
        for (final s in game.squads) s.id: s.members.map((p) => p.id).toList(),
      }, members);
      expect(List.generate(8, (_) => lcsRandom(100000)), rolls);
    },
  );

  test('squad selection automatically reaches an entity on page two', () async {
    Squad? target;
    for (var i = 0; i < 21; i++) {
      target = _extraSquad();
    }
    final journal = start();
    var sawPageTwo = false;
    void recordPage() {
      sawPageTwo |= organisationOverviewFrame(engine.console)?.page == 1;
    }

    engine.console.revision.addListener(recordPage);
    addTearDown(() => engine.console.revision.removeListener(recordPage));
    expect(await journal.selectSquad(target!.id), isTrue);
    expect(game.activeSquad, same(target));
    expect(sawPageTwo, isTrue);
    expect(engine.console.screen, 'headquarters');
    expect(journal.headquarters?.squadId, target.id);
    expect(journal.assembly, isNull);
  });

  for (final siege in ['attack', 'elsewhere', 'waiting']) {
    test(
      'HQ snapshot retains exact source W/F/C capabilities: $siege',
      () async {
        final current = game.activeSquad!.site!;
        if (siege == 'elsewhere') {
          final remote = _extraPerson();
          final otherSite = game.sites.firstWhere((site) => site != current);
          remote.location = otherSite;
          otherSite.siege
            ..activeSiegeType = SiegeType.police
            ..underAttack = true;
        } else {
          current.siege
            ..activeSiegeType = SiegeType.police
            ..underAttack = siege == 'attack';
        }
        final journal = start();
        expect(journal.headquarters, isNotNull);
        final w = engine.console.actions
            .where((action) => action.key == 'w')
            .firstOrNull;
        expect(journal.headquartersAction('w'), same(w));
        expect(
          journal.headquartersAction('f'),
          same(
            engine.console.actions.singleWhere((action) => action.key == 'f'),
          ),
        );
        expect(
          journal.headquartersAction('c'),
          same(
            engine.console.actions.singleWhere((action) => action.key == 'c'),
          ),
        );
        if (siege == 'attack') {
          expect(
            w,
            isNull,
            reason: 'An attacked active location has no W choice.',
          );
          expect(
            journal.headquartersAction('f')?.label,
            contains('Fight/Escape'),
          );
        } else if (siege == 'elsewhere') {
          expect(w?.label, contains('Select Siege Location'));
        } else {
          expect(w?.label, contains('Wait out the siege'));
        }
        final before = _snapshot();
        final revision = engine.console.revision.value;
        reseedRNG(seed: 3332);
        final rolls = List.generate(8, (_) => lcsRandom(100000));
        reseedRNG(seed: 3332);
        for (var i = 0; i < 5; i++) {
          expect(journal.headquarters?.squadId, game.activeSquad!.id);
          expect(journal.headquarters?.locationId, current.idString);
          expect(journal.headquarters?.date, game.date);
          journal.headquartersAction('w');
          journal.headquartersAction('f');
          journal.headquartersAction('c');
        }
        expect(_snapshot(), before);
        expect(engine.console.revision.value, revision);
        expect(List.generate(8, (_) => lcsRandom(100000)), rolls);
      },
    );
  }

  test(
    'matching HQ capabilities survive menu browsing but invalidate changed orders and rosters',
    () async {
      final journal = start();
      final actualWait = journal.headquartersAction('w');
      expect(actualWait?.enabled, isTrue);
      expect(await journal.openOrders(game.pool.first.id), isTrue);
      expect(journal.headquartersAction('w'), same(actualWait));
      expect(await journal.returnToHeadquarters(), isTrue);
      expect(await journal.openAllocation(game.activeSquad!.id), isTrue);
      expect(journal.headquartersAction('w'), isNotNull);
      expect(await journal.assignPerson(game.pool.last.id), isTrue);
      expect(
        journal.headquarters,
        isNull,
        reason: 'A changed roster needs fresh source options.',
      );
      expect(journal.headquartersAction('w'), isNull);
      expect(await journal.finishAllocation(), isTrue);
      expect(engine.console.screen, 'headquarters');
      expect(journal.headquartersAction('w'), isNotNull);
      game.activeSquad!.activity = Activity(
        ActivityType.visit,
        idString: game.activeSquad!.site!.idString,
      );
      expect(
        journal.headquarters,
        isNull,
        reason: 'Queued order changes cannot reuse old W wording.',
      );
    },
  );

  test(
    'HQ capability scope invalidates date, team, site and campaign replacement',
    () async {
      final other = _extraSquad();
      final journal = start();
      expect(journal.headquarters, isNotNull);
      final date = game.date;
      game.gameState.date = date.add(const Duration(days: 1));
      expect(journal.headquarters, isNull);
      game.gameState.date = date;
      expect(journal.headquarters, isNotNull);
      final original = game.activeSquad!;
      game.activeSquad = other;
      expect(journal.headquarters, isNull);
      game.activeSquad = original;
      expect(journal.headquarters, isNotNull);
      final first = original.members.first;
      final location = first.location;
      first.location = game.sites.firstWhere((site) => site != location);
      expect(journal.headquarters, isNull);
      first.location = location;
      expect(journal.headquarters, isNotNull);
      game.gameState = decodeSaveContents(saveContents).gameState!;
      game.mode = GameMode.base;
      expect(
        journal.headquarters,
        isNull,
        reason:
            'Identical IDs/date in another campaign are not the same capability.',
      );
    },
  );

  test(
    'selecting a besieged squad refreshes exact source footer capabilities',
    () async {
      final other = _extraSquad();
      final site = game.sites.firstWhere(
        (site) => site != game.activeSquad!.site,
      );
      other.members.single.location = site;
      site.siege.activeSiegeType = SiegeType.police;
      final journal = start();
      expect(journal.headquartersAction('w')?.label, contains('Wait a day'));
      expect(await journal.selectSquad(other.id), isTrue);
      expect(engine.console.screen, 'headquarters');
      expect(journal.headquarters?.squadId, other.id);
      expect(
        journal.headquartersAction('w')?.label,
        contains('Wait out the siege'),
      );
      expect(journal.headquartersAction('f')?.label, contains('Fight/Escape'));
    },
  );

  test('journal follows source-side keyboard squad changes', () async {
    final target = _extraSquad();
    final original = game.activeSquad!;
    final journal = start();
    expect(await journal.selectSquad(original.id), isTrue);
    game.activeSquad = target;
    final before = _snapshot();
    engine.console.flush();
    expect(journal.selectedSquad, same(target));
    expect(journal.selectedSquadId, target.id);
    expect(_snapshot(), before);
  });

  test(
    'allocation retains the six-person rule with immediate original toggles',
    () async {
      final firstExtra = _extraPerson();
      final secondExtra = _extraPerson();
      final squad = game.activeSquad!;
      final originalMember = squad.members.first;
      final journal = start();
      expect(await journal.openAllocation(squad.id), isTrue);
      expect(journal.assembly?.memberIds, squad.members.map((p) => p.id));
      expect(await journal.assignPerson(firstExtra.id), isTrue);
      expect(squad.members, contains(firstExtra));
      expect(firstExtra.squadId, squad.id);
      final full = _snapshot();
      expect(await journal.assignPerson(secondExtra.id), isFalse);
      expect(journal.message, contains('six members'));
      expect(_snapshot(), full);
      expect(await journal.assignPerson(originalMember.id), isTrue);
      expect(originalMember.squadId, isNull);
      expect(await journal.assignPerson(secondExtra.id), isTrue);
      expect(squad.members.length, 6);
    },
  );

  test(
    'transferring and toggling again restores the original other squad',
    () async {
      final other = _extraSquad();
      final person = other.members.single;
      final target = game.activeSquad!;
      final journal = start();
      expect(await journal.openAllocation(target.id), isTrue);
      expect(await journal.assignPerson(person.id), isTrue);
      expect(person.squad, same(target));
      expect(other.members, isEmpty);
      expect(await journal.assignPerson(person.id), isTrue);
      expect(person.squad, same(other));
      expect(other.members, [person]);
      expect(target.members, isNot(contains(person)));
    },
  );

  test('all pool members can be allocated across original pages', () async {
    Creature? target;
    for (var i = 0; i < 21; i++) {
      target = _extraPerson();
    }
    final squad = game.activeSquad!;
    final journal = start();
    expect(await journal.openAllocation(squad.id), isTrue);
    expect(journal.allocationPool.length, 26);
    expect(await journal.assignPerson(target!.id), isTrue);
    expect(journal.assembly?.page, 1);
    expect(squad.members, contains(target));
    expect(await journal.assignPerson(game.pool.first.id), isTrue);
    expect(journal.assembly?.page, 0);
    expect(game.pool.first.squadId, isNull);
  });

  test(
    'removing the last member retains the handler’s fixed local pool',
    () async {
      final squad = game.activeSquad!;
      final local = List<Creature>.of(squad.members);
      final remote = _extraPerson();
      remote.location = game.sites.firstWhere((site) => site != squad.site);
      final journal = start();
      expect(await journal.openAllocation(squad.id), isTrue);
      for (final person in local) {
        expect(await journal.assignPerson(person.id), isTrue);
      }
      expect(squad.members, isEmpty);
      expect(journal.assembly?.memberIds, isEmpty);
      expect(journal.allocationPool, local);
      expect(journal.allocationPool, isNot(contains(remote)));
      final empty = _snapshot();
      expect(await journal.assignPerson(remote.id), isFalse);
      expect(_snapshot(), empty);
      expect(await journal.assignPerson(local.last.id), isTrue);
      expect(squad.members, [local.last]);
      expect(journal.assembly?.memberIds, [local.last.id]);
    },
  );

  for (final wheelchair in [false, true]) {
    test(
      'allocation explains impaired mobility; wheelchair=$wheelchair',
      () async {
        final person = _extraPerson();
        final body = person.body as HumanoidBody;
        body.leftLeg.cleanOff = true;
        body.rightLeg.cleanOff = true;
        person.hasWheelchair = wheelchair;
        expect(person.canWalk, isFalse);
        final journal = start();
        expect(await journal.openAllocation(game.activeSquad!.id), isTrue);
        final before = _snapshot();
        expect(await journal.assignPerson(person.id), wheelchair);
        if (wheelchair) {
          expect(game.activeSquad!.members, contains(person));
        } else {
          expect(journal.message, contains('wheelchair'));
          expect(_snapshot(), before);
        }
      },
    );
  }

  test('remote and inactive people cannot be silently allocated', () async {
    final remote = _extraPerson();
    remote.location = game.sites.firstWhere(
      (site) => site != game.activeSquad!.site,
    );
    final dead = _extraPerson()..alive = false;
    final away = _extraPerson()..hidingDaysLeft = 3;
    final journal = start();
    expect(await journal.openAllocation(game.activeSquad!.id), isTrue);
    expect(journal.allocationPool, isNot(contains(remote)));
    expect(journal.allocationPool, isNot(contains(dead)));
    expect(journal.allocationPool, isNot(contains(away)));
    final before = _snapshot();
    for (final person in [remote, dead, away]) {
      expect(await journal.assignPerson(person.id), isFalse);
      expect(_snapshot(), before);
    }
  });

  test(
    'new squad keeps same-location rules and requires explicit naming',
    () async {
      final remote = _extraPerson();
      remote.location = game.sites.firstWhere(
        (site) => site != game.activeSquad!.site,
      );
      final local = game.pool.first;
      final originalCount = game.squads.length;
      final journal = start();
      expect(await journal.openAllocation(null), isTrue);
      expect(journal.isNewAssembly, isTrue);
      expect(journal.allocationPool, contains(remote));
      expect(await journal.assignPerson(local.id), isTrue);
      final before = _snapshot();
      expect(await journal.assignPerson(remote.id), isFalse);
      expect(journal.message, contains('same location'));
      expect(_snapshot(), before);
      expect(await journal.returnToHeadquarters(), isFalse);
      expect(journal.message, contains('name it'));
      expect(engine.console.screen, 'squad-assembly');
      expect(_snapshot(), before);
      expect(await journal.finishAllocation(), isTrue);
      expect(engine.console.textInput, isTrue);
      expect(journal.assembly, isNull);
      expect(game.squads.length, originalCount);
      expect(await journal.openSection('m'), isFalse);
      expect(engine.console.textInput, isTrue);
      engine.console.sendInput('Enter');
      await Future<void>.delayed(const Duration(milliseconds: 3));
      expect(game.squads.length, originalCount + 1);
      expect(game.squads.last.name, 'The Liberal Crime Squad');
    },
  );

  test(
    'existing assembly finalizes intentionally when changing squad tabs',
    () async {
      final other = _extraSquad();
      final first = game.activeSquad!;
      final person = first.members.first;
      final journal = start();
      expect(await journal.openAllocation(first.id), isTrue);
      expect(await journal.assignPerson(person.id), isTrue);
      expect(await journal.selectSquad(other.id), isTrue);
      expect(game.activeSquad, same(other));
      expect(person.squadId, isNull);
      expect(journal.assembly, isNull);
      expect(engine.console.screen, 'headquarters');
    },
  );

  test(
    'orders open the actual selected actor and preserve queued visits',
    () async {
      final other = _extraSquad();
      final target = game.activeSquad!.site!;
      final queued = Activity(ActivityType.visit, idString: target.idString);
      other.activity = queued;
      final person = game.pool.first;
      final journal = start();
      final before = _snapshot();
      expect(await journal.openOrders(person.id), isTrue);
      final confirm = engine.console.actions.singleWhere(
        (a) => a.entityType == 'activity-confirm',
      );
      expect(confirm.entityCategory, person.id.toString());
      expect(other.activity, same(queued));
      expect(_snapshot(), before);
      expect(await journal.returnToHeadquarters(), isTrue);
      expect(_snapshot(), before);
      expect(await journal.openOrders(other.members.single.id), isFalse);
      expect(journal.message, contains('joint operation'));
      expect(other.activity, same(queued));
    },
  );

  test(
    'order actor on later page can be opened without any category default',
    () async {
      Creature? target;
      for (var i = 0; i < 23; i++) {
        target = _extraPerson();
      }
      target!.activity = Activity(ActivityType.donations);
      final journal = start();
      final before = _snapshot();
      expect(await journal.openOrders(target.id), isTrue);
      expect(
        engine.console.actions
            .singleWhere((a) => a.entityType == 'activity-confirm')
            .entityCategory,
        target.id.toString(),
      );
      expect(target.activity.type, ActivityType.donations);
      expect(_snapshot(), before);
    },
  );

  test(
    'return from actual Operations preserves the exact queued visit',
    () async {
      final target = game.activeSquad!.site!;
      final queued = Activity(ActivityType.visit, idString: target.idString);
      game.activeSquad!.activity = queued;
      final journal = start();
      final before = _snapshot();
      expect(await journal.openSection('f'), isTrue);
      expect(engine.console.navigation?.section, 'operations');
      expect(await journal.returnToHeadquarters(), isTrue);
      expect(game.activeSquad!.activity, same(queued));
      expect(_snapshot(), before);
    },
  );

  test(
    'sleeper orders use the real nine-person pages and actor handler',
    () async {
      Creature? target;
      for (var i = 0; i < 12; i++) {
        target = _extraPerson()..sleeperAgent = true;
      }
      final person = target!;
      person.activity = Activity(ActivityType.sleeperSpy);
      final journal = start();
      final before = _snapshot();
      expect(await journal.openOrders(person.id), isTrue);
      expect(
        engine.console.actions
            .singleWhere(
              (action) => action.entityType == 'sleeper-activity-confirm',
            )
            .entityCategory,
        person.id.toString(),
      );
      expect(person.activity.type, ActivityType.sleeperSpy);
      expect(_snapshot(), before);
      expect(await journal.returnToHeadquarters(), isTrue);
      expect(_snapshot(), before);
    },
  );

  test(
    'all seven regular categories preview without changing an order',
    () async {
      final person = game.pool.first;
      final order = Activity(ActivityType.sellArt);
      person.activity = order;
      final journal = start();
      expect(await journal.openOrders(person.id), isTrue);
      final before = _snapshot();
      reseedRNG(seed: 4882);
      final rolls = List.generate(12, (_) => lcsRandom(100000));
      reseedRNG(seed: 4882);
      for (final key in ['a', 'b', 'c', 'd', 'e', 't', 'm']) {
        final category = engine.console.actions.singleWhere(
          (action) =>
              action.entityType == 'activity-category' && action.key == key,
        );
        expect(
          await journal.browseCategory(
            category,
            revision: engine.console.revision.value,
          ),
          isTrue,
        );
        expect(activityOrderFrame(engine.console)?.selectedCategoryKey, key);
        expect(activityOrderFrame(engine.console)?.actorId, person.id);
        expect(person.activity, same(order));
        expect(_snapshot(), before);
      }
      expect(List.generate(12, (_) => lcsRandom(100000)), rolls);
      expect(await journal.returnToHeadquarters(), isTrue);
      expect(person.activity, same(order));
      expect(_snapshot(), before);
    },
  );

  test(
    'both sleeper categories preview without clearing undercover orders',
    () async {
      final person = _extraPerson()..sleeperAgent = true;
      final order = Activity(ActivityType.sleeperSpy);
      person.activity = order;
      final journal = start();
      expect(await journal.openOrders(person.id), isTrue);
      final before = _snapshot();
      reseedRNG(seed: 9820);
      final rolls = List.generate(12, (_) => lcsRandom(100000));
      reseedRNG(seed: 9820);
      for (final key in ['a', 'b']) {
        final category = engine.console.actions.singleWhere(
          (action) =>
              action.key == key &&
              (action.entityType == 'sleeper-category' ||
                  action.entityType == 'sleeper-category-selected'),
        );
        expect(
          await journal.browseCategory(
            category,
            revision: engine.console.revision.value,
          ),
          isTrue,
        );
        expect(activityOrderFrame(engine.console)?.selectedCategoryKey, key);
        expect(activityOrderFrame(engine.console)?.sleeper, isTrue);
        expect(person.activity, same(order));
        expect(_snapshot(), before);
      }
      expect(List.generate(12, (_) => lcsRandom(100000)), rolls);
      expect(await journal.returnToHeadquarters(), isTrue);
      expect(person.activity, same(order));
      expect(_snapshot(), before);
    },
  );

  test(
    'Confirm applies the actual task once and returns to headquarters',
    () async {
      final person = game.pool.first;
      person.activity = Activity(ActivityType.sellMusic);
      final journal = start();
      final date = game.date;
      final funds = game.ledger.funds;
      expect(await journal.openOrders(person.id), isTrue);
      final category = engine.console.actions.singleWhere(
        (action) =>
            action.entityType == 'activity-category' && action.key == 'b',
      );
      expect(
        await journal.browseCategory(
          category,
          revision: engine.console.revision.value,
        ),
        isTrue,
      );
      final task = engine.console.actions.singleWhere(
        (action) =>
            action.entityType == 'activity' && action.entityId == 'donations',
      );
      final oldOrder = person.activity;
      final before = _snapshot();
      final taskRevision = engine.console.revision.value;
      expect(
        person.activity,
        same(oldOrder),
        reason: 'Merely staging a task does not send it.',
      );
      reseedRNG(seed: 11289);
      final rolls = List.generate(8, (_) => lcsRandom(100000));
      reseedRNG(seed: 11289);
      expect(await journal.commitOrder(task, revision: taskRevision), isTrue);
      expect(engine.console.screen, 'headquarters');
      expect(person.activity.type, ActivityType.donations);
      expect(person.activity, isNot(same(oldOrder)));
      expect(game.date, date);
      expect(game.ledger.funds, funds);
      expect(List.generate(8, (_) => lcsRandom(100000)), rolls);
      final expected = jsonDecode(before) as Map<String, dynamic>;
      final after = jsonDecode(_snapshot()) as Map<String, dynamic>;
      final expectedPool =
          (expected['lcs'] as Map<String, dynamic>)['pool'] as List;
      final afterPool = (after['lcs'] as Map<String, dynamic>)['pool'] as List;
      final index = game.pool.indexOf(person);
      (expectedPool[index] as Map<String, dynamic>)['activity'] =
          (afterPool[index] as Map<String, dynamic>)['activity'];
      expect(after, expected);
      final committed = _snapshot();
      expect(await journal.commitOrder(task, revision: taskRevision), isFalse);
      expect(_snapshot(), committed);
    },
  );

  test(
    'sleeper Confirm applies the task and keeps its original timing',
    () async {
      final person = _extraPerson()..sleeperAgent = true;
      person.activity = Activity(ActivityType.sleeperLiberal);
      final journal = start();
      final date = game.date;
      final funds = game.ledger.funds;
      expect(await journal.openOrders(person.id), isTrue);
      final category = engine.console.actions.singleWhere(
        (action) =>
            action.entityType == 'sleeper-category' && action.key == 'b',
      );
      expect(
        await journal.browseCategory(
          category,
          revision: engine.console.revision.value,
        ),
        isTrue,
      );
      final task = engine.console.actions.singleWhere(
        (action) =>
            action.entityType == 'sleeper-activity' &&
            action.entityId == 'sleeperEmbezzle',
      );
      final infiltration = person.infiltration;
      expect(
        await journal.commitOrder(
          task,
          revision: engine.console.revision.value,
        ),
        isTrue,
      );
      expect(engine.console.screen, 'headquarters');
      expect(person.activity.type, ActivityType.sleeperEmbezzle);
      expect(person.infiltration, infiltration);
      expect(game.date, date);
      expect(game.ledger.funds, funds);
    },
  );

  for (final nested in ['study', 'makeClothing', 'interrogation']) {
    test('Confirm leaves the required $nested choice explicit', () async {
      final person = game.pool.first;
      person.activity = Activity(ActivityType.donations);
      if (nested == 'interrogation') {
        _extraPerson().align = Alignment.conservative;
        _extraPerson().align = Alignment.conservative;
      }
      final journal = start();
      expect(await journal.openOrders(person.id), isTrue);
      if (nested != 'interrogation') {
        final category = engine.console.actions.singleWhere(
          (action) =>
              action.entityType == 'activity-category' &&
              action.key == (nested == 'study' ? 'e' : 'd'),
        );
        expect(
          await journal.browseCategory(
            category,
            revision: engine.console.revision.value,
          ),
          isTrue,
        );
      }
      final task = engine.console.actions.singleWhere(
        (action) =>
            action.entityType == 'activity' && action.entityId == nested,
      );
      final before = _snapshot();
      final order = person.activity;
      expect(
        await journal.commitOrder(
          task,
          revision: engine.console.revision.value,
        ),
        isTrue,
      );
      expect(engine.console.awaitingInput, isTrue);
      expect(engine.console.screen, isNot('headquarters'));
      expect(activityOrderFrame(engine.console), isNull);
      expect(engine.console.navigation, isNull);
      expect(person.activity, same(order));
      expect(_snapshot(), before);
      expect(await journal.returnToHeadquarters(), isFalse);
      expect(_snapshot(), before);
    });
  }

  test(
    'preview and Confirm reject stale and wrong-kind source choices',
    () async {
      final person = game.pool.first;
      final journal = start();
      expect(await journal.openOrders(person.id), isTrue);
      final category = engine.console.actions.singleWhere(
        (action) =>
            action.entityType == 'activity-category' && action.key == 'b',
      );
      final oldRevision = engine.console.revision.value;
      final before = _snapshot();
      expect(
        await journal.commitOrder(category, revision: oldRevision),
        isFalse,
      );
      expect(
        await journal.browseCategory(category, revision: oldRevision),
        isTrue,
      );
      expect(
        await journal.browseCategory(category, revision: oldRevision),
        isFalse,
      );
      final task = engine.console.actions.singleWhere(
        (action) =>
            action.entityType == 'activity' && action.entityId == 'donations',
      );
      expect(
        await journal.browseCategory(
          task,
          revision: engine.console.revision.value,
        ),
        isFalse,
      );
      expect(await journal.commitOrder(task, revision: oldRevision), isFalse);
      expect(_snapshot(), before);
    },
  );

  test(
    'legacy category letters retain their original immediate behavior',
    () async {
      final person = _extraPerson()..sleeperAgent = true;
      final order = Activity(ActivityType.sleeperSpy);
      person.activity = order;
      final journal = start();
      expect(await journal.openOrders(person.id), isTrue);
      final category = engine.console.actions.singleWhere(
        (action) =>
            action.entityType == 'sleeper-category' && action.key == 'b',
      );
      expect(
        await journal.sendAction(
          category,
          revision: engine.console.revision.value,
        ),
        isTrue,
      );
      expect(person.activity.type, ActivityType.none);
      expect(person.activity, isNot(same(order)));
    },
  );

  test(
    'read-only inspection and frame data do not alter save, time or RNG',
    () async {
      final journal = start();
      expect(await journal.openAllocation(game.activeSquad!.id), isTrue);
      final before = _snapshot();
      final revision = engine.console.revision.value;
      reseedRNG(seed: 1444);
      final rolls = List.generate(8, (_) => lcsRandom(100000));
      reseedRNG(seed: 1444);
      for (var i = 0; i < 3; i++) {
        journal.inspectPerson(game.pool[i].id);
        expect(journal.selectedPerson, same(game.pool[i]));
        expect(journal.allocationMembers.length, 5);
        expect(journal.allocationPool.length, 5);
        expect(journal.allocationBlockReason(game.pool[i].id), isNull);
        expect(journal.canNavigate, isTrue);
      }
      journal.clearInspection();
      expect(_snapshot(), before);
      expect(engine.console.revision.value, revision);
      expect(List.generate(8, (_) => lcsRandom(100000)), rolls);
    },
  );

  test(
    'stale IDs and captured actions never dispatch an unrelated key',
    () async {
      final journal = start();
      final before = _snapshot();
      expect(await journal.selectSquad(999999), isFalse);
      expect(await journal.assignPerson(999999), isFalse);
      expect(await journal.openOrders(999999), isFalse);
      expect(_snapshot(), before);
      final action = engine.console.actions.first;
      final revision = engine.console.revision.value;
      expect(await journal.selectSquad(game.activeSquad!.id), isTrue);
      final overview = _snapshot();
      expect(await journal.sendAction(action, revision: revision), isFalse);
      expect(journal.message, contains('changed'));
      expect(engine.console.screen, 'headquarters');
      expect(_snapshot(), overview);
    },
  );

  test(
    'legacy squad View reader cannot inherit allocation capability or auto-exit',
    () async {
      final journal = start();
      expect(await journal.openAllocation(game.activeSquad!.id), isTrue);
      final before = _snapshot();
      final view = engine.console.actions.singleWhere(
        (action) => action.key == 'v',
      );
      expect(
        await journal.sendAction(view, revision: engine.console.revision.value),
        isTrue,
      );
      expect(engine.console.awaitingInput, isTrue);
      expect(
        engine.console.actions.any((action) => action.entityType == 'person'),
        isTrue,
        reason: 'The legacy nested prompt keeps the old person actions.',
      );
      expect(squadAllocationFrame(engine.console), isNull);
      final marker = engine.console.screen;
      engine.console.screen = 'squad-assembly';
      expect(
        squadAllocationFrame(engine.console),
        isNull,
        reason:
            'Even a stale marker cannot revive an erased squad-ready action.',
      );
      engine.console.screen = marker;
      expect(await journal.returnToHeadquarters(), isFalse);
      expect(_snapshot(), before);
      expect(engine.console.sendInput('Escape'), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 4));
      expect(squadAllocationFrame(engine.console), isNotNull);
      expect(_snapshot(), before);
    },
  );

  test(
    'original mobility-error reader cannot inherit allocation capability',
    () async {
      final person = _extraPerson();
      final body = person.body as HumanoidBody;
      body.leftLeg.cleanOff = true;
      body.rightLeg.cleanOff = true;
      final journal = start();
      expect(await journal.openAllocation(game.activeSquad!.id), isTrue);
      final before = _snapshot();
      final action = engine.console.actions.singleWhere(
        (action) =>
            action.entityType == 'person' &&
            action.entityId == person.id.toString(),
      );
      expect(
        engine.console.sendInput(action.key),
        isTrue,
        reason:
            'Exercise the original keyboard error path, not the modern guard.',
      );
      await Future<void>.delayed(const Duration(milliseconds: 4));
      expect(engine.console.awaitingInput, isTrue);
      expect(squadAllocationFrame(engine.console), isNull);
      final marker = engine.console.screen;
      engine.console.screen = 'squad-assembly';
      expect(squadAllocationFrame(engine.console), isNull);
      engine.console.screen = marker;
      expect(await journal.returnToHeadquarters(), isFalse);
      expect(_snapshot(), before);
      expect(engine.console.sendInput('Escape'), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 4));
      expect(squadAllocationFrame(engine.console), isNotNull);
      expect(_snapshot(), before);
    },
  );

  test(
    'activity capability requires exact confirmation and navigation identity',
    () async {
      final journal = start();
      expect(await journal.openOrders(game.pool.first.id), isTrue);
      final frame = activityOrderFrame(engine.console)!;
      final before = _snapshot();
      engine.console.navigation = ConsoleNavigation(
        section: frame.navigation.section,
        backKey: frame.navigation.backKey,
        note: frame.navigation.note,
      );
      expect(
        activityOrderFrame(engine.console),
        isNull,
        reason:
            'A different reader with matching navigation text is not this await.',
      );
      engine.console.navigation = frame.navigation;
      expect(activityOrderFrame(engine.console), same(frame));
      final index = engine.console.actions.indexOf(frame.confirmation);
      final original = frame.confirmation;
      engine.console.actions[index] = ConsoleAction(
        key: original.key,
        label: original.label,
        enabled: original.enabled,
        y: original.y,
        x: original.x,
        width: original.width,
        entityType: original.entityType,
        entityId: original.entityId,
        entityCategory: original.entityCategory,
      );
      expect(
        activityOrderFrame(engine.console),
        isNull,
        reason: 'A replaced choice cannot resurrect a previous capability.',
      );
      engine.console.actions[index] = original;
      expect(activityOrderFrame(engine.console), same(frame));
      expect(_snapshot(), before);
    },
  );

  test(
    'real required skill reader rejects restored activity markers and navigation',
    () async {
      final journal = start();
      expect(await journal.openOrders(game.pool.first.id), isTrue);
      final category = engine.console.actions.singleWhere(
        (action) =>
            action.entityType == 'activity-category' && action.key == 'e',
      );
      expect(
        await journal.browseCategory(
          category,
          revision: engine.console.revision.value,
        ),
        isTrue,
      );
      final frame = activityOrderFrame(engine.console)!;
      final task = engine.console.actions.singleWhere(
        (action) =>
            action.entityType == 'activity' && action.entityId == 'study',
      );
      final before = _snapshot();
      expect(
        await journal.commitOrder(
          task,
          revision: engine.console.revision.value,
        ),
        isTrue,
      );
      expect(activityOrderFrame(engine.console), isNull);
      final marker = engine.console.screen;
      engine.console.screen = 'activity-orders';
      engine.console.navigation = frame.navigation;
      expect(
        activityOrderFrame(engine.console),
        isNull,
        reason:
            'The actual source skill choices have removed the old confirmation.',
      );
      engine.console.navigation = null;
      engine.console.screen = marker;
      expect(await journal.returnToHeadquarters(), isFalse);
      expect(_snapshot(), before);
    },
  );

  for (final prompt in ['unsafe', 'text', 'tactical']) {
    test('controller never unwinds $prompt prompts', () async {
      if (prompt == 'tactical') game.mode = GameMode.site;
      engine.console.textInput = prompt == 'text';
      engine.console.screen = 'generic';
      final input = engine.getKey();
      final journal = controller = OrganisationController(
        console: engine.console,
      );
      final before = _snapshot();
      final revision = engine.console.revision.value;
      expect(journal.canNavigate, isFalse);
      expect(await journal.returnToHeadquarters(), isFalse);
      expect(await journal.openAllocation(game.activeSquad!.id), isFalse);
      expect(_snapshot(), before);
      expect(engine.console.revision.value, revision);
      expect(engine.console.awaitingInput, isTrue);
      engine.console.sendInput('Escape');
      expect(await input, engine.Key.escape);
    });
  }

  test(
    'busy controller rejects duplicate clicks without duplicate mutation',
    () async {
      final extra = _extraPerson();
      final journal = start();
      expect(await journal.openAllocation(game.activeSquad!.id), isTrue);
      final first = journal.assignPerson(extra.id);
      expect(journal.busy, isTrue);
      expect(await journal.assignPerson(extra.id), isFalse);
      expect(await first, isTrue);
      expect(game.activeSquad!.members.where((p) => p == extra).length, 1);
    },
  );
}
