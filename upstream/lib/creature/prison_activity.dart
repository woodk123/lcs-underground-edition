/// Separate from a person's ordinary daily assignment. Old saves have no
/// prison activity and retain the original monthly prison behaviour.
enum PrisonOrder {
  keepHeadDown('Keep your head down'),
  studyLaw('Study Law'),
  studyWriting('Study Writing'),
  buildContacts('Build contacts'),
  documentConditions('Document conditions');

  const PrisonOrder(this.label);
  final String label;
}

class PrisonActivity {
  PrisonActivity();

  factory PrisonActivity.fromJson(Map<String, dynamic> json) {
    int bounded(String key, int max) =>
        ((json[key] as num?)?.toInt() ?? 0).clamp(0, max);
    return PrisonActivity()
      ..order = PrisonOrder.values.firstWhere(
        (order) => order.name == json['order'],
        orElse: () => PrisonOrder.keepHeadDown,
      )
      ..contacts = bounded('contacts', maxPrisonContacts)
      ..documentProgress = bounded('documentProgress', prisonDocumentMonths)
      ..documentCompleted = json['documentCompleted'] == true
      ..pendingDocument = json['pendingDocument'] == true
      ..pendingDocumentCityId = (json['pendingDocumentCityId'] as num?)?.toInt()
      ..lastResolvedMonth = (json['lastResolvedMonth'] as num?)?.toInt()
      ..lastReport = json['lastReport'] as String?;
  }

  Map<String, dynamic> toJson() => {
    'order': order.name,
    'contacts': contacts,
    'documentProgress': documentProgress,
    'documentCompleted': documentCompleted,
    'pendingDocument': pendingDocument,
    'pendingDocumentCityId': pendingDocumentCityId,
    'lastResolvedMonth': lastResolvedMonth,
    'lastReport': lastReport,
  };

  PrisonOrder order = PrisonOrder.keepHeadDown;
  int contacts = 0;
  int documentProgress = 0;
  bool documentCompleted = false;
  bool pendingDocument = false;
  int? pendingDocumentCityId;
  int? lastResolvedMonth;
  String? lastReport;
}

const maxPrisonContacts = 6;
const prisonDocumentMonths = 3;
