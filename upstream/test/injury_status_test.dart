import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/creature/attributes.dart';
import 'package:lcs_new_age/creature/body.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/modern/injury_status.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String fixture;
  late Creature person;
  late HumanoidBody body;

  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
  });

  setUp(() {
    game.gameState = decodeSaveContents(fixture).gameState!;
    person = game.pool.first;
    body = HumanoidBody();
    person.body = body;
  });

  InjuryLocation location(String id) =>
      injuryLocations(person).singleWhere((entry) => entry.id == id);

  test('healthy humans expose six independently addressable body regions', () {
    final entries = injuryLocations(person);
    expect(entries.map((entry) => entry.id), [
      'head',
      'torso',
      'left-arm',
      'right-arm',
      'left-leg',
      'right-leg',
    ]);
    expect(entries.map((entry) => entry.region), InjuryRegion.values);
    expect(entries.every((entry) => !entry.affected), isTrue);
    expect(entries.every((entry) => entry.tissueHealth == 1), isTrue);
    expect(entries.every((entry) => !entry.internal), isTrue);
  });

  void injureEverySpecial() {
    body
      ..puncturedRightLung = true
      ..puncturedLeftLung = true
      ..puncturedHeart = true
      ..puncturedLiver = true
      ..puncturedStomach = true
      ..puncturedRightKidney = true
      ..puncturedLeftKidney = true
      ..puncturedSpleen = true
      ..neck = InjuryState.untreated
      ..upperSpine = InjuryState.untreated
      ..lowerSpine = InjuryState.untreated
      ..missingRightEye = true
      ..missingLeftEye = true
      ..missingNose = true
      ..missingTongue = true
      ..teeth = 12
      ..ribs = 4;
  }

  test(
    'every special injury remains a separate entry beside its body part',
    () {
      injureEverySpecial();
      body.torso.shot = true;
      final entries = injuryLocations(person);
      const specials = {
        'right-lung',
        'left-lung',
        'heart',
        'liver',
        'stomach',
        'right-kidney',
        'left-kidney',
        'spleen',
        'neck',
        'upper-spine',
        'lower-spine',
        'right-eye',
        'left-eye',
        'nose',
        'tongue',
        'teeth',
        'ribs',
      };
      expect(entries, hasLength(6 + specials.length));
      expect(
        entries.map((entry) => entry.id).toSet(),
        hasLength(entries.length),
      );
      for (final id in specials) {
        final injury = location(id);
        expect(injury.affected, isTrue, reason: id);
        expect(injury.findings, isNotEmpty, reason: id);
        expect(injury.effects, isNotEmpty, reason: id);
        expect(injury.care, isNotEmpty, reason: id);
        expect(injury.tissueHealth, isNull, reason: id);
      }
      expect(location('torso').findings, contains('Shot'));
      expect(location('right-lung').internal, isTrue);
      expect(location('right-lung').region, InjuryRegion.torso);
      expect(location('right-eye').internal, isFalse);
      expect(location('right-eye').region, InjuryRegion.head);
    },
  );

  final organs = <(String, int, void Function(HumanoidBody))>[
    ('right-lung', 2, (body) => body.puncturedRightLung = true),
    ('left-lung', 2, (body) => body.puncturedLeftLung = true),
    ('heart', 2, (body) => body.puncturedHeart = true),
    ('liver', 1, (body) => body.puncturedLiver = true),
    ('stomach', 1, (body) => body.puncturedStomach = true),
    ('right-kidney', 1, (body) => body.puncturedRightKidney = true),
    ('left-kidney', 1, (body) => body.puncturedLeftKidney = true),
    ('spleen', 1, (body) => body.puncturedSpleen = true),
  ];
  for (final (id, modifier, injure) in organs) {
    test(
      '$id describes its real injury modifier and conditional daily risk',
      () {
        injure(body);
        expect(body.combatRollModifier, modifier);
        final injury = location(id);
        expect(
          injury.effects.first,
          contains('Adds $modifier to the injury modifier'),
        );
        expect(
          injury.effects.last,
          contains(id == 'heart' ? '9 blood' : '1 blood'),
        );
        expect(injury.effects.last, contains('If daily treatment fails'));
        expect(injury.effects.last, contains('risk of permanent'));
        expect(injury.care, contains('no fixed recovery date'));
        expect(injury.effects.join(' '), isNot(contains('accuracy')));
      },
    );
  }

  for (final (ribs, modifier) in [(9, 1), (4, 2), (0, 3)]) {
    test('$ribs intact ribs describes the engine modifier $modifier', () {
      body.ribs = ribs;
      expect(body.combatRollModifier, modifier);
      expect(location('ribs').effects.first, contains('Adds $modifier'));
      expect(location('ribs').findings.single, contains('$ribs intact'));
    });
  }

  test('rib modifiers preserve the existing fixed-count thresholds', () {
    body
      ..maxRibs = 20
      ..ribs = 15;
    expect(body.combatRollModifier, 0);
    expect(
      location('ribs').effects.first,
      contains('No additional injury modifier'),
    );
    expect(location('ribs').findings.single, '5 broken · 15 intact');
  });

  final spines = <(String, int, void Function(InjuryState))>[
    ('neck', 75, (state) => body.neck = state),
    ('upper-spine', 25, (state) => body.upperSpine = state),
    ('lower-spine', 50, (state) => body.lowerSpine = state),
  ];
  for (final (id, modifier, injure) in spines) {
    test('$id stabilization retains paralysis and the actual modifier', () {
      injure(InjuryState.untreated);
      final untreated = location(id);
      expect(untreated.findings.single, contains('untreated'));
      expect(untreated.effects.join(' '), contains('1 blood lost'));
      expect(untreated.care, contains('does not reverse paralysis'));
      expect(body.canWalk, isFalse);
      expect(body.combatRollModifier, modifier);

      injure(InjuryState.treated);
      final stabilized = location(id);
      expect(stabilized.findings.single, contains('stabilized'));
      expect(stabilized.effects.first, contains('Adds $modifier'));
      expect(stabilized.effects.join(' '), isNot(contains('blood lost')));
      expect(
        stabilized.care,
        contains('Paralysis and the injury modifier remain'),
      );
      expect(body.canWalk, isFalse);
      expect(body.combatRollModifier, modifier);
      expect(body.armok, id == 'lower-spine' ? 2 : 0);
    });
  }

  test('each missing eye has its Charisma cost; blindness requires both', () {
    body.missingLeftEye = true;
    expect(body.canSee, isTrue);
    expect(body.combatRollModifier, 0);
    expect(
      location('left-eye').effects,
      contains('Charisma −2 before the attribute minimum.'),
    );
    expect(
      location('left-eye').effects.last,
      'One eye remains: sight is retained.',
    );

    body.missingRightEye = true;
    expect(body.canSee, isFalse);
    expect(body.combatRollModifier, 5);
    for (final id in ['left-eye', 'right-eye']) {
      expect(location(id).effects.last, contains('Combined eye loss adds 5'));
    }
  });

  test('facial loss and teeth report actual cumulative Charisma effects', () {
    final intact = body.permanentAttributeMods(Attribute.charisma, 20, 30);
    body
      ..missingNose = true
      ..missingTongue = true;
    expect(body.permanentAttributeMods(Attribute.charisma, 20, 30), intact - 6);
    expect(location('nose').effects.first, contains('Charisma −3'));
    expect(location('tongue').effects.first, contains('Charisma −3'));
    for (final (teeth, penalty) in [(31, 1), (15, 2), (0, 3)]) {
      body.teeth = teeth;
      expect(
        body.permanentAttributeMods(Attribute.charisma, 20, 30),
        intact - 6 - penalty,
      );
      expect(location('teeth').effects.single, contains('Charisma −$penalty'));
      expect(location('teeth').findings.single, '$teeth of 32 teeth remain');
      expect(location('teeth').care, contains('do not replace'));
    }
  });

  final wounds = <(String, void Function(BodyPart))>[
    ('Shot', (part) => part.shot = true),
    ('Cut', (part) => part.cut = true),
    ('Bruised', (part) => part.bruised = true),
    ('Burned', (part) => part.burned = true),
    ('Torn', (part) => part.torn = true),
  ];
  for (final (finding, injure) in wounds) {
    test('$finding is visible even without a tissue or blood change', () {
      injure(body.leftArm);
      final injury = location('left-arm');
      expect(injury.affected, isTrue);
      expect(injury.findings, contains(finding));
      expect(injury.tissueHealth, 1);
      expect(
        injury.effects.join(' '),
        contains('no separate combat or movement penalty'),
      );
      expect(body.combatRollModifier, 0);
    });
  }

  test('tissue-only and bleeding-only injuries are not silently dropped', () {
    body.leftLeg.relativeHealth = .97;
    body.rightLeg.bleeding = 2;
    final tissue = location('left-leg');
    final bleeding = location('right-leg');
    expect(tissue.affected, isTrue);
    expect(tissue.tissueHealth, .97);
    expect(tissue.findings, contains('Tissue damage'));
    expect(tissue.effects.join(' '), contains('more easily sever'));
    expect(tissue.care, contains('not a percentage of combat effectiveness'));
    expect(bleeding.affected, isTrue);
    expect(bleeding.tissueHealth, 1);
    expect(bleeding.bleeding, 2);
    expect(bleeding.findings, contains('Bleeding (2)'));
    expect(bleeding.care, contains('First Aid'));
    expect(bleeding.effects.join(' '), contains('not guaranteed'));
    expect(body.canWalk, isTrue);
  });

  test(
    'raw tissue loss is preserved without converting it to effectiveness',
    () {
      body.torso.relativeHealth = -.25;
      final injury = location('torso');
      expect(injury.tissueHealth, -.25);
      expect(injury.affected, isTrue);
      expect(body.combatRollModifier, 0);
      expect(injury.effects.join(' '), isNot(contains('%')));
    },
  );

  test('severed and stabilized losses preserve different treatment states', () {
    body
      ..leftArm.nastyOff = true
      ..rightArm.cleanOff = true;
    final untreated = location('left-arm');
    final stabilized = location('right-arm');
    expect(untreated.severity, InjurySeverity.missing);
    expect(untreated.findings, contains('Severed · unstabilized'));
    expect(
      untreated.effects,
      contains('Failed daily stabilization costs 4 blood.'),
    );
    expect(untreated.care, contains('does not regrow'));
    expect(stabilized.findings, contains('Missing · stabilized'));
    expect(stabilized.care, contains('Permanent loss'));
    expect(stabilized.effects.join(' '), contains('cannot wield weapons'));
  });

  test(
    'one missing leg retains walking; losing both has the actual effect',
    () {
      body.leftLeg.cleanOff = true;
      expect(body.canWalk, isTrue);
      expect(
        location('left-leg').effects,
        contains('One leg remains: walking is still possible.'),
      );
      body.rightLeg.cleanOff = true;
      expect(body.canWalk, isFalse);
      expect(
        location('left-leg').effects.join(' '),
        contains('Agility is quartered'),
      );
      expect(location('right-leg').effects.join(' '), contains('cannot walk'));
    },
  );

  test('paralysis is not hidden by a simultaneous single-limb loss', () {
    body
      ..leftArm.cleanOff = true
      ..leftLeg.cleanOff = true
      ..upperSpine = InjuryState.treated;
    expect(body.armok, 0);
    expect(body.canWalk, isFalse);
    expect(
      location('left-arm').effects.join(' '),
      contains('remaining arm is paralyzed'),
    );
    expect(
      location('left-leg').effects.join(' '),
      contains('remaining leg is paralyzed'),
    );
    expect(
      location('left-leg').effects.join(' '),
      isNot(contains('still possible')),
    );
  });

  test('a missing part can still report an active bleeding stack', () {
    body.leftArm
      ..cleanOff = true
      ..bleeding = 2;
    final injury = location('left-arm');
    expect(
      injury.findings,
      containsAll(['Missing · stabilized', 'Bleeding (2)']),
    );
    expect(injury.effects.join(' '), contains('Uncontrolled bleeding'));
    expect(injury.care, contains('First Aid'));
    expect(injury.care, contains('Permanent loss'));
  });

  test(
    'nonhuman bodies preserve every actual part and use no human map region',
    () {
      for (final candidate in [dogBody(), sixLeggedPigBody(), TankBody()]) {
        person.body = candidate;
        candidate.parts.first.shot = true;
        final entries = injuryLocations(person);
        expect(
          entries.map((entry) => entry.name),
          candidate.parts.map((part) => part.name),
        );
        expect(entries, hasLength(candidate.parts.length));
        expect(entries.every((entry) => entry.region == null), isTrue);
        expect(entries.first.affected, isTrue);
        expect(
          entries.map((entry) => entry.id).toSet(),
          hasLength(entries.length),
        );
      }
      person.body = sixLeggedPigBody();
      expect(
        injuryLocations(person).map((entry) => entry.name),
        containsAll([
          'Left Middle Leg',
          'Right Middle Leg',
          'Left Front Leg',
          'Right Front Leg',
        ]),
      );
      person.body = TankBody();
      expect(
        injuryLocations(person).map((entry) => entry.name),
        containsAll([
          'Turret Front',
          'Turret Rear',
          'Left Track',
          'Right Track',
        ]),
      );
    },
  );

  test(
    'special injuries on nonhuman bodies are kept without human regions',
    () {
      final dog = dogBody() as HumanoidBody;
      dog.puncturedLeftLung = true;
      person.body = dog;
      final injury = location('left-lung');
      expect(injury.region, isNull);
      expect(injury.findings, contains('Collapsed lung'));
      expect(injuryLocations(person), hasLength(dog.parts.length + 1));
    },
  );

  test(
    'descriptions are immutable snapshots and preserve campaign state and RNG',
    () {
      injureEverySpecial();
      body.leftArm
        ..shot = true
        ..bleeding = 2
        ..relativeHealth = .55;
      person.permanentHealthDamage = 3;
      final before = jsonEncode(game.gameState);
      reseedRNG(seed: 20261017);
      final expectedRolls = List.generate(12, (_) => lcsRandom(1000000));
      reseedRNG(seed: 20261017);
      for (var i = 0; i < 30; i++) {
        final entries = injuryLocations(person);
        expect(entries.any((entry) => entry.id == 'permanent-health'), isFalse);
        expect(entries.clear, throwsUnsupportedError);
        expect(() => entries.first.findings.clear(), throwsUnsupportedError);
        expect(
          () => entries.first.effects.add('invented'),
          throwsUnsupportedError,
        );
      }
      expect(jsonEncode(game.gameState), before);
      expect(List.generate(12, (_) => lcsRandom(1000000)), expectedRolls);

      final snapshot = location('left-arm');
      body.leftArm.heal();
      expect(snapshot.findings, contains('Shot'));
      expect(snapshot.bleeding, 2);
      expect(snapshot.tissueHealth, .55);
      expect(location('left-arm').affected, isFalse);
    },
  );
}
