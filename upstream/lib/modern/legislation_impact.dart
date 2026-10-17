import 'package:lcs_new_age/modern/law_help.dart';
import 'package:lcs_new_age/politics/alignment.dart' show DeepAlignment;
import 'package:lcs_new_age/politics/laws.dart';

/// A read-only comparison of the two policies carried by a bill or ruling.
/// Callers decide whether [afterPolicy] is proposed or has actually taken effect.
class LegislationImpact {
  const LegislationImpact({
    required this.beforePolicy,
    required this.afterPolicy,
    required this.gameplayImpact,
  });

  final String beforePolicy;
  final String afterPolicy;
  final String gameplayImpact;
}

LegislationImpact legislationImpact(
  Law law,
  DeepAlignment before,
  DeepAlignment after,
) => LegislationImpact(
  // The outer descriptions are reserved for endgame victory worlds.
  beforePolicy: law.description[before.index + 1],
  afterPolicy: law.description[after.index + 1],
  gameplayImpact: before == after
      ? 'The current policy stays in force. ${lawEffectSummary(law)}'
      : _changeImpact(law, before, after),
);

String _changeImpact(Law law, DeepAlignment before, DeepAlignment after) {
  final liberal = after > before;
  final direction = liberal ? 'closer to' : 'further from';
  final victory = 'Moves this issue $direction the Elite Liberal victory goal.';
  // These explanations deliberately distinguish effects that happen at every
  // step from threshold effects and combinations with other laws. Mechanics
  // are also documented in law_help.dart; no simulation handler runs here.
  final effect = switch (law) {
    Law.healthcare =>
      liberal
          ? 'Hospital treatment becomes cheaper for the crew. At Elite Liberal, the hospital billing factor reaches zero.'
          : 'Hospital treatment becomes more expensive for the crew; the bill still depends on the care needed.',
    Law.elections =>
      liberal
          ? 'Reduces the conservative bias in congressional elections and the incumbent automatic-win advantage. Term limits can already disable that incumbent advantage.'
          : 'Increases the conservative bias in congressional elections and the incumbent automatic-win advantage. Term limits can still disable that incumbent advantage.',
    Law.policeReform =>
      liberal
          ? 'Lowers the cap on police strength when building cases against detained crew. Arch Conservative death-penalty law overrides this cap. Police encounters and chase behaviour also depend on this law.'
          : 'Raises the cap on police strength when building cases against detained crew. Arch Conservative death-penalty law overrides this cap. Police encounters and chase behaviour also depend on this law.',
    Law.deathPenalty =>
      after == DeepAlignment.eliteLiberal
          ? 'Abolishes death sentences and commutes existing death-row sentences to life during prison processing.'
          : liberal
          ? 'Reduces execution risk in eligible cases. Abolition requires Elite Liberal law.'
          : after == DeepAlignment.archConservative
          ? 'Any non-lenient conviction can now result in execution. Police case strength also reaches its harshest setting.'
          : 'Raises execution risk in eligible non-lenient cases; other charges and the trial still matter.',
    Law.drugs =>
      after >= DeepAlignment.liberal && before < DeepAlignment.liberal
          ? 'Weed-brownie income falls, but the selling activity no longer triggers its drug-law police searches, and drug-distribution charges add no prison time.'
          : after < DeepAlignment.liberal && before >= DeepAlignment.liberal
          ? 'Weed-brownie income rises, but selling again risks drug-law police searches and drug-distribution prison time.'
          : liberal
          ? 'Weed-brownie income falls as prohibition eases. Below Liberal, drug searches and distribution sentences also become less harsh.'
          : 'Weed-brownie income rises with tighter prohibition. Below Liberal, drug searches and distribution sentences also become harsher.',
    Law.flagBurning =>
      after >= DeepAlignment.liberal
          ? 'National-flag burning is legal at Liberal and Elite Liberal levels.'
          : after == DeepAlignment.archConservative
          ? 'Flag burning carries the highest offence heat and can qualify for capital punishment, depending on death-penalty law.'
          : 'National-flag burning remains criminal. The law level controls its heat and prison sentence.',
    Law.gunControl =>
      liberal
          ? 'Tightens legal weapon and ammunition availability as ban thresholds are crossed. Can raise black-market weapon prices, reduce civilian armament and change weapon security checks.'
          : 'Relaxes legal weapon and ammunition restrictions as ban thresholds are crossed. Can lower black-market weapon prices, increase civilian armament and change weapon security checks.',
    Law.immigration =>
      after == DeepAlignment.eliteLiberal
          ? 'Detained crew wanted for illegal entry are no longer deported by the monthly immigration check.'
          : before == DeepAlignment.eliteLiberal
          ? 'Detained crew wanted for illegal entry can now be deported. At Arch Conservative immigration and death-penalty law, that outcome becomes execution.'
          : 'Detained crew wanted for illegal entry remain at risk of deportation. Execution requires both immigration and death-penalty law to be Arch Conservative.',
    Law.prisons =>
      after == DeepAlignment.eliteLiberal
          ? 'Eligible prison scenes now use rehabilitation.'
          : after == DeepAlignment.archConservative
          ? 'Eligible prison scenes now use labor camps. This also contributes to the 1984 regime when the other required laws align.'
          : 'Eligible prison scenes use ordinary prison events at this level. Rehabilitation requires Elite Liberal law; labor camps require Arch Conservative law.',
    Law.torture =>
      after == DeepAlignment.eliteLiberal
          ? 'Removes the torture-related incident from the daily civil-disobedience event pool.'
          : before == DeepAlignment.eliteLiberal
          ? 'The torture-related incident can appear again during daily civil disobedience.'
          : 'The torture-related civil-disobedience incident remains possible; its removal requires Elite Liberal law.',
    // For indirect and mixed effects, share the existing grounded law guide
    // rather than imply that every one-step change grants a new daily bonus.
    _ => lawGameplayEffects(law),
  };
  return '$effect $victory';
}
