import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/main.dart';

Future<void> mountTitle(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 800);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  engine.console.screen = 'title';
  engine.addOptionText(13, 10, 'N', 'N - Start a New Game');
  await tester.pumpWidget(const MainApp());
  await tester.pumpAndSettle();
}

Future<void> tabTo(WidgetTester tester, Finder label) async {
  final node = Focus.of(tester.element(label));
  for (var attempt = 0; attempt < 20 && !node.hasPrimaryFocus; attempt++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }
  expect(
    node.hasPrimaryFocus,
    isTrue,
    reason: 'Tab navigation must reach the visible control.',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final modern = FontLoader('ModernSans');
    for (final weight in ['regular', 'medium', 'bold', 'black']) {
      modern.addFont(rootBundle.load('fonts/modern/roboto-$weight.ttf'));
    }
    final original = FontLoader('SourceCodePro')
      ..addFont(rootBundle.load('fonts/SourceCodePro-Regular.ttf'));
    await Future.wait([modern.load(), original.load()]);
  });

  setUp(() {
    engine.console = Console();
    game.gameState = game.GameState();
  });

  for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
    testWidgets('Tab then ${key.keyLabel} activates the focused game choice', (
      tester,
    ) async {
      await mountTitle(tester);
      String? received;
      unawaited(engine.console.getkey().then((value) => received = value));
      await tester.pump();
      await tabTo(tester, find.text('Start a New Game'));
      await tester.sendKeyEvent(
        key,
        character: key == LogicalKeyboardKey.space ? ' ' : null,
      );
      await tester.pump();
      expect(received, 'n');
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  }

  for (final (key, command) in [
    (LogicalKeyboardKey.pageUp, '['),
    (LogicalKeyboardKey.pageDown, ']'),
  ]) {
    testWidgets('${key.keyLabel} forwards the original pagination command', (
      tester,
    ) async {
      await mountTitle(tester);
      String? received;
      unawaited(engine.console.getkey().then((value) => received = value));
      await tester.pump();
      await tester.sendKeyEvent(key);
      await tester.pump();
      expect(received, command);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  }

  testWidgets(
    'Tab then Enter opens the focused field guide without game input',
    (tester) async {
      await mountTitle(tester);
      String? received;
      unawaited(engine.console.getkey().then((value) => received = value));
      await tester.pump();
      await tabTo(tester, find.text('How to play'));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('A small movement. A long game.'), findsOneWidget);
      expect(received, isNull);
      await tester.tap(find.text('Back to the game'));
      await tester.pumpAndSettle();
      engine.console.sendInput('Escape');
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'Tab skips the hidden classic mobile keyboard without game input',
    (tester) async {
      await mountTitle(tester);
      String? received;
      unawaited(engine.console.getkey().then((value) => received = value));
      await tester.pump();
      await tabTo(tester, find.text('Start a New Game'));
      expect(
        received,
        isNull,
        reason: 'Traversing the modern UI must not focus hidden legacy input.',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(received, 'n');
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets('text prompt confirmation submits the visible edited name', (
    tester,
  ) async {
    await mountTitle(tester);
    engine.erase();
    engine.mvaddstr(0, 0, 'Name your founder');
    String? received;
    unawaited(
      engine.mvgetstr(4, 0, starting: 'Alice').then((v) => received = v),
    );
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'Avery');
    await tester.tap(find.text('Confirm text'));
    for (var step = 0; step < 15; step++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(received, 'Avery');
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
