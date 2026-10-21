import 'dart:math' as math;

import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/gamestate/game_state.dart';
import 'package:lcs_new_age/justice/crimes.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/politics/laws.dart';

/// Read-only bounds of penalize() in justice/trial.dart. Never roll a sentence
/// while inspecting a person. Ranges are inclusive and counts cap at ten.
String possiblePenalties(Creature person) {
  final charges = person.wantedForCrimes.entries.where((e) => e.value > 0);
  if (charges.isEmpty) return 'No current wanted charges.';
  var totalMin = 0, totalMax = 0;
  var canBeLife = false;
  final lines = <String>['Base prison time if convicted (current laws):'];
  for (final charge in charges) {
    final count = math.min(10, charge.value);
    final (low, high) = _months(charge.key);
    totalMin += low * count;
    totalMax += high * count;
    final life =
        charge.key == Crime.murder ||
        (charge.key == Crime.flagBurning &&
            laws[Law.flagBurning] == DeepAlignment.archConservative);
    canBeLife |= life;
    final penalty = charge.key == Crime.murder && count >= 3
        ? '$count life terms'
        : '${_time(low * count, high * count)}${life ? ' or $count life ${count == 1 ? 'term' : 'terms'}' : ''}';
    lines.add(
      '${charge.key.wantedFor} ×${charge.value}: $penalty'
      '${charge.value > 10 ? ' (10 counts used)' : ''}',
    );
  }
  if (!canBeLife) {
    lines.add('Combined base time: ${_time(totalMin, totalMax)}.');
  }
  lines.add(
    'Before leniency, sentence rounding and any existing sentence. '
    'These are possible penalties, not a predicted verdict.',
  );
  if (laws[Law.deathPenalty] == DeepAlignment.archConservative ||
      (laws[Law.deathPenalty] != DeepAlignment.eliteLiberal &&
          charges.any(
            (e) =>
                e.key == Crime.murder ||
                e.key == Crime.treason ||
                (e.key == Crime.flagBurning &&
                    laws[Law.flagBurning] == DeepAlignment.archConservative),
          ))) {
    lines.add(
      'Current death-penalty law also allows execution without leniency.',
    );
  }
  return lines.join('\n\n');
}

String _time(int low, int high) => high == 0
    ? 'no added prison time'
    : '${low == high ? '$low' : '$low–$high'} ${high == 1 ? 'month' : 'months'}';

// Offences without a time() call add no prison time themselves; they still
// contribute to the prosecution. In particular, treason currently uses zero
// months in lifeOrTime(true, 0, 1, ...), so do not invent a life sentence for it.
(int, int) _months(Crime crime) => switch (crime) {
  Crime.kidnapping => (36, 53),
  Crime.theft => (1, 4),
  Crime.grandTheftAuto => (6, 12),
  Crime.dataTheft || Crime.embezzlement => (1, 13),
  Crime.creditCardFraud => (6, 30),
  Crime.unlawfulBurial => (3, 14),
  Crime.prostitution => (1, 6),
  Crime.disturbingThePeace ||
  Crime.publicNudity ||
  Crime.harboring ||
  Crime.breakingAndEntering ||
  Crime.resistingArrest ||
  Crime.vandalism => (1, 1),
  Crime.racketeering => (12, 111),
  Crime.drugDistribution => switch (laws[Law.drugs]) {
    DeepAlignment.archConservative => (3, 362),
    DeepAlignment.conservative => (3, 122),
    DeepAlignment.moderate => (3, 14),
    _ => (0, 0),
  },
  Crime.terrorism => (60, 240),
  Crime.bankRobbery || Crime.juryTampering || Crime.aidingEscape => (30, 90),
  Crime.escapingPrison => (3, 18),
  Crime.extortion => (6, 6),
  Crime.unlawfulSpeech => (4, 6),
  Crime.arson => (12, 23),
  Crime.assault => (3, 3),
  Crime.flagBurning => switch (laws[Law.flagBurning]) {
    DeepAlignment.archConservative => (120, 360),
    DeepAlignment.conservative => (36, 36),
    DeepAlignment.moderate => (1, 1),
    _ => (0, 0),
  },
  Crime.murder => (120, 360),
  Crime.treason ||
  Crime.illegalEntry ||
  Crime.cyberTerrorism ||
  Crime.cyberVandalism ||
  Crime.loitering => (0, 0),
};
