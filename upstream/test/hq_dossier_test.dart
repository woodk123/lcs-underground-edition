import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activate_regulars.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/saveload/save_load.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String fixture;
  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
  });

  setUp(() {
    game.gameState = decodeSaveContents(fixture).gameState!;
    game.mode = GameMode.base;
    game.activeSquadMember = null;
    engine.console = Console()..screen = 'headquarters';
    engine.addOptionText(21, 0, 'a', 'A - Assign Tasks');
    engine.addOptionText(23, 0, 'w', 'W - Wait a day');
    engine.addOptionText(23, 40, 'x', 'X - Exit to the Title Screen');
  });

  Future<void> mount(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const MainApp());
    await tester.pumpAndSettle();
  }

  testWidgets(
    'HQ portrait inspection and Escape leave pending game input intact',
    (tester) async {
      final person = game.squad.first;
      final before = jsonEncode(game.gameState.toJson());
      int? received;
      final input = engine.getKey().then((value) => received = value);
      await mount(tester);
      final portrait = find.byKey(ValueKey('hq-portrait:${person.id}'));
      await tester.ensureVisible(portrait);
      await tester.tap(portrait);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('crew-inspector')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('crew-inspector')), findsNothing);
      expect(received, isNull);
      expect(find.byType(Dialog), findsNothing);
      expect(engine.console.awaitingInput, isTrue);
      expect(jsonEncode(game.gameState.toJson()), before);
      engine.console.sendInput('Enter');
      await tester.pumpAndSettle();
      await input;
    },
  );

  testWidgets('HQ dossier Select closes before one original squad command', (
    tester,
  ) async {
    final person = game.squad.first;
    final before = jsonEncode(game.gameState.toJson());
    int? received;
    final input = engine.getKey().then((value) => received = value);
    await mount(tester);
    final control = find.byKey(ValueKey('hq-dossier:${person.id}'));
    await tester.ensureVisible(control);
    await tester.tap(control);
    await tester.pumpAndSettle();
    expect(received, isNull);
    await tester.tap(find.text('Select in squad'));
    await tester.pumpAndSettle();
    await input;
    expect(find.byKey(const ValueKey('crew-inspector')), findsNothing);
    expect(received, '1'.codeUnitAt(0));
    // The real HQ handler owns selection; the dossier sends only its input.
    expect(jsonEncode(game.gameState.toJson()), before);
  });

  testWidgets(
    'Escape cancels a live text prompt before closing crew inspection',
    (tester) async {
      final person = game.squad.first;
      String? answer;
      final flow = () async {
        await engine.getKey();
        engine.erase();
        engine.mvaddstr(0, 0, 'Name your contact');
        answer = await engine.mvgetstr(4, 0);
      }();
      await mount(tester);
      await tester.tap(find.byKey(ValueKey('hq-portrait:${person.id}')));
      await tester.pumpAndSettle();
      engine.console.sendInput('a');
      await tester.pumpAndSettle();
      expect(engine.console.textInput, isTrue);
      // The required source reader uses the right page until it completes.
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byKey(const ValueKey('crew-inspector')), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await flow;
      // The real engine flushes the next awaited frame after the reader.
      engine.flush();
      await tester.pumpAndSettle();
      expect(answer, '');
      expect(engine.console.textInput, isFalse);
      expect(find.byKey(const ValueKey('crew-inspector')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a removed person leaves no invisible inspector swallowing Escape',
    (tester) async {
      final person = game.squad.first;
      int? received;
      final input = engine.getKey().then((value) => received = value);
      await mount(tester);
      await tester.tap(find.byKey(ValueKey('hq-portrait:${person.id}')));
      await tester.pumpAndSettle();
      game.pool.remove(person);
      engine.flush();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('crew-inspector')), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await input;
      expect(received, engine.Key.escape);
    },
  );

  testWidgets('a headquarters shortcut frees inspector space in one click', (
    tester,
  ) async {
    final person = game.squad.first;
    int? received;
    final input = () async {
      received = await engine.getKey();
      await activateRegulars();
    }();
    await mount(tester);
    await tester.tap(find.byKey(ValueKey('hq-portrait:${person.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('crew-inspector')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('journal-orders')));
    await tester.pumpAndSettle();
    expect(received, 'a'.codeUnitAt(0));
    expect(find.byKey(const ValueKey('crew-inspector')), findsNothing);
    engine.console.sendInput('Enter');
    await tester.pumpAndSettle();
    engine.console.sendInput('Escape');
    await tester.pumpAndSettle();
    await input;
  });
}
