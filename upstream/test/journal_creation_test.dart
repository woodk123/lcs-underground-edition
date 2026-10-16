import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/creature/attributes.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/creation_context.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/modern/attribute_help.dart';
import 'package:lcs_new_age/modern/creation_bonus_help.dart';
import 'package:lcs_new_age/modern/crew_portrait.dart';
import 'package:lcs_new_age/modern/journal_creation.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/skill_help.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

class _Reader {
  _Reader(this.context, {List<ConsoleAction> actions = const []}) {
    console.creation = context;
    console.actions.addAll(actions);
    unawaited(console.getkey().then((key) => received = key));
  }
  final CreationContext context;
  final console = Console();
  String? received;
  final sent = <String>[];
  void send(String key) {
    sent.add(key);
    console.sendInput(key);
  }
}

ConsoleAction _action(String key, {bool enabled = true, String? id}) =>
    ConsoleAction(
      key: key,
      label: 'Original $key',
      enabled: enabled,
      y: 1,
      x: 1,
      width: 20,
      entityType: 'creation-choice',
      entityId: id ?? key,
    );

Finder _key(String value) => find.byKey(ValueKey(value));

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 15; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle();
}

Future<void> _mount(
  WidgetTester tester,
  _Reader reader, {
  Size size = const Size(1280, 720),
  double scale = 1,
  Widget? inputBar,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(disableAnimations: true);
  addTearDown(() async {
    reader.console.sendInput('Escape');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: buildJournalTheme(),
      home: MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: JournalCreationPage(
            console: reader.console,
            context: reader.context,
            onAction: reader.send,
            inputBar: inputBar ?? const SizedBox.shrink(),
            onHelp: () {},
            readingControl: IconButton(
              tooltip: 'Reading size',
              onPressed: () {},
              icon: const Icon(Icons.text_fields),
            ),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
}

void _inside(WidgetTester tester, Finder finder, Size size) {
  expect(finder.hitTestable(), findsOneWidget);
  final rect = tester.getRect(finder);
  expect(rect.left, greaterThanOrEqualTo(0));
  expect(rect.top, greaterThanOrEqualTo(0));
  expect(rect.right, lessThanOrEqualTo(size.width));
  expect(rect.bottom, lessThanOrEqualTo(size.height));
}

void main() {
  late String fixture;
  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
    final serif = FontLoader('JournalSerif');
    serif.addFont(
      rootBundle.load('fonts/journal/LibreBaskerville-Variable.ttf'),
    );
    serif.addFont(
      rootBundle.load('fonts/journal/LibreBaskerville-Italic-Variable.ttf'),
    );
    await serif.load();
  });
  setUp(() {
    game.gameState = decodeSaveContents(fixture).gameState!;
  });

  testWidgets('a central setting sends its actual original key once', (
    tester,
  ) async {
    final reader = _Reader(
      CreationContext(
        stage: CreationStage.setup,
        title: 'Campaign dossier',
        fields: const [
          CreationField(
            key: 'A',
            label: 'Starting political climate',
            value: 'The Times They Are a-Changin’',
            description:
                'The country is beginning to slide into far-right authoritarianism.',
          ),
        ],
        choices: const [
          CreationChoice(key: 'Enter', label: 'Continue to founder'),
        ],
      ),
      actions: [_action('a'), _action('Enter')],
    );
    await _mount(tester, reader);
    final button = tester.widget<OutlinedButton>(_key('creation-field:A'));
    expect(button.onPressed, isNotNull);
    button.onPressed!();
    button.onPressed!();
    await _settle(tester);
    expect(reader.sent, ['a']);
    expect(reader.received, 'a');
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets(
    'portrait reroll uses its source action once on the name screen',
    (tester) async {
      final reader = _Reader(
        CreationContext(
          stage: CreationStage.identity,
          title: 'The founder',
          portraitId: 1,
          portraitRerollKey: 'F',
          fields: const [
            CreationField(key: 'A', label: 'Given name', value: 'Alex'),
          ],
        ),
        actions: [_action('a'), _action('f')],
      );
      await _mount(tester, reader);
      expect(find.byType(FounderPortraitPreview), findsOneWidget);
      expect(_key('creation-field:A'), findsOneWidget);
      final button = tester.widget<OutlinedButton>(
        _key('creation-reroll-portrait'),
      );
      button.onPressed!();
      button.onPressed!();
      await _settle(tester);
      expect(reader.sent, ['f']);
      expect(reader.received, 'f');
    },
  );

  testWidgets('founder values form two close label/value columns', (
    tester,
  ) async {
    final founder = game.pool.first;
    final reader = _Reader(
      CreationContext(
        stage: CreationStage.background,
        title: 'Background',
        founder: founder,
        step: 2,
      ),
    );
    await _mount(tester, reader);
    final strength = tester.getRect(_key('creation-attribute:strength'));
    final agility = tester.getRect(_key('creation-attribute:agility'));
    final intelligence = tester.getRect(
      _key('creation-attribute:intelligence'),
    );
    expect((strength.top - agility.top).abs(), lessThan(1));
    expect(agility.left, greaterThan(strength.right));
    expect(intelligence.top, greaterThan(strength.bottom));
    final label = tester.getRect(find.text('Strength'));
    expect(strength.left - label.right, inInclusiveRange(5, 7));
    expect(find.textContaining('Hover an attribute'), findsNothing);
    expect(find.textContaining('Hover a skill'), findsNothing);
    final skills = find.byType(SkillTooltip);
    final first = tester.getRect(skills.at(0));
    final second = tester.getRect(skills.at(1));
    expect((first.top - second.top).abs(), lessThan(1));
    expect(second.left, greaterThan(first.right));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a background answer sends once with its complete effects visible', (
    tester,
  ) async {
    final reader = _Reader(
      CreationContext(
        stage: CreationStage.background,
        title: 'The founder’s history',
        prompt: 'In the moments after I was born in 2004...',
        step: 1,
        totalSteps: 10,
        founder: game.pool.first,
        choices: const [
          CreationChoice(
            key: 'a',
            label:
                'American torture of prisoners in Iraq was revealed on national TV.',
            description: '+2 Agility, June 30th',
          ),
        ],
      ),
      actions: [_action('a')],
    );
    await _mount(tester, reader);
    expect(
      tester.widget<Semantics>(_key('creation-effects:a')).properties.label,
      'Effects: +2 Agility, June 30th',
    );
    expect(find.text('+2 Agility'), findsOneWidget);
    expect(
      _key('creation-continue'),
      findsNothing,
      reason:
          'Choosing an answer is the original commit, with no extra confirmation.',
    );
    expect(
      _key('creation-founder-age'),
      findsNothing,
      reason: 'The first birth-date answer has not been applied.',
    );
    await tester.tap(_key('creation-choice:a'));
    await _settle(tester);
    expect(reader.sent, ['a']);
    expect(reader.received, 'a');
  });

  testWidgets(
    'stale revision, context and replaced source action callbacks are rejected',
    (tester) async {
      final original = _action('a', id: 'old');
      final context = CreationContext(
        stage: CreationStage.setup,
        title: 'Campaign',
        fields: const [
          CreationField(key: 'A', label: 'Climate', value: 'Standard'),
        ],
      );
      final reader = _Reader(context, actions: [original]);
      await _mount(tester, reader);
      final callback = tester
          .widget<OutlinedButton>(_key('creation-field:A'))
          .onPressed!;
      reader.console.actions[0] = _action('a', id: 'replaced');
      callback();
      expect(reader.sent, isEmpty);
      reader.console.actions[0] = original;
      reader.console.creation = CreationContext(
        stage: CreationStage.identity,
        title: 'Identity',
      );
      callback();
      expect(reader.sent, isEmpty);
      reader.console.creation = context;
      reader.console.flush();
      callback();
      expect(reader.sent, isEmpty);
      expect(reader.received, isNull);
    },
  );

  for (final view in [
    (size: const Size(1280, 720), scale: 1.0),
    (size: const Size(800, 600), scale: 1.5),
  ]) {
    testWidgets('answer bonus help is passive and clickable at ${view.size}', (
      tester,
    ) async {
      final founder = game.pool.first;
      final reader = _Reader(
        CreationContext(
          stage: CreationStage.background,
          title: 'The founder’s background',
          step: 4,
          founder: founder,
          choices: const [
            CreationChoice(
              key: 'a',
              label: 'Acrimoniously. I once tripped over the paperwork!',
              description: '+1 Law, +1 Agility, +1 Computers',
              bonuses: CreationBonuses(
                skills: {Skill.law: 1, Skill.computers: 1},
                attributes: {Attribute.agility: 1},
              ),
            ),
          ],
        ),
        actions: [_action('a')],
      );
      final before = jsonEncode(game.gameState.toJson());
      reseedRNG(seed: 18023);
      final rolls = List.generate(12, (_) => lcsRandom(100000));
      reseedRNG(seed: 18023);
      await _mount(tester, reader, size: view.size, scale: view.scale);
      expect(
        tester.getRect(find.text('+1 Law')).height,
        closeTo(12 * 1.4 * view.scale, 1),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      final preview = CreationBonusPreview(
        founder,
        reader.context.choices.first.bonuses!,
      );
      for (final help in [
        (label: '+1 Law', message: preview.skill(Skill.law)),
        (label: '+1 Agility', message: preview.attribute(Attribute.agility)),
        (label: '+1 Computers', message: preview.skill(Skill.computers)),
      ]) {
        await mouse.moveTo(tester.getCenter(find.text(help.label)));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.pumpAndSettle();
        final popup = find.text(help.message);
        expect(popup, findsOneWidget);
        final bounds = tester.getRect(popup);
        expect(bounds.left, greaterThanOrEqualTo(0));
        expect(bounds.top, greaterThanOrEqualTo(0));
        expect(bounds.right, lessThanOrEqualTo(view.size.width));
        expect(bounds.bottom, lessThanOrEqualTo(view.size.height));
        expect(reader.sent, isEmpty);
      }
      await tester.longPress(find.text('+1 Law'));
      await tester.pumpAndSettle();
      expect(find.text(preview.skill(Skill.law)), findsOneWidget);
      expect(reader.sent, isEmpty);
      expect(jsonEncode(game.gameState.toJson()), before);
      expect(List.generate(12, (_) => lcsRandom(100000)), rolls);
      await tester.tap(find.text('+1 Agility'));
      await _settle(tester);
      expect(reader.sent, ['a']);
      expect(reader.received, 'a');
      await mouse.removePointer();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('shared bonuses and Int get help while equipment stays plain', (
    tester,
  ) async {
    const description =
        r'+4 Int, +2 Science Computers Writing and Teaching, '
        r'+1 Business and Law, $1000, Security Uniform';
    final reader = _Reader(
      CreationContext(
        stage: CreationStage.background,
        title: 'Background',
        founder: game.pool.first,
        choices: const [
          CreationChoice(
            key: 'a',
            label: 'A college background',
            description: description,
          ),
        ],
      ),
      actions: [_action('a')],
    );
    await _mount(tester, reader);
    final effects = _key('creation-effects:a');
    expect(
      tester.widget<Semantics>(effects).properties.label,
      'Effects: $description',
    );
    final skills = tester.widgetList<SkillTooltip>(
      find.descendant(of: effects, matching: find.byType(SkillTooltip)),
    );
    expect(
      skills.map((tooltip) => tooltip.skill),
      unorderedEquals([
        Skill.science,
        Skill.computers,
        Skill.writing,
        Skill.teaching,
        Skill.business,
        Skill.law,
      ]),
    );
    final attributes = tester.widgetList<AttributeTooltip>(
      find.descendant(of: effects, matching: find.byType(AttributeTooltip)),
    );
    expect(attributes.map((tooltip) => tooltip.attribute), [
      Attribute.intelligence,
    ]);
    expect(find.text('+4 Int'), findsOneWidget);
    expect(reader.sent, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled source choices stay disabled and cannot supply input', (
    tester,
  ) async {
    final reader = _Reader(
      CreationContext(
        stage: CreationStage.background,
        title: 'History',
        choices: const [
          CreationChoice(key: 'a', label: 'Unavailable source choice'),
        ],
      ),
      actions: [_action('a', enabled: false)],
    );
    await _mount(tester, reader);
    expect(
      tester.widget<OutlinedButton>(_key('creation-choice:a')).onPressed,
      isNull,
    );
    expect(reader.sent, isEmpty);
    expect(reader.received, isNull);
  });

  testWidgets(
    'fate and briefing show only the original body plus Enter acknowledgement',
    (tester) async {
      final reader = _Reader(
        CreationContext(
          stage: CreationStage.background,
          title: 'A chapter chosen by fate',
          step: 1,
          totalSteps: 10,
          body: const ['Ronald Reagan died.', '+2 Strength, June 5th'],
          founder: game.pool.first,
        ),
      );
      await _mount(tester, reader);
      expect(find.text('Ronald Reagan died.'), findsOneWidget);
      expect(
        tester
            .widget<Semantics>(_key('creation-effects:fate'))
            .properties
            .label,
        '+2 Strength, June 5th',
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith(
                'creation-choice:',
              ),
        ),
        findsNothing,
      );
      await tester.tap(_key('creation-continue'));
      await _settle(tester);
      expect(reader.sent, ['Enter']);
      expect(reader.received, 'Enter');
    },
  );

  testWidgets(
    'viewing the dossier, skills and portrait preserves source state and RNG',
    (tester) async {
      final founder = game.pool.first;
      final reader = _Reader(
        CreationContext(
          stage: CreationStage.background,
          title: 'Your history',
          step: 2,
          totalSteps: 10,
          founder: founder,
          choices: const [CreationChoice(key: 'a', label: 'A full answer')],
        ),
        actions: [_action('a')],
      );
      final before = jsonEncode(game.gameState.toJson());
      reseedRNG(seed: 48113);
      final expected = List.generate(20, (_) => lcsRandom(100000));
      reseedRNG(seed: 48113);
      await _mount(tester, reader);
      expect(find.byType(SkillTooltip), findsNWidgets(Skill.values.length));
      expect(
        find.byType(AttributeTooltip),
        findsNWidgets(Attribute.values.length),
      );
      for (final attribute in Attribute.values) {
        expect(
          tester
              .widget<Text>(_key('creation-attribute:${attribute.name}'))
              .data,
          '${founder.attribute(attribute)}',
        );
      }
      expect(_key('creation-founder-age'), findsOneWidget);
      final attributeMouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await attributeMouse.addPointer(location: Offset.zero);
      for (final attribute in Attribute.values) {
        final target = _key('creation-attribute:${attribute.name}');
        await tester.ensureVisible(target);
        await attributeMouse.moveTo(tester.getCenter(target));
        await tester.pump(const Duration(milliseconds: 500));
        expect(
          find.text(attributeHelp(attribute, actor: founder)),
          findsOneWidget,
        );
        await attributeMouse.moveTo(Offset.zero);
        await tester.pump(const Duration(milliseconds: 300));
      }
      await attributeMouse.removePointer();
      await tester.ensureVisible(_key('creation-skill:computers'));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(_key('creation-skill:computers')));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.textContaining('Computers'), findsWidgets);
      expect(jsonEncode(game.gameState.toJson()), before);
      expect(List.generate(20, (_) => lcsRandom(100000)), expected);
      expect(reader.sent, isEmpty);
      expect(reader.received, isNull);
      await mouse.removePointer();
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(1280, 720), const Size(800, 600)]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets(
        'setup Continue remains visible at ${size.width}x${size.height}, scale $scale',
        (tester) async {
          final reader = _Reader(
            CreationContext(
              stage: CreationStage.setup,
              title: 'Campaign dossier',
              subtitle: 'Set the conditions for your new movement',
              fields: const [
                CreationField(
                  key: 'A',
                  label: 'Starting political climate',
                  value: 'The End of the World as We Know It',
                  description:
                      'Liberalism is already forgotten. Is it too late to fight back?',
                ),
                CreationField(
                  key: 'B',
                  label: 'Conservative Crime Squad',
                  value: 'We Didn’t Start The Fire',
                  description: 'The CCS starts active and extremely strong.',
                ),
                CreationField(
                  key: 'C',
                  label: 'Combat difficulty',
                  value: 'Welcome to the Jungle',
                  description:
                      'Zipper initiative: Teams take turns attacking one at a time.',
                ),
              ],
              choices: const [
                CreationChoice(key: 'Enter', label: 'Continue to founder'),
              ],
            ),
            actions: [
              _action('a'),
              _action('b'),
              _action('c'),
              _action('Enter'),
            ],
          );
          await _mount(tester, reader, size: size, scale: scale);
          _inside(tester, _key('creation-continue'), size);
          await tester.ensureVisible(_key('creation-field:C'));
          await _settle(tester);
          expect(_key('creation-field:C').hitTestable(), findsOneWidget);
          expect(
            find.text(
              'Zipper initiative: Teams take turns attacking one at a time.',
            ),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'full narrative and all five answer descriptions scroll at ${size.width}, scale $scale',
        (tester) async {
          final choices = List.generate(
            5,
            (index) => CreationChoice(
              key: String.fromCharCode(97 + index),
              label:
                  'This is the full original narrative answer ${index + 1}: '
                  'words beyond the old terminal’s eighty-column boundary remain '
                  'readable, including Wangarĩ Maathai and a long explanation of '
                  'the circumstances in which the founder grew up.',
              description:
                  '+${index + 1} Intelligence, +1 Writing, '
                  'with the complete source description preserved.',
            ),
          );
          final reader = _Reader(
            CreationContext(
              stage: CreationStage.background,
              title: 'The founder’s history',
              prompt:
                  'When I was in secondary school, the people around me '
                  'expected things to continue as they had always been...',
              choices: choices,
              founder: game.pool.first,
              step: 4,
              totalSteps: 10,
            ),
            actions: choices.map((choice) => _action(choice.key)).toList(),
          );
          await _mount(tester, reader, size: size, scale: scale);
          await tester.ensureVisible(_key('creation-choice:e'));
          await _settle(tester);
          expect(_key('creation-choice:e').hitTestable(), findsOneWidget);
          for (final choice in choices) {
            final label = tester.widget<Text>(find.text(choice.label));
            expect(label.maxLines, isNull);
            expect(label.overflow, isNot(TextOverflow.ellipsis));
            expect(
              tester
                  .widget<Semantics>(_key('creation-effects:${choice.key}'))
                  .properties
                  .label,
              'Effects: ${choice.description}',
            );
          }
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'name entry sits beside its question and fits at ${size.width}, scale $scale',
        (tester) async {
          final reader = _Reader(
            CreationContext(
              stage: CreationStage.name,
              title: 'Your public name',
              prompt: 'What is your name to the people?',
              founder: game.pool.first,
              body: const ['This is the name the movement will know you by.'],
            ),
          );
          final controller = TextEditingController(text: 'Wangarĩ Fernández');
          addTearDown(controller.dispose);
          final input = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const ValueKey('source-name-entry'),
                controller: controller,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton(
                    key: const ValueKey('source-name-submit'),
                    onPressed: () => reader.send('Enter'),
                    child: const Text('Begin campaign'),
                  ),
                  TextButton(
                    key: const ValueKey('source-name-original'),
                    onPressed: () => reader.send('Escape'),
                    child: const Text('Use original name'),
                  ),
                ],
              ),
            ],
          );
          await _mount(
            tester,
            reader,
            size: size,
            scale: scale,
            inputBar: input,
          );
          _inside(tester, _key('source-name-entry'), size);
          _inside(tester, _key('source-name-submit'), size);
          _inside(tester, _key('source-name-original'), size);
          final main = tester.getRect(_key('creation-main-scroll'));
          final field = tester.getRect(_key('source-name-entry'));
          expect(field.left, greaterThanOrEqualTo(main.left));
          expect(field.right, lessThanOrEqualTo(main.right));
          expect(
            field.top,
            greaterThan(tester.getRect(_key('creation-prompt')).bottom),
          );
          expect(_key('creation-footer'), findsNothing);
          expect(controller.text, 'Wangarĩ Fernández');
          expect(
            _key('creation-continue'),
            findsNothing,
            reason:
                'The original name reader supplies the only submission control.',
          );
          await tester.tap(_key('source-name-submit'));
          await tester.pump();
          expect(reader.sent, ['Enter']);
          expect(reader.received, 'Enter');
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
