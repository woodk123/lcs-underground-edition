import 'dart:math' as math;

import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/creature/attributes.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/creature_type.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/daily/activities/fundraising.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/items/loot.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/politics/laws.dart';
import 'package:lcs_new_age/politics/views.dart';

/// A read-only calculation explanation, never a simulated activity outcome.
/// [estimated] identifies fixed-roll baselines rather than guaranteed returns.
/// [quantities] names numerical inputs/results for verification and presentation.
class ActivityCalculation {
  ActivityCalculation({
    required this.formula,
    required this.result,
    required this.source,
    List<String> inputs = const [],
    List<String> qualifiers = const [],
    Map<String, num> quantities = const {},
    this.estimated = false,
  }) : inputs = List.unmodifiable(inputs),
       qualifiers = List.unmodifiable(qualifiers),
       quantities = Map.unmodifiable(quantities);

  final String formula;
  final List<String> inputs;
  final String result;
  final List<String> qualifiers;
  final String source;
  final bool estimated;
  final Map<String, num> quantities;

  String get text => [formula, ...inputs, result, ...qualifiers].join('\n');
}

const _daily = 'lib/daily/activities/';
const _monthly = 'lib/monthly/sleeper_update.dart';
const _beforeDay =
    'Current inputs only. Squad orders, availability and other daily events '
    'can change whether this assignment runs.';

String _number(num value) => value == value.roundToDouble()
    ? value.round().toString()
    : value.toStringAsFixed(4).replaceFirst(RegExp(r'\.?0+$'), '');

String _skills(Creature actor, List<Skill> skills) => skills
    .map((skill) => '${skill.displayName} ${actor.skill(skill)}')
    .join(' · ');

/// Pure data only: no daily/monthly handler, RNG, training or income mutation.
/// The six fundraising helpers are called ONLY with estimate:true; their source
/// branch reads raw skill, clothing, weapon, public mood and laws without rolls.
ActivityCalculation calculationForActivity(
  ActivityType type, {
  Creature? actor,
  Activity? activity,
  bool? sleeper,
}) {
  final order = activity?.type == type
      ? activity
      : actor?.activity.type == type
      ? actor!.activity
      : null;
  final undercover = sleeper ?? actor?.sleeperAgent ?? false;
  switch (type) {
    case ActivityType.donations:
    case ActivityType.sellTshirts:
    case ActivityType.sellArt:
    case ActivityType.sellMusic:
    case ActivityType.sellDrugs:
    case ActivityType.prostitution:
      return _fundraising(type, actor);
    case ActivityType.study:
    case ActivityType.takeClass:
      return _learning(type, actor, order);
    case ActivityType.teachLiberalArts:
    case ActivityType.teachCovert:
    case ActivityType.teachFighting:
      return _teaching(type, actor);
    case ActivityType.hacking:
    case ActivityType.ccfraud:
      return _hacking(type, actor);
    case ActivityType.writeGuardian:
    case ActivityType.streamGuardian:
      return _guardian(type, actor);
    case ActivityType.makeClothing:
    case ActivityType.makeFlag:
      return _crafting(type, actor, order);
    case ActivityType.graffiti:
      final art = actor?.skill(Skill.art);
      final denominator = art == null ? null : math.max(30 - 2 * art, 5);
      return ActivityCalculation(
        formula:
            'Mural start: 1 in max(30 − 2 × Art, 5). '
            'Mural completion: 1 in 3; completed power = (Art + 2d6) ÷ 3, '
            'discarding the fraction.',
        inputs: actor == null
            ? const []
            : [
                _skills(actor, [Skill.art, Skill.streetSmarts]),
              ],
        result: denominator == null
            ? 'Select an artist to show the current mural-start denominator.'
            : 'Current mural-start check: 1 in $denominator '
                  '(${_number(100 / denominator)}%) after avoiding police.',
        qualifiers: [
          'The police gate is 1 in 10 followed by Street Smarts + 2d6 < 9. '
              'A trigger starts an arrest encounter; it is not an arrest outcome.',
          'A normal tag adds 1 Juice up to 50. A completed mural adds its '
              'power in Juice up to 20 × power. Spraypaint is required.',
          if (order?.view != null)
            'Currently working on a mural about ${order!.view!.label}. '
                'The completion check replaces the mural-start check.',
          _beforeDay,
        ],
        quantities: {
          'muralStartDenominator': ?denominator,
          if (denominator != null) 'muralStartPercent': 100 / denominator,
          'muralCompletionDenominator': 3,
          'policeCheckDifficulty': 9,
        },
        source: '${_daily}graffiti.dart',
      );
    case ActivityType.trouble:
      final team = actor == null ? <Creature>[] : _dailyTeam(type, actor);
      final baseline = team.fold<int>(
        0,
        (sum, person) =>
            sum +
            person.skill(Skill.art) +
            7 +
            person.skill(Skill.streetSmarts),
      );
      return ActivityCalculation(
        formula:
            'Team power = sum(Art + 2d6 + Street Smarts). '
            'Impact = 1 + one point for each random draw below team power '
            'from 0–9, 0–19, 0–39, 0–59, 0–79 and 0–99.',
        inputs: actor == null
            ? const []
            : [
                _skills(actor, [Skill.art, Skill.streetSmarts]),
                '${team.length} currently eligible activists in the daily pool',
              ],
        result: actor == null
            ? 'Impact is 1–7; a real roll and the chosen incident decide it.'
            : 'Using 7 for every 2d6 roll gives team-power baseline $baseline. '
                  'Actual impact is 1–7.',
        qualifiers: const [
          'Awareness gets impact ÷ 2 and approval gets impact ÷ 4, '
              'discarding fractions; the selected issue gets impact power.',
          'Incident choice decides Juice and criminal charges. A criminal '
              'incident has a 1-in-30 police/hostile gate followed by '
              'Street Smarts + 2d6 < 9.',
          _beforeDay,
        ],
        quantities: {'baselineTeamPower': baseline, 'teamSize': team.length},
        estimated: true,
        source: '${_daily}trouble.dart',
      );
    case ActivityType.communityService:
      final awareness = game.publicOpinion[View.lcsKnown] ?? 0;
      // U is an integer 0..99, so fractional awareness uses ceil, not truncation.
      final chance = awareness.ceil().clamp(0, 100);
      final gain = actor == null
          ? null
          : actor.juice >= 10
          ? 0
          : math.max(-50, math.min(actor.juice + 1, 10)) - actor.juice;
      return ActivityCalculation(
        formula:
            'Juice: add 1 only while below 10. '
            'Reputation triggers when awareness > a random integer from 0 to 99.',
        inputs: [
          'Movement awareness ${_number(awareness)}%',
          if (actor != null) 'Current Juice ${actor.juice}',
        ],
        result:
            'Current reputation-trigger chance: $chance%. '
            '${gain == null ? 'Juice gain is capped at 10.' : 'Current personal Juice gain: $gain.'}',
        qualifiers: const [
          'A trigger applies 1 reputation power. Actual approval change also '
              'uses current approval and public interest; it is not a fixed '
              'percentage-point gain.',
          _beforeDay,
        ],
        quantities: {
          'awarenessTriggerPercent': chance,
          'juiceGain': ?gain,
        },
        source: '${_daily}solo_activities.dart',
      );
    case ActivityType.recruiting:
      return _recruiting(actor, order);
    case ActivityType.sleeperLiberal:
      return _sleeperInfluence(actor);
    case ActivityType.sleeperEmbezzle:
      return _sleeperEmbezzlement(actor);
    case ActivityType.sleeperSpy:
    case ActivityType.sleeperSteal:
      return _sleeperOperation(type, actor);
    case ActivityType.sleeperRecruit:
      return _sleeperRecruitment(actor);
    case ActivityType.sleeperConservative:
      return _sleeperRest(actor, conservative: true);
    case ActivityType.none:
      if (undercover) return _sleeperRest(actor);
      return ActivityCalculation(
        formula:
            'Handle one bloody/damaged clothing item. '
            'Damaged clothing requests 5 Tailoring XP; destroyed clothing '
            '(quality > its supported quality levels) becomes recycled cloth.',
        inputs: actor == null
            ? const []
            : [
                'Worn clothing: ${actor.clothing.type.name}',
                'Bloody: ${actor.clothing.bloody ? 'yes' : 'no'} · '
                    'Damaged: ${actor.clothing.damaged ? 'yes' : 'no'}',
              ],
        result:
            'Clothing care runs daily without a fee. If worn clothing is '
            'clean, the base stock supplies the item to handle.',
        qualifiers: const [
          'XP is limited by the Tailoring attribute cap and the existing XP '
              'storage limit. Routine healing runs separately.',
        ],
        source: '${_daily}clothing_repair.dart',
      );
    case ActivityType.visit:
      final site = order?.location;
      final team = actor?.squad ?? game.activeSquad;
      final cityTravel =
          site != null &&
          team != null &&
          team.members.isNotEmpty &&
          site.cityId != team.members.first.base?.cityId;
      final cost = cityTravel ? team.members.length * 100 : 0;
      return ActivityCalculation(
        formula:
            'Intercity travel = \$100 × squad members. '
            'A squad destination replaces members’ personal daily assignments.',
        inputs: [
          if (team != null) '${team.members.length} squad members',
          if (site != null) 'Selected destination: ${site.name}',
        ],
        result: site == null
            ? 'Choose a destination to calculate the intercity fee.'
            : 'Current intercity fee: \$$cost.',
        qualifiers: const [
          'Closed or besieged sites cancel departure. A destination in another '
              'area needs a car; an intercity departure also needs enough cash.',
        ],
        quantities: {'travelCost': cost},
        source: 'lib/daily/advance_day.dart',
      );
    case ActivityType.sleeperJoinLcs:
      return ActivityCalculation(
        formula:
            'Return the sleeper to active membership through the original '
            'job-exit handler; there is no income or recruitment roll here.',
        result: 'Processed with the daily assignments.',
        qualifiers: const [
          'Needs an LCS-controlled safehouse outside siege. Prefers one in '
              'the current city with residents, then any in that city, '
              'then the first viable safehouse elsewhere. The return does '
              'not generate equipment or income.',
        ],
        source: '${_daily}sleeper_join_lcs.dart',
      );
    case ActivityType.interrogation:
      return _interrogation(actor, order);
    case ActivityType.bury:
      return _burial(actor);
    case ActivityType.wheelchair:
      return ActivityCalculation(
        formula:
            'One completed daily assignment provides a wheelchair, '
            'with no cash deduction and no skill roll.',
        inputs: [
          if (actor != null)
            'Already has a wheelchair: ${actor.hasWheelchair ? 'yes' : 'no'}',
        ],
        result:
            'Sets wheelchair ownership to yes and returns the assignment '
            'to Lay Low. Cost: \$0.',
        qualifiers: const [_beforeDay],
        quantities: const {'dailyFee': 0, 'completedAssignmentsNeeded': 1},
        source: '${_daily}solo_activities.dart',
      );
    case ActivityType.augment:
      return ActivityCalculation(
        formula:
            'This activity is not offered by the current assignment menu '
            'and has no daily dispatch branch.',
        result: 'No augmentation calculation is available here.',
        source: '${_daily}solo_activities.dart',
      );
    case ActivityType.stealCars:
    case ActivityType.clinic:
      return ActivityCalculation(
        formula:
            'The original encounter or treatment checks the selected person, '
            'equipment, location and subsequent choices.',
        result:
            'There is no single fixed payout or overall success percentage '
            'for this assignment.',
        qualifiers: const [_beforeDay],
        source: '${_daily}solo_activities.dart',
      );
  }
}

ActivityCalculation _fundraising(ActivityType type, Creature? actor) {
  final skills = switch (type) {
    ActivityType.donations => [Skill.persuasion, Skill.streetSmarts],
    ActivityType.sellTshirts => [Skill.tailoring, Skill.business],
    ActivityType.sellArt => [Skill.art, Skill.business],
    ActivityType.sellMusic => [Skill.music, Skill.streetSmarts],
    ActivityType.sellDrugs => [
      Skill.persuasion,
      Skill.business,
      Skill.streetSmarts,
    ],
    _ => [Skill.seduction, Skill.seduction, Skill.streetSmarts, Skill.business],
  };
  final mood = game.politics.publicMood();
  final highImpact = type == ActivityType.donations;
  final moodMultiplier = switch (mood) {
    > 90 => highImpact ? 1 / 16 : 1 / 4,
    > 65 => highImpact ? 1 / 8 : 1 / 4,
    > 35 => highImpact ? 1 / 4 : 1 / 2,
    > 10 => highImpact ? 1 / 2 : 1.0,
    _ => 1.0,
  };
  final drugLaw = game.laws[Law.drugs]!;
  final banMultiplier = switch (drugLaw) {
    DeepAlignment.archConservative => 4.0,
    DeepAlignment.conservative => 2.0,
    DeepAlignment.moderate => 1.0,
    DeepAlignment.liberal => .5,
    DeepAlignment.eliteLiberal => .25,
  };
  final roll = actor == null
      ? null
      : (skills.fold<int>(0, (sum, skill) => sum + actor.skill(skill)) /
                    skills.length)
                .round() +
            7;
  final estimate = actor == null
      ? null
      : switch (type) {
          ActivityType.donations => estimateDonationsIncome(
            actor,
            estimate: true,
          ),
          ActivityType.sellTshirts => estimateTshirtIncome(
            actor,
            estimate: true,
          ),
          ActivityType.sellArt => estimateArtIncome(actor, estimate: true),
          ActivityType.sellMusic => estimateMusicIncome(actor, estimate: true),
          ActivityType.sellDrugs => estimateBrownieIncome(
            actor,
            estimate: true,
          ),
          _ => estimateProstitutionIncome(actor, estimate: true),
        };
  final legalPublic =
      type != ActivityType.sellDrugs && type != ActivityType.prostitution;
  final heatGate = actor == null
      ? null
      : actor.heat > 10 * actor.skill(Skill.streetSmarts);
  final interruptPercent = actor == null || !legalPublic
      ? null
      : actor.indecent
      ? heatGate!
            ? 51
            : 50
      : heatGate!
      ? 2
      : 0;
  final formula = switch (type) {
    ActivityType.donations =>
      'Daily income = round((round((Persuasion + Street Smarts) ÷ 2) + 2d6) '
          '× mood multiplier × (clothing professionalism + 1) × 0.5).',
    ActivityType.sellTshirts =>
      'Daily income = round((round((Tailoring + Business) ÷ 2) + 2d6) '
          '× mood multiplier).',
    ActivityType.sellArt =>
      'Daily income = round((round((Art + Business) ÷ 2) + 2d6) '
          '× mood multiplier).',
    ActivityType.sellMusic =>
      'Daily income = round((round((Music + Street Smarts) ÷ 2) + 2d6) '
          '× mood multiplier × instrument multiplier).',
    ActivityType.sellDrugs =>
      'Daily income = round((round((Persuasion + Business + Street Smarts) ÷ 3) '
          '+ 2d6) × drug-law multiplier × 3).',
    _ =>
      'Performance = round((2 × Seduction + Street Smarts + Business) ÷ 4) '
          '+ 2d6. Cash on a working day = 3 × round((4 × performance + 1) ÷ 3). '
          'The work gate is 1 in 3 days.',
  };
  final incomeInputs = <String>[
    if (actor != null) _skills(actor, skills.toSet().toList()),
    if (roll != null) 'Fixed-roll baseline: $roll (2d6 = 7)',
    if (type != ActivityType.sellDrugs && type != ActivityType.prostitution)
      'Public mood ${_number(mood)} · income multiplier ×${_number(moodMultiplier)}',
    if (type == ActivityType.donations && actor != null)
      'Clothing professionalism ${actor.clothing.type.professionalism}',
    if (type == ActivityType.sellMusic && actor != null)
      'Instrument multiplier ×${actor.weapon.type.instrument ? '1' : '0.25'}',
    if (type == ActivityType.sellDrugs)
      'Drug law ${drugLaw.label} · multiplier ×${_number(banMultiplier)}',
    if (actor != null && legalPublic)
      'Heat ${actor.heat} · heat gate above '
          '${10 * actor.skill(Skill.streetSmarts)} · '
          'indecent clothing: ${actor.indecent ? 'yes' : 'no'}',
  ];
  return ActivityCalculation(
    formula: formula,
    inputs: incomeInputs,
    result: estimate == null
        ? 'Select a crew member for the current fixed-roll income estimate.'
        : type == ActivityType.prostitution
        ? '\$$estimate/day estimated across the 1-in-3 work gate; '
              '\$${3 * estimate} on a working day (2d6 = 7), before stings.'
        : '\$$estimate/day estimated (2d6 = 7), before incidents.'
              '${interruptPercent == null ? '' : ' Police-interruption gate: $interruptPercent%.'}',
    qualifiers: [
      '2d6 means the sum of two six-sided dice (2–12). This uses 7 as a '
          'baseline; rounding and incidents mean it is not a guaranteed payout.',
      if (type == ActivityType.prostitution)
        'A working day has a 1-in-50 sting. Street Smarts + 2d6 ≥ 9 avoids '
            'arrest; the sting branch pays no income even when evaded.',
      if (type == ActivityType.sellDrugs && drugLaw <= DeepAlignment.moderate)
        'A search gate is 1 in ${15 * (drugLaw.index + 1)} followed by '
            'Street Smarts + 2d6 < 9; this can open an arrest encounter.',
      if (legalPublic)
        'A police trigger interrupts income and opens an accost/chase encounter; '
            'it is not guaranteed arrest. Indecent clothing first checks '
            '1 in 2. If that draw does not trigger, heat above '
            '10 × Street Smarts checks 1 in 50: both conditions give '
            '50% + 50% × 2% = 51%.',
      _beforeDay,
    ],
    quantities: {
      'baselineRoll': ?roll,
      'estimatedIncome': ?estimate,
      if (type == ActivityType.prostitution && estimate != null)
        'workingDayIncomeBaseline': 3 * estimate,
      if (type == ActivityType.sellDrugs) 'lawMultiplier': banMultiplier,
      if (type != ActivityType.sellDrugs && type != ActivityType.prostitution)
        'moodMultiplier': moodMultiplier,
      if (type == ActivityType.sellMusic && actor != null)
        'instrumentMultiplier': actor.weapon.type.instrument ? 1 : .25,
      'policeInterruptPercent': ?interruptPercent,
    },
    estimated: true,
    source: '${_daily}fundraising.dart',
  );
}

int _trainingGain(Creature actor, Skill skill, int requested) {
  if (actor.skill(skill) >= actor.skillCap(skill) || requested <= 0) return 0;
  final stored = actor.skillXP(skill);
  final limit = (skillXpNeeded(actor.skill(skill)) * 1.5).round();
  return math.min(stored + requested, limit) - stored;
}

ActivityCalculation _learning(
  ActivityType type,
  Creature? actor,
  Activity? activity,
) {
  final paid = type == ActivityType.takeClass;
  final skill = activity?.skill;
  final level = actor != null && skill != null ? actor.skill(skill) : null;
  final cap = actor != null && skill != null ? actor.skillCap(skill) : null;
  final requested = level == null
      ? null
      : paid
      ? 50 - level * 5
      : 5;
  final stopped = level != null && (level >= cap! || paid && level >= 10);
  final gain = actor == null || skill == null || requested == null
      ? null
      : stopped
      ? 0
      : _trainingGain(actor, skill, requested);
  return ActivityCalculation(
    formula: paid
        ? 'Training request = 50 − 5 × current skill, at \$30 per training day. '
              'Classes stop at level 10 or the governing-attribute cap.'
        : 'Training request = 5 XP per day, until the governing-attribute cap.',
    inputs: [
      if (skill != null && level != null)
        '${skill.displayName}: level $level · cap $cap · stored XP ${actor!.skillXP(skill)}',
      if (paid) 'Current cash \$${game.ledger.funds}',
    ],
    result: gain == null
        ? 'Choose the skill to show the current XP calculation.'
        : stopped
        ? 'Current gain: 0 XP; this skill is already at its available limit.'
        : 'Current storage-limited gain: $gain XP if the training runs.'
              '${paid && game.ledger.funds < 30 ? ' Current cash cannot cover the \$30 fee.' : ''}',
    qualifiers: [
      'XP storage is limited to 1.5 × (100 + 10 × current level), rounded. '
          'An injury can lower the cap without reducing existing skill levels.',
      if (paid)
        'The class handler checks XP > 100 + 10 × (current level + 1) '
            'before requesting a level increase.'
      else
        'The practice handler checks XP > 100 + 10 × current level '
            'before requesting a level increase.',
      'Common day-end leveling also promotes when XP ≥ 100 + 10 × current '
          'level. The stricter in-activity checks control immediate messages; '
          'they are not the final daily promotion threshold.',
      _beforeDay,
    ],
    quantities: {
      'skillLevel': ?level,
      'skillCap': ?cap,
      'requestedXp': ?requested,
      'storedXpGain': ?gain,
      if (level != null) 'dayEndLevelThreshold': skillXpNeeded(level),
      if (gain != null && actor != null && skill != null)
        'xpAfterTraining': actor.skillXP(skill) + gain,
      'dailyFee': paid ? 30 : 0,
    },
    source: '${_daily}learning.dart',
  );
}

ActivityCalculation _teaching(ActivityType type, Creature? teacher) {
  final rate = switch (type) {
    ActivityType.teachLiberalArts => 2,
    ActivityType.teachCovert => 6,
    _ => 10,
  };
  final skills = switch (type) {
    ActivityType.teachLiberalArts => const [
      Skill.law,
      Skill.persuasion,
      Skill.writing,
      Skill.religion,
      Skill.business,
      Skill.science,
      Skill.psychology,
      Skill.music,
      Skill.art,
    ],
    ActivityType.teachCovert => const [
      Skill.security,
      Skill.computers,
      Skill.disguise,
      Skill.tailoring,
      Skill.stealth,
      Skill.seduction,
      Skill.driving,
      Skill.streetSmarts,
    ],
    _ => const [
      Skill.heavyWeapons,
      Skill.throwing,
      Skill.martialArts,
      Skill.dodge,
      Skill.firstAid,
      Skill.firearms,
    ],
  };
  var workload = 0;
  var learners = 0;
  int? example;
  String? exampleLabel;
  if (teacher != null) {
    final city = teacher.site?.city;
    final localIds = game.allLocations
        .where((location) => location.city == city)
        .map((location) => location.idString)
        .toSet();
    final justiceIds = game.sites
        .where((site) => site.isPartOfTheJusticeSystem)
        .map((site) => site.idString)
        .toSet();
    final pairs = <(Creature, Skill)>[];
    for (final student in game.pool) {
      if (student == teacher ||
          !localIds.contains(student.locationId) ||
          student.align != Alignment.liberal ||
          student.hospitalized ||
          !student.sleeperAgent && justiceIds.contains(student.locationId)) {
        continue;
      }
      var learns = false;
      for (final skill in skills) {
        if (student.skill(skill) < teacher.skill(skill) &&
            student.skill(skill) < student.skillCap(skill)) {
          pairs.add((student, skill));
          learns = true;
        }
      }
      if (learns) learners++;
    }
    workload = pairs.length;
    if (pairs.isNotEmpty) {
      final (student, skill) = pairs.first;
      var amount =
          teacher.skill(skill) +
          3 * teacher.skill(Skill.teaching) -
          student.skill(skill);
      if (workload > 10) amount = ((amount * 30 ~/ workload) + amount) ~/ 4;
      example = amount.clamp(1, 50);
      exampleLabel = '${student.name}, ${skill.displayName}';
    }
  }
  final cost = rate * math.min(workload, 10);
  return ActivityCalculation(
    formula:
        'Supplies = \$$rate × min(workload, 10). '
        'Each teachable skill/student pair counts once. '
        'Training = teacher’s topic skill + 3 × Teaching − student’s topic skill.',
    inputs: [
      if (teacher != null) 'Teaching ${teacher.skill(Skill.teaching)}',
      skills.map((skill) => skill.displayName).join(', '),
      if (teacher != null) '$learners learners · $workload teachable pairs',
    ],
    result: teacher == null
        ? 'Select a teacher to calculate current students and supplies.'
        : 'Current supplies: \$$cost per day.'
              '${example == null ? ' No teachable pair; the assignment will stop.' : ' Example: $exampleLabel requests $example XP.'}',
    qualifiers: [
      'When workload > 10, training becomes '
          'floor((floor(training × 30 ÷ workload) + training) ÷ 4). '
          'The final request is clamped to 1–50 XP and then storage/skill caps apply.',
      'Students are other liberals located in the same city, not hospitalized, '
          'and outside the justice system unless they are sleepers.',
      if (teacher != null && game.ledger.funds < cost)
        'Current cash \$${game.ledger.funds} cannot cover these supplies.',
      _beforeDay,
    ],
    quantities: {
      'costPerPair': rate,
      'workload': workload,
      'learnerCount': learners,
      'dailyFee': cost,
      'exampleRequestedXp': ?example,
    },
    source: '${_daily}teaching.dart',
  );
}

/// Preview grouping reads the whole daily pool, not just the selected squad.
/// It mirrors the existing prefilter without clearing orders or moving people.
List<Creature> _dailyTeam(ActivityType type, Creature actor) {
  final people = <Creature>[];
  for (final person in game.pool) {
    if (!person.alive ||
        person.hospitalized ||
        person.vacationDaysLeft > 0 ||
        person.hidingDaysLeft != 0 ||
        person.align != Alignment.liberal ||
        person.imprisoned) {
      continue;
    }
    final squadOrder = person.squad?.activity.type;
    if (squadOrder == ActivityType.visit) continue;
    final effective = squadOrder != null && squadOrder != ActivityType.none
        ? squadOrder
        : person == actor
        ? type
        : person.activity.type;
    if (effective != type) continue;
    if (type == ActivityType.hacking &&
        person.base?.compound.hackerDen != true) {
      continue;
    }
    final site = person.site ?? person.base;
    if (site?.isPartOfTheJusticeSystem == true && !person.sleeperAgent) {
      continue;
    }
    if (site?.siege.underSiege == true &&
        (type != ActivityType.hacking && type != ActivityType.ccfraud ||
            site!.siege.lightsOff)) {
      continue;
    }
    people.add(person);
  }
  return people;
}

ActivityCalculation _hacking(ActivityType type, Creature? actor) {
  final fraud = type == ActivityType.ccfraud;
  final team = actor == null ? <Creature>[] : _dailyTeam(type, actor);
  final scores = team
      .map((person) => person.skill(Skill.computers) + 7)
      .toList();
  final best = scores.isEmpty ? 0 : scores.reduce(math.max);
  final baseline = fraud
      ? scores.fold<int>(0, (sum, score) => sum + score)
      : scores.isEmpty
      ? 0
      : best + team.length - 1;
  final draws = math.max(0, (baseline - 10) ~/ 2);
  return ActivityCalculation(
    formula: fraud
        ? 'Team score = sum(Computers + 2d6). '
              'For thresholds 11, 13, 15, … strictly below that score, '
              'add one random cash draw from \$0–\$50.'
        : 'Best roll = max(Computers + 2d6). '
              'Team score = best roll + hacker count − 1. '
              'Score 13–14 is a minor hack; 15+ is a major hack.',
    inputs: [
      if (actor != null) 'Selected Computers ${actor.skill(Skill.computers)}',
      if (actor != null)
        '${team.length} eligible assigned people across the daily pool',
    ],
    result: actor == null
        ? 'Select a crew member for an all-pool fixed-roll baseline (2d6 = 7).'
        : fraud
        ? 'Fixed-roll baseline (2d6 = 7): score $baseline → $draws cash draws. '
              'At that fixed score their mean is \$${25 * draws}; '
              'this is not the expected payout across all skill rolls.'
        : 'Fixed-roll baseline (2d6 = 7): best roll $best, team score $baseline. '
              '${team.isEmpty
                  ? 'No currently eligible hacker.'
                  : baseline < 13
                  ? 'Below the success threshold.'
                  : baseline < 15
                  ? 'Minor-hack threshold reached.'
                  : 'Major-hack threshold reached.'}',
    qualifiers: [
      if (fraud)
        'Real cash varies from 0 to 50 per draw; each hacker’s displayed '
            'income is total cash ÷ hacker count, discarding the fraction. '
            'Charges check cash ÷ 10 > (random integer 0…score + score) ÷ 2.'
      else
        'Trace evasion = unboosted best roll − a random integer 0–4. '
            'Required score is 15 for minor hacks, usually 17 for major '
            'hacks, 19 for military and 23 for CIA targets. Extra hackers '
            'boost success, not trace evasion.',
      if (fraud)
        'The assignment menu checks Computers and a Hacker Den. The daily '
            'fraud filter does not remove an existing order solely because '
            'the base lacks a Hacker Den.'
      else
        'Daily hacking requires a Hacker Den at each actor’s base. '
            'Siege power cuts can cancel this assignment.',
      'Each participant requests 5 Computers XP. Actual rolls and incident '
          'selection remain random.',
      _beforeDay,
    ],
    quantities: {
      'teamSize': team.length,
      'baselineTeamScore': baseline,
      if (!fraud) 'baselineBestRoll': best,
      if (fraud) 'baselineCashDraws': draws,
      if (fraud) 'conditionalMeanCash': 25 * draws,
    },
    estimated: true,
    source: '${_daily}hacking.dart',
  );
}

ActivityCalculation _guardian(ActivityType type, Creature? actor) {
  final stream = type == ActivityType.streamGuardian;
  final skill = stream ? Skill.persuasion : Skill.writing;
  final knowledge = actor == null
      ? null
      : [
          Skill.law,
          Skill.science,
          Skill.religion,
          Skill.business,
        ].fold<int>(0, (sum, skill) => sum + actor.skill(skill));
  final baseline = actor == null
      ? null
      : (stream ? 4 : 1) * (actor.skill(skill) + 7 + knowledge! - 5);
  return ActivityCalculation(
    formula: stream
        ? 'Influence power = 4 × (Persuasion + 2d6 + Law + Science + Religion '
              '+ Business − 5).'
        : 'Influence power = Writing + 2d6 + Law + Science + Religion '
              '+ Business − 5.',
    inputs: actor == null
        ? const []
        : [
            _skills(actor, [
              skill,
              Skill.law,
              Skill.science,
              Skill.religion,
              Skill.business,
            ]),
          ],
    result: baseline == null
        ? 'Select a contributor for a fixed-roll influence baseline (2d6 = 7).'
        : 'Fixed-roll baseline (2d6 = 7): $baseline power on a random issue.',
    qualifiers: [
      'This adds background influence; it is not a direct percentage-point '
          'change in public opinion. Requests 5 ${skill.displayName} XP per day.',
      if (stream) 'Daily streaming requires a streaming studio at the base.',
      _beforeDay,
    ],
    quantities: {'baselineInfluencePower': ?baseline},
    estimated: true,
    source: '${_daily}guardian.dart',
  );
}

ActivityCalculation _crafting(
  ActivityType type,
  Creature? actor,
  Activity? activity,
) {
  final flag = type == ActivityType.makeFlag;
  final clothing = activity?.clothingType;
  final banner = activity?.flagType;
  final armor = activity?.armorUpgrade;
  final selected = flag ? banner != null : clothing != null && armor != null;
  final baseDifficulty = flag
      ? banner?.makeDifficulty
      : clothing == null || armor == null
      ? null
      : clothing.makeDifficulty + armor.makeDifficulty;
  final fullCost = flag
      ? banner?.makePrice
      : clothing == null || armor == null
      ? null
      : clothing.makePrice + armor.makePrice;
  final cloth =
      actor?.site?.loot.whereType<Loot>().any((item) => item.type.cloth) ??
      false;
  final cost = fullCost == null
      ? null
      : cloth
      ? fullCost ~/ 2
      : fullCost;
  final difficulty = actor == null || baseDifficulty == null
      ? null
      : baseDifficulty - actor.skill(Skill.tailoring) + (flag ? 0 : 4);
  final flagChance = flag && difficulty != null
      ? difficulty <= 0
            ? 100.0
            : difficulty >= 10
            ? 0.0
            : 100 * (1 - difficulty * difficulty / 100)
      : null;
  return ActivityCalculation(
    formula: flag
        ? 'Difficulty = flag difficulty − Tailoring. '
              'Success when max(two independent random integers 0–9) ≥ difficulty.'
        : 'Difficulty = clothing difficulty + armor difficulty − Tailoring + 4. '
              'Quality starts at 1; it worsens while min(two random integers '
              '0–9) < difficulty − quality.',
    inputs: [
      if (actor != null) 'Tailoring ${actor.skill(Skill.tailoring)}',
      if (selected) 'Selected item: ${flag ? banner!.name : clothing!.name}',
      if (difficulty != null) 'Current adjusted difficulty $difficulty',
      if (actor != null) 'Recyclable cloth on site: ${cloth ? 'yes' : 'no'}',
    ],
    result: !selected
        ? 'Select the item${flag ? '' : ' and armor upgrade'} to calculate cost and difficulty.'
        : 'Current supplies: \$$cost${cloth ? ' (halved, discarding the fraction)' : ''}.'
              '${flagChance == null ? '' : ' With these inputs the flag check succeeds ${_number(flagChance)}% of the time, if crafting runs.'}',
    qualifiers: [
      'One cloth item halves supplies. The handler consumes that cloth before '
          'the cash check. Costs are paid even when the craft fails.',
      if (baseDifficulty != null)
        'Initial Tailoring training request: ${baseDifficulty * 2 + 1} XP.',
      if (!flag)
        'Each quality step requests 5 extra XP. Worse than the clothing’s '
            'supported quality levels means failure and recycled cloth.',
      if (cost != null && game.ledger.funds < cost)
        'Current cash \$${game.ledger.funds} cannot cover supplies.',
      _beforeDay,
    ],
    quantities: {
      'supplyCost': ?cost,
      'adjustedDifficulty': ?difficulty,
      'flagSuccessPercent': ?flagChance,
      if (baseDifficulty != null) 'initialTrainingXp': baseDifficulty * 2 + 1,
    },
    source: flag
        ? '${_daily}flag_creation.dart'
        : '${_daily}clothing_creation.dart',
  );
}

ActivityCalculation _recruiting(Creature? actor, Activity? activity) {
  // recruitableCreatures and Activity.recruitData mutate a shared cached list.
  // Read static type metadata plus the original mutant law rule instead.
  final target = creatureTypes[activity?.idString];
  var difficulty = target?.recruitActivityDifficulty;
  if (target?.id == CreatureTypeIds.mutant) {
    difficulty = game.mutantsCommon
        ? 2
        : game.mutantsPossible
        ? 6
        : null;
  }
  final baseline = actor == null ? null : actor.skill(Skill.streetSmarts) + 7;
  final count = difficulty == null || baseline == null
      ? null
      : difficulty >= 10 || difficulty <= 0
      ? 0
      : math.min(10, (baseline / difficulty).round());
  return ActivityCalculation(
    formula:
        'Meetings = min(10, round((Street Smarts + 7) ÷ profession difficulty)). '
        'Difficulty 10 or higher produces no meeting.',
    inputs: [
      if (actor != null) 'Street Smarts ${actor.skill(Skill.streetSmarts)}',
      if (target != null) 'Target profession: ${target.name}',
      if (difficulty != null) 'Meeting difficulty $difficulty',
    ],
    result: count == null
        ? 'Choose an available target profession to calculate meeting count.'
        : 'Fixed encounter roll (2d6 = 7): $count meetings. '
              'This is not a recruit count.',
    qualifiers: const [
      'Finding contacts requests 5 Street Smarts XP. Conversion happens in '
          'the subsequent conversation and has no single overall success rate.',
      'Mutant difficulty is 2 when both pollution and nuclear law are '
          'Arch Conservative, 6 when only one is; otherwise that profession '
          'is unavailable.',
      _beforeDay,
    ],
    quantities: {
      'meetingDifficulty': ?difficulty,
      'meetingCount': ?count,
    },
    source: '${_daily}recruiting.dart',
  );
}

int _noticePercent(double infiltration, int multiplier) =>
    (99 - (multiplier * infiltration).floor()).clamp(0, 100);

ActivityCalculation _sleeperRest(Creature? actor, {bool conservative = false}) {
  final trust = actor?.infiltration;
  return ActivityCalculation(
    formula: 'Monthly infiltration = clamp(current + random 0.01–0.05, 0, 1).',
    inputs: [
      if (trust != null) 'Current infiltration ${_number(100 * trust)}%',
    ],
    result: trust == null
        ? 'Adds 1–5 infiltration percentage points at month end, capped at 100%.'
        : 'Next infiltration range: '
              '${_number(100 * (trust + .01).clamp(0, 1))}–'
              '${_number(100 * (trust + .05).clamp(0, 1))}%.',
    qualifiers: [
      if (conservative)
        'This assignment currently follows the default infiltration branch; '
            'the monthly handler has no separate conservative-influence effect.',
      'Infiltration is job access and trust. Individual operations use their '
          'own gates; it is not a universal success percentage.',
    ],
    quantities: {
      if (trust != null) 'minimumNextInfiltration': (trust + .01).clamp(0, 1),
      if (trust != null) 'maximumNextInfiltration': (trust + .05).clamp(0, 1),
    },
    source: _monthly,
  );
}

ActivityCalculation _sleeperEmbezzlement(Creature? actor) {
  final tier = switch (actor?.type.id) {
    CreatureTypeIds.corporateCEO ||
    CreatureTypeIds.president ||
    CreatureTypeIds.insuranceCEO => 50000,
    CreatureTypeIds.eminentScientist ||
    CreatureTypeIds.corporateManager ||
    CreatureTypeIds.bankManager ||
    CreatureTypeIds.auditor ||
    CreatureTypeIds.actuary ||
    CreatureTypeIds.nursingHomeAdmin => 5000,
    _ => 500,
  };
  final trust = actor?.infiltration;
  final quiet = trust == null ? null : (tier * trust).round();
  final noticed = trust == null
      ? null
      : trust - .2 < 0
      ? 0
      : (tier * (trust - .2)).round();
  final notice = trust == null ? null : _noticePercent(trust, 90);
  return ActivityCalculation(
    formula:
        'Notice if random integer 0–99 > 90 × infiltration. '
        'Notice subtracts 0.20 infiltration before payout. '
        'Monthly cash = round(profession tier × remaining infiltration).',
    inputs: [
      if (actor != null) '${actor.type.name} · profession tier \$$tier',
      if (trust != null) 'Current infiltration ${_number(100 * trust)}%',
    ],
    result: quiet == null
        ? 'Select a sleeper for both quiet and noticed monthly payouts.'
        : 'Quiet month: \$$quiet. Notice gate: $notice%. '
              '${trust! - .2 < 0 ? 'If noticed, infiltration becomes negative: capture and no payout.' : 'If noticed: \$$noticed after the infiltration loss.'}',
    qualifiers: const [
      'Tiers: 50,000 for CEO/President/Insurance CEO; 5,000 for senior '
          'management, finance, eminent scientists and nursing-home admin; '
          '500 otherwise. A surviving attempt adds 10 Juice up to 1,000.',
      'At exactly 20% infiltration, notice leaves 0% and pays \$0. Capture '
          'requires infiltration below zero, not equal to zero.',
    ],
    quantities: {
      'professionTier': tier,
      'quietIncome': ?quiet,
      'noticedIncome': ?noticed,
      'noticePercent': ?notice,
    },
    source: _monthly,
  );
}

ActivityCalculation _sleeperOperation(ActivityType type, Creature? actor) {
  final steal = type == ActivityType.sleeperSteal;
  final multiplier = steal ? 95 : 100;
  final workSite = actor?.workSite;
  final camp = actor == null
      ? null
      : game.sites
            .where(
              (site) =>
                  site.type == SiteType.homelessEncampment &&
                  site.city == actor.workLocation.city,
            )
            .firstOrNull;
  final notice = actor == null
      ? null
      : _noticePercent(actor.infiltration, multiplier);
  return ActivityCalculation(
    formula:
        'Notice if random integer 0–99 > $multiplier × infiltration. '
        'Current notice chance counts exactly the failing integer draws.',
    inputs: [
      if (actor != null) 'Infiltration ${_number(100 * actor.infiltration)}%',
      if (actor?.workSite != null) 'Worksite: ${actor!.workSite!.name}',
      if (actor != null)
        'Dead-drop camp: ${camp?.name ?? 'none in the work location’s city'}',
    ],
    result: notice == null
        ? 'Select a sleeper to show this operation’s current notice gate.'
        : steal && camp == null
        ? 'No local dead-drop camp; the equipment-theft handler returns '
              'before its notice check.'
        : steal && workSite == null
        ? 'No worksite equipment table is available. The notice formula '
              'alone is not a usable theft forecast.'
        : 'Monthly notice gate: $notice%. '
              '${steal ? 'Attempts 1–10 equipment drops if the operation can run.' : 'Passing this gate can map the worksite; a document leak also depends on profession and location.'}',
    qualifiers: steal
        ? [
            'Notice subtracts 20 infiltration points; negative infiltration leads '
                'to capture. A surviving attempt adds 10 Juice up to 1,000.',
            'After the notice check, infiltration changes by +2 to −7 percentage '
                'points. Loot attempts may return no item; 1–10 attempts does not '
                'guarantee 1–10 items. Needs a worksite and homeless dead-drop camp.',
          ]
        : [
            'A failed snooping gate subtracts 5 infiltration points. Negative '
                'infiltration leads to losing the job; no document is leaked.',
            'A document leak subtracts 20 infiltration points and adds 50 Juice '
                'up to 1,000. Some professions have a direct leak branch; other '
                'supported worksites require a further 1-in-3 gate. The dead-drop '
                'camp must be usable and normal site visibility available.',
            'The gate is not an overall chance to obtain documents.',
            if (actor != null && (camp == null || camp.siege.underSiege))
              'The current dead-drop camp is missing or besieged; '
                  'the document-leak branch will not run.',
          ],
    quantities: {'noticePercent': ?notice},
    source: _monthly,
  );
}

ActivityCalculation _sleeperRecruitment(Creature? actor) {
  // The public president getter can generate a new random character. toJson
  // exposes the existing reference without creating it or changing the RNG.
  final president =
      actor != null &&
      identical(actor, game.uniqueCreatures.toJson()['_president']);
  final bonus = actor == null
      ? null
      : (actor.attribute(Attribute.charisma) / 10).round() +
            (actor.juice / 100).round();
  return ActivityCalculation(
    formula: president
        ? 'Cabinet bonus votes = round(Charisma ÷ 10) + round(Juice ÷ 100). '
              'Confirmation needs 51 Senate votes; a Vice President also '
              'needs a House majority.'
        : 'Recruit only while subordinate capacity remains. In a generated '
              'encounter, coworkers pass the location gate; outsiders need '
              'a 1-in-5 gate, and non-liberals need another 1-in-5 gate.',
    inputs: [
      if (actor != null)
        'Remaining subordinate capacity: ${actor.subordinatesLeft}',
      if (president)
        'Charisma ${actor.attribute(Attribute.charisma)} · Juice ${actor.juice}',
    ],
    result: actor == null
        ? 'Select a sleeper for current capacity and any cabinet-vote bonus.'
        : president
        ? 'Current cabinet-vote bonus: $bonus. Candidate alignment also '
              'depends on the current Senate and House.'
        : 'Generated coworkers and their alignment determine whether anyone '
              'joins; there is no fixed overall recruit probability.',
    qualifiers: const [
      'Needs a valid worksite or local park/camp encounter. At capacity zero '
          'the recruiting branch does nothing. Cabinet position selection '
          'and encounters remain random.',
    ],
    quantities: {
      if (actor != null) 'subordinateCapacity': actor.subordinatesLeft,
      if (president && bonus != null) 'cabinetBonusVotes': bonus,
    },
    source: _monthly,
  );
}

ActivityCalculation _sleeperInfluence(Creature? actor) {
  final base = actor == null
      ? null
      : actor.attribute(Attribute.charisma) +
            actor.attribute(Attribute.heart) +
            actor.attribute(Attribute.intelligence) +
            actor.skill(Skill.persuasion);
  final weighted = switch (actor?.type.id) {
    CreatureTypeIds.artCritic => const {Skill.writing: 3, Skill.art: 2},
    CreatureTypeIds.painter || CreatureTypeIds.sculptor => const {Skill.art: 5},
    CreatureTypeIds.musicCritic => const {Skill.writing: 3, Skill.music: 2},
    CreatureTypeIds.musician => const {Skill.music: 5},
    CreatureTypeIds.author ||
    CreatureTypeIds.journalist => const {Skill.writing: 5},
    CreatureTypeIds.liberalJudge ||
    CreatureTypeIds.conservativeJudge => const {Skill.writing: 1, Skill.law: 1},
    CreatureTypeIds.lawyer => const {Skill.law: 1},
    CreatureTypeIds.labTech ||
    CreatureTypeIds.eminentScientist => const {Skill.science: 1},
    CreatureTypeIds.corporateCEO ||
    CreatureTypeIds.corporateManager ||
    CreatureTypeIds.insuranceCEO ||
    CreatureTypeIds.auditor ||
    CreatureTypeIds.actuary => const {Skill.business: 1},
    CreatureTypeIds.priest ||
    CreatureTypeIds.nun ||
    CreatureTypeIds.televangelist => const {Skill.religion: 5},
    CreatureTypeIds.educator ||
    CreatureTypeIds.socialWorker ||
    CreatureTypeIds.psychologist => const {Skill.psychology: 1},
    CreatureTypeIds.teacher ||
    CreatureTypeIds.yogaInstructor => const {Skill.teaching: 1},
    CreatureTypeIds.athlete ||
    CreatureTypeIds.cheerleader => const {Skill.dodge: 1},
    CreatureTypeIds.nursingHomeAttendant ||
    CreatureTypeIds.dietician ||
    CreatureTypeIds.physicalTherapist ||
    CreatureTypeIds.nurse ||
    CreatureTypeIds.doctor => const {Skill.firstAid: 1},
    _ => const <Skill, int>{},
  };
  final multiplier = switch (actor?.type.id) {
    CreatureTypeIds.corporateCEO ||
    CreatureTypeIds.president ||
    CreatureTypeIds.eminentScientist ||
    CreatureTypeIds.ccsArchConservative ||
    CreatureTypeIds.policeChief => 20,
    CreatureTypeIds.deathSquad ||
    CreatureTypeIds.educator ||
    CreatureTypeIds.televangelist => 6,
    CreatureTypeIds.actor ||
    CreatureTypeIds.gangUnit ||
    CreatureTypeIds.militaryPolice ||
    CreatureTypeIds.seal ||
    CreatureTypeIds.conservativeJudge => 4,
    _ => 2,
  };
  const noInfluence = {
    CreatureTypeIds.childLaborer,
    CreatureTypeIds.genetic,
    CreatureTypeIds.guardDog,
    CreatureTypeIds.bum,
    CreatureTypeIds.crackhead,
    CreatureTypeIds.tank,
    CreatureTypeIds.punk,
    CreatureTypeIds.goth,
    CreatureTypeIds.emo,
    CreatureTypeIds.hippie,
    CreatureTypeIds.unionWorker,
  };
  final bonus = actor == null
      ? 0
      : weighted.entries.fold<int>(
          0,
          (sum, item) => sum + actor.skill(item.key) * item.value,
        );
  final rawPower = base == null
      ? null
      : ((base + bonus) * multiplier * actor!.infiltration).round();
  final media = actor?.type.id == CreatureTypeIds.newsAnchor
      ? View.cableNews
      : actor?.type.id == CreatureTypeIds.radioPersonality
      ? View.amRadio
      : null;
  final nextMediaOpinion = media == null
      ? null
      : (game.publicOpinion[media]! +
                (100 - game.publicOpinion[media]!) *
                    math
                        .min(2, 1 + game.politics.publicInterest[media]! / 16)
                        .round() /
                    100)
            .clamp(0, 100);
  final power = actor == null || rawPower == null
      ? null
      : noInfluence.contains(actor.type.id)
      ? 0
      : media == null
      ? rawPower
      : rawPower * (100 - nextMediaOpinion!) ~/ 100;
  return ActivityCalculation(
    formula:
        'Monthly influence budget = round((Charisma + Heart + Intelligence '
        '+ Persuasion + profession skill bonus) × profession multiplier '
        '× infiltration).',
    inputs: actor == null
        ? const []
        : [
            'Charisma ${actor.attribute(Attribute.charisma)} · '
                'Heart ${actor.attribute(Attribute.heart)} · '
                'Intelligence ${actor.attribute(Attribute.intelligence)} · '
                'Persuasion ${actor.skill(Skill.persuasion)}',
            'Profession bonus $bonus · multiplier ×$multiplier · '
                'infiltration ${_number(100 * actor.infiltration)}%',
            if (weighted.isNotEmpty)
              weighted.entries
                  .map(
                    (entry) =>
                        '${entry.key.displayName} ${actor.skill(entry.key)} × ${entry.value}',
                  )
                  .join(' · '),
            if (media != null)
              '${media.label} opinion ${_number(game.publicOpinion[media]!)}%; '
                  'after this operation’s first opinion-power step '
                  '${_number(nextMediaOpinion!)}%',
          ],
    result: power == null
        ? 'Select a sleeper to show current profession-weighted influence.'
        : 'Current monthly influence budget: $power.'
              '${noInfluence.contains(actor!.type.id) ? ' This profession has no influence branch.' : ''}',
    qualifiers: [
      if (media != null)
        'Media professions apply an additional factor '
            '(100 − ${media.label} opinion) ÷ 100, discarding the fraction.',
      'Profession decides the affected issues; some roles choose random '
          'issues. This adds background power, not a fixed opinion percentage. '
          'Transferred power above 50 also requests opinion power ÷ 50, '
          'discarding the fraction.',
      'This assignment does not gain the resting infiltration bonus.',
    ],
    quantities: {
      'baseInfluence': ?base,
      'professionBonus': bonus,
      'professionMultiplier': multiplier,
      'professionInfluenceBudget': ?rawPower,
      'mediaOpinionAfterEffect': ?nextMediaOpinion,
      'monthlyInfluencePower': ?power,
    },
    source: _monthly,
  );
}

ActivityCalculation _burial(Creature? actor) {
  final localBodies = actor == null
      ? null
      : game.pool
            .where(
              (person) =>
                  !person.alive &&
                  person.site != null &&
                  person.site!.city == actor.site?.city,
            )
            .length;
  final noSite = game.pool
      .where((person) => !person.alive && person.site == null)
      .length;
  final team = actor == null
      ? <Creature>[]
      : _dailyTeam(ActivityType.bury, actor);
  final localBuriers = actor == null
      ? <Creature>[]
      : team.where((person) => person.site?.city == actor.site?.city).toList();
  return ActivityCalculation(
    formula:
        'Disposal check: Street Smarts + 2d6 ≥ 7. '
        'The first assigned burier in each body’s city handles the body. '
        'A failed check opens an arrest encounter and removes that burier '
        'from the remainder of the day’s burial work.',
    inputs: [
      if (actor != null) 'Street Smarts ${actor.skill(Skill.streetSmarts)}',
      if (localBodies != null) '$localBodies bodies currently in this city',
      if (actor != null) '${localBuriers.length} eligible buriers in this city',
    ],
    result: actor == null
        ? 'Select a burier to show current bodies and the check baseline.'
        : 'Fixed-roll check (2d6 = 7): ${actor.skill(Skill.streetSmarts) + 7} '
              'against 7.'
              '${localBuriers.isEmpty ? ' No currently eligible burier.' : ' First handler: ${localBuriers.first.name}.'}',
    qualifiers: [
      'Each handled body requests 50 Street Smarts XP and transfers its loot. '
          'The body leaves the roster before the check, including a failed check.',
      if (noSite > 0)
        '$noSite deceased records without a site are removed separately '
            'without needing a local burier.',
      _beforeDay,
    ],
    quantities: {
      'localBodies': ?localBodies,
      'bodiesWithoutSite': noSite,
      'localBuriers': localBuriers.length,
      'checkDifficulty': 7,
      if (actor != null) 'baselineCheck': actor.skill(Skill.streetSmarts) + 7,
      'requestedXpPerBody': 50,
    },
    estimated: true,
    source: '${_daily}bury_dead.dart',
  );
}

ActivityCalculation _interrogation(Creature? actor, Activity? activity) {
  final hostage = game.pool
      .where((person) => person.id == activity?.idInt)
      .firstOrNull;
  final actorBase = actor == null
      ? null
      : math.max(
          0,
          2 * actor.skill(Skill.psychology) +
              actor.clothing.type.interrogationBasePower,
        );
  final tenders = hostage == null
      ? <Creature>[]
      : game.pool
            .where(
              (person) =>
                  person.alive &&
                  person.location != null &&
                  person.location == hostage.location &&
                  (person == actor ||
                      person.activity.type == ActivityType.interrogation &&
                          person.activity.idInt == hostage.id),
            )
            .toList();
  Creature? lead;
  var bestBase = -1;
  for (final tender in tenders) {
    final base = math.max(
      0,
      2 * tender.skill(Skill.psychology) +
          tender.clothing.type.interrogationBasePower,
    );
    if (base > bestBase) {
      lead = tender;
      bestBase = base;
    }
  }
  final session = hostage == null
      ? null
      : game.interrogationSessions
            .where((item) => item.hostageId == hostage.id)
            .firstOrNull;
  final rapport = lead == null ? null : session?.rapport[lead.id] ?? 0.0;
  final forceBaseline = lead == null
      ? null
      : lead.skill(Skill.psychology) + 7 + (5 * rapport!).round();
  return ActivityCalculation(
    formula:
        'Session lead: highest max(0, 2 × Psychology + clothing base power); '
        'ties use the first tender. The demand-information roll is '
        'Psychology + 2d6 + round(5 × rapport).',
    inputs: [
      if (actor != null)
        'Psychology ${actor.skill(Skill.psychology)} · '
            'clothing base power ${actor.clothing.type.interrogationBasePower}',
      if (hostage != null) 'Selected hostage: ${hostage.name}',
      if (lead != null)
        'Current lead: ${lead.name} · rapport ${_number(rapport!)}',
    ],
    result: lead == null
        ? actorBase == null
              ? 'Select a tender and hostage for current inputs.'
              : 'Selected tender’s lead-selection base: $actorBase. '
                    'Choose a hostage at the same location to form the session.'
        : 'Current lead-selection base: $bestBase. Demand-information '
              'fixed-roll baseline (2d6 = 7): $forceBaseline.',
    qualifiers: const [
      'This is not an overall conversion or information-success chance. '
          'Demanding information lowers rapport by 1, then checks the '
          'hostage’s Wisdom and Religion. Other plans use their own formulas.',
      'Other tenders’ Business, Religion and Science do not raise the current '
          'demand-information roll. Recruitment instead uses lead Psychology, '
          'rapport and the hostage’s Wisdom and Juice.',
      _beforeDay,
    ],
    quantities: {
      'actorLeadSelectionBase': ?actorBase,
      if (lead != null) 'leadSelectionBase': bestBase,
      'demandInformationBaseline': ?forceBaseline,
      'sameLocationTenders': tenders.length,
    },
    estimated: true,
    source:
        'lib/daily/hostages/tend_hostage.dart; '
        'lib/daily/hostages/interrogate.dart',
  );
}
