import 'dart:math' as math;

import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/creature/attributes.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/level.dart';
import 'package:lcs_new_age/politics/alignment.dart';

/// Only fixed caps verified in their activity handlers. Conditional rewards
/// such as graffiti murals deliberately do not claim one universal cap here.
int? knownActivityJuiceCap(ActivityType type) => switch (type) {
  ActivityType.communityService => 10,
  ActivityType.trouble => 50,
  ActivityType.hacking => 200,
  ActivityType.stealCars => 100,
  _ => null,
};

/// A read-only view of the engine's Juice ranks, including recovery milestones.
/// Negative thresholds use the first point of the next rank, not the old
/// classic display's single "0" target for every negative value.
class JuiceStatus {
  const JuiceStatus(this.person);
  final Creature person;

  int get juice => person.juice;
  int get level => person.level;
  String get title => person.title;
  int? get nextJuice => nextJuiceThreshold(juice);
  String? get nextTitle =>
      nextJuice == null ? null : levelTitle(level + 1, person.align);
  int? get remaining =>
      nextJuice == null ? null : math.max(0, nextJuice! - juice);
  int get _rankFloor => switch (level) {
    <= -2 => -50,
    -1 => -49,
    0 => -9,
    1 => 0,
    2 => 10,
    3 => 50,
    4 => 100,
    5 => 200,
    6 => 500,
    _ => 1000,
  };
  double get progress => nextJuice == null
      ? 1
      : ((juice - _rankFloor) / (nextJuice! - _rankFloor))
            .clamp(0, 1)
            .toDouble();

  /// Percentage before normal attribute rounding. Crisis instead sets affected
  /// attributes to 1, so expressing that rank as a percentage would be false.
  int? get bonusPercent => switch (level) {
    <= -2 => null,
    -1 => -40,
    0 => -20,
    _ => (level - 1) * 10,
  };
  bool affectsAttribute(Attribute attribute) =>
      !(person.align == Alignment.liberal && attribute == Attribute.wisdom) &&
      !(person.align == Alignment.conservative && attribute == Attribute.heart);

  String get bonusSummary {
    final affected = person.align == Alignment.moderate
        ? 'Attributes'
        : 'Most attributes';
    if (bonusPercent == null) return '$affected reduced to 1';
    if (bonusPercent == 0) return 'Base attributes';
    return '$affected ${bonusPercent! > 0 ? '+' : '−'}${bonusPercent!.abs()}%';
  }

  String get milestone => nextJuice == null
      ? 'Highest Juice rank reached'
      : '$remaining to $nextTitle ($nextJuice)';

  int get recruitCap => person.maxSubordinates;
  int? get nextRecruitCap =>
      nextJuice == null ? null : _recruitCapAt(level + 1);
  int get recruitsUsed => person.maxSubordinates - person.subordinatesLeft;
  int get freeRecruitSlots => math.max(0, person.subordinatesLeft);

  int _recruitCapAt(int rank) {
    if (person.brainwashed) return 0;
    final base = rank >= 6
        ? 6
        : rank >= 5
        ? 5
        : rank >= 4
        ? 3
        : rank >= 3
        ? 1
        : 0;
    return base +
        (person.hireId == null && person.align == Alignment.liberal ? 6 : 0);
  }
}
