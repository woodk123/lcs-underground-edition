import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/main.dart';

void main() {
  setUpAll(() async {
    final font = FontLoader('ModernSans')
      ..addFont(rootBundle.load('fonts/modern/roboto-regular.ttf'));
    await font.load();
  });

  testWidgets(
    'a name prompt focuses its modern field and Escape preserves the original',
    (tester) async {
      engine.console = Console();
      engine.addOptionText(0, 0, 'n', 'New campaign');
      engine.console.screen = 'title';
      await tester.pumpWidget(const MainApp());
      await tester.pumpAndSettle();
      engine.erase();
      engine.mvaddstr(0, 0, 'What is your name?');
      final name = engine.mvgetstr(2, 0, starting: 'Alice');
      await tester.pumpAndSettle();
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
      await tester.pumpAndSettle();
      expect(await name, 'Alice');
      expect(tester.takeException(), isNull);
    },
  );
}
