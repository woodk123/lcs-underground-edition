import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' hide Alignment, View;
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/daily/activities/guardian.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/engine/media_production_context.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/items/loot.dart';
import 'package:lcs_new_age/items/loot_type.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/modern/journal_media_production.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/monthly/lcs_monthly.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/politics/views.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

String _snapshot() => jsonEncode(game.gameState.toJson());
Finder _key(String value) => find.byKey(ValueKey(value));
Creature _copy(Creature person) =>
    Creature.fromJson(jsonDecode(jsonEncode(person)) as Map<String, dynamic>);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String fixture;
  late Creature person;
  late Site home;

  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
  });

  setUp(() {
    game.gameState = decodeSaveContents(fixture).gameState!;
    person = game.pool.first;
    home = game.sites.firstWhere((s) => s.controller == SiteController.lcs);
    person
      ..location = home
      ..base = home
      ..squadId = null
      ..activity = Activity.none()
      ..hidingDaysLeft = 0
      ..vacationDaysLeft = 0;
    home.compound.videoRoom = false;
    for (final site in game.sites) {
      site.loot.clear();
    }
  });

  test(
    'monthly publisher eligibility applies the same active check to writers and streamers',
    () {
      final hospital = game.sites.firstWhere(
        (site) => site.type == SiteType.universityHospital,
      );
      final prison = game.sites.firstWhere(
        (site) => site.type == SiteType.prison,
      );
      for (final activity in [
        ActivityType.writeGuardian,
        ActivityType.streamGuardian,
      ]) {
        Creature candidate() => _copy(person)..activity = Activity(activity);
        final available = candidate();
        final dead = candidate()..alive = false;
        final conservative = candidate()..align = Alignment.conservative;
        final sleeper = candidate()..sleeperAgent = true;
        final patient = candidate()..location = hospital;
        final prisoner = candidate()..location = prison;
        final vacationer = candidate()..vacationDaysLeft = 1;
        final hiding = candidate()..hidingDaysLeft = 1;
        final resting = candidate()..activity = Activity.none();

        final before = _snapshot();
        reseedRNG(seed: 74311);
        final expectedRoll = nextRngSeed;
        reseedRNG(seed: 74311);
        expect(
          guardianSpecialEditionPublishers([
            available,
            dead,
            conservative,
            sleeper,
            patient,
            prisoner,
            vacationer,
            hiding,
            resting,
          ]),
          orderedEquals([available]),
          reason: activity.name,
        );
        expect(_snapshot(), before);
        expect(nextRngSeed, expectedRoll);
      }
    },
  );

  test(
    'evidence preview shares all 16 source IDs, groups per location and never consolidates',
    () {
      expect(guardianSpecialEditionEvidenceIds, hasLength(16));
      expect(guardianSpecialEditionEvidenceIds.toSet(), hasLength(16));
      for (final id in guardianSpecialEditionEvidenceIds) {
        home.loot.add(Loot(id, stackSize: 2));
      }
      home.loot
        ..add(Loot(LootTypeIds.corpFiles, stackSize: 3))
        ..add(Loot(LootTypeIds.cheapJewelry, stackSize: 4));
      final other = game.sites.firstWhere((s) => s != home);
      other
        ..controller = SiteController.lcs
        ..loot.add(Loot(LootTypeIds.corpFiles));
      final enemy = game.sites.firstWhere((s) => s != home && s != other);
      enemy
        ..controller = SiteController.unaligned
        ..loot.add(Loot(LootTypeIds.policeRecords, stackSize: 7));
      final before = _snapshot();
      reseedRNG(seed: 99172);
      final expectedRoll = nextRngSeed;
      reseedRNG(seed: 99172);

      final stocks = mediaProductionEvidence();

      expect(stocks, hasLength(17));
      expect(
        stocks.where((s) => s.site == home).map((s) => s.typeId),
        orderedEquals(guardianSpecialEditionEvidenceIds),
      );
      expect(
        stocks
            .singleWhere(
              (s) => s.site == home && s.typeId == LootTypeIds.corpFiles,
            )
            .quantity,
        5,
      );
      expect(stocks.singleWhere((s) => s.site == other).quantity, 1);
      expect(stocks.any((s) => s.site == enemy), isFalse);
      expect(stocks.any((s) => s.typeId == LootTypeIds.cheapJewelry), isFalse);
      expect(
        home.loot.whereType<Loot>().where(
          (i) => i.typeName == LootTypeIds.corpFiles,
        ),
        hasLength(2),
      );
      expect(_snapshot(), before);
      expect(nextRngSeed, expectedRoll);
    },
  );

  test(
    'preview evidence matches the actual monthly decision without publishing',
    () async {
      for (final id in guardianSpecialEditionEvidenceIds) {
        home.loot.add(Loot(id));
      }
      home.loot.add(Loot(LootTypeIds.cheapJewelry));
      home.loot.sort();
      final expected = mediaProductionEvidence().map((s) => s.name).toList();
      final before = _snapshot();
      engine.console = Console();
      final labels = <String>[];
      void respond() {
        if (!engine.console.awaitingInput || engine.console.lastKey != null) {
          return;
        }
        labels.addAll(
          engine.console.actions
              .where((action) => RegExp(r'^[a-p]$').hasMatch(action.key))
              .map(
                (action) => action.label
                    .replaceFirst(RegExp(r'^[A-Za-z] - '), '')
                    .trim(),
              ),
        );
        engine.console.sendInput('Escape');
      }

      engine.console.revision.addListener(respond);
      try {
        expect(
          await chooseSpecialEdition().timeout(const Duration(seconds: 5)),
          isNull,
        );
      } finally {
        engine.console.revision.removeListener(respond);
      }
      expect(labels, unorderedEquals(expected));
      expect(_snapshot(), before);
    },
  );

  test(
    'writing is available without studio; streaming requires that person’s local studio',
    () {
      final other = game.sites.firstWhere((s) => s != home);
      other.compound.videoRoom = true;
      expect(
        mediaProductionUnavailableReason(person, ActivityType.writeGuardian),
        isNull,
      );
      expect(
        mediaProductionUnavailableReason(person, ActivityType.streamGuardian),
        contains('current location'),
      );
      person.location = other;
      expect(
        mediaProductionUnavailableReason(person, ActivityType.streamGuardian),
        isNull,
      );
      person.activity = Activity(ActivityType.streamGuardian);
      expect(
        mediaProductionDailyWarning(person),
        contains('Home base has no studio'),
      );
      home.compound.videoRoom = true;
      expect(mediaProductionDailyWarning(person), isNull);
    },
  );

  test(
    'source actor eligibility explains absence rather than suggesting assignments',
    () {
      person.vacationDaysLeft = 1;
      expect(
        mediaProductionUnavailableReason(person, ActivityType.writeGuardian),
        'Away on vacation',
      );
      person
        ..vacationDaysLeft = 0
        ..hidingDaysLeft = 2;
      expect(
        mediaProductionUnavailableReason(person, ActivityType.writeGuardian),
        'In hiding',
      );
      person
        ..hidingDaysLeft = 0
        ..sleeperAgent = true;
      expect(
        mediaProductionUnavailableReason(person, ActivityType.writeGuardian),
        contains('Network'),
      );
      person.sleeperAgent = false;
      final hospital = game.sites.firstWhere(
        (s) => s.type == SiteType.universityHospital,
      );
      person.location = hospital;
      expect(
        mediaProductionUnavailableReason(person, ActivityType.writeGuardian),
        'In hospital',
      );
    },
  );

  test(
    'next monthly review follows the campaign calendar including year rollover',
    () {
      expect(
        nextMediaProductionReview(DateTime(2023, 1, 4)),
        '1 February 2023',
      );
      expect(
        nextMediaProductionReview(DateTime(2023, 12, 31)),
        '1 January 2024',
      );
    },
  );

  Future<void> mount(
    WidgetTester tester, {
    ValueChanged<MediaProductionRequest>? onAssign,
    VoidCallback? onOpenPeople,
    VoidCallback? onOpenBases,
    VoidCallback? onOpenStores,
    VoidCallback? onOpenArchive,
    bool enabled = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 600);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildJournalTheme(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
            body: JournalMediaProductionView(
              enabled: enabled,
              onAssign: onAssign ?? (_) {},
              onOpenPeople: onOpenPeople ?? () {},
              onOpenBases: onOpenBases ?? () {},
              onOpenStores: onOpenStores ?? () {},
              onOpenArchive: onOpenArchive,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, Finder target) async {
    final scrollable = find
        .descendant(
          of: _key('media-production-scroll'),
          matching: find.byType(Scrollable),
        )
        .first;
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(target, 240, scrollable: scrollable);
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final target = _key(key);
    await reveal(tester, target);
    expect(target.hitTestable(), findsOneWidget);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'production is readable at 800x600 and 150%, prepares source orders without saving',
    (tester) async {
      final requests = <MediaProductionRequest>[];
      var openedPeople = 0;
      var openedBases = 0;
      var openedStores = 0;
      var openedArchive = 0;
      final before = _snapshot();
      reseedRNG(seed: 68431);
      final expectedRoll = nextRngSeed;
      reseedRNG(seed: 68431);
      await mount(
        tester,
        onAssign: requests.add,
        onOpenPeople: () => openedPeople++,
        onOpenBases: () => openedBases++,
        onOpenStores: () => openedStores++,
        onOpenArchive: () => openedArchive++,
      );
      expect(_key('media-production-no-producers'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(
              _key('media-production-assign:streamGuardian'),
            )
            .onPressed,
        isNull,
      );
      await tap(tester, 'media-production-person');
      final chosenPerson = find.text(person.name).last;
      await tester.ensureVisible(chosenPerson);
      await tester.pumpAndSettle();
      await tester.tap(chosenPerson);
      await tester.pumpAndSettle();
      await tap(tester, 'media-production-assign:writeGuardian');
      expect(requests.single.person, same(person));
      expect(requests.single.activity, ActivityType.writeGuardian);
      await tap(tester, 'media-production-people');
      await tap(tester, 'media-production-bases');
      await tap(tester, 'media-production-stores');
      await tap(tester, 'media-production-archive');
      expect(
        (openedPeople, openedBases, openedStores, openedArchive),
        (1, 1, 1, 1),
      );
      await reveal(tester, _key('media-production-no-evidence'));
      expect(_key('media-production-no-evidence'), findsOneWidget);
      expect(find.textContaining('automatically asks'), findsOneWidget);
      expect(find.textContaining('Publish now'), findsNothing);
      expect(tester.takeException(), isNull);
      expect(_snapshot(), before);
      expect(nextRngSeed, expectedRoll);
    },
  );

  testWidgets(
    'shows current production, evidence location, and eligible streaming request',
    (tester) async {
      home.compound.videoRoom = true;
      person.activity = Activity(ActivityType.writeGuardian);
      home.loot.add(Loot(LootTypeIds.corpFiles, stackSize: 2));
      final requests = <MediaProductionRequest>[];
      final before = _snapshot();
      await mount(tester, onAssign: requests.add);
      expect(_key('media-producer:${person.id}'), findsOneWidget);
      expect(
        tester.widget<Text>(_key('media-producer:${person.id}')).data,
        contains(home.getName(includeCity: true)),
      );
      await tap(tester, 'media-production-assign:streamGuardian');
      expect(requests.single.activity, ActivityType.streamGuardian);
      final stock = _key('media-evidence:${home.id}:${LootTypeIds.corpFiles}');
      await reveal(tester, stock);
      expect(tester.widget<Text>(stock).data, contains('2 copies'));
      expect(
        tester.widget<Text>(stock).data,
        contains(home.getName(includeCity: true)),
      );
      expect(_snapshot(), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'real daily media work feeds the live influence preview without creating archived posts',
    (tester) async {
      for (final skill in [
        Skill.writing,
        Skill.persuasion,
        Skill.law,
        Skill.science,
        Skill.religion,
        Skill.business,
      ]) {
        person.rawSkill[skill] = 5;
      }
      for (final view in View.values) {
        game.politics.backgroundInfluence[view] = 0;
      }
      final opinionsBefore = Map.of(game.politics.publicOpinion);
      final archiveBefore = List.of(game.gameState.newsArchive);
      reseedRNG(seed: 63912);
      doActivityWriteGuardian([person]);
      final writingInfluence = Map.of(game.politics.backgroundInfluence);
      final writingIssue = writingInfluence.entries.singleWhere(
        (entry) => entry.value != 0,
      );
      expect(writingIssue.value, greaterThan(0));
      final afterWriting = _snapshot();
      await mount(tester);
      await reveal(tester, _key('media-production-influence-total'));
      expect(
        tester.widget<Text>(_key('media-production-influence-total')).data,
        contains('${writingIssue.value} net power'),
      );
      expect(_key('media-influence:${writingIssue.key.name}'), findsNothing);
      final breakdown = find.text('Issue breakdown (1)');
      await reveal(tester, breakdown);
      await tester.tap(breakdown);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(_key('media-influence:${writingIssue.key.name}'))
            .data,
        contains('+${writingIssue.value} power'),
      );
      expect(
        find.textContaining('do not create a separate archived article'),
        findsOneWidget,
      );
      expect(_snapshot(), afterWriting);

      for (final view in View.values) {
        game.politics.backgroundInfluence[view] = 0;
      }
      reseedRNG(seed: 63912);
      doActivityStreamGuardian([person]);
      expect(
        game.politics.backgroundInfluence[writingIssue.key],
        writingIssue.value * 4,
      );
      expect(game.politics.publicOpinion, opinionsBefore);
      expect(game.gameState.newsArchive, archiveBefore);
      final afterStreaming = _snapshot();
      await mount(tester);
      await reveal(tester, _key('media-production-influence-total'));
      expect(
        tester.widget<Text>(_key('media-production-influence-total')).data,
        contains('${writingIssue.value * 4} net power'),
      );
      expect(_snapshot(), afterStreaming);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'many issue values stay collapsed below the Archive action and expand read only at 150%',
    (tester) async {
      for (final view in View.values) {
        game.politics.backgroundInfluence[view] = 0;
      }
      for (var index = 0; index < View.issues.length; index++) {
        game.politics.backgroundInfluence[View.issues[index]] = index + 1;
      }
      final before = _snapshot();
      reseedRNG(seed: 44819);
      final expectedRng = nextRngSeed;
      reseedRNG(seed: 44819);
      var openedArchive = 0;
      await mount(tester, onOpenArchive: () => openedArchive++);
      await reveal(tester, _key('media-production-archive'));
      expect(_key('media-production-archive').hitTestable(), findsOneWidget);
      for (final view in View.issues) {
        expect(_key('media-influence:${view.name}'), findsNothing);
      }
      final breakdown = find.text('Issue breakdown (${View.issues.length})');
      final tileKey = PageStorageKey(
        'media-production-influence-breakdown:${game.gameState.uniqueGameId}',
      );
      expect(find.byKey(tileKey), findsOneWidget);
      expect(
        tester.getTopLeft(_key('media-production-archive')).dy,
        lessThan(tester.getTopLeft(breakdown).dy),
      );
      await tester.tap(_key('media-production-archive'));
      await tester.pumpAndSettle();
      expect(openedArchive, 1);
      await reveal(tester, breakdown);
      await tester.tap(breakdown);
      await tester.pumpAndSettle();
      for (var index = 0; index < View.issues.length; index++) {
        final row = _key('media-influence:${View.issues[index].name}');
        expect(tester.widget<Text>(row).data, contains('+${index + 1} power'));
      }
      expect(_snapshot(), before);
      expect(nextRngSeed, expectedRng);
      await reveal(tester, breakdown);
      await tester.tap(breakdown);
      await tester.pumpAndSettle();
      expect(_key('media-influence:${View.issues.first.name}'), findsNothing);
      await reveal(tester, _key('media-production-monthly-timing'));
      expect(
        _key('media-production-monthly-timing').hitTestable(),
        findsOneWidget,
      );
      expect(_snapshot(), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'special edition planning shows staff skills, active count and publication before sleeper work',
    (tester) async {
      game.pool.removeWhere((candidate) => candidate != person);
      person.activity = Activity(ActivityType.writeGuardian);
      final unavailableStreamer = _copy(person)
        ..id = 876543
        ..activity = Activity(ActivityType.streamGuardian)
        ..vacationDaysLeft = 2;
      game.pool.add(unavailableStreamer);
      person.rawSkill[Skill.writing] = 7;
      person.rawSkill[Skill.persuasion] = 4;
      person.rawSkill[Skill.law] = 2;
      final before = _snapshot();
      await mount(tester);
      await reveal(tester, _key('media-production-person-skills'));
      expect(
        tester.widget<Text>(_key('media-production-person-skills')).data,
        contains('Writing 7 · Persuasion 4'),
      );
      await reveal(tester, _key('media-production-publisher-count'));
      expect(
        tester.widget<Text>(_key('media-production-publisher-count')).data,
        startsWith('1 active contributor'),
      );
      expect(
        tester.widget<Text>(_key('media-production-monthly-timing')).data,
        contains('before sleepers carry out their monthly orders'),
      );
      expect(
        tester.widget<Text>(_key('media-production-edition-staffing')).data,
        contains('Persuasion roll minus 5'),
      );
      expect(_snapshot(), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty crew has a reachable People action and busy state disables routing',
    (tester) async {
      game.pool.clear();
      var openedPeople = 0;
      await mount(tester, onOpenPeople: () => openedPeople++);
      expect(find.textContaining('No active crew to assign'), findsOneWidget);
      await tap(tester, 'media-production-people');
      expect(openedPeople, 1);
      await mount(tester, enabled: false);
      expect(
        tester
            .widget<OutlinedButton>(_key('media-production-people'))
            .onPressed,
        isNull,
      );
      expect(
        tester.widget<OutlinedButton>(_key('media-production-bases')).onPressed,
        isNull,
      );
      await reveal(tester, _key('media-production-stores'));
      expect(
        tester
            .widget<OutlinedButton>(_key('media-production-stores'))
            .onPressed,
        isNull,
      );
      await mount(tester, enabled: false, onOpenArchive: () {});
      await reveal(tester, _key('media-production-archive'));
      expect(
        tester
            .widget<OutlinedButton>(_key('media-production-archive'))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
