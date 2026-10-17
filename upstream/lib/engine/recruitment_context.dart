import 'package:flutter/foundation.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/creature_type.dart';
import 'package:lcs_new_age/creature/skills.dart';

/// Metadata for the currently awaited profession choice, never generated NPCs.
class RecruitmentTargetContext {
  RecruitmentTargetContext(
    this.recruiter,
    this.targets,
    this.page,
    this.pageCount,
  ) : preview = ValueNotifier(targets[page * 20].$1);
  final Creature recruiter;
  final List<(CreatureType, int)> targets;
  final int page, pageCount;
  final ValueNotifier<CreatureType> preview;

  int meetings(CreatureType type) {
    final difficulty = targets.firstWhere((t) => t.$1 == type).$2;
    if (difficulty <= 0 || difficulty >= 10) return 0;
    return (recruiter.skillRoll(Skill.streetSmarts, take10: true) / difficulty)
        .round()
        .clamp(0, 10);
  }
}

/// Only people introduced by the current recruitment reader. Presentation
/// metadata does not generate characters, run checks or change recruitment.
class RecruitmentProspect {
  const RecruitmentProspect(this.person, {this.choiceKey});
  final Creature person;
  final String? choiceKey;
}

class RecruitmentContext {
  RecruitmentContext({
    required this.recruiter,
    required List<RecruitmentProspect> prospects,
    this.followUp = false,
  }) : prospects = List.unmodifiable(prospects);

  final Creature recruiter;
  final List<RecruitmentProspect> prospects;
  final bool followUp;
}
