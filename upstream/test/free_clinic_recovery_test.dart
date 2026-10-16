import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activate_regulars.dart';
import 'package:lcs_new_age/basemode/activate_sleepers.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/basemode/review_mode.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/daily/advance_day.dart';
import 'package:lcs_new_age/daily/shopsnstuff.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/engine/recovery_context.dart';
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/gamestate/ledger.dart';
import 'package:lcs_new_age/gamestate/squad.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/modern/decision_help.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/politics/laws.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/saveload/storage/game_storage.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'campaign_acceptance_test.dart' show playChoices;
import 'test_support.dart';

/// The original day handler autosaves. Keep these prepared medical scenarios in
/// memory, independent of browser or native player storage.
class _MedicalTestStorage implements GameStorage {
  final Map<String, String> _saves = {};

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

Site _facility(Creature patient, SiteType type) => game.sites.firstWhere(
  (site) => site.type == type && site.city == patient.base!.city,
);

Future<void> _admit(Creature patient, Site site) async {
  final frames = await playChoices(() => hospitalize(site, patient), (_, _, _) {
    expect(engine.console.eventTitle, 'Hospital admission');
    return 'Enter';
  });
  expect(frames, hasLength(1));
  expect(patient.location, same(site));
  expect(patient.squad, isNull);
  expect(patient.activity.type, ActivityType.none);
}

Future<List<String>> _day() => playChoices(
  () async => expect(await advanceDay(), isTrue),
  (_, _, _) => recoveryContext(engine.console)?.scene == RecoveryScene.discharge
      ? 'b'
      : 'Enter',
  promptLimit: 150,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final storage = _MedicalTestStorage();
  late String fixture;
  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
    SharedPreferences.setMockInitialValues({});
    await initStorage(storage: storage);
  });
  tearDownAll(storage.close);
  setUp(() {
    game.gameState = decodeSaveContents(fixture).gameState!;
    game.mode = GameMode.base;
    engine.console = Console();
    game.politics.laws[Law.healthcare] = DeepAlignment.archConservative;
    reseedRNG(seed: 20261016);
  });

  test(
    'clinic sleeper staff retain their workplace and orders across a day',
    () async {
      final staff = game.squad.last;
      final clinic = _facility(staff, SiteType.clinic);
      staff.squad = null;
      staff.sleeperAgent = true;
      staff.workLocation = clinic;
      staff.location = clinic;
      staff.base = clinic;
      staff.blood = staff.maxBlood;
      staff.activity = Activity(ActivityType.sleeperLiberal);
      staff.infiltration = 0.42;
      final before = jsonEncode(game.gameState.toJson());
      expect(staff.hospitalized, isFalse);
      expect(jsonEncode(game.gameState.toJson()), before);

      Future<void> expectAvailable() async {
        final frames = await playChoices(activateSleepers, (_, actions, _) {
          expect(
            actions.where(
              (action) =>
                  action.entityType == 'person' &&
                  action.entityId == staff.id.toString() &&
                  action.enabled,
            ),
            hasLength(1),
          );
          return 'Enter';
        });
        expect(frames, hasLength(1));
      }

      await expectAvailable();
      final frames = await _day();
      expect(frames.join('\n'), isNot(contains('discharged')));
      expect(staff.location, same(clinic));
      expect(staff.base, same(clinic));
      expect(staff.workSite, same(clinic));
      expect(staff.activity.type, ActivityType.sleeperLiberal);
      expect(staff.infiltration, 0.42);
      expect(staff.sleeperAgent, isTrue);
      expect(staff.daysHospitalized, 0);
      expect(staff.hospitalized, isFalse);
      await expectAvailable();
    },
  );

  test('a sleeper admitted to another clinic remains a patient', () async {
    final patient = game.squad.last;
    final workplace = _facility(patient, SiteType.clinic);
    final treatmentClinic = game.sites.firstWhere(
      (site) => site.type == SiteType.clinic && site != workplace,
    );
    patient.squad = null;
    patient.sleeperAgent = true;
    patient.workLocation = workplace;
    patient.location = workplace;
    patient.base = workplace;
    patient.blood = patient.maxBlood - 24;
    await _admit(patient, treatmentClinic);
    expect(patient.hospitalized, isTrue);
    await _day();
    expect(patient.location, same(treatmentClinic));
    expect(patient.daysHospitalized, 1);
    expect(patient.hospitalized, isTrue);
    expect(patient.sleeperAgent, isTrue);
    expect(patient.workSite, same(workplace));
    final frames = await playChoices(activateSleepers, (_, _, _) {
      fail('An admitted clinic patient must not receive sleeper orders.');
    });
    expect(frames, isEmpty);
  });

  test(
    'clinic patients stay admitted across daily relocation and skip work',
    () async {
      final patient = game.squad.last;
      final clinic = _facility(patient, SiteType.clinic);
      final initialBlood = patient.maxBlood - 24;
      patient.blood = initialBlood;
      await _admit(patient, clinic);

      expect(clinic.controller, isNot(SiteController.lcs));
      expect(patient.hospitalized, isTrue);
      expect(patient.away, isTrue);
      expect(patient.isActiveLiberal, isFalse);

      // A stale personal assignment must not run while the patient is admitted.
      patient.rawSkill[Skill.science] = 0;
      patient.rawSkillXP[Skill.science] = 0;
      patient.activity = Activity(ActivityType.study, skill: Skill.science);
      final start = game.date;
      final funds = game.ledger.funds;
      for (var day = 1; day <= 3; day++) {
        await _day();
        expect(patient.location, same(clinic));
        expect(patient.hospitalized, isTrue);
        expect(patient.isActiveLiberal, isFalse);
        expect(patient.squad, isNull);
        expect(patient.daysHospitalized, day);
        // Existing clinic support heals 3; ordinary end-of-day aging restores 1.
        expect(patient.blood, initialBlood + 4 * day);
        expect(patient.medicalBills, 0);
        expect(patient.skill(Skill.science), 0);
        expect(patient.skillXP(Skill.science), 0);
        expect(game.date, start.add(Duration(days: day)));
      }
      expect(game.ledger.funds, funds);
      expect(game.ledger.expense[Expense.hospitalBills] ?? 0, 0);
    },
  );

  test(
    'clinic patients are absent from original task and squad allocation readers',
    () async {
      final patient = game.squad.last;
      patient.blood = patient.maxBlood - 24;
      await _admit(patient, _facility(patient, SiteType.clinic));
      for (final reader in [
        activateRegulars,
        () => assembleSquad(Squad.temporary()),
      ]) {
        final frames = await playChoices(reader, (_, actions, _) {
          expect(
            actions.where(
              (action) =>
                  action.entityType == 'person' &&
                  action.entityId == patient.id.toString(),
            ),
            isEmpty,
          );
          return 'Enter';
        });
        expect(frames, hasLength(1));
      }
      expect(patient.squad, isNull);
    },
  );

  test('clinic discharges when aging restored the final blood point', () async {
    final patient = game.squad.last;
    final clinic = _facility(patient, SiteType.clinic);
    final base = patient.base;
    patient.blood = patient.maxBlood - 4;
    await _admit(patient, clinic);
    await _day();
    expect(patient.blood, patient.maxBlood);
    expect(patient.location, same(clinic));
    expect(patient.daysHospitalized, 1);
    final frames = await _day();
    expect(
      frames.join('\n'),
      contains('has been discharged from ${clinic.name}'),
    );
    expect(patient.location, same(base));
    expect(patient.daysHospitalized, 0);
    expect(patient.hospitalized, isFalse);
    expect(patient.isActiveLiberal, isTrue);
    expect(patient.squad, isNull);
    expect(patient.activity.type, ActivityType.none);
    expect(patient.medicalBills, 0);
  });

  for (final existingDebt in [0, 135]) {
    test(
      'clinic applies the existing 60-day limit with debt $existingDebt',
      () async {
        final patient = game.squad.last;
        final base = patient.base;
        patient.blood = patient.maxBlood - 30;
        await _admit(patient, _facility(patient, SiteType.clinic));
        // Prepared late-stay scenario; this test advances the 60th care day.
        patient.daysHospitalized = 59;
        patient.medicalBills = existingDebt;
        final frames = await _day();
        expect(frames.join('\n'), contains('discharged'));
        expect(clinictime(patient), greaterThan(0));
        expect(patient.location, same(base));
        expect(patient.daysHospitalized, 0);
        expect(patient.hospitalized, isFalse);
        expect(patient.squad, isNull);
        expect(patient.activity.type, ActivityType.none);
        // Free treatment neither creates charges nor forgives previous debt.
        expect(patient.medicalBills, existingDebt);
        expect(game.ledger.expense[Expense.hospitalBills] ?? 0, 0);
      },
    );
  }

  test(
    'university hospital retains stronger support and the original law charge',
    () async {
      final patient = game.squad.last;
      final hospital = _facility(patient, SiteType.universityHospital);
      final initialBlood = patient.maxBlood - 24;
      patient.blood = initialBlood;
      await _admit(patient, hospital);
      await _day();
      expect(patient.location, same(hospital));
      expect(patient.daysHospitalized, 1);
      // Existing support 16 heals 6, then aging restores the usual extra point.
      expect(patient.blood, initialBlood + 7);
      expect(patient.medicalBills, 360);
      expect(patient.hospitalized, isTrue);
      expect(patient.isActiveLiberal, isFalse);
    },
  );

  test('personal hospital order retains the university destination', () async {
    final patient = game.squad.last;
    final hospital = _facility(patient, SiteType.universityHospital);
    patient.squad = null;
    patient.blood = patient.maxBlood - 24;
    patient.activity = Activity(ActivityType.clinic);
    final frames = await _day();
    expect(frames.join('\n'), contains('is admitted to ${hospital.name}'));
    expect(patient.location, same(hospital));
    expect(patient.daysHospitalized, 1);
    expect(patient.activity.type, ActivityType.none);
    expect(patient.medicalBills, 360);
  });

  test(
    'health mechanics explain care support, charges and discharge without advancing',
    () {
      final before = jsonEncode(game.gameState.toJson());
      final text = decisionDetails(
        DecisionTopic.health,
        actor: game.squad.last,
      ).join('\n');
      expect(text, contains('Free Clinic'));
      expect(text, contains('First Aid 6'));
      expect(text, contains('without new treatment charges'));
      expect(text, contains('University hospitals provide medical support 16'));
      expect(text, contains('60 days'));
      expect(text, contains('University hospital billing factor'));
      expect(jsonEncode(game.gameState.toJson()), before);
    },
  );
}
