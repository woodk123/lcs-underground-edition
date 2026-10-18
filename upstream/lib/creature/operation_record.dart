import 'package:json_annotation/json_annotation.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/justice/crimes.dart';
import 'package:lcs_new_age/politics/views.dart';

part 'operation_record.g.dart';

/// A historical snapshot, independent of the person's current legal status.
/// Older saves have no entries; totals cannot reconstruct past operations.
@JsonSerializable()
class OperationRecord {
  OperationRecord({
    required this.date,
    required this.siteName,
    required this.outcome,
    required this.heatBefore,
    required this.heatAfter,
    this.siege = false,
    this.participants = const [],
    this.juiceChange = 0,
    this.bloodChange = 0,
    this.newCharges = const {},
    this.trainingXp = const {},
    this.injuries = const [],
    this.squadResults = const [],
    this.opinionChanges = const {},
  });

  factory OperationRecord.fromJson(Map<String, dynamic> json) =>
      _$OperationRecordFromJson(json);
  Map<String, dynamic> toJson() => _$OperationRecordToJson(this);

  final DateTime date;
  final String siteName;
  final OperationOutcome outcome;
  final int heatBefore;
  final int heatAfter;
  final bool siege;
  final List<String> participants;
  final int juiceChange;
  final int bloodChange;
  final Map<Crime, int> newCharges;
  final Map<Skill, int> trainingXp;
  final List<String> injuries;
  final List<String> squadResults;
  final Map<View, double> opinionChanges;
}

enum OperationOutcome { returned, captured, killed, missing }

/// Bound save growth while retaining useful recent personal history.
const operationHistoryLimit = 50;
