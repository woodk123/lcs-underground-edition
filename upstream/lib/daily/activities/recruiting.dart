import 'package:lcs_new_age/common_display/common_display.dart';
import 'package:lcs_new_age/common_display/print_creature_info.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/creature_type.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/engine/engine.dart';
import 'package:lcs_new_age/engine/recruitment_context.dart';
import 'package:lcs_new_age/gamestate/game_state.dart';
import 'package:lcs_new_age/talk/talk.dart';
import 'package:lcs_new_age/utils/colors.dart';
import 'package:lcs_new_age/utils/interface_options.dart';

Future<void> doActivityRecruit(Creature cr) async {
  try {
    await _doActivityRecruit(cr);
  } finally {
    console.recruitment = null;
  }
}

Future<void> _doActivityRecruit(Creature cr) async {
  activeSite = cr.site;

  RecruitData recruit = cr.activity.recruitData ?? recruitableCreatures.first;
  int difficulty = recruit.difficulty;
  String name = recruit.type.name;

  cr.train(Skill.streetSmarts, 5);

  erase();
  mvaddstrc(0, 0, white, "Adventures in Liberal Recruitment");
  printCreatureInfo(cr, showCarPrefs: ShowCarPrefs.onFoot);
  makeDelimiter();

  mvaddstrc(10, 0, lightGray, "${cr.name} asks around for a $name...");

  await getKey();

  int recruitCount = 0;
  encounter.clear();

  if (difficulty < 10) {
    // Generate recruitment candidates
    recruitCount = (cr.skillRoll(Skill.streetSmarts, take10: true) / difficulty)
        .round();
    if (recruitCount > 10) recruitCount = 10;
    for (int i = 0; i < recruitCount; i++) {
      encounter.add(Creature.fromId(recruit.type.id));
    }
  }

  if (recruitCount == 0) {
    mvaddstr(11, 0, "${cr.name} was unable to track down a $name.");
    await getKey();
    return;
  } else if (recruitCount == 1) {
    mvaddstr(11, 0, "${cr.name} managed to set up a meeting with ");
    addstrc(
      encounter[0].align.color,
      "${encounter[0].name} ${creatureAgeAndGender(encounter[0])}",
    );
    addstrc(lightGray, ".");
    console.recruitment = RecruitmentContext(
      recruiter: cr,
      prospects: [RecruitmentProspect(encounter[0])],
    );
    await getKey();

    await _introduceRecruit(cr, encounter[0]);
  } else {
    while (true) {
      erase();
      mvaddstrc(0, 0, white, "Adventures in Liberal Recruitment");
      printCreatureInfo(cr, showCarPrefs: ShowCarPrefs.onFoot);
      makeDelimiter();

      mvaddstrc(
        10,
        0,
        lightGray,
        "${cr.name} was able to get information on multiple people.",
      );
      for (int i = 0; i < recruitCount; i++) {
        String letter = letterAPlus(i);
        addOptionText(
          12 + i,
          0,
          letter,
          "$letter - &${ColorKey.fromColor(encounter[i].align.color)}${encounter[i].name} ${creatureAgeAndGender(encounter[i])}",
        );
      }
      addOptionText(
        12 + recruitCount + 1,
        0,
        "Enter/Escape",
        "Enter/Escape - Call it a day",
      );
      console.recruitment = RecruitmentContext(
        recruiter: cr,
        prospects: [
          for (var i = 0; i < recruitCount; i++)
            RecruitmentProspect(encounter[i], choiceKey: letterAPlus(i)),
        ],
      );

      int c = await getKey();

      if (isBackKey(c)) break;
      c -= 'a'.codePoint;
      if (c >= 0 && c < encounter.length) {
        Creature target = encounter[c];
        await _introduceRecruit(cr, target);
        encounter.remove(target);
        recruitCount--;
        if (recruitCount <= 0) break;
      }
    }
    encounter.clear();
  }
}

Future<void> _introduceRecruit(Creature recruiter, Creature target) async {
  siteAlarm = false;
  siteAlienated = SiteAlienation.none;
  erase();
  mvaddstrc(0, 0, white, 'Adventures in Liberal Recruitment');
  printCreatureInfo(target, showCarPrefs: ShowCarPrefs.onFoot);
  makeDelimiter();
  console.recruitment = RecruitmentContext(
    recruiter: recruiter,
    prospects: [RecruitmentProspect(target)],
  );
  try {
    await talk(recruiter, target);
  } finally {
    console.recruitment = null;
  }
}

class RecruitData {
  RecruitData(this.type, this.name, this.difficulty);
  final String name;
  final CreatureType type;
  int difficulty;
}

List<RecruitData> get recruitableCreatures {
  // Availability changes with the laws. Build a snapshot so filtering out a
  // profession cannot remove it from future campaigns or mutate an open menu.
  final recruitData = <RecruitData>[];
  for (final type in creatureTypes.values) {
    int? difficulty = type.recruitActivityDifficulty;
    if (difficulty == null) continue;
    if (type.id == CreatureTypeIds.mutant) {
      if (!mutantsPossible) continue;
      difficulty = mutantsCommon ? 2 : 6;
    }
    recruitData.add(RecruitData(type, type.name, difficulty));
  }
  recruitData.sort((a, b) {
    final difficultyOrder = a.difficulty.compareTo(b.difficulty);
    if (difficultyOrder != 0) return difficultyOrder;
    final nameOrder = a.name.compareTo(b.name);
    if (nameOrder != 0) return nameOrder;
    return a.type.id.compareTo(b.type.id);
  });
  return recruitData;
}
