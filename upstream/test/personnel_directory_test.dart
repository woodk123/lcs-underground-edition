import 'dart:convert';
import 'dart:io';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/modern/personnel_directory.dart';
import 'package:lcs_new_age/politics/alignment.dart' as politics;
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String fixture;
  late PersonnelDirectoryController controller;
  late List<Creature> people;
  final opened = <int>[];
  Finder key(String value) => find.byKey(ValueKey(value));

  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
  });

  setUp(() {
    game.gameState = decodeSaveContents(fixture).gameState!;
    controller = PersonnelDirectoryController();
    opened.clear();
    final template = jsonEncode(game.pool.first.toJson());
    people = List.generate(8, (index) {
      final person = Creature.fromJson(
        jsonDecode(template) as Map<String, dynamic>,
      );
      person
        ..id = 8000 + index
        ..name = [
          'Ada Active',
          'Chaz Reasoner',
          'Casey Custody',
          'Sam Sleeper',
          'Holly Hiding',
          'Victor Vacation',
          'Harriet Hostage',
          'Dora Departed',
        ][index]
        ..alive = true
        ..squadId = null
        ..align = politics.Alignment.liberal
        ..sleeperAgent = false
        ..hidingDaysLeft = 0
        ..vacationDaysLeft = 0
        ..location = game.activeSafehouse;
      return person;
    });
    people[1]
      ..location = game.sites.firstWhere(
        (site) => site.type == SiteType.universityHospital,
      )
      ..medicalBills = 1360;
    people[2].location = game.sites.firstWhere(
      (site) => site.type == SiteType.policeStation,
    );
    people[3].sleeperAgent = true;
    people[4].hidingDaysLeft = 4;
    people[5].vacationDaysLeft = 3;
    people[6].align = politics.Alignment.conservative;
    people[7]
      ..alive = false
      ..location = people[1].location;
  });

  tearDown(() => controller.dispose());

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(1280, 800),
    double scale = 1,
    List<Creature>? roster,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: PersonnelDirectory(
              people: roster ?? people,
              controller: controller,
              onOpen: (person) => opened.add(person.id),
              onClose: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester, int id) async {
    final list = find
        .descendant(
          of: key('personnel-directory'),
          matching: find.byType(Scrollable),
        )
        .first;
    tester.state<ScrollableState>(list).position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      key('personnel-person:$id'),
      160,
      scrollable: list,
      maxScrolls: 100,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('all personnel includes patients, locations and unique counts', (
    tester,
  ) async {
    await mount(tester, roster: [...people, people[1]]);
    for (final person in people) {
      await reveal(tester, person.id);
      expect(key('personnel-person:${person.id}'), findsOneWidget);
    }
    await reveal(tester, 8001);
    expect(
      find.textContaining(people[1].location!.getName(includeCity: true)),
      findsWidgets,
    );
    expect(find.textContaining('1,360'), findsWidgets);
    tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .jumpTo(0);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: key('personnel-filter:all'),
        matching: find.textContaining('8'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: key('personnel-filter:hospital'),
        matching: find.textContaining('1'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('every category is visible, counted and shows its people', (
    tester,
  ) async {
    await mount(tester);
    final expected = <PersonnelFilter, List<int>>{
      PersonnelFilter.active: [0],
      PersonnelFilter.hospital: [1],
      PersonnelFilter.custody: [2],
      PersonnelFilter.sleepers: [3],
      PersonnelFilter.away: [4, 5],
      PersonnelFilter.hostages: [6],
      PersonnelFilter.dead: [7],
      PersonnelFilter.all: List.generate(8, (i) => i),
    };
    for (final entry in expected.entries) {
      final target = key('personnel-filter:${entry.key.name}');
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
      expect(controller.filter, entry.key);
      expect(
        find.text(
          '${entry.value.length} of 8 people · ${personnelFilterLabel(entry.key) == 'All' ? 'All personnel' : personnelFilterLabel(entry.key)}',
        ),
        findsOneWidget,
      );
      for (var i = 0; i < people.length; i++) {
        if (entry.value.contains(i)) {
          await reveal(tester, people[i].id);
          expect(
            key('personnel-person:${people[i].id}'),
            findsOneWidget,
            reason: '${entry.key.name} must accurately list ${people[i].name}',
          );
        }
      }
    }
  });

  testWidgets(
    'search finds a missing patient across categories and survives inspection',
    (tester) async {
      await mount(tester);
      controller.selectFilter(PersonnelFilter.active);
      await tester.pumpAndSettle();
      await tester.enterText(key('personnel-search'), 'cHaZ');
      await tester.pumpAndSettle();
      expect(controller.filter, PersonnelFilter.all);
      expect(key('personnel-person:8001'), findsOneWidget);
      expect(key('personnel-person:8000'), findsNothing);
      await tester.tap(key('personnel-person:8001'));
      expect(opened, [8001]);
      await tester.pumpWidget(const SizedBox.shrink());
      await mount(tester);
      expect(controller.query, 'cHaZ');
      expect(key('personnel-person:8001'), findsOneWidget);
      await tester.enterText(key('personnel-search'), 'No Such Person');
      await tester.pumpAndSettle();
      expect(key('personnel-empty'), findsOneWidget);
      await tester.tap(key('personnel-clear-search'));
      await tester.pumpAndSettle();
      expect(controller.query, isEmpty);
      expect(key('personnel-person:8001'), findsOneWidget);
    },
  );

  testWidgets('empty directory retains all filters and explains absence', (
    tester,
  ) async {
    await mount(tester, roster: []);
    expect(key('personnel-empty'), findsOneWidget);
    for (final filter in PersonnelFilter.values) {
      expect(key('personnel-filter:${filter.name}'), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('permanent no-contact hiding remains discoverable in Away', (
    tester,
  ) async {
    people[4]
      ..hidingDaysLeft = -1
      ..locationId = null;
    controller.selectFilter(PersonnelFilter.away);
    await mount(tester);
    expect(key('personnel-person:8004'), findsOneWidget);
    expect(find.text('In hiding'), findsOneWidget);
    expect(find.text('No contact'), findsOneWidget);
    expect(find.text('2 of 8 people · Away'), findsOneWidget);
  });

  testWidgets(
    'a roster beyond legacy page limit can search and reach its final person',
    (tester) async {
      final template = jsonEncode(people.first.toJson());
      final large = List.generate(61, (index) {
        final person = Creature.fromJson(
          jsonDecode(template) as Map<String, dynamic>,
        );
        person
          ..id = 9000 + index
          ..name = 'Crew ${index.toString().padLeft(3, '0')}';
        return person;
      });
      await mount(tester, roster: large);
      await reveal(tester, 9060);
      await tester.tap(key('personnel-person:9060'));
      expect(opened, [9060]);
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      await tester.enterText(key('personnel-search'), 'Crew 060');
      await tester.pumpAndSettle();
      expect(key('personnel-person:9060').hitTestable(), findsOneWidget);
      expect(find.text('1 of 61 people · All personnel'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final viewport in [
    (const Size(1024, 720), 1.5),
    (const Size(390, 844), 2.0),
  ]) {
    testWidgets('patient is readable and touch reachable at $viewport', (
      tester,
    ) async {
      controller.selectFilter(PersonnelFilter.hospital);
      await mount(tester, size: viewport.$1, scale: viewport.$2);
      final patient = key('personnel-person:8001');
      await reveal(tester, 8001);
      await tester.pumpAndSettle();
      expect(patient.hitTestable(), findsOneWidget);
      final rect = tester.getRect(patient);
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(viewport.$1.width));
      expect(rect.height, greaterThanOrEqualTo(44));
      await tester.tap(patient);
      expect(opened, [8001]);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'keyboard row activation and screen reader labels identify patient',
    (tester) async {
      final semantics = tester.ensureSemantics();

      controller.selectFilter(PersonnelFilter.hospital);
      await mount(tester);
      final patient = key('personnel-person:8001');
      final namedPatient = find.bySemanticsLabel(
        RegExp('Open dossier for Chaz Reasoner'),
      );
      expect(namedPatient, findsOneWidget);
      final data = tester.getSemantics(namedPatient).getSemanticsData();
      expect(data.label, contains('Chaz Reasoner'));
      expect(data.label.toLowerCase(), contains('hospital'));
      expect(
        data.hasAction(SemanticsAction.tap),
        isTrue,
        reason: 'The named screen reader control must activate the dossier.',
      );
      await tester.tap(key('personnel-search'));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      // Activate the row through its ordinary focus node, not its pointer callback.
      final label = find.descendant(
        of: patient,
        matching: find.text('Chaz Reasoner'),
      );
      Focus.of(tester.element(label)).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(opened, [8001]);
      semantics.dispose();
    },
  );

  testWidgets(
    'search, filters, sorts and inspection leave campaign and RNG untouched',
    (tester) async {
      final before = jsonEncode(game.gameState.toJson());
      final personBefore = people
          .map((person) => jsonEncode(person.toJson()))
          .toList();
      reseedRNG(seed: 298164);
      final rolls = List.generate(16, (_) => lcsRandom(100000));
      reseedRNG(seed: 298164);
      await mount(tester);
      await tester.enterText(key('personnel-search'), 'chaz');
      await tester.pumpAndSettle();
      controller.selectFilter(PersonnelFilter.hospital);
      await tester.pumpAndSettle();
      for (final sort in PersonnelSort.values) {
        controller.selectSort(sort);
        await tester.pumpAndSettle();
        expect(controller.sort, sort);
      }
      await tester.tap(key('personnel-person:8001'));
      controller.clearSearch();
      await tester.pumpAndSettle();
      expect(jsonEncode(game.gameState.toJson()), before);
      expect(
        people.map((person) => jsonEncode(person.toJson())).toList(),
        personBefore,
      );
      expect(List.generate(16, (_) => lcsRandom(100000)), rolls);
    },
  );
}
