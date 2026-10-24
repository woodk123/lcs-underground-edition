import 'package:flutter/material.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/modern/activity_calculations.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/skill_help.dart';
import 'package:lcs_new_age/politics/alignment.dart' as politics;

/// Read-only descriptions and formula projections from the retained simulation.
/// No live rolls, training, activity handlers or input loops run here.
class ActivityMechanics {
  const ActivityMechanics({
    required this.type,
    required this.title,
    required this.summary,
    this.policyId,
    this.factors = '',
    this.cost = '',
    this.requirements = '',
    this.risk = '',
    this.details = '',
    this.timing = 'Runs each day until changed, completed or interrupted.',
    this.unavailableReason,
    this.calculation,
  });

  final ActivityType type;
  final String title;
  final String summary;
  final String? policyId;
  final String factors;
  final String cost;
  final String requirements;
  final String risk;
  final String details;
  final String timing;
  final String? unavailableReason;
  final ActivityCalculation? calculation;
}

/// A command's activity identity is authored alongside its original menu.
/// Display labels, letters and coordinates are deliberately not identities.
ActivityType? activityTypeForAction(ConsoleAction action) {
  if (!const {
    'activity',
    'activity-confirm',
    'sleeper-activity',
    'sleeper-activity-confirm',
    'sleeper-bulk-activity',
    'sleeper-bulk-selected',
  }.contains(action.entityType)) {
    return null;
  }
  for (final type in ActivityType.values) {
    if (type.name == action.entityId) return type;
  }
  return null;
}

ActivityMechanics activityMechanics(
  ActivityType type, {
  Creature? actor,
  Activity? activity,
  bool? sleeper,
}) {
  final undercover = sleeper ?? actor?.sleeperAgent ?? false;
  String uses(List<Skill> skills) => skills
      .map(
        (skill) => actor == null
            ? skill.displayName
            : '${skill.displayName} ${actor.skill(skill)}',
      )
      .join(' · ');
  ActivityMechanics help(
    String summary, {
    List<Skill> skills = const [],
    String cost = '',
    String requirements = '',
    String risk = '',
    String details = '',
    String? unavailableReason,
    String timing = 'Runs each day until changed, completed or interrupted.',
  }) => ActivityMechanics(
    type: type,
    title: activity?.type == type ? activity!.description : type.label,
    summary: summary,
    factors: uses(skills),
    cost: cost,
    requirements: requirements,
    risk: risk,
    details: details,
    timing: timing,
    unavailableReason: unavailableReason,
    calculation: calculationForActivity(
      type,
      actor: actor,
      activity: activity ?? Activity(type),
      sleeper: undercover,
    ),
  );
  switch (type) {
    case ActivityType.workPrintShop:
      return help(
        'Work at a staffed print shop: commercial orders earn money, while '
        'movement printing supports Free Speech.',
        skills: const [Skill.business, Skill.writing],
        cost:
            '\$20 running costs per active worker per day; setup is separate.',
        requirements: 'An open print shop at your current home base; at most two workers.',
        details:
            'Assign staff and choose the operating mode through Bases → Manage '
            'print shop. This replaces the worker’s daily assignment. '
            'Squad departures and unavailable staff do not produce shop work. '
            'Closing the shop clears staff assignments. Commercial work trains '
            'Business; movement printing trains Writing and needs available funds.',
      );
    case ActivityType.none:
      if (undercover) {
        return help(
          'Stay out of undercover trouble and rebuild infiltration.',
          cost: 'No activity fee',
          details:
              'At month end, adds 1–5 percentage points to infiltration, '
              'capped at 100%. This is job access and trust, not an automatic '
              'success chance. As with other crew set to Lay Low, clothing '
              'care may also run during daily processing.',
          timing: 'Infiltration improves at month end; clothing care can run daily.',
        );
      }
      return help(
        'Stay out of public activity and wash or mend clothing at the base.',
        cost: 'No activity fee',
        details:
            'Checks worn clothing first, then damaged or bloody clothing in '
            'base inventory. Destroyed clothing is recycled into cloth. '
            'Mending damaged clothing trains Tailoring. '
            'Routine healing is handled separately from the daily assignment.',
      );
    case ActivityType.visit:
      return help(
        'Carry out the squad’s destination order.',
        timing: 'Next day: visit replaces personal orders. Reassign afterward.',
        details:
            'A squad visit replaces individual daily tasks. '
            'After the visit, crew return to Lay Low; their earlier daily '
            'orders do not resume automatically. After an observed visit, '
            'Prepare previous order offers supported daily jobs again for '
            'confirmation in Organisation or People. '
            'Inspecting a building does not move the squad; issuing its order '
            'queues the visit for the next day.',
      );
    case ActivityType.communityService:
      return help(
        'Volunteer to improve the movement’s reputation and build early Juice.',
        cost: 'No activity fee',
        risk: 'No arrest check in this activity',
        details:
            'Adds 1 Juice per day up to 10. Reputation can improve when '
            'public awareness of the movement is high enough. Juice is personal '
            'activist credibility, not money.',
      );
    case ActivityType.trouble:
      return help(
        'Stage public disobedience to influence political issues and gain Juice.',
        skills: const [Skill.art, Skill.streetSmarts],
        risk: 'Police and hostile encounters are possible',
        details:
            'Art rolls and Street Smarts contribute to the group’s impact. '
            'The issue and incident vary; actions can create criminal charges. '
            'Street Smarts helps with police and hostile attention.',
      );
    case ActivityType.graffiti:
      return help(
        'Spread movement tags; skilled artists can create issue-focused murals.',
        skills: const [Skill.art, Skill.streetSmarts],
        requirements: 'Equipped spraypaint',
        cost: 'May buy spraypaint if none is available',
        risk: 'Vandalism charges and arrest are possible',
        details:
            'First checks for spraypaint at the base, then buys it if funds '
            'allow. Art affects mural work; Street Smarts helps avoid police. '
            'Murals can take several days.',
      );
    case ActivityType.hacking:
      return help(
        'Attack networks to influence issues or recover secret documents.',
        skills: const [Skill.computers],
        requirements: 'Computers above 0 and a Hacker Den',
        risk: 'Traceable crimes add personal and safehouse heat',
        unavailableReason: actor == null
            ? null
            : actor.skill(Skill.computers) == 0
            ? 'Requires at least 1 Computers skill.'
            : actor.site?.compound.hackerDen != true
            ? 'Requires a Hacker Den at this location.'
            : null,
        details:
            'Uses the best Computers roll plus one point for each additional '
            'hacker. Successful major hacks can recover documents for a special '
            'edition. A successful hack is not necessarily an untraceable hack.',
      );
    case ActivityType.writeGuardian:
      return help(
        'Publish articles that gradually influence public opinion.',
        skills: const [
          Skill.writing,
          Skill.law,
          Skill.science,
          Skill.religion,
          Skill.business,
        ],
        cost: 'No activity fee',
        details:
            'Uses a Writing roll plus knowledge skills. Writing trains '
            'Writing. Secret documents can support a separate special edition '
            'at month end; regular posts do not require documents.',
      );
    case ActivityType.streamGuardian:
      return help(
        'Broadcast political discussion through the Liberal Guardian.',
        skills: const [
          Skill.persuasion,
          Skill.law,
          Skill.science,
          Skill.religion,
          Skill.business,
        ],
        requirements: 'Streaming studio at the location',
        unavailableReason:
            actor != null && actor.site?.compound.videoRoom != true
            ? 'Requires a streaming studio at this location.'
            : null,
        details:
            'Multiplies the daily influence expression by 4. Uses a '
            'Persuasion roll instead of Writing and trains Persuasion. The '
            'result still depends on the broadcaster’s skills.',
      );
    case ActivityType.donations:
      return help(
        'Ask supporters for money; professional clothing improves donations.',
        skills: const [Skill.persuasion, Skill.streetSmarts],
        cost: 'No activity fee',
        risk: 'Public activity: existing heat or indecent clothing can attract police',
        details:
            'Income uses Persuasion and Street Smarts, public mood, clothing '
            'professionalism and a dice roll. More conservative public moods '
            'increase returns. There is no fixed daily payout.',
      );
    case ActivityType.sellTshirts:
      return help(
        'Make and sell clothing to raise money.',
        skills: const [Skill.tailoring, Skill.business],
        risk: 'Public activity: existing heat or indecent clothing can attract police',
        details:
            'Income uses Tailoring and Business, public mood and a dice '
            'roll. This fundraising task does not craft a selected inventory '
            'item; use Make Clothing for equipment.',
      );
    case ActivityType.sellArt:
      return help(
        'Create and sell art to raise money.',
        skills: const [Skill.art, Skill.business],
        risk: 'Public activity: existing heat or indecent clothing can attract police',
        details:
            'Income uses Art and Business, public mood and a dice roll. '
            'Strong Art can also add background political influence. '
            'More conservative public moods increase returns.',
      );
    case ActivityType.sellMusic:
      return help(
        'Busk for money; equip an instrument for full earnings.',
        skills: const [Skill.music, Skill.streetSmarts],
        risk: 'Public activity: existing heat or indecent clothing can attract police',
        details:
            'The implemented income formula uses Music and Street Smarts '
            '(not Business). Without an equipped instrument, its income '
            'multiplier is one quarter. Public mood and dice rolls also matter.',
      );
    case ActivityType.sellDrugs:
      return help(
        'Sell weed brownies for income affected by drug laws.',
        skills: const [Skill.persuasion, Skill.business, Skill.streetSmarts],
        risk: 'Police searches and drug-distribution charges; heat can expose your base to raids',
        details:
            'Stricter drug laws increase income and expose sellers to '
            'police-search checks. Street Smarts helps avoid being caught. '
            'A police interruption ends the working day without income, '
            'even if the seller escapes. Wanted crew bring heat home; '
            'an exposed base can be raided.',
      );
    case ActivityType.prostitution:
      return help(
        'Earn money from occasional clients; work does not pay every day.',
        skills: const [Skill.seduction, Skill.streetSmarts, Skill.business],
        requirements: 'Age 18 or older',
        risk: 'A failed police-sting check causes immediate arrest',
        unavailableReason: actor != null && actor.age < 18
            ? 'Available only to adults aged 18 or older.'
            : null,
        details:
            'Seduction is weighted twice in the earnings calculation. '
            'Street Smarts is checked during a sting; a failed check has no '
            'fight-or-flight choice.',
      );
    case ActivityType.ccfraud:
      return help(
        'Pool the hackers’ skills to steal money from credit cards.',
        skills: const [Skill.computers],
        requirements: 'Computers above 0 and a Hacker Den',
        risk: 'Larger thefts can create fraud charges and safehouse heat',
        unavailableReason: actor == null
            ? null
            : actor.skill(Skill.computers) == 0
            ? 'Requires at least 1 Computers skill.'
            : actor.site?.compound.hackerDen != true
            ? 'Requires a Hacker Den at this location.'
            : null,
        details:
            'Adds the team’s Computers rolls, then makes repeated payout '
            'checks at rising difficulty. Low rolls can earn nothing. Income '
            'is divided between the hackers; it is not a fixed salary.',
      );
    case ActivityType.recruiting:
      return help(
        'Find prospective members, then talk them into joining.',
        skills: const [Skill.streetSmarts, Skill.persuasion, Skill.seduction],
        timing: 'Choose a profession when the day runs; repeats until changed.',
        details:
            'The day’s activity asks which profession to seek. Street '
            'Smarts helps arrange a meeting; conversation or seduction '
            'determines whether the prospect joins. Existing follow-up meetings '
            'continue separately from the recruiter’s daily order; review '
            'pending meetings in People.',
      );
    case ActivityType.stealCars:
      return help(
        'Attempt to steal a vehicle for the garage.',
        skills: const [Skill.streetSmarts, Skill.security],
        risk: 'Alarms, broken windows and police can interrupt the theft',
        details:
            'Street Smarts helps find cars; Security helps with locks and '
            'hotwiring. Smashing a window uses Strength and attracts attention. '
            'The theft is an interactive scene when the day runs.',
      );
    case ActivityType.makeClothing:
      return help(
        'Craft a chosen disguise and armor for the location’s inventory.',
        skills: const [Skill.tailoring],
        cost: 'Chosen kit’s supplies; available cloth halves the price',
        risk:
            'Poor results can waste supplies or produce lower-quality clothing',
        details:
            'Choose clothing and its supported armor first. Their combined '
            'difficulty is reduced by Tailoring. Money and cloth are consumed '
            'when the task runs, not while browsing the designs.',
      );
    case ActivityType.makeFlag:
      return help(
        'Sew a chosen flag for the location’s inventory.',
        skills: const [Skill.tailoring],
        cost: 'Chosen flag’s supplies; available cloth halves the price',
        risk: 'Failure wastes supplies and leaves recycled cloth',
        details:
            'A successful craft ends this assignment. Flags have their '
            'own issue and secrecy effects when flown; crafting one does not '
            'automatically fly it.',
      );
    case ActivityType.wheelchair:
      return help(
        'Obtain a wheelchair for a crew member who cannot walk.',
        cost: 'No charge in this activity',
        requirements: 'Unable to walk and no wheelchair already owned',
        unavailableReason: actor == null
            ? null
            : actor.canWalk
            ? 'This crew member can already walk.'
            : actor.hasWheelchair
            ? 'This crew member already has a wheelchair.'
            : null,
        details:
            'Completes in one daily activity and returns the person to '
            'Laying Low.',
      );
    case ActivityType.bury:
      return help(
        'Dispose of bodies and recover their equipment into local inventory.',
        skills: const [Skill.streetSmarts],
        requirements: 'A body at this location to enable the assignment',
        risk: 'A failed Street Smarts check can trigger an arrest attempt',
        unavailableReason:
            actor != null &&
                actor.site?.creaturesPresent.any((person) => !person.alive) !=
                    true
            ? 'There are no bodies at this location.'
            : null,
        details:
            'The daily handler can dispose of bodies in the same city. '
            'Completing the work returns the assigned person to Laying Low.',
      );
    case ActivityType.interrogation:
      return help(
        'Tend to a chosen prisoner using the available interaction options.',
        skills: const [
          Skill.psychology,
          Skill.business,
          Skill.religion,
          Skill.science,
        ],
        requirements: 'A living conservative prisoner at this location',
        risk: 'Consequences depend on the chosen treatment',
        unavailableReason:
            actor != null &&
                actor.site?.creaturesPresent.any(
                      (person) =>
                          person.alive &&
                          person.align == politics.Alignment.conservative,
                    ) !=
                    true
            ? 'There is no living conservative prisoner at this location.'
            : null,
        details:
            'Choose the prisoner here; treatment choices appear when prisoner '
            'care is processed. This assignment is different from recruiting '
            'in public. The highest value of twice Psychology plus clothing '
            'base power selects the lead tender. Demanding information uses '
            'Psychology + 2d6 + round(5 × rapport). Other treatment choices '
            'have their own checks and consequences.',
      );
    case ActivityType.study:
      return help(
        'Practice a chosen skill slowly without paying for classes.',
        skills: activity?.skill == null ? const [] : [activity!.skill!],
        cost: 'Free · 5 training XP per day before training modifiers',
        details:
            'Any skill can be selected. Progress stops at the person’s '
            'skill potential; the assignment then returns to Laying Low.',
      );
    case ActivityType.takeClass:
      return help(
        'Pay for faster training in a skill that offers classes.',
        skills: activity?.skill == null ? const [] : [activity!.skill!],
        cost: '\$30 per training day',
        requirements:
            'Taught skill below level 10 and below personal potential',
        details:
            'The daily training amount is 50 minus 5 times current skill '
            'before training modifiers. If funds are below \$30, no class is '
            'paid for. Only skills with available courses appear in the picker.',
      );
    case ActivityType.teachLiberalArts:
    case ActivityType.teachCovert:
    case ActivityType.teachFighting:
      final (subjects, maximumCost) = switch (type) {
        ActivityType.teachLiberalArts => (
          'Law, Persuasion, Writing, Religion, '
              'Business, Science, Psychology, Music and Art',
          20,
        ),
        ActivityType.teachCovert => (
          'Security, Computers, Disguise, Tailoring, '
              'Stealth, Seduction, Driving and Street Smarts',
          60,
        ),
        _ => (
          'Heavy Weapons, Throwing, Martial Arts, Dodge, First Aid '
              'and Firearms',
          100,
        ),
      };
      return help(
        'Train eligible crew in the same city without replacing their tasks.',
        skills: const [Skill.teaching],
        cost: 'Supplies up to \$$maximumCost per day, based on workload',
        requirements: 'Students must be below the teacher’s skill and their own potential',
        details:
            'Teaches $subjects. Topic skill plus three times Teaching '
            'minus student skill sets training, with a per-skill cap and '
            'reduced effectiveness at high workload. Hospitalized crew are '
            'excluded; ordinary prisoners are excluded. With no students '
            'the teacher returns to Laying Low.',
      );
    case ActivityType.clinic:
      return help(
        'Send an injured crew member to a hospital in the same city.',
        requirements: 'Blood below maximum to select this task',
        risk: 'Hospital admission removes the person from their squad',
        unavailableReason: actor != null && actor.blood >= actor.maxBlood
            ? 'This crew member’s blood is already at maximum.'
            : null,
        details:
            'Admission depends on injuries and an available hospital. '
            'Treatment can generate medical bills. Capable medics also provide '
            'routine care at their location without a separate daily task.',
      );
    case ActivityType.augment:
      return help(
        'Undergo augmentation surgery.',
        requirements: 'This task is not offered by the regular assignment menu',
        details:
            'Availability is controlled by the original game; this '
            'description does not enable an unavailable surgery.',
      );
    case ActivityType.sleeperLiberal:
      return help(
        'Influence politics from an undercover job.',
        skills: const [Skill.persuasion],
        details:
            'Profession, relevant skills, attributes and infiltration '
            'determine the issues and influence.',
        timing: 'Sleeper effects are processed at month end.',
      );
    case ActivityType.sleeperSpy:
      return help(
        'Use job access to look for secret information.',
        risk: 'Exposure can reduce infiltration or cost the sleeper their job',
        details:
            'Available information depends on the workplace. '
            'Infiltration affects exposure checks. A successful document leak '
            'also costs 20 infiltration percentage points.',
        timing: 'Sleeper effects are processed at month end.',
      );
    case ActivityType.sleeperEmbezzle:
      return help(
        'Divert money from the sleeper’s employer.',
        risk: 'Exposure reduces infiltration and can lead to arrest',
        details:
            'Income depends on profession and infiltration; it is not '
            'a fixed payout for every sleeper.',
        timing: 'Sleeper effects are processed at month end.',
      );
    case ActivityType.sleeperSteal:
      return help(
        'Take equipment available through the sleeper’s job.',
        risk: 'Exposure reduces infiltration and can lead to arrest',
        details:
            'Workplace determines available equipment. Infiltration '
            'affects exposure checks.',
        timing: 'Sleeper effects are processed at month end.',
      );
    case ActivityType.sleeperRecruit:
      return help(
        'Recruit coworkers while remaining undercover.',
        requirements: 'Remaining subordinate capacity',
        unavailableReason: actor != null && actor.subordinatesLeft <= 0
            ? actor.brainwashed
                  ? 'Enlightened crew cannot recruit.'
                  : 'No subordinate capacity; more Juice can increase it.'
            : null,
        details:
            'Recruitment depends on workplace encounters and remaining '
            'subordinate capacity. '
            'Some political offices have their own appointment rules.',
        timing: 'Sleeper effects are processed at month end.',
      );
    case ActivityType.sleeperJoinLcs:
      return help(
        'Leave the undercover job and return to active service.',
        details:
            'Requires an LCS-controlled safehouse that is not under siege. '
            'On the next day, the crew member returns to an available safehouse '
            'and ends the sleeper role. Without one, the assignment waits.',
      );
    case ActivityType.sleeperConservative:
      return help(
        'The stored activity is Spouting Conservatism.',
        details:
            'This legacy activity has no dedicated effect in the current '
            'monthly sleeper switch; it follows the default infiltration update.',
        timing: 'Sleeper effects are processed at month end.',
      );
  }
}

enum FeatureMechanic { heat, secrecy, squadOrder, juice, infiltration }

String featureMechanics(FeatureMechanic feature) => switch (feature) {
  FeatureMechanic.heat =>
    'Heat is accumulated attention, not a percentage. '
        'Crimes and exposed crew contribute to it. Heat above Secrecy lets '
        'police search for the safehouse; it does not guarantee an immediate raid.',
  FeatureMechanic.secrecy =>
    'Secrecy is this safehouse’s protection against '
        'heat. Location type, a discreet front and a flown flag affect it. '
        'Compare Heat with Secrecy; neither number is a success percentage.',
  FeatureMechanic.squadOrder =>
    'Inspecting changes no orders or time. '
        'Issue a destination order to queue the squad’s visit; advance the day '
        'to travel. Visits replace personal orders; after the visit, crew '
        'return to Lay Low and need new daily orders.',
  FeatureMechanic.juice =>
    'Juice measures personal experience and standing. Rank milestones strengthen '
        'eligible attributes, which can raise training caps and maximum blood; '
        'higher ranks can also expand direct recruitment capacity. Juice helps '
        'with courage checks. Activities award it up to their own limits; '
        'skill XP and money are separate.',
  FeatureMechanic.infiltration =>
    'Infiltration is job access and trust, '
        'displayed as a percentage. It affects undercover exposure and results; '
        'it is not the chance of every order succeeding. Lay Low rebuilds it '
        'at month end; risky work can spend or damage it.',
};

String? activityCategorySummary(String? id) => switch (id) {
  'activism' =>
    'Influence public opinion, raise awareness or recover documents.',
  'legal' => 'Earn money through donations, clothing, art or music.',
  'illegal' => 'Raise money while risking charges, exposure or arrest.',
  'acquisition' => 'Recruit people, obtain transport or make equipment.',
  'education' => 'Practice for free or choose faster paid classes.',
  'teaching' => 'Train eligible crew in the same city; supplies cost money.',
  'medical' => 'Send injured crew to a hospital; routine care is automatic.',
  'sleeper-advocacy' =>
    'Stay undercover, influence politics or expand the network.',
  'sleeper-espionage' =>
    'Use job access for secrets, money or equipment; exposure risks the cover.',
  _ => null,
};

/// Several bulk policies choose a different task for each person. Their
/// authored policy identity must not be mistaken for one concrete activity.
ActivityMechanics? bulkActivityMechanics(String? policy) {
  final type = switch (policy) {
    'communityService' => ActivityType.communityService,
    'liberalActivism' => ActivityType.trouble,
    'liberalGuardian' => ActivityType.writeGuardian,
    'legalFundraising' => ActivityType.donations,
    'sellBrownies' => ActivityType.sellDrugs,
    'prostitution' => ActivityType.prostitution,
    'ccfraud' => ActivityType.ccfraud,
    'stealCars' => ActivityType.stealCars,
    'recruiting' => ActivityType.recruiting,
    _ => null,
  };
  if (type == null) return null;
  final base = activityMechanics(type);
  final (title, summary, details) = switch (policy) {
    'liberalActivism' => (
      'Liberal Activism · best fit per person',
      'Choose an activism task suited to each selected crew member.',
      'Chooses Hacking with Computers above 2 and a Hacker Den; otherwise '
          'Graffiti with Art above 1; otherwise Liberal Disobedience. The bulk '
          'policy does not choose Community Service.',
    ),
    'liberalGuardian' => (
      'Liberal Guardian · best fit per person',
      'Choose writing or streaming for each selected crew member.',
      'Chooses Streaming when a studio exists and Persuasion is at least '
          'Writing; otherwise chooses Writing.',
    ),
    'legalFundraising' => (
      'Legal Fundraising · best fit per person',
      'Choose the legal fundraising task with the best internal estimate for each person.',
      'The original policy compares Donations, Clothing, Art and Music using '
          'that person’s skills and equipment plus public mood. This is not a '
          'guaranteed payout; daily rolls still determine the result.',
    ),
    _ => (base.title, base.summary, base.details),
  };
  return ActivityMechanics(
    type: type,
    policyId: policy,
    title: title,
    summary: summary,
    factors:
        const {
          'liberalActivism',
          'liberalGuardian',
          'legalFundraising',
        }.contains(policy)
        ? ''
        : base.factors,
    cost: base.cost,
    requirements: policy == 'ccfraud'
        ? 'Hacker Den at the location; Computers affects results'
        : base.requirements,
    risk: policy == 'liberalActivism'
        ? 'Street activism risks police; hacking risks traceable crimes and heat'
        : base.risk,
    details: details,
    timing: base.timing,
  );
}

/// Always-visible essentials with optional nonmodal detail. Merely opening it
/// never advances a reader, changes an order or performs a simulated preview.
class ActivityMechanicsPanel extends StatelessWidget {
  const ActivityMechanicsPanel({
    super.key,
    required this.mechanics,
    this.assignment = false,
    this.bulk = false,
  });
  final ActivityMechanics mechanics;
  final bool assignment;
  final bool bulk;

  @override
  Widget build(BuildContext context) => Container(
    key: ValueKey(
      'activity-mechanics:${mechanics.policyId ?? mechanics.type.name}',
    ),
    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
    decoration: BoxDecoration(
      color: JournalPalette.inset,
      border: Border.all(color: JournalPalette.rule),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${bulk
              ? 'Bulk task: '
              : assignment
              ? 'Assigned: '
              : ''}${mechanics.title}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(mechanics.summary, style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 7),
        Wrap(
          spacing: 20,
          runSpacing: 5,
          children: [
            if (mechanics.factors.isNotEmpty) Text('Uses ${mechanics.factors}'),
            if (mechanics.cost.isNotEmpty) Text('Cost: ${mechanics.cost}'),
            if (mechanics.requirements.isNotEmpty)
              Text('Needs: ${mechanics.requirements}'),
          ],
        ),
        if (mechanics.risk.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            mechanics.risk,
            style: const TextStyle(color: JournalPalette.danger),
          ),
        ],
        const SizedBox(height: 6),
        Text(
          bulk
              ? '${mechanics.timing} Selecting a bulk task changes no person. '
                    'Select each person to apply it immediately.'
              : assignment
              ? '${mechanics.timing} Choosing a task updates the assignment now. '
                    'Done closes this screen without advancing time.'
              : mechanics.timing,
          style: const TextStyle(fontSize: 12, color: JournalPalette.muted),
        ),
        if (mechanics.calculation case final calculation?) ...[
          const SizedBox(height: 8),
          ActivityCalculationView(calculation: calculation),
        ],
        if (mechanics.details.isNotEmpty)
          Material(
            type: MaterialType.transparency,
            child: ExpansionTile(
              key: PageStorageKey(
                'activity-mechanics-details:${mechanics.policyId ?? mechanics.type.name}',
              ),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              dense: true,
              visualDensity: VisualDensity.compact,
              title: const Text('How it works', style: TextStyle(fontSize: 12)),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    mechanics.details,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

/// Explains formulas and current values without requesting another decision.
/// Estimates are identified by the source projection, never presented as rolls.
class ActivityCalculationView extends StatelessWidget {
  const ActivityCalculationView({
    super.key,
    required this.calculation,
    this.compact = false,
  });
  final ActivityCalculation calculation;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall
        ?.copyWith(fontSize: compact ? 11 : 13, height: 1.4);
    return Column(
      key: const ValueKey('activity-calculation'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!compact) ...[
          MechanicsTooltip(
            message: calculation.text,
            maxWidth: 520,
            child: Text(
              calculation.result,
              key: const ValueKey('activity-calculation-result'),
              style: style?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 4),
        ],
        Text('Calculation: ${calculation.formula}', style: style),
        for (final input in calculation.inputs) Text(input, style: style),
        for (final note in calculation.qualifiers)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(note, style: style),
          ),
      ],
    );
  }
}
