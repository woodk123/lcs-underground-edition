import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/engine/journal_context.dart';
import 'package:lcs_new_age/engine/pursuit_context.dart';
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/modern/journal_pursuit.dart';
import 'package:lcs_new_age/modern/journal_shortcuts.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/sitemode/chase_sequence.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';
import 'package:lcs_new_age/vehicles/vehicle.dart';
import 'package:lcs_new_age/vehicles/vehicle_type.dart';

import 'test_support.dart';

Finder _action(String key) =>
    find.byKey(ValueKey('journal-pursuit-action:$key'));
String _snapshot() => jsonEncode(game.gameState.toJson());

/// Authored reader fixtures exercise presentation without deciding car rules.
/// Engine regressions separately run the real pursuit and obstacle handlers.
class _PursuitReaders {
  _PursuitReaders({this.wholeCrew = false, this.fullCommands = false}) {
    unawaited(_run());
  }

  final bool wholeCrew;
  final bool fullCommands;
  final commands = <int>[];
  bool obstacle = false, finished = false;

  void _publish() {
    engine.erase();
    final person = game.pool.first;
    final actions = <ConsoleAction>[
      ConsoleAction(
        key: 'd',
        label: obstacle ? 'D-Swerve around' : 'Drive hard to escape',
        enabled: true,
        y: 12,
        x: 1,
        width: 20,
      ),
      ConsoleAction(
        key: 'f',
        label: obstacle ? 'F-Slow down' : 'Fight',
        enabled: true,
        y: 12,
        x: 23,
        width: 12,
      ),
      const ConsoleAction(
        key: 'e',
        label: 'Equipment',
        enabled: true,
        y: 13,
        x: 1,
        width: 12,
      ),
      const ConsoleAction(
        key: '0',
        label: 'Show squad status',
        enabled: true,
        y: 13,
        x: 15,
        width: 18,
      ),
      if (!obstacle) ...[
        const ConsoleAction(
          key: 'b',
          label: 'Bail out and run',
          enabled: false,
          y: 14,
          x: 1,
          width: 18,
        ),
        const ConsoleAction(
          key: 'p',
          label: 'Pull over and surrender',
          enabled: true,
          y: 14,
          x: 22,
          width: 25,
        ),
      ],
    ];
    if (fullCommands) {
      final status = actions.singleWhere((action) => action.key == '0');
      actions.remove(status);
      actions.insert(
        3,
        const ConsoleAction(
          key: 'o',
          label: 'Squad orders',
          enabled: false,
          y: 13,
          x: 1,
          width: 14,
        ),
      );
      actions.add(status);
    }
    engine.console.actions.addAll(actions);
    engine.console.screen = 'pursuit';
    engine.console.pursuit = PursuitContext(
      title: 'Car pursuit',
      threatSummary: wholeCrew ? 'Pursuers: 8' : 'Pursuing vehicles: 1',
      location: 'Downtown',
      note: 'Pulling over ends the pursuit in police custody.',
      statusLines: [
        'Police Cruiser is 45 feet back.',
        if (obstacle)
          'A truck pulls out!'
        else
          'Headlights flash in your mirrors.',
      ],
      people: [
        for (final person in wholeCrew ? game.squad : [person])
          JournalPersonSummary(
            person: person,
            name: person.name,
            role: person.title,
            health: 'Healthy',
            equipment: const ['Transport: Red Sportscar (driver)'],
            details: const ['Driving: 0'],
          ),
      ],
      encounterLines: wholeCrew
          ? [for (var i = 1; i <= 8; i++) '$i Police officer — 9mm pistol']
          : const ['Police Officer — Police Cruiser'],
      actions: actions,
    );
  }

  Future<void> _run() async {
    try {
      while (true) {
        _publish();
        final key = await engine.getKey();
        commands.add(key);
        if (key == engine.Key.p) break;
        if (key == engine.Key.d) obstacle = true;
        if (key == engine.Key.f && obstacle) obstacle = false;
        if (key == engine.Key.e) {
          engine.erase();
          engine.addOptionText(0, 0, 'Enter', 'Done with equipment');
          await engine.getKey();
        }
      }
    } finally {
      finished = true;
      engine.erase();
      engine.console.flush();
    }
  }

  Future<void> stop(WidgetTester tester) async {
    for (var attempt = 0; attempt < 12 && !finished; attempt++) {
      if (engine.console.awaitingInput) {
        engine.console.sendInput(
          pursuitContext(engine.console) == null ? 'Enter' : 'p',
        );
      }
      await tester.pump();
    }
    expect(finished, isTrue);
  }
}

class _ActualCarReader {
  _ActualCarReader() {
    final car = Vehicle(VehicleTypeIds.sportsCar);
    game.vehiclePool.add(car);
    for (final person in game.squad) {
      person.carId = car.id;
      person.isDriver = person == game.squad.first;
    }
    game.activeSquadMemberIndex = -1;
    game.chaseSequence = ChaseSequence(game.squad.first.site!);
    makeChasers(SiteType.policeStation, 1);
    void announcements() {
      if (pursuitContext(engine.console) != null) {
        engine.console.revision.removeListener(announcements);
      } else if (engine.console.awaitingInput &&
          engine.console.lastKey == null &&
          engine.console.eventMessage != null) {
        engine.console.sendInput('Enter');
      }
    }

    engine.console.revision.addListener(announcements);
    unawaited(
      _run().whenComplete(
        () => engine.console.revision.removeListener(announcements),
      ),
    );
  }

  bool finished = false;
  ChaseOutcome? outcome;

  Future<void> _run() async {
    try {
      outcome = await carChaseSequence();
    } finally {
      finished = true;
      engine.erase();
      engine.console.flush();
    }
  }

  Future<void> stop(WidgetTester tester) async {
    for (var attempt = 0; attempt < 20 && !finished; attempt++) {
      if (engine.console.awaitingInput) {
        engine.console.sendInput(
          pursuitContext(engine.console) == null ? 'Enter' : 'p',
        );
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(finished, isTrue);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String fixture;
  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
    final font = FontLoader('JournalSerif')
      ..addFont(rootBundle.load('fonts/journal/LibreBaskerville-Variable.ttf'));
    await font.load();
  });
  setUp(() {
    game.gameState = decodeSaveContents(fixture).gameState!;
    game.mode = GameMode.carChase;
    engine.console = Console();
    journalReadingScale.value = 1;
  });

  Future<_PursuitReaders> mount(
    WidgetTester tester, {
    Size size = const Size(1200, 800),
    double scale = 1,
    bool wholeCrew = false,
    bool fullCommands = false,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    journalReadingScale.value = scale;
    final readers = _PursuitReaders(
      wholeCrew: wholeCrew,
      fullCommands: fullCommands,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await readers.stop(tester);
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });
    await tester.pumpWidget(const MainApp());
    await tester.pumpAndSettle();
    expect(find.byType(JournalPursuitView), findsOneWidget);
    return readers;
  }

  for (final (size, scale) in [
    (const Size(1280, 800), 1.0),
    (const Size(800, 600), 1.5),
    (const Size(390, 844), 2.0),
  ]) {
    testWidgets('raid pursuers precede a full crew at $size/$scale', (
      tester,
    ) async {
      await mount(tester, size: size, scale: scale, wholeCrew: true);
      final before = _snapshot();
      expect(
        find
            .byKey(const ValueKey('journal-pursuit-threat-summary'))
            .hitTestable(),
        findsOneWidget,
      );
      reseedRNG(seed: 92014);
      final expected = lcsRandom(100000);
      reseedRNG(seed: 92014);
      final list = find
          .descendant(
            of: find.byKey(const ValueKey('journal-pursuit-scroll')),
            matching: find.byType(Scrollable),
          )
          .first;
      if (size.width < 400) {
        await tester.scrollUntilVisible(
          find.text('1 Police officer — 9mm pistol'),
          80,
          scrollable: list,
        );
      }
      expect(
        find.text('1 Police officer — 9mm pistol').hitTestable(),
        findsOneWidget,
      );
      expect(_action('d').hitTestable(), findsOneWidget);
      final crewHeading = find.text('Crew (${game.squad.length})');
      await tester.scrollUntilVisible(
        crewHeading,
        180,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('journal-pursuit-scroll')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(crewHeading.hitTestable(), findsOneWidget);
      await tester.tap(crewHeading);
      await tester.pumpAndSettle();
      await tester.ensureVisible(crewHeading);
      await tester.pumpAndSettle();
      expect(crewHeading.hitTestable(), findsOneWidget);
      await tester.tap(crewHeading);
      await tester.pumpAndSettle();
      expect(_snapshot(), before);
      expect(lcsRandom(100000), expected);
      expect(_action('d').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'actual car animation preserves live actions, campaign state and random rolls',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      final reader = _ActualCarReader();
      addTearDown(() async {
        engine.console.repaint = null;
        await tester.pumpWidget(const SizedBox.shrink());
        await reader.stop(tester);
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      await tester.pumpWidget(const MainApp());
      await tester.pumpAndSettle();
      expect(find.text('Car pursuit'), findsOneWidget);
      final frame = pursuitContext(engine.console)!;
      expect(frame.statusLines, isNotEmpty);
      expect(frame.encounterLines, isNotEmpty);
      expect(frame.people.map((summary) => summary.person), game.squad);
      final revision = engine.console.revision.value;
      final surrender = tester.widget<OutlinedButton>(_action('p')).onPressed!;
      final snapshot = _snapshot();
      reseedRNG(seed: 70013);
      final expected = lcsRandom(100000);
      reseedRNG(seed: 70013);
      var cosmeticRepaints = 0;
      final repaint = engine.console.repaint;
      engine.console.repaint = () {
        cosmeticRepaints++;
        repaint?.call();
      };
      for (var tick = 0; tick < 4; tick++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(cosmeticRepaints, greaterThan(0));
      expect(engine.console.revision.value, revision);
      expect(pursuitContext(engine.console), same(frame));
      expect(_snapshot(), snapshot);
      expect(lcsRandom(100000), expected);
      // The callback was retained before the real classic animation repainted.
      surrender();
      await tester.pumpAndSettle();
      expect(engine.console.eventMessage, 'You pull over and are arrested.');
      expect(find.text('You pull over and are arrested.'), findsOneWidget);
      expect(pursuitContext(engine.console), isNull);
      await reader.stop(tester);
      expect(reader.outcome, ChaseOutcome.capture);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('car road and obstacle show only their authored controls', (
    tester,
  ) async {
    final readers = await mount(tester);
    expect(find.text('Car pursuit'), findsOneWidget);
    expect(find.text('Police Cruiser is 45 feet back.'), findsOneWidget);
    expect(find.text('Headlights flash in your mirrors.'), findsOneWidget);
    expect(find.text('Fight'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(_action('b')).onPressed, isNull);
    expect(tester.widget<OutlinedButton>(_action('p')).onPressed, isNotNull);
    final oldFight = tester.widget<OutlinedButton>(_action('f')).onPressed!;
    final oldSurrender = tester.widget<OutlinedButton>(_action('p')).onPressed!;
    await tester.tap(_action('d'));
    await tester.pumpAndSettle();
    expect(find.text('A truck pulls out!'), findsOneWidget);
    expect(
      find.descendant(of: _action('f'), matching: find.text('Slow down')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _action('f'), matching: find.text('F')),
      findsOneWidget,
    );
    expect(find.text('Fight'), findsNothing);
    expect(_action('b'), findsNothing);
    expect(_action('p'), findsNothing);
    final count = readers.commands.length;
    oldFight();
    oldSurrender();
    await tester.pump();
    expect(readers.commands.length, count);
    await tester.tap(_action('f'));
    await tester.pumpAndSettle();
    expect(readers.commands.last, engine.Key.f);
    expect(find.text('Fight'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('nested equipment and squad status reject retained callbacks', (
    tester,
  ) async {
    final readers = await mount(tester);
    final old = tester.widget<OutlinedButton>(_action('p')).onPressed!;
    await tester.tap(_action('e'));
    await tester.pumpAndSettle();
    expect(find.byType(JournalPursuitView), findsNothing);
    expect(pursuitContext(engine.console), isNull);
    old();
    expect(engine.console.lastKey, isNull);
    engine.console.sendInput('Enter');
    await tester.pumpAndSettle();
    expect(_action('p').hitTestable(), findsOneWidget);
    old();
    expect(engine.console.lastKey, isNull);
    final statusOld = tester.widget<OutlinedButton>(_action('p')).onPressed!;
    await tester.tap(_action('0'));
    await tester.pumpAndSettle();
    statusOld();
    expect(engine.console.lastKey, isNull);
    expect(readers.commands, [engine.Key.e, engine.Key.num0]);
    await tester.tap(_action('p'));
    await tester.pumpAndSettle();
    expect(readers.finished, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'car inspection blocks keyboard and retained actions without changing state or RNG',
    (tester) async {
      final readers = await mount(tester);
      final person = game.pool.first;
      final snapshot = _snapshot();
      final revision = engine.console.revision.value;
      reseedRNG(seed: 70013);
      final expected = lcsRandom(100000);
      reseedRNG(seed: 70013);
      final surrender = tester.widget<OutlinedButton>(_action('p')).onPressed!;
      await tester.tap(find.byTooltip('Inspect ${person.name}'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      surrender();
      await tester.pumpAndSettle();
      expect(readers.commands, isEmpty);
      expect(engine.console.revision.value, revision);
      expect(_snapshot(), snapshot);
      expect(lcsRandom(100000), expected);
      await tester.tap(find.byTooltip('Close dossier'));
      await tester.pumpAndSettle();
      await tester.tap(_action('p'));
      await tester.pumpAndSettle();
      expect(readers.finished, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('pursuit command semantics follows live reading-scale reflow', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    try {
      await mount(tester, size: const Size(800, 600), fullCommands: true);
      final frame = pursuitContext(engine.console);
      final revision = engine.console.revision.value;
      final before = _snapshot();
      reseedRNG(seed: 852016);
      final expected = lcsRandom(100000);
      reseedRNG(seed: 852016);

      void expectAlignedCommand() {
        final node = tester.getSemantics(_action('p'));
        var transform = Matrix4.identity();
        for (
          SemanticsNode? current = node;
          current != null;
          current = current.parent
        ) {
          transform = (current.transform ?? Matrix4.identity()) * transform;
        }
        final semanticBounds = MatrixUtils.transformRect(transform, node.rect);
        final paintedBounds = tester.getRect(_action('p'));
        expect(semanticBounds.top, closeTo(paintedBounds.top, .01));
        expect(semanticBounds.bottom, closeTo(paintedBounds.bottom, .01));
        expect(semanticBounds.bottom, lessThanOrEqualTo(600));
        expect(_action('p').hitTestable(), findsOneWidget);
      }

      expectAlignedCommand();
      journalReadingScale.value = 1.5;
      await tester.pumpAndSettle();
      expectAlignedCommand();
      journalReadingScale.value = 1;
      await tester.pumpAndSettle();
      expectAlignedCommand();
      expect(pursuitContext(engine.console), same(frame));
      expect(engine.console.revision.value, revision);
      expect(_snapshot(), before);
      expect(lcsRandom(100000), expected);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('narrow pursuit commands reveal keyboard focus after reflow', (
    tester,
  ) async {
    final readers = await mount(
      tester,
      size: const Size(540, 600),
      fullCommands: true,
    );
    final before = _snapshot();
    final revision = engine.console.revision.value;
    reseedRNG(seed: 852017);
    final expected = lcsRandom(100000);
    reseedRNG(seed: 852017);
    journalReadingScale.value = 1.5;
    await tester.pumpAndSettle();
    final scroller = find
        .ancestor(of: _action('0'), matching: find.byType(Scrollable))
        .first;
    final position = tester.state<ScrollableState>(scroller).position;
    expect(position.maxScrollExtent, greaterThan(0));
    FocusNode commandFocus(String key) => Focus.of(
      tester.element(
        find.descendant(
          of: _action(key),
          matching: find.byType(JournalCommandLabel),
        ),
      ),
    );
    commandFocus('d').requestFocus();
    await tester.pumpAndSettle();
    for (var tab = 0; tab < 4; tab++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
    }
    final statusFocus = commandFocus('0');
    expect(statusFocus.hasPrimaryFocus, isTrue);
    expect(position.pixels, greaterThan(0));
    expect(_action('0').hitTestable(), findsOneWidget);
    journalReadingScale.value = 1;
    await tester.pumpAndSettle();
    expect(commandFocus('0'), same(statusFocus));
    expect(statusFocus.hasPrimaryFocus, isTrue);
    expect(_action('0').hitTestable(), findsOneWidget);
    expect(readers.commands, isEmpty);
    expect(engine.console.revision.value, revision);
    expect(_snapshot(), before);
    expect(lcsRandom(100000), expected);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'car actions stay reachable at 800x600 and 150 percent reading size',
    (tester) async {
      await mount(tester, size: const Size(800, 600), scale: 1.5);
      expect(find.text('Car pursuit').hitTestable(), findsOneWidget);
      expect(
        find.byKey(const ValueKey('journal-pursuit-status')).hitTestable(),
        findsOneWidget,
      );
      expect(_action('p').hitTestable(), findsOneWidget);
      expect(tester.getRect(_action('p')).bottom, lessThanOrEqualTo(600));
      await tester.drag(
        find.byKey(const ValueKey('journal-pursuit-scroll')),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      expect(_action('p').hitTestable(), findsOneWidget);
      await tester.tap(_action('d'));
      await tester.pumpAndSettle();
      expect(_action('f').hitTestable(), findsOneWidget);
      expect(_action('p'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
