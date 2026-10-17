import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/politics/laws.dart';

enum LegislationStage { agenda, votes, president, results }

/// Presentation snapshot owned by Congress. Targets are proposals until the
/// simulation records an outcome; rendering never rolls votes or changes laws.
class LegislationContext {
  LegislationContext(this.year);
  final int year;
  LegislationStage stage = LegislationStage.agenda;
  final List<LegislationBill> bills = [];
}

class LegislationBill {
  LegislationBill({
    required this.law,
    required this.before,
    required this.after,
  });
  final Law law;
  final DeepAlignment before, after;
  String? outcome;
  bool enacted = false;
}
