import 'package:flutter/foundation.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/journal_context.dart';

enum RecoveryScene { hospital, discharge, defense }

/// Presentation for one original hospital or court input reader. The source
/// owns the people, prose, legal skills, costs and enabled choices shown here.
@immutable
class RecoveryContext {
  RecoveryContext({
    required this.scene,
    required this.title,
    required this.note,
    required Iterable<JournalPersonSummary> people,
    required Iterable<int> bodyRows,
    required Iterable<ConsoleAction> actions,
    Iterable<String> details = const [],
  }) : people = List.unmodifiable(people),
       bodyRows = Set.unmodifiable(bodyRows),
       actions = List.unmodifiable(actions),
       details = List.unmodifiable(details);

  final RecoveryScene scene;
  final String title, note;
  final List<JournalPersonSummary> people;
  final Set<int> bodyRows;
  final List<ConsoleAction> actions;
  final List<String> details;
}

/// Known crew information for a source-authored recovery decision. All game
/// effects stay in the original handlers; this only records the current state.
JournalPersonSummary recoveryPersonSummary(
  Creature person,
) => JournalPersonSummary(
  person: person,
  name: person.name,
  role: person.title,
  health: '${person.blood}/${person.maxBlood} blood',
  equipment: [
    'Weapon: ${person.weapon.equipTitle()}',
    'Clothing: ${person.clothing.shortName}',
    if (person.spareAmmo != null)
      'Reserve ammunition: ${person.spareAmmo!.stackSize}',
  ],
  details: [
    ...person.body.allSpecialInjuries(),
    for (final part in person.body.parts.where((part) => part.wounded))
      '${part.name}: ${[if (part.missing) 'missing', if (part.shot) 'shot', if (part.cut) 'cut', if (part.bruised) 'bruised', if (part.burned) 'burned', if (part.torn) 'torn', if (part.bleeding > 0) 'bleeding (${part.bleeding})'].join(', ')}',
  ],
);

RecoveryContext? recoveryContext(Console console) {
  final frame = console.recovery;
  return console.awaitingInput &&
          !console.textInput &&
          console.eventMessage == null &&
          console.journalProfile == null &&
          console.screen == 'recovery' &&
          frame != null &&
          frame.actions.length == console.actions.length &&
          frame.actions.every(console.actions.contains)
      ? frame
      : null;
}

/// Callbacks from earlier readers, revisions or action objects cannot reach a
/// later input reader even if it happens to use the same keyboard character.
bool recoveryActionIsCurrent(
  Console console,
  RecoveryContext frame,
  ConsoleAction action,
  int revision,
) =>
    action.enabled &&
    console.revision.value == revision &&
    identical(recoveryContext(console), frame) &&
    frame.actions.contains(action) &&
    console.actions.contains(action) &&
    console.lastKey == null;
