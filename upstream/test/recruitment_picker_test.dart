import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/daily/activities/recruiting.dart';
import 'package:lcs_new_age/daily/activities/solo_activities.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/recruitment_target_picker.dart';
import 'package:lcs_new_age/saveload/save_load.dart';

import 'test_support.dart';

void main() {
  setUpAll(ensureGameDataLoaded);
  setUp(() async {
    engine.console = Console();
    journalReadingScale.value = 1;
    game.gameState = decodeSaveContents(
      await File('test/saves/felix_1_0.json').readAsString(),
    ).gameState!;
    final actor = game.pool.first;
    game.pool.removeWhere((person) => person != actor);
    actor.activity = Activity(ActivityType.recruiting);
    actor.hidingDaysLeft = 0;
    actor.vacationDaysLeft = 0;
    actor.location = actor.base;
  });

  for (final size in [
    const Size(2560, 1440),
    const Size(1920, 1080),
    const Size(1024, 720),
  ]) {
    testWidgets('daily profession picker renders and cancels at $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      engine.console.screen = 'headquarters';
      await tester.pumpWidget(const MainApp());
      await tester.pumpAndSettle();
      var finished = false;
      final flow = soloActivities(false).then((_) => finished = true);
      await tester.pump();
      expect(engine.console.awaitingInput, isTrue);
      expect(engine.console.actions.length, greaterThan(10));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final targets = recruitableCreatures;
      expect(find.textContaining(targets.first.name), findsWidgets);
      expect(find.textContaining('Meeting difficulty'), findsWidgets);
      expect(find.textContaining('Page 1 of'), findsOneWidget);
      expect(find.text('Skip recruitment today'), findsOneWidget);
      expect(find.text('Runs when you advance the day.'), findsNothing);
      expect(engine.console.recruitmentTarget, isNotNull);
      final info = find.byWidgetPredicate(
        (widget) =>
            widget is IconButton &&
            widget.tooltip == recruitmentProfessionHelp(targets.first.type),
      );
      await tester.ensureVisible(info);
      await tester.tap(info);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('Base attribute ranges:'), findsWidgets);
      expect(find.textContaining('Profession skills:'), findsWidgets);
      expect(game.pool.first.activity.idString, isNull);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('journal-management-page')),
        findsOneWidget,
      );
      journalReadingScale.value = 1.5;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('try to meet and recruit?'), findsWidgets);
      engine.console.sendInput(']');
      await tester.pumpAndSettle();
      expect(find.textContaining(targets[20].name), findsWidgets);
      expect(find.textContaining('Page 2 of'), findsOneWidget);
      expect(tester.takeException(), isNull);
      engine.console.sendInput('[');
      await tester.pumpAndSettle();
      expect(find.textContaining(targets.first.name), findsWidgets);
      engine.console.sendInput('Escape');
      await tester.pump();
      expect(finished, isTrue);
      await flow;
      expect(game.pool.first.activity.idString, isNull);
      expect(engine.console.recruitmentTarget, isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
