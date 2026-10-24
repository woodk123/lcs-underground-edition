import 'dart:async';
import 'dart:ui' show PointerDeviceKind, SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/modern/activity_calculations.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/mechanics_help.dart';
import 'package:lcs_new_age/modern/order_mechanics_dialog.dart';
import 'package:lcs_new_age/modern/organisation_order_workspace.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'support/campaign_fixture.dart';

Finder _key(String key) => find.byKey(ValueKey(key));
const _prepareKey = 'journal-activity:donations';
const _detailsKey = 'journal-activity-details:donations';
const _prepareName = 'Prepare Soliciting Donations · Assign immediately with 1';
const _detailsName = 'Details for Soliciting Donations';

final _help = ActivityMechanics(
  type: ActivityType.donations,
  title: 'Soliciting Donations',
  summary: 'A complete task summary belongs in explicit details.',
  timing: 'Runs at the original daily boundary.',
  factors: 'Persuasion 4 · Public mood 50',
  cost: '\$7 per eligible day',
  requirements: 'An available Liberal at an eligible location.',
  risk: 'The original encounter checks still apply.',
  unavailableReason: 'This task needs an eligible location.',
  details: 'All longer source-authored notes remain available here.',
  calculation: ActivityCalculation(
    formula: 'The original formula, unchanged',
    inputs: const ['Current input: Persuasion 4'],
    result: 'Estimated current result: 12',
    qualifiers: const ['This is a projection, never a game roll.'],
    source: 'lib/daily/activities/fundraising.dart',
    estimated: true,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CampaignFixture fixture;
  var prepared = 0, opened = 0, closed = 0;
  setUpAll(() async {
    fixture = await CampaignFixture.load('test/saves/felix_1_0.json');
    final serif = FontLoader('JournalSerif')
      ..addFont(rootBundle.load('fonts/journal/LibreBaskerville-Variable.ttf'))
      ..addFont(
        rootBundle.load('fonts/journal/LibreBaskerville-Italic-Variable.ttf'),
      );
    await serif.load();
    final sans = FontLoader('ModernSans');
    for (final weight in ['regular', 'medium', 'bold', 'black']) {
      sans.addFont(rootBundle.load('fonts/modern/roboto-$weight.ttf'));
    }
    await sans.load();
  });
  setUp(() {
    fixture.restoreHeadquarters(console: Console());
    prepared = opened = closed = 0;
  });

  Future<void> mount(
    WidgetTester tester, {
    bool available = true,
    bool large = false,
    bool compact = false,
    String? categoryLabel,
    bool preparedOrder = false,
    bool detailsEnabled = true,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = large
        ? const Size(1024, 720)
        : const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildJournalTheme(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(large ? 1.5 : 1)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: SizedBox(
                width: large ? 360 : 520,
                child: SingleChildScrollView(
                  child: OrganisationOrderTaskView(
                    taskId: 'donations',
                    type: ActivityType.donations,
                    label: _help.title,
                    shortcut: '1',
                    categoryLabel: categoryLabel,
                    enabled: available,
                    selected: preparedOrder,
                    prepared: preparedOrder,
                    summary: _help.summary,
                    factors: _help.factors,
                    cost: _help.cost,
                    unavailableReason: available
                        ? null
                        : _help.unavailableReason,
                    compact: compact,
                    showGuidance: false,
                    onPrepare: available ? () => prepared++ : null,
                    onDetails: !detailsEnabled
                        ? null
                        : () {
                            opened++;
                            unawaited(
                              showDialog<void>(
                                context: context,
                                builder: (dialogContext) =>
                                    OrderMechanicsDialog(
                                      help: _help,
                                      onClose: () {
                                        closed++;
                                        Navigator.of(dialogContext).pop();
                                      },
                                    ),
                              ),
                            );
                          },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tabTo(WidgetTester tester, String label) async {
    final named = find.bySemanticsLabel(label);
    expect(named, findsOneWidget);
    final data = tester.getSemantics(named).getSemanticsData();
    expect(data.flagsCollection.isButton, true);
    expect(data.flagsCollection.isFocused, isNot(Tristate.none));
    expect(data.hasAction(SemanticsAction.tap), true);
    for (
      var step = 0;
      step < 12 &&
          tester
                  .getSemantics(named)
                  .getSemanticsData()
                  .flagsCollection
                  .isFocused !=
              Tristate.isTrue;
      step++
    ) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
    }
    expect(
      tester.getSemantics(named).getSemanticsData().flagsCollection.isFocused,
      Tristate.isTrue,
    );
  }

  testWidgets(
    'hovering a task does not open full mechanics; explicit details does',
    (tester) async {
      await mount(tester);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(2, 2));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(_key(_prepareKey)));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(_help.summary, findRichText: true), findsNothing);
      expect(_key('journal-order-details-dialog'), findsNothing);
      expect(prepared, 0);
      expect(opened, 0);
      await mouse.moveTo(tester.getCenter(_key(_detailsKey)));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(_detailsName, findRichText: true), findsOneWidget);
      expect(find.text(_help.summary, findRichText: true), findsNothing);
      await tester.tap(_key(_detailsKey));
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(prepared, 0);
      expect(find.text(_help.summary), findsOneWidget);
      await tester.tap(_key('journal-order-details-close'));
      await tester.pumpAndSettle();
      expect(closed, 1);
      await tester.tap(_key(_prepareKey));
      await tester.pumpAndSettle();
      expect(prepared, 1);
      expect(opened, 1);
    },
  );

  for (final large in [false, true]) {
    testWidgets(
      'separate native keyboard controls and complete accessible details, large=$large',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          await mount(tester, large: large, compact: large);
          final source = engine.console;
          source.addAction('1', '1 - Solicit donations');
          var sourceCompleted = false;
          unawaited(source.getkey().then((_) => sourceCompleted = true));
          await tester.pump();
          addTearDown(() async {
            source.sendInput('Escape');
            await tester.pump();
            expect(sourceCompleted, true);
          });
          final before = campaignSnapshot();
          final actions = List.of(source.actions);
          final revision = source.revision.value;
          final pending = source.nextKeyEvent;
          reseedRNG(seed: 40713);
          final rolls = List.generate(12, (_) => lcsRandom(100000));
          reseedRNG(seed: 40713);
          for (final key in [_prepareKey, _detailsKey]) {
            final control = _key(key);
            expect(control.hitTestable(), findsOneWidget);
            final rect = tester.getRect(control);
            expect(rect.left, greaterThanOrEqualTo(0));
            expect(
              rect.right,
              lessThanOrEqualTo(tester.view.physicalSize.width),
            );
            expect(rect.height, greaterThanOrEqualTo(48));
            expect(rect.width, greaterThanOrEqualTo(48));
          }
          await tabTo(tester, _detailsName);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(opened, 1);
          expect(prepared, 0);
          final close = find.bySemanticsLabel('Close');
          expect(
            tester
                .getSemantics(close)
                .getSemanticsData()
                .flagsCollection
                .isFocused,
            Tristate.isTrue,
          );
          for (final text in [
            _help.summary,
            _help.timing,
            'Uses: ${_help.factors}',
            'Cost: ${_help.cost}',
            'Needs: ${_help.requirements}',
            'Unavailable: ${_help.unavailableReason}',
            _help.risk,
            'Calculation: ${_help.calculation!.formula}',
            ..._help.calculation!.inputs,
            _help.calculation!.result,
            ..._help.calculation!.qualifiers,
            _help.details,
          ]) {
            final label = find.descendant(
              of: _key('journal-order-details-dialog'),
              matching: find.text(text),
            );
            await tester.ensureVisible(label);
            await tester.pumpAndSettle();
            expect(
              tester.getSemantics(label).getSemanticsData().label,
              contains(text),
            );
          }
          final closeControl = _key('journal-order-details-close');
          expect(closeControl.hitTestable(), findsOneWidget);
          expect(
            tester.getRect(closeControl).bottom,
            lessThanOrEqualTo(tester.view.physicalSize.height),
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(_key('journal-order-details-dialog'), findsNothing);
          expect(closed, 1);
          expect(campaignSnapshot(), before);
          expect(source.actions, actions);
          expect(source.revision.value, revision);
          expect(identical(source.nextKeyEvent, pending), true);
          expect(sourceCompleted, false);
          expect(List.generate(12, (_) => lcsRandom(100000)), rolls);
          await tabTo(tester, _prepareName);
          await tester.sendKeyEvent(LogicalKeyboardKey.space, character: ' ');
          await tester.pumpAndSettle();
          expect(prepared, 1);
          expect(opened, 1);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );

    testWidgets(
      'unavailable task still has independent native Details, large=$large',
      (tester) async {
        final semantics = tester.ensureSemantics();
        try {
          await mount(tester, available: false, large: large, compact: large);
          expect(
            tester.widget<TextButton>(_key(_prepareKey)).onPressed,
            isNull,
          );
          expect(
            find.text('Unavailable: ${_help.unavailableReason}'),
            findsOneWidget,
          );
          final unavailable = find.bySemanticsLabel(
            '$_prepareName · Unavailable: ${_help.unavailableReason}',
          );
          expect(unavailable, findsOneWidget);
          expect(
            tester
                .getSemantics(unavailable)
                .getSemanticsData()
                .flagsCollection
                .isEnabled,
            Tristate.isFalse,
          );
          await tabTo(tester, _detailsName);
          await tester.sendKeyEvent(LogicalKeyboardKey.space, character: ' ');
          await tester.pumpAndSettle();
          expect(opened, 1);
          expect(prepared, 0);
          expect(
            find.text('Unavailable: ${_help.unavailableReason}'),
            findsWidgets,
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(closed, 1);
          expect(prepared, 0);
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  testWidgets(
    'search category, prepared status and temporarily blocked Details retain their facts',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        await mount(
          tester,
          categoryLabel: 'Business',
          preparedOrder: true,
          detailsEnabled: false,
        );
        expect(
          find.bySemanticsLabel(
            'Prepare Soliciting Donations · Business · Prepared, awaiting confirmation',
          ),
          findsOneWidget,
        );
        expect(find.text('Business'), findsOneWidget);
        expect(find.text('Prepared'), findsOneWidget);
        expect(find.text('Uses: ${_help.factors}'), findsOneWidget);
        expect(find.text('Cost: ${_help.cost}'), findsOneWidget);
        expect(find.text('Assign now: '), findsNothing);
        expect(tester.widget<IconButton>(_key(_detailsKey)).onPressed, isNull);
        await tester.tap(_key(_prepareKey));
        expect(prepared, 1);
        expect(opened, 0);
      } finally {
        semantics.dispose();
      }
    },
  );
}
