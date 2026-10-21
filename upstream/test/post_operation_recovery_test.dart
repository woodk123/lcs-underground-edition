import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/creature/body.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/daily/advance_day.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/saveload/storage/game_storage.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'campaign_acceptance_test.dart' show playChoices;
import 'test_support.dart';

class _RecoveryStorage implements GameStorage {
  final _saves = <String, String>{};
  @override
  Future<void> init() async {}
  @override
  Future<void> saveGame(SaveFile file) async {
    _saves[file.gameId] = jsonEncode(file.toJson());
  }

  @override
  Future<SaveFile?> loadGame(String id) async => _saves.containsKey(id)
      ? SaveFile.fromJson(jsonDecode(_saves[id]!) as Map<String, dynamic>)
      : null;
  @override
  Future<List<String>> listGameIds() async => _saves.keys.toList();
  @override
  Future<void> deleteGame(String id) async => _saves.remove(id);
  @override
  Future<void> updateLastGameId(String id) async {}
  @override
  Future<void> close() async => _saves.clear();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final storage = _RecoveryStorage();
  late String fixture;
  late Creature patient;
  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
    SharedPreferences.setMockInitialValues({});
    await initStorage(storage: storage);
  });
  tearDownAll(storage.close);
  setUp(() async {
    engine.console = Console();
    game.gameState = decodeSaveContents(fixture).gameState!;
    game.mode = GameMode.base;
    game.activeSite = game.squad.first.site;
    for (final person in game.pool) {
      person.activity = Activity.none();
      person.rawSkill[Skill.firstAid] = 0;
    }
    for (final squad in game.squads) {
      squad.activity = Activity.none();
    }
    patient = game.squad.last;
    // Declared severe wound at a safehouse without a capable medic. The real
    // daily recovery handler determines treatment need, damage and assignment.
    patient.blood = 40;
    (patient.body as HumanoidBody).puncturedLeftLung = true;
    reseedRNG(seed: 20261016);
    journalReadingScale.value = 1;
    // A departing operation's last reader retains its field body boundary.
    engine.console.screen = 'field_prompt';
    engine.console.journalBodyStart = 9;
    engine.mvaddstr(9, 1, 'Old field narration');
    engine.mvaddstr(12, 55, 'OLDMAP');
    engine.addOptionText(10, 1, 'v', 'V-Flee');
    final priorReader = engine.getKey();
    engine.console.sendInput('Up');
    await priorReader;
    expect(engine.console.screen, 'field_prompt');
    expect(engine.console.journalBodyStart, 9);
  });

  test(
    'daily professional treatment notice starts its own current reader',
    () async {
      final initialDate = game.date;
      final location = patient.location;
      final portrait = patient.portraitId;
      final weapon = patient.equippedWeapon;
      var notices = 0;
      await playChoices(
        () async {
          expect(await advanceDay(), isTrue);
        },
        (_, actions, _) {
          if (engine.console.eventMessage?.contains(
                'require professional treatment',
              ) ??
              false) {
            notices++;
            expect(engine.console.eventTitle, 'Daily report');
            expect(
              engine.console.eventMessage,
              "${patient.name}'s injuries require professional treatment.",
            );
            expect(engine.console.screen, 'generic');
            expect(engine.console.journalBodyStart, 0);
            expect(engine.console.journalPeople, isEmpty);
            expect(actions, isEmpty);
            expect(patient.activity.type, ActivityType.clinic);
            expect(patient.location, same(location));
          }
          return 'Enter';
        },
      );
      expect(notices, 1);
      expect(patient.activity.type, ActivityType.clinic);
      expect(patient.location, same(location));
      expect(patient.portraitId, portrait);
      expect(patient.equippedWeapon, same(weapon));
      expect(game.date, initialDate.add(const Duration(days: 1)));
      expect(patient.alive, isTrue);
      expect(patient.medicalBills, 0);
    },
  );

  testWidgets(
    'post-operation treatment notice has a working journal Continue',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1024, 720);
      journalReadingScale.value = 1.5;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var finished = false;
      bool? dayResult;
      final day = advanceDay().then((result) {
        dayResult = result;
        finished = true;
      });
      await tester.pumpWidget(const MainApp());
      await tester.pumpAndSettle();
      expect(
        engine.console.eventMessage,
        "${patient.name}'s injuries require professional treatment.",
      );
      expect(find.text(engine.console.eventMessage!), findsOneWidget);
      expect(find.text('Old field narration'), findsNothing);
      expect(find.text('OLDMAP'), findsNothing);
      expect(find.text('V-Flee'), findsNothing);
      expect(find.text('Continue').hitTestable(), findsOneWidget);
      expect(finished, isFalse);
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await day;
      expect(finished, isTrue);
      expect(dayResult, isTrue);
      expect(patient.activity.type, ActivityType.clinic);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
