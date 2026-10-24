import 'dart:math' as math;

import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/daily/medical_support.dart';
import 'package:lcs_new_age/daily/shopsnstuff.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;

/// Current conditions only: no simulation, mutation, treatment rolls or RNG.
List<String> dailyRecoveryHelp(Creature person) {
  if (!person.alive) return const [];
  final site = person.site;
  final support = site == null ? 0 : medicalSupportAt(site, game.pool);
  final severity = clinictime(person);
  final ceiling = math.min(
    person.maxBlood,
    (person.maxBlood * (1 - (severity - 1) * .2)).round(),
  );
  final care = site == null || severity == 0
      ? 0
      : math.max(0, math.min(1 + support ~/ 3, ceiling - person.blood));
  final natural = person.blood + care < person.maxBlood ? 1 : 0;
  return [
    'With current conditions: up to +${care + natural} blood/day before injury losses. '
        'Recalculated as injuries, location and people present change.',
    'Natural recovery adds +1 blood at the end of each day, up to full blood. '
        '${site == null ? 'No site: no daily medical care here.' : 'Medical support at ${site.getName()}: First Aid $support. Care adds up to +${1 + support ~/ 3} blood/day (1 + First Aid / 3, rounded down).'}',
    'Care is automatic: no medic assignment or Lay Low order is required. '
        'The highest First Aid among eligible people at the same site is used, '
        'including the patient; helpers do not stack. Dead, hiding and sleeper '
        'characters cannot provide support. A besieged site without food gets no crew support.',
    'Daily care also trains First Aid at LCS-controlled sites with injury work: '
        '1 to 50 XP per person per day, based on total blood deficit and major injuries, '
        'subject to normal skill and XP caps. Everyone at that site receives this training, '
        'not just the strongest medic. No assignment is required. Non-LCS clinics and '
        'hospitals do not grant this daily-care XP.',
    'LCS bases start with support 0; other sites start at 6; university hospitals start at 16. '
        'A higher First Aid skill can improve that support.',
    if (severity > 0)
      'Current medical recovery ceiling: ${math.max(0, ceiling)}/${person.maxBlood} blood '
          '(treatment severity $severity). Each severity point above 1 lowers the ceiling '
          'by 20% of maximum blood. Natural recovery still applies above this ceiling.',
    'Bleeding and untreated major injuries can cause blood loss after medical recovery, '
        'so the net gain can be smaller or negative. Stabilization uses daily medical checks; '
        'a recovery rate is not a guaranteed discharge date. Lay Low does not add a healing bonus.',
  ];
}
