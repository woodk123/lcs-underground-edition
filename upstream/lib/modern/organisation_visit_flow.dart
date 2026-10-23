import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/gamestate/squad.dart';
import 'package:lcs_new_age/location/city.dart';
import 'package:lcs_new_age/location/district.dart';
import 'package:lcs_new_age/location/location.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/modern/organisation_controller.dart';

/// Local map selection and the original planner's asynchronous visit journey.
/// The journal supplies live readers/selection and keeps layout and focus.
class OrganisationVisitFlow extends ChangeNotifier {
  OrganisationVisitFlow({
    required Console Function() console,
    required OrganisationController Function() controller,
    required Squad? Function() squad,
  }) : _readConsole = console,
       _readController = controller,
       _readSquad = squad;

  final Console Function() _readConsole;
  final OrganisationController Function() _readController;
  final Squad? Function() _readSquad;
  Console get _console => _readConsole();
  OrganisationController get _controller => _readController();
  Squad? get _squad => _readSquad();
  bool get _planning => _console.screen == 'planning';

  String? _areaId, _targetId, _message;
  int? _targetSquadId;
  int _request = 0;
  bool _routing = false, _disposed = false;

  String? get areaId => _areaId;
  String? get targetId => _targetId;
  String? get message => _message;
  bool get routing => _routing;
  Site? get selectedDestination => _targetSquadId == _squad?.id
      ? game.sites
            .where((site) => site.idString == _targetId && !site.hidden)
            .firstOrNull
      : null;
  ConsoleAction? get visitAction => _planning
      ? _console.actions
            .where(
              (action) =>
                  action.entityType == 'site' &&
                  action.entityId == selectedDestination?.idString,
            )
            .firstOrNull
      : null;

  void invalidate() => _request++;

  void clearTarget({bool clearSquad = false}) {
    _targetId = null;
    if (clearSquad) _targetSquadId = null;
    notifyListeners();
  }

  void selectLocation(Location location) {
    invalidate();
    _message = null;
    _targetId = location is Site ? location.idString : null;
    _targetSquadId = location is Site ? _squad?.id : null;
    if (!_planning && (location is District || location is City)) {
      _areaId = location.idString;
    }
    notifyListeners();
  }

  void cityOverview() {
    _areaId = null;
    _targetId = null;
    notifyListeners();
  }

  List<String> locationDetails(ConsoleAction action) {
    if (action.y < 0 || action.y >= _console.height) return const [];
    return [
      _console.buffer[action.y]
          .skip((action.x + action.width).clamp(0, _console.width))
          .map((cell) => cell.glyph)
          .join()
          .trim(),
    ];
  }

  String _unavailableVisit(ConsoleAction action) {
    final reason = locationDetails(action)
        .where((text) => text.isNotEmpty)
        .join(' · ');
    return reason.isEmpty
        ? 'Unavailable for this squad in the current visit planner.'
        : reason;
  }

  void showUnavailable(ConsoleAction action) {
    _message = _unavailableVisit(action);
    notifyListeners();
  }

  /// Retained pointer callbacks cannot queue a replacement target or reader.
  VoidCallback? queueCallback(Future<void> Function() onQueue) {
    final targetId = selectedDestination?.idString;
    final squadId = _squad?.id;
    final revision = _console.revision.value;
    return targetId == null || squadId == null
        ? null
        : () {
            if (!_disposed &&
                _console.revision.value == revision &&
                selectedDestination?.idString == targetId &&
                _squad?.id == squadId) {
              unawaited(onQueue());
            }
          };
  }

  Future<bool> queue({
    required bool undercover,
    required VoidCallback onPrepare,
    required VoidCallback onPrepared,
  }) async {
    if (_disposed) return false;
    final targetId = selectedDestination?.idString;
    final squadId = _squad?.id;
    if (targetId == null ||
        squadId == null ||
        _routing ||
        !_controller.canNavigate) {
      return false;
    }
    final request = _request + 1;
    await prepare(
      undercover: undercover,
      onPrepare: onPrepare,
      onPrepared: onPrepared,
    );
    if (_disposed ||
        request != _request ||
        _squad?.id != squadId ||
        selectedDestination?.idString != targetId) {
      return false;
    }
    final action = visitAction;
    return action?.enabled == true && await confirm(action!);
  }

  Future<void> prepare({
    required bool undercover,
    required VoidCallback onPrepare,
    required VoidCallback onPrepared,
  }) async {
    if (_disposed || _routing || !_controller.canNavigate || undercover) return;
    final selected = selectedDestination;
    final squadId = _squad?.id;
    final request = ++_request;
    _routing = true;
    _message = null;
    if (selected != null) _areaId = selected.district.idString;
    onPrepare();
    notifyListeners();
    bool current() =>
        !_disposed &&
        request == _request &&
        _squad?.id == squadId &&
        game.activeSquad?.id == squadId &&
        (selected == null || _targetId == selected.idString);
    try {
      if (!await _controller.openSection('f') || !current() || !_planning) {
        if (current()) {
          _message =
              _controller.message ??
              'Visit planning is unavailable for the selected squad.';
          notifyListeners();
        }
        return;
      }
      if (selected == null) return;
      final district = await _findVisitAction(
        'district',
        selected.district.idString,
        current,
      );
      if (!current() || district == null) {
        if (current()) {
          _message = 'The original planner does not offer this district to the selected squad.';
          notifyListeners();
        }
        return;
      }
      if (!district.enabled) {
        showUnavailable(district);
        return;
      }
      if (!await _controller.sendAction(
            district,
            revision: _console.revision.value,
          ) ||
          !current()) {
        return;
      }
      final destination = await _findVisitAction(
        'site',
        selected.idString,
        current,
      );
      if (!current()) return;
      _message = destination == null
          ? 'The original planner does not offer this building.'
          : destination.enabled
          ? null
          : _unavailableVisit(destination);
      notifyListeners();
    } finally {
      if (!_disposed) {
        _routing = false;
        notifyListeners();
      }
      onPrepared();
    }
  }

  Future<ConsoleAction?> _findVisitAction(
    String type,
    String id,
    bool Function() current,
  ) async {
    // The original planner retains its page on district entry. Its real page
    // controls rewind and search; no labels or painted coordinates are commands.
    final rewind = <String>{};
    while (current() && _planning) {
      final previous = _console.actions
          .where((a) => a.key == 'PageUp' && a.enabled)
          .firstOrNull;
      if (previous == null) break;
      final signature = _console.actions
          .map((a) => '${a.entityType}:${a.entityId}:${a.key}')
          .join('|');
      if (!rewind.add(signature) ||
          !await _controller.sendAction(
            previous,
            revision: _console.revision.value,
          )) {
        return null;
      }
    }
    final visited = <String>{};
    for (var page = 0; page < 256 && current() && _planning; page++) {
      final action = _console.actions
          .where((a) => a.entityType == type && a.entityId == id)
          .firstOrNull;
      if (action != null) return action;
      final signature = _console.actions
          .map((a) => '${a.entityType}:${a.entityId}:${a.key}')
          .join('|');
      if (!visited.add(signature)) break;
      final next = _console.actions
          .where((a) => a.key == 'PageDown' && a.enabled)
          .firstOrNull;
      if (next == null ||
          !await _controller.sendAction(
            next,
            revision: _console.revision.value,
          )) {
        break;
      }
    }
    return null;
  }

  Future<bool> confirm(ConsoleAction action) async {
    if (_disposed ||
        _routing ||
        selectedDestination == null ||
        !identical(action, visitAction) ||
        !action.enabled) {
      return false;
    }
    if (!await _controller.sendAction(
          action,
          revision: _console.revision.value,
        ) ||
        _disposed) {
      return false;
    }
    _message = null;
    notifyListeners();
    return true;
  }

  Future<bool> cancel() async {
    if (_disposed || _routing) return false;
    invalidate();
    if (!await _controller.returnToHeadquarters() || _disposed) return false;
    _message = null;
    notifyListeners();
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    invalidate();
    super.dispose();
  }
}
