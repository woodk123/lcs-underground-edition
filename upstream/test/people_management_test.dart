import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/basemode/review_mode.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/modern/journal_people.dart';
import 'package:lcs_new_age/modern/personnel_directory.dart';
import 'package:lcs_new_age/politics/alignment.dart' as politics;
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

String _snapshot() => jsonEncode(game.gameState.toJson());
Finder _key(String value) => find.byKey(ValueKey(value));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String fixture;
  late String template;
  PersonnelDirectoryController? directory;
  Future<void>? reader;

  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
  });

  setUp(() {
    game.gameState = decodeSaveContents(fixture).gameState!;
    game.mode = GameMode.base;
    engine.console = Console();
    template = jsonEncode(game.pool.first.toJson());
  });

  tearDown(() async {
    directory?.dispose();
    directory = null;
    if (reader != null) {
      engine.console.sendInput('Escape');
      await reader!.timeout(const Duration(seconds: 2));
      reader = null;
    }
  });

  Creature person(int id, String name) {
    final p = Creature.fromJson(jsonDecode(template) as Map<String, dynamic>);
    p
      ..id = id
      ..name = name
      ..squadId = null
      ..hireId = null
      ..alive = true
      ..align = politics.Alignment.liberal
      ..sleeperAgent = false
      ..hidingDaysLeft = 0
      ..vacationDaysLeft = 0
      ..seduced = false
      ..brainwashed = false
      ..juice = 1000
      ..location = game.sites.firstWhere(
        (s) => s.type == SiteType.homelessEncampment,
      )
      ..activity = Activity.none();
    return p;
  }

  test('available outside squads excludes every unavailable status', () {
    final crew = List.generate(9, (i) => person(9000 + i, 'Crew $i'));
    crew[1].squad = game.activeSquad;
    crew[2].location = game.sites.firstWhere(
      (s) => s.type == SiteType.universityHospital,
    );
    crew[3].location = game.sites.firstWhere(
      (s) => s.type == SiteType.policeStation,
    );
    crew[4].sleeperAgent = true;
    crew[5].hidingDaysLeft = -1;
    crew[6].vacationDaysLeft = 3;
    crew[7].alive = false;
    crew[8].align = politics.Alignment.conservative;
    expect(
      crew.where(
        (p) =>
            personnelMatchesFilter(p, PersonnelFilter.availableOutsideSquads),
      ),
      [crew.first],
    );
  });

  test(
    'staffing reads the actual captive location and leaves away orders intact',
    () {
      final captive = person(9010, 'Captive')
        ..align = politics.Alignment.conservative;
      final present = person(9011, 'Present tender')
        ..activity = Activity(ActivityType.interrogation, idInt: captive.id);
      final away = person(9012, 'Away tender')
        ..location = game.sites.firstWhere(
          (s) => s.type == SiteType.universityHospital,
        )
        ..activity = Activity(ActivityType.interrogation, idInt: captive.id);
      final dead = person(9013, 'Dead tender')
        ..alive = false
        ..activity = Activity(ActivityType.interrogation, idInt: captive.id);
      final wrongTarget = person(9014, 'Other assignment')
        ..activity = Activity(ActivityType.interrogation, idInt: 99999);
      final crew = [captive, present, away, dead, wrongTarget];
      expect(captiveAssignedTenders(captive, crew), [present, away]);
      expect(captivePresentTenders(captive, crew), [present]);
      expect(captiveTenderCandidates(captive, crew), [present, wrongTarget]);
      expect(away.activity.idInt, captive.id);
      captive.location = null;
      expect(captivePresentTenders(captive, crew), isEmpty);
      expect(captiveTenderCandidates(captive, crew), isEmpty);
    },
  );

  test(
    'promotion source publishes exact IDs and preserves browsing state and RNG',
    () async {
      final founder = person(9100, 'Founder');
      final contact = person(9101, 'Contact')..hireId = founder.id;
      final recruit = person(9102, 'Recruit')..hireId = contact.id;
      game.pool
        ..clear()
        ..addAll([founder, contact, recruit]);
      final before = _snapshot();
      reseedRNG(seed: 770001);
      final rolls = List.generate(8, (_) => lcsRandom(100000));
      reseedRNG(seed: 770001);
      reader = promoteliberals();
      expect(engine.console.screen, 'leadership');
      expect(engine.console.navigation?.section, 'people');
      final action = engine.console.actions.singleWhere(
        (a) =>
            a.entityType == 'promotion-person' &&
            a.entityId == recruit.id.toString(),
      );
      expect(action.enabled, isTrue);
      expect(action.entityCategory, founder.id.toString());
      expect(
        engine.console.actions
            .singleWhere(
              (a) =>
                  a.entityType == 'promotion-person' &&
                  a.entityId == founder.id.toString(),
            )
            .enabled,
        isFalse,
      );
      expect(_snapshot(), before);
      expect(List.generate(8, (_) => lcsRandom(100000)), rolls);
      expect(leadershipPromotionTarget(recruit, game.pool), founder);
      expect(leadershipPromotionUnavailableReason(recruit, game.pool), isNull);
      engine.console.sendInput(action.key);
      await Future<void>.delayed(Duration.zero);
      expect(recruit.hireId, founder.id);
      expect(contact.hireId, founder.id);
      expect(
        leadershipPromotionUnavailableReason(recruit, game.pool),
        isNotNull,
      );
      // The letter immediately after the last roster entry used to index past
      // the list. It must be harmless in the source handler.
      engine.console.sendInput('d');
      await Future<void>.delayed(Duration.zero);
      expect(recruit.hireId, founder.id);
    },
  );

  test(
    'promotion limits match original hiding, seduction and capacity rules',
    () {
      final founder = person(9150, 'Founder');
      final contact = person(9151, 'Contact')..hireId = founder.id;
      final recruit = person(9152, 'Recruit')..hireId = contact.id;
      game.pool
        ..clear()
        ..addAll([founder, contact, recruit]);
      recruit.hidingDaysLeft = -1;
      expect(
        leadershipPromotionUnavailableReason(recruit, game.pool),
        contains('hiding'),
      );
      recruit
        ..hidingDaysLeft = 0
        ..seduced = true;
      expect(
        leadershipPromotionUnavailableReason(recruit, game.pool),
        contains('lover'),
      );
      recruit.seduced = false;
      founder.brainwashed = true;
      expect(
        leadershipPromotionUnavailableReason(recruit, game.pool),
        contains('no free'),
      );
      recruit.brainwashed = true;
      expect(leadershipPromotionUnavailableReason(recruit, game.pool), isNull);
    },
  );

  test(
    'promotion source exposes usable pages beyond the first nineteen people',
    () async {
      final founder = person(9160, 'Founder');
      final contact = person(9161, 'Contact')..hireId = founder.id;
      final recruits = List.generate(
        23,
        (i) => person(9170 + i, 'Recruit $i')..hireId = contact.id,
      );
      game.pool
        ..clear()
        ..addAll([founder, contact, ...recruits]);
      final before = _snapshot();
      reader = promoteliberals();
      final next = engine.console.actions.singleWhere(
        (a) => a.label.contains('Next Page'),
      );
      engine.console.sendInput(next.key);
      await Future<void>.delayed(Duration.zero);
      expect(
        engine.console.actions
            .where((a) => a.entityType == 'promotion-person')
            .length,
        6,
      );
      expect(
        engine.console.actions.any(
          (a) =>
              a.entityType == 'promotion-person' &&
              a.entityId == recruits.last.id.toString(),
        ),
        isTrue,
      );
      expect(_snapshot(), before);
    },
  );

  Future<void> mount(
    WidgetTester tester,
    List<Creature> people, {
    JournalPeopleScope scope = JournalPeopleScope.people,
    ValueChanged<Creature>? assign,
    ValueChanged<Creature>? join,
    ValueChanged<Creature>? tender,
    double scale = 1,
    Size size = const Size(900, 900),
  }) async {
    directory ??= PersonnelDirectoryController();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(12),
              child: JournalPeopleView(
                people: people,
                directoryController: directory!,
                initialScope: scope,
                onOpenProfile: (_) {},
                onAssignOrder: assign ?? (_) {},
                onJoinSquad: join ?? (_) {},
                onAssignTender: tender ?? (_) {},
                onOpenPromotionTools: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('outside-squad orders and membership are distinct actions', (
    tester,
  ) async {
    final crew = person(9200, 'Ada Available');
    final ordered = <int>[];
    final joined = <int>[];
    directory = PersonnelDirectoryController()
      ..selectFilter(PersonnelFilter.availableOutsideSquads);
    final before = _snapshot();
    await mount(
      tester,
      [crew],
      assign: (p) => ordered.add(p.id),
      join: (p) => joined.add(p.id),
    );
    await tester.ensureVisible(_key('personnel-assign-order:${crew.id}'));
    await tester.tap(_key('personnel-assign-order:${crew.id}'));
    expect(ordered, [crew.id]);
    expect(joined, isEmpty);
    await tester.tap(_key('personnel-join-squad:${crew.id}'));
    expect(joined, [crew.id]);
    expect(crew.squadId, isNull);
    expect(_snapshot(), before);
  });

  testWidgets(
    'captive staffing explains unattended and routes chosen active crew',
    (tester) async {
      final captive = person(9300, 'Casey Captive')
        ..align = politics.Alignment.conservative;
      final crew = person(9301, 'Taylor Tender');
      final ordered = <int>[];
      final before = _snapshot();
      await mount(
        tester,
        [captive, crew],
        scope: JournalPeopleScope.captives,
        tender: (p) => ordered.add(p.id),
      );
      expect(find.text('UNATTENDED · No tender present'), findsOneWidget);
      await tester.tap(_key('captive-staff:${captive.id}'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        _key('captive-choose-tender:${captive.id}:${crew.id}'),
      );
      await tester.tap(_key('captive-choose-tender:${captive.id}:${crew.id}'));
      expect(ordered, [crew.id]);
      expect(crew.activity.type, ActivityType.none);
      expect(_snapshot(), before);
      expect(tester.takeException(), isNull);
    },
  );

  for (final scope in JournalPeopleScope.values) {
    testWidgets('${scope.name} remains usable at narrow width and large text', (
      tester,
    ) async {
      final leader = person(9400, 'Long Named Movement Leader');
      final recruit = person(9401, 'A Recently Recruited Person')
        ..hireId = leader.id;
      final captive = person(9402, 'A Captive At The Safehouse')
        ..align = politics.Alignment.conservative;
      await mount(
        tester,
        [leader, recruit, captive],
        scope: scope,
        size: const Size(480, 850),
        scale: 1.5,
      );
      expect(tester.takeException(), isNull);
      expect(_key('people-scope:${scope.name}'), findsOneWidget);
    });
  }
}
