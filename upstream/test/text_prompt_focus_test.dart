import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/modern/journal_shortcuts.dart';

Future<void> _finishSubmission(WidgetTester tester) async {
  // The form replays its visible edits through the real mvgetstr reader.
  for (var step = 0; step < 40; step++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    final font = FontLoader('ModernSans')
      ..addFont(rootBundle.load('fonts/modern/roboto-regular.ttf'));
    await font.load();
  });

  Future<({Future<String> result})> mountPrompt(WidgetTester tester) async {
    engine.console = Console();
    engine.addOptionText(0, 0, 'n', 'New campaign');
    engine.console.screen = 'title';
    await tester.pumpWidget(const MainApp());
    await tester.pumpAndSettle();
    engine.erase();
    engine.mvaddstr(0, 0, 'What is your name?');
    final result = engine.mvgetstr(2, 0, starting: 'Alice');
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      if (engine.console.textInput) engine.console.sendInput('Escape');
      await tester.pump(const Duration(seconds: 1));
    });
    return (result: result);
  }

  testWidgets(
    'a name prompt focuses its field and Escape accepts visible edits',
    (tester) async {
      final prompt = await mountPrompt(tester);
      final field = find.byType(TextField);
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
      await tester.enterText(field, 'Avery');
      await tester.pump();
      expect(
        engine.console.textInputValue,
        'Alice',
        reason: 'Edits stay in the form until confirmed.',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _finishSubmission(tester);
      expect(await prompt.result, 'Avery');
      expect(engine.console.textInput, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'prefilled text starts at the end and physical Backspace edits it',
    (tester) async {
      final prompt = await mountPrompt(tester);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.focusNode!.hasFocus, isTrue);
      expect(
        field.controller!.selection,
        const TextSelection.collapsed(offset: 5),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(field.controller!.text, 'Alic');
      expect(engine.console.textInputValue, 'Alice');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _finishSubmission(tester);
      expect(await prompt.result, 'Alic');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Cancel edits explicitly rolls back without an Escape badge', (
    tester,
  ) async {
    final prompt = await mountPrompt(tester);
    await tester.enterText(find.byType(TextField), 'Avery');
    await tester.pump();
    final cancel = find.widgetWithText(TextButton, 'Cancel edits');
    expect(
      find.descendant(of: cancel, matching: find.byType(JournalShortcutBadge)),
      findsNothing,
    );
    await tester.tap(cancel);
    await _finishSubmission(tester);
    expect(await prompt.result, 'Alice');
    expect(engine.console.textInput, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Escape during submission cannot terminate partially replayed text',
    (tester) async {
      final prompt = await mountPrompt(tester);
      await tester.enterText(find.byType(TextField), 'Avery');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm text'));
      await tester.pump(const Duration(milliseconds: 20));
      expect(engine.console.textInput, isTrue);
      expect(
        engine.console.textInputValue,
        isNot('Alice'),
        reason: 'The source reader is partway through the visible edit replay.',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _finishSubmission(tester);
      expect(await prompt.result, 'Avery');
      expect(engine.console.textInput, isFalse);
      expect(tester.takeException(), isNull);
    },
  );
}
