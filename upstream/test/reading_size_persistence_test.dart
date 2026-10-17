import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/utils/game_options.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    journalReadingScale.value = 1;
    engine.console = Console();
  });
  tearDown(() => journalReadingScale.value = 1);

  testWidgets('reading-size menu persists its value for a later launch', (
    tester,
  ) async {
    engine.mvaddstr(0, 0, 'A current decision');
    engine.addOptionText(5, 0, 'a', 'A - A choice');
    await tester.pumpWidget(const MainApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Reading size'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('150%'));
    await tester.pumpAndSettle();
    expect(journalReadingScale.value, 1.5);
    final later = GameOptions();
    await later.load();
    expect(later.journalScale, 1.5);
    expect(
      later.fontSize,
      16,
      reason: 'Journal size must not alter Classic font size.',
    );
    expect(tester.takeException(), isNull);
  });
  test('old preferences retain the default journal size', () async {
    SharedPreferences.setMockInitialValues({'fontSize': 20.0});
    final options = GameOptions();
    await options.load();
    expect(options.journalScale, 1);
    expect(options.fontSize, 20);
  });
  test('unsupported saved journal sizes use a readable default', () async {
    SharedPreferences.setMockInitialValues({'journalReadingScale': 25.0});
    final options = GameOptions();
    await options.load();
    expect(options.journalScale, 1);
  });
}
