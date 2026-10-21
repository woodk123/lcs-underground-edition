import 'package:lcs_new_age/engine/organisation_context.dart';

/// Search vocabulary adds familiar goals to source-authored task names. It
/// never supplies availability or command keys.
const _synonyms = <String, String>{
  'donations': 'money earn income fundraising charity',
  'sellTshirts': 'money earn income fundraising clothes shirts tailor',
  'sellArt': 'money earn income fundraising paint draw',
  'sellMusic': 'money earn income fundraising music busk',
  'sellDrugs': 'money earn income fundraising drugs cannabis',
  'prostitution': 'money earn income fundraising sex',
  'ccfraud': 'money earn income fundraising hacking computer',
  'recruiting': 'recruit new people crew members persuade',
  'study': 'train training learn education practice skills free',
  'takeClass': 'train training learn education school skills paid',
  'teachLiberalArts': 'train training learn education teacher students',
  'teachCovert': 'train training learn education teacher students',
  'teachFighting': 'train training learn education teacher students combat',
  'clinic': 'heal healing injury injuries treatment medical doctor hospital',
  'none': 'rest resting recover heal laundry mend repair clothes lay low',
  'interrogation': 'hostage captive prisoner convert tend',
  'bury': 'dead body bodies corpse disposal bury burial',
  'makeClothing': 'craft crafting tailor clothes armour armor',
  'makeFlag': 'craft crafting sew flag',
  'wheelchair': 'mobility disabled walking medical',
  'stealCars': 'vehicle vehicles car theft',
  'writeGuardian': 'newspaper media publish writing propaganda',
  'streamGuardian': 'media video broadcast streaming television propaganda',
  'communityService': 'juice reputation charity volunteer',
};

bool matchesOrderSearch(
  ActivityOrderCategory category,
  ActivityOrderTask task,
  String query,
) {
  final words = query.toLowerCase().trim().split(RegExp(r'\s+'));
  final text = '${category.label} ${task.label} ${_synonyms[task.typeId] ?? ''}'
      .toLowerCase();
  return words.every(text.contains);
}
