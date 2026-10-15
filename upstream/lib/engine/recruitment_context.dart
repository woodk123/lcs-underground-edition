import 'package:lcs_new_age/creature/creature.dart';

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
