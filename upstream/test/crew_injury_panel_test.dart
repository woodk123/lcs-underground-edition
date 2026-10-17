import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/creature/body.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/modern/crew_dossier.dart';
import 'package:lcs_new_age/modern/crew_injury_panel.dart';
import 'package:lcs_new_age/modern/injury_status.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

Finder _key(String value) => find.byKey(ValueKey(value));

String _detailText(String id, WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: _key('injury-detail:$id'),
        matching: find.byType(Text),
      ),
    )
    .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? '')
    .join('\n');

Future<void> _mountPanel(
  WidgetTester tester,
  Creature person, {
  Size size = const Size(1280, 800),
  double reading = 1,
  bool dossier = false,
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
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(reading)),
        child: child!,
      ),
      home: Scaffold(
        body: dossier
            ? Builder(
                builder: (context) => TextButton(
                  onPressed: () => showCrewDossier(context, person: person),
                  child: const Text('Open dossier'),
                ),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: CrewInjuryPanel(person: person),
              ),
      ),
    ),
  );
  if (dossier) await tester.tap(find.text('Open dossier'));
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, String value) async {
  final target = _key(value);
  expect(target, findsOneWidget);
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  if (value.startsWith('injury-zone:')) {
    await tester.tapAt(
      _zonePoint(tester, value.substring('injury-zone:'.length)),
    );
  } else {
    await tester.tap(target);
  }
  await tester.pumpAndSettle();
}

// Zone InkWells fill the plate and are clipped to the anatomical outlines.
// Their rectangular RenderBox center is therefore not a valid limb hit point.
Offset _zonePoint(WidgetTester tester, String id) {
  final relative = switch (id) {
    'head' => const Offset(.5, .09),
    'torso' => const Offset(.5, .43),
    'left-arm' => const Offset(.74, .4),
    'right-arm' => const Offset(.26, .4),
    'left-leg' => const Offset(.57, .78),
    'right-leg' => const Offset(.43, .78),
    _ => throw ArgumentError.value(id),
  };
  final plate = tester.getRect(_key('injury-map'));
  return plate.topLeft +
      Offset(plate.width * relative.dx, plate.height * relative.dy);
}

bool _hasFocusedDescendant(String value) {
  var inside = false;
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  if (context.widget.key == ValueKey(value)) return true;
  context.visitAncestorElements((element) {
    if (element.widget.key == ValueKey(value)) inside = true;
    return !inside;
  });
  return inside;
}

Future<void> _tabTo(WidgetTester tester, String value) async {
  for (var i = 0; i < 90; i++) {
    if (_hasFocusedDescendant(value)) return;
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
  }
  fail('$value cannot be reached through ordinary Tab traversal.');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String campaign;
  late Creature person;

  setUpAll(() async {
    await ensureGameDataLoaded();
    campaign = await File('test/saves/felix_1_0.json').readAsString();
    final font = FontLoader(JournalPalette.serif)
      ..addFont(rootBundle.load('fonts/journal/LibreBaskerville-Variable.ttf'));
    await font.load();
  });

  setUp(() {
    engine.console = Console();
    game.gameState = decodeSaveContents(campaign).gameState!;
    game.activeSquadMember = null;
    journalReadingScale.value = 1;
    person = game.pool.first
      ..body = HumanoidBody()
      ..permanentHealthDamage = 0
      ..alive = true;
    person.blood = person.maxBlood;
  });

  testWidgets('every healthy body region is directly selectable on the map', (
    tester,
  ) async {
    await _mountPanel(tester, person);
    expect(_key('injury-map'), findsOneWidget);
    for (final id in [
      'head',
      'torso',
      'left-arm',
      'right-arm',
      'left-leg',
      'right-leg',
    ]) {
      await _tap(tester, 'injury-zone:$id');
      expect(_key('injury-detail:$id'), findsOneWidget);
      expect(
        _detailText(id, tester),
        contains(
          injuryLocations(
            person,
          ).singleWhere((location) => location.id == id).name,
        ),
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('web accessibility targets are bounded to their body regions', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await _mountPanel(tester, person);
      final map = tester.getSize(_key('injury-map'));
      for (final id in [
        'head',
        'torso',
        'left-arm',
        'right-arm',
        'left-leg',
        'right-leg',
      ]) {
        final rect = tester.getSemantics(_key('injury-zone:$id')).rect;
        expect(
          rect.width,
          lessThan(map.width * .75),
          reason: '$id must not expose a full-plate web semantics hit target.',
        );
        expect(
          rect.height,
          lessThan(map.height * .75),
          reason: '$id must not intercept clicks on unrelated body regions.',
        );
      }
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('hover previews a region then returns to the pinned selection', (
    tester,
  ) async {
    (person.body as HumanoidBody).puncturedRightLung = true;
    await _mountPanel(tester, person);
    await _tap(tester, 'injury-zone:left-arm');
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(2, 2));
    await mouse.moveTo(_zonePoint(tester, 'right-leg'));
    await tester.pumpAndSettle();
    expect(_key('injury-detail:right-leg'), findsOneWidget);
    await mouse.moveTo(const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(_key('injury-detail:left-arm'), findsOneWidget);
    await mouse.moveTo(tester.getCenter(_key('injury-marker:right-lung')));
    await tester.pumpAndSettle();
    expect(_key('injury-detail:right-lung'), findsOneWidget);
    await mouse.moveTo(const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(_key('injury-detail:left-arm'), findsOneWidget);
    await mouse.removePointer();
  });

  testWidgets('click and touch pin organ and body details after pointer exit', (
    tester,
  ) async {
    (person.body as HumanoidBody)
      ..puncturedHeart = true
      ..rightLeg.bruised = true;
    await _mountPanel(tester, person);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(2, 2));
    final heart = tester.getCenter(_key('injury-marker:heart'));
    await mouse.moveTo(heart);
    await mouse.down(heart);
    await mouse.up();
    await mouse.moveTo(const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(_key('injury-detail:heart'), findsOneWidget);
    await mouse.removePointer();
    await _tap(tester, 'injury-zone:right-leg');
    expect(_key('injury-detail:right-leg'), findsOneWidget);
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(_key('injury-detail:right-leg'), findsOneWidget);
  });

  for (final activation in [
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.space,
  ]) {
    testWidgets('${activation.keyLabel} pins a naturally focused map region', (
      tester,
    ) async {
      await _mountPanel(tester, person);
      await _tap(tester, 'injury-zone:left-arm');
      await _tabTo(tester, 'injury-zone:right-leg');
      await tester.sendKeyEvent(activation);
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(2, 2));
      await mouse.moveTo(_zonePoint(tester, 'left-leg'));
      await tester.pumpAndSettle();
      await mouse.moveTo(const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(_key('injury-detail:right-leg'), findsOneWidget);
      await mouse.removePointer();
    });
  }

  testWidgets(
    'injury list offers named buttons and comfortable touch targets',
    (tester) async {
      (person.body as HumanoidBody)
        ..puncturedLeftLung = true
        ..leftArm.bleeding = 3;
      final semantics = tester.ensureSemantics();
      try {
        await _mountPanel(tester, person);
        for (final id in ['left-lung', 'left-arm']) {
          final target = _key('injury-row:$id');
          await tester.ensureVisible(target);
          await tester.pumpAndSettle();
          final data = tester.getSemantics(target).getSemanticsData();
          expect(data.flagsCollection.isButton, isTrue);
          expect(data.label.trim(), isNotEmpty);
          expect(tester.getSize(target).height, greaterThanOrEqualTo(44));
          await _tap(tester, 'injury-row:$id');
          expect(_key('injury-detail:$id'), findsOneWidget);
        }
        for (final id in [
          'head',
          'torso',
          'left-arm',
          'right-arm',
          'left-leg',
          'right-leg',
        ]) {
          final data = tester
              .getSemantics(_key('injury-zone:$id'))
              .getSemanticsData();
          expect(data.flagsCollection.isButton, isTrue);
          expect(data.label.trim(), isNotEmpty);
        }
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('all locations toggle exposes healthy locations in the list', (
    tester,
  ) async {
    (person.body as HumanoidBody).puncturedSpleen = true;
    await _mountPanel(tester, person);
    expect(_key('injury-row:spleen'), findsOneWidget);
    expect(_key('injury-row:left-leg'), findsNothing);
    await _tap(tester, 'injury-all-locations');
    expect(_key('injury-row:left-leg'), findsOneWidget);
    await _tap(tester, 'injury-row:left-leg');
    expect(_key('injury-detail:left-leg'), findsOneWidget);
  });

  testWidgets('blood loss remains visible without creating local injuries', (
    tester,
  ) async {
    person.blood = person.maxBlood ~/ 5;
    await _mountPanel(tester, person);
    expect(
      find.textContaining('${person.blood} / ${person.maxBlood}'),
      findsWidgets,
    );
    expect(
      injuryLocations(person).where((location) => location.affected),
      isEmpty,
    );
    expect(_key('injury-map'), findsOneWidget);
    await _tap(tester, 'injury-zone:torso');
    expect(_key('injury-detail:torso'), findsOneWidget);
    expect(_detailText('torso', tester).toLowerCase(), isNot(contains('shot')));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'multiple organs have distinct accurate markers and persistent details',
    (tester) async {
      (person.body as HumanoidBody)
        ..puncturedRightLung = true
        ..puncturedLeftKidney = true
        ..puncturedHeart = true
        ..torso.shot = true
        ..torso.relativeHealth = .74;
      person.blood = person.maxBlood ~/ 2;
      await _mountPanel(tester, person);
      for (final id in ['right-lung', 'left-kidney', 'heart']) {
        expect(_key('injury-marker:$id'), findsOneWidget);
        await _tap(tester, 'injury-row:$id');
        final model = injuryLocations(
          person,
        ).singleWhere((location) => location.id == id);
        final text = _detailText(id, tester);
        expect(text, contains(model.name));
        for (final finding in model.findings) {
          expect(text, contains(finding));
        }
        for (final effect in model.effects) {
          expect(text, contains(effect));
        }
        expect(text, contains(model.care));
      }
    },
  );

  testWidgets(
    'amputation and stabilized spinal disability remain inspectable',
    (tester) async {
      (person.body as HumanoidBody)
        ..leftArm.cleanOff = true
        ..upperSpine = InjuryState.treated;
      person.hasWheelchair = true;
      await _mountPanel(tester, person);
      for (final id in ['left-arm', 'upper-spine']) {
        await _tap(tester, 'injury-row:$id');
        final model = injuryLocations(
          person,
        ).singleWhere((location) => location.id == id);
        final text = _detailText(id, tester);
        for (final finding in model.findings) {
          expect(text, contains(finding));
        }
        expect(text, contains(model.care));
      }
      expect(person.body.fullParalysis, isTrue);
      expect(person.body.armok, 0);
      expect(person.body.canWalk, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'every simultaneous special marker selects itself at its visible center',
    (tester) async {
      (person.body as HumanoidBody)
        ..puncturedRightLung = true
        ..puncturedLeftLung = true
        ..puncturedHeart = true
        ..puncturedLiver = true
        ..puncturedStomach = true
        ..puncturedRightKidney = true
        ..puncturedLeftKidney = true
        ..puncturedSpleen = true
        ..neck = InjuryState.untreated
        ..upperSpine = InjuryState.untreated
        ..lowerSpine = InjuryState.treated
        ..missingRightEye = true
        ..missingLeftEye = true
        ..missingNose = true
        ..missingTongue = true
        ..teeth = 0
        ..ribs = 0;
      await _mountPanel(tester, person);
      for (final id in [
        'right-lung',
        'left-lung',
        'heart',
        'liver',
        'stomach',
        'right-kidney',
        'left-kidney',
        'spleen',
        'neck',
        'upper-spine',
        'lower-spine',
        'right-eye',
        'left-eye',
        'nose',
        'tongue',
        'teeth',
        'ribs',
      ]) {
        await _tap(tester, 'injury-marker:$id');
        expect(
          _key('injury-detail:$id'),
          findsOneWidget,
          reason: '$id must not be hidden by a neighboring marker hit target.',
        );
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'nonhuman anatomy uses a selectable named list without human map',
    (tester) async {
      person.body = dogBody();
      final body = person.body as HumanoidBody;
      body.leftArm
        ..cut = true
        ..bleeding = 1;
      await _mountPanel(tester, person);
      expect(_key('injury-map'), findsNothing);
      final location = injuryLocations(
        person,
      ).firstWhere((location) => location.affected);
      expect(location.region, isNull);
      await _tap(tester, 'injury-row:${location.id}');
      expect(_detailText(location.id, tester), contains('Left Front Leg'));
      expect(tester.takeException(), isNull);
    },
  );

  for (final viewport in [
    (const Size(1280, 800), 1.0),
    (const Size(800, 600), 1.5),
    (const Size(390, 844), 2.0),
  ]) {
    testWidgets(
      'dossier injuries scroll and close at ${viewport.$1} ${viewport.$2}x',
      (tester) async {
        (person.body as HumanoidBody)
          ..puncturedRightLung = true
          ..leftLeg.bruised = true
          ..leftLeg.relativeHealth = .97
          ..torso.shot = true
          ..torso.relativeHealth = .74;
        person.blood = person.maxBlood ~/ 5;
        await _mountPanel(
          tester,
          person,
          size: viewport.$1,
          reading: viewport.$2,
          dossier: true,
        );
        expect(_key('crew-injury-panel'), findsOneWidget);
        await _tap(tester, 'injury-row:right-lung');
        await tester.ensureVisible(_key('injury-detail:right-lung'));
        await tester.pumpAndSettle();
        expect(_key('injury-detail:right-lung').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _tap(tester, 'crew-dossier-close');
        expect(find.byType(CrewDossier), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'dead condition remains inspectable without a live combat-readiness claim',
    (tester) async {
      person.alive = false;
      person.blood = 0;
      (person.body as HumanoidBody).torso.shot = true;
      await _mountPanel(tester, person);
      await _tap(tester, 'injury-zone:torso');
      expect(_key('injury-detail:torso'), findsOneWidget);
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data ?? widget.textSpan?.toPlainText() ?? '')
          .join('\n')
          .toLowerCase();
      expect(texts, anyOf(contains('dead'), contains('deceased')));
      expect(texts, isNot(contains('ready for combat')));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('inspection preserves campaign, RNG and pending engine input', (
    tester,
  ) async {
    (person.body as HumanoidBody)
      ..puncturedLeftLung = true
      ..rightArm.bleeding = 2;
    final before = jsonEncode(game.gameState);
    final date = game.date;
    final funds = game.ledger.funds;
    var inputConsumed = false;
    late Future<int> reader;
    // The engine reader is an external asynchronous resource. Keep its
    // completion outside the widget clock so cleanup also works after a failed
    // widget expectation; none of the UI actions may complete this reader.
    await tester.runAsync(() async {
      reader = engine.getKey().then((value) {
        inputConsumed = true;
        return value;
      });
    });
    addTearDown(() async {
      await tester.runAsync(() async {
        if (!inputConsumed) engine.console.sendInput('Enter');
        await reader;
      });
    });
    reseedRNG(seed: 60173);
    final expectedRolls = List.generate(12, (_) => lcsRandom(100000));
    reseedRNG(seed: 60173);
    await _mountPanel(tester, person, dossier: true);
    await _tap(tester, 'injury-row:left-lung');
    await _tap(tester, 'injury-all-locations');
    await _tap(tester, 'injury-row:left-leg');
    await _tabTo(tester, 'injury-zone:right-arm');
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(CrewDossier), findsNothing);
    expect(inputConsumed, isFalse);
    expect(engine.console.awaitingInput, isTrue);
    expect(jsonEncode(game.gameState), before);
    expect(game.date, date);
    expect(game.ledger.funds, funds);
    expect(List.generate(12, (_) => lcsRandom(100000)), expectedRolls);
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      expect(engine.console.sendInput('Enter'), isTrue);
      await reader;
    });
    expect(inputConsumed, isTrue);
  });
}
