import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/utils/game_options.dart';

KeyDownEvent characterEvent(String character) => KeyDownEvent(
  logicalKey: LogicalKeyboardKey.keyA,
  physicalKey: PhysicalKeyboardKey.keyA,
  character: character,
  timeStamp: Duration.zero,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Modern presentation bridge', () {
    late Console previousConsole;

    setUp(() {
      previousConsole = engine.console;
      engine.console = Console();
    });

    tearDown(() {
      engine.console = previousConsole;
    });

    test('plain and colored console text keep Unicode graphemes intact', () {
      engine.console.mvaddstr(0, 0, 'e\u0301👩🏽‍💻!');
      engine.console.mvaddstrx(1, 0, '&Ge\u0301👩🏽‍💻&x!');
      for (final row in [0, 1]) {
        expect(engine.console.buffer[row].take(3).map((c) => c.glyph), [
          'e\u0301',
          '👩🏽‍💻',
          '!',
        ]);
      }
    });

    test('Unicode option widths and reports use console cell columns', () {
      engine.mvaddstr(2, 0, 'A current result.');
      engine.addOptionText(4, 0, 'a', 'A - Jose\u0301👩🏽‍💻');
      final action = engine.console.actions.single;
      expect(action.width, 9);
      expect(engine.strLenX('&GJose\u0301👩🏽‍💻&x'), 5);
      expect(engine.centerString('Jose\u0301👩🏽‍💻', x: 10), 8);
      expect(engine.console.currentReportText(), 'A current result.');
    });

    test('entity inspection metadata preserves the original command', () {
      engine.addOptionText(10, 0, 'b', 'B - Warehouse', enabledWhen: false);
      final original = engine.console.actions.single;
      engine.console.annotateActionEntity(
        'b',
        type: 'site',
        id: 'Site42',
        category: 'Abandoned Warehouse',
      );
      engine.console.annotateAction('b', 'Queue a squad visit');
      final action = engine.console.actions.single;
      expect(
        (
          action.key,
          action.label,
          action.enabled,
          action.y,
          action.x,
          action.width,
        ),
        (
          original.key,
          original.label,
          original.enabled,
          original.y,
          original.x,
          original.width,
        ),
      );
      expect(action.entityType, 'site');
      expect(action.entityId, 'Site42');
      expect(action.entityCategory, 'Abandoned Warehouse');
      expect(action.intentLabel, 'Queue a squad visit');
      engine.console.replaceActions({'Enter': 'Continue'});
      expect(engine.console.actions.single.entityId, isNull);
    });

    test('entity annotations distinguish uppercase and lowercase commands', () {
      final console = engine.console;
      console.addAction('c', 'Passenger', caseSensitive: true);
      console.addAction('C', 'Drive', caseSensitive: true);
      console.annotateActionEntity('C', type: 'vehicle', id: 'Car7');
      console.annotateAction('C', 'Choose a driver');
      final driver = console.actions.singleWhere((action) => action.key == 'C');
      final passenger = console.actions.singleWhere(
        (action) => action.key == 'c',
      );
      expect(driver.entityId, 'Car7');
      expect(driver.intentLabel, 'Choose a driver');
      expect(passenger.entityId, isNull);
      expect(passenger.intentLabel, isNull);
    });

    test(
      'captures original labels, input keys, enabled state and coordinates',
      () {
        engine.addOptionText(4, 7, 'a', 'A - &GAssign&x Tasks & Equipment');
        engine.addOptionText(
          8,
          12,
          'Enter',
          'Enter - Done',
          enabledWhen: false,
        );
        expect(engine.console.actions, hasLength(2));
        final action = engine.console.actions.first;
        expect(action.key, 'a');
        expect(action.label, 'A - Assign Tasks & Equipment');
        expect(action.enabled, isTrue);
        expect((action.y, action.x), (4, 7));
        expect(action.width, action.label.length);
        final disabled = engine.console.actions.last;
        expect(disabled.key, 'Enter');
        expect(disabled.enabled, isFalse);
      },
    );

    test('normalizes named, legacy and prefixed action inputs', () {
      expect(normalizeConsoleKey('ANY OTHER KEY'), 'Enter');
      expect(normalizeConsoleKey('ESC'), 'Escape');
      expect(normalizeConsoleKey('UP'), 'Up');
      expect(normalizeConsoleKey('A - '), 'a');
      expect(normalizeConsoleKey('\x1b'), 'Escape');
      expect(normalizeConsoleKey('\x11'), 'Up');
      expect(normalizeConsoleKey(' '), 'Space');
      expect(normalizeConsoleKey('PGDN'), 'PageDown');
      expect(normalizeConsoleKey(''), '');
    });

    test('partial erasure removes intersecting controls, retaining others', () {
      engine.addOptionText(4, 3, 'a', 'A - Assign Tasks');
      engine.addOptionText(4, 40, 'b', 'B - Next');
      engine.addOptionText(8, 3, 'c', 'C - Continue');
      engine.eraseArea(startY: 4, endY: 5, startX: 12, endX: 13);
      expect(engine.console.actions.map((a) => a.key), ['b', 'c']);
      engine.eraseLine(4);
      expect(engine.console.actions.single.key, 'c');
      engine.console.screen = 'headquarters';
      engine.erase();
      expect(engine.console.actions, isEmpty);
      expect(engine.console.screen, 'generic');
    });

    test('redrawing an option replaces its original semantic action', () {
      engine.addOptionText(4, 3, 'a', 'A - Enabled');
      engine.addOptionText(4, 3, 'a', 'A - Disabled', enabledWhen: false);
      expect(engine.console.actions, hasLength(1));
      expect(engine.console.actions.single.label, 'A - Disabled');
      expect(engine.console.actions.single.enabled, isFalse);
    });

    test(
      'driver and passenger actions dispatch different case-sensitive keys',
      () async {
        engine.console.move(10, 1);
        engine.console.addAction('a', 'A - Passenger');
        engine.console.addAction('A', 'Drive the car', caseSensitive: true);
        expect(engine.console.actions.map((action) => action.key), ['a', 'A']);
        for (final action in List.of(engine.console.actions)) {
          final pending = engine.console.getkey();
          expect(engine.console.sendInput(action.key), isTrue);
          expect(await pending, action.key);
        }
      },
    );

    test(
      'consuming headquarters input expires its marker and stale actions',
      () async {
        engine.console.screen = 'headquarters';
        engine.addOptionText(21, 1, 'a', 'A - Assign Tasks');
        final pending = engine.console.getkey();
        expect(engine.console.screen, 'headquarters');
        expect(engine.console.actions, isNotEmpty);
        engine.console.sendInput('a');
        expect(await pending, 'a');
        expect(engine.console.screen, 'generic');
        expect(engine.console.actions, isEmpty);
      },
    );

    test('every flush updates revision and marks console graphics stale', () {
      int repaints = 0;
      engine.console.repaint = () => repaints++;
      engine.console.stale = false;
      engine.flush();
      engine.flush();
      expect(engine.console.revision.value, 2);
      expect(engine.console.stale, isTrue);
      expect(repaints, 2);
    });

    test(
      'text reader exposes prefill and clears context on confirmation',
      () async {
        final pending = engine.mvgetstr(4, 10, starting: 'Alice');
        expect(engine.console.textInput, isTrue);
        expect(engine.console.textInputValue, 'Alice');
        expect(engine.console.textInputLimit, 69);
        engine.console.sendInput('Backspace');
        await Future<void>.delayed(Duration.zero);
        expect(engine.console.textInputValue, 'Alic');
        engine.console.sendInput('e');
        await Future<void>.delayed(Duration.zero);
        expect(engine.console.textInputValue, 'Alice');
        engine.console.sendInput('Enter');
        expect(await pending, 'Alice');
        expect(engine.console.textInput, isFalse);
        expect(engine.console.textInputValue, isEmpty);
        expect(engine.console.textInputLimit, 0);
      },
    );

    test(
      'text reader preserves and deletes complete Unicode characters',
      () async {
        final pending = engine.mvgetstr(4, 10, starting: 'Jos');
        for (final key in ['e\u0301', '👩🏽‍💻', 'Backspace']) {
          expect(engine.console.sendInput(key), isTrue);
          await Future<void>.delayed(Duration.zero);
        }
        expect(engine.console.textInputValue, 'Jose\u0301');
        expect(engine.console.sendInput('Backspace'), isTrue);
        await Future<void>.delayed(Duration.zero);
        expect(engine.console.textInputValue, 'Jos');
        for (final key in ['e\u0301', '👩🏽‍💻', 'Enter']) {
          expect(engine.console.sendInput(key), isTrue);
          await Future<void>.delayed(Duration.zero);
        }
        expect(await pending, 'Jose\u0301👩🏽‍💻');
      },
    );

    test('erasing a frame resets pending text context', () {
      engine.console.textInput = true;
      engine.console.textInputValue = 'Old prompt';
      engine.console.textInputLimit = 20;
      engine.erase();
      expect(engine.console.textInput, isFalse);
      expect(engine.console.textInputValue, isEmpty);
      expect(engine.console.textInputLimit, 0);
    });

    test('text prompt context is cleared if rendering fails', () async {
      engine.console.repaint = () => throw StateError('Rendering failed');
      await expectLater(engine.mvgetstr(4, 10), throwsStateError);
      expect(engine.console.textInput, isFalse);
      expect(engine.console.textInputValue, isEmpty);
      expect(engine.console.textInputLimit, 0);
      expect(engine.console.awaitingInput, isFalse);
    });
  });

  group('Modern and original input delivery', () {
    test('special actions reach the original engine codes', () async {
      final console = Console();
      const expected = {
        'Enter': engine.Key.enter,
        'Escape': engine.Key.escape,
        'Backspace': engine.Key.backspace,
        'Tab': engine.Key.tab,
        'Shift': engine.Key.shift,
        'Up': engine.Key.upArrow,
        'Down': engine.Key.downArrow,
        'Left': engine.Key.leftArrow,
        'Right': engine.Key.rightArrow,
        'Space': engine.Key.space,
        'PGUP': 91,
        'PGDN': 93,
        'A': engine.Key.a,
        '7': engine.Key.num7,
      };
      for (final entry in expected.entries) {
        final key = console.getkey();
        expect(console.awaitingInput, isTrue);
        expect(console.sendInput(entry.key), isTrue);
        expect((await key).codePoint, entry.value, reason: entry.key);
        expect(console.awaitingInput, isFalse);
      }
    });

    test('original initial keyboard input is accepted once', () async {
      final console = Console();
      console.keyEvent(characterEvent('z'));
      expect(keyEventToString(await console.getKeyEvent()), 'z');
      expect(console.lastKey, isNull);
      final next = console.getkey();
      console.sendInput('b');
      expect(await next, 'b');
    });

    test('rapid taps retain first input without double completing', () async {
      final console = Console();
      final first = console.getkey();
      console.keyEvent(characterEvent('a'));
      expect(() => console.keyEvent(characterEvent('b')), returnsNormally);
      expect(await first, 'a');
      expect(console.sendInput('c'), isFalse);
      final second = console.getkey();
      expect(console.sendInput('d'), isTrue);
      expect(console.sendInput('e'), isFalse);
      expect(await second, 'd');
    });

    test(
      'input dispatched synchronously by a flush listener is accepted',
      () async {
        final console = Console();
        console.revision.addListener(() => console.sendInput('Enter'));
        expect(await console.getkey(), 'Enter');
      },
    );

    test('empty modern input cannot stall or skip the next choice', () async {
      final console = Console();
      final pending = console.getkey();
      expect(console.sendInput(''), isFalse);
      expect(console.sendInput('Escape'), isTrue);
      expect(await pending, 'Escape');
    });

    test(
      'text entry preserves letter case while action keys remain normalized',
      () async {
        final console = Console();
        final pending = console.getkey();
        expect(console.sendInput('A'), isTrue);
        expect(await pending, 'A');
        expect(normalizeConsoleKey('A'), 'a');
      },
    );
  });

  test('offscreen drawing, regions and clicks stay within the terminal', () {
    final console = Console();
    console.move(-1, 0);
    expect(() => console.addchar('a'), returnsNormally);
    console.move(0, -1);
    expect(() => console.addchar('a'), returnsNormally);
    expect(
      () => console.registerMouseRegion(-2, -2, 4, 4, 'a'),
      returnsNormally,
    );
    expect(console.buffer[0][0].mouseClickKey, 'a');
    expect(console.buffer[1][1].mouseClickKey, 'a');
    expect(console.buffer[2][2].mouseClickKey, isNull);
    expect(
      () => console.registerMouseRegion(24, 79, 9, 9, 'b'),
      returnsNormally,
    );
    expect(console.buffer[24][79].mouseClickKey, 'b');
    final mouseInput = gameOptions.mouseInput;
    gameOptions.mouseInput = true;
    try {
      expect(() => console.handleMouseClick(-1, 0), returnsNormally);
      expect(() => console.handleMouseClick(0, -1), returnsNormally);
      expect(() => console.handleMouseClick(25, 80), returnsNormally);
      expect(console.lastKey, isNull);
    } finally {
      gameOptions.mouseInput = mouseInput;
    }
  });
}
