import 'dart:math';

import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/gender.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/gamestate/game_state.dart';

enum PortraitBackground {
  civilian,
  professional,
  trades,
  academic,
  creative,
  security,
}

/// Metadata describes visual presentation, not a character's actual abilities.
class PortraitEntry {
  const PortraitEntry(this.id, this.background, this.gender, this.visualAge);

  final int id;
  final PortraitBackground background;
  final Gender gender;

  /// Approximate visual age, used as a soft casting preference.
  final int visualAge;
  String get asset =>
      'assets/modern/portraits_v2/batch_${(id ~/ 16).toString().padLeft(2, '0')}.png';
  int get cell => id % 16;
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
]);

PortraitBackground portraitBackgroundFor(Creature person) {
  final type = person.typeId.toUpperCase();
  bool containsAny(List<String> terms) => terms.any(type.contains);
  if (containsAny([
    'COP',
    'POLICE',
    'SWAT',
    'SECURITYGUARD',
    'BOUNCER',
    'SOLDIER',
    'MILITARY',
    'SEAL',
    'AGENT',
    'SECRET_SERVICE',
    'MERC',
    'VETERAN',
    'DEATHSQUAD',
    'FIREFIGHTER',
  ])) {
    return PortraitBackground.security;
  }
  if (containsAny([
    'SCIENTIST',
    'DOCTOR',
    'NURSE',
    'NURSING',
    'PSYCHOLOGIST',
    'THERAPIST',
    'DIETICIAN',
    'TEACHER',
    'EDUCATOR',
    'MATHEMATICIAN',
  ])) {
    return PortraitBackground.academic;
  }
  if (containsAny([
    'WORKER_FACTORY',
    'WORKER_SWEATSHOP',
    'JANITOR',
    'PLUMBER',
    'ENGINEER',
    'CONSTRUCTION',
    'SEWER',
    'GARBAGE',
    'MAILMAN',
    'CHEF',
    'BAKER',
  ])) {
    return PortraitBackground.trades;
  }
  if (containsAny([
    'CORPORATE',
    'CEO',
    'LAWYER',
    'JUDGE',
    'PRESIDENT',
    'BANK_',
    'SECRETARY',
    'OFFICE',
    'AUDITOR',
    'ACTUARY',
    'CPA',
    'CLAIMS',
    'LANDLORD',
    'SALESMAN',
    'TELEMARKETER',
  ])) {
    return PortraitBackground.professional;
  }
  if (containsAny([
    'MUSIC',
    'PAINTER',
    'SCULPTOR',
    'AUTHOR',
    'JOURNALIST',
    'DANCER',
    'PHOTOGRAPHER',
    'CAMERAMAN',
    'CRITIC',
    'MAGICIAN',
    'HIPPIE',
  ])) {
    return PortraitBackground.creative;
  }
  return PortraitBackground.civilian;
}

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
/// Profession and age bias casting; they do not predetermine a person's face.
/// Known crew, contacts and the present encounter get first claim on their faces.
int ensurePortraitId(Creature person) {
  final saved = person.portraitId;
  if (saved != null && saved >= 0 && saved < portraitCatalog.length) {
    return saved;
  }
  if (!person.human || person.age < 18) return -1;

  final known = poolAndProspects.followedBy(encounter);
  final identities = <int, int>{};
  final used = <int>{};
  for (final other in known) {
    final otherPortrait = other.portraitId;
    if (_validPortrait(otherPortrait)) {
      identities[other.id] = otherPortrait!;
      used.add(otherPortrait);
    }
  }
  return _assignPortrait(person, identities, used);
}

bool _validPortrait(int? id) =>
    id != null && id >= 0 && id < portraitCatalog.length;

int _assignPortrait(Creature person, Map<int, int> identities, Set<int> used) {
  // Reconcile duplicate NPC records without selecting a second identity.
  final existing = identities[person.id];
  if (existing != null) return person.portraitId = existing;
  final gender = person.gender.simplified;
  final compatible = portraitCatalog
      .where((entry) => gender == Gender.nonbinary || entry.gender == gender)
      .toList();
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
      identities[person.id] = entry.id;
      used.add(entry.id);
      return person.portraitId = entry.id;
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
  final identities = <int, int>{};
  final used = <int>{};
  // Give every valid saved identity priority before filling legacy omissions.
  for (final person in known) {
    if (_validPortrait(person.portraitId)) {
      identities.putIfAbsent(person.id, () => person.portraitId!);
      used.add(person.portraitId!);
    }
  }
  for (final person in known) {
    if (person.human && person.age >= 18) {
      _assignPortrait(person, identities, used);
    }
  }
}
