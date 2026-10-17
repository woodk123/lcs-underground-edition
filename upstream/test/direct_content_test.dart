import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activate_regulars.dart';
import 'package:lcs_new_age/basemode/base_actions.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/modern/direct_content.dart';
import 'package:lcs_new_age/modern/modern_app.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/sitemode/chase_sequence.dart';
import 'package:lcs_new_age/vehicles/vehicle.dart';
import 'package:lcs_new_age/vehicles/vehicle_type.dart';

import 'test_support.dart';

Finder contentAction(ConsoleAction action) =>
    find.byKey(ValueKey('direct-action:${action.y}:${action.x}:${action.key}'));

Future<void> mountContent(
  WidgetTester tester,
  Size size,
  Future<void> engineFlow, {
  ValueChanged<String>? onAction,
}) async {
  var completed = false;
  unawaited(engineFlow.then((_) => completed = true));
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() async {
    for (var i = 0; i < 8 && !completed; i++) {
      if (engine.console.awaitingInput) engine.console.sendInput('Enter');
      await tester.pump();
    }
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: buildModernTheme(),
      home: Scaffold(
        body: Material(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ValueListenableBuilder<int>(
              valueListenable: engine.console.revision,
              builder: (context, revision, child) => DirectContent(
                console: engine.console,
                onAction:
                    onAction ??
                    (key) {
                      engine.console.sendInput(key);
                    },
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await ensureGameDataLoaded();
    final modern = FontLoader('ModernSans');
    for (final weight in ['regular', 'medium', 'bold', 'black']) {
      modern.addFont(rootBundle.load('fonts/modern/roboto-$weight.ttf'));
    }
    await modern.load();
  });
  setUp(() async {
    engine.console = Console();
    game.gameState = decodeSaveContents(
      await File('test/saves/felix_1_0.json').readAsString(),
    ).gameState!;
    game.mode = GameMode.base;
    game.activeSquadMember = null;
  });

  for (final size in [const Size(1280, 800), const Size(800, 600)]) {
    testWidgets('save rows retain dates after a separate shortcut at $size', (
      tester,
    ) async {
      engine.mvaddstr(0, 0, 'Liberal Save Game Management System');
      engine.mvaddstr(2, 0, '─' * 80);
      engine.mvaddstr(2, 4, 'IN GAME DATE');
      engine.mvaddstr(2, 20, 'LCS LEADER');
      engine.mvaddstr(2, 50, 'LAST PLAYED');
      engine.mvaddstr(2, 70, 'VERSION');
      engine.addOptionText(3, 0, 'a', 'A - ');
      engine.mvaddstr(3, 4, 'Apr 4, 2023');
      engine.mvaddstr(3, 20, 'Felix Kobayashi');
      engine.mvaddstr(3, 50, 'Oct 17, 2026');
      engine.mvaddstr(3, 70, '1.5.6');
      final flow = engine.getKey();
      await mountContent(tester, size, flow.then((_) {}));
      expect(find.text('Apr 4, 2023', findRichText: true), findsOneWidget);
      expect(find.text('Felix Kobayashi', findRichText: true), findsOneWidget);
      expect(tester.takeException(), isNull);
      engine.console.sendInput('a');
      await flow;
    });
  }

  testWidgets('Unicode option labels retain their following value', (
    tester,
  ) async {
    engine.mvaddstr(0, 0, 'Name settings');
    engine.addOptionText(4, 0, 'a', 'A - Jose\u0301👩🏽‍💻');
    engine.addstr('  Selected value');
    final flow = engine.getKey();
    await mountContent(tester, const Size(1280, 800), flow.then((_) {}));
    expect(
      find.textContaining('Jose\u0301👩🏽‍💻', findRichText: true),
      findsWidgets,
    );
    expect(
      find.textContaining('Selected value', findRichText: true),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
    engine.console.sendInput('a');
    await flow;
  });

  testWidgets('Unicode report columns preserve each complete fragment', (
    tester,
  ) async {
    engine.mvaddstr(0, 0, 'Status report');
    engine.mvaddstr(3, 1, 'Jose\u0301👩🏽‍💻  Ready to work');
    final flow = engine.getKey();
    await mountContent(tester, const Size(800, 600), flow.then((_) {}));
    expect(find.text('Jose\u0301👩🏽‍💻', findRichText: true), findsOneWidget);
    expect(find.text('Ready to work', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
    engine.console.sendInput('Enter');
    await flow;
  });

  testWidgets('chase command separators do not become card descriptions', (
    tester,
  ) async {
    printChaseOptions();
    final flow = engine.getKey();
    await mountContent(tester, const Size(1280, 800), flow.then((_) {}));
    expect(find.text(',', findRichText: true), findsNothing);
    final fight = engine.console.actions.singleWhere(
      (action) => action.key == 'f',
    );
    await tester.tap(contentAction(fight));
    await tester.pumpAndSettle();
    expect(await flow, engine.Key.f);
  });

  for (final size in [const Size(1280, 800), const Size(800, 600)]) {
    final viewport = '${size.width.toInt()}x${size.height.toInt()}';
    testWidgets(
      'real roster renders visible proportional table columns at $viewport',
      (tester) async {
        final flow = activateRegulars();
        final first = engine.console.actions.firstWhere(
          (action) => action.label.contains(game.pool.first.name),
        );
        await mountContent(tester, size, flow);
        expect(find.byKey(const ValueKey('direct-data-table')), findsOneWidget);
        for (final column in [
          'Code name',
          'Skill',
          'Health',
          'Location',
          'Activity',
        ]) {
          expect(find.text(column), findsWidgets);
        }
        final record = contentAction(first);
        expect(record, findsOneWidget);
        expect(tester.getRect(record).width, greaterThan(size.width * .75));
        final children = find.descendant(
          of: record,
          matching: find.byType(Text),
        );
        final words = tester
            .widgetList<Text>(children)
            .map(
              (widget) => widget.data ?? widget.textSpan?.toPlainText() ?? '',
            )
            .join(' ');
        expect(words, contains(game.pool.first.name));
        expect(words, contains('Homeless'));
        expect(words, contains('Laying Low'));
        final fonts = children.evaluate().map((element) {
          final text = element.widget as Text;
          return DefaultTextStyle.of(
            element,
          ).style.merge(text.style).fontFamily;
        }).toSet();
        expect(fonts, contains('JournalSerif'));
        expect(fonts, isNot(contains('SourceCodePro')));
        expect(find.byType(SelectableText), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'narrow roster uses labeled clickable records without horizontal clipping',
    (tester) async {
      final flow = activateRegulars();
      final first = engine.console.actions.firstWhere(
        (action) => action.label.contains(game.pool.first.name),
      );
      await mountContent(tester, const Size(560, 800), flow);
      expect(find.byKey(const ValueKey('direct-data-table')), findsNothing);
      final record = contentAction(first);
      expect(record, findsOneWidget);
      for (final column in ['Skill', 'Health', 'Location', 'Activity']) {
        expect(
          find.descendant(of: record, matching: find.text(column)),
          findsOneWidget,
        );
      }
      expect(tester.getRect(record).left, greaterThanOrEqualTo(0));
      expect(tester.getRect(record).right, lessThanOrEqualTo(560));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'disabled activity card remains visible and cannot dispatch a key',
    (tester) async {
      final received = <String>[];
      final flow = assignTask(game.pool.first);
      final disabled = engine.console.actions.singleWhere(
        (action) => action.label.contains('Interact with a Prisoner'),
      );
      expect(disabled.enabled, isFalse);
      await mountContent(
        tester,
        const Size(1280, 800),
        flow,
        onAction: received.add,
      );
      final control = contentAction(disabled);
      expect(control, findsOneWidget);
      await tester.ensureVisible(control);
      await tester.pumpAndSettle();
      final button = find.descendant(
        of: control,
        matching: find.byType(TextButton),
      );
      expect(tester.widget<TextButton>(button).onPressed, isNull);
      await tester.tap(control);
      await tester.pump();
      expect(received, isEmpty);
      expect(engine.console.awaitingInput, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'direct vehicle controls retain distinct passenger and driver raw keys',
    (tester) async {
      game.vehiclePool.add(Vehicle(vehicleTypes.keys.first));
      final received = <String>[];
      final flow = setVehicles();
      final passenger = engine.console.actions.singleWhere(
        (action) => action.key == 'a',
      );
      final driver = engine.console.actions.singleWhere(
        (action) => action.key == 'A',
      );
      await mountContent(
        tester,
        const Size(1280, 800),
        flow,
        onAction: received.add,
      );
      for (final action in [passenger, driver]) {
        final control = contentAction(action);
        expect(control, findsOneWidget);
        await tester.ensureVisible(control);
        await tester.pumpAndSettle();
        await tester.tap(control);
        await tester.pump();
      }
      expect(received, ['a', 'A']);
      expect(engine.console.awaitingInput, isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}
