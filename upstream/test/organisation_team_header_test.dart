import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/organisation_team_header.dart';

Finder _key(String value) => find.byKey(ValueKey(value));
const _name = 'Eugene Kaltenbrunner';
const _team = 'The Liberal Crime Squad';
const _location = 'Holmes, SEA';
const _status = 'Juice 0 · 140/140 blood';

OrganisationTeamActorView _actor({
  String name = _name,
  String location = _location,
  String status = _status,
  String statusTooltip = 'Juice 0 · Liberal · 140/140 blood',
  bool warning = false,
  double portraitSize = 46,
  VoidCallback? onInspect,
}) => OrganisationTeamActorView(
  personId: 7,
  name: name,
  location: location,
  status: status,
  statusTooltip: statusTooltip,
  statusWarning: warning,
  portrait: Semantics(
    label: 'Decorative portrait',
    image: true,
    child: SizedBox.square(
      dimension: portraitSize,
      child: const ColoredBox(color: JournalPalette.olive),
    ),
  ),
  onInspect: onInspect ?? () {},
);

Future<void> _mount(
  WidgetTester tester, {
  required double width,
  double scale = 1,
  bool compact = false,
  bool showingSkills = false,
  String team = _team,
  String memberCount = '6/6',
  String memberLabel = 'Squad members',
  String armed = '5',
  String cars = '2',
  bool withActor = true,
  OrganisationTeamActorView? actor,
  VoidCallback? onToggle,
  double? viewportHeight,
}) async {
  final header = OrganisationTeamHeaderView(
    key: const ValueKey('team-header'),
    teamName: team,
    showingSkills: showingSkills,
    onToggleSkills: onToggle ?? () {},
    memberCount: memberCount,
    memberCountLabel: memberLabel,
    armedCount: armed,
    carCount: cars,
    compact: compact,
    actor: withActor ? actor ?? _actor() : null,
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: buildJournalTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: viewportHeight == null
                ? header
                : SizedBox(
                    height: viewportHeight,
                    child: SingleChildScrollView(
                      key: const ValueKey('team-header-viewport'),
                      child: header,
                    ),
                  ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _insideHeader(WidgetTester tester, Finder finder) {
  final header = tester.getRect(_key('team-header'));
  final control = tester.getRect(finder);
  expect(control.left, greaterThanOrEqualTo(header.left));
  expect(control.right, lessThanOrEqualTo(header.right));
  expect(control.top, greaterThanOrEqualTo(header.top));
  expect(control.bottom, lessThanOrEqualTo(header.bottom));
}

Future<void> _tabTo(WidgetTester tester, Finder finder) async {
  var data = tester.getSemantics(finder).getSemanticsData();
  expect(data.flagsCollection.isButton, isTrue);
  expect(data.flagsCollection.isFocused, isNot(Tristate.none));
  expect(data.hasAction(SemanticsAction.tap), isTrue);
  for (
    var step = 0;
    step < 6 && data.flagsCollection.isFocused != Tristate.isTrue;
    step++
  ) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    data = tester.getSemantics(finder).getSemanticsData();
  }
  expect(data.flagsCollection.isFocused, Tristate.isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final serif = FontLoader('JournalSerif')
      ..addFont(rootBundle.load('fonts/journal/LibreBaskerville-Variable.ttf'));
    final sans = FontLoader('ModernSans')
      ..addFont(rootBundle.load('fonts/modern/roboto-regular.ttf'));
    await Future.wait([serif.load(), sans.load()]);
  });

  for (final (width, scale, compact) in [
    (600.0, 1.0, false),
    (300.0, 1.0, true),
    (300.0, 1.5, true),
    (220.0, 1.5, true),
  ]) {
    testWidgets(
      'identity, counters and native controls fit width=$width scale=$scale compact=$compact',
      (tester) async {
        var toggles = 0;
        var inspections = 0;
        await _mount(
          tester,
          width: width,
          scale: scale,
          compact: compact,
          actor: _actor(
            onInspect: () => inspections++,
            portraitSize: compact ? 36 : 58,
          ),
          onToggle: () => toggles++,
        );
        expect(tester.widget<Text>(_key('journal-team-name')).data, _team);
        expect(
          tester.widget<Text>(_key('journal-selected-person')).data,
          _name,
        );
        expect(find.text(_location), findsOneWidget);
        expect(find.text(_status), findsOneWidget);
        for (final (id, label) in [
          ('members', 'Squad members: 6/6'),
          ('armed', 'Armed members: 5'),
          ('cars', 'Assigned cars: 2'),
        ]) {
          expect(
            tester
                .getSemantics(_key('journal-team-$id'))
                .getSemanticsData()
                .label,
            label,
          );
          _insideHeader(tester, _key('journal-team-$id'));
        }
        expect(find.byTooltip('Squad members'), findsOneWidget);
        expect(find.byTooltip('Armed members'), findsOneWidget);
        expect(find.byTooltip('Assigned cars'), findsOneWidget);
        expect(find.bySemanticsLabel('Inspect $_name'), findsOneWidget);
        expect(find.bySemanticsLabel('Decorative portrait'), findsNothing);
        for (final control in [_key('journal-skills'), _key('hq-portrait:7')]) {
          _insideHeader(tester, control);
          expect(control.hitTestable(), findsOneWidget);
        }
        await tester.tap(_key('journal-skills'));
        await tester.pumpAndSettle();
        await tester.tap(_key('hq-portrait:7'));
        await tester.pumpAndSettle();
        expect(toggles, 1);
        expect(inspections, 1);
        debugPrint(
          'Header width=$width scale=$scale compact=$compact: ${tester.getSize(_key('team-header')).height}',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'compact enlarged header removes a counter row without reducing text sizes',
    (tester) async {
      await _mount(tester, width: 300, scale: 1.5);
      final standardHeight = tester.getSize(_key('team-header')).height;
      final teamSize = tester
          .widget<Text>(_key('journal-team-name'))
          .style!
          .fontSize;
      final nameSize = tester
          .widget<Text>(_key('journal-selected-person'))
          .style!
          .fontSize;
      final statusSize = tester
          .widget<Text>(_key('journal-selected-status'))
          .style!
          .fontSize;
      await _mount(tester, width: 300, scale: 1.5, compact: true);
      final compactHeight = tester.getSize(_key('team-header')).height;
      expect(standardHeight - compactHeight, greaterThanOrEqualTo(20));
      expect(compactHeight, lessThanOrEqualTo(110));
      expect(
        tester.widget<Text>(_key('journal-team-name')).style!.fontSize,
        teamSize,
      );
      expect(
        tester.widget<Text>(_key('journal-selected-person')).style!.fontSize,
        nameSize,
      );
      expect(
        tester.widget<Text>(_key('journal-selected-status')).style!.fontSize,
        statusSize,
      );
      debugPrint(
        'Header300px/150%: standard=$standardHeight compact=$compactHeight',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compact warning retains complete visible health text and accessible detail',
    (tester) async {
      const warning = 'Juice 1200 · 5/230 blood · Bleeding';
      const detail = 'Juice 1200 · Commander · 5/230 blood · Bleeding';
      await _mount(
        tester,
        width: 300,
        scale: 1.5,
        compact: true,
        actor: _actor(status: warning, statusTooltip: detail, warning: true),
      );
      final status = _key('journal-selected-status');
      expect(tester.widget<Text>(status).maxLines, isNull);
      expect(
        tester.renderObject<RenderParagraph>(status).didExceedMaxLines,
        isFalse,
      );
      expect(tester.widget<Text>(status).style!.color, JournalPalette.danger);
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.bySemanticsLabel('Health warning: $detail'), findsOneWidget);
      expect(find.byTooltip(detail), findsOneWidget);
      _insideHeader(tester, status);
      debugPrint(
        'Header300px/150% warning: ${tester.getSize(_key('team-header')).height}',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'compact inspect and toggle preserve native Tab and keyboard activation',
    (tester) async {
      var toggles = 0;
      var inspections = 0;
      await _mount(
        tester,
        width: 300,
        scale: 1.5,
        compact: true,
        actor: _actor(onInspect: () => inspections++, portraitSize: 36),
        onToggle: () => toggles++,
      );
      await _tabTo(tester, _key('journal-skills'));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      await _tabTo(tester, _key('hq-portrait:7'));
      await tester.sendKeyEvent(LogicalKeyboardKey.space, character: ' ');
      await tester.pumpAndSettle();
      expect(toggles, 1);
      expect(inspections, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'long network counters wrap within compact bounds with full labels',
    (tester) async {
      await _mount(
        tester,
        width: 300,
        scale: 1.5,
        compact: true,
        team: 'Undercover network',
        memberCount: '18 agents',
        memberLabel: 'Undercover agents',
        armed: '12',
        cars: '4',
      );
      expect(
        tester
            .getSemantics(_key('journal-team-members'))
            .getSemanticsData()
            .label,
        'Undercover agents: 18 agents',
      );
      for (final id in ['members', 'armed', 'cars']) {
        _insideHeader(tester, _key('journal-team-$id'));
      }
      expect(find.byTooltip('Undercover network'), findsOneWidget);
      debugPrint(
        'Header300px/150% longnetwork: ${tester.getSize(_key('team-header')).height}',
      );
      expect(tester.takeException(), isNull);
    },
  );

  for (final (scale, warning, allocation, network) in [
    (1.0, false, 86.0, false),
    (1.0, true, 96.0, false),
    (1.5, false, 140.0, false),
    (1.5, true, 140.0, false),
    (1.5, false, 140.0, true),
    (1.5, true, 140.0, true),
  ]) {
    testWidgets(
      '${network ? 'small network' : 'individual assignment'} keeps blood and Juice visible scale=$scale warning=$warning',
      (tester) async {
        final members = network ? '1 agents' : '1 person';
        final memberLabel = network
            ? 'Undercover agents'
            : 'Individual assignment';
        final statusText = warning ? 'Juice 1200 · 5/230 blood' : _status;
        final detail = warning
            ? 'Juice 1200 · Commander · 5/230 blood · Injured'
            : 'Juice 0 · Liberal · 140/140 blood';
        await _mount(
          tester,
          width: 300,
          scale: scale,
          compact: true,
          viewportHeight: allocation,
          team: network ? 'Undercover network' : 'Individual orders',
          memberCount: members,
          memberLabel: memberLabel,
          armed: '1',
          cars: '0',
          actor: _actor(
            name: 'Mara Planner',
            location: 'Homeless, SEA',
            status: statusText,
            statusTooltip: detail,
            warning: warning,
            portraitSize: 36,
          ),
        );
        final viewport = tester.getRect(_key('team-header-viewport'));
        final header = tester.getRect(_key('team-header'));
        final status = tester.getRect(_key('journal-selected-status'));
        debugPrint(
          '${network ? 'SmallNetwork' : 'Individual'}300px scale=$scale warning=$warning: natural=${header.height} allocation=${viewport.height} statusBottom=${status.bottom - viewport.top}',
        );
        expect(header.bottom, lessThanOrEqualTo(viewport.bottom));
        expect(status.bottom, lessThanOrEqualTo(viewport.bottom));
        expect(status.top, greaterThanOrEqualTo(viewport.top));
        expect(
          tester
              .renderObject<RenderParagraph>(_key('journal-selected-status'))
              .didExceedMaxLines,
          isFalse,
        );
        expect(
          tester
              .getSemantics(_key('journal-team-members'))
              .getSemanticsData()
              .label,
          '$memberLabel: $members',
        );
        expect(
          find.bySemanticsLabel('${warning ? 'Health warning: ' : ''}$detail'),
          findsOneWidget,
        );
        for (final id in ['members', 'armed', 'cars']) {
          final counter = tester.getRect(_key('journal-team-$id'));
          expect(counter.bottom, lessThanOrEqualTo(viewport.bottom));
        }
        expect(_key('journal-skills').hitTestable(), findsOneWidget);
        expect(_key('hq-portrait:7').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'empty crew retains counters and native toggle without an inspect action',
    (tester) async {
      var toggles = 0;
      await _mount(
        tester,
        width: 300,
        scale: 1.5,
        compact: true,
        withActor: false,
        memberCount: '0/6',
        armed: '0',
        cars: '0',
        onToggle: () => toggles++,
      );
      expect(find.text('No active crew selected.'), findsOneWidget);
      expect(_key('journal-selected-person'), findsNothing);
      expect(_key('hq-portrait:7'), findsNothing);
      expect(
        tester
            .getSemantics(_key('journal-team-members'))
            .getSemanticsData()
            .label,
        'Squad members: 0/6',
      );
      await tester.tap(_key('journal-skills'));
      expect(toggles, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
