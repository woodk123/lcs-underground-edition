import 'package:collection/collection.dart';
import 'package:lcs_new_age/common_display/common_display.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/prison_activity.dart';
import 'package:lcs_new_age/engine/engine.dart';
import 'package:lcs_new_age/gamestate/game_state.dart';
import 'package:lcs_new_age/justice/prison.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/utils/colors.dart';
import 'package:lcs_new_age/utils/interface_options.dart';

/// Original source reader. Presentation dispatches only these current choices.
Future<void> managePrisoners({int? personId}) async {
  if (personId != null) {
    final person = pool.firstWhereOrNull((person) => person.id == personId);
    if (person != null) await _managePrisoner(person);
    return;
  }
  int page = 0;
  while (true) {
    final prisoners =
        pool
            .where(
              (person) =>
                  person.alive &&
                  person.align == Alignment.liberal &&
                  !person.sleeperAgent &&
                  person.site?.type == SiteType.prison,
            )
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    final pages = (prisoners.length / 16).ceil().clamp(1, 1000000);
    page = page.clamp(0, pages - 1);
    erase();
    console.screen = 'prison-management';
    mvaddstrc(0, 1, white, 'Prison orders');
    mvaddstr(
      2,
      1,
      'Standing orders resolve monthly; ordinary prison events still occur.',
    );
    if (prisoners.isEmpty) {
      mvaddstr(5, 1, 'No LCS members are serving time in prison.');
      mvaddstr(
        7,
        1,
        'Police custody, court and sleeper staff do not receive prison orders.',
      );
    }
    int index = 0;
    for (final person in prisoners.skip(page * 16).take(16)) {
      final key = letterAPlus(index);
      final order = person.prisonActivity?.order ?? PrisonOrder.keepHeadDown;
      final name = person.name.length > 27
          ? '${person.name.substring(0, 26)}…'
          : person.name;
      addOptionText(4 + index, 1, key, '$key - $name: ${order.label}');
      console.annotateActionEntity(
        key,
        type: 'prisoner-person',
        id: person.id.toString(),
      );
      index++;
    }
    if (pages > 1) addPageButtons(y: 21, x: 1, current: page + 1, max: pages);
    addOptionText(23, 1, 'Enter', 'Enter - Back');
    declareMenuNavigation('people', backKey: 'Enter');
    final input = await getKey();
    if (isBackKey(input)) return;
    if ((isPageUp(input) || input == Key.leftArrow || input == Key.upArrow) &&
        page > 0) {
      page--;
    }
    if ((isPageDown(input) ||
            input == Key.rightArrow ||
            input == Key.downArrow) &&
        page + 1 < pages) {
      page++;
    }
    if (input >= Key.a && input < Key.a + 16) {
      final selected = page * 16 + input - Key.a;
      if (selected < prisoners.length) {
        await _managePrisoner(prisoners[selected]);
      }
    }
  }
}

Future<void> _managePrisoner(Creature person) async {
  while (true) {
    erase();
    console.screen = 'prison-order';
    final state = person.prisonActivity;
    final current = state?.order ?? PrisonOrder.keepHeadDown;
    mvaddstrc(0, 1, white, 'Prison orders: ${person.name}');
    final sentence = person.deathPenalty
        ? 'Death row'
        : person.sentence < 0
        ? 'Life sentence'
        : '${person.sentence} months remaining';
    mvaddstr(
      2,
      1,
      '${person.location?.getName(short: true) ?? 'No current location'} - $sentence',
    );
    mvaddstr(3, 1, 'Current order: ${current.label}');
    mvaddstr(
      4,
      1,
      'Resolves monthly before sentence countdown; no daily assignment changes.',
    );
    mvaddstr(
      5,
      1,
      'Contacts: ${state?.contacts ?? 0}/6 (${prisonContacts(person)}/6 shared here)',
    );
    final dossier = state?.pendingDocument == true
        ? 'Awaiting safehouse delivery'
        : state?.documentCompleted == true
        ? 'Completed for this sentence'
        : '${state?.documentProgress ?? 0}/$prisonDocumentMonths successful months';
    mvaddstr(6, 1, 'Prison dossier: $dossier');
    final unavailable = prisonOrderUnavailableReason(person);
    if (unavailable != null) mvaddstrc(7, 1, yellow, unavailable);
    for (int i = 0; i < PrisonOrder.values.length; i++) {
      final order = PrisonOrder.values[i];
      final key = letterAPlus(i);
      final reason = prisonProjectUnavailableReason(person, order);
      addOptionText(
        9 + i,
        1,
        key,
        '$key - ${order.label}${current == order ? ' (current)' : ''}',
        enabledWhen: reason == null,
      );
      console.annotateActionEntity(
        key,
        type: 'prison-order',
        id: order.name,
        category: person.id.toString(),
      );
    }
    final explanation = switch (current) {
      PrisonOrder.keepHeadDown => 'No additional project or project risk. Normal prison events and automatic escape chances continue.',
      PrisonOrder.studyLaw || PrisonOrder.studyWriting => 'Study earns skill XP each month, up to the normal training limit. Better prison laws provide more study time; labor camps provide no study materials.',
      PrisonOrder.buildContacts => 'Persuasion checks build up to 6 contacts and train Persuasion. Failure disrupts a contact and can cost 5 Juice. Three shared contacts help document conditions.',
      PrisonOrder.documentConditions => 'Writing or Stealth checks build a dossier over 3 successful months. Failure loses one month of evidence and can cost 10 Juice. One dossier per sentence, delivered to a same-city safehouse for publication. Rehabilitation has no abuse dossier.',
    };
    addparagraph(15, 1, explanation, y2: 18, x2: 78);
    if (unavailable == null) {
      final studyRestriction = prisonProjectUnavailableReason(
        person,
        PrisonOrder.studyLaw,
      );
      final documentRestriction = prisonProjectUnavailableReason(
        person,
        PrisonOrder.documentConditions,
      );
      if (studyRestriction != null) mvaddstrc(19, 1, yellow, studyRestriction);
      if (documentRestriction != null) {
        mvaddstrc(19, 1, yellow, documentRestriction);
      }
    }
    if (state?.lastReport != null) {
      addparagraph(20, 1, 'Last report: ${state!.lastReport}', y2: 22, x2: 78);
    }
    addOptionText(24, 1, 'Enter', 'Enter - Back');
    declareMenuNavigation('people', backKey: 'Enter');
    final input = await getKey();
    if (isBackKey(input)) return;
    if (input >= Key.a && input < Key.a + PrisonOrder.values.length) {
      setPrisonOrder(person, PrisonOrder.values[input - Key.a]);
    }
  }
}
