import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/basemode/base_mode.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/location/siege.dart';
import 'package:lcs_new_age/modern/headquarters_view.dart';
import 'package:lcs_new_age/saveload/save_load.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String fixture;

  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
    final fonts = FontLoader('ModernSans');
    for (final weight in ['regular', 'medium', 'bold', 'black']) {
      fonts.addFont(rootBundle.load('fonts/modern/roboto-$weight.ttf'));
    }
    await fonts.load();
  });

  setUp(() {
    game.gameState = decodeSaveContents(fixture).gameState!;
    game.activeSquadMember = null;
    engine.console = Console();
    final original = game.squad.first;
    final squad = game.activeSquad!;
    for (var i = game.squad.length; i < 5; i++) {
      final person =
          Creature.fromJson(
              jsonDecode(jsonEncode(original)) as Map<String, dynamic>,
            )
            ..id = 100 + i
            ..name = 'Crew member ${i + 1}'
            ..squadId = null
            ..activity = Activity(ActivityType.sellArt);
      game.pool.add(person);
      person.squad = squad;
    }
    baseModeSquadSafehouseDisplay(squad.site);
    baseModeOptionsDisplay(squad.site);
  });

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(1040, 610),
    double textScale = 1,
    ValueChanged<String>? onAction,
    ValueChanged<Creature>? onInspect,
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
        theme: ThemeData(useMaterial3: true, fontFamily: 'ModernSans'),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: HeadquartersView(
            console: engine.console,
            onAction: onAction ?? (_) {},
            onInspect: onInspect ?? (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('five live crew fit the first HQ viewport with no banner gap', (
    tester,
  ) async {
    // 1040 x 610 is the content area remaining after desktop shell chrome in
    // a 1280 x 720 window. This checks useful content before any scroll.
    await mount(tester);
    for (final person in game.squad) {
      final row = find.byKey(ValueKey('hq-crew:${person.id}'));
      expect(row, findsOneWidget);
      expect(tester.getRect(row).top, greaterThanOrEqualTo(0));
      expect(tester.getRect(row).bottom, lessThanOrEqualTo(610));
      expect(row.hitTestable(), findsOneWidget);
    }
    expect(find.text('MOVEMENT FUNDS'), findsNothing);
    expect(find.text('OPERATIONS QUEUED'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('commands remain reachable and use their exact source keys', (
    tester,
  ) async {
    final received = <String>[];
    final actions = List<ConsoleAction>.of(engine.console.actions);
    await mount(tester, onAction: received.add);
    await tester.ensureVisible(
      find.byKey(const PageStorageKey('hq-more-commands')),
    );
    await tester.tap(find.text('More headquarters commands'));
    await tester.pumpAndSettle();
    for (final action in actions) {
      final key = action.key.toLowerCase();
      Finder finder;
      if (key == 'w') {
        finder = find.byKey(const ValueKey('hq-commit'));
      } else if (key == 'r') {
        finder = find.byKey(const ValueKey('hq-manage-crew'));
      } else if (action.entityType == 'person') {
        finder = find.byKey(ValueKey('hq-select:${action.entityId}'));
      } else {
        finder = find.byKey(ValueKey('hq-command:${action.key}'));
      }
      expect(finder, findsOneWidget, reason: action.label);
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      final before = received.length;
      await tester.tap(finder);
      await tester.pumpAndSettle();
      if (action.enabled) {
        expect(received.length, before + 1, reason: action.label);
        expect(received.last, action.key);
      } else {
        expect(received.length, before, reason: action.label);
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('portrait and dossier inspection are read-only and immediate', (
    tester,
  ) async {
    final received = <String>[];
    final inspected = <Creature>[];
    final before = jsonEncode(game.gameState.toJson());
    await mount(tester, onAction: received.add, onInspect: inspected.add);
    final person = game.squad.last;
    await tester.tap(find.byKey(ValueKey('hq-portrait:${person.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('hq-dossier:${person.id}')));
    await tester.pumpAndSettle();
    expect(inspected, [person, person]);
    expect(received, isEmpty);
    expect(jsonEncode(game.gameState.toJson()), before);
    expect(find.byType(Dialog), findsNothing);
  });

  testWidgets('queued destination and replacement task are explained honestly', (
    tester,
  ) async {
    final squad = game.activeSquad!;
    final site = game.sites.firstWhere((site) => site != squad.site);
    squad.activity = Activity(ActivityType.visit, idString: site.idString);
    final member = squad.members.last;
    member.activity = Activity(ActivityType.donations);
    engine.erase();
    baseModeSquadSafehouseDisplay(squad.site);
    baseModeOptionsDisplay(squad.site);
    final received = <String>[];
    await mount(tester, onAction: received.add);
    expect(find.text('Carry out your plans'), findsOneWidget);
    expect(find.text('Cancel Departure'), findsOneWidget);
    expect(
      find.textContaining('${squad.name} → ${site.getName(includeCity: true)}'),
      findsOneWidget,
    );
    expect(find.textContaining('Next day · 5 crew'), findsOneWidget);
    expect(
      find.text(
        'Squad visit overrides individual daily tasks on the next day.',
      ),
      findsOneWidget,
    );
    final row = find.byKey(ValueKey('hq-crew:${member.id}'));
    expect(
      find.descendant(of: row, matching: find.text(squad.activity.description)),
      findsOneWidget,
    );
    final hint = tester.widget<Tooltip>(
      find.descendant(of: row, matching: find.byType(Tooltip)).first,
    );
    expect(
      hint.message,
      contains('Replaces individual task: Soliciting Donations'),
    );
    await tester.tap(find.byKey(const ValueKey('hq-command:c')));
    await tester.pumpAndSettle();
    expect(received, ['c']);
    expect(squad.activity.type, ActivityType.visit);
    // Sending the command is all the view does; the source HQ handler owns it.
    expect(tester.takeException(), isNull);
  });

  testWidgets('siege controls and W wording follow the real HQ frame', (
    tester,
  ) async {
    final site = game.activeSquad!.site!;
    site.siege.activeSiegeType = SiegeType.police;
    engine.erase();
    baseModeSquadSafehouseDisplay(site);
    baseModeOptionsDisplay(site);
    await mount(tester);
    expect(find.text('Fight/Escape'), findsOneWidget);
    expect(find.text('Wait out the siege'), findsOneWidget);
    expect(find.text('Give Up'), findsOneWidget);
    expect(
      find.textContaining('Raw attention and secrecy points'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Heat ${site.heat} · Protection ${site.heatProtection}',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('an active attack never invents a day-advance command', (
    tester,
  ) async {
    final site = game.activeSquad!.site!;
    site.siege
      ..activeSiegeType = SiegeType.police
      ..underAttack = true;
    engine.erase();
    baseModeSquadSafehouseDisplay(site);
    baseModeOptionsDisplay(site);
    await mount(tester);
    expect(find.byKey(const ValueKey('hq-commit')), findsNothing);
    expect(find.text('Fight/Escape'), findsOneWidget);
    expect(
      find.text('Resolve the attack before advancing time.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('blood loss is visible without opening the dossier', (
    tester,
  ) async {
    final person = game.squad.last;
    person.blood = person.maxBlood ~/ 2;
    await mount(tester);
    final row = find.byKey(ValueKey('hq-crew:${person.id}'));
    expect(
      find.descendant(of: row, matching: find.text('Injured')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: row,
        matching: find.text('${person.blood}/${person.maxBlood} blood'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'narrow HQ shows crew before overview and scales without overflow',
    (tester) async {
      await mount(tester, size: const Size(600, 720), textScale: 1.3);
      final lastCrew = tester.getRect(
        find.byKey(ValueKey('hq-crew:${game.squad.last.id}')),
      );
      final overview = tester.getRect(find.text('THE MOVEMENT'));
      expect(overview.top, greaterThan(lastCrew.bottom));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a rendered command cannot fire after the engine frame changes', (
    tester,
  ) async {
    final received = <String>[];
    await mount(tester, onAction: received.add);
    engine.console.revision.value++;
    await tester.tap(find.byKey(const ValueKey('hq-commit')));
    await tester.pump();
    expect(received, isEmpty);
  });
}
