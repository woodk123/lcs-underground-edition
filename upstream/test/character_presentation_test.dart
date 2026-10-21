import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/creature/attributes.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/engine/journal_context.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/modern/character_attributes.dart';
import 'package:lcs_new_age/modern/crew_dossier.dart';
import 'package:lcs_new_age/modern/crew_portrait.dart';
import 'package:lcs_new_age/modern/journal_person_summary.dart';
import 'package:lcs_new_age/modern/journal_preferences.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/recruitment_card.dart';
import 'package:lcs_new_age/modern/recruitment_target_picker.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

void main() {
  setUpAll(ensureGameDataLoaded);
  setUp(() async {
    engine.console = Console();
    game.gameState = decodeSaveContents(
      await File('test/saves/felix_1_0.json').readAsString(),
    ).gameState!;
  });

  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    bool compact = true,
    bool guidance = false,
    Size size = const Size(1280, 800),
    double scale = 1,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: buildJournalTheme(),
        builder: (context, child) => JournalPreferences(
          compact: compact,
          showGuidance: guidance,
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        ),
        home: Scaffold(body: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> activateInfo(WidgetTester tester, Finder button) async {
    await tester.ensureVisible(button);
    final icon = find.descendant(
      of: button,
      matching: find.byIcon(Icons.info_outline),
    );
    final focus = Focus.of(tester.element(icon));
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
  }

  test(
    'graphical attributes share classic display order without enum changes',
    () {
      expect(characterAttributeDisplayOrder, [
        Attribute.heart,
        Attribute.intelligence,
        Attribute.wisdom,
        Attribute.agility,
        Attribute.strength,
        Attribute.charisma,
      ]);
      expect(Attribute.values.first, Attribute.strength);
      final help = recruitmentProfessionHelp(game.pool.first.type);
      final attributes = characterAttributeDisplayOrder
          .where(game.pool.first.type.attributePoints.containsKey)
          .toList();
      for (var i = 1; i < attributes.length; i++) {
        String label(Attribute a) =>
            '${a.name[0].toUpperCase()}${a.name.substring(1)} ';
        expect(
          help.indexOf(label(attributes[i - 1])),
          lessThan(help.indexOf(label(attributes[i]))),
        );
      }
    },
  );

  for (final layout in [
    (const Size(1280, 800), 1.0),
    (const Size(1024, 720), 1.5),
    (const Size(390, 844), 2.0),
  ]) {
    testWidgets(
      'compact recruitment keeps values and keyboard details at $layout',
      (tester) async {
        final person = game.pool.last;
        final before = jsonEncode(game.gameState);
        reseedRNG(seed: 50125);
        final rolls = List.generate(8, (_) => lcsRandom(100000));
        reseedRNG(seed: 50125);
        String? received;
        unawaited(engine.console.getkey().then((key) => received = key));
        var inspected = false;
        await mount(
          tester,
          SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: RecruitmentCard(
              person: person,
              recruiter: game.pool.first,
              onInspect: () => inspected = true,
            ),
          ),
          size: layout.$1,
          scale: layout.$2,
        );
        final cells = tester
            .widgetList<SizedBox>(
              find.byWidgetPredicate(
                (widget) =>
                    widget is SizedBox &&
                    widget.key is ValueKey<String> &&
                    (widget.key! as ValueKey<String>).value.startsWith(
                      'character-attribute-cell:',
                    ),
              ),
            )
            .toList();
        expect(
          cells.map((cell) => (cell.key! as ValueKey<String>).value),
          characterAttributeDisplayOrder.map(
            (a) => 'character-attribute-cell:${a.name}',
          ),
        );
        for (final attribute in characterAttributeDisplayOrder) {
          expect(
            tester
                .widget<Text>(
                  find.byKey(ValueKey('character-attribute:${attribute.name}')),
                )
                .data,
            '${person.attribute(attribute)}',
          );
        }
        expect(find.text(recruitmentBackground(person)), findsNothing);
        final portrait = tester.widget<CrewPortrait>(find.byType(CrewPortrait));
        expect(portrait.size, 44);
        await activateInfo(
          tester,
          find.byKey(ValueKey('character-attribute-help:${person.id}')),
        );
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.textContaining('Current effective value:'), findsWidgets);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Inspect ${person.name}'));
        await tester.tap(find.text('Inspect ${person.name}'));
        expect(inspected, isTrue);
        expect(received, isNull);
        expect(engine.console.awaitingInput, isTrue);
        expect(jsonEncode(game.gameState), before);
        expect(List.generate(8, (_) => lcsRandom(100000)), rolls);
        engine.console.sendInput('Escape');
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'compact skill reference preserves selected tab, progress and live input',
    (tester) async {
      final person = game.pool.first;
      final before = jsonEncode(game.gameState);
      String? received;
      unawaited(engine.console.getkey().then((key) => received = key));
      await mount(
        tester,
        CrewDossier(person: person, embedded: true, page: 1),
        size: const Size(1024, 720),
        scale: 1.5,
      );
      expect(
        find.byKey(const ValueKey('crew-dossier-compact-header')),
        findsOneWidget,
      );
      expect(find.text(Skill.art.description), findsNothing);
      for (final skill in Skill.values) {
        expect(
          tester
              .widget<Text>(
                find.byKey(ValueKey('crew-dossier-skill-level:${skill.name}')),
              )
              .data,
          '${person.skill(skill)}',
        );
      }
      final reference = find.byKey(
        const ValueKey('crew-dossier-skill-reference'),
      );
      await activateInfo(tester, reference);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining(Skill.art.description), findsWidgets);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('crew-dossier-skill:art')),
        findsOneWidget,
      );
      final tabs = tester.widget<Semantics>(
        find
            .ancestor(
              of: find.byKey(const ValueKey('journal-profile-tab:1')),
              matching: find.byType(Semantics),
            )
            .first,
      );
      expect(tabs.properties.selected, isTrue);
      await activateInfo(tester, reference);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(received, isNull);
      expect(jsonEncode(game.gameState), before);
      engine.console.sendInput('Escape');
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'restricted source summary never adds unadvertised character facts',
    (tester) async {
      final person = game.pool.first;
      await mount(
        tester,
        SingleChildScrollView(
          child: JournalPersonCard(
            summary: JournalPersonSummary(
              person: person,
              name: 'Unidentified prospect',
              role: 'Unknown',
              health: '?',
              equipment: ['Weapon unknown'],
              details: ['Persuasion: ?'],
              inspectable: false,
            ),
          ),
        ),
      );
      expect(find.byType(CharacterAttributes), findsNothing);
      expect(find.text('Weapon unknown'), findsOneWidget);
      await tester.tap(find.text('Attributes, skills & condition'));
      await tester.pumpAndSettle();
      expect(find.text('Persuasion: ?'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
