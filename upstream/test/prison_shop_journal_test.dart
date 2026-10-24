import 'dart:convert';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart' hide Alignment;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/basemode/base_mode.dart';
import 'package:lcs_new_age/basemode/invest_in_location.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/prison_activity.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/location/front_business.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/siege.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/modern/journal_preferences.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/organisation_journal.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/politics/laws.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/campaign_fixture.dart';
import 'support/headquarters_test_harness.dart';

/// Only HQ dispatch is supplied; all nested choices enter the real readers.
class _Harness extends HeadquartersTestHarness {
  _Harness({super.reader});

  @override
  Future<void> dispatch(int key) async {
    if (key == engine.Key.i) {
      final site = game.activeSafehouse;
      if (site != null && site.upgradable && !site.siege.underSiege) {
        await investInLocation(site);
      }
    } else {
      await super.dispatch(key);
    }
  }
}

Finder _key(String value) => find.byKey(ValueKey(value));

Future<void> _settle(WidgetTester tester) async {
  for (var step = 0; step < 35; step++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder control) async {
  expect(control, findsOneWidget);
  await tester.ensureVisible(control);
  await _settle(tester);
  expect(control.hitTestable(), findsOneWidget);
  await tester.tap(control);
  await _settle(tester);
}

Future<void> _sourceKey(
  WidgetTester tester,
  LogicalKeyboardKey value, {
  bool restoreFocus = true,
}) async {
  if (restoreFocus) {
    tester
        .widgetList<Focus>(find.byType(Focus))
        .singleWhere(
          (widget) => widget.focusNode?.debugLabel == 'Game keyboard',
        )
        .focusNode!
        .requestFocus();
    await tester.pump();
  }
  await tester.sendKeyEvent(value);
  await _settle(tester);
}

ConsoleAction _action(String type, [String? id]) =>
    engine.console.actions.singleWhere(
      (action) =>
          action.entityType == type && (id == null || action.entityId == id),
    );

Finder _control(ConsoleAction action) =>
    _key('direct-action:${action.y}:${action.x}:${action.key}');

VoidCallback _retain(WidgetTester tester, ConsoleAction action) => tester
    .widget<TextButton>(
      find.descendant(of: _control(action), matching: find.byType(TextButton)),
    )
    .onPressed!;

Future<void> _choose(WidgetTester tester, String type, [String? id]) async {
  final action = _action(type, id);
  expect(action.enabled, isTrue);
  await _tap(tester, _control(action));
}

Future<void> _tabToSourceAction(
  WidgetTester tester,
  ConsoleAction action,
) async {
  final control = _control(action);
  await tester.ensureVisible(control);
  await _settle(tester);
  var semantics = tester.getSemantics(control).getSemanticsData();
  expect(semantics.flagsCollection.isButton, isTrue);
  expect(
    semantics.flagsCollection.isFocused,
    isNot(Tristate.none),
    reason: 'The named source action must retain native focusability metadata.',
  );
  expect(semantics.hasAction(SemanticsAction.tap), isTrue);
  final revision = engine.console.revision.value;
  final pending = engine.console.nextKeyEvent;
  for (
    var tabs = 0;
    tabs < 100 && semantics.flagsCollection.isFocused != Tristate.isTrue;
    tabs++
  ) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await _settle(tester);
    semantics = tester.getSemantics(control).getSemanticsData();
  }
  expect(
    semantics.flagsCollection.isFocused,
    Tristate.isTrue,
    reason: 'Actual Tab traversal must focus this same named source action.',
  );
  expect(engine.console.revision.value, revision);
  expect(engine.console.nextKeyEvent, same(pending));
}

Map<String, dynamic> _snapshot() => jsonDecode(campaignSnapshot());

Map<String, dynamic> _savedPerson(Map<String, dynamic> saved, int id) =>
    ((saved['lcs'] as Map<String, dynamic>)['pool'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .singleWhere((person) => person['id'] == id);

Map<String, dynamic> _savedSite(Map<String, dynamic> saved, int id) =>
    (saved['cities'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .expand(
          (city) =>
              (city['districts'] as List<dynamic>).cast<Map<String, dynamic>>(),
        )
        .expand((district) => district['sites'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .singleWhere((site) => site['id'] == id);

void _expectOnlyPrisonOrderChanged(
  Map<String, dynamic> before,
  Creature person,
  PrisonOrder order,
) {
  expect(person.prisonActivity!.order, order);
  final after = _snapshot();
  _savedPerson(after, person.id)['prisonActivity'] = _savedPerson(
    before,
    person.id,
  )['prisonActivity'];
  expect(
    after,
    before,
    reason: 'Only the selected prisoner project may change.',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CampaignFixture fixture;
  setUpAll(() async {
    fixture = await CampaignFixture.load('test/saves/felix_1_0.json');
    final serif = FontLoader('JournalSerif')
      ..addFont(rootBundle.load('fonts/journal/LibreBaskerville-Variable.ttf'));
    await serif.load();
    final sans = FontLoader('ModernSans');
    for (final weight in ['regular', 'medium', 'bold', 'black']) {
      sans.addFont(rootBundle.load('fonts/modern/roboto-$weight.ttf'));
    }
    await sans.load();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fixture.restoreHeadquarters(console: Console());
    journalReadingScale.value = 1;
    journalPresentation.value = const JournalPreferenceValues();
    for (final squad in game.squads) {
      squad.activity = Activity.none();
    }
    for (final person in game.pool) {
      person.activity = Activity.none();
    }
    game.laws[Law.prisons] = DeepAlignment.moderate;
  });
  tearDown(() => journalReadingScale.value = 1);

  Future<_Harness> mount(
    WidgetTester tester,
    Size size,
    double scale, {
    Future<void> Function()? reader,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    journalReadingScale.value = scale;
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    final harness = _Harness(reader: reader);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      harness.stopped = true;
      for (var step = 0; step < 70 && !harness.finished; step++) {
        if (engine.console.awaitingInput) {
          engine.console.sendInput('Escape');
        }
        await tester.pump(const Duration(milliseconds: 5));
      }
      expect(harness.finished, isTrue);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
    });
    await tester.pumpWidget(const MainApp());
    await _settle(tester);
    return harness;
  }

  Creature addPrisoner(String name) => addTestCrewMember(name: name)
    ..location = game.sites.firstWhere((site) => site.type == SiteType.prison)
    ..sentence = 12
    ..deathPenalty = false
    ..sleeperAgent = false
    ..align = Alignment.liberal
    ..prisonActivity = null;

  for (final (size, scale) in [
    (const Size(1440, 1000), 1.0),
    (const Size(1024, 720), 1.5),
  ]) {
    final variant = '${size.width.toInt()}-$scale';
    testWidgets(
      'Justice prison orders retain source identity, focus and cancellation at $variant',
      (tester) async {
        final first = addPrisoner('Prepared prisoner Alpha');
        final second = addPrisoner('Prepared prisoner Beta');
        final harness = await mount(tester, size, scale);
        final before = _snapshot();
        reseedRNG(seed: 847321);
        final nextRoll = lcsRandom(1000000);
        reseedRNG(seed: 847321);

        await _tap(tester, _key('journal-section:2'));
        expect(harness.dispatched, contains(engine.Key.r));
        expect(engine.console.screen, 'personnel-roster');
        await _choose(tester, 'prison-management-open', 'all');
        expect(engine.console.screen, 'prison-management');
        await _choose(tester, 'prisoner-person', first.id.toString());
        expect(engine.console.screen, 'prison-order');
        expect(
          tester.getRect(_key('journal-management-page')).width,
          greaterThan(size.width * .8),
        );
        final study = _action('prison-order', 'studyLaw');
        expect(study.entityCategory, first.id.toString());
        final staleStudy = _retain(tester, study);
        final back = tester
            .widget<TextButton>(_key('journal-management-back'))
            .onPressed!;
        expect(_snapshot(), before);
        expect(lcsRandom(1000000), nextRoll);

        // Pointer-opened controls must not swallow the original Escape key.
        await _sourceKey(
          tester,
          LogicalKeyboardKey.escape,
          restoreFocus: false,
        );
        expect(engine.console.screen, 'prison-management');
        await _choose(tester, 'prisoner-person', second.id.toString());
        final pending = engine.console.nextKeyEvent;
        final revision = engine.console.revision.value;
        staleStudy();
        back();
        await _settle(tester);
        expect(engine.console.nextKeyEvent, same(pending));
        expect(engine.console.revision.value, revision);
        expect(_snapshot(), before);

        final semantics = tester.ensureSemantics();
        try {
          await _tabToSourceAction(tester, _action('prison-order', 'studyLaw'));
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await _settle(tester);
        } finally {
          semantics.dispose();
        }
        _expectOnlyPrisonOrderChanged(before, second, PrisonOrder.studyLaw);
        expect(first.prisonActivity, isNull);
        await _sourceKey(
          tester,
          LogicalKeyboardKey.escape,
          restoreFocus: false,
        );
        await _choose(tester, 'prisoner-person', second.id.toString());
        expect(
          _action('prison-order', 'studyLaw').label,
          contains('(current)'),
        );

        // Help owns keyboard input and retained controls while the await stays.
        final retainedWriting = _retain(
          tester,
          _action('prison-order', 'studyWriting'),
        );
        final afterOrder = campaignSnapshot();
        final awaiting = engine.console.nextKeyEvent;
        await _sourceKey(tester, LogicalKeyboardKey.f1);
        retainedWriting();
        await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
        await _settle(tester);
        expect(campaignSnapshot(), afterOrder);
        expect(engine.console.nextKeyEvent, same(awaiting));
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await _settle(tester);
        await _sourceKey(tester, LogicalKeyboardKey.escape);
        expect(engine.console.screen, 'prison-management');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Bases print shop setup, staffing, name cancellation and closing at $variant',
      (tester) async {
        // Declared prepared premises and staff; purchases and orders are earned
        // through the original readers below, with no day advancement.
        final site =
            game.sites.firstWhere((site) => site.type == SiteType.warehouse)
              ..controller = SiteController.lcs
              ..name = 'Prepared print shop base'
              ..shortName = 'Prepared print shop base'
              ..frontName = null
              ..frontShortName = null
              ..businessFront = false
              ..frontBusiness = null
              ..siege = Siege()
              ..closed = 0;
        final worker = addTestCrewMember(name: 'Prepared print worker')
          ..base = site
          ..location = site;
        final other = addTestCrewMember(name: 'Other print worker')
          ..base = site
          ..location = site;
        game.activeSquad = null;
        game.activeSafehouse = site;
        game.ledger.forceSetFunds(10000);
        await mount(tester, size, scale);
        await _tap(tester, _key('journal-section:10'));
        await _tap(tester, find.text(site.getName(includeCity: true)).first);
        final before = campaignSnapshot();
        final funds = game.ledger.funds;
        final date = game.date;
        reseedRNG(seed: 5923);
        final nextRoll = lcsRandom(1000000);
        reseedRNG(seed: 5923);
        await _tap(
          tester,
          find.widgetWithText(OutlinedButton, 'Manage print shop'),
        );
        expect(engine.console.screen, 'front-business');
        expect(
          tester.getRect(_key('journal-management-page')).width,
          greaterThan(size.width * .8),
        );
        await _choose(tester, 'front-business-setup');
        final staleConfirm = _retain(
          tester,
          _action('front-business-confirm', 'setup'),
        );
        await _sourceKey(
          tester,
          LogicalKeyboardKey.escape,
          restoreFocus: false,
        );
        expect(campaignSnapshot(), before);
        staleConfirm();
        await _settle(tester);
        expect(campaignSnapshot(), before);
        expect(lcsRandom(1000000), nextRoll);

        await _choose(tester, 'front-business-setup');
        await _choose(tester, 'front-business-confirm', 'setup');
        expect(site.frontBusiness, isNotNull);
        expect(site.businessFront, isTrue);
        expect(game.ledger.funds, funds - printShopSetupCostForTest);
        await _choose(tester, 'front-business-staffing');
        final beforeStaff = _snapshot();
        await _choose(tester, 'front-business-staff', worker.id.toString());
        expect(worker.activity.type, ActivityType.workPrintShop);
        expect(worker.activity.idString, site.idString);
        expect(other.activity.type, ActivityType.none);
        final afterStaff = _snapshot();
        _savedPerson(afterStaff, worker.id)['activity'] = _savedPerson(
          beforeStaff,
          worker.id,
        )['activity'];
        _savedSite(afterStaff, site.id)['frontBusiness'] = _savedSite(
          beforeStaff,
          site.id,
        )['frontBusiness'];
        expect(
          afterStaff,
          beforeStaff,
          reason: 'Staffing changes only the shop roster and selected order.',
        );
        await _sourceKey(
          tester,
          LogicalKeyboardKey.escape,
          restoreFocus: false,
        );

        final beforeRename = campaignSnapshot();
        await _choose(tester, 'front-business-name');
        expect(engine.console.textInput, isTrue);
        final editor = find.byType(TextField);
        expect(editor, findsOneWidget);
        await tester.enterText(editor, 'Cancelled shop name');
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await _settle(tester);
        expect(engine.console.textInput, isFalse);
        expect(campaignSnapshot(), beforeRename);
        expect(site.frontBusiness!.name, 'Community Print Shop');
        expect(site.frontBusiness!.staffIds, [worker.id]);

        await _choose(tester, 'front-business-mode', 'movement');
        expect(site.frontBusiness!.mode, FrontBusinessMode.movement);
        await _sourceKey(tester, LogicalKeyboardKey.escape);
        // Return through the source investment reader, then revisit via Bases.
        expect(engine.console.screen, 'base-investment');
        await _sourceKey(tester, LogicalKeyboardKey.escape);
        await _tap(tester, _key('journal-section:10'));
        await _tap(tester, find.text(site.getName(includeCity: true)).first);
        await _tap(
          tester,
          find.widgetWithText(OutlinedButton, 'Manage print shop'),
        );
        expect(site.frontBusiness!.mode, FrontBusinessMode.movement);
        expect(site.frontBusiness!.staffIds, [worker.id]);
        await _choose(tester, 'front-business-mode', 'closed');
        expect(worker.activity.type, ActivityType.none);
        expect(site.frontBusiness!.staffIds, isEmpty);
        expect(site.frontBusiness!.mode, FrontBusinessMode.closed);
        expect(game.date, date);
        expect(game.ledger.funds, funds - printShopSetupCostForTest);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'blind prison planning blocks chapter routes without consuming Back',
    (tester) async {
      final prison = game.sites.firstWhere(
        (site) => site.type == SiteType.prison,
      );
      for (final person in game.pool) {
        if (!person.alive || person.align != Alignment.liberal) continue;
        person
          ..sleeperAgent = false
          ..location = prison
          ..sentence = 12
          ..deathPenalty = false;
      }
      expect(await checkForVision(), isTrue);
      int? plannedMonth;
      await mount(
        tester,
        const Size(1024, 720),
        1.5,
        reader: () async {
          // Retain a shell that already visited HQ, as in a running campaign
          // whose outside crew were captured. Only its W dispatch is stubbed.
          engine.erase();
          final location = game.activeSquad?.site ?? game.activeSafehouse;
          baseModeSquadSafehouseDisplay(location);
          baseModeOptionsDisplay(location);
          await engine.getKey();
          plannedMonth = await reviewPrisonPlanBeforeBlindTime(null);
        },
      );
      await _sourceKey(tester, LogicalKeyboardKey.keyW);
      final journal = tester.widget<OrganisationJournal>(
        find.byType(OrganisationJournal),
      );
      expect(journal.controller.canNavigate, isFalse);
      final before = campaignSnapshot();
      final revision = engine.console.revision.value;
      final pending = engine.console.nextKeyEvent;
      final tab = _key('journal-section:9');
      expect(
        tester
            .widget<InkWell>(
              find.descendant(of: tab, matching: find.byType(InkWell)),
            )
            .onTap,
        isNull,
      );
      await _tap(tester, tab);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      await _settle(tester);
      expect(await journal.controller.returnToHeadquarters(), isFalse);
      expect(engine.console.revision.value, revision);
      expect(engine.console.nextKeyEvent, same(pending));
      expect(campaignSnapshot(), before);
      expect(plannedMonth, isNull);
      await _sourceKey(tester, LogicalKeyboardKey.escape);
      expect(plannedMonth, game.date.year * 12 + game.date.month);
      expect(campaignSnapshot(), before);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'all-imprisoned monthly planning preserves time and can be declined once',
    () async {
      final prison = game.sites.firstWhere(
        (site) => site.type == SiteType.prison,
      );
      for (final person in game.pool) {
        if (!person.alive || person.align != Alignment.liberal) continue;
        person
          ..sleeperAgent = false
          ..location = prison
          ..sentence = 12
          ..deathPenalty = false;
      }
      expect(await checkForVision(), isTrue);
      final before = campaignSnapshot();
      final date = game.date;
      reseedRNG(seed: 8173);
      final nextRoll = lcsRandom(1000000);
      reseedRNG(seed: 8173);
      final planning = reviewPrisonPlanBeforeBlindTime(null);
      await Future<void>.delayed(Duration.zero);
      expect(engine.console.awaitingInput, isTrue);
      expect(engine.console.screen, 'prison-management');
      expect(engine.console.sendInput('Enter'), isTrue);
      final month = await planning;
      expect(month, date.year * 12 + date.month);
      expect(campaignSnapshot(), before);
      expect(game.date, date);
      expect(lcsRandom(1000000), nextRoll);
      final revision = engine.console.revision.value;
      expect(await reviewPrisonPlanBeforeBlindTime(month), month);
      expect(engine.console.awaitingInput, isFalse);
      expect(engine.console.revision.value, revision);
      expect(campaignSnapshot(), before);
    },
  );
}

// Equipment plus the existing business-front cover, shown before confirming.
const printShopSetupCostForTest = 4500;
