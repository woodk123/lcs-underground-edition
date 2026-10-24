/// Optional, additive state for a working business front. Older campaigns have
/// no working shop until the player chooses to equip one.
enum FrontBusinessMode {
  commercial('Commercial work'),
  movement('Movement printing'),
  closed('Temporarily closed');

  const FrontBusinessMode(this.label);
  final String label;
}

class FrontBusiness {
  FrontBusiness({this.name = 'Community Print Shop'});

  factory FrontBusiness.fromJson(Map<String, dynamic> json) {
    final business = FrontBusiness(
      name: json['name'] as String? ?? 'Community Print Shop',
    );
    business.mode = FrontBusinessMode.values.firstWhere(
      (mode) => mode.name == json['mode'],
      orElse: () => FrontBusinessMode.commercial,
    );
    business.staffIds = (json['staffIds'] as List<dynamic>? ?? [])
        .whereType<num>()
        .map((id) => id.toInt())
        .toSet()
        .take(maxStaff)
        .toList();
    business.lastProcessedDay = json['lastProcessedDay'] as String?;
    business.lastGross = (json['lastGross'] as num?)?.toInt() ?? 0;
    business.lastCost = (json['lastCost'] as num?)?.toInt() ?? 0;
    business.lastInfluence = (json['lastInfluence'] as num?)?.toInt() ?? 0;
    business.lastWorkers = (json['lastWorkers'] as num?)?.toInt() ?? 0;
    business.lastReport = json['lastReport'] as String? ?? business.lastReport;
    business.operatingDaysSinceOffer =
        ((json['operatingDaysSinceOffer'] as num?)?.toInt() ?? 0).clamp(
          0,
          rushOrderInterval - 1,
        );
    business.rushOrderPending = json['rushOrderPending'] as bool? ?? false;
    business.rushOrderAccepted =
        business.rushOrderPending &&
        (json['rushOrderAccepted'] as bool? ?? false);
    return business;
  }

  static const equipmentCost = 1500;
  static const maxStaff = 2;
  static const dailyCostPerWorker = 20;
  static const rushOrderInterval = 7;
  static const rushOrderBonus = 100;

  String name;
  FrontBusinessMode mode = FrontBusinessMode.commercial;
  List<int> staffIds = [];
  String? lastProcessedDay;
  int lastGross = 0;
  int lastCost = 0;
  int lastInfluence = 0;
  int lastWorkers = 0;
  String lastReport = 'No trading day completed yet.';
  int operatingDaysSinceOffer = 0;
  bool rushOrderPending = false;
  bool rushOrderAccepted = false;

  Map<String, dynamic> toJson() => {
    'name': name,
    'mode': mode.name,
    'staffIds': staffIds,
    'lastProcessedDay': lastProcessedDay,
    'lastGross': lastGross,
    'lastCost': lastCost,
    'lastInfluence': lastInfluence,
    'lastWorkers': lastWorkers,
    'lastReport': lastReport,
    'operatingDaysSinceOffer': operatingDaysSinceOffer,
    'rushOrderPending': rushOrderPending,
    'rushOrderAccepted': rushOrderAccepted,
  };
}
