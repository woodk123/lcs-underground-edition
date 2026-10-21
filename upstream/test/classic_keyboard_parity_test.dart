import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activate_regulars.dart';
import 'package:lcs_new_age/basemode/activate_sleepers.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/basemode/base_actions.dart';
import 'package:lcs_new_age/basemode/base_mode.dart';
import 'package:lcs_new_age/basemode/liberal_agenda.dart';
import 'package:lcs_new_age/basemode/media_overview.dart';
import 'package:lcs_new_age/basemode/plan_site_visit.dart';
import 'package:lcs_new_age/basemode/review_mode.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/console_widget.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/engine/organisation_context.dart';
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/modern/journal_preferences.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/newspaper/news_story.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_support.dart';

/// The real base dispatch boundary: every menu below is an original reader.
/// No graphical controller supplies the oracle's frames or selected actions.
class _SourceJourney {
  _SourceJourney({this.initialText});

  void start() {
    unawaited(_run());
  }

  final String? initialText;
  String? textResult;
  bool stopped = false, finished = false;
  final dispatched = <int>[];

  Future<void> _run() async {
    try {
      if (initialText != null) {
        engine.erase();
        textResult = await engine.mvgetstr(2, 0, starting: initialText);
      }
      while (!stopped) {
        engine.erase();
        final location = game.activeSquad?.site ?? game.activeSafehouse;
        baseModeSquadSafehouseDisplay(location);
        baseModeOptionsDisplay(location);
        final key = await engine.getKey();
        if (stopped) break;
        dispatched.add(key);
        switch (key) {
          case engine.Key.r:
            await reviewAssetsAndFormSquads();
          case engine.Key.a:
            await activateRegulars();
          case engine.Key.b:
            await activateSleepers();
          case engine.Key.f:
            await planSiteVisit();
          case engine.Key.c:
            game.activeSquad?.activity = Activity.none();
          case engine.Key.v:
            await setVehicles();
          case engine.Key.o:
            await orderparty();
          case engine.Key.m:
            await mediaOverview();
          case engine.Key.l:
            await liberalAgenda();
        }
      }
    } finally {
      finished = true;
    }
  }

  Future<void> stop(WidgetTester tester) async {
    stopped = true;
    for (var attempt = 0; attempt < 60 && !finished; attempt++) {
      if (engine.console.awaitingInput) {
        engine.console.sendInput(engine.console.textInput ? 'Enter' : 'Escape');
      }
      await tester.pump(const Duration(milliseconds: 5));
    }
    expect(finished, isTrue, reason: 'The real source readers must close.');
  }
}

enum _KeyPhase { press, down, repeat, up }

class _Step {
  const _Step(
    this.key, {
    this.phase = _KeyPhase.press,
    this.screen,
    this.activity,
    this.pendingText,
  }) : actionType = null,
       actionId = null;

  const _Step.action(this.actionType, {this.actionId, this.screen})
    : key = null,
      phase = _KeyPhase.press,
      activity = null,
      pendingText = null;

  final String? key, actionType, screen, pendingText;
  final String Function()? actionId;
  final ActivityType? activity;
  final _KeyPhase phase;

  String resolveOriginalKey() =>
      key ??
      engine.console.actions
          .singleWhere(
            (action) =>
                action.enabled &&
                action.entityType == actionType &&
                (actionId == null || action.entityId == actionId!()),
          )
          .key;
}

class _Journey {
  const _Journey(
    this.name,
    this.steps, {
    this.prepare,
    this.size = const Size(1440, 1000),
    this.scale = 1,
    this.initialText,
  });

  final String name;
  final List<_Step> steps;
  final VoidCallback? prepare;
  final Size size;
  final double scale;
  final String? initialText;
}

typedef _Checkpoint = ({
  Map<String, Object?> frame,
  Object campaign,
  List<int> rolls,
});
typedef _Trace = ({List<String> keys, List<_Checkpoint> checkpoints});

Future<void> _settle(WidgetTester tester) async {
  for (var frame = 0; frame < 40; frame++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  await tester.pumpAndSettle();
}

LogicalKeyboardKey _logicalKey(String key) => switch (key) {
  'Enter' => LogicalKeyboardKey.enter,
  'Escape' => LogicalKeyboardKey.escape,
  'Backspace' => LogicalKeyboardKey.backspace,
  'Up' => LogicalKeyboardKey.arrowUp,
  'Down' => LogicalKeyboardKey.arrowDown,
  'Left' => LogicalKeyboardKey.arrowLeft,
  'Right' => LogicalKeyboardKey.arrowRight,
  'PageUp' => LogicalKeyboardKey.pageUp,
  'PageDown' => LogicalKeyboardKey.pageDown,
  'Space' => LogicalKeyboardKey.space,
  _ => LogicalKeyboardKey(key.toLowerCase().codeUnitAt(0)),
};

String? _character(String key) => key.length == 1
    ? key
    : key == 'Space'
    ? ' '
    : null;

Future<void> _physicalKey(
  WidgetTester tester,
  String key,
  _KeyPhase phase, {
  required bool classic,
}) async {
  if (classic) {
    // Route the oracle through the actual legacy desktop keyboard handler,
    // including its KeyRepeatEvent support, not ModernGameShell's wrapper.
    tester.widget<ConsoleWidget>(find.byType(ConsoleWidget)).requestFocus();
  } else if (!engine.console.textInput) {
    tester
        .widgetList<Focus>(find.byType(Focus))
        .singleWhere(
          (widget) => widget.focusNode?.debugLabel == 'Game keyboard',
        )
        .focusNode!
        .requestFocus();
  }
  await tester.pump();
  final editing = !classic && engine.console.textInput;
  final before = editing
      ? tester.widget<EditableText>(find.byType(EditableText)).controller.value
      : null;
  final logical = _logicalKey(key);
  final character = _character(key);
  switch (phase) {
    case _KeyPhase.press:
      await tester.sendKeyEvent(logical, character: character);
    case _KeyPhase.down:
      await tester.sendKeyDownEvent(logical, character: character);
    case _KeyPhase.repeat:
      await tester.sendKeyRepeatEvent(logical, character: character);
    case _KeyPhase.up:
      await tester.sendKeyUpEvent(logical);
  }
  if (before != null &&
      character != null &&
      phase != _KeyPhase.up &&
      engine.console.textInput) {
    // A physical key plus the platform's text update models native typing.
    // Flutter's test keyboard does not itself generate IME character edits.
    // Preserve the real editor selection so selecting-all-on-entry is caught.
    final selection = before.selection;
    final start = selection.isValid ? selection.start : before.text.length;
    final end = selection.isValid ? selection.end : before.text.length;
    final text = before.text.replaceRange(start, end, character);
    tester.testTextInput.updateEditingValue(
      TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: start + character.length),
      ),
    );
  }
  await _settle(tester);
}

Map<String, Object?> _action(ConsoleAction action) => {
  'key': action.key,
  'label': action.label,
  'enabled': action.enabled,
  'position': [action.y, action.x, action.width],
  'intent': action.intentLabel,
  'entity': [action.entityType, action.entityId, action.entityCategory],
};

_Checkpoint _capture(
  WidgetTester tester,
  _SourceJourney source, {
  required bool classic,
}) {
  final console = engine.console;
  final navigation = console.navigation;
  final profile = console.journalProfile;
  final order = activityOrderFrame(console);
  return (
    frame: {
      'screen': console.screen,
      'awaitingInput': console.awaitingInput,
      'textInput': console.textInput,
      'pendingText': !console.textInput
          ? null
          : classic
          ? console.textInputValue
          : tester
                .widget<EditableText>(find.byType(EditableText))
                .controller
                .text,
      'textResult': source.textResult,
      'actions': console.actions.map(_action).toList(),
      'navigation': navigation == null
          ? null
          : [navigation.section, navigation.backKey, navigation.note],
      'profile': profile == null
          ? null
          : [
              profile.person.id,
              profile.page,
              profile.personIds,
              profile.canSelectPerson,
              profile.confirming,
            ],
      'orders': order == null
          ? null
          : [order.actorId, order.sleeper, order.selectedCategoryKey],
      // The graphical native editor batches its visible edits into mvgetstr
      // when Enter/Escape finishes it. Compare the visible pending text above
      // during editing, then the full original buffer after the terminal key.
      'buffer': console.textInput
          ? null
          : [for (final row in console.buffer) row.map((c) => c.glyph).join()],
      'selectedPerson': game.activeSquadMember?.id,
      'dispatched': List<int>.of(source.dispatched),
    },
    campaign: jsonDecode(jsonEncode(game.gameState.toJson())) as Object,
    // Mirrored probes after every key detect a UI consuming gameplay rolls.
    // Both presentations consume these same probes in the same sequence.
    rolls: List.generate(8, (_) => lcsRandom(1000000)),
  );
}

void _assertOriginalStep(_Step step, _Checkpoint checkpoint) {
  expect(checkpoint.frame['awaitingInput'], isTrue);
  if (step.screen != null) expect(checkpoint.frame['screen'], step.screen);
  if (step.pendingText != null) {
    expect(checkpoint.frame['pendingText'], step.pendingText);
  }
  if (step.activity != null) {
    final orders = activityOrderFrame(engine.console);
    final actor = orders == null
        ? null
        : game.pool.singleWhere((person) => person.id == orders.actorId);
    expect(actor?.activity.type, step.activity);
  }
}

Future<_Trace> _runJourney(
  WidgetTester tester,
  String fixture,
  _Journey journey, {
  required bool classic,
  _Trace? oracle,
}) async {
  SharedPreferences.setMockInitialValues({});
  journalReadingScale.value = journey.scale;
  journalPresentation.value = const JournalPreferenceValues();
  engine.console = Console();
  game.gameState = decodeSaveContents(fixture).gameState!;
  game.mode = GameMode.base;
  game.activeSquadMember = null;
  for (final person in game.pool) {
    person.activity = Activity.none();
  }
  game.activeSquad?.activity = Activity.none();
  journey.prepare?.call();
  reseedRNG(seed: 20261021);
  final source = _SourceJourney(initialText: journey.initialText);
  final keys = <String>[];
  final checkpoints = <_Checkpoint>[];
  try {
    await tester.pumpWidget(const MainApp());
    // Mount before beginning the source await so native text-entry setup sees
    // the same revision notification as it does in the running game.
    source.start();
    await _settle(tester);
    if (classic) {
      await tester.tap(find.byTooltip('Switch readable / classic view'));
      await _settle(tester);
    }
    checkpoints.add(_capture(tester, source, classic: classic));
    if (oracle != null) {
      _compareCheckpoint(
        checkpoints.first,
        oracle.checkpoints.first,
        'initial',
      );
    }
    for (var index = 0; index < journey.steps.length; index++) {
      final step = journey.steps[index];
      // Resolve authored entity letters only in Classic, then replay that
      // exact sequence even if graphical routing reaches a different menu.
      final key = oracle?.keys[index] ?? step.resolveOriginalKey();
      keys.add(key);
      await _physicalKey(tester, key, step.phase, classic: classic);
      final checkpoint = _capture(tester, source, classic: classic);
      checkpoints.add(checkpoint);
      final reason =
          '${journey.name}: key ${index + 1} $key (${step.phase.name})';
      if (oracle == null) {
        _assertOriginalStep(step, checkpoint);
      } else {
        _compareCheckpoint(checkpoint, oracle.checkpoints[index + 1], reason);
      }
    }
  } finally {
    // Unmount before changing globals. The previous source coroutine must
    // finish against its own Console before decoding the second campaign.
    await tester.pumpWidget(const SizedBox.shrink());
    await source.stop(tester);
  }
  return (keys: keys, checkpoints: checkpoints);
}

void _compareCheckpoint(_Checkpoint actual, _Checkpoint expected, String step) {
  expect(
    actual.frame,
    expected.frame,
    reason: '$step: source reader and choices',
  );
  expect(
    actual.campaign,
    expected.campaign,
    reason: '$step: complete campaign',
  );
  expect(actual.rolls, expected.rolls, reason: '$step: gameplay RNG');
}

void _addSleeper() {
  final sleeper = Creature.fromJson(
    jsonDecode(jsonEncode(game.pool.first.toJson())) as Map<String, dynamic>,
  );
  sleeper
    ..id = game.gameState.nextCreatureId++
    ..name = 'Parity Sleeper'
    ..squadId = null
    ..sleeperAgent = true
    ..activity = Activity.none();
  game.pool.add(sleeper);
  expect(sleeperOrderUnavailableReason(sleeper), isNull);
}

void _addArchive() {
  game.gameState.newsArchive.clear();
  for (var index = 0; index < 20; index++) {
    game.gameState.newsArchive.add(
      NewsStory()
        ..headline = 'Parity archive headline $index'
        ..body = 'A deterministic archived report, number $index.'
        ..date = game.date
        ..publication = Publication.times
        ..byline = 'Archive desk',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String fixture;
  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
    final serif = FontLoader('JournalSerif')
      ..addFont(rootBundle.load('fonts/journal/LibreBaskerville-Variable.ttf'))
      ..addFont(
        rootBundle.load('fonts/journal/LibreBaskerville-Italic-Variable.ttf'),
      );
    final sans = FontLoader('ModernSans');
    for (final weight in ['regular', 'medium', 'bold', 'black']) {
      sans.addFont(rootBundle.load('fonts/modern/roboto-$weight.ttf'));
    }
    await Future.wait([serif.load(), sans.load()]);
  });

  late String districtId;
  late String siteId;
  void prepareTravel() {
    final park = game.activeSquad!.site!.city.sites.singleWhere(
      (site) => site.type == SiteType.publicPark,
    );
    districtId = park.district.idString;
    siteId = park.idString;
  }

  final journeys = [
    const _Journey('R overview, finance caller, roster and profile return', [
      _Step('r', screen: 'organisation'),
      _Step('v'),
      _Step('Enter', screen: 'organisation'),
      _Step('1'),
      _Step('a'),
      _Step('Down'),
      _Step('Up'),
      _Step('Enter'),
      _Step('Enter', screen: 'organisation'),
      _Step('Enter', screen: 'headquarters'),
    ]),
    for (final compact in [false, true])
      _Journey(
        'ordinary task defaults and numeric choices${compact ? ' at 800px/150%' : ''}',
        const [
          _Step('a'),
          _Step('a', screen: 'activity-orders'),
          _Step('b', screen: 'activity-orders'),
          _Step('1', activity: ActivityType.donations),
          _Step('x', activity: ActivityType.none),
          _Step('a'),
          _Step('2', activity: ActivityType.trouble),
          _Step('Enter'),
          _Step('Enter', screen: 'headquarters'),
        ],
        size: compact ? const Size(1024, 720) : const Size(1440, 1000),
        scale: compact ? 1.5 : 1,
      ),
    const _Journey('sleeper category defaults and immediate numeric choices', [
      _Step('b'),
      _Step('a', screen: 'activity-orders'),
      _Step('a', activity: ActivityType.none),
      _Step('2', activity: ActivityType.sleeperLiberal),
      _Step('b', activity: ActivityType.none),
      _Step('2', activity: ActivityType.sleeperEmbezzle),
      _Step('Escape'),
      _Step('Escape', screen: 'headquarters'),
    ], prepare: _addSleeper),
    const _Journey('Media pages, article acknowledgement and Escape', [
      _Step('m', screen: 'media-archive'),
      _Step(']', screen: 'media-archive'),
      _Step('a', screen: 'article'),
      _Step('q', screen: 'media-archive'),
      _Step('[', screen: 'media-archive'),
      _Step('Escape', screen: 'headquarters'),
    ], prepare: _addArchive),
    const _Journey('Agenda brackets, arrows, exit and revisit', [
      _Step('l', screen: 'agenda-records'),
      _Step(']', screen: 'agenda-records'),
      _Step('[', screen: 'agenda-records'),
      _Step('Right', screen: 'agenda-records'),
      _Step('Left', screen: 'agenda-records'),
      _Step('q', screen: 'headquarters'),
      _Step('l', screen: 'agenda-records'),
      _Step('Escape', screen: 'headquarters'),
    ]),
    _Journey(
      'travel source letters, one-level Back and immediate destination',
      [
        const _Step('f', screen: 'planning'),
        _Step.action(
          'district',
          actionId: () => districtId,
          screen: 'planning',
        ),
        const _Step('Enter', screen: 'planning'),
        _Step.action(
          'district',
          actionId: () => districtId,
          screen: 'planning',
        ),
        const _Step('Escape', screen: 'planning'),
        const _Step('Escape', screen: 'headquarters'),
        const _Step('f', screen: 'planning'),
        _Step.action(
          'district',
          actionId: () => districtId,
          screen: 'planning',
        ),
        _Step.action('site', actionId: () => siteId, screen: 'headquarters'),
        const _Step('f', screen: 'planning'),
        const _Step('Escape', screen: 'headquarters'),
      ],
      prepare: prepareTravel,
    ),
    const _Journey('held profile arrows and rename Backspace / Escape', [
      _Step('r'),
      _Step('1'),
      _Step('a'),
      _Step('Right', phase: _KeyPhase.down),
      _Step('Right', phase: _KeyPhase.repeat),
      _Step('Right', phase: _KeyPhase.up),
      _Step('Left'),
      _Step('n', pendingText: ''),
      _Step('a', pendingText: 'a'),
      _Step('b', pendingText: 'ab'),
      _Step('Backspace', pendingText: 'a'),
      _Step('x', pendingText: 'ax'),
      _Step('Escape'),
      _Step('Enter'),
      _Step('Enter', screen: 'organisation'),
      _Step('Enter', screen: 'headquarters'),
    ]),
    const _Journey(
      'prefilled source text keeps its end caret and Escape result',
      [
        _Step('Backspace', pendingText: 'Alic'),
        _Step('Escape', screen: 'headquarters'),
      ],
      initialText: 'Alice',
    ),
  ];

  for (final journey in journeys) {
    testWidgets('Graphical preserves Classic ${journey.name}', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = journey.size;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(() {
        journalReadingScale.value = 1;
        journalPresentation.value = const JournalPreferenceValues();
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
      });
      final oracle = await _runJourney(tester, fixture, journey, classic: true);
      await _runJourney(
        tester,
        fixture,
        journey,
        classic: false,
        oracle: oracle,
      );
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  }
}
