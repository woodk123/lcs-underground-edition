import 'dart:math' as math;

import 'package:flutter/material.dart' hide View;
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/creature/attributes.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/daily/shopsnstuff.dart' show clinictime;
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/items/ammo.dart';
import 'package:lcs_new_age/items/clothing.dart';
import 'package:lcs_new_age/items/clothing_type.dart';
import 'package:lcs_new_age/items/item.dart';
import 'package:lcs_new_age/items/weapon.dart';
import 'package:lcs_new_age/items/weapon_type.dart';
import 'package:lcs_new_age/location/compound_upgrades.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/politics/laws.dart';
import 'package:lcs_new_age/politics/views.dart';
import 'package:lcs_new_age/vehicles/vehicle_type.dart';

enum DecisionTopic {
  weapons('Weapons'),
  clothing('Clothing & armour'),
  availability('Crew availability'),
  health('Health & treatment'),
  heat('Heat & wanted status'),
  vehicles('Vehicles'),
  recruitment('Recruitment & relationships'),
  upgrades('Safehouse upgrades'),
  ledger('Money & ledger'),
  opinion('Public opinion');

  const DecisionTopic(this.label);
  final String label;
}

String crewAvailabilityHelp(Creature person) => [
  '${person.name}: ${person.isActiveLiberal ? 'active crew' : 'unavailable for ordinary daily work'}.',
  if (!person.alive) 'Deceased characters cannot receive daily work.',
  if (!person.isLiberal) 'Ordinary crew orders require liberal alignment.',
  if (person.sleeperAgent)
    'Undercover agent: uses sleeper orders and monthly processing.',
  if (person.imprisoned)
    'In custody: resolve detention, trial or imprisonment before ordinary work.',
  if (person.hospitalized)
    'Hospitalized: treatment must finish before ordinary work resumes.',
  if (person.hidingDaysLeft > 0)
    'Hiding: ${person.hidingDaysLeft} days remaining.',
  if (person.vacationDaysLeft > 0)
    'Vacation: ${person.vacationDaysLeft} days remaining.',
  if (person.squad?.activity.type != null &&
      person.squad!.activity.type != ActivityType.none)
    'Squad order: ${person.squad!.activity.description}. Replaces individual task: ${person.activity.description} when the squad operation runs. Cancel its departure before assigning personal work; the squad operation takes precedence.',
  if (person.blood < person.maxBlood)
    'Injured does not automatically mean unavailable. Blood loss reduces physical and some mental attributes; equipment and injury checks still matter.',
  'Squad allocation, individual daily work, driving and teaching have their own requirements. Available actions reflect the current task’s requirements.',
].join('\n\n');

String weaponHelp(WeaponType type, {Creature? actor}) {
  final lines = <String>[
    type.description ?? type.name,
    'Size ${type.size}; ${type.suspicious ? 'potentially suspicious' : 'not marked suspicious'}; nominal price \$${type.price}.',
    'Configured capabilities: ${[if (type.canTakeHostages) 'hostage-taking', if (type.threatening) 'threatening', if (type.protectsAgainstKidnapping) 'protection against kidnapping', if (type.canGraffiti) 'graffiti', if (type.autoBreakLock) 'automatic lock forcing', if (type.instrument) 'musical instrument'].join(', ')}. Other scene and character checks can still apply.',
    'Current legal-shop status: ${type.bannedAtGunControl == null || game.laws[Law.gunControl]!.index < type.bannedAtGunControl!.index ? 'not banned by gun-control threshold' : 'banned by gun-control threshold'}. Other shop restrictions still apply.',
    if (type.usesAmmo)
      'Magazine capacity: ${type.ammoCapacity}${type.canKeepOneInTheChamber ? ' + one in the chamber when supported' : ''}. Compatible ammunition: ${type.acceptableAmmo.map((a) => a.name).join(', ')}.'
    else if (type.thrown)
      'Thrown item: supply depends on the carried stack.'
    else
      'Does not use cartridge ammunition.',
  ];
  for (final attack in type.attacks) {
    final skill = actor?.skill(attack.skill);
    final fixed = (attack.damage * .2).round();
    final random = (attack.damage * .8).round();
    lines.add(
      '${attack.ranged ? 'Ranged' : 'Melee'}${attack.thrown ? ', thrown' : ''} attack · ${attack.skill.displayName}${skill == null ? '' : ' $skill'}: accuracy bonus ${attack.accuracyBonus}, initiative ${attack.initiative}, configured attacks ${attack.numberOfAttacks}, successive-attack difficulty ${attack.successiveAttacksDifficulty}.',
    );
    if (attack.usesAmmo) {
      lines.add(
        'Firearm damage comes from the loaded ammunition. The weapon’s fallback damage parameter is not a zero-damage rating. Compatible ammo profiles for this attack:',
      );
      for (final ammo in type.acceptableAmmo.where(
        (a) => a.cartridge == attack.cartridge,
      )) {
        final ammoFixed = (ammo.damage * .2).round();
        final ammoRandom = (ammo.damage * .8).round();
        lines.add(
          '${ammo.name}: damage parameter ${ammo.damage}; initial raw roll $ammoFixed–${ammoFixed + math.max(0, ammoRandom - 1)} per hit; multihit ${ammo.multihit}; recoil ${ammo.recoil}. Target armour, burst hits, position and other combat modifiers change the result.',
        );
      }
    } else if (!attack.socialDamage) {
      lines.add(
        'Base damage parameter ${attack.damage}. Initial raw damage = random integer 0–${math.max(0, random - 1)} + $fixed, giving $fixed–${fixed + math.max(0, random - 1)} before strength, position, hit location, armour and other modifiers. This is not guaranteed final damage.',
      );
    } else {
      lines.add(
        'This attack deals social damage; physical damage comparisons do not describe its conversion effects.',
      );
    }
    lines.add(
      'Strength configuration: minimum ${attack.strengthMin}, maximum ${attack.strengthMax}. Damage flags: ${[if (attack.bruises) 'bruises', if (attack.cuts) 'cuts', if (attack.tears) 'tears', if (attack.burns) 'burns', if (attack.shoots) 'shoots', if (attack.bleeds) 'bleeding', if (attack.stuns) 'stuns'].join(', ')}.',
    );
    if (actor != null && !attack.socialDamage) {
      final armorPenalty = actor.equippedClothing?.armor?.accuracyPenalty ?? 0;
      lines.add(
        'This crew member’s simple attack baseline: d20 + ${actor.skill(attack.skill)} skill + ${attack.accuracyBonus} weapon accuracy − $armorPenalty armour accuracy penalty. Combat can select another attack and apply additional modifiers.',
      );
    }
  }
  lines.add(
    'Reloading and thrown attacks use the weapon’s ammo/throw rules and available supplies. Ranged is an attack category; this catalogue does not specify one universal maximum range in tiles. A carried weapon is concealed when its size fits the outfit’s concealment allowance; uniform permissions can also affect detection.',
  );
  return lines.join('\n\n');
}

String _damageLabel(WeaponType type) => type.attack?.usesAmmo == true
    ? 'ammunition-dependent'
    : '${type.attack?.damage ?? 0}';

String _weaponCondition(Weapon weapon) => weapon.type.usesAmmo
    ? 'Loaded rounds ${weapon.ammo}; ammunition ${weapon.loadedAmmoType?.name ?? 'not recorded; reload with a matching cartridge to set it'}.'
    : weapon.type.thrown
    ? 'Thrown supply stack ${weapon.stackSize}.'
    : 'This weapon does not require loaded ammunition.';

String clothingHelp(ClothingType type, {Creature? actor, Clothing? actual}) {
  final armor = actual?.armor ?? type.intrinsicArmor;
  return [
    if (type.description.isNotEmpty) type.description,
    'Coverage: ${[if (type.coversHead) 'head', if (type.coversBody) 'body', if (type.coversArms) 'arms', if (type.coversLegs) 'legs'].join(', ')}. Face concealed: ${type.concealsFace ? 'yes' : 'no'}.',
    'Configured alarming outfit: ${type.alarming}; police uniform: ${type.police}; culture markers: ${type.culture.join(', ')}. ${actual == null ? '' : 'Current item considered alarming: ${actual.alarming}.'}',
    'Professionalism ${type.professionalism}; concealment allowance ${type.concealWeaponSize}; stealth value ${type.stealthValue}. Professionalism contributes to donation income; it is not a universal disguise bonus.',
    'Uniform-permitted weapons: ${type.weaponsPermitted.map((w) => w.name).join(', ')}. A disguise must suit the site; the same outfit can be appropriate at one site and suspicious at another.',
    'Armour: ${armor?.name ?? 'no intrinsic armour; inspect an upgrade below'}. Body ${actual?.bodyArmor ?? armor?.bodyArmor ?? 0}; head ${actual?.headArmor ?? armor?.headArmor ?? 0}; limb rating ${actual?.maxLimbArmor ?? armor?.limbArmor ?? 0}. Actual damaged limbs can differ.',
    'Dodge penalty ${armor?.dodgePenalty ?? 0}; accuracy penalty ${armor?.accuracyPenalty ?? 0}; fire resistance ${armor?.fireResistant == true ? 'yes' : 'no'}. Armour blocks part of incoming damage and loses protection as it is damaged.',
    'Quality 1 is best. Armour quality multiplier = 1 − (quality − 1) × 0.2, except armour with crafting difficulty 0 uses multiplier 1. Maximum armour ratings are multiplied and rounded. Face-concealing outfits can use limb armour for the head when the upgrade has no separate head rating.',
    'Stealth clothing modifier starts at (stealth value − 2) × 5, rounded. Positive bonuses are multiplied by 0.8 for each quality step above 1, and halved when damaged. Shredded clothing can reduce the total to zero.',
    if (actual != null)
      'Current item: quality ${actual.quality}/${type.qualityLevels}; bloodstained ${actual.bloody}; damaged ${actual.damaged}; body armour ${actual.bodyArmor}/${actual.maxBodyArmor}; head armour ${actual.headArmor}/${actual.maxHeadArmor}.',
    'Crafting: base supply price \$${type.makePrice}; difficulty ${type.makeDifficulty}. With an armour upgrade: difficulty = clothing difficulty + armour difficulty − Tailoring + 4. Available recyclable cloth halves supply cost. Failure can still consume materials and money.',
    if (actor != null)
      'This crew member: Tailoring ${actor.skill(Skill.tailoring)}. Existing outfit: ${actor.equippedClothing?.type.name ?? 'none'}.',
    'Lay Low washes or repairs clothing. Repair and recycling depend on damage, supported quality levels, cloth stock and the selected base; cleanliness, protection and disguise suitability are separate properties.',
  ].join('\n\n');
}

String vehicleHelp(VehicleType type, {Creature? actor}) => [
  type.longName,
  'Vehicle driving bonus ${type.driveBonus}; list price \$${type.price}; sleeper price \$${type.sleeperprice}.',
  'Finding difficulty ${type.difficultyToFind}; stealing Juice ${type.juice}; extra heat ${type.extraHeat}. Alarm configuration: sensing ${type.senseAlarmChance}, touching ${type.touchAlarmChance}. These are separate car-theft checks, not a final theft-success percentage.',
  if (actor != null)
    'Chase driving-score baseline = round(max(0, Driving ${actor.skill(Skill.driving)} + 2 × vehicle bonus ${type.driveBonus}) × blood ${actor.blood}/${actor.maxBlood} × 2) = ${actor.maxBlood > 0 ? (math.max(0, actor.skill(Skill.driving) + type.driveBonus * 2) * actor.blood / actor.maxBlood * 2).round() : 0}. Other chase checks still apply.',
  'Assign a driver explicitly; passengers also need vehicle assignments. Chase driver selection checks assigned, living crew and paralysis. The vehicle data does not expose a per-model seat-capacity statistic, so this guide does not invent one.',
  'Travel to another area requires a car. Intercity travel additionally requires \$100 per squad member. Merely owning a vehicle does not guarantee that the travelling squad has it assigned.',
  'Stolen-vehicle heat belongs to the vehicle and is distinct from a person’s heat. Vehicle type, driver skill, injuries, position and enemy vehicles influence pursuit.',
].join('\n\n');

String ammoHelp(Ammo ammo) => [
  '${ammo.type.name}: ${ammo.stackSize} rounds. Cartridge: ${ammo.type.cartridge}. Box size ${ammo.type.boxSize}; box price \$${ammo.type.boxPrice}.',
  'Damage parameter ${ammo.type.damage}; multihit ${ammo.type.multihit}; recoil ${ammo.type.recoil}. These are attack inputs, not guaranteed total damage.',
  'Compatible weapons: ${weaponTypes.values.where((w) => w.acceptableCartridge.contains(ammo.type.cartridge)).map((w) => w.name).join(', ')}.',
  'Ammunition must match the attack’s cartridge. Magazine capacity and reload behaviour belong to the weapon, not the size of a loose ammo stack.',
].join('\n\n');

String _upgradeEffect(CompoundUpgrade upgrade) => switch (upgrade) {
  CompoundUpgrade.fortify =>
    'Defensive fortifications used during sieges; does not make the base immune to attack.',
  CompoundUpgrade.cameras =>
    'Security cameras support defensive surveillance and siege handling.',
  CompoundUpgrade.boobyTraps =>
    'Traps are used in siege defenses. They do not provide a passive bonus to every field attack.',
  CompoundUpgrade.bollards =>
    'Defensive barriers keep hostile vehicles away during relevant siege events.',
  CompoundUpgrade.generator =>
    'Backup electricity during a siege; requires stockpiled diesel.',
  CompoundUpgrade.solarPanels =>
    'Alternative power infrastructure. Roof installation competes with the anti-aircraft gun.',
  CompoundUpgrade.aaGun =>
    'Anti-aircraft defense for relevant attacks. Roof installation competes with solar panels; legality changes its price.',
  CompoundUpgrade.videoRoom =>
    'Unlocks daily Liberal Guardian streaming at this base.',
  CompoundUpgrade.hackerDen =>
    'Unlocks hacking and credit-card fraud here, subject to the individual task’s skill requirements.',
  CompoundUpgrade.businessFront =>
    'Provides cover: base heat protection becomes 80 before flag modifiers and the 95 cap. Not offered for a discreet base or one already operating a front.',
};

String compoundUpgradeHelp(CompoundUpgrade upgrade, Site? site) => [
  '${upgrade.name}: \$${upgrade.price}. ${_upgradeEffect(upgrade)}',
  'Cash available: \$${game.ledger.funds}. ${game.ledger.funds >= upgrade.price ? 'Price is affordable' : 'Insufficient funds'}.',
  if (site != null)
    '${site.getName()}: ${upgrade.isActiveOn(site) ? 'already installed' : 'not installed'}. Supports full upgrades: ${site.upgradable}.',
  'Other menu prerequisites remain authoritative. Inspecting does not buy or install this upgrade.',
].join('\n\n');

List<String> decisionDetails(
  DecisionTopic topic, {
  Creature? actor,
  Site? site,
}) {
  final base =
      site ?? actor?.base ?? game.activeSquad?.site ?? game.activeSafehouse;
  switch (topic) {
    case DecisionTopic.availability:
      return [
        if (actor != null) crewAvailabilityHelp(actor),
        'A squad holds up to six people. Allocation can reject members assigned elsewhere or unavailable in the current allocation screen. A green portrait status is a broad condition indicator, not a promise that every task is enabled.',
        'Personal tasks execute when you advance the day. Squad visits override personal assignments for that operation. Sleeper work executes in the monthly system. Required skill, target, name or crafting choices must still be completed.',
      ];
    case DecisionTopic.health:
      return [
        if (actor != null)
          '${actor.name}: blood ${actor.blood}/${actor.maxBlood}; health ${actor.health}; permanent health damage ${actor.permanentHealthDamage}. Blood fraction ${actor.maxBlood > 0 ? (100 * actor.blood / actor.maxBlood).toStringAsFixed(1) : '0'}%.',
        if (actor != null)
          'Injury combat modifier ${actor.body.combatRollModifier}. Bleeding stacks ${actor.body.parts.fold<int>(0, (n, part) => n + part.bleeding)}. Body can walk: ${actor.body.canWalk}; wheelchair: ${actor.hasWheelchair}. Bleeding stacks are not a fixed number of blood points lost per turn.',
        if (actor != null)
          'Current treatment severity score: ${clinictime(actor)}. It counts blood-loss thresholds, severe limbs, punctured organs, ribs and untreated spinal injuries. It is used by recovery rules; it is not a guaranteed number of remaining days.',
        'Effective Strength, Agility, Charisma and Intelligence are scaled by blood/max blood and rounded, then the effective attribute is bounded below by 1. Heart and Wisdom do not use this blood scaling. Permanent injuries and activist level also affect attributes.',
        'Checks enabling health penalties subtract floor((max blood − blood) × 2 / max blood) and the injury combat modifier. A dead character cannot pass an ordinary skill or attribute check.',
        'Health derives from level-adjusted Strength plus conviction: Heart for liberals, Wisdom for conservatives, and the lower of the two for moderates, minus permanent health damage, with minimum 1. Blood and health are different values.',
        'The Free Clinic provides basic medical support (First Aid 6 at a non-LCS site) without new treatment charges. University hospitals provide medical support 16. Higher First Aid skill among people present can improve either facility. Admitted patients remain unavailable for ordinary work until healed or discharged after 60 days; discharge does not automatically restore squad membership.',
        'University hospital billing factor by healthcare law: Arch Conservative 300, Conservative 200, moderate 100, Liberal 25, Elite Liberal 0. Blood-restoration bills add restored blood × factor / 5, discarding fractions; individual injury treatments can add other charges. Treatment, stabilization and recovery remain separate checks.',
        'First Aid can stop bleeding during operations and supports treatment at base. Missing parts, paralysis and organ damage are not interchangeable with a low blood bar. Inspect the actual injury list before deciding whether to rest, seek treatment or send the person out.',
      ];
    case DecisionTopic.heat:
      return [
        if (actor != null)
          '${actor.name}: personal heat ${actor.heat}. Recorded crimes: ${actor.wantedForCrimes.entries.where((e) => e.value > 0).map((e) => '${e.key.name} ×${e.value}').join(', ')}.',
        if (base != null)
          '${base.getName()}: base heat ${base.heat}; heat protection ${base.heatProtection}. Exposure above protection: ${math.max(0, base.heat - base.heatProtection)}. This is not a raid probability.',
        'Personal heat measures attention; crime counts record alleged offences; base heat measures location exposure. Vehicle heat is separate again. A person can have recorded crimes while attention is low.',
        'Base heat protection starts at 15; homeless camp 3; tenement 30; apartment 60; upscale apartments, discreet sites and business fronts 80. Flying flags can modify protection. Final protection is clamped to 0–95.',
        'Legal street fundraising can attract police when clothing is indecent or heat exceeds 10 × Street Smarts. The indecency draw is 1 in 2. If it does not trigger, the high-heat draw is 1 in 50. Passing a search gate is not an arrest or conviction; encounters and subsequent choices decide the outcome.',
        'During ordinary safehouse heat processing, eligible liberal occupants contribute their current personal heat, then lose min(max(1, round(heat × 0.04)), heat) personal heat. Hidden and sleeper occupants are excluded from accumulation; siege and other conditions can interrupt normal processing.',
        'Monthly police case strength for detainees = min(law cap, 10 × personal heat), with caps 200/150/100/75/50 from Arch Conservative to Elite Liberal police law. Arch Conservative death-penalty law overrides this to 200.',
        'Laying low, hiding, relocating and reducing public exposure affect different parts of the pursuit system. A successful escape or changing clothing does not erase all recorded crimes.',
      ];
    case DecisionTopic.recruitment:
      return [
        if (actor != null)
          '${actor.name}: Persuasion ${actor.skill(Skill.persuasion)}, Seduction ${actor.skill(Skill.seduction)}, Street Smarts ${actor.skill(Skill.streetSmarts)}, Intelligence ${actor.attribute(Attribute.intelligence)}, Heart ${actor.attribute(Attribute.heart)}, Charisma ${actor.attribute(Attribute.charisma)}.',
        'Recruitment contacts: meetings = min(10, round((Street Smarts + 7) / target-profession difficulty)); difficulty 10 or higher produces no meeting. Finding a contact is separate from converting them.',
        'Recruitment discussion expertise = Business + Science + Religion + Law + Intelligence. Target reluctance begins at 5 + the target’s four corresponding skills + Wisdom + Intelligence. If your expertise exceeds that total, reluctance becomes 0; otherwise subtract your expertise.',
        'The paid recruitment-discussion option costs \$50 and subtracts 5 from discussion difficulty; the target’s activist level − 1 is then added. A Persuasion check decides whether the discussion is insightful; a failed check gets a second Persuasion check. It also requests training XP. Other choices and checks decide whether the target joins; there is no universal recruitment probability.',
        if (actor != null)
          for (final meeting in game.recruitmentSessions.where(
            (r) => r.recruiter.id == actor.id,
          ))
            recruitmentComparison(actor, meeting.recruit),
        if (actor != null)
          for (final partner in actor.relationships)
            'Partner ${partner.name}: shared skill interests ${Skill.values.where((s) => actor.skill(s) >= 1 && partner.skill(s) >= 1).length}. Basic fixed Wisdom-resistance baseline ${partner.attribute(Attribute.wisdom) + 2 + partner.level}; before date-specific modifiers.',
        if (actor != null)
          'Command capacity: ${actor.maxSubordinates}; remaining subordinate slots ${actor.subordinatesLeft}. Relationships: ${actor.relationships.length}/${actor.maxRelationships}; remaining relationship slots ${actor.relationshipsLeft}.',
        'Relationship capacity = max(trunc((Heart − 4)/2), trunc((Charisma − 4)/2), round(Seduction/2 + 1)). This is independent of the six-person squad limit and subordinate command capacity.',
        'A basic date compares a Seduction roll with the partner’s fixed Wisdom attribute roll plus their activist level; shared interests add 3 each to your roll. Paid dates and location/health requirements modify the route. A relationship does not automatically mean ordinary squad availability.',
      ];
    case DecisionTopic.upgrades:
      return [
        if (base != null)
          '${base.getName()}: ${base.upgradable ? 'supports compound upgrades' : 'does not support the full compound upgrade menu'}; available funds \$${game.ledger.funds}; rent \$${base.rent}.',
        for (final upgrade in CompoundUpgrade.values)
          '${upgrade.name}: \$${upgrade.price}${base == null
              ? ''
              : upgrade.isActiveOn(base)
              ? ' · Installed'
              : game.ledger.funds < upgrade.price
              ? ' · Insufficient funds'
              : ' · Affordable; other prerequisites still apply'}. ${_upgradeEffect(upgrade)}',
        'Solar panels and the AA gun require neither roof option already installed. A business front requires a suitable non-discreet location without an existing front. Existing upgrades are not offered for purchase again.',
        if (base != null)
          'Stored rations ${base.compound.rations}; approximate food days ${base.foodDaysLeft}; diesel days ${base.compound.diesel}. Food days = round(rations / max(number eating, 1)); this is a stock estimate, not a permanent capacity upgrade.',
        'Ration purchase: \$150 for 20 daily rations. Generator diesel purchase: five days for \$300/500/750/1000/2000 as pollution law moves from Arch Conservative to Elite Liberal. Generator fuel is a supply requirement; ordinary upgrade purchase prices are one-off expenses.',
        'Solar-panel price is law-dependent: \$60000/40000/30000/20000/10000. AA gun: \$35000 with Arch Conservative gun control, otherwise \$200000 to install and conceal it.',
      ];
    case DecisionTopic.ledger:
      return [
        'Cash on hand: \$${game.ledger.funds}; cumulative recorded income \$${game.ledger.totalIncome}; cumulative recorded expenses \$${game.ledger.totalExpense}. Cash changes by income minus expenses. Starting/imported cash is not automatically lifetime income.',
        'Month income entries: ${game.ledger.income.entries.where((e) => e.value != 0).map((e) => '${e.key.name} \$${e.value}').join('; ')}.',
        'Month expenses: ${game.ledger.expense.entries.where((e) => e.value != 0).map((e) => '${e.key.name} \$${e.value}').join('; ')}.',
        'Daily income entries: ${game.ledger.dailyIncome.entries.where((e) => e.value != 0).map((e) => '${e.key.name} \$${e.value}').join('; ')}.',
        'Daily expenses: ${game.ledger.dailyExpense.entries.where((e) => e.value != 0).map((e) => '${e.key.name} \$${e.value}').join('; ')}.',
        for (final person in game.pool.where((p) => p.isLiberal && p.alive))
          '${person.name}: recorded income \$${person.income}; assigned ${person.activity.description}. This is a recorded result, not a forecast for the next day.',
        'Month totals reset during monthly reporting; daily totals reset daily; lifetime totals remain separate. Asset liquidation values are not spendable cash until a sale happens.',
        'Recurring costs include applicable rent, paid classes and patient care. Equipment, upgrades and travel are charged by their own actions. A required monthly report must be completed before normal planning resumes.',
        'Order previews use a fixed dice baseline (usually 7 for 2d6). Actual income can differ because of random rolls, law or mood multipliers, interruptions, eligibility, rounding and squad-operation overrides. The ledger keeps category totals; it does not contain a complete historical per-person transaction trail.',
      ];
    case DecisionTopic.opinion:
      return [
        'Movement awareness ${game.politics.publicOpinion[View.lcsKnown]!.toStringAsFixed(2)}%; popularity among those aware ${game.politics.publicOpinion[View.lcsLiked]!.toStringAsFixed(2)}%; effective LCS approval ${game.politics.lcsApproval().toStringAsFixed(2)}%.',
        'Effective LCS approval = awareness × LCS popularity / 100. Issue support is a different measure: liberal support for that particular subject. Interest measures attention to an issue, not agreement.',
        'Public mood: ${game.politics.publicMood().toStringAsFixed(2)}. Fundraising uses mood-dependent multipliers; it is not identical to approval of your movement.',
        for (final view in View.values.where(
          (v) => v.index <= View.retirement.index,
        ))
          '${view.label}: support ${game.politics.publicOpinion[view]!.toStringAsFixed(2)}%; interest ${game.politics.publicInterest[view]}; background influence ${game.politics.backgroundInfluence[view]}.',
        'Articles and broadcasts add background influence; power is not a direct percentage-point increase in public opinion. Public operations, activism, news and sleeper actions can contribute through their own issue-specific paths.',
        'For an ordinary opinion change, power is scaled by min(2, 1 + existing interest / 16), rounded, then capped to −75…75. Positive power P changes support v to v + (100 − v) × P/100; negative P changes it to v + v × P/100. The result is bounded to 0–100. Movement awareness/popularity and changes colored by movement approval have extra preprocessing.',
        'Law support is the mean of its linked opinion values; law interest is the mean of linked attention values with the fraction discarded. Multiple laws can share the same opinion. Congressional priorities and politician voting depend on these values; opinion does not directly overwrite a law.',
        'The Agenda law guides explain current proposal pressure, priorities, voting, court bias and victory requirements. Improving awareness without maintaining popularity can leave effective movement approval low.',
      ];
    case DecisionTopic.weapons:
      return [
        'Inspect a weapon below to see its actual attack definitions and compare it with the selected character’s equipped weapon. Catalogue entries are reference data; selection here never equips or purchases an item.',
      ];
    case DecisionTopic.clothing:
      return [
        'Inspect an outfit below to see coverage, stealth, professionalism and armour choices. Item condition and installed armour are shown separately from the base clothing definition. Selecting a comparison never changes the worn item.',
      ];
    case DecisionTopic.vehicles:
      return [
        'Inspect a vehicle type below for chase modifiers and costs. Actual ownership, vehicle heat, assignments and location are shown separately.',
        for (final vehicle in game.vehiclePool)
          '${vehicle.fullName()}: heat ${vehicle.heat}; location ${vehicle.location?.getName() ?? 'not recorded'}; assigned crew ${game.pool.where((p) => p.carId == vehicle.id || p.preferredCarId == vehicle.id).map((p) => '${p.name}${p.isDriver ? ' (driver)' : ''}').join(', ')}.',
      ];
  }
}

String recruitmentComparison(Creature actor, Creature target) {
  int expertise(Creature person) =>
      [Skill.business, Skill.science, Skill.religion, Skill.law].fold<int>(
        person.attribute(Attribute.intelligence),
        (sum, skill) => sum + person.skill(skill),
      );
  final difficulty =
      math.max(
        0,
        5 +
            expertise(target) +
            target.attribute(Attribute.wisdom) -
            expertise(actor),
      ) +
      target.level -
      1;
  double chance(int difficulty) {
    if (!actor.alive) return 0;
    var wins = 0;
    for (var a = 1; a <= 6; a++) {
      for (var b = 1; b <= 6; b++) {
        if (a + b + actor.skill(Skill.persuasion) >= difficulty) wins++;
      }
    }
    return wins * 100 / 36;
  }

  return 'Contact ${target.name}: expertise ${expertise(actor)} against target knowledge/conviction ${5 + expertise(target) + target.attribute(Attribute.wisdom)}. Free discussion difficulty $difficulty; first-check pass chance ${chance(difficulty).toStringAsFixed(2)}%. Paid discussion difficulty ${difficulty - 5}; first-check pass chance ${chance(difficulty - 5).toStringAsFixed(2)}%, at \$50. These are exact ordinary 2d6 Persuasion-check probabilities, not the chance of joining the movement.';
}

Future<void> showDecisionGuide(
  BuildContext context,
  DecisionTopic topic, {
  Creature? actor,
  Site? site,
  String? itemType,
  Item? item,
}) => showDialog<void>(
  context: context,
  builder: (_) => _DecisionGuide(
    initialTopic: topic,
    actor: actor,
    site: site,
    itemType: itemType,
    item: item,
  ),
);

class DecisionGuideButton extends StatelessWidget {
  const DecisionGuideButton({
    super.key,
    required this.topic,
    this.actor,
    this.site,
    this.itemType,
    this.item,
    this.compact = false,
    this.label,
  });
  final DecisionTopic topic;
  final Creature? actor;
  final Site? site;
  final String? itemType;
  final Item? item;
  final bool compact;
  final String? label;
  @override
  Widget build(BuildContext context) => compact
      ? IconButton(
          tooltip: label ?? '${topic.label} guide',
          icon: const Icon(Icons.info_outline, size: 18),
          onPressed: () => showDecisionGuide(
            context,
            topic,
            actor: actor,
            site: site,
            itemType: itemType,
            item: item,
          ),
        )
      : TextButton.icon(
          icon: const Icon(Icons.info_outline, size: 17),
          label: Text('${topic.label} guide'),
          onPressed: () => showDecisionGuide(
            context,
            topic,
            actor: actor,
            site: site,
            itemType: itemType,
            item: item,
          ),
        );
}

class _DecisionGuide extends StatefulWidget {
  const _DecisionGuide({
    required this.initialTopic,
    this.actor,
    this.site,
    this.itemType,
    this.item,
  });
  final DecisionTopic initialTopic;
  final Creature? actor;
  final Site? site;
  final String? itemType;
  final Item? item;
  @override
  State<_DecisionGuide> createState() => _DecisionGuideState();
}

class _DecisionGuideState extends State<_DecisionGuide> {
  late DecisionTopic _topic = widget.initialTopic;
  late int? _actorId =
      widget.actor?.id ??
      game.pool.where((p) => p.isLiberal && p.alive).firstOrNull?.id;
  late String? _weaponId = weaponTypes.containsKey(widget.itemType)
      ? widget.itemType
      : widget.actor?.equippedWeapon?.type.idName;
  late String? _clothingId = clothingTypes.containsKey(widget.itemType)
      ? widget.itemType
      : widget.actor?.equippedClothing?.type.idName;
  late String? _vehicleId = vehicleTypes.containsKey(widget.itemType)
      ? widget.itemType
      : widget.actor?.car?.typeName;

  Widget _section(String title, String text) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Text(
          title,
          style: JournalPalette.heading.copyWith(fontSize: 16),
        ),
      ),
      Text(text, style: JournalPalette.body),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final actor = game.pool.where((p) => p.id == _actorId).firstOrNull;
    final people = game.pool
        .where((p) => p.isLiberal && p.alive || p.id == _actorId)
        .toList();
    final weapon = weaponTypes[_weaponId];
    final clothing = clothingTypes[_clothingId];
    final vehicle = vehicleTypes[_vehicleId];
    final selectedItem = widget.item?.typeName == _weaponId
        ? widget.item
        : null;
    final selectedClothing =
        widget.item is Clothing && widget.item?.typeName == _clothingId
        ? widget.item! as Clothing
        : actor?.equippedClothing?.type.idName == _clothingId
        ? actor?.equippedClothing
        : null;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 800),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 6, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_topic.label} guide',
                      style: JournalPalette.heading,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close decision guide',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButton<DecisionTopic>(
                      isExpanded: true,
                      value: _topic,
                      items: [
                        for (final topic in DecisionTopic.values)
                          DropdownMenuItem(
                            value: topic,
                            child: Text(topic.label),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _topic = value);
                      },
                    ),
                    if (people.isNotEmpty)
                      DropdownButton<int>(
                        isExpanded: true,
                        value: _actorId,
                        hint: const Text('Inspect character'),
                        items: [
                          for (final person in people)
                            DropdownMenuItem(
                              value: person.id,
                              child: Text(
                                'Compare for ${person.name}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) => setState(() => _actorId = value),
                      ),
                    for (final text in decisionDetails(
                      _topic,
                      actor: actor,
                      site: widget.site,
                    ))
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(text, style: JournalPalette.body),
                      ),
                    if (_topic == DecisionTopic.weapons) ...[
                      if (widget.item is Ammo)
                        _section(
                          'Selected ammunition',
                          ammoHelp(widget.item! as Ammo),
                        ),
                      _catalogue(
                        weaponTypes.map((id, type) => MapEntry(id, type.name)),
                        _weaponId,
                        (id) => setState(() => _weaponId = id),
                      ),
                      if (weapon != null) ...[
                        if (actor?.equippedWeapon != null)
                          _section(
                            'Quick comparison',
                            '${actor!.equippedWeapon!.type.name} → ${weapon.name}\nMagazine: ${actor.equippedWeapon!.type.usesAmmo ? actor.equippedWeapon!.type.ammoCapacity : 'not applicable'} → ${weapon.usesAmmo ? weapon.ammoCapacity : 'not applicable'}. Size: ${actor.equippedWeapon!.type.size} → ${weapon.size}.\nPrimary attack damage parameter: ${_damageLabel(actor.equippedWeapon!.type)} → ${_damageLabel(weapon)}; accuracy bonus ${actor.equippedWeapon!.type.attack?.accuracyBonus ?? 0} → ${weapon.attack?.accuracyBonus ?? 0}.\nPrimary skill: ${actor.equippedWeapon!.type.attack?.skill.displayName ?? 'none'} → ${weapon.attack?.skill.displayName ?? 'none'}. Other attacks and social-damage profiles must be compared below.',
                          ),
                        _section(
                          'Selected weapon',
                          weaponHelp(weapon, actor: actor),
                        ),
                        if (selectedItem is Weapon)
                          _section(
                            'Selected item ammunition',
                            '${_weaponCondition(selectedItem)} Stack quantity ${selectedItem.stackSize}.',
                          ),
                        if (actor?.equippedWeapon != null) ...[
                          _section(
                            'Currently equipped',
                            weaponHelp(
                              actor!.equippedWeapon!.type,
                              actor: actor,
                            ),
                          ),
                          _section(
                            'Comparison',
                            'Magazine capacity change: ${weapon.usesAmmo && actor.equippedWeapon!.type.usesAmmo ? weapon.ammoCapacity - actor.equippedWeapon!.type.ammoCapacity : 'not applicable'}. Weapon size change: ${weapon.size - actor.equippedWeapon!.type.size}. Base price change: \$${weapon.price - actor.equippedWeapon!.type.price}. Attack definitions above show skill, accuracy and damage differences; these are not a universal upgrade score.',
                          ),
                          _section(
                            'Current weapon condition',
                            '${_weaponCondition(actor.equippedWeapon!)} Spare ammo/equipment: ${actor.spareAmmo?.type.name ?? 'none'}. Outfit concealment allowance ${actor.equippedClothing?.type.concealWeaponSize ?? 0}.',
                          ),
                        ],
                      ],
                    ],
                    if (_topic == DecisionTopic.clothing) ...[
                      _catalogue(
                        clothingTypes.map(
                          (id, type) => MapEntry(id, type.name),
                        ),
                        _clothingId,
                        (id) => setState(() => _clothingId = id),
                      ),
                      if (clothing != null) ...[
                        if (actor?.equippedClothing != null)
                          _section(
                            'Quick comparison',
                            '${actor!.equippedClothing!.type.name} → ${clothing.name}\nProfessionalism: ${actor.equippedClothing!.type.professionalism} → ${clothing.professionalism}. Stealth value: ${actor.equippedClothing!.type.stealthValue} → ${clothing.stealthValue}. Concealment allowance: ${actor.equippedClothing!.type.concealWeaponSize} → ${clothing.concealWeaponSize}.\nArmour and damage are separate from the base outfit; inspect the actual item and armour options below.',
                          ),
                        _section(
                          'Selected outfit',
                          clothingHelp(
                            clothing,
                            actor: actor,
                            actual: selectedClothing,
                          ),
                        ),
                        for (final armor in clothing.allowedArmor)
                          ExpansionTile(
                            key: PageStorageKey(
                              'clothing-armor:${armor.idName}',
                            ),
                            title: Text(
                              '${armor.name} · body ${armor.bodyArmor}',
                            ),
                            children: [
                              Text(
                                '${armor.description}\nHead ${armor.headArmor}; limbs ${armor.limbArmor}; Dodge penalty ${armor.dodgePenalty}; accuracy penalty ${armor.accuracyPenalty}; visible ${armor.visible}; fire resistant ${armor.fireResistant}. Extra crafting cost \$${armor.makePrice}; difficulty adjustment ${armor.makeDifficulty}.',
                                style: JournalPalette.body,
                              ),
                            ],
                          ),
                        if (actor?.equippedClothing != null)
                          _section(
                            'Comparison to worn outfit',
                            'Professionalism change: ${clothing.professionalism - actor!.equippedClothing!.type.professionalism}. Stealth-value change: ${clothing.stealthValue - actor.equippedClothing!.type.stealthValue}. Concealment allowance change: ${clothing.concealWeaponSize - actor.equippedClothing!.type.concealWeaponSize}. Installed armour and damage must be compared separately. ${selectedClothing == null ? '' : 'Actual item body-armour change: ${selectedClothing.bodyArmor - actor.equippedClothing!.bodyArmor}; head-armour change: ${selectedClothing.headArmor - actor.equippedClothing!.headArmor}; Dodge-penalty change: ${(selectedClothing.armor?.dodgePenalty ?? 0) - (actor.equippedClothing!.armor?.dodgePenalty ?? 0)}.'}',
                          ),
                      ],
                    ],
                    if (_topic == DecisionTopic.vehicles) ...[
                      _catalogue(
                        vehicleTypes.map(
                          (id, type) => MapEntry(id, type.longName),
                        ),
                        _vehicleId,
                        (id) => setState(() => _vehicleId = id),
                      ),
                      if (vehicle != null)
                        _section(
                          'Vehicle specification',
                          vehicleHelp(vehicle, actor: actor),
                        ),
                    ],
                    const SizedBox(height: 16),
                    const Text(
                      'Inspection and comparisons are read-only. They do not equip items, assign work, buy upgrades, advance time or roll outcomes.',
                      style: JournalPalette.small,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _catalogue(
    Map<String, String> names,
    String? selected,
    ValueChanged<String?> change,
  ) => DropdownButton<String>(
    isExpanded: true,
    value: selected,
    hint: const Text('Choose catalogue entry to inspect'),
    items: [
      for (final entry in names.entries)
        DropdownMenuItem(
          value: entry.key,
          child: Text(
            entry.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
    ],
    onChanged: change,
  );
}
