import 'package:lcs_new_age/creature/creature.dart';

class JournalProfileContext {
  JournalProfileContext(
    this.person,
    this.page, {
    this.confirming = false,
    Iterable<int> personIds = const [],
    bool canSelectPerson = false,
  }) : personIds = List.unmodifiable(personIds),
       canSelectPerson = canSelectPerson && !confirming;
  final Creature person;
  final int page;
  final bool confirming;

  /// The exact ordered roster used by this source profile reader, rather than
  /// a modern UI guess based on squad, employment or location.
  final List<int> personIds;

  /// Only ordinary profile readers expose person navigation. Rename entries,
  /// confirmations and reports must keep their own awaited input.
  final bool canSelectPerson;
}

/// A snapshot of information actually printed by the current engine scene.
/// Details stay as printed, including unknown skills and restricted knowledge.
class JournalPersonSummary {
  JournalPersonSummary({
    required this.person,
    required this.name,
    required this.role,
    required this.health,
    required this.equipment,
    this.details = const [],
    this.choiceKey,
    this.inspectable = true,
  });

  final Creature person;
  final String name, role, health;
  final List<String> equipment, details;
  final String? choiceKey;
  final bool inspectable;
}
