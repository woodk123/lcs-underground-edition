import 'package:flutter/material.dart';
import 'package:lcs_new_age/engine/agenda_context.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/politics/alignment.dart' show DeepAlignment;
import 'package:lcs_new_age/politics/laws.dart';

/// Read-only explanations of political rules. Never call the simulation's
/// randomized election, sentencing, encounter or fundraising handlers here.
String lawEffectSummary(Law law) => switch (law) {
  Law.abortion ||
  Law.civilRights => 'Political and story effects. No direct daily bonus.',
  Law.housing => 'Political and story effects. Does not change rent.',
  Law.retirement => 'Political and story effects. Does not pay pensions.',
  Law.privacy =>
    'Combined effects: helps trigger authoritarian regimes with other laws.',
  Law.military =>
    'Combined effects: helps trigger the 1984 regime with other laws.',
  Law.corporate || Law.taxes =>
    'Combined effects: helps trigger corporate feudalism with other laws.',
  Law.nuclearPower || Law.pollution =>
    'World effects: enables mutants; both laws together make them common.',
  Law.animalRights =>
    'World effects: changes how animals are treated and some encounters.',
  Law.policeReform =>
    'Direct effects: police cases and encounters. Also enables law combinations.',
  Law.deathPenalty =>
    'Direct effects: execution risk, police cases and detained immigrants.',
  Law.labor =>
    'Direct effects: worker encounters. Also enables corporate feudalism.',
  Law.lgbtRights ||
  Law.genderEquality => 'Direct effects: changes character generation.',
  Law.freeSpeech =>
    'Direct effects: speech-offence heat. Also enables repression with other laws.',
  Law.flagBurning =>
    'Direct effects: flag-burning legality, heat and sentences.',
  Law.gunControl =>
    'Direct effects: weapon sales, prices, armament and security checks.',
  Law.drugs =>
    'Direct effects: brownie income, police searches and drug sentences.',
  Law.immigration =>
    'Direct effects: deportation or execution after illegal-entry detention.',
  Law.elections =>
    'Political mechanics: changes election bias and incumbent advantages.',
  Law.torture => 'Event effects: changes which protest incidents can occur.',
  Law.prisons =>
    'Event effects: changes prison scenes. Also enables the 1984 regime.',
  Law.healthcare => 'Direct effects: changes hospital bills.',
};

const _lawVictorySummary =
    'Every law must reach Elite Liberal for normal victory.';

String lawGameplayEffects(Law law) => switch (law) {
  Law.abortion =>
    'A political objective linked to Women’s Rights opinion. Changes abortion-related news and political arguments; it does not grant a separate daily cash or combat bonus.',
  Law.animalRights =>
    'Changes the treatment and presentation of laboratory subjects and animal-related stories. At Elite Liberal, animals are treated as people by the simulation. Also changes a special dating outcome at Arch Conservative.',
  Law.policeReform =>
    'Changes police strength when building racketeering cases against detained crew, police encounters and behaviour in chases. Combines with other laws to enable death squads and authoritarian regimes.',
  Law.privacy =>
    'Participates in the Fahrenheit 451 and 1984 regime combinations, affecting repression and the identities of intelligence and military facilities. Linked to Intelligence opinion.',
  Law.deathPenalty =>
    'Changes capital-punishment rolls for eligible non-lenient cases. Arch Conservative can expose any case to execution; otherwise qualifying crimes include murder, treason and flag burning when flag laws are Arch Conservative. Also affects police charging pressure and immigration outcomes.',
  Law.nuclearPower =>
    'Combines with Pollution to enable mutant encounters and recruitment. Changes nuclear-plant presentation and interactions at extreme law levels.',
  Law.pollution =>
    'Combines with Nuclear Power to control whether mutants can appear, whether they are common, and how difficult they are to find for recruitment.',
  Law.labor =>
    'Changes industrial encounters: child labourers, non-union workers and union workers have different weights at each law level. Also participates in corporate feudalism.',
  Law.lgbtRights =>
    'Changes gates used when generating gender identity and nonbinary characters, alongside profession and alignment. The gates below are intermediate generation checks, not final population percentages.',
  Law.corporate =>
    'Combines with Tax Structure and Labor Rights to enable corporate feudalism. Changes corporate-related news, political arguments and CEO-residence presentation.',
  Law.freeSpeech =>
    'Changes the heat attached to unlawful-speech offences and participates in the Fahrenheit 451 regime. Linked to Free Speech opinion, which also feeds flag-burning law support.',
  Law.flagBurning =>
    'Controls when burning national flags is criminal, offence heat and sentencing. At Arch Conservative it can be a qualifying capital offence. Liberal and Elite Liberal levels permit national-flag burning.',
  Law.gunControl =>
    'Controls legal shop availability for weapons and compatible ammunition, black-market weapon price scaling, civilian armament and some weapon loot choices. It also changes how security treats visible weapons.',
  Law.taxes =>
    'A political objective linked to Taxes opinion. Combines with Corporate Law and Labor Rights to enable corporate feudalism and changes CEO-residence presentation. This is not a direct percentage tax deducted from every squad donation.',
  Law.genderEquality =>
    'Changes the gender-conformity gate used when generating profession-biased characters. Also changes related news, political arguments and certain site interactions.',
  Law.civilRights =>
    'A political objective linked to Civil Rights opinion. Shapes political arguments and news. Its Agenda level is not a separate daily income or combat multiplier.',
  Law.drugs =>
    'Changes weed-brownie income, the police-search gate and sentencing for drug distribution. Conservative prohibition increases returns but also exposes the seller to searches and harsher sentences.',
  Law.immigration =>
    'Affects detained crew wanted for illegal entry. Below Elite Liberal, detention can lead to deportation; Arch Conservative immigration combined with Arch Conservative death-penalty law changes this to execution.',
  Law.elections =>
    'Changes congressional election bias and the incumbent automatic-win gate. Term limits disable the automatic-win gate and the seat-incumbency bias. These are components of an election, not the final chance of winning a seat.',
  Law.military =>
    'A political objective linked to Military opinion. With Arch Conservative Prison Reform, Privacy Rights and Police Regulation, it activates the 1984 regime and changes military/intelligence-site presentation. It is not a flat squad attack or defense bonus.',
  Law.torture =>
    'Linked to Intelligence and Police Behavior opinion. Elite Liberal torture law removes one torture-related protest incident from the daily disobedience pool; other levels retain it.',
  Law.prisons =>
    'Changes eligible monthly prison scenes: Arch Conservative uses labor camps, Elite Liberal uses rehabilitation, and intermediate levels use ordinary prison scenes. Also participates in the 1984 regime and changes prisoner encounters under that regime.',
  Law.housing =>
    'A political objective linked to Housing opinion. Changes housing-related news and arguments. The law level is not directly multiplied into the crew’s rent payment.',
  Law.healthcare =>
    'Changes the billing factor for hospital recovery. Actual bills depend on treatment performed, blood restored and injuries; the law is not a fixed daily admission price.',
  Law.retirement =>
    'A political objective linked to Retirement opinion. Changes retirement-related news and political arguments; it does not pay a recurring pension directly into the LCS ledger.',
};

List<String> lawLevelCalculations(Law law, DeepAlignment level) {
  final i = level.index;
  return switch (law) {
    Law.drugs => [
      'Brownie income multiplier: ×${[4.0, 2.0, 1.0, .5, .25][i]}. Income = round((round((Persuasion + Business + Street Smarts) / 3) + 2d6) × multiplier × 3).',
      if (i <= 2)
        'Police-search gate: 1 in ${15 * (i + 1)} (${(100 / (15 * (i + 1))).toStringAsFixed(2)}%). A failed Street Smarts + 2d6 check against difficulty 9 then triggers the arrest encounter.'
      else
        'This brownie-selling police-search gate is disabled.',
      'Drug-distribution sentence per count: ${['3–362', '3–122', '3–14', '0', '0'][i]} months, before leniency and other charges. This component applies only when the case is not sentenced to death.',
    ],
    Law.healthcare => [
      'Hospital billing factor: ${[300, 200, 100, 25, 0][i]}.',
      'Blood-restoration charge = restored blood × factor / 5, discarding the fraction. Example: 10 blood restored costs \$${10 * [300, 200, 100, 25, 0][i] ~/ 5}.',
      'Stabilizing a torn-off limb can add factor × 5 = \$${[300, 200, 100, 25, 0][i] * 5}. Other treatment branches can also add bills.',
    ],
    Law.deathPenalty => [
      'Eligible non-lenient case: death-sentence roll ${['100%', '66.67%', '50%', '20%', '0%'][i]}. These are conditional rolls after conviction and eligibility, not the overall chance that an arrested person is executed.',
      if (i == 0)
        'Arch Conservative also overrides the monthly police case-strength calculation to 200.',
    ],
    Law.policeReform => [
      'Monthly police case-strength cap: ${[200, 150, 100, 75, 50][i]}. Case strength = min(cap, 10 × detainee heat). Arch Conservative death-penalty law overrides this to 200.',
    ],
    Law.gunControl => [
      'Law restriction index: $i (Arch Conservative = 0, Elite Liberal = 4). A legal shop hides a weapon when its ban threshold ≤ $i.',
      'Legal ammunition is available when at least one weapon accepting it has a ban threshold > $i.',
      'At shops that increase prices with illegality: weapon price = base price × max(1, $i − weapon ban threshold + 2). The threshold defaults to 3 when missing in this price calculation. Undercover pricing is calculated separately.',
    ],
    Law.elections => [
      'Election bias = 4 − index = ${4 - i}. The House/Senate vote threshold includes 4 × election bias = ${4 * (4 - i)}.',
      'Incumbent automatic-win gate: ${['66.67%', '50%', '33.33%', '20%', '12.5%'][i]}, unless term limits disable it. Other election rolls still matter when this gate fails.',
      'Seat bias without term limits = (2 − incumbent alignment index) × 20. With term limits, seat bias = 0.',
    ],
    Law.genderEquality => [
      'Profession-conformity gate: ${['100%', '95%', '80%', '50%', '0%'][i]}. This is used for male-/female-biased professions, not a universal gender distribution.',
    ],
    Law.lgbtRights => [
      'Generation gate permitting trans identities: ${['0%', '5%', '20%', '50%', '100%'][i]}. Liberal characters also bypass this gate.',
      'When the generator selects an unrestricted gender and the character is liberal or passes that gate: nonbinary check = 1 in ${[20, 20, 16, 12, 8][i]} (${(100 / [20, 20, 16, 12, 8][i]).toStringAsFixed(2)}%). This is not the final chance for every person.',
    ],
    Law.labor => [
      'Industrial worker weights: ${['Child Laborer 160', 'Non-union Worker 160', 'Non-union Worker 80', 'Non-union Worker 50; Union Worker 110', 'Union Worker 160'][i]}. Other staff and security add to the total; a person’s share = their weight / all applicable weights.',
      'Union-worker flag: ${i >= 2 ? 'enabled' : 'disabled'}. Non-union-worker flag: ${i < 4 ? 'enabled' : 'disabled'}. These flags also affect encounter pools at other sites.',
    ],
    Law.flagBurning => [
      'National-flag offence heat: ${[5, 1, 0, 0, 0][i]}. Heat is not a sentence length.',
      'Non-capital sentence per count: ${['120–360 months on the time branch, otherwise a life sentence; the branch check is 50/50', '36 months', '1 month', 'No flag-burning sentence component', 'No flag-burning sentence component'][i]}. Leniency can modify the sentence.',
    ],
    Law.freeSpeech => [
      'Unlawful-speech offence heat: ${[5, 1, 0, 0, 0][i]}. Existing unlawful-speech convictions add a separate 4–6 month sentence component per count before leniency.',
    ],
    Law.prisons => [
      'Eligible monthly prison-scene gate: 1 in 5 (20%), provided the person is not on death row and their remaining sentence is not 1. Scene: ${i == 0
          ? 'labor camp'
          : i == 4
          ? 'rehabilitation'
          : 'ordinary prison scene'}.',
    ],
    _ => [
      lawEffectSummary(law),
      'No separate per-level formula to show here. See effects and combinations below.',
    ],
  };
}

const _lawCombinations = <String, (List<Law>, DeepAlignment)>{
  'Death squads': (
    [Law.policeReform, Law.deathPenalty],
    DeepAlignment.archConservative,
  ),
  'Fahrenheit 451 repression': (
    [Law.freeSpeech, Law.privacy, Law.policeReform],
    DeepAlignment.archConservative,
  ),
  '1984 regime': (
    [Law.prisons, Law.privacy, Law.military, Law.policeReform],
    DeepAlignment.archConservative,
  ),
  'Corporate feudalism': (
    [Law.corporate, Law.taxes, Law.labor],
    DeepAlignment.archConservative,
  ),
  'Mutants common': (
    [Law.pollution, Law.nuclearPower],
    DeepAlignment.archConservative,
  ),
  'Execution after immigration detention': (
    [Law.immigration, Law.deathPenalty],
    DeepAlignment.archConservative,
  ),
};

List<String> lawCombinationDetails(Law law) => [
  for (final entry in _lawCombinations.entries)
    if (entry.value.$1.contains(law))
      '${entry.key}: ${entry.value.$1.every((l) => game.laws[l] == entry.value.$2) ? 'conditions met' : 'conditions not met'}. Requires every listed law at ${entry.value.$2.label}: ${entry.value.$1.map((l) => '${l.label} (${game.laws[l]?.label ?? 'unknown'})').join('; ')}.',
  if (law == Law.pollution || law == Law.nuclearPower)
    'Mutants possible if either Pollution or Nuclear Power is Arch Conservative: ${game.mutantsPossible ? 'yes' : 'no'}. Mutant recruitment difficulty is 2 when both are Arch Conservative, 6 when only one is, otherwise that recruitment profession is unavailable.',
  if (law == Law.animalRights)
    'Animals treated as people: ${game.animalsArePeopleToo ? 'enabled' : 'disabled'}. Requires Animal Rights at Elite Liberal.',
  if (law == Law.immigration)
    'Deportation applies to detained crew wanted for illegal entry below Elite Liberal; it is not a random removal of every immigrant crew member.',
];

String lawHoverHelp(AgendaLaw record) {
  final law = Law.values.where((l) => l.name == record.id).firstOrNull;
  if (law == null) {
    return '${record.name}: ${record.alignment.label}\n${record.description}';
  }
  return [
    '${record.name}: ${record.alignment.label}',
    lawEffectSummary(law),
    _lawVictorySummary,
    'Click for details and calculations.',
  ].join('\n\n');
}

List<String> lawPoliticalCalculations(Law law) {
  final politics = game.politics;
  final level = game.laws[law]!.index;
  final support = politics.publicSupportForLaw(law);
  final interest = politics.publicInterestForLaw(law);
  var up = 0;
  var down = 0;
  for (final member in politics.house) {
    if (member.index > level) {
      up += member == DeepAlignment.eliteLiberal ? 3 : 1;
    }
    if (member.index < level) {
      down += member == DeepAlignment.archConservative ? 3 : 1;
    }
  }
  for (final member in politics.senate) {
    if (member.index > level) {
      up += member == DeepAlignment.eliteLiberal ? 10 : 4;
    }
    if (member.index < level) {
      down += member == DeepAlignment.archConservative ? 10 : 4;
    }
  }
  var position = 0;
  for (final threshold in [10, 30, 50, 70]) {
    if (support > threshold) position++;
  }
  if (level < position) up += 150;
  if (level > position) down += 150;
  final pressure = (up - down).abs();
  final direction = level == 0
      ? 'liberal'
      : level == 4
      ? 'conservative'
      : up > down
      ? 'liberal'
      : down > up
      ? 'conservative'
      : 'random tie-break';
  final bias = law == Law.freeSpeech || law == Law.flagBurning
      ? 1
      : law == Law.gunControl
      ? -1
      : 0;
  return [
    'Public target index: $position (${DeepAlignment.values[position].label}). Add one step for support strictly above each of 10%, 30%, 50% and 70%.',
    'Proposal pressure: liberal $up; conservative $down. House members favoring a change contribute 1 each, or 3 for extremists in that direction. Senators contribute 4 each, or 10 for extremists. Public opinion adds 150 toward its target when that target differs from the current law.',
    'Current proposed direction: $direction. Ties roll randomly; laws at either endpoint must move inward.',
    'Bill priority = round(|liberal pressure − conservative pressure| × (interest + random integer 0–24) / 100). Current possible priority: ${(pressure * interest / 100).round()}–${(pressure * (interest + 24) / 100).round()}. Congress selects the highest-priority unused law; tied priorities are selected randomly. This range is not a probability of passage.',
    'Centrist legislator voting: four independent checks against this law’s public support. Polling result = number of successful checks (0–4). If it differs from the legislator’s alignment index by more than 1, pull the result one step toward that alignment. Extremist legislators retain their own alignment index. A member votes for change only when the result lies beyond the current law in the proposed direction.',
    'House passage needs more than half its votes. Senate passage needs more than half, with a possible Vice President tie-break. Veto override needs more than two-thirds in the House and at least two-thirds in the Senate.',
    'Centrist President/VP deliberation = round(clamp((sum of the four executive alignment indices + a random number from 0 inclusive to 9 exclusive − 4) / 4, 0, 4)). Extremists retain their own index. These rolls determine executive support; a successful law change moves one step.',
    'Court issue bias: ${bias >= 0 ? '+' : ''}$bias. Non-extreme justices use alignment index + issue bias + a random integer from −1 to +1. Extremists retain their index. A vote for change must lie beyond the current law in the case direction; the court accepts change when yes votes reach at least half its size.',
  ];
}

Future<void> showLawGuide(BuildContext context, AgendaLaw record) =>
    showDialog<void>(
      context: context,
      builder: (_) => _LawGuide(record: record),
    );

class _LawGuide extends StatelessWidget {
  const _LawGuide({required this.record});
  final AgendaLaw record;
  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 6),
    child: Text(text, style: JournalPalette.heading.copyWith(fontSize: 16)),
  );
  @override
  Widget build(BuildContext context) {
    final law = Law.values.where((l) => l.name == record.id).firstOrNull;
    final combos = law == null ? <String>[] : lawCombinationDetails(law);
    final politics = game.politics;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780, maxHeight: 800),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${record.name} · ${record.alignment.label}',
                      style: JournalPalette.heading,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close law guide',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(record.description, style: JournalPalette.body),
                    if (law != null) ...[
                      _heading('At a glance'),
                      Text(lawEffectSummary(law), style: JournalPalette.body),
                      const SizedBox(height: 6),
                      const Text(
                        _lawVictorySummary,
                        style: JournalPalette.small,
                      ),
                      _heading('Gameplay effects'),
                      Text(lawGameplayEffects(law), style: JournalPalette.body),
                      _heading('Current calculations'),
                      for (final line in lawLevelCalculations(
                        law,
                        record.alignment,
                      ))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(line, style: JournalPalette.body),
                        ),
                      _heading('Compare law levels'),
                      for (final level in DeepAlignment.values)
                        ExpansionTile(
                          key: PageStorageKey(
                            'law-level:${record.id}:${level.name}',
                          ),
                          tilePadding: EdgeInsets.zero,
                          title: Text(
                            '${level.label}${level == record.alignment ? ' · Current' : ''}',
                          ),
                          children: [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Text(
                                  [
                                    law.description[level.index + 1],
                                    ...lawLevelCalculations(law, level),
                                  ].join('\n\n'),
                                  style: JournalPalette.body,
                                ),
                              ),
                            ),
                          ],
                        ),
                      if (combos.isNotEmpty) ...[
                        _heading('Combinations and current conditions'),
                        for (final line in combos)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(line, style: JournalPalette.body),
                          ),
                      ],
                      _heading('Public opinion and law changes'),
                      for (final view in politics.viewsForLaw(law))
                        Text(
                          '${view.label}: support ${politics.publicOpinion[view]!.toStringAsFixed(2)}%; interest ${politics.publicInterest[view]}.',
                          style: JournalPalette.body,
                        ),
                      Text(
                        'Support for this law = average of its linked opinion values = ${politics.publicSupportForLaw(law).toStringAsFixed(2)}%. Interest = average of linked interest values, discarding the fraction = ${politics.publicInterestForLaw(law)}.',
                        style: JournalPalette.body,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Liberal reform proposal: ${billName(law, true)}.\nConservative proposal: ${billName(law, false)}.',
                        style: JournalPalette.body,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Public opinion influences politics; it does not directly replace the law. Congress and court decisions resolve changes. Elections determine who controls those institutions. Browsing this guide changes no law.',
                        style: JournalPalette.small,
                      ),
                      _heading('Legislation and court calculations'),
                      for (final line in lawPoliticalCalculations(law))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(line, style: JournalPalette.body),
                        ),
                    ],
                    _heading('Normal liberal victory requirements'),
                    Text(
                      'Laws at Elite Liberal: ${game.laws.values.where((a) => a == DeepAlignment.eliteLiberal).length}/${Law.values.length}.',
                      style: JournalPalette.body,
                    ),
                    for (final (name, body) in [
                      ('Supreme Court', politics.court),
                      ('House', politics.house),
                      ('Senate', politics.senate),
                    ])
                      Text(
                        '$name: ${body.where((a) => a == DeepAlignment.eliteLiberal).length}/${body.length} Elite Liberal; needs strictly more than half.',
                        style: JournalPalette.body,
                      ),
                    Text(
                      'Executive offices: ${politics.exec.values.where((a) => a == DeepAlignment.eliteLiberal).length}/${politics.exec.length} Elite Liberal; every office must qualify.\nCCS active: ${game.ccsActive ? 'yes · must be defeated' : 'no'}.',
                      style: JournalPalette.body,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'All of these conditions must be met together at the monthly victory check. Getting every law to Elite Liberal alone does not finish the campaign.',
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
}
