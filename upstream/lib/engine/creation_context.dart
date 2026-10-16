import 'package:flutter/foundation.dart';
import 'package:lcs_new_age/creature/creature.dart';

enum CreationStage { setup, identity, background, briefing, name }

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
  });

  final String key;
  final String label;
  final String description;
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
  }) : fields = List.unmodifiable(fields),
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
}
