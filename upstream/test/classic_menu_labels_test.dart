import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/creation_context.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/modern/crew_dossier.dart';
import 'package:lcs_new_age/modern/journal_creation.dart';
import 'package:lcs_new_age/modern/journal_shortcuts.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/journal_title.dart';
import 'package:lcs_new_age/saveload/save_load.dart';

import 'test_support.dart';

Future<void> _mount(WidgetTester tester, Widget page) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 800);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: buildJournalTheme(),
      home: Scaffold(body: page),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _badge(String key) => find.byKey(ValueKey('journal-shortcut:$key'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String fixture;

  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
    final serif = FontLoader('JournalSerif')
      ..addFont(rootBundle.load('fonts/journal/LibreBaskerville-Variable.ttf'));
    final sans = FontLoader('ModernSans')
      ..addFont(rootBundle.load('fonts/modern/roboto-regular.ttf'));
    await Future.wait([serif.load(), sans.load()]);
  });

  setUp(() {
    game.gameState = decodeSaveContents(fixture).gameState!;
  });

  testWidgets('title badges retain each current source key and case', (
    tester,
  ) async {
    final console = Console()..screen = 'title';
    console.addAction('N', 'N - Start a New Game');
    console.addAction('Q', 'Q - Extra source action', caseSensitive: true);
    final sent = <String>[];
    await _mount(
      tester,
      JournalTitlePage(console: console, onAction: sent.add, onHelp: () {}),
    );
    for (final key in ['n', 'Q']) {
      final control = find.byKey(ValueKey('journal-title-action:$key'));
      expect(
        find.descendant(of: control, matching: _badge(key)),
        findsOneWidget,
      );
    }
    expect(find.text('N'), findsOneWidget);
    expect(find.text('Shift+Q'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(JournalShortcutBadge),
        matching: find.byType(Focus),
      ),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('journal-title-action:n')));
    expect(sent, ['n']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('creation metadata uses its resolved source key without Shift', (
    tester,
  ) async {
    final creation = CreationContext(
      stage: CreationStage.setup,
      title: 'Campaign dossier',
      fields: const [
        CreationField(key: 'A', label: 'Political climate', value: 'Current'),
        CreationField(
          key: 'B',
          label: 'Unavailable source field',
          value: 'None',
        ),
      ],
    );
    final console = Console()..creation = creation;
    console.addAction('A', 'A - Political climate');
    unawaited(console.getkey());
    addTearDown(() => console.sendInput('Escape'));
    final sent = <String>[];
    await _mount(
      tester,
      JournalCreationPage(
        console: console,
        context: creation,
        onAction: sent.add,
        inputBar: const SizedBox.shrink(),
      ),
    );
    final available = find.byKey(const ValueKey('creation-field:A'));
    final unavailable = find.byKey(const ValueKey('creation-field:B'));
    expect(
      find.descendant(of: available, matching: _badge('a')),
      findsOneWidget,
    );
    expect(find.text('Shift+A'), findsNothing);
    expect(
      find.descendant(
        of: unavailable,
        matching: find.byType(JournalShortcutBadge),
      ),
      findsNothing,
    );
    await tester.tap(available);
    expect(sent, ['a']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile page hint requires source keys and a page callback', (
    tester,
  ) async {
    final person = game.pool.first;
    await _mount(
      tester,
      CrewDossier(
        person: person,
        embedded: true,
        pageShortcuts: const ['Up', 'Down'],
        onPage: (_) {},
      ),
    );
    expect(_badge('Up'), findsOneWidget);
    expect(_badge('Down'), findsOneWidget);
    expect(find.text('More info'), findsOneWidget);
    await _mount(
      tester,
      CrewDossier(person: person, embedded: true, onPage: (_) {}),
    );
    expect(_badge('Up'), findsNothing);
    expect(_badge('Down'), findsNothing);
    await _mount(
      tester,
      CrewDossier(
        person: person,
        embedded: true,
        pageShortcuts: const ['Up', 'Down'],
      ),
    );
    expect(find.text('More info'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
