import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/daily/recruitment.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/siege.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/modern/journal_people.dart';
import 'package:lcs_new_age/modern/journal_recruitment.dart';
import 'package:lcs_new_age/modern/personnel_directory.dart';
import 'package:lcs_new_age/politics/alignment.dart' as politics;
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

Finder _key(String value) => find.byKey(ValueKey(value));
String _snapshot() => jsonEncode(game.gameState.toJson());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String fixture;
  late Creature recruiter, prospect;
  late Site home;
  late RecruitmentSession session;

  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
  });

  setUp(() {
    game.gameState = decodeSaveContents(fixture).gameState!;
    recruiter = game.pool.first;
    home = game.sites.firstWhere((s) => s.controller == SiteController.lcs);
    recruiter
      ..name = 'Alex Recruiter'
      ..alive = true
      ..align = politics.Alignment.liberal
      ..hireId = null
      ..brainwashed = false
      ..juice = 1000
      ..location = home
      ..activity = Activity(ActivityType.donations)
      ..meetings = 0;
    prospect =
        Creature.fromJson(
            jsonDecode(jsonEncode(recruiter)) as Map<String, dynamic>,
          )
          ..id = 99001
          ..name = 'Jordan Prospect'
          ..align = politics.Alignment.liberal
          ..location = home;
    session = RecruitmentSession(prospect, recruiter)..rawEagerness = 3;
    game.recruitmentSessions
      ..clear()
      ..add(session);
    game.disbanding = false;
    engine.console = Console();
  });

  test('overview reads actual follow-ups without altering saves or RNG', () {
    final before = _snapshot();
    reseedRNG(seed: 49912);
    final expectedRoll = nextRngSeed;
    reseedRNG(seed: 49912);

    final meetings = pendingRecruitmentMeetings();

    expect(meetings, hasLength(1));
    expect(meetings.single.recruiterName, 'Alex Recruiter');
    expect(meetings.single.prospectName, 'Jordan Prospect');
    expect(meetings.single.venueWarning, isNull);
    expect(meetings.single.readiness, 'Feels something needs to be done');
    expect(meetings.single.canOfferJoin, isFalse);
    expect(recruiter.activity.type, ActivityType.donations);
    expect(_snapshot(), before);
    expect(nextRngSeed, expectedRoll);
  });

  for (final (alignment, rawEagerness, brainwashed) in [
    (politics.Alignment.liberal, 3, false),
    (politics.Alignment.liberal, 4, false),
    (politics.Alignment.moderate, 6, false),
    (politics.Alignment.conservative, 7, false),
    (politics.Alignment.conservative, 8, false),
    (politics.Alignment.liberal, 4, true),
  ]) {
    test(
      'readiness matches original offer choice for $alignment/$rawEagerness/$brainwashed',
      () async {
        prospect.align = alignment;
        session.rawEagerness = rawEagerness;
        recruiter.brainwashed = brainwashed;
        final overview = pendingRecruitmentMeetings().single;
        bool? offerEnabled;
        void answer() {
          if (!engine.console.awaitingInput ||
              engine.console.lastKey != null ||
              engine.console.recruitment?.followUp != true) {
            return;
          }
          final offer = engine.console.actions
              .where((action) => action.key.toLowerCase() == 'c')
              .firstOrNull;
          if (offer != null) {
            offerEnabled = offer.enabled;
            engine.console.sendInput('d');
          }
        }

        engine.console.revision.addListener(answer);
        try {
          expect(
            await completeRecruitMeeting(
              session,
              recruiter,
            ).timeout(const Duration(seconds: 5)),
            isTrue,
          );
        } finally {
          engine.console.revision.removeListener(answer);
        }
        expect(offerEnabled, isNotNull);
        expect(overview.canOfferJoin, offerEnabled);
      },
    );
  }

  for (final reason in ['away', 'siege', 'dead']) {
    test('warnings match source removal for a $reason recruiter', () async {
      switch (reason) {
        case 'away':
          recruiter.location = game.sites.firstWhere(
            (s) => s.controller != SiteController.lcs,
          );
        case 'siege':
          home.siege.activeSiegeType = SiegeType.police;
        case 'dead':
          recruiter.alive = false;
      }
      expect(pendingRecruitmentMeetings().single.venueWarning, isNotNull);

      await meetWithPotentialRecruits().timeout(const Duration(seconds: 5));

      expect(game.recruitmentSessions, isEmpty);
      expect(pendingRecruitmentMeetings(), isEmpty);
    });
  }

  test(
    'disbanding pauses source follow-ups without inventing cancellation',
    () async {
      game.disbanding = true;
      await meetWithPotentialRecruits().timeout(const Duration(seconds: 5));
      expect(pendingRecruitmentMeetings(), hasLength(1));
      expect(game.recruitmentSessions, [session]);
    },
  );

  test('meeting venue follows current cities, independently of home base', () {
    expect(pendingRecruitmentMeetings().single.inPerson, isTrue);
    final otherCity = game.sites.firstWhere((s) => s.city != home.city);
    prospect.location = otherCity;
    final overview = pendingRecruitmentMeetings().single;
    expect(overview.inPerson, isFalse);
    expect(overview.venueWarning, isNull);
    expect(overview.recruiterLocation, home.getName());
  });

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(1024, 720),
    double scale = 1.5,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  JournalRecruitmentOverview(),
                  const Expanded(child: SizedBox()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'compact reader opens actual meetings without sending engine input',
    (tester) async {
      final before = _snapshot();
      await mount(tester);
      expect(find.text('Recruitment meetings · 1'), findsOneWidget);
      expect(find.textContaining('Jordan Prospect'), findsNothing);
      await tester.tap(_key('people-recruitment-overview'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Jordan Prospect'), findsOneWidget);
      expect(find.text('Recruiter: Alex Recruiter'), findsOneWidget);
      expect(
        find.textContaining('does not need another Recruiting order'),
        findsOneWidget,
      );
      await tester.tap(_key('people-recruitment-close'));
      await tester.pumpAndSettle();
      expect(_key('people-recruitment-dialog'), findsNothing);
      expect(engine.console.lastKey, isNull);
      expect(_snapshot(), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty list and disbanding use current source state', (
    tester,
  ) async {
    game.recruitmentSessions.clear();
    await mount(tester);
    await tester.tap(_key('people-recruitment-overview'));
    await tester.pumpAndSettle();
    expect(_key('people-recruitment-empty'), findsOneWidget);
    await tester.tap(_key('people-recruitment-close'));
    await tester.pumpAndSettle();
    game.recruitmentSessions.add(session);
    game.disbanding = true;
    await mount(tester);
    expect(
      find.text('Follow-ups are paused while disbanding.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'long session list scrolls within the reader at 1024x720 and 150%',
    (tester) async {
      for (var i = 0; i < 15; i++) {
        final another =
            Creature.fromJson(
                jsonDecode(jsonEncode(prospect)) as Map<String, dynamic>,
              )
              ..id = 99010 + i
              ..name = 'Additional Prospect $i';
        game.recruitmentSessions.add(RecruitmentSession(another, recruiter));
      }
      await mount(tester);
      await tester.tap(_key('people-recruitment-overview'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        _key('people-recruitment-meeting:${recruiter.id}:99024'),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Additional Prospect 14').hitTestable(),
        findsOneWidget,
      );
      expect(_key('people-recruitment-close').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'People keeps directory order actions reachable beside compact overview',
    (tester) async {
      final directory = PersonnelDirectoryController();
      addTearDown(directory.dispose);
      recruiter
        ..squadId = null
        ..location = game.sites.firstWhere(
          (s) => s.type == SiteType.homelessEncampment,
        );
      tester.view.physicalSize = const Size(1024, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(1024, 720),
              textScaler: TextScaler.linear(1.5),
            ),
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(10),
                child: JournalPeopleView(
                  people: [recruiter],
                  directoryController: directory,
                  onOpenProfile: (_) {},
                  onAssignOrder: (_) {},
                  onJoinSquad: (_) {},
                  onOpenPromotionTools: () {},
                  onAssignTender: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        _key('personnel-assign-order:${recruiter.id}'),
        120,
        scrollable: find
            .descendant(
              of: _key('personnel-directory'),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
      expect(
        _key('personnel-assign-order:${recruiter.id}').hitTestable(),
        findsOneWidget,
      );
      expect(
        _key('personnel-join-squad:${recruiter.id}').hitTestable(),
        findsOneWidget,
      );
      expect(_key('people-recruitment-overview'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
