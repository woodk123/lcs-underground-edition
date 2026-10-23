import 'dart:convert';

import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:lcs_new_age/devtools/report_observation.dart';
import 'package:lcs_new_age/devtools/tactical_observation.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/utils/game_version.dart';

const developmentToolsEnabled = bool.fromEnvironment('LCS_DEVTOOLS');

/// A development-only view of the real reader. It never owns gameplay rules.
final developmentBridge = DevelopmentBridge(
  console: () => engine.console,
  enabled: developmentToolsEnabled,
);

typedef DevelopmentTextInput =
    Future<bool> Function(String text, String submit);

class _Choice {
  _Choice(
    this.console,
    this.revision,
    this.action,
    this.signature, {
    this.navigation,
  }) : sourceChoices = List.of(console.actions);
  final Console console;
  final int revision;
  final ConsoleAction? action;
  final ConsoleNavigation? navigation;
  final String signature;
  final List<ConsoleAction> sourceChoices;
}

class _BridgeError implements Exception {
  _BridgeError(this.code, this.message);
  final String code, message;
}

class DevelopmentBridge {
  DevelopmentBridge({required this.console, this.enabled = true});

  final Console Function() console;
  final bool enabled;
  Object? _owner;
  String? Function()? _blocked;
  DevelopmentTextInput? _textInput;
  void Function()? _prepareSourceInput;
  bool _busy = false;
  int _nextChoice = 0;
  final Map<String, _Choice> _choices = {};

  void attachUi(
    Object owner, {
    required String? Function() blockedReason,
    required DevelopmentTextInput inputText,
    void Function()? prepareSourceInput,
  }) {
    _owner = owner;
    _blocked = blockedReason;
    _textInput = inputText;
    _prepareSourceInput = prepareSourceInput;
  }

  void detachUi(Object owner) {
    if (!identical(owner, _owner)) return;
    _owner = null;
    _blocked = null;
    _textInput = null;
    _prepareSourceInput = null;
  }

  String? get blockedReason {
    if (_busy) return 'bridge_busy';
    if (_owner == null) return 'shell_unavailable';
    final reason = _blocked?.call();
    if (reason != null) return reason;
    final current = console();
    if (!current.awaitingInput || current.lastKey != null) return 'processing';
    return null;
  }

  String _signature(Console current) => jsonEncode({
    'screen': current.screen,
    'message': current.eventMessage,
    'textInput': current.textInput,
    'text': _screenText(current),
  });

  String _screenText(Console current) => current.buffer
      .map((row) => row.map((cell) => cell.glyph).join().trimRight())
      .join('\n');

  String _choiceId(
    Console current,
    ConsoleAction? action,
    String signature, {
    ConsoleNavigation? navigation,
  }) {
    for (final entry in _choices.entries) {
      final choice = entry.value;
      if (identical(choice.console, current) &&
          choice.revision == current.revision.value &&
          identical(choice.action, action) &&
          identical(choice.navigation, navigation) &&
          choice.signature == signature) {
        return entry.key;
      }
    }
    final id = 'choice-${_nextChoice++}';
    _choices[id] = _Choice(
      current,
      current.revision.value,
      action,
      signature,
      navigation: navigation,
    );
    return id;
  }

  Map<String, dynamic> observe() {
    final current = console();
    _choices.removeWhere(
      (_, choice) =>
          !identical(choice.console, current) ||
          choice.revision != current.revision.value,
    );
    final signature = _signature(current);
    final actions = <Map<String, dynamic>>[
      if (!current.textInput && current.eventMessage == null)
        for (final action in current.actions)
          {
            'id': _choiceId(current, action, ''),
            'kind': 'source_action',
            'key': action.key,
            'label': action.label,
            'enabled': action.enabled,
            if (action.intentLabel != null) 'intentLabel': action.intentLabel,
            if (action.entityType != null) 'entityType': action.entityType,
            if (action.entityId != null) 'entityId': action.entityId,
            if (action.entityCategory != null)
              'entityCategory': action.entityCategory,
          },
      // The journal already offers Enter on authored reports, articles/maps,
      // and an empty-action reader. Capture that capability for this reader
      // only; it cannot become a generic key or Advance day command.
      if (_hasAcknowledgement(current))
        {
          'id': _choiceId(current, null, signature),
          'kind': 'acknowledgement',
          'key': 'Enter',
          'label': 'Continue',
          'enabled': true,
        },
      if (_hasNavigation(current))
        {
          'id': _choiceId(current, null, '', navigation: current.navigation),
          'kind': 'source_navigation',
          'key': current.navigation!.backKey,
          'label': 'Back',
          'enabled': true,
        },
    ];
    final report = reportObservation(current);
    return {
      'bridgeVersion': 1,
      'build': {
        'version': gameVersion,
        'channel': gameChannel,
        'source': gameBuild,
      },
      'revision': current.revision.value,
      'screen': current.screen,
      'text': _screenText(current),
      'report': report?['text'] ?? '',
      'reportContext': ?report,
      'map': ?tacticalObservation(current, actions),
      'awaitingInput': current.awaitingInput && current.lastKey == null,
      'blockedReason': blockedReason,
      'textInput': current.textInput
          ? {'value': current.textInputValue, 'limit': current.textInputLimit}
          : null,
      'navigation': current.navigation == null
          ? null
          : {
              'section': current.navigation!.section,
              'backKey': current.navigation!.backKey,
              'note': current.navigation!.note,
            },
      'actions': actions,
    };
  }

  bool _hasAcknowledgement(Console current) =>
      current.awaitingInput &&
      current.lastKey == null &&
      !current.textInput &&
      (current.eventMessage != null ||
          current.actions.isEmpty ||
          const {'article', 'full_map'}.contains(current.screen));

  bool _hasNavigation(Console current) =>
      current.awaitingInput &&
      current.lastKey == null &&
      !current.textInput &&
      current.eventMessage == null &&
      current.navigation != null &&
      current.navigation!.backKey.isNotEmpty &&
      !current.actions.any(
        (action) => action.key == current.navigation!.backKey,
      );

  Map<String, dynamic> inspect(Map<String, dynamic> params) {
    final scope = params['scope'] ?? 'summary';
    switch (scope) {
      case 'summary':
        return {
          'campaignId': game.gameState.uniqueGameId,
          'date': game.date.toIso8601String(),
          'mode': game.mode.name,
          'funds': game.ledger.funds,
          'activeSquadId': game.gameState.activeSquadId,
          'activeSiteId': game.activeSite?.id,
          'position': {'x': game.locx, 'y': game.locy, 'z': game.locz},
          'people': [
            for (final person in game.pool)
              {
                'id': person.id,
                'name': person.name,
                'alive': person.alive,
                'sleeper': person.sleeperAgent,
                'squadId': person.squadId,
                'locationId': person.locationId,
                'baseId': person.baseId,
                'activity': person.activity.type.name,
                'blood': person.blood,
                'medicalBills': person.medicalBills,
              },
          ],
          'squads': [
            for (final squad in game.squads)
              {
                'id': squad.id,
                'name': squad.name,
                'members': squad.members.map((person) => person.id).toList(),
                'activity': squad.activity.type.name,
              },
          ],
        };
      case 'campaign':
        // Detach nested generated serializer values before returning them.
        // This does not save, load, construct a campaign or touch RNG.
        return {
          'campaign': jsonDecode(jsonEncode(game.gameState.toJson())),
          'note':
              'Saved campaign fields only; tactical runtime state and RNG are not a restorable checkpoint.',
        };
      case 'context':
        // Read existing fields only. Never generate NPCs or evaluate a roll to
        // provide a convenient inspection summary.
        return {
          'activePersonId': game.activeSquadMember?.id,
          'locations': [
            for (final site in game.sites)
              {
                'id': site.id,
                'name': site.name,
                'type': site.type.name,
                'cityId': site.cityId,
                'hidden': site.hidden,
                'controller': site.controller.name,
              },
          ],
          'recruitment': [
            for (final session in game.recruitmentSessions)
              {
                'personId': session.recruit.id,
                'name': session.recruit.name,
                'recruiterId': session.recruiterId,
                'eagerness': session.eagerness,
              },
          ],
          'vehicles': [
            for (final vehicle in game.vehiclePool)
              {
                'id': vehicle.id,
                'name': vehicle.fullName(),
                'locationId': vehicle.locationId,
                'heat': vehicle.heat,
              },
          ],
          'encounter': [
            for (final person in game.encounter)
              {
                'id': person.id,
                'name': person.name,
                'alive': person.alive,
                'alignment': person.align.name,
                'blood': person.blood,
              },
          ],
          'note':
              'Existing engine state for debugging; not a player discovery or readiness prediction.',
        };
      case 'person':
        final id = params['personId'];
        if (id is! int) {
          throw _BridgeError('invalid_params', 'personId must be an integer.');
        }
        for (final person in game.pool) {
          if (person.id == id) {
            return {'person': jsonDecode(jsonEncode(person.toJson()))};
          }
        }
        throw _BridgeError(
          'person_not_found',
          'No current crew member has that ID.',
        );
      default:
        throw _BridgeError('invalid_params', 'Unknown inspection scope.');
    }
  }

  void _checkReady(Map<String, dynamic> params) {
    final revision = params['revision'];
    if (revision is! int) {
      throw _BridgeError('invalid_params', 'revision must be an integer.');
    }
    if (revision != console().revision.value) {
      throw _BridgeError(
        'stale_revision',
        'Observe the current reader before acting.',
      );
    }
    final blocked = blockedReason;
    if (blocked != null) throw _BridgeError('input_blocked', blocked);
  }

  Future<Map<String, dynamic>> _act(Map<String, dynamic> params) async {
    _checkReady(params);
    final current = console();
    if (current.textInput) {
      throw _BridgeError(
        'text_input_required',
        'Use input_text for the current entry.',
      );
    }
    final choice = _choices[params['actionId']];
    if (choice == null ||
        !identical(choice.console, current) ||
        choice.revision != current.revision.value ||
        choice.action == null &&
            choice.navigation == null &&
            choice.signature != _signature(current)) {
      throw _BridgeError(
        'stale_action',
        'Choose an action ID from the latest observation.',
      );
    }
    final action = choice.action;
    final navigation = choice.navigation;
    // Generic source acknowledgements may retain their parent menu's actions.
    // Those keys would only acknowledge the report; their old labels no longer
    // describe the current reader. Require its scoped Continue capability.
    if (current.eventMessage != null &&
        (action != null || navigation != null)) {
      throw _BridgeError(
        'stale_action',
        'Acknowledge the current report first.',
      );
    }
    if (navigation != null &&
        (!identical(navigation, current.navigation) ||
            !_hasNavigation(current))) {
      throw _BridgeError('stale_action', 'The navigation reader changed.');
    }
    if (action == null &&
        navigation == null &&
        (choice.sourceChoices.length != current.actions.length ||
            choice.sourceChoices.asMap().entries.any(
              (entry) => !identical(entry.value, current.actions[entry.key]),
            ))) {
      throw _BridgeError('stale_action', 'The acknowledgement reader changed.');
    }
    if (navigation == null &&
        (action == null
            ? !_hasAcknowledgement(current)
            : !action.enabled || !current.actions.contains(action))) {
      throw _BridgeError(
        'stale_action',
        'This source choice is no longer available.',
      );
    }
    _prepareSourceInput?.call();
    _busy = true;
    try {
      if (!current.sendInput(action?.key ?? navigation?.backKey ?? 'Enter')) {
        throw _BridgeError(
          'input_blocked',
          'The current input is already being processed.',
        );
      }
      await Future<void>.delayed(Duration.zero);
    } finally {
      _busy = false;
    }
    return {'accepted': true, 'observation': observe()};
  }

  Future<Map<String, dynamic>> _inputText(Map<String, dynamic> params) async {
    _checkReady(params);
    final current = console();
    if (!current.textInput) {
      throw _BridgeError(
        'not_text_input',
        'The reader is not requesting text.',
      );
    }
    final text = params['text'];
    final submit = params['submit'] ?? 'Enter';
    if (text is! String ||
        text.runes.any((r) => r < 32 || (r >= 127 && r <= 159)) ||
        text.characters.length > current.textInputLimit ||
        !const {'Enter', 'Escape'}.contains(submit)) {
      throw _BridgeError(
        'invalid_params',
        'Supply text within the visible limit and Enter or Escape.',
      );
    }
    _busy = true;
    try {
      if (!await _textInput!(text, submit as String)) {
        throw _BridgeError(
          'text_input_interrupted',
          'The text reader changed or input was blocked; inspect before continuing.',
        );
      }
    } finally {
      _busy = false;
    }
    return {'accepted': true, 'observation': observe()};
  }

  Future<String> request(String encoded) async {
    try {
      if (!enabled) {
        throw _BridgeError(
          'disabled',
          'Development tools are not enabled in this build.',
        );
      }
      final decoded = jsonDecode(encoded);
      if (decoded is! Map<String, dynamic> ||
          decoded['method'] is! String ||
          decoded['params'] != null &&
              decoded['params'] is! Map<String, dynamic>) {
        throw _BridgeError(
          'invalid_request',
          'Expected a method and an optional params object.',
        );
      }
      final params = (decoded['params'] as Map<String, dynamic>?) ?? {};
      final result = switch (decoded['method']) {
        'observe' => observe(),
        'inspect' => inspect(params),
        'act' => await _act(params),
        'input_text' => await _inputText(params),
        _ => throw _BridgeError(
          'unknown_method',
          'Unknown development bridge method.',
        ),
      };
      return jsonEncode({'ok': true, 'result': result});
    } on _BridgeError catch (error) {
      return jsonEncode({
        'ok': false,
        'error': {'code': error.code, 'message': error.message},
      });
    } on FormatException {
      return jsonEncode({
        'ok': false,
        'error': {
          'code': 'invalid_request',
          'message': 'Invalid JSON request.',
        },
      });
    } catch (error) {
      return jsonEncode({
        'ok': false,
        'error': {'code': 'bridge_error', 'message': error.toString()},
      });
    }
  }
}
