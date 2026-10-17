import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/modern/journal_title.dart';
import 'package:lcs_new_age/utils/game_version.dart';

Console titleConsole({bool canContinue = false, bool hasSaves = false}) {
  final console = Console()..screen = 'title';
  const labels = {
    'C': 'C - Continue as &GBernie Spitzer&x',
    'N': 'N - Start a New Game',
    'L': 'L - Load & Manage Saves',
    'I': 'I - Import a Save',
    'O': 'O - Gameplay Options',
    'H': 'H - View High Scores',
    'V': 'V - View Changelog',
    'M': 'M - Mod Tools',
  };
  for (final entry in labels.entries) {
    console.move(console.actions.length, 0);
    console.addAction(
      entry.key,
      entry.value,
      enabled: entry.key == 'C'
          ? canContinue
          : entry.key == 'L'
          ? hasSaves
          : entry.key != 'H',
      caseSensitive: true,
    );
  }
  return console;
}

Future<void> mountTitle(
  WidgetTester tester,
  Console console, {
  Size size = const Size(1280, 900),
  double textScale = 1,
  ValueChanged<String>? onAction,
  VoidCallback? onHelp,
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
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: JournalTitlePage(
            console: console,
            onAction: onAction ?? (_) {},
            onHelp: onHelp ?? () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder actionButton(String key) =>
    find.byKey(ValueKey('journal-title-action:$key'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final serif = FontLoader('JournalSerif')
      ..addFont(rootBundle.load('fonts/journal/LibreBaskerville-Variable.ttf'));
    final fallback = FontLoader('ModernSans')
      ..addFont(rootBundle.load('fonts/modern/roboto-regular.ttf'));
    await Future.wait([serif.load(), fallback.load()]);
  });

  testWidgets(
    'all original actions, disabled states and author credit remain available',
    (tester) async {
      final console = titleConsole();
      await mountTitle(tester, console);
      expect(find.text('Liberal Crime Squad: New Age'), findsOneWidget);
      expect(find.text('THE UNDERGROUND EDITION'), findsOneWidget);
      expect(find.text('Continue as Bernie Spitzer'), findsOneWidget);
      for (final action in console.actions) {
        final button = tester.widget<ButtonStyleButton>(
          actionButton(action.key),
        );
        expect(button.onPressed != null, action.enabled);
      }
      expect(
        find.text('No recent campaign is available to continue.'),
        findsOneWidget,
      );
      expect(find.text('No saved campaigns are available.'), findsOneWidget);
      expect(
        find.textContaining('Original game by Tarn Adams'),
        findsOneWidget,
      );
      expect(find.textContaining('New Age by Ashley S. Fox'), findsOneWidget);
      expect(find.textContaining('GPL-2.0'), findsOneWidget);
      expect(find.textContaining(gameVersionLabel), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'source keys are forwarded exactly and a stale callback cannot affect a new frame',
    (tester) async {
      final console = titleConsole(canContinue: true, hasSaves: true);
      final received = <String>[];
      await mountTitle(tester, console, onAction: received.add);
      final retained = tester
          .widget<ButtonStyleButton>(actionButton('C'))
          .onPressed!;
      await tester.tap(actionButton('C'));
      expect(received, ['C']);
      console.flush();
      retained();
      expect(received, ['C']);
      await tester.pumpAndSettle();
      final current = tester
          .widget<ButtonStyleButton>(actionButton('N'))
          .onPressed!;
      console.screen = 'generic';
      current();
      expect(received, ['C']);
    },
  );

  testWidgets('load remains usable when there is no recent continue target', (
    tester,
  ) async {
    final console = titleConsole(hasSaves: true);
    final received = <String>[];
    await mountTitle(tester, console, onAction: received.add);
    expect(
      tester.widget<ButtonStyleButton>(actionButton('C')).onPressed,
      isNull,
    );
    await tester.tap(actionButton('L'));
    expect(received, ['L']);
  });

  testWidgets(
    'future source actions and guide remain reachable without hardcoded menu filtering',
    (tester) async {
      final console = titleConsole();
      console.move(10, 0);
      console.addAction('Q', 'Q - Extra source option', caseSensitive: true);
      final received = <String>[];
      var guideCount = 0;
      await mountTitle(
        tester,
        console,
        onAction: received.add,
        onHelp: () => guideCount++,
      );
      await tester.ensureVisible(actionButton('Q'));
      await tester.tap(actionButton('Q'));
      expect(received, ['Q']);
      await tester.ensureVisible(
        find.byKey(const ValueKey('journal-title-help')),
      );
      await tester.tap(find.byKey(const ValueKey('journal-title-help')));
      expect(guideCount, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [
    const Size(1280, 720),
    const Size(800, 600),
    const Size(360, 640),
  ]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets(
        'journal menu scrolls without clipping at $size and ${scale * 100}%',
        (tester) async {
          final console = titleConsole(canContinue: true, hasSaves: true);
          final received = <String>[];
          await mountTitle(
            tester,
            console,
            size: size,
            textScale: scale,
            onAction: received.add,
          );
          expect(tester.takeException(), isNull);
          for (final action in console.actions.where(
            (action) => action.enabled,
          )) {
            await tester.ensureVisible(actionButton(action.key));
            await tester.pumpAndSettle();
            await tester.tap(actionButton(action.key));
            expect(received.last, action.key);
            expect(tester.takeException(), isNull);
          }
          await tester.ensureVisible(find.textContaining('GPL-2.0'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
