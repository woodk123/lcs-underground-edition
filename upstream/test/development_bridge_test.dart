import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activate_regulars.dart';
import 'package:lcs_new_age/devtools/development_bridge.dart';
import 'package:lcs_new_age/engine/changelog.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_support.dart';

extension BridgeResponse on Map<String, dynamic> {
  String get errorCode =>
      (this['error'] as Map<String, dynamic>)['code'] as String;
}

Map<String, dynamic> decodeResponse(String value) =>
    jsonDecode(value) as Map<String, dynamic>;

Future<Map<String, dynamic>> request(
  DevelopmentBridge bridge,
  String method, [
  Map<String, dynamic> params = const {},
]) async =>
    jsonDecode(
          await bridge.request(
            jsonEncode({'method': method, 'params': params}),
          ),
        )
        as Map<String, dynamic>;

Map<String, dynamic> firstAction(DevelopmentBridge bridge) =>
    (bridge.observe()['actions'] as List).first as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DevelopmentBridge bridge;
  String? blocked;

  setUpAll(ensureGameDataLoaded);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    engine.console = Console();
    final saved = SaveFile.fromJson(
      jsonDecode(await File('test/saves/felix_1_0.json').readAsString())
          as Map<String, dynamic>,
    );
    game.gameState = game.GameState.fromJson(saved.saveData);
    applyBugFixes(saved.version);
    blocked = null;
    bridge = DevelopmentBridge(console: () => engine.console);
    bridge.attachUi(
      Object(),
      blockedReason: () => blocked,
      inputText: (_, _) async => false,
    );
  });

  test(
    'inspection preserves campaign, reader, choices, pending input and RNG',
    () async {
      final console = engine.console;
      console.addAction('f', 'Inspect crew');
      final pending = console.getkey();
      final state = jsonEncode(game.gameState.toJson());
      final actions = List.of(console.actions);
      final completer = console.nextKeyEvent;
      final revision = console.revision.value;
      reseedRNG(seed: 9217);
      final expected = List.generate(10, (_) => lcsRandom(1000000));
      reseedRNG(seed: 9217);
      for (var i = 0; i < 3; i++) {
        expect((await request(bridge, 'observe'))['ok'], true);
        expect((await request(bridge, 'inspect'))['ok'], true);
        final context = await request(bridge, 'inspect', {'scope': 'context'});
        expect(context['ok'], true);
        final details = context['result'] as Map<String, dynamic>;
        expect((details['locations'] as List).length, game.sites.length);
        expect(
          ((details['locations'] as List).first
              as Map<String, dynamic>)['name'],
          game.sites.first.name,
        );
        expect((details['vehicles'] as List).length, game.vehiclePool.length);
        expect(
          (details['recruitment'] as List).length,
          game.recruitmentSessions.length,
        );
        expect((details['encounter'] as List).length, game.encounter.length);
        expect(
          (await request(bridge, 'inspect', {'scope': 'campaign'}))['ok'],
          true,
        );
        expect(
          (await request(bridge, 'inspect', {
            'scope': 'person',
            'personId': game.pool.first.id,
          }))['ok'],
          true,
        );
      }
      expect(jsonEncode(game.gameState.toJson()), state);
      expect(console.actions, orderedEquals(actions));
      expect(identical(console.nextKeyEvent, completer), true);
      expect(console.lastKey, isNull);
      expect(console.revision.value, revision);
      expect(console.awaitingInput, true);
      expect(List.generate(10, (_) => lcsRandom(1000000)), expected);
      console.sendInput('Enter');
      await pending;
    },
  );

  test(
    'actual source report hides retained parent actions and navigation',
    () async {
      final console = engine.console;
      console.addAction('a', r'Spend $50 on recruitment');
      console.navigation = const ConsoleNavigation(section: 'assignments');
      console.mvaddstr(10, 0, 'The recruit found the discussion insightful.');
      final state = jsonEncode(game.gameState.toJson());
      final pending = engine.acknowledge(title: 'Recruitment report');
      final observation = bridge.observe();
      final actions = (observation['actions'] as List)
          .cast<Map<String, dynamic>>();
      expect(actions, hasLength(1));
      expect(actions.single['kind'], 'acknowledgement');
      expect(observation['report'], contains('insightful'));
      expect(
        console.actions.single.key,
        'a',
        reason: 'Do not edit source metadata.',
      );
      expect(
        (await request(bridge, 'act', {
          'revision': observation['revision'],
          'actionId': actions.single['id'],
        }))['ok'],
        true,
      );
      await pending;
      expect(console.eventMessage, isNull);
      expect(jsonEncode(game.gameState.toJson()), state);
    },
  );

  test(
    'report boundary rejects captured parent and Back capabilities',
    () async {
      final console = engine.console;
      console.addAction('a', r'Spend $50 on recruitment');
      console.navigation = const ConsoleNavigation(section: 'assignments');
      final pending = console.getkey();
      final original = bridge.observe();
      final old = (original['actions'] as List).cast<Map<String, dynamic>>();
      console.eventMessage = 'A report now owns this reader.';
      for (final action in old) {
        expect(
          (await request(bridge, 'act', {
            'revision': original['revision'],
            'actionId': action['id'],
          })).errorCode,
          'stale_action',
        );
        expect(console.lastKey, isNull);
      }
      final acknowledgement = firstAction(bridge);
      expect(acknowledgement['kind'], 'acknowledgement');
      expect(
        (await request(bridge, 'act', {
          'revision': console.revision.value,
          'actionId': acknowledgement['id'],
        }))['ok'],
        true,
      );
      expect(await pending, 'Enter');
    },
  );

  test(
    'source navigation leaves the actual task roster without campaign or RNG changes',
    () async {
      final state = jsonEncode(game.gameState.toJson());
      reseedRNG(seed: 491);
      final expected = List.generate(10, (_) => lcsRandom(1000000));
      reseedRNG(seed: 491);
      final pending = activateRegulars();
      final observation = bridge.observe();
      final navigation = (observation['actions'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((action) => action['kind'] == 'source_navigation');
      expect(navigation['key'], 'Escape');
      expect(
        (await request(bridge, 'act', {
          'revision': observation['revision'],
          'actionId': navigation['id'],
        }))['ok'],
        true,
      );
      await pending;
      expect(jsonEncode(game.gameState.toJson()), state);
      expect(List.generate(10, (_) => lcsRandom(1000000)), expected);
    },
  );

  test(
    'navigation rejects replacement, explicit disabled Back and text entry',
    () async {
      final console = engine.console;
      console.addAction('f', 'Current choice');
      console.navigation = const ConsoleNavigation(section: 'assignments');
      final pending = console.getkey();
      Map<String, dynamic> navigation() => (bridge.observe()['actions'] as List)
          .cast<Map<String, dynamic>>()
          .singleWhere((action) => action['kind'] == 'source_navigation');
      final captured = navigation();
      console.navigation = ConsoleNavigation(
        section: console.navigation!.section,
      );
      expect(
        (await request(bridge, 'act', {
          'revision': console.revision.value,
          'actionId': captured['id'],
        })).errorCode,
        'stale_action',
      );
      final replacement = navigation();
      console.addAction('Escape', 'Unavailable Back', enabled: false);
      expect(
        (bridge.observe()['actions'] as List)
            .cast<Map<String, dynamic>>()
            .where((action) => action['kind'] == 'source_navigation'),
        isEmpty,
      );
      expect(
        (await request(bridge, 'act', {
          'revision': console.revision.value,
          'actionId': replacement['id'],
        })).errorCode,
        'stale_action',
      );
      console.actions.removeLast();
      console.textInput = true;
      expect(
        (await request(bridge, 'act', {
          'revision': console.revision.value,
          'actionId': replacement['id'],
        })).errorCode,
        'text_input_required',
      );
      console.textInput = false;
      final current = navigation();
      expect(
        (await request(bridge, 'act', {
          'revision': console.revision.value,
          'actionId': current['id'],
        }))['ok'],
        true,
      );
      expect(await pending, 'Escape');
    },
  );

  test(
    'exact source choice tolerates cosmetic repaint and preserves case',
    () async {
      final console = engine.console;
      console.addAction('F', 'Uppercase source choice', caseSensitive: true);
      final pending = console.getkey();
      final action = firstAction(bridge);
      final revision = console.revision.value;
      console.buffer[2][2].glyph = '~';
      expect(firstAction(bridge)['id'], action['id']);
      final response = await request(bridge, 'act', {
        'revision': revision,
        'actionId': action['id'],
      });
      expect(response['ok'], true);
      expect(await pending, 'F');
    },
  );

  test(
    'replaced, disabled, stale and concurrent choices do not dispatch',
    () async {
      final console = engine.console;
      console.addAction('f', 'Current choice');
      final pending = console.getkey();
      final action = firstAction(bridge);
      final revision = console.revision.value;
      console.actions[0] = const ConsoleAction(
        key: 'f',
        label: 'Current choice',
        enabled: true,
        y: 0,
        x: 0,
        width: 14,
      );
      expect(
        (await request(bridge, 'act', {
          'revision': revision,
          'actionId': action['id'],
        })).errorCode,
        'stale_action',
      );
      expect(console.lastKey, isNull);
      final replacement = firstAction(bridge);
      console.flush();
      expect(
        (await request(bridge, 'act', {
          'revision': revision,
          'actionId': replacement['id'],
        })).errorCode,
        'stale_revision',
      );
      console.actions[0] = const ConsoleAction(
        key: 'f',
        label: 'Disabled',
        enabled: false,
        y: 0,
        x: 0,
        width: 8,
      );
      final disabled = firstAction(bridge);
      expect(
        (await request(bridge, 'act', {
          'revision': console.revision.value,
          'actionId': disabled['id'],
        })).errorCode,
        'stale_action',
      );
      console.actions[0] = const ConsoleAction(
        key: 'f',
        label: 'Enabled',
        enabled: true,
        y: 0,
        x: 0,
        width: 7,
      );
      final enabled = firstAction(bridge);
      final params = {
        'revision': console.revision.value,
        'actionId': enabled['id'],
      };
      final accepted = request(bridge, 'act', params);
      final duplicate = await request(bridge, 'act', params);
      expect(duplicate['ok'], false);
      expect((await accepted)['ok'], true);
      expect(await pending, 'f');
      expect(console.lastKey, isNull);
    },
  );

  test(
    'UI boundary blocks modal/draft/busy input without changing reader',
    () async {
      engine.console.addAction('f', 'Source choice');
      final pending = engine.console.getkey();
      final action = firstAction(bridge);
      for (final reason in [
        'modal_open',
        'unconfirmed_draft',
        'ui_busy',
        'inspection_open',
      ]) {
        blocked = reason;
        final response = await request(bridge, 'act', {
          'revision': engine.console.revision.value,
          'actionId': action['id'],
        });
        expect(response.errorCode, 'input_blocked');
        expect(bridge.observe()['blockedReason'], reason);
        expect(engine.console.lastKey, isNull);
        expect(engine.console.awaitingInput, true);
      }
      blocked = null;
      engine.console.sendInput('Enter');
      await pending;
    },
  );

  test(
    'scoped acknowledgement cannot become a later choice or text input',
    () async {
      final console = engine.console;
      final pending = console.getkey();
      final acknowledgement = firstAction(bridge);
      expect(acknowledgement['kind'], 'acknowledgement');
      console.addAction('f', 'A consequential choice');
      expect(
        (await request(bridge, 'act', {
          'revision': console.revision.value,
          'actionId': acknowledgement['id'],
        })).errorCode,
        'stale_action',
      );
      console.actions.clear();
      final current = firstAction(bridge);
      console.textInput = true;
      expect(bridge.observe()['actions'], isEmpty);
      expect(
        (await request(bridge, 'act', {
          'revision': console.revision.value,
          'actionId': current['id'],
        })).errorCode,
        'text_input_required',
      );
      console.textInput = false;
      console.buffer[0][0].glyph = '!';
      expect(
        (await request(bridge, 'act', {
          'revision': console.revision.value,
          'actionId': current['id'],
        })).errorCode,
        'stale_action',
      );
      final fresh = firstAction(bridge);
      expect(
        (await request(bridge, 'act', {
          'revision': console.revision.value,
          'actionId': fresh['id'],
        }))['ok'],
        true,
      );
      expect(await pending, 'Enter');
    },
  );

  test('disabled gate and malformed requests cannot mutate the game', () async {
    final disabled = DevelopmentBridge(
      console: () => engine.console,
      enabled: false,
    );
    expect((await request(disabled, 'observe')).errorCode, 'disabled');
    expect(
      decodeResponse(await bridge.request('{')).errorCode,
      'invalid_request',
    );
    expect(
      (await request(bridge, 'send_key', {'key': 'f'})).errorCode,
      'unknown_method',
    );
  });

  testWidgets(
    'real shell rejects changelog/modal and replays actual source text',
    (tester) async {
      if (!developmentToolsEnabled) {
        expect(
          (await request(developmentBridge, 'observe')).errorCode,
          'disabled',
        );
        return;
      }
      engine.console.addAction('f', 'Source choice');
      final pending = engine.console.getkey();
      await tester.pumpWidget(const MainApp());
      await tester.pump();
      final action = firstAction(developmentBridge);
      ChangelogWidget.globalKey.currentState!.show('# Development bridge test');
      await tester.pump();
      expect(developmentBridge.observe()['blockedReason'], 'changelog_open');
      expect(
        (await request(developmentBridge, 'act', {
          'revision': engine.console.revision.value,
          'actionId': action['id'],
        })).errorCode,
        'input_blocked',
      );
      ChangelogWidget.globalKey.currentState!.hide();
      await tester.pump();
      unawaited(
        showDialog<void>(
          context: MainApp.navigatorKey.currentContext!,
          builder: (_) => const AlertDialog(title: Text('Read-only overlay')),
        ),
      );
      await tester.pump();
      expect(developmentBridge.observe()['blockedReason'], 'modal_open');
      expect(engine.console.lastKey, isNull);
      MainApp.navigatorKey.currentState!.pop();
      await tester.pump(const Duration(milliseconds: 400));
      engine.console.sendInput('Enter');
      await pending;
      final text = engine.mvgetstr(3, 0, starting: 'Old');
      await tester.pump();
      final revision = engine.console.revision.value;
      expect(
        (await request(developmentBridge, 'input_text', {
          'revision': revision,
          'text': 'bad\ninput',
        })).errorCode,
        'invalid_params',
      );
      expect(engine.console.textInputValue, 'Old');
      Map<String, dynamic>? result;
      unawaited(
        request(developmentBridge, 'input_text', {
          'revision': revision,
          'text': 'New é🙂',
          'submit': 'Escape',
        }).then((value) => result = value),
      );
      for (var i = 0; i < 60 && result == null; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(result?['ok'], true, reason: result.toString());
      expect(await text, 'New é🙂');
      await tester.pumpWidget(const SizedBox());
    },
  );
}
