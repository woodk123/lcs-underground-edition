import 'package:lcs_new_age/common_display/common_display.dart';
import 'package:lcs_new_age/common_display/print_creature_info.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/engine/engine.dart';
import 'package:lcs_new_age/engine/journal_context.dart';
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart';
import 'package:lcs_new_age/utils/colors.dart';

/// A nested decision owns its whole frame, rather than inheriting roster or
/// field commands from the reader that opened it.
void printSquadMemberChoices(
  String prompt, {
  bool Function(Creature)? enabledWhen,
}) {
  erase();
  console.screen = 'squad_choice';
  mvaddstrc(0, 1, white, prompt);
  for (var index = 0; index < squad.length; index++) {
    final person = squad[index];
    final key = '${index + 1}';
    addOptionText(
      10 + index,
      1,
      key,
      '$key - ${person.name}',
      enabledWhen: enabledWhen?.call(person) ?? true,
    );
    console.annotateActionEntity(key, type: 'person', id: person.id.toString());
  }
  addOptionText(10 + squad.length, 1, 'Enter', 'Enter - Cancel');
}

void printParty({
  bool fullParty = false,
  ShowCarPrefs? showCarPrefs,
}) {
  showCarPrefs ??= mode == GameMode.base
      ? ShowCarPrefs.showPreferences
      : ShowCarPrefs.showActualCar;
  List<Creature> party = activeSquad?.members ?? [];
  setColor(lightGray);
  eraseArea(startY: 2, endY: 8);
  if (activeSquadMember != null && !fullParty) {
    printCreatureInfo(activeSquadMember!, showCarPrefs: showCarPrefs);
    mvaddstrc(1, 0, white, (activeSquadMemberIndex + 1).toString());
  } else {
    console.journalPeople = [];
    addHeader({
      0: "#",
      2: "CODE NAME",
      23: "SKILL",
      29: "WEAPON",
      44: "ARMOR",
      59: "HEALTH",
      70: "TRANSPORT",
    });
    for (int p = 0; p < party.length; p++) {
      addOptionText(p + 2, 0, String.fromCharCode('1'.codePoint + p),
          "${String.fromCharCode('1'.codePoint + p)} ${party[p].name}",
          baseColorKey: ColorKey.white);
      console.annotateActionEntity(
        String.fromCharCode('1'.codePoint + p),
        type: 'person',
        id: party[p].id.toString(),
      );
      if (party[p].isHoldingBody) addstrc(pink, "+H");
      printSkillSummary(p + 2, 23, party[p], showWeaponSkill: true);
      move(p + 2, 29);
      setWeaponColor(party[p]);
      printWeapon(party[p]);
      setColorForArmor(party[p]);
      mvaddstr(p + 2, 44, party[p].clothing.shortName);
      printHealthStat(p + 2, 59, party[p], small: true);
      setColor(lightGray);
      move(p + 2, 70);
      printTransportation(party[p], showCarPrefs);
      String text(int start, int end) => console.buffer[p + 2]
          .sublist(start, end).map((cell) => cell.glyph).join()
          .replaceAll(RegExp(r'[—═─━]{2,}'), '').trim();
      console.journalPeople.add(JournalPersonSummary(
        person: party[p],
        name: party[p].name,
        role: party[p].title,
        health: text(59, 70),
        equipment: [
          'Weapon: ${text(29, 44)}',
          'Armor: ${text(44, 59)}',
          'Transport: ${text(70, 80)}',
        ],
        details: ['Skill: ${text(23, 29)}'],
        choiceKey: '${p + 1}',
      ));
    }
  }
  makeDelimiter();
  console.journalBodyStart = 9;
}

void printSkillSummary(
  int y,
  int x,
  Creature c, {
  bool showWeaponSkill = true,
}) {
  int skill = 0;
  bool bright = false;
  for (Skill sk in Skill.values) {
    skill += c.rawSkill[sk]!;
    if (c.rawSkillXP[sk]! >= 100 + (10 * c.rawSkill[sk]!) &&
        c.rawSkill[sk]! < c.skillCap(sk)) {
      bright = true;
    }
  }
  setColor(bright ? white : lightGray);
  mvaddstr(y, x, "$skill");
  if (showWeaponSkill) addstr("/${c.weaponSkill}");
}
