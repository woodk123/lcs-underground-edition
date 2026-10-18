import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/creature/creature.dart';
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
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

String _snapshot() => jsonEncode(game.gameState.toJson());
Finder _key(String value) => find.byKey(ValueKey(value));

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
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final target = _key(key);
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
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
      expect((openedPeople, openedBases, openedStores), (1, 1, 1));
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
      await tester.ensureVisible(stock);
      await tester.pumpAndSettle();
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
      expect(
        tester
            .widget<OutlinedButton>(_key('media-production-stores'))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
