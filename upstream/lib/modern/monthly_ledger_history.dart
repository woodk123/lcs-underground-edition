import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:lcs_new_age/engine/ledger_context.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The latest observed and acknowledged monthly report. This is local reading
/// history, not part of a game save, and contains no source commands.
@immutable
class MonthlyLedgerSnapshot {
  MonthlyLedgerSnapshot({
    required this.period,
    required this.reportedAt,
    required this.cash,
    required this.monthlyNet,
    required this.dailyNet,
    required this.totalLiquidAssets,
    required List<LedgerReportLine> lines,
  }) : lines = List.unmodifiable(lines);

  factory MonthlyLedgerSnapshot.fromFrame(LedgerReportFrame frame) =>
      MonthlyLedgerSnapshot(
        period: frame.period,
        reportedAt: frame.reportedAt,
        cash: frame.cash,
        monthlyNet: frame.monthlyNet,
        dailyNet: frame.dailyNet,
        totalLiquidAssets: frame.totalLiquidAssets,
        lines: frame.lines,
      );

  factory MonthlyLedgerSnapshot._fromJson(Map<String, dynamic> json) =>
      MonthlyLedgerSnapshot(
        period: DateTime.parse(json['period'] as String),
        reportedAt: DateTime.parse(json['reportedAt'] as String),
        cash: json['cash'] as int,
        monthlyNet: json['monthlyNet'] as int,
        dailyNet: json['dailyNet'] as int,
        totalLiquidAssets: json['totalLiquidAssets'] as int,
        lines: [
          for (final value in json['lines'] as List)
            LedgerReportLine(
              id: (value as Map)['id'] as String,
              label: value['label'] as String,
              kind: LedgerLineKind.values.byName(value['kind'] as String),
              amount: value['amount'] as int,
              dailyAmount: value['dailyAmount'] as int,
              page: value['page'] as int,
            ),
        ],
      );

  final DateTime period, reportedAt;
  final int cash, monthlyNet, dailyNet, totalLiquidAssets;
  final List<LedgerReportLine> lines;

  int get pageCount => lines.fold(
    1,
    (pages, line) => line.page + 1 > pages ? line.page + 1 : pages,
  );

  Map<String, dynamic> _toJson() => {
    'period': period.toIso8601String(),
    'reportedAt': reportedAt.toIso8601String(),
    'cash': cash,
    'monthlyNet': monthlyNet,
    'dailyNet': dailyNet,
    'totalLiquidAssets': totalLiquidAssets,
    'lines': [
      for (final line in lines)
        {
          'id': line.id,
          'label': line.label,
          'kind': line.kind.name,
          'amount': line.amount,
          'dailyAmount': line.dailyAmount,
          'page': line.page,
        },
    ],
  };
}

class MonthlyLedgerHistoryStore extends ChangeNotifier {
  MonthlyLedgerHistoryStore({Future<SharedPreferences> Function()? preferences})
    : _preferencesLoader = preferences ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _preferencesLoader;
  SharedPreferences? _preferences;
  Future<void> _tail = Future<void>.value();
  Future<void> _writes = Future<void>.value();
  int? _campaignId;
  int _generation = 0;
  bool _disposed = false, _loaded = false;
  MonthlyLedgerSnapshot? _latest;
  bool get loaded => _loaded;
  MonthlyLedgerSnapshot? get latest => _latest;
  String _key(int id) => 'monthlyLedgerHistory.v1.$id';

  /// The controller supplies only the source's completed-report marker. Copy
  /// its immutable values now, before any asynchronous preference load. A first
  /// observation without an actual report never invents previous accounts.
  Future<void> observe(
    int campaignId,
    DateTime date, {
    LedgerReportFrame? completed,
  }) {
    if (_disposed) return Future<void>.value();
    final snapshot =
        completed != null &&
            !completed.management &&
            completed.campaignId == campaignId &&
            !completed.reportedAt.isAfter(date) &&
            completed.period ==
                DateTime(
                  completed.reportedAt.year,
                  completed.reportedAt.month - 1,
                )
        ? MonthlyLedgerSnapshot.fromFrame(completed)
        : null;
    if (_campaignId != campaignId) {
      final generation = ++_generation;
      _campaignId = campaignId;
      _loaded = false;
      _latest = null;
      _preferences = null;
      _tail = _load(campaignId, generation);
      notifyListeners();
    }
    final generation = _generation;
    return _tail = _tail.then((_) async {
      if (_disposed || generation != _generation) return;
      var changed = false;
      // Importing an older save from this campaign must not expose its future.
      if (_latest?.reportedAt.isAfter(date) == true) {
        _latest = null;
        changed = true;
      }
      if (snapshot != null &&
          (_latest == null ||
              !snapshot.reportedAt.isBefore(_latest!.reportedAt)) &&
          jsonEncode(snapshot._toJson()) !=
              (_latest == null ? null : jsonEncode(_latest!._toJson()))) {
        _latest = snapshot;
        changed = true;
      }
      if (changed) {
        notifyListeners();
        await _persist(campaignId);
      }
    });
  }

  Future<void> _load(int campaignId, int generation) async {
    SharedPreferences? preferences;
    MonthlyLedgerSnapshot? saved;
    try {
      await _writes;
      preferences = await _preferencesLoader();
      final contents = preferences.getString(_key(campaignId));
      if (contents != null) {
        saved = MonthlyLedgerSnapshot._fromJson(
          Map<String, dynamic>.from(jsonDecode(contents) as Map),
        );
        if (saved.period !=
                DateTime(saved.reportedAt.year, saved.reportedAt.month - 1) ||
            saved.lines.any((line) => line.page < 0)) {
          saved = null;
        }
      }
    } catch (_) {
      // Corrupt or unavailable preferences never obstruct the real ledger.
    }
    if (_disposed || generation != _generation) return;
    _preferences = preferences;
    _latest = saved;
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist(int campaignId) {
    final preferences = _preferences;
    final contents = _latest == null ? null : jsonEncode(_latest!._toJson());
    return _writes = _writes.then((_) async {
      try {
        if (contents == null) {
          await preferences?.remove(_key(campaignId));
        } else {
          await preferences?.setString(_key(campaignId), contents);
        }
      } catch (_) {
        // Keep the in-memory report if storage is unavailable.
      }
    });
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
