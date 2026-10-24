import 'package:flutter/foundation.dart';
import 'package:lcs_new_age/creature/attributes.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/skills.dart';

enum CreationStage { setup, identity, background, briefing, name }

/// The stat changes authored by a background option. Both the original reader
/// and its read-only choice preview use these values; narrative text is not a
/// source of gameplay arithmetic. Equipment and world effects stay in the reader.
@immutable
class CreationBonuses {
  const CreationBonuses({
    this.attributes = const {},
    this.skills = const {},
    this.birthDate,
    this.juice,
  });

  final Map<Attribute, int> attributes;
  final Map<Skill, int> skills;
  final DateTime? birthDate;
  final int? juice;

  void apply(Creature actor) {
    if (birthDate != null) actor.birthDate = birthDate!;
    for (final entry in attributes.entries) {
      actor.adjustAttribute(entry.key, entry.value);
    }
    for (final entry in skills.entries) {
      actor.adjustSkill(entry.key, entry.value);
    }
    if (juice != null) actor.juice = juice!;
  }
}

@immutable
class CreationField {
  const CreationField({
    required this.key,
    required this.label,
    required this.value,
    this.description = '',
  });

  final String key;
  final String label;
  final String value;
  final String description;
}

@immutable
class CreationChoice {
  const CreationChoice({
    required this.key,
    required this.label,
    this.description = '',
    this.bonuses,
  });

  final String key;
  final String label;
  final String description;
  final CreationBonuses? bonuses;
}

/// Presentation of one original creation reader. Lists are immutable snapshots;
/// the optional founder is the authoritative live person, read only by the UI.
@immutable
class CreationContext {
  CreationContext({
    required this.stage,
    required this.title,
    this.subtitle = '',
    this.prompt = '',
    this.step,
    this.totalSteps,
    List<CreationField> fields = const [],
    List<CreationChoice> choices = const [],
    List<String> body = const [],
    this.founder,
    this.portraitId,
    this.portraitRerollKey,
    this.portraitSelectKey,
    Map<String, int> portraitChoices = const {},
    this.pendingBonuses,
  }) : portraitChoices = Map.unmodifiable(portraitChoices),
       fields = List.unmodifiable(fields),
       choices = List.unmodifiable(choices),
       body = List.unmodifiable(body);

  final CreationStage stage;
  final String title;
  final String subtitle;
  final String prompt;
  final int? step;
  final int? totalSteps;
  final List<CreationField> fields;
  final List<CreationChoice> choices;
  final List<String> body;
  final Creature? founder;

  /// Cosmetic identity preview; the founder has not joined the campaign yet.
  final int? portraitId;
  final String? portraitRerollKey;
  final String? portraitSelectKey;
  final Map<String, int> portraitChoices;
  final CreationBonuses? pendingBonuses;
}
