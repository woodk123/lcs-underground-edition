import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' hide Alignment;
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/daily/recruitment.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/engine/recruitment_context.dart';
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/modern/direct_content.dart';
import 'package:lcs_new_age/modern/modern_app.dart';
import 'package:lcs_new_age/modern/recruitment_card.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/saveload/save_load.dart';

import 'test_support.dart';

void main() {
  setUpAll(ensureGameDataLoaded);
  setUp(() async {
    engine.console = Console();
    game.gameState = decodeSaveContents(
      await File('test/saves/felix_1_0.json').readAsString(),
    ).gameState!;
  });

  Creature prospect() =>
      Creature.fromJson(
          jsonDecode(jsonEncode(game.pool.first)) as Map<String, dynamic>,
        )
        ..id = 1234
        ..name = 'Morgan Rivers'
        ..typeId = 'CREATURE_LAWYER'
        ..rawSkill = {
          Skill.law: 7,
          Skill.business: 4,
          Skill.persuasion: 4,
          Skill.art: 1,
        };

  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    double width = 1000,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildModernTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  test(
    'skill summary uses real positive levels, stable ties and no mutation',
    () {
      final p = prospect();
      final before = jsonEncode(p);
      expect(recruitmentStrengths(p), [
        Skill.law,
        Skill.business,
        Skill.persuasion,
      ]);
      expect(
        recruitmentBackground(p),
        contains('Law, Business and Persuasion'),
      );
      expect(recruitmentBackground(p), contains('Lawyer'));
      expect(jsonEncode(p), before);
      p.rawSkill.clear();
      expect(recruitmentStrengths(p), isEmpty);
      expect(recruitmentBackground(p), contains('no trained skills'));
    },
  );

  for (final width in [320.0, 800.0, 1600.0]) {
    testWidgets('card is readable at $width with large text and long names', (
      tester,
    ) async {
      final alignment = Alignment.values[[320.0, 800.0, 1600.0].indexOf(width)];
      final label =
          alignment.name[0].toUpperCase() + alignment.name.substring(1);
      final p = prospect()
        ..name = 'Alexandria Montgomery-Worthington'
        ..align = alignment;
      final personBefore = jsonEncode(p);
      final before = jsonEncode(game.gameState);
      var inspected = false;
      await mount(
        tester,
        RecruitmentCard(
          person: p,
          recruiter: game.pool.first,
          onInspect: () => inspected = true,
        ),
        width: width,
        scale: 1.5,
      );
      expect(find.text('Law 7'), findsOneWidget);
      expect(find.text('Business 4'), findsOneWidget);
      expect(find.text('Persuasion 4'), findsOneWidget);
      expect(find.text('Art 1'), findsNothing);
      expect(
        find.text('Lawyer · Age ${p.age} · $label', findRichText: true),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Inspect ${p.name}'));
      await tester.tap(find.text('Inspect ${p.name}'));
      expect(inspected, isTrue);
      expect(jsonEncode(game.gameState), before);
      expect(jsonEncode(p), personBefore);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'candidate card dispatches only its existing enabled reader action',
    (tester) async {
      final p = prospect();
      engine.addOptionText(12, 0, 'A', 'A - Morgan Rivers');
      engine.addOptionText(
        14,
        0,
        'Enter/Escape',
        'Enter/Escape - Call it a day',
      );
      engine.console.recruitment = RecruitmentContext(
        recruiter: game.pool.first,
        prospects: [RecruitmentProspect(p, choiceKey: 'A')],
      );
      final sent = <String>[];
      await mount(
        tester,
        DirectContent(console: engine.console, onAction: sent.add),
      );
      expect(find.byType(RecruitmentCard), findsOneWidget);
      await tester.tap(find.text('A · Meet Morgan Rivers'));
      expect(sent, ['a']);
      expect(find.textContaining('Call it a day'), findsWidgets);
      engine.console.erase();
      expect(engine.console.recruitment, isNull);
    },
  );

  testWidgets('disabled or missing reader commands cannot be invoked by card', (
    tester,
  ) async {
    final p = prospect();
    engine.addOptionText(12, 0, 'A', 'A - Morgan Rivers', enabledWhen: false);
    engine.console.recruitment = RecruitmentContext(
      recruiter: game.pool.first,
      prospects: [RecruitmentProspect(p, choiceKey: 'A')],
    );
    final sent = <String>[];
    await mount(
      tester,
      DirectContent(console: engine.console, onAction: sent.add),
    );
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'A · Meet Morgan Rivers'),
    );
    expect(button.onPressed, isNull);
    expect(sent, isEmpty);
  });

  testWidgets(
    'prospect dossier opens without crew membership or engine input',
    (tester) async {
      final p = prospect();
      engine.console.recruitment = RecruitmentContext(
        recruiter: game.pool.first,
        prospects: [RecruitmentProspect(p, choiceKey: 'Z')],
      );
      final before = jsonEncode(game.gameState);
      final sent = <String>[];
      await mount(
        tester,
        DirectContent(console: engine.console, onAction: sent.add),
      );
      expect(find.byType(FilledButton), findsNothing);
      await tester.tap(find.text('Inspect Morgan Rivers'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(sent, isEmpty);
      expect(jsonEncode(game.gameState), before);
      await tester.tap(find.text('Close dossier'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(engine.console.recruitment, isNotNull);
    },
  );

  testWidgets(
    'real follow-up reader exposes prospect and clears context on exit',
    (tester) async {
      final p = prospect();
      final recruiter = game.pool.first;
      recruiter.meetings = 0;
      recruiter.location = game.locationMap.values.first;
      p.location = recruiter.location;
      final session = RecruitmentSession.fromJson({
        'recruit': jsonDecode(jsonEncode(p)),
        'recruiter': recruiter.id,
        'rawEagerness': 0,
      })..recruiter = recruiter;
      final flow = completeRecruitMeeting(session, recruiter);
      await tester.pump();
      expect(engine.console.recruitment!.prospects.single.person.id, p.id);
      expect(engine.console.recruitment!.followUp, isTrue);
      await mount(
        tester,
        DirectContent(
          console: engine.console,
          onAction: engine.console.sendInput,
        ),
      );
      expect(find.text('Get to know your prospect'), findsOneWidget);
      expect(find.textContaining("isn't ready to join"), findsWidgets);
      engine.console.sendInput('d');
      await tester.pump();
      expect(await flow, isTrue);
      expect(engine.console.recruitment, isNull);
      expect(game.pool.any((person) => person.id == p.id), isFalse);
    },
  );

  for (final paid in [false, true]) {
    for (final size in [const Size(1280, 800), const Size(800, 600)]) {
      testWidgets(
        '${paid ? 'paid' : 'free'} recruitment results replace stale choices at $size',
        (tester) async {
          game.mode = GameMode.base;
          final p = prospect();
          final recruiter = game.pool.first..meetings = 0;
          p.location = recruiter.location;
          game.ledger.forceSetFunds(100);
          final session = RecruitmentSession.fromJson({
            'recruit': jsonDecode(jsonEncode(p)),
            'recruiter': recruiter.id,
            'rawEagerness': 0,
          })..recruiter = recruiter;
          var done = false;
          final flow = completeRecruitMeeting(session, recruiter).then((value) {
            done = true;
            return value;
          });
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          try {
            await tester.pumpWidget(const MainApp());
            await tester.pumpAndSettle();
            expect(engine.console.sendInput(paid ? 'a' : 'b'), isTrue);
            await tester.pumpAndSettle();
            expect(engine.console.eventTitle, 'Recruitment report');
            expect(engine.console.eventMessage, contains(recruiter.name));
            expect(game.ledger.funds, paid ? 50 : 100);
            expect(
              find.textContaining('Spend \$50', findRichText: true),
              findsNothing,
            );
            for (var i = 0; i < 5 && !done; i++) {
              expect(engine.console.eventMessage, isNotNull);
              final continueButton = find.text('Continue').first;
              await tester.ensureVisible(continueButton);
              await tester.tap(continueButton);
              await tester.pumpAndSettle();
            }
            expect(done, isTrue);
            expect(
              game.ledger.funds,
              paid ? 50 : 100,
              reason: 'Acknowledgement must never repeat the purchase.',
            );
            expect(tester.takeException(), isNull);
          } finally {
            for (var i = 0; i < 10 && !done; i++) {
              if (engine.console.awaitingInput) {
                engine.console.sendInput('Enter');
              }
              await tester.pump();
            }
            if (done) await flow;
            await tester.pumpWidget(const SizedBox.shrink());
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          }
        },
      );
    }
  }
}
