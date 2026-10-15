import 'package:lcs_new_age/creature/creature.dart';

class JournalProfileContext {
  const JournalProfileContext(this.person, this.page);
  final Creature person;
  final int page;
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
