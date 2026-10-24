import 'dart:math';

import 'package:lcs_new_age/creature/body.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/creature_type.dart';
import 'package:lcs_new_age/creature/gender.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/gamestate/game_state.dart';

part 'portrait_expansion.dart';

enum PortraitBackground {
  civilian,
  professional,
  trades,
  academic,
  creative,
  security,
  punk,
  goth,
  emo,
  biker,
  religious,
  mutant,
  child,
  teenager,
  canine,
  tank,
  monster,
  purpleGorilla,
  warpedBear,
  pinkElephant,
  madCow,
  sixLeggedPig,
  flamingRabbit,
  giantMosquito,
  elderly,
}

/// Metadata describes visual presentation, not a character's actual abilities.
class PortraitEntry {
  const PortraitEntry(this.id, this.background, this.gender, this.visualAge);

  final int id;
  final PortraitBackground background;
  final Gender gender;

  /// Approximate painted age. New casting stays in a suitable age cohort.
  final int visualAge;

  /// Ordinary human artwork is a semantic class, independent of saved ID era.
  bool get ordinaryHuman => const {
    PortraitBackground.civilian,
    PortraitBackground.professional,
    PortraitBackground.trades,
    PortraitBackground.academic,
    PortraitBackground.creative,
    PortraitBackground.security,
  }.contains(background);
  String get asset =>
      'assets/modern/portraits_v2/batch_${(id < 250 ? id ~/ 16 : 16 + (id - 250) ~/ 16).toString().padLeft(2, '0')}.webp';
  int get cell => id < 250 ? id % 16 : (id - 250) % 16;
}

// Keep IDs stable when adding artwork: saves reference these positions.
const _batchBackgrounds = [
  PortraitBackground.professional,
  PortraitBackground.professional,
  PortraitBackground.professional,
  PortraitBackground.trades,
  PortraitBackground.trades,
  PortraitBackground.trades,
  PortraitBackground.academic,
  PortraitBackground.academic,
  PortraitBackground.creative,
  PortraitBackground.creative,
  PortraitBackground.creative,
  PortraitBackground.security,
  PortraitBackground.security,
  PortraitBackground.civilian,
  PortraitBackground.civilian,
  PortraitBackground.civilian,
];
final List<PortraitEntry> portraitCatalog = List.unmodifiable([
  for (var id = 0; id < 250; id++)
    PortraitEntry(
      id,
      _batchBackgrounds[id ~/ 16],
      id.isEven ? Gender.female : Gender.male,
      const [25, 38, 53, 68][id % 16 ~/ 4],
    ),
  for (var cell = 0; cell < 128; cell++)
    PortraitEntry(
      250 + cell,
      _specialistBackground(cell),
      cell.isEven ? Gender.female : Gender.male,
      switch (cell ~/ 16) {
        0 => const [22, 30, 24, 45][cell % 16 ~/ 4],
        1 => const [25, 40, 55, 72][cell % 16 ~/ 4],
        2 => const [25, 38, 53, 68][cell % 16 ~/ 4],
        3 => const [4, 7, 10, 12][cell % 16 ~/ 4],
        4 => const [14, 16, 18, 19][cell % 16 ~/ 4],
        7 => const [76, 84, 92, 100][cell % 16 ~/ 4],
        _ => 0,
      },
    ),
  ...expandedPortraitEntries,
]);

PortraitBackground _specialistBackground(int cell) => switch (cell ~/ 16) {
  0 => const [
    PortraitBackground.punk,
    PortraitBackground.goth,
    PortraitBackground.emo,
    PortraitBackground.biker,
  ][cell % 16 ~/ 4],
  1 => PortraitBackground.religious,
  2 => PortraitBackground.mutant,
  3 => PortraitBackground.child,
  4 => PortraitBackground.teenager,
  5 => PortraitBackground.canine,
  6 => const [
    PortraitBackground.tank,
    PortraitBackground.monster,
    PortraitBackground.purpleGorilla,
    PortraitBackground.warpedBear,
    PortraitBackground.pinkElephant,
    PortraitBackground.madCow,
    PortraitBackground.sixLeggedPig,
    PortraitBackground.flamingRabbit,
    PortraitBackground.giantMosquito,
  ][min(cell % 16 ~/ 2, 7) + (cell % 16 == 15 ? 1 : 0)],
  _ => PortraitBackground.elderly,
};

const portraitProfessionBackgrounds = <String, PortraitBackground>{
  CreatureTypeIds.bouncer: PortraitBackground.security,
  CreatureTypeIds.securityGuard: PortraitBackground.security,
  CreatureTypeIds.cop: PortraitBackground.security,
  CreatureTypeIds.policeChief: PortraitBackground.security,
  CreatureTypeIds.swat: PortraitBackground.security,
  CreatureTypeIds.deathSquad: PortraitBackground.security,
  CreatureTypeIds.firefighter: PortraitBackground.security,
  CreatureTypeIds.gangUnit: PortraitBackground.security,
  CreatureTypeIds.agent: PortraitBackground.security,
  CreatureTypeIds.secretService: PortraitBackground.security,
  CreatureTypeIds.ccsArchConservative: PortraitBackground.security,
  CreatureTypeIds.ccsVigilante: PortraitBackground.security,
  CreatureTypeIds.merc: PortraitBackground.security,
  CreatureTypeIds.veteran: PortraitBackground.security,
  CreatureTypeIds.hardenedVeteran: PortraitBackground.security,
  CreatureTypeIds.soldier: PortraitBackground.security,
  CreatureTypeIds.militaryOfficer: PortraitBackground.security,
  CreatureTypeIds.militaryPolice: PortraitBackground.security,
  CreatureTypeIds.seal: PortraitBackground.security,
  CreatureTypeIds.prisonGuard: PortraitBackground.security,
  CreatureTypeIds.labTech: PortraitBackground.academic,
  CreatureTypeIds.eminentScientist: PortraitBackground.academic,
  CreatureTypeIds.educator: PortraitBackground.academic,
  CreatureTypeIds.doctor: PortraitBackground.academic,
  CreatureTypeIds.psychologist: PortraitBackground.academic,
  CreatureTypeIds.nurse: PortraitBackground.academic,
  CreatureTypeIds.dietician: PortraitBackground.academic,
  CreatureTypeIds.physicalTherapist: PortraitBackground.academic,
  CreatureTypeIds.nursingHomeAttendant: PortraitBackground.academic,
  CreatureTypeIds.socialWorker: PortraitBackground.academic,
  CreatureTypeIds.collegeStudent: PortraitBackground.academic,
  CreatureTypeIds.mathematician: PortraitBackground.academic,
  CreatureTypeIds.teacher: PortraitBackground.academic,
  CreatureTypeIds.programmer: PortraitBackground.academic,
  CreatureTypeIds.president: PortraitBackground.professional,
  CreatureTypeIds.corporateManager: PortraitBackground.professional,
  CreatureTypeIds.nursingHomeAdmin: PortraitBackground.professional,
  CreatureTypeIds.corporateCEO: PortraitBackground.professional,
  CreatureTypeIds.insuranceCEO: PortraitBackground.professional,
  CreatureTypeIds.secretary: PortraitBackground.professional,
  CreatureTypeIds.landlord: PortraitBackground.professional,
  CreatureTypeIds.bankTeller: PortraitBackground.professional,
  CreatureTypeIds.bankManager: PortraitBackground.professional,
  CreatureTypeIds.liberalJudge: PortraitBackground.professional,
  CreatureTypeIds.conservativeJudge: PortraitBackground.professional,
  CreatureTypeIds.lawyer: PortraitBackground.professional,
  CreatureTypeIds.telemarketer: PortraitBackground.professional,
  CreatureTypeIds.carSalesman: PortraitBackground.professional,
  CreatureTypeIds.officeWorker: PortraitBackground.professional,
  CreatureTypeIds.auditor: PortraitBackground.professional,
  CreatureTypeIds.actuary: PortraitBackground.professional,
  CreatureTypeIds.cpa: PortraitBackground.professional,
  CreatureTypeIds.claimsAdjuster: PortraitBackground.professional,
  CreatureTypeIds.socialite: PortraitBackground.professional,
  CreatureTypeIds.servant: PortraitBackground.trades,
  CreatureTypeIds.janitor: PortraitBackground.trades,
  CreatureTypeIds.sweatshopWorker: PortraitBackground.trades,
  CreatureTypeIds.nonUnionWorker: PortraitBackground.trades,
  CreatureTypeIds.childLaborer: PortraitBackground.trades,
  CreatureTypeIds.unionWorker: PortraitBackground.trades,
  CreatureTypeIds.sewerWorker: PortraitBackground.trades,
  CreatureTypeIds.engineer: PortraitBackground.trades,
  CreatureTypeIds.fastFoodWorker: PortraitBackground.trades,
  CreatureTypeIds.baker: PortraitBackground.trades,
  CreatureTypeIds.barista: PortraitBackground.trades,
  CreatureTypeIds.bartender: PortraitBackground.trades,
  CreatureTypeIds.mailman: PortraitBackground.trades,
  CreatureTypeIds.garbageman: PortraitBackground.trades,
  CreatureTypeIds.plumber: PortraitBackground.trades,
  CreatureTypeIds.chef: PortraitBackground.trades,
  CreatureTypeIds.constructionWorker: PortraitBackground.trades,
  CreatureTypeIds.clerk: PortraitBackground.trades,
  CreatureTypeIds.trucker: PortraitBackground.trades,
  CreatureTypeIds.taxiDriver: PortraitBackground.trades,
  CreatureTypeIds.locksmith: PortraitBackground.trades,
  CreatureTypeIds.radioPersonality: PortraitBackground.creative,
  CreatureTypeIds.newsAnchor: PortraitBackground.creative,
  CreatureTypeIds.musician: PortraitBackground.creative,
  CreatureTypeIds.amateurMagician: PortraitBackground.creative,
  CreatureTypeIds.hippie: PortraitBackground.creative,
  CreatureTypeIds.artCritic: PortraitBackground.creative,
  CreatureTypeIds.musicCritic: PortraitBackground.creative,
  CreatureTypeIds.painter: PortraitBackground.creative,
  CreatureTypeIds.sculptor: PortraitBackground.creative,
  CreatureTypeIds.author: PortraitBackground.creative,
  CreatureTypeIds.journalist: PortraitBackground.creative,
  CreatureTypeIds.dancer: PortraitBackground.creative,
  CreatureTypeIds.photographer: PortraitBackground.creative,
  CreatureTypeIds.cameraman: PortraitBackground.creative,
  CreatureTypeIds.hairstylist: PortraitBackground.creative,
  CreatureTypeIds.fashionDesigner: PortraitBackground.creative,
  CreatureTypeIds.actor: PortraitBackground.creative,
  CreatureTypeIds.politicalActivist: PortraitBackground.creative,
  CreatureTypeIds.prisoner: PortraitBackground.civilian,
  CreatureTypeIds.juror: PortraitBackground.civilian,
  CreatureTypeIds.highschoolDropout: PortraitBackground.civilian,
  CreatureTypeIds.bum: PortraitBackground.civilian,
  CreatureTypeIds.gangMember: PortraitBackground.civilian,
  CreatureTypeIds.crackhead: PortraitBackground.civilian,
  CreatureTypeIds.footballCoach: PortraitBackground.civilian,
  CreatureTypeIds.sexWorker: PortraitBackground.civilian,
  CreatureTypeIds.angryRuralMob: PortraitBackground.civilian,
  CreatureTypeIds.retiree: PortraitBackground.civilian,
  CreatureTypeIds.thief: PortraitBackground.civilian,
  CreatureTypeIds.yogaInstructor: PortraitBackground.civilian,
  CreatureTypeIds.martialArtist: PortraitBackground.civilian,
  CreatureTypeIds.athlete: PortraitBackground.civilian,
  CreatureTypeIds.cheerleader: PortraitBackground.civilian,
  CreatureTypeIds.neoNazi: PortraitBackground.civilian,
  CreatureTypeIds.punk: PortraitBackground.punk,
  CreatureTypeIds.naziPunk: PortraitBackground.punk,
  CreatureTypeIds.goth: PortraitBackground.goth,
  CreatureTypeIds.emo: PortraitBackground.emo,
  CreatureTypeIds.biker: PortraitBackground.biker,
  CreatureTypeIds.priest: PortraitBackground.religious,
  CreatureTypeIds.nun: PortraitBackground.religious,
  CreatureTypeIds.televangelist: PortraitBackground.religious,
  CreatureTypeIds.mutant: PortraitBackground.mutant,
  CreatureTypeIds.genetic: PortraitBackground.mutant,
  CreatureTypeIds.guardDog: PortraitBackground.canine,
  CreatureTypeIds.tank: PortraitBackground.tank,
  CreatureTypeIds.teenager: PortraitBackground.teenager,
};

PortraitBackground portraitBackgroundFor(Creature person) =>
    portraitProfessionBackgrounds[person.typeId] ?? PortraitBackground.civilian;

int _skillAffinity(Creature person, PortraitBackground background) {
  final skills = switch (background) {
    PortraitBackground.professional => [Skill.business, Skill.law],
    PortraitBackground.academic => [
      Skill.science,
      Skill.firstAid,
      Skill.teaching,
    ],
    PortraitBackground.creative => [Skill.art, Skill.music, Skill.writing],
    _ => <Skill>[],
  };
  return skills.any((skill) => person.skill(skill) >= 4) ? 1 : 0;
}

/// Chooses once, using an isolated RNG and the saved campaign identity.
/// Age suitability precedes profession and avoiding repeated faces.
/// Known crew, contacts and the present encounter get first claim on their faces.
int ensurePortraitId(Creature person) {
  final saved = person.portraitId;
  if (_canKeepSaved(person)) {
    person.portraitVariant ??= _variant(person);
    person.portraitAssignedAge ??= person.age;
    return saved!;
  }

  final known = poolAndProspects.followedBy(encounter);
  final identities = <int, Creature>{};
  final used = <int>{};
  for (final other in known) {
    final otherPortrait = other.portraitId;
    if (_canKeepSaved(other)) {
      identities[other.id] = other;
      used.add(otherPortrait!);
    }
  }
  return _assignPortrait(person, identities, used);
}

bool _validPortrait(int? id) =>
    id != null && id >= 0 && id < portraitCatalog.length;

int _assignPortrait(
  Creature person,
  Map<int, Creature> identities,
  Set<int> used,
) {
  // Reconcile duplicate NPC records without selecting a second identity.
  final existing = identities[person.id];
  if (existing != null) {
    person.portraitVariant = existing.portraitVariant ?? _variant(person);
    person.portraitAssignedAge = existing.portraitAssignedAge ?? person.age;
    return person.portraitId = existing.portraitId!;
  }
  if (_canKeepSaved(person)) {
    person.portraitVariant ??= _variant(person);
    person.portraitAssignedAge ??= person.age;
    identities[person.id] = person;
    return person.portraitId!;
  }
  final entry = _choosePortrait(person, used);
  identities[person.id] = person;
  person.portraitVariant = _variant(person);
  person.portraitAssignedAge = person.age;
  used.add(entry.id);
  return person.portraitId = entry.id;
}

/// A pure lookup for rendering unassigned preview/legacy records. Normal world
/// creation and load migration persist identities before the UI displays them.
int portraitIdForDisplay(Creature person) {
  if (_canKeepSaved(person)) return person.portraitId!;
  return _choosePortrait(person, const {}).id;
}

/// A cosmetic choice for the identity page, before the founder's birthday is
/// chosen. Cycling uses catalog order and an isolated seed, never gameplay RNG.
int chooseFounderPortrait({
  required Gender gender,
  required int age,
  required int seed,
  int? after,
}) {
  final choices = founderPortraitChoices(gender: gender, age: age);
  if (choices.isEmpty) throw StateError('No suitable founder portraits');
  final previous = choices.indexWhere((entry) => entry.id == after);
  return choices[previous < 0
          ? Random(seed).nextInt(choices.length)
          : (previous + 1) % choices.length]
      .id;
}

/// The same compatible catalogue used by both reroll and explicit selection.
List<PortraitEntry> founderPortraitChoices({
  required Gender gender,
  required int age,
}) => portraitCatalog.where((entry) {
  final human = age < 20
      ? entry.background == PortraitBackground.teenager &&
            (entry.visualAge - age).abs() <= 2 &&
            (age >= 18 || entry.visualAge < 18)
      : entry.ordinaryHuman ||
            const {
              PortraitBackground.punk,
              PortraitBackground.goth,
              PortraitBackground.emo,
              PortraitBackground.biker,
            }.contains(entry.background);
  return human &&
      (gender.simplified == Gender.nonbinary ||
          entry.gender == gender.simplified) &&
      (entry.visualAge - age).abs() <= _portraitAgeTolerance(age);
}).toList();

bool _canKeepSaved(Creature person) {
  if (!_validPortrait(person.portraitId)) return false;
  final entry = portraitCatalog[person.portraitId!];
  final nonhuman =
      person.body.type != BodyType.human ||
      person.type.animal ||
      person.type.tank;
  const nonhumanBackgrounds = {
    PortraitBackground.canine,
    PortraitBackground.tank,
    PortraitBackground.monster,
    PortraitBackground.purpleGorilla,
    PortraitBackground.warpedBear,
    PortraitBackground.pinkElephant,
    PortraitBackground.madCow,
    PortraitBackground.sixLeggedPig,
    PortraitBackground.flamingRabbit,
    PortraitBackground.giantMosquito,
  };
  if (nonhuman) return _appropriate(person, entry);
  if (nonhumanBackgrounds.contains(entry.background)) return false;
  // Judge saved faces against the age when they were assigned, so birthdays
  // never reroll an appropriate identity. Repair visibly mismatched faces from
  // the former weighted-only casting, including already-saved assignments.
  final age = person.portraitAssignedAge ?? person.age;
  if (age < 20) return _appropriate(person, entry, atAge: age);
  if (entry.background == PortraitBackground.child ||
      entry.background == PortraitBackground.teenager) {
    return false;
  }
  if ((entry.visualAge - age).abs() <= _portraitAgeTolerance(age)) return true;
  // A few specialist banks have limited age coverage. Keep the nearest
  // available face rather than repeatedly attempting the same repair.
  final current = _ageCandidates(
    person,
    atAge: age,
    matchGender: false,
  ).any((candidate) => candidate.id == entry.id);
  if (current) return true;
  // An expanded specialist bank must not invalidate a previously appropriate
  // nearest-age assignment from the original library.
  return entry.id < 378 &&
      _ageCandidates(
        person,
        atAge: age,
        matchGender: false,
        catalogSize: 378,
      ).any((candidate) => candidate.id == entry.id);
}

int _portraitAgeTolerance(int age) => age < 30 ? 8 : 12;

List<PortraitEntry> _ageCandidates(
  Creature person, {
  int? atAge,
  bool matchGender = true,
  int? catalogSize,
}) {
  final age = atAge ?? person.age;
  final gender = person.gender.simplified;
  final compatible = portraitCatalog
      .take(catalogSize ?? portraitCatalog.length)
      .where((entry) => _appropriate(person, entry, atAge: age))
      .where(
        (entry) =>
            !matchGender ||
            person.body.type != BodyType.human ||
            person.type.animal ||
            person.type.tank ||
            gender == Gender.nonbinary ||
            entry.gender == gender,
      )
      .toList();
  if (person.body.type != BodyType.human ||
      person.type.animal ||
      person.type.tank ||
      age < 20) {
    return compatible;
  }
  final matching = compatible
      .where(
        (entry) => (entry.visualAge - age).abs() <= _portraitAgeTolerance(age),
      )
      .toList();
  final nearest = compatible
      .map((entry) => (entry.visualAge - age).abs())
      .reduce(min);
  final ageSuitable = matching.isNotEmpty
      ? matching
      : compatible
            .where((entry) => (entry.visualAge - age).abs() == nearest)
            .toList();
  final background = portraitBackgroundFor(person);
  if (const {
    PortraitBackground.punk,
    PortraitBackground.goth,
    PortraitBackground.emo,
    PortraitBackground.biker,
    PortraitBackground.religious,
  }.contains(background)) {
    final specialist = ageSuitable
        .where((entry) => entry.background == background)
        .toList();
    if (specialist.isNotEmpty) return specialist;
  }
  return ageSuitable;
}

PortraitEntry _choosePortrait(Creature person, Set<int> used) {
  final compatible = _ageCandidates(person);
  final unused = compatible.where((entry) => !used.contains(entry.id)).toList();
  final candidates = unused.isNotEmpty ? unused : compatible;
  final background = portraitBackgroundFor(person);
  int ageWeight(PortraitEntry entry) {
    final distance = (entry.visualAge - person.age).abs();
    return distance < 12
        ? 6
        : distance < 25
        ? 3
        : 1;
  }

  int weight(PortraitEntry entry) =>
      (entry.background == background
              ? 6
              : entry.background == PortraitBackground.civilian
              ? 2
              : 1) *
          ageWeight(entry) +
      _skillAffinity(person, entry.background);
  final random = Random(
    (gameState.uniqueGameId * 65537 + person.id * 8191) & 0x7fffffff,
  );
  var roll = random.nextInt(
    candidates.fold<int>(0, (sum, entry) => sum + weight(entry)),
  );
  for (final entry in candidates) {
    roll -= weight(entry);
    if (roll < 0) {
      return entry;
    }
  }
  throw StateError('Portrait catalog has no compatible entries');
}

/// Migration runs before a loaded campaign can be inspected or saved again.
void assignKnownPortraits() {
  final known =
      poolAndProspects
          .followedBy(encounter)
          .followedBy(uniqueCreatures.knownCreatures)
          .toList()
        ..sort((left, right) => left.id.compareTo(right.id));
  final identities = <int, Creature>{};
  final used = <int>{};
  // Give every valid saved identity priority before filling legacy omissions.
  for (final person in known) {
    if (_canKeepSaved(person)) {
      identities.putIfAbsent(person.id, () => person);
      used.add(person.portraitId!);
    }
  }
  for (final person in known) {
    _assignPortrait(person, identities, used);
  }
}

// Cosmetic identity uses an isolated stable hash, never the gameplay RNG.
int _variant(Creature person) =>
    ((gameState.uniqueGameId * 104729) ^ (person.id * 1000003)) & 0x7fffffff;

bool _appropriate(Creature person, PortraitEntry entry, {int? atAge}) {
  final age = atAge ?? person.age;
  final bodyBackground = switch (person.body.type) {
    BodyType.human => null,
    BodyType.canine => PortraitBackground.canine,
    BodyType.tank => PortraitBackground.tank,
    BodyType.monster => PortraitBackground.monster,
    BodyType.purpleGorilla => PortraitBackground.purpleGorilla,
    BodyType.warpedBear => PortraitBackground.warpedBear,
    BodyType.pinkElephant => PortraitBackground.pinkElephant,
    BodyType.madCow => PortraitBackground.madCow,
    BodyType.sixLeggedPig => PortraitBackground.sixLeggedPig,
    BodyType.flamingRabbit => PortraitBackground.flamingRabbit,
    BodyType.giantMosquito => PortraitBackground.giantMosquito,
  };
  if (bodyBackground != null) return entry.background == bodyBackground;
  // Some tests/legacy records still have an ordinary body before type repair.
  if (person.typeId == CreatureTypeIds.guardDog) {
    return entry.background == PortraitBackground.canine;
  }
  if (person.typeId == CreatureTypeIds.tank) {
    return entry.background == PortraitBackground.tank;
  }
  if (age < 13) {
    final visualAge = age <= 5
        ? 4
        : age <= 8
        ? 7
        : age <= 10
        ? 10
        : 12;
    return entry.background == PortraitBackground.child &&
        entry.visualAge == visualAge;
  }
  if (age < 20) {
    return entry.background == PortraitBackground.teenager &&
        (entry.visualAge - age).abs() <= 2 &&
        (age >= 18 || entry.visualAge < 18);
  }
  final profession = portraitBackgroundFor(person);
  if (profession == PortraitBackground.mutant) {
    return entry.background == PortraitBackground.mutant;
  }
  if (const {
        PortraitBackground.punk,
        PortraitBackground.goth,
        PortraitBackground.emo,
        PortraitBackground.biker,
        PortraitBackground.religious,
      }.contains(profession) &&
      entry.background == profession) {
    return true;
  }
  if (age >= 75) return entry.background == PortraitBackground.elderly;
  return entry.ordinaryHuman;
}
