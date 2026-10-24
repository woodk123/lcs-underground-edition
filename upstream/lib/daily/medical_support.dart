import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/site.dart';

/// Daily care is automatic. Tasks do not gate support, and skills do not stack.
/// Shared with the read-only medical record so its explanation uses engine rules.
int medicalSupportAt(Site site, Iterable<Creature> people) {
  var support = site.controller == SiteController.lcs ? 0 : 6;
  if (site.type == SiteType.universityHospital) support = 16;
  if (site.foodDaysLeft < 1 && site.siege.underSiege) return support;
  for (final person in people) {
    if (!person.alive || person.inHiding || person.sleeperAgent) continue;
    if (person.site != site) continue;
    final skill = person.skill(Skill.firstAid);
    if (skill > support) support = skill;
  }
  return support;
}
