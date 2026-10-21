import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/common_actions/equipment.dart';
import 'package:lcs_new_age/daily/shopsnstuff.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/items/clothing.dart';
import 'package:lcs_new_age/items/item.dart';
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/modern/journal_preferences.dart';
import 'package:lcs_new_age/modern/journal_shortcuts.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

Finder _action(ConsoleAction action) =>
    find.byKey(ValueKey('direct-action:${action.y}:${action.x}:${action.key}'));

Future<void> _mount(
  WidgetTester tester, {
  Size size = const Size(1280, 800),
  bool compact = false,
  double scale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  journalPresentation.value = JournalPreferenceValues(
    compact: compact,
    showGuidance: false,
  );
  journalReadingScale.value = scale;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    journalPresentation.value = const JournalPreferenceValues();
    journalReadingScale.value = 1;
  });
  await tester.pumpWidget(const MainApp());
  await tester.pumpAndSettle();
}

Future<void> _focusAction(WidgetTester tester, ConsoleAction action) async {
  final control = _action(action);
  await tester.ensureVisible(control);
  final text = find.descendant(of: control, matching: find.byType(Text)).first;
  final focus = Focus.of(tester.element(text));
  // Use deliberate traversal: incidental pointer focus must not steal Back.
  for (var step = 0; step < 100 && !focus.hasPrimaryFocus; step++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }
  expect(focus.hasPrimaryFocus, isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await ensureGameDataLoaded();
    final font = FontLoader('ModernSans');
    for (final weight in ['regular', 'medium', 'bold', 'black']) {
      font.addFont(rootBundle.load('fonts/modern/roboto-$weight.ttf'));
    }
    final original = FontLoader('SourceCodePro')
      ..addFont(rootBundle.load('fonts/SourceCodePro-Regular.ttf'));
    await Future.wait([font.load(), original.load()]);
  });

  setUp(() async {
    engine.console = Console();
    game.gameState = decodeSaveContents(
      await File('test/saves/felix_1_0.json').readAsString(),
    ).gameState!;
    game.mode = GameMode.base;
    game.activeSquadMember = null;
    journalPresentation.value = const JournalPreferenceValues();
    journalReadingScale.value = 1;
  });

  testWidgets('named shortcut badges have no independent focus stops', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              JournalShortcutBadge(shortcut: 'Enter'),
              JournalShortcutBadge(shortcut: 'Escape'),
              JournalShortcutBadge(shortcut: 'Down'),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Enter'), findsOneWidget);
    expect(find.text('Esc'), findsOneWidget);
    expect(find.text('↓'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(JournalShortcutBadge),
        matching: find.byType(Focus),
      ),
      findsNothing,
    );
    expect(journalShortcutSpokenLabel('Down'), 'Down arrow');
    expect(journalShortcutLabel('a'), 'A');
    expect(journalShortcutLabel('HQ: l'), 'HQ: L');
    expect(journalShortcutLabel('r → v'), 'R → V');
    expect(
      journalShortcutSpokenLabel('HQ: r → v'),
      'At headquarters, R, then V',
    );
    expect(journalShortcutLabel('A'), 'Shift+A');
    expect(journalShortcutSpokenLabel('A'), 'Shift A');
  });

  for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
    testWidgets(
      'focused ${key.keyLabel} activates exactly the named source choice',
      (tester) async {
        engine.console.screen = 'generic';
        engine.mvaddstr(0, 0, 'Choose a route');
        engine.addOptionText(4, 0, 'a', 'A - Visit the library');
        engine.addOptionText(7, 0, 'b', 'B - Visit the clinic');
        engine.addOptionText(24, 0, 'Enter', 'Enter - Cancel');
        final sourceAction = engine.console.actions.singleWhere(
          (action) => action.key == 'b',
        );
        final result = engine.getKey();
        await _mount(tester, compact: true);
        final before = jsonEncode(game.gameState.toJson());
        reseedRNG(seed: 671);
        final expectedRoll = Random(671).nextInt(1000000);
        await _focusAction(tester, sourceAction);
        expect(engine.console.lastKey, isNull);
        expect(jsonEncode(game.gameState.toJson()), before);
        expect(lcsRandom(1000000), expectedRoll);
        await tester.sendKeyEvent(
          key,
          character: key == LogicalKeyboardKey.space ? ' ' : null,
        );
        await tester.pumpAndSettle();
        expect(await result, engine.Key.b);
        expect(jsonEncode(game.gameState.toJson()), before);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'retained focused callback cannot activate a replacement with the same key',
    (tester) async {
      engine.console.screen = 'generic';
      engine.addOptionText(3, 0, 'a', 'A - Original choice');
      final original = engine.console.actions.single;
      final result = engine.getKey();
      await _mount(tester);
      final retained = tester.widget<TextButton>(
        find.descendant(
          of: _action(original),
          matching: find.byType(TextButton),
        ),
      );
      engine.erase();
      engine.addOptionText(3, 0, 'a', 'A - Replacement choice');
      engine.console.flush();
      await tester.pumpAndSettle();
      retained.onPressed!();
      await tester.pump();
      expect(engine.console.lastKey, isNull);
      final current = engine.console.actions.single;
      await _focusAction(tester, current);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(await result, engine.Key.a);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'equipment keyboard recipient cancellation and revisit preserve actor identity',
    (tester) async {
      game.activeSquad!.members.removeRange(2, game.squad.length);
      final first = game.squad.first;
      final second = game.squad.last;
      game.activeSquadMember = second;
      final selected = game.activeSquadMember;
      final firstOutfit = first.equippedClothing;
      final secondOutfit = second.equippedClothing;
      final outfit = Clothing('CLOTHING_CATSUIT');
      final loot = <Item>[outfit];
      var finished = false;
      unawaited(equip(loot).then((_) => finished = true));
      addTearDown(() async {
        for (var step = 0; step < 4 && !finished; step++) {
          if (engine.console.awaitingInput) engine.console.sendInput('Enter');
          await tester.pump();
        }
        expect(finished, isTrue);
      });
      await _mount(
        tester,
        size: const Size(1024, 720),
        compact: true,
        scale: 1.5,
      );
      final before = jsonEncode(game.gameState.toJson());
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA, character: 'a');
      await tester.pumpAndSettle();
      expect(engine.console.actions.map((action) => action.key), [
        '1',
        '2',
        'Enter',
      ]);
      expect(
        engine.console.actions.every((action) => action.intentLabel == null),
        isTrue,
        reason: 'Recipient keys must not retain the equipment unequip intent.',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(jsonEncode(game.gameState.toJson()), before);
      expect(first.equippedClothing, same(firstOutfit));
      expect(second.equippedClothing, same(secondOutfit));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA, character: 'a');
      await tester.pumpAndSettle();
      final recipient = engine.console.actions.singleWhere(
        (action) => action.key == '2',
      );
      await _focusAction(tester, recipient);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(first.equippedClothing, same(firstOutfit));
      expect(second.equippedClothing!.typeName, outfit.typeName);
      expect(game.activeSquadMember, same(selected));
      expect(loot, isNot(contains(outfit)));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'shop buyer choice stays keyboard reachable in enlarged compact view',
    (tester) async {
      game.activeSquad!.members.removeRange(2, game.squad.length);
      final buyer = chooseBuyerIndex(0);
      await _mount(
        tester,
        size: const Size(1024, 720),
        compact: true,
        scale: 1.5,
      );
      final before = jsonEncode(game.gameState.toJson());
      final choice = engine.console.actions.singleWhere(
        (action) => action.key == '2',
      );
      expect(
        find.descendant(of: _action(choice), matching: find.text('2')),
        findsOneWidget,
      );
      await _focusAction(tester, choice);
      await tester.sendKeyEvent(LogicalKeyboardKey.space, character: ' ');
      await tester.pumpAndSettle();
      expect(await buyer, 1);
      expect(jsonEncode(game.gameState.toJson()), before);
      expect(tester.takeException(), isNull);
    },
  );
}
