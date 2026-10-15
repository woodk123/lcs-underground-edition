import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activate_regulars.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/creature/body.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/gender.dart';
import 'package:lcs_new_age/creature/portrait.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/justice/crimes.dart';
import 'package:lcs_new_age/modern/crew_dossier.dart';
import 'package:lcs_new_age/modern/crew_portrait.dart';
import 'package:lcs_new_age/modern/direct_content.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/modern_app.dart';
import 'package:lcs_new_age/modern/skill_help.dart';
import 'package:lcs_new_age/politics/alignment.dart' as politics;
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

Future<void> mountInspector(
  WidgetTester tester,
  Creature person, {
  Size size = const Size(1280, 800),
  double textScale = 1,
  List<CrewDossierAction> actions = const [],
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
      theme: buildModernTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () =>
                showCrewDossier(context, person: person, actions: actions),
            child: const Text('Open dossier'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open dossier'));
  await tester.pumpAndSettle();
}

Future<void> chooseTab(WidgetTester tester, int tab) async {
  final target = find.byKey(ValueKey('crew-dossier-tab-$tab'));
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await ensureGameDataLoaded();
    final journalFont = FontLoader(JournalPalette.serif)
      ..addFont(rootBundle.load('fonts/journal/LibreBaskerville-Variable.ttf'));
    await journalFont.load();
  });
  setUp(() async {
    engine.console = Console();
    game.gameState = decodeSaveContents(
      await File('test/saves/felix_1_0.json').readAsString(),
    ).gameState!;
    game.activeSquadMember = null;
  });

  testWidgets('an idle squad does not describe Lay Low as a task override', (
    tester,
  ) async {
    final person = game.squad.first;
    person.activity = Activity(ActivityType.donations);
    person.squad!.activity = Activity(ActivityType.none);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CrewInspector(person: person, onClose: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('None · personal assignment applies'),
      findsOneWidget,
    );
    expect(find.textContaining('Stay out of public activity'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test(
    'portrait choice survives save reload and renaming without campaign rolls',
    () {
      final founder = game.pool.first;
      final portrait = stablePortraitIndex(founder);
      final clone = Creature.fromJson(
        jsonDecode(jsonEncode(founder)) as Map<String, dynamic>,
      );
      expect(stablePortraitIndex(clone), portrait);
      founder.name = 'A new code name';
      expect(stablePortraitIndex(founder), portrait);
      expect(portraitCatalog[portrait].gender, Gender.male);
      founder.gender = Gender.female;
      expect(stablePortraitIndex(founder), portrait);
      reseedRNG(seed: 91245);
      final expected = List.generate(8, (_) => lcsRandom(100000));
      reseedRNG(seed: 91245);
      for (var i = 0; i < 50; i++) {
        stablePortraitIndex(founder);
      }
      expect(List.generate(8, (_) => lcsRandom(100000)), expected);
    },
  );

  testWidgets(
    'real founder dossier displays health, location, orders and full skills',
    (tester) async {
      final founder = game.pool.first;
      await mountInspector(tester, founder);
      expect(find.text(founder.name), findsOneWidget);
      expect(
        find.text('${founder.blood} / ${founder.maxBlood}'),
        findsOneWidget,
      );
      expect(
        find.text(founder.location!.getName(includeCity: true)),
        findsWidgets,
      );
      expect(find.text(founder.activity.description), findsWidgets);
      expect(find.byType(CrewPortrait), findsOneWidget);
      await chooseTab(tester, 1);
      for (final skill in Skill.values) {
        expect(find.text(skill.displayName), findsOneWidget);
      }
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('crew-dossier-skill:art')),
          matching: find.text(
            '${founder.skillXP(Skill.art)} / ${skillXpNeeded(founder.skill(Skill.art))} XP · Attribute cap ${founder.skillCap(Skill.art)}',
          ),
        ),
        findsOneWidget,
      );
      await chooseTab(tester, 2);
      expect(find.text('${founder.age}'), findsWidgets);
      expect(find.text('Identity & service'), findsOneWidget);
      expect(
        find.text('No current wanted charges'),
        founder.isCriminal ? findsNothing : findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('healthy non-liberal portraits do not imply available crew', (
    tester,
  ) async {
    final person = game.pool.first;
    person.align = politics.Alignment.moderate;
    person.blood = person.maxBlood;
    expect(person.isActiveLiberal, isFalse);
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(MaterialApp(home: CrewPortrait(person: person)));
      await tester.pumpAndSettle();
      final label = tester.getSemantics(find.byType(CrewPortrait)).label;
      expect(label, contains('Not active crew'));
      expect(label, isNot(contains('Available')));
    } finally {
      semantics.dispose();
    }
  });

  testWidgets(
    'recorded ammunition without a type is not described as unloaded',
    (tester) async {
      final person = game.pool.first;
      person.equippedWeapon!
        ..ammo = 30
        ..loadedAmmoType = null;
      final before = jsonEncode(game.gameState);
      await mountInspector(tester, person);
      expect(find.text('30 rounds · Type not recorded'), findsOneWidget);
      expect(find.text('Unloaded'), findsNothing);
      expect(jsonEncode(game.gameState), before);
      await tester.tap(find.byKey(const ValueKey('crew-dossier-close')));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'injuries and damaged equipment use readable actual campaign values',
    (tester) async {
      final founder = game.pool.first;
      founder.blood = founder.maxBlood - 21;
      (founder.body as HumanoidBody)
        ..missingLeftEye = true
        ..leftArm.cut = true
        ..leftArm.bleeding = 2
        ..leftArm.relativeHealth = .55;
      founder.equippedClothing!
        ..bloody = true
        ..damaged = true;
      founder.wantedForCrimes[Crime.theft] = 3;
      founder.pastConvictions[Crime.vandalism] = 2;
      founder.sentence = 4;
      await mountInspector(tester, founder);
      expect(find.text('No Left Eye'), findsOneWidget);
      expect(
        find.text('Left Arm · Cut, Bleeding (2), 55% tissue health'),
        findsOneWidget,
      );
      expect(find.text('Quality 1 · Bloodstained · Damaged'), findsOneWidget);
      expect(find.text(founder.equippedClothing!.type.name), findsOneWidget);
      expect(find.textContaining('&C'), findsNothing);
      expect(find.textContaining('&R'), findsNothing);
      await chooseTab(tester, 2);
      expect(find.text('Theft'), findsOneWidget);
      expect(find.text('Past convictions'), findsOneWidget);
      expect(find.text('4 months in prison'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'inspect and Escape preserve the complete campaign, date, funds and RNG',
    (tester) async {
      final founder = game.pool.first;
      final before = jsonEncode(game.gameState);
      final beforeDate = game.date;
      final beforeFunds = game.ledger.funds;
      var completed = false;
      final pendingInput = engine.getKey().then((value) {
        completed = true;
        return value;
      });
      reseedRNG(seed: 71935);
      final expected = List.generate(8, (_) => lcsRandom(100000));
      reseedRNG(seed: 71935);
      await mountInspector(tester, founder);
      await chooseTab(tester, 1);
      await chooseTab(tester, 2);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(CrewDossier), findsNothing);
      expect(completed, isFalse);
      expect(engine.console.awaitingInput, isTrue);
      expect(jsonEncode(game.gameState), before);
      expect(game.date, beforeDate);
      expect(game.ledger.funds, beforeFunds);
      expect(List.generate(8, (_) => lcsRandom(100000)), expected);
      engine.console.sendInput('Enter');
      await pendingInput;
    },
  );

  testWidgets('only an explicitly invoked host action triggers its callback', (
    tester,
  ) async {
    var called = 0;
    await mountInspector(
      tester,
      game.pool.first,
      actions: [
        CrewDossierAction(label: 'Select in squad', onPressed: () => called++),
      ],
    );
    expect(called, 0);
    await tester.tap(find.text('Select in squad'));
    await tester.pumpAndSettle();
    expect(called, 1);
    expect(find.byType(CrewDossier), findsNothing);
  });

  testWidgets(
    'journal dossier retains passive hints, close and exact host actions at 800px150%',
    (tester) async {
      final person = game.pool.first;
      final before = jsonEncode(game.gameState);
      var called = 0;
      var completed = false;
      final pendingInput = engine.getKey().then((_) => completed = true);
      final actions = [
        CrewDossierAction(label: 'Select in squad', onPressed: () => called++),
        CrewDossierAction(
          label: 'Unavailable order',
          enabled: false,
          onPressed: () => called += 100,
        ),
      ];
      await mountInspector(
        tester,
        person,
        size: const Size(800, 600),
        textScale: 1.5,
        actions: actions,
      );
      expect(
        find.byKey(const ValueKey('crew-dossier-close')).hitTestable(),
        findsOneWidget,
      );
      await tester.tap(find.text('Unavailable order'));
      await tester.pumpAndSettle();
      expect(called, 0);
      expect(find.byType(CrewDossier), findsOneWidget);
      await chooseTab(tester, 1);
      final skill = find.byKey(
        const ValueKey('crew-dossier-skill:martialArts'),
      );
      await tester.ensureVisible(skill);
      await tester.pumpAndSettle();
      final hint = find.descendant(of: skill, matching: find.byType(Tooltip));
      tester.state<TooltipState>(hint).ensureTooltipVisible();
      await tester.pump(const Duration(milliseconds: 650));
      expect(
        find.text(skillHelp(Skill.martialArts, actor: person)),
        findsOneWidget,
      );
      expect(find.byType(CrewDossier), findsOneWidget);
      expect(completed, isFalse);
      expect(jsonEncode(game.gameState), before);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(CrewDossier), findsNothing);
      expect(engine.console.awaitingInput, isTrue);
      expect(completed, isFalse);
      expect(jsonEncode(game.gameState), before);
      await tester.tap(find.text('Open dossier'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select in squad'));
      await tester.pumpAndSettle();
      expect(called, 1);
      expect(find.byType(CrewDossier), findsNothing);
      expect(completed, isFalse);
      expect(jsonEncode(game.gameState), before);
      engine.console.sendInput('Enter');
      await pendingInput;
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'inline crew inspection leaves other controls usable and preserves campaign and RNG',
    (tester) async {
      final person = game.pool.first;
      final before = jsonEncode(game.gameState);
      final beforeDate = game.date;
      final beforeFunds = game.ledger.funds;
      var otherClicks = 0;
      var commands = 0;
      var completed = false;
      final pendingInput = engine.getKey().then((_) => completed = true);
      reseedRNG(seed: 71935);
      final expected = List.generate(8, (_) => lcsRandom(100000));
      reseedRNG(seed: 71935);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildModernTheme(),
          home: Scaffold(
            body: Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => otherClicks++,
                    child: const Text('Keep using the city'),
                  ),
                ),
                SizedBox(
                  width: 284,
                  height: 450,
                  child: CrewInspector(
                    person: person,
                    onClose: () {},
                    actions: [
                      CrewDossierAction(
                        label: 'Host order',
                        onPressed: () => commands++,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      await tester.tap(find.text('Keep using the city'));
      await tester.pumpAndSettle();
      expect(otherClicks, 1);
      expect(commands, 0);
      expect(find.byType(CrewInspector), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('crew-inspector-full')));
      await tester.pumpAndSettle();
      expect(find.byType(CrewDossier), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(CrewDossier), findsNothing);
      expect(find.byType(CrewInspector), findsOneWidget);
      await tester.tap(find.text('Host order'));
      await tester.pumpAndSettle();
      expect(commands, 1);
      expect(find.byType(CrewInspector), findsOneWidget);
      expect(completed, isFalse);
      expect(engine.console.awaitingInput, isTrue);
      expect(jsonEncode(game.gameState), before);
      expect(game.date, beforeDate);
      expect(game.ledger.funds, beforeFunds);
      expect(List.generate(8, (_) => lcsRandom(100000)), expected);
      engine.console.sendInput('Enter');
      await pendingInput;
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compact inline inspector keeps close and actions visible at large reading size',
    (tester) async {
      final person = game.pool.first
        ..name = 'Alexandria Persephone The Extraordinary Organiser';
      var closed = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildModernTheme(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: Scaffold(
              body: SizedBox(
                width: 360,
                height: 230,
                child: CrewInspector(
                  person: person,
                  compact: true,
                  onClose: () => closed = true,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final bounds = tester.getRect(find.byType(CrewInspector));
      expect(
        tester
            .getRect(find.byKey(const ValueKey('crew-inspector-close')))
            .bottom,
        lessThanOrEqualTo(bounds.bottom),
      );
      expect(
        tester
            .getRect(find.byKey(const ValueKey('crew-inspector-full')))
            .bottom,
        lessThanOrEqualTo(bounds.bottom),
      );
      expect(find.byType(Dialog), findsNothing);
      await tester.tap(find.byKey(const ValueKey('crew-inspector-close')));
      expect(closed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'long names and large reading size remain scrollable at narrow width',
    (tester) async {
      game.pool.first.name =
          'Alexandria Persephone The Extraordinary Organiser';
      await mountInspector(
        tester,
        game.pool.first,
        size: const Size(360, 640),
        textScale: 1.6,
      );
      expect(tester.takeException(), isNull);
      await chooseTab(tester, 1);
      expect(find.text('Skills & training'), findsOneWidget);
      await chooseTab(tester, 2);
      expect(find.text('Identity & service'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('crew-dossier-close')));
      await tester.pumpAndSettle();
      expect(find.byType(CrewDossier), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'center roster portrait inspects separately from the original assignment action',
    (tester) async {
      final founder = game.pool.first;
      final before = jsonEncode(game.gameState);
      var completed = false;
      final flow = activateRegulars().then((_) => completed = true);
      final action = engine.console.actions.firstWhere(
        (action) =>
            action.entityType == 'person' && action.entityId == '${founder.id}',
      );
      final commands = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildModernTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: DirectContent(
                console: engine.console,
                onAction: commands.add,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final portrait = find.byKey(
        ValueKey('direct-dossier:${action.y}:${action.x}:${founder.id}'),
      );
      await tester.tap(portrait);
      await tester.pumpAndSettle();
      expect(find.byType(CrewDossier), findsOneWidget);
      expect(commands, isEmpty);
      await tester.tap(find.byKey(const ValueKey('crew-dossier-close')));
      await tester.pumpAndSettle();
      expect(completed, isFalse);
      expect(jsonEncode(game.gameState), before);
      await tester.tap(
        find.byKey(
          ValueKey('direct-action:${action.y}:${action.x}:${action.key}'),
        ),
      );
      await tester.pump();
      expect(commands, [action.key]);
      engine.console.sendInput('Enter');
      await flow;
    },
  );

  testWidgets(
    'a matching name without explicit person metadata cannot expose a dossier',
    (tester) async {
      engine.erase();
      engine.addOptionText(3, 0, 'a', 'A - ${game.pool.first.name}');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DirectContent(console: engine.console, onAction: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CrewPortrait), findsNothing);
      expect(find.byType(CrewDossier), findsNothing);
    },
  );
}
