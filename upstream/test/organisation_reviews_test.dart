import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/modern/organisation_reviews.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String fixture;
  late Creature person;
  final stores = <OrganisationReviewStore>[];
  final day = DateTime(2023, 1, 4);
  final tomorrow = DateTime(2023, 1, 5);

  OrganisationReviewStore store({
    Future<SharedPreferences> Function()? preferences,
  }) {
    final result = OrganisationReviewStore(preferences: preferences);
    stores.add(result);
    return result;
  }

  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({'unrelatedSetting': 'keep'});
    game.gameState = decodeSaveContents(fixture).gameState!;
    person = game.pool.first
      ..alive = true
      ..align = Alignment.liberal
      ..missing = false
      ..vacationDaysLeft = 0
      ..hidingDaysLeft = 0
      ..squadId = null
      ..activity = Activity.none();
    expect(person.isActiveLiberal, isTrue);
  });

  tearDown(() {
    for (final review in stores) {
      review.dispose();
    }
    stores.clear();
  });

  test(
    'previous daily job survives queued visit, restart and acknowledgement',
    () async {
      final squad = game.squads.first;
      person.squad = squad;
      person.activity = Activity(ActivityType.stealCars);
      squad.activity = Activity(
        ActivityType.visit,
        idString: person.base!.idString,
      );
      final review = store();
      final before = jsonEncode(game.gameState.toJson());
      reseedRNG(seed: 40);
      final expected = lcsRandom(100000);
      reseedRNG(seed: 40);
      await review.observe(101, [person], day);
      expect(jsonEncode(game.gameState.toJson()), before);
      expect(lcsRandom(100000), expected);
      squad.activity = Activity.none();
      person.activity = Activity.none();
      final returned = store();
      await returned.observe(101, [person], tomorrow);
      expect(returned.notices.single.previousActivity, ActivityType.stealCars);
      expect(
        previousOrderCategory(returned.notices.single.previousActivity),
        'acquisition',
      );
      final reopened = store();
      await reopened.observe(101, [person], tomorrow);
      expect(reopened.notices.single.previousActivity, ActivityType.stealCars);
      await reopened.acknowledgePerson(person.id);
      expect(reopened.notices, isEmpty);
    },
  );

  test('previous job never replays parameterised or completed work', () async {
    expect(previousOrderCategory(ActivityType.study), isNull);
    expect(previousOrderCategory(ActivityType.makeClothing), isNull);
    expect(previousOrderCategory(ActivityType.interrogation), isNull);
    expect(previousOrderCategory(ActivityType.visit), isNull);
    expect(previousOrderCategory(ActivityType.none), isNull);
  });

  test(
    'first observation is a baseline, including available squadless crew',
    () async {
      final review = store();
      expect(review.loaded, isFalse);
      await review.observe(101, [person], day);
      expect(review.loaded, isTrue);
      expect(review.notices, isEmpty);
      await review.observe(101, [person], tomorrow);
      await review.observe(101, [person], DateTime(2023, 2, 1));
      expect(review.notices, isEmpty);
    },
  );

  test(
    'new squadless idle crew stay reviewable until an explicit choice',
    () async {
      final review = store();
      await review.observe(101, [], day);
      await review.observe(101, [person], tomorrow);
      final notice = review.notices.single;
      expect(notice.kind, OrganisationReviewKind.newRecruit);
      expect(notice.title, 'New crew member');
      expect(
        notice.detail,
        contains('Daily orders and squad membership are separate'),
      );

      final reopened = store();
      await reopened.observe(101, [person], DateTime(2023, 1, 6));
      expect(reopened.notices.single.id, notice.id);
      await reopened.acknowledge(notice.id);
      await reopened.observe(101, [person], DateTime(2023, 1, 7));
      expect(reopened.notices, isEmpty);
      final acknowledged = store();
      await acknowledged.observe(101, [person], DateTime(2023, 1, 8));
      expect(acknowledged.notices, isEmpty);
    },
  );

  test(
    'new arrivals with work, a squad, or no availability are not idle recruits',
    () async {
      final review = store();
      await review.observe(101, [], day);
      person.activity = Activity(ActivityType.donations);
      await review.observe(101, [person], tomorrow);
      expect(review.notices, isEmpty);
      person.activity = Activity.none();
      await review.observe(101, [person], tomorrow);
      expect(review.notices, isEmpty);

      await review.observe(102, [], day);
      person.squad = game.squads.first;
      await review.observe(102, [person], tomorrow);
      expect(review.notices, isEmpty);

      await review.observe(103, [], day);
      person.squad = null;
      person.sleeperAgent = true;
      await review.observe(103, [person], tomorrow);
      expect(review.notices, isEmpty);
      person.sleeperAgent = false;
      await review.observe(103, [person], DateTime(2023, 1, 6));
      expect(review.notices.single.kind, OrganisationReviewKind.returned);
    },
  );

  test(
    'joining a squad or assigning work resolves a new recruit notice',
    () async {
      final review = store();
      await review.observe(101, [], day);
      await review.observe(101, [person], tomorrow);
      expect(review.notices.single.kind, OrganisationReviewKind.newRecruit);
      person.squad = game.squads.first;
      await review.observe(101, [person], tomorrow);
      expect(review.notices, isEmpty);

      person.squad = null;
      await review.observe(102, [], day);
      await review.observe(102, [person], tomorrow);
      person.activity = Activity(ActivityType.donations);
      await review.observe(102, [person], tomorrow);
      expect(review.notices, isEmpty);
    },
  );

  test(
    'released crew get a custody follow-up without inferring a release date',
    () async {
      final home = person.locationId;
      person.location = game.sites.firstWhere(
        (site) => site.isPartOfTheJusticeSystem,
      );
      final review = store();
      await review.observe(101, [person], day);
      await review.observe(101, [person], tomorrow);
      expect(review.notices, isEmpty);
      person.locationId = home;
      await review.observe(101, [person], tomorrow);
      expect(review.notices.single.kind, OrganisationReviewKind.returned);
      expect(review.notices.single.title, 'Returned from custody');
      final reopened = store();
      await reopened.observe(101, [person], DateTime(2023, 1, 6));
      expect(reopened.notices.single.title, 'Returned from custody');
    },
  );

  test(
    'an observed queued squad visit becomes a persistent return follow-up',
    () async {
      final squad = game.squads.first;
      person.squad = squad;
      final destination = game.sites.firstWhere(
        (site) => site.type == SiteType.publicPark,
      );
      squad.activity = Activity(
        ActivityType.visit,
        idString: destination.idString,
      );
      final review = store();
      await review.observe(101, [person], day);
      expect(review.notices, isEmpty);

      // The original day processor clears the squad visit before the next safe
      // headquarters snapshot; the person's own idle order never changes.
      // Failed departures produce the same HQ history, so the notice names the
      // ended order and destination without claiming a successful trip.
      squad.activity = Activity.none();
      final reopened = store();
      await reopened.observe(101, [person], tomorrow);
      final notice = reopened.notices.single;
      expect(notice.kind, OrganisationReviewKind.visitFinished);
      expect(notice.title, 'Visit order ended');
      expect(notice.detail, contains(destination.getName()));
      expect(notice.detail, contains('prepare another visit'));
      await reopened.observe(101, [person], DateTime(2023, 1, 6));
      expect(reopened.notices.single.id, notice.id);
      final returned = store();
      await returned.observe(101, [person], DateTime(2023, 1, 7));
      expect(returned.notices.single.id, notice.id);
      await returned.acknowledge(notice.id);
      await returned.observe(101, [person], DateTime(2023, 1, 8));
      expect(returned.notices, isEmpty);
    },
  );

  test(
    'canceling a visit on the same day never becomes a completion',
    () async {
      final squad = game.squads.first;
      person.squad = squad;
      final destination = game.sites.firstWhere(
        (site) => site.type == SiteType.publicPark,
      );
      squad.activity = Activity(
        ActivityType.visit,
        idString: destination.idString,
      );
      final review = store();
      await review.observe(101, [person], day);
      squad.activity = Activity.none();
      await review.observe(101, [person], day);
      await review.observe(101, [person], tomorrow);
      expect(review.notices, isEmpty);
    },
  );

  test(
    'ongoing visits and unavailable or working crew do not get visit reminders',
    () async {
      final squad = game.squads.first;
      person.squad = squad;
      final destination = game.sites.firstWhere(
        (site) => site.type == SiteType.publicPark,
      );
      squad.activity = Activity(
        ActivityType.visit,
        idString: destination.idString,
      );
      final review = store();
      await review.observe(101, [person], day);
      await review.observe(101, [person], tomorrow);
      expect(review.notices, isEmpty);
      squad.activity = Activity.none();
      person.activity = Activity(ActivityType.donations);
      await review.observe(101, [person], DateTime(2023, 1, 6));
      expect(review.notices, isEmpty);

      person.activity = Activity.none();
      squad.activity = Activity(
        ActivityType.visit,
        idString: destination.idString,
      );
      await review.observe(101, [person], DateTime(2023, 1, 6));
      squad.activity = Activity.none();
      person.hidingDaysLeft = 2;
      await review.observe(101, [person], DateTime(2023, 1, 7));
      expect(review.notices, isEmpty);
      person.alive = false;
      await review.observe(101, [person], DateTime(2023, 1, 8));
      expect(review.notices, isEmpty);
    },
  );

  test(
    'a new visit clears follow-ups and useful work clears a finished visit',
    () async {
      final squad = game.squads.first;
      person.squad = squad;
      final destination = game.sites.firstWhere(
        (site) => site.type == SiteType.publicPark,
      );
      squad.activity = Activity(
        ActivityType.visit,
        idString: destination.idString,
      );
      final review = store();
      await review.observe(101, [person], day);
      squad.activity = Activity.none();
      await review.observe(101, [person], tomorrow);
      expect(review.notices.single.kind, OrganisationReviewKind.visitFinished);
      squad.activity = Activity(
        ActivityType.visit,
        idString: destination.idString,
      );
      await review.observe(101, [person], tomorrow);
      expect(review.notices, isEmpty);
      squad.activity = Activity.none();
      await review.observe(101, [person], DateTime(2023, 1, 6));
      expect(review.notices.single.kind, OrganisationReviewKind.visitFinished);
      person.activity = Activity(ActivityType.donations);
      await review.observe(101, [person], DateTime(2023, 1, 6));
      expect(review.notices, isEmpty);
    },
  );

  test(
    'returned hospital patient stays reviewable across days and restart',
    () async {
      final home = person.locationId;
      person.location = game.sites.firstWhere(
        (site) => site.type == SiteType.universityHospital,
      );
      final review = store();
      await review.observe(101, [person], day);
      expect(review.notices, isEmpty);
      person.locationId = home;
      await review.observe(101, [person], tomorrow);
      expect(review.notices.single.personId, person.id);
      expect(review.notices.single.kind, OrganisationReviewKind.returned);
      expect(review.notices.single.title, 'Returned from hospital');
      final noticeId = review.notices.single.id;

      final reopened = store();
      await reopened.observe(101, [person], DateTime(2023, 1, 6));
      expect(reopened.notices.single.id, noticeId);
      await reopened.acknowledge(noticeId);
      await reopened.observe(101, [person], DateTime(2023, 1, 7));
      expect(reopened.notices, isEmpty);
      final acknowledged = store();
      await acknowledged.observe(101, [person], DateTime(2023, 1, 8));
      expect(acknowledged.notices, isEmpty);
    },
  );

  test(
    'hospital and away countdowns do not produce premature reminders',
    () async {
      person.hidingDaysLeft = 3;
      final review = store();
      await review.observe(101, [person], day);
      person.hidingDaysLeft = 2;
      person.blood -= 1;
      person.infiltration += 0.03;
      await review.observe(101, [person], tomorrow);
      expect(review.notices, isEmpty);
      person.hidingDaysLeft = 1;
      await review.observe(101, [person], DateTime(2023, 1, 6));
      expect(review.notices, isEmpty);
      person.hidingDaysLeft = 0;
      await review.observe(101, [person], DateTime(2023, 1, 7));
      expect(review.notices.single.kind, OrganisationReviewKind.returned);
      final id = review.notices.single.id;
      for (var i = 8; i <= 12; i++) {
        await review.observe(101, [person], DateTime(2023, 1, i));
      }
      expect(review.notices.single.id, id);
    },
  );

  test('indefinite hiding stays unavailable until an actual return', () async {
    person.activity = Activity(ActivityType.study, skill: Skill.art);
    final review = store();
    await review.observe(101, [person], day);

    // Losing contact clears the order and uses -1 for indefinite hiding.
    person
      ..hidingDaysLeft = -1
      ..activity = Activity.none();
    await review.observe(101, [person], tomorrow);
    expect(review.notices, isEmpty);

    final reopened = store();
    await reopened.observe(101, [person], DateTime(2023, 1, 6));
    expect(reopened.notices, isEmpty);
    person.hidingDaysLeft = 2;
    await reopened.observe(101, [person], DateTime(2023, 1, 7));
    expect(reopened.notices, isEmpty);

    person.hidingDaysLeft = 0;
    await reopened.observe(101, [person], DateTime(2023, 1, 9));
    expect(reopened.notices.single.kind, OrganisationReviewKind.returned);
    final noticeId = reopened.notices.single.id;
    await reopened.observe(101, [person], DateTime(2023, 1, 10));
    expect(reopened.notices.single.id, noticeId);
  });

  test(
    'sleeper recall is observed without changing sleeper mechanics',
    () async {
      person.sleeperAgent = true;
      person.activity = Activity(ActivityType.sleeperJoinLcs);
      final review = store();
      await review.observe(101, [person], day);
      person.sleeperAgent = false;
      person.activity = Activity.none();
      await review.observe(101, [person], tomorrow);
      expect(review.notices.single.title, 'Sleeper recalled');
    },
  );

  for (final activity in [
    ActivityType.study,
    ActivityType.takeClass,
    ActivityType.teachLiberalArts,
    ActivityType.teachFighting,
    ActivityType.teachCovert,
  ]) {
    test(
      '${activity.name} ending after a day produces one follow-up',
      () async {
        person.activity = Activity(activity, skill: Skill.persuasion);
        person.squadId = 1;
        final review = store();
        await review.observe(101, [person], day);
        person.activity = Activity.none();
        await review.observe(101, [person], tomorrow);
        expect(
          review.notices.single.kind,
          OrganisationReviewKind.assignmentFinished,
        );
        expect(review.notices.single.detail, contains(person.name));
        final id = review.notices.single.id;
        await review.observe(101, [person], tomorrow);
        await review.observe(101, [person], DateTime(2023, 1, 6));
        expect(review.notices.single.id, id);
        await review.acknowledgePerson(person.id);
        await review.observe(101, [person], DateTime(2023, 1, 7));
        expect(review.notices, isEmpty);
      },
    );
  }

  test(
    'choosing Lay Low deliberately on the same day is not a completion',
    () async {
      person.activity = Activity(ActivityType.study, skill: Skill.art);
      final review = store();
      await review.observe(101, [person], day);
      person.activity = Activity.none();
      await review.observe(101, [person], day);
      expect(review.notices, isEmpty);
      await review.observe(101, [person], tomorrow);
      expect(review.notices, isEmpty);
    },
  );

  test(
    'baseline survives restart and detects a later completed assignment',
    () async {
      person.activity = Activity(ActivityType.study, skill: Skill.art);
      final review = store();
      await review.observe(101, [person], day);
      person.activity = Activity.none();
      final reopened = store();
      await reopened.observe(101, [person], tomorrow);
      expect(
        reopened.notices.single.kind,
        OrganisationReviewKind.assignmentFinished,
      );
      await reopened.observe(102, [person], tomorrow);
      expect(reopened.notices, isEmpty);
      await reopened.observe(101, [person], tomorrow);
      expect(
        reopened.notices.single.kind,
        OrganisationReviewKind.assignmentFinished,
      );
      expect(
        (await SharedPreferences.getInstance()).getString('unrelatedSetting'),
        'keep',
      );
    },
  );

  test(
    'useful work clears notices; joining a squad resolves a return',
    () async {
      person.vacationDaysLeft = 1;
      final review = store();
      await review.observe(101, [person], day);
      person.vacationDaysLeft = 0;
      await review.observe(101, [person], tomorrow);
      expect(review.notices, hasLength(1));
      person.squadId = 1;
      await review.observe(101, [person], tomorrow);
      expect(review.notices, isEmpty);

      person.activity = Activity(ActivityType.study, skill: Skill.art);
      await review.observe(101, [person], tomorrow);
      person.activity = Activity.none();
      await review.observe(101, [person], DateTime(2023, 1, 6));
      expect(review.notices, hasLength(1));
      person.activity = Activity(ActivityType.donations);
      await review.observe(101, [person], DateTime(2023, 1, 6));
      expect(review.notices, isEmpty);
    },
  );

  test(
    'dead, hospitalized, captive and missing crew never need normal orders',
    () async {
      final review = store();
      Future<void> completeTraining() async {
        person.activity = Activity(ActivityType.study, skill: Skill.art);
        await review.observe(101, [person], day);
        person.activity = Activity.none();
        await review.observe(101, [person], tomorrow);
        expect(review.notices, hasLength(1));
      }

      await completeTraining();
      person.alive = false;
      await review.observe(101, [person], tomorrow);
      expect(review.notices, isEmpty);
      person.alive = true;
      await review.observe(101, [person], DateTime(2023, 1, 6));
      expect(review.notices, isEmpty);
      person.location = game.sites.firstWhere(
        (site) => site.type == SiteType.universityHospital,
      );
      await review.observe(101, [person], DateTime(2023, 1, 7));
      expect(review.notices, isEmpty);
      person.location = game.sites.firstWhere(
        (site) => site.isPartOfTheJusticeSystem,
      );
      await review.observe(101, [person], DateTime(2023, 1, 8));
      expect(review.notices, isEmpty);
      person.missing = true;
      await review.observe(101, [person], DateTime(2023, 1, 9));
      expect(review.notices, isEmpty);
    },
  );

  test(
    'a removed person or older campaign save clears stale follow-ups',
    () async {
      person.activity = Activity(ActivityType.study, skill: Skill.art);
      final review = store();
      await review.observe(101, [person], day);
      person.activity = Activity.none();
      await review.observe(101, [person], tomorrow);
      expect(review.notices, hasLength(1));
      await review.observe(101, [], tomorrow);
      expect(review.notices, isEmpty);
      person.activity = Activity(ActivityType.study, skill: Skill.art);
      await review.observe(101, [person], tomorrow);
      person.activity = Activity.none();
      await review.observe(101, [person], DateTime(2023, 1, 6));
      expect(review.notices, hasLength(1));
      await review.observe(101, [person], day);
      expect(review.notices, isEmpty);
    },
  );

  test(
    'queued observation captures game input before storage finishes loading',
    () async {
      final preferences = Completer<SharedPreferences>();
      person.activity = Activity(ActivityType.study, skill: Skill.art);
      final review = store(preferences: () => preferences.future);
      final baseline = review.observe(101, [person], day);
      person.activity = Activity.none();
      preferences.complete(await SharedPreferences.getInstance());
      await baseline;
      expect(review.notices, isEmpty);
      await review.observe(101, [person], tomorrow);
      expect(
        review.notices.single.kind,
        OrganisationReviewKind.assignmentFinished,
      );
    },
  );

  test(
    'late campaign loads cannot overwrite current snapshots or notices',
    () async {
      final first = Completer<SharedPreferences>();
      final second = Completer<SharedPreferences>();
      var calls = 0;
      final review = store(
        preferences: () => calls++ == 0 ? first.future : second.future,
      );
      person.activity = Activity(ActivityType.study, skill: Skill.art);
      final a = review.observe(101, [person], day);
      // Let the first loader start before dispatching the second one.
      await Future<void>.delayed(Duration.zero);
      final b = review.observe(102, [person], day);
      final preferences = await SharedPreferences.getInstance();
      second.complete(preferences);
      await b;
      person.activity = Activity.none();
      await review.observe(102, [person], tomorrow);
      expect(review.notices, hasLength(1));
      first.complete(preferences);
      await a;
      expect(review.loaded, isTrue);
      expect(review.notices, hasLength(1));
      final reopened = store();
      await reopened.observe(101, [person], tomorrow);
      expect(reopened.notices, isEmpty);
    },
  );

  test(
    'storage failure and corrupt history keep reviews usable in memory',
    () async {
      person.activity = Activity(ActivityType.study, skill: Skill.art);
      final review = store(
        preferences: () async => throw StateError('offline'),
      );
      await review.observe(101, [person], day);
      person.activity = Activity.none();
      await review.observe(101, [person], tomorrow);
      expect(review.loaded, isTrue);
      expect(review.notices, hasLength(1));
      await review.acknowledge(review.notices.single.id);
      expect(review.notices, isEmpty);

      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('organisationReview.v1.102', '{broken');
      final corrupted = store();
      await corrupted.observe(102, [person], tomorrow);
      expect(corrupted.loaded, isTrue);
      expect(corrupted.notices, isEmpty);
    },
  );

  test('pending loads and actions are safe after disposal', () async {
    final preferences = Completer<SharedPreferences>();
    final review = store(preferences: () => preferences.future);
    var notifications = 0;
    review.addListener(() => notifications++);
    final pending = review.observe(101, [person], day);
    review.dispose();
    final before = notifications;
    preferences.complete(await SharedPreferences.getInstance());
    await pending;
    await review.observe(102, [person], tomorrow);
    await review.acknowledge('anything');
    await review.acknowledgePerson(person.id);
    expect(notifications, before);
    expect(review.notices, isEmpty);
  });

  test(
    'observing and acknowledging leave all campaign fields and RNG unchanged',
    () async {
      person.activity = Activity(ActivityType.study, skill: Skill.art);
      final review = store();
      final before = jsonEncode(game.gameState.toJson());
      reseedRNG(seed: 20261018);
      final rolls = List.generate(8, (_) => lcsRandom(100000));
      reseedRNG(seed: 20261018);
      await review.observe(game.gameState.uniqueGameId, game.pool, day);
      expect(jsonEncode(game.gameState.toJson()), before);
      person.activity = Activity.none();
      final afterRealGameChange = jsonEncode(game.gameState.toJson());
      await review.observe(game.gameState.uniqueGameId, game.pool, tomorrow);
      await review.acknowledgePerson(person.id);
      expect(jsonEncode(game.gameState.toJson()), afterRealGameChange);
      expect(List.generate(8, (_) => lcsRandom(100000)), rolls);
    },
  );
}
