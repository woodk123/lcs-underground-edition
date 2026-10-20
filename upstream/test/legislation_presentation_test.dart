import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/engine/legislation_context.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/modern/journal_legislation.dart';
import 'package:lcs_new_age/modern/journal_shortcuts.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/politics/congress.dart';
import 'package:lcs_new_age/politics/laws.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

void main() {
  setUpAll(() async {
    await ensureGameDataLoaded();
    final serif = FontLoader('JournalSerif')
      ..addFont(rootBundle.load('fonts/journal/LibreBaskerville-Variable.ttf'));
    final sans = FontLoader('ModernSans')
      ..addFont(rootBundle.load('fonts/modern/roboto-regular.ttf'));
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await Future.wait([serif.load(), sans.load(), icons.load()]);
  });
  setUp(() async {
    engine.console = Console();
    journalReadingScale.value = 1;
    game.gameState = decodeSaveContents(
      await File('test/saves/felix_1_0.json').readAsString(),
    ).gameState!;
  });

  for (final outcome in ['signed', 'overridden', 'vetoed', 'defeated']) {
    final blocked = outcome == 'defeated';
    final enacted = outcome == 'signed' || outcome == 'overridden';
    test(
      'Congress retains illustrated reports at every pause; $outcome',
      () async {
        reseedRNG(seed: 761);
        for (final law in Law.values) {
          game.laws[law] = blocked
              ? DeepAlignment.eliteLiberal
              : DeepAlignment.moderate;
        }
        game.politics.house.fillRange(
          0,
          game.house.length,
          DeepAlignment.eliteLiberal,
        );
        game.politics.senate.fillRange(
          0,
          game.senate.length,
          DeepAlignment.eliteLiberal,
        );
        if (outcome == 'vetoed') {
          game.politics.house.fillRange(
            260,
            game.house.length,
            DeepAlignment.archConservative,
          );
          game.politics.senate.fillRange(
            60,
            game.senate.length,
            DeepAlignment.archConservative,
          );
        }
        for (final office in game.exec.keys) {
          game.exec[office] = outcome == 'signed' || blocked
              ? DeepAlignment.eliteLiberal
              : DeepAlignment.archConservative;
        }
        game.politics.supremeCourtPurged = true;
        final stages = <LegislationStage>[];
        final proposals = <LegislationBill>[];
        void respond() {
          if (!engine.console.awaitingInput || engine.console.lastKey != null) {
            return;
          }
          final frame = engine.console.legislation;
          if (frame != null) {
            expect(engine.console.eventMessage, isNull);
            expect(isLegislativeVoteScreen(engine.console), isTrue);
            stages.add(frame.stage);
            if (frame.stage == LegislationStage.agenda) {
              proposals.addAll(frame.bills);
            }
            if (frame.stage == LegislationStage.results) {
              expect(frame.bills.every((bill) => bill.outcome != null), isTrue);
              for (final bill in frame.bills) {
                expect(bill.enacted, enacted);
                expect(game.laws[bill.law], enacted ? bill.after : bill.before);
                expect(bill.outcome, switch (outcome) {
                  'signed' => 'Signed into law',
                  'overridden' => 'Veto overridden · enacted',
                  'vetoed' => 'Vetoed · law unchanged',
                  _ => 'Defeated in Congress',
                });
              }
            }
          }
          engine.console.sendInput('Enter');
        }

        engine.console.revision.addListener(respond);
        try {
          await congress().timeout(const Duration(seconds: 30));
        } finally {
          engine.console.revision.removeListener(respond);
        }
        expect(proposals, isNotEmpty);
        expect(
          stages,
          blocked
              ? [LegislationStage.agenda, LegislationStage.results]
              : [
                  LegislationStage.agenda,
                  LegislationStage.votes,
                  LegislationStage.results,
                ],
        );
        expect(engine.console.legislation, isNull);
        engine.console.erase();
        expect(isLegislativeVoteScreen(engine.console), isFalse);
      },
    );
  }

  for (final size in [
    const Size(1280, 800),
    const Size(800, 600),
    const Size(390, 844),
  ]) {
    testWidgets('journal legislation keeps one source continuation at $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      engine.console.screen = 'headquarters';
      await tester.pumpWidget(const MainApp());
      await tester.pumpAndSettle();
      engine.erase();
      engine.console.legislation = LegislationContext(2023);
      engine.mvaddstr(0, 0, 'Legislative Agenda 2023');
      engine.addOptionText(24, 0, 'Enter', 'Enter - Continue');
      final reader = engine.getKey();
      await tester.pumpAndSettle();
      if (size.width == 800) journalReadingScale.value = 1.5;
      await tester.pumpAndSettle();
      expect(find.text('Watch the votes').hitTestable(), findsOneWidget);
      expect(
        tester
            .widget<JournalShortcutBadge>(
              find.descendant(
                of: find.byKey(const ValueKey('journal-legislation-continue')),
                matching: find.byType(JournalShortcutBadge),
              ),
            )
            .shortcut,
        engine.console.actions.single.key,
      );
      expect(find.text('Continue'), findsNothing);
      expect(find.byKey(const ValueKey('journal-advance-day')), findsNothing);
      await tester.tap(find.text('Watch the votes'));
      await tester.pump();
      expect(await reader, engine.Key.enter);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'illustrated outcome explains enacted and rejected changes at $size',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final frame = LegislationContext(2023)
          ..stage = LegislationStage.results;
        frame.bills.addAll([
          LegislationBill(
              law: Law.healthcare,
              before: DeepAlignment.moderate,
              after: DeepAlignment.liberal,
            )
            ..enacted = true
            ..outcome = 'Signed into law',
          LegislationBill(
            law: Law.freeSpeech,
            before: DeepAlignment.moderate,
            after: DeepAlignment.conservative,
          )..outcome = 'Vetoed · law unchanged',
        ]);
        engine.console.legislation = frame;
        engine.mvaddstr(0, 0, 'Legislative Agenda 2023');
        engine.mvaddstr(0, 35, 'President');
        engine.mvaddstr(0, 62, 'House');
        engine.mvaddstr(0, 70, 'Senate');
        engine.mvaddstr(2, 35, 'Signed');
        engine.mvaddstr(5, 35, '*** VETO ***');
        for (var i = 0; i < 2; i++) {
          engine.mvaddstr(2 + i * 3, 0, 'Joint Resolution 2023-${i + 1}');
          engine.mvaddstr(2 + i * 3, 62, '276 Yea');
          engine.mvaddstr(3 + i * 3, 62, '159 Nay');
          engine.mvaddstr(2 + i * 3, 70, '71 Yea');
          engine.mvaddstr(3 + i * 3, 70, '29 Nay');
        }
        final reader = engine.console.getkey();
        final before = jsonEncode(game.gameState.toJson());
        final boundary = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(key: boundary, child: const MainApp()),
        );
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          for (final asset in [
            'assets/modern/site_atlas_3_v1.webp',
            JournalPalette.paperAsset,
            JournalPalette.leatherAsset,
          ]) {
            await precacheImage(AssetImage(asset), boundary.currentContext!);
          }
        });
        await tester.pumpAndSettle();
        if (size.width == 800) journalReadingScale.value = 1.5;
        await tester.pumpAndSettle();
        expect(find.byType(JournalLegislationView), findsOneWidget);
        expect(find.text('Signed into law'), findsOneWidget);
        expect(find.text('Now in force'), findsOneWidget);
        expect(
          find.textContaining('Hospital treatment becomes cheaper'),
          findsOneWidget,
        );
        expect(find.text('Vetoed · law unchanged'), findsOneWidget);
        expect(find.text('This change did not take effect.'), findsOneWidget);
        expect(
          find.text('Return to the campaign').hitTestable(),
          findsOneWidget,
        );
        expect(jsonEncode(game.gameState.toJson()), before);
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('CAPTURE_LEGISLATION') &&
            size.width == 1280) {
          await tester.runAsync(() async {
            final image =
                await (boundary.currentContext!.findRenderObject()!
                        as RenderRepaintBoundary)
                    .toImage();
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await Directory(
              '../.local/legislation-review',
            ).create(recursive: true);
            await File(
              '../.local/legislation-review/outcome.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.tap(find.text('Return to the campaign'));
        await tester.pump();
        expect(await reader, 'Enter');
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'a legislative continuation cannot reach a replaced source stage',
    (tester) async {
      engine.console.legislation = LegislationContext(2023);
      engine.addOptionText(24, 0, 'Enter', 'Enter - Continue');
      final first = engine.getKey();
      final sent = <String>[];
      Future<void> mount() => tester.pumpWidget(
        MaterialApp(
          theme: buildJournalTheme(),
          home: Scaffold(
            body: JournalLegislationView(
              console: engine.console,
              onAction: sent.add,
            ),
          ),
        ),
      );
      await mount();
      await tester.pumpAndSettle();
      final control = find.byKey(
        const ValueKey('journal-legislation-continue'),
      );
      final retained = tester.widget<FilledButton>(control).onPressed!;
      retained();
      expect(sent, ['Enter']);
      engine.console.sendInput('Enter');
      await tester.pump();
      expect(await first, engine.Key.enter);
      engine.erase();
      engine.console.legislation = LegislationContext(2023)
        ..stage = LegislationStage.results;
      engine.addOptionText(24, 0, 'Enter', 'Enter - Return');
      final second = engine.getKey();
      await mount();
      await tester.pumpAndSettle();
      retained();
      expect(sent, ['Enter']);
      expect(engine.console.lastKey, isNull);
      tester.widget<FilledButton>(control).onPressed!();
      expect(sent, ['Enter', 'Enter']);
      engine.console.sendInput('Enter');
      await tester.pump();
      expect(await second, engine.Key.enter);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );
}
