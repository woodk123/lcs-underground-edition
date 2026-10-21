import 'package:flutter/foundation.dart';
import 'package:lcs_new_age/engine/base_management_context.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/organisation_context.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/modern/organisation_controller.dart';

/// Routes only through current, source-authored actions. Selecting a base in
/// the journal is local; opening its investment reader uses original Next
/// Location actions so the source owns its active safehouse and all purchases.
class BaseManagementController extends ChangeNotifier {
  BaseManagementController({required this.organisation}) {
    organisation.addListener(_notify);
  }
  final OrganisationController organisation;
  Console get console => organisation.console;
  bool _busy = false;
  bool _disposed = false;
  String? _message;
  bool get busy => _busy || organisation.busy;
  String? get message => _message ?? organisation.message;

  static bool ownsScreen(Console console) =>
      console.awaitingInput &&
      !console.textInput &&
      console.eventMessage == null &&
      switch (console.screen) {
        'base-investment' => console.navigation?.section == 'bases',
        'equipment-transfer' => console.navigation?.section == 'equipment',
        'base-assignment' => console.navigation?.section == 'people',
        _ => false,
      };

  Future<bool> openInvestment(int siteId) => _run(() async {
    final site = organisationBases()
        .where((site) => site.id == siteId)
        .firstOrNull;
    if (site == null) return _fail('This location is no longer an LCS base.');
    final reason = baseInvestmentUnavailableReason(site);
    if (reason != null) return _fail(reason);
    if (!await _openBaseHeadquarters(siteId, requireUnselectedSquad: true)) {
      return false;
    }
    return await _sendKey('i') && console.screen == 'base-investment';
  });

  Future<bool> openFlags(int siteId, {required String expectedLabel}) =>
      _run(() async {
        if (!await _openBaseHeadquarters(siteId)) return false;
        final action = _action('p');
        if (action == null ||
            action.label != stripConsoleColors(expectedLabel).trim() ||
            !action.enabled) {
          return _fail('The flag action has changed. Choose it again.');
        }
        return _send(action);
      });

  Future<bool> _openBaseHeadquarters(
    int siteId, {
    bool requireUnselectedSquad = false,
  }) async {
    if (!organisationBases().any((site) => site.id == siteId)) {
      return _fail('This location is no longer an LCS base.');
    }
    if (!await organisation.returnToHeadquarters()) return false;
    final maxSteps = organisationBases().length + 1;
    for (var step = 0; step < maxSteps; step++) {
      if ((!requireUnselectedSquad || game.activeSquad == null) &&
          (game.activeSquad?.site ?? game.activeSafehouse)?.id == siteId) {
        return true;
      }
      if (console.screen != 'headquarters' || !await _sendKey('z')) {
        return false;
      }
    }
    return _fail('The selected base has changed. Choose it again.');
  }

  Future<bool> openStores() => _run(() async {
    final reason = storesUnavailableReason();
    if (reason != null) return _fail(reason);
    if (!await organisation.openSection('r')) return false;
    // The original overview pages equipment after the squads. Never send 8
    // to a screen merely because its painted text resembles the overview.
    for (var step = 0; step < (game.squads.length + 8) ~/ 19 + 2; step++) {
      if (organisationOverviewFrame(console) == null) break;
      final equipment = _action('8');
      if (equipment != null && equipment.enabled) {
        return await _send(equipment) && console.screen == 'equipment-transfer';
      }
      // The original overview handles the printed page keys in reverse.
      // Follow the same source key route as OrganisationController for squads.
      final next = console.actions
          .where(
            (action) =>
                action.enabled && action.label.contains('Previous Page'),
          )
          .firstOrNull;
      if (next == null || !await _send(next)) break;
    }
    return _fail('The current equipment reader is unavailable.');
  });

  Future<bool> openSquadlessAssignment() => _run(() async {
    final reason = baseAssignmentUnavailableReason();
    if (reason != null) return _fail(reason);
    if (!await organisation.openSection('r') ||
        organisationOverviewFrame(console) == null) {
      return false;
    }
    return await _sendKey('t') && console.screen == 'base-assignment';
  });

  Future<bool> sendAction(ConsoleAction action, {required int revision}) =>
      _run(() => organisation.sendAction(action, revision: revision));

  Future<bool> closeSource() => _run(organisation.returnToHeadquarters);

  ConsoleAction? _action(String key) => console.actions
      .where((action) => action.key == normalizeConsoleKey(key))
      .firstOrNull;

  Future<bool> _sendKey(String key) async {
    final action = _action(key);
    if (action == null || !action.enabled) {
      return _fail('That action is unavailable in the current source menu.');
    }
    return _send(action);
  }

  Future<bool> _send(ConsoleAction action) =>
      organisation.sendAction(action, revision: console.revision.value);

  Future<bool> _run(Future<bool> Function() action) async {
    if (busy || _disposed) return false;
    _busy = true;
    _message = null;
    _notify();
    try {
      return await action();
    } finally {
      _busy = false;
      _notify();
    }
  }

  bool _fail(String message) {
    _message = message;
    return false;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    organisation.removeListener(_notify);
    super.dispose();
  }
}
