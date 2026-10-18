import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:lcs_new_age/basemode/activate_sleepers.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Acknowledgements for the Network's "Review role" prompts.
///
/// This is local presentation state, separate from campaign saves and mechanics.
/// A workplace, job, standing order or availability change invites a new review;
/// normal infiltration growth, the date and remaining recovery days do not.
class NetworkReviewStore extends ChangeNotifier {
  NetworkReviewStore({Future<SharedPreferences> Function()? preferences})
    : _preferencesLoader = preferences ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _preferencesLoader;
  final Map<int, String> _reviewed = {};
  SharedPreferences? _preferences;
  Future<void>? _loading;
  int? _campaignId;
  int _generation = 0;
  bool _loaded = false;
  bool _disposed = false;

  bool get loaded => _loaded;

  String _prefix(int campaignId) => 'networkRoleReview.v1.$campaignId.';

  /// Switches campaigns immediately and ignores any older pending load.
  Future<void> load(int campaignId) {
    if (_disposed) return Future<void>.value();
    if (_campaignId == campaignId && (_loaded || _loading != null)) {
      return _loading ?? Future<void>.value();
    }
    final generation = ++_generation;
    _campaignId = campaignId;
    _loaded = false;
    _preferences = null;
    _reviewed.clear();
    final loading = _loading = _load(campaignId, generation);
    notifyListeners();
    return loading;
  }

  Future<void> _load(int campaignId, int generation) async {
    SharedPreferences? preferences;
    final reviewed = <int, String>{};
    try {
      preferences = await _preferencesLoader();
      final prefix = _prefix(campaignId);
      for (final key in preferences.getKeys().where(
        (key) => key.startsWith(prefix),
      )) {
        final personId = int.tryParse(key.substring(prefix.length));
        final value = preferences.get(key);
        if (personId != null && value is String) reviewed[personId] = value;
      }
    } catch (_) {
      // Storage failure must never prevent inspecting or assigning real orders.
      // Acknowledgements still work in memory for the current app session.
    }
    if (_disposed || generation != _generation) return;
    _preferences = preferences;
    _reviewed.addAll(reviewed);
    _loaded = true;
    _loading = null;
    notifyListeners();
  }

  bool needsReview(Creature person) =>
      _loaded &&
      !_disposed &&
      person.alive &&
      person.sleeperAgent &&
      _reviewed[person.id] != _signature(person);

  int count(Iterable<Creature> people) => people.where(needsReview).length;

  /// Acknowledges the person's current role without altering any game field.
  Future<void> markReviewed(Creature person) async {
    final campaignId = _campaignId;
    if (!_loaded ||
        _disposed ||
        campaignId == null ||
        !person.alive ||
        !person.sleeperAgent) {
      return;
    }
    final signature = _signature(person);
    if (_reviewed[person.id] == signature) return;
    _reviewed[person.id] = signature;
    notifyListeners();
    try {
      await _preferences?.setString(
        '${_prefix(campaignId)}${person.id}',
        signature,
      );
    } catch (_) {
      // Preserve the in-memory acknowledgement when local storage is unavailable.
    }
  }

  String _signature(Creature person) => jsonEncode([
    person.typeId,
    person.workLocationId,
    person.activity.toJson(),
    sleeperOrderUnavailableReason(person),
  ]);

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
