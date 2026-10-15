import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/console_widget.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/modern/direct_content.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/sitemode/sitemap.dart';

void titleFrame({bool canContinue = false}) {
  engine.erase();
  engine.console.screen = 'title';
  engine.addOptionText(
    12,
    10,
    'C',
    'C - Continue Last Game',
    enabledWhen: canContinue,
  );
  engine.addOptionText(
    12,
    48,
    'L',
    'L - Load & Manage Saves',
    enabledWhen: canContinue,
  );
  engine.addOptionText(13, 10, 'N', 'N - Start a New Game');
  engine.addOptionText(13, 48, 'I', 'I - Import a Save');
  engine.addOptionText(15, 10, 'O', 'O - Gameplay Options');
}

void headquartersFrame() {
  engine.erase();
  engine.console.screen = 'headquarters';
  engine.mvaddstr(0, 0, 'Your movement');
  engine.addOptionText(
    19,
    1,
    'f',
    'F - Go Forth to Stop Evil',
    enabledWhen: false,
  );
  engine.addOptionText(19, 40, 'e', 'E - Equip Squad', enabledWhen: false);
  engine.addOptionText(20, 40, 'r', 'R - Review Assets and Form Squads');
  engine.addOptionText(21, 1, 'a', 'A - Assign Tasks');
  engine.addOptionText(21, 40, 'l', 'L - The Status of the Liberal Agenda');
  engine.addOptionText(22, 40, 'm', 'M - Media Overview & Impact');
  engine.addOptionText(23, 1, 'w', 'W - Wait a day');
  engine.addOptionText(23, 40, 'x', 'X - Exit to the Title Screen');
  engine.addOptionText(17, 20, 's', '(S - Change the Slogan)');
  game.slogan = 'Every voice counts.';
  game.ledger.forceSetFunds(1200);
}

void decisionFrame({bool choices = true}) {
  engine.erase();
  engine.mvaddstr(0, 0, 'Choose your next step');
  engine.mvaddstr(2, 0, 'Your founder is ready to build a movement.');
  if (choices) {
    engine.addOptionText(7, 1, 'a', 'A - &GCommunity work&x');
    engine.addOptionText(8, 1, 'b', 'B - Risky operation', enabledWhen: false);
    engine.addOptionText(24, 0, 'Escape', 'Escape - Back');
  }
}

Future<void> mountApp(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(const MainApp());
  await tester.pumpAndSettle();
}

Finder buttonLabel(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
);

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
    journalReadingScale.value = 1;
    engine.console = Console();
    game.gameState = game.GameState();
    game.mode = GameMode.base;
  });

  for (final size in [const Size(1280, 800), const Size(800, 600)]) {
    final viewport = '${size.width.toInt()}x${size.height.toInt()}';

    testWidgets('modern title is readable and fits $viewport', (tester) async {
      titleFrame();
      await mountApp(tester, size);
      expect(
        find.byKey(const ValueKey('journal-title-scroll')),
        findsOneWidget,
      );
      expect(find.text('Start a New Game'), findsOneWidget);
      expect(
        tester
            .widget<ButtonStyleButton>(buttonLabel('Continue Last Game'))
            .onPressed,
        isNull,
      );
      expect(find.text('Load & Manage Saves'), findsOneWidget);
      expect(
        tester
            .widget<ButtonStyleButton>(buttonLabel('Load & Manage Saves'))
            .onPressed,
        isNull,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('headquarters actions fit $viewport', (tester) async {
      headquartersFrame();
      await mountApp(tester, size);
      expect(find.text('DAILY BRIEFING'), findsOneWidget);
      expect(find.text('Wait a day'), findsOneWidget);
      expect(find.text('MOVEMENT FUNDS'), findsNothing);
      expect(find.textContaining('\$1200'), findsWidgets);
      expect(find.text('Daily assignments'), findsWidgets);
      expect(find.text('Plan an operation'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('readable decision and choices fit $viewport', (tester) async {
      decisionFrame();
      await mountApp(tester, size);
      expect(find.text('AVAILABLE CHOICES'), findsNothing);
      expect(find.byType(DirectContent), findsOneWidget);
      final centralAction = find.byKey(const ValueKey('direct-action:7:1:a'));
      expect(centralAction, findsOneWidget);
      expect(
        find.ancestor(of: centralAction, matching: find.byType(DirectContent)),
        findsOneWidget,
      );
      expect(
        tester
            .widget<TextButton>(
              find.descendant(
                of: centralAction,
                matching: find.byType(TextButton),
              ),
            )
            .onPressed,
        isNotNull,
      );
      expect(find.text('Community work'), findsOneWidget);
      expect(find.text('Risky operation'), findsOneWidget);
      expect(
        tester
            .widget<ButtonStyleButton>(buttonLabel('Risky operation'))
            .onPressed,
        isNull,
      );
      expect(
        find.descendant(
          of: find.byType(DirectContent),
          matching: find.text('Your founder is ready to build a movement.'),
        ),
        findsOneWidget,
      );
      expect(find.byType(SelectableText), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('headquarters remains readable at larger text in $viewport', (
      tester,
    ) async {
      headquartersFrame();
      await mountApp(tester, size);
      await tester.tap(find.byTooltip('Reading size'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('150%'));
      await tester.pumpAndSettle();
      expect(find.text('DAILY BRIEFING'), findsOneWidget);
      expect(find.text('Wait a day'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('new movement button forwards the original new game input', (
    tester,
  ) async {
    titleFrame();
    await mountApp(tester, const Size(1280, 800));
    String? received;
    unawaited(engine.console.getkey().then((value) => received = value));
    await tester.pump();
    await tester.tap(find.text('Start a New Game'));
    await tester.pump();
    expect(received, 'n');
    expect(engine.console.lastKey, isNull);
  });

  testWidgets('continue preserves the original saved campaign action', (
    tester,
  ) async {
    titleFrame(canContinue: true);
    await mountApp(tester, const Size(1280, 800));
    String? received;
    unawaited(engine.console.getkey().then((value) => received = value));
    await tester.pump();
    await tester.tap(find.text('Continue Last Game'));
    await tester.pump();
    expect(received, 'c');
  });

  testWidgets(
    'HQ navigation respects disabled actions and forwards assignments',
    (tester) async {
      headquartersFrame();
      await mountApp(tester, const Size(1280, 800));
      final disabledOperation = tester.widget<ButtonStyleButton>(
        buttonLabel('Plan an operation'),
      );
      expect(disabledOperation.onPressed, isNull);
      String? received;
      unawaited(engine.console.getkey().then((value) => received = value));
      await tester.pump();
      await tester.tap(find.text('Plan an operation'));
      await tester.pump();
      expect(received, isNull);
      await tester.tap(find.text('Daily assignments').first);
      await tester.pump();
      expect(received, 'a');
    },
  );

  testWidgets(
    'decision buttons preserve semantic keys after color formatting',
    (tester) async {
      decisionFrame();
      await mountApp(tester, const Size(1280, 800));
      String? received;
      unawaited(engine.console.getkey().then((value) => received = value));
      await tester.pump();
      await tester.tap(find.text('Community work'));
      await tester.pump();
      expect(received, 'a');
    },
  );

  testWidgets('guide keyboard input cannot make a game choice', (tester) async {
    titleFrame();
    await mountApp(tester, const Size(1280, 800));
    String? received;
    unawaited(engine.console.getkey().then((value) => received = value));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pumpAndSettle();
    expect(find.text('A small movement. A long game.'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN, character: 'n');
    await tester.pump();
    expect(received, isNull);
    await tester.tap(find.text('Back to the game'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN, character: 'n');
    await tester.pump();
    expect(received, 'n');
  });

  testWidgets('editing text does not send game commands before submission', (
    tester,
  ) async {
    decisionFrame();
    await mountApp(tester, const Size(1280, 800));
    String? received;
    unawaited(engine.mvgetstr(4, 0).then((value) => received = value));
    await tester.pump();
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA, character: 'a');
    await tester.pump();
    expect(
      received,
      isNull,
      reason: 'Typing in the entry field must not activate action A.',
    );
    expect(engine.console.textInputValue, isEmpty);
    engine.console.sendInput('Escape');
    await tester.pump();
  });

  testWidgets('submitted names preserve casing and reach original text entry', (
    tester,
  ) async {
    decisionFrame(choices: false);
    await mountApp(tester, const Size(1280, 800));
    String? received;
    unawaited(engine.mvgetstr(4, 0).then((value) => received = value));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'Alice');
    await tester.tap(find.text('Confirm text'));
    for (int i = 0; i < 7; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(received, 'Alice');
    expect(engine.console.textInput, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('editing a prefilled name replaces the original value', (
    tester,
  ) async {
    decisionFrame(choices: false);
    await mountApp(tester, const Size(1280, 800));
    String? received;
    unawaited(
      engine
          .mvgetstr(4, 0, starting: 'Alice')
          .then((value) => received = value),
    );
    await tester.pump();
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      'Alice',
    );
    await tester.enterText(find.byType(TextField).first, 'Avery');
    await tester.tap(find.text('Confirm text'));
    for (int i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    expect(received, 'Avery');
    expect(engine.console.textInput, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('decision menus do not expose a misleading text entry field', (
    tester,
  ) async {
    decisionFrame();
    await mountApp(tester, const Size(1280, 800));
    expect(engine.console.textInput, isFalse);
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('engine revisions switch title, headquarters and decisions', (
    tester,
  ) async {
    titleFrame();
    await mountApp(tester, const Size(1280, 800));
    expect(find.byKey(const ValueKey('journal-title-scroll')), findsOneWidget);
    headquartersFrame();
    engine.flush();
    await tester.pumpAndSettle();
    expect(find.text('DAILY BRIEFING'), findsOneWidget);
    expect(find.byKey(const ValueKey('journal-title-scroll')), findsNothing);
    decisionFrame();
    engine.flush();
    await tester.pumpAndSettle();
    expect(find.text('AVAILABLE CHOICES'), findsNothing);
    expect(find.byType(DirectContent), findsOneWidget);
    final centralAction = find.byKey(const ValueKey('direct-action:7:1:a'));
    expect(
      find.ancestor(of: centralAction, matching: find.byType(DirectContent)),
      findsOneWidget,
    );
    expect(
      tester
          .widget<TextButton>(
            find.descendant(
              of: centralAction,
              matching: find.byType(TextButton),
            ),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      find.descendant(
        of: find.byType(DirectContent),
        matching: find.text('Your founder is ready to build a movement.'),
      ),
      findsOneWidget,
    );
    expect(find.text('DAILY BRIEFING'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('classic view remains mounted and can repaint after switching', (
    tester,
  ) async {
    decisionFrame();
    await mountApp(tester, const Size(1280, 800));
    expect(find.byType(ConsoleWidget), findsNothing);
    expect(find.byType(ConsoleWidget, skipOffstage: false), findsOneWidget);
    await tester.tap(find.byTooltip('Switch readable / classic view'));
    await tester.pumpAndSettle();
    expect(find.byType(ConsoleWidget), findsOneWidget);
    engine.mvaddstr(5, 0, 'Updated original console');
    engine.flush();
    await tester.pump();
    expect(engine.console.stale, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('specialized articles keep one visible original continuation', (
    tester,
  ) async {
    engine.mvaddstr(0, 0, 'An original article');
    engine.addOptionText(24, 0, 'Any Key', 'Press Any Key to Continue');
    engine.console.showArticle(
      title: 'An original article',
      publisher: 'Cable News',
      body: 'The complete source story.',
      date: DateTime(2023, 1, 2),
    );
    String? received;
    final input = engine.console.getkey().then((value) => received = value);
    await mountApp(tester, const Size(800, 600));
    expect(engine.console.actions, isNotEmpty);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Continue').hitTestable(), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('specialized-return')));
    await tester.pump();
    await input;
    expect(received, 'Enter');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'full tactical map has one pointer return with no section shortcut',
    (tester) async {
      game.mode = GameMode.site;
      game.locx = 35;
      game.locy = 11;
      game.locz = 0;
      levelMap = List.generate(
        MAPX,
        (x) => List.generate(
          MAPY,
          (y) => List.generate(MAPZ, (z) => SiteTile(x, y, z)),
        ),
      );
      engine.console.screen = 'full_map';
      engine.mvaddstr(0, 0, 'Original floor map');
      String? received;
      final input = engine.console.getkey().then((value) => received = value);
      await mountApp(tester, const Size(800, 600));
      expect(find.text('Back to operation').hitTestable(), findsOneWidget);
      expect(find.text('Continue'), findsNothing);
      expect(find.byKey(const ValueKey('section:0')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('specialized-return')));
      await tester.pump();
      await input;
      expect(received, 'Enter');
      expect(tester.takeException(), isNull);
    },
  );
}
