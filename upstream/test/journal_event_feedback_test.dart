import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/common_display/common_display.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/modern/journal_legislation.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

void main() {
  setUpAll(ensureGameDataLoaded);
  setUp(() async {
    engine.console = Console();
    journalReadingScale.value = 1;
    clearScreenOnNextMessage = false;
    game.gameState = decodeSaveContents(
      await File('test/saves/felix_1_0.json').readAsString(),
    ).gameState!;
  });

  Future<void> mount(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(const MainApp());
    await tester.pumpAndSettle();
  }

  for (final size in [const Size(1280, 720), const Size(800, 600)]) {
    testWidgets('required notice precedes stale transcript at $size / 150%', (
      tester,
    ) async {
      engine.console.screen = 'headquarters';
      engine.mvaddstr(0, 0, 'STALE CASH 999 AND OLD DAY');
      engine.mvaddstr(2, 0, 'Old party transcript');
      final before = jsonEncode(game.gameState.toJson());
      reseedRNG(seed: 1837);
      final random = lcsRandom(100000);
      reseedRNG(seed: 1837);
      var complete = false;
      final reader = showMessage(
        'Congress is acting on legislation!',
      ).then((_) => complete = true);
      await mount(tester, size);
      journalReadingScale.value = 1.5;
      await tester.pumpAndSettle();
      final message = find.byKey(
        const ValueKey('journal-current-announcement'),
      );
      expect(message, findsOneWidget);
      expect(tester.getTopLeft(message).dy, lessThan(size.height / 2));
      expect(find.textContaining('STALE CASH'), findsNothing);
      expect(find.text('Old party transcript'), findsNothing);
      expect(find.text('Continue').hitTestable(), findsOneWidget);
      expect(complete, isFalse);
      expect(jsonEncode(game.gameState.toJson()), before);
      expect(lcsRandom(100000), random);
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await reader;
      expect(complete, isTrue);
      expect(engine.console.eventMessage, isNull);
      expect(engine.console.awaitingInput, isFalse);
      expect(jsonEncode(game.gameState.toJson()), before);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final size in [const Size(1280, 720), const Size(800, 600)]) {
    testWidgets(
      'vote counts retain branch identity with blank President at $size',
      (tester) async {
        engine.mvaddstr(0, 0, 'Legislative Agenda 2023');
        engine.mvaddstr(0, 35, 'President');
        engine.mvaddstr(0, 62, 'House');
        engine.mvaddstr(0, 70, 'Senate');
        engine.mvaddstr(2, 0, 'Joint Resolution 2023-1');
        engine.mvaddstr(3, 0, 'Protect Animal Welfare');
        engine.mvaddstr(2, 62, '309 Yea');
        engine.mvaddstr(3, 62, '126 Nay');
        engine.mvaddstr(2, 70, '78 Yea');
        engine.mvaddstr(3, 70, '22 Nay');
        String? received;
        final reader = engine.console.getkey().then((key) => received = key);
        final before = jsonEncode(game.gameState.toJson());
        await mount(tester, size);
        journalReadingScale.value = 1.5;
        await tester.pumpAndSettle();
        expect(isLegislativeVoteScreen(engine.console), isTrue);
        final president = find.byKey(const ValueKey('legislation-2-president'));
        final house = find.byKey(const ValueKey('legislation-2-house'));
        final senate = find.byKey(const ValueKey('legislation-2-senate'));
        expect(
          find.descendant(of: president, matching: find.text('Pending')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: house, matching: find.text('309 Yea · 126 Nay')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: senate, matching: find.text('78 Yea · 22 Nay')),
          findsOneWidget,
        );
        engine.mvaddstr(2, 35, 'Ray Buckley');
        engine.console.flush();
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: president, matching: find.text('Ray Buckley')),
          findsOneWidget,
        );
        expect(find.text('309 Yea · 126 Nay'), findsOneWidget);
        expect(jsonEncode(game.gameState.toJson()), before);
        await tester.tap(find.text('Continue'));
        await tester.pump();
        await reader;
        expect(received, 'Enter');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
