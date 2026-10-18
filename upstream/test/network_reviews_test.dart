import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activate_sleepers.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/creature_type.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/modern/network_reviews.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String fixture;
  late Creature sleeper;
  final stores = <NetworkReviewStore>[];

  NetworkReviewStore store({
    Future<SharedPreferences> Function()? preferences,
  }) {
    final result = NetworkReviewStore(preferences: preferences);
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
    sleeper = game.pool.first
      ..sleeperAgent = true
      ..activity = Activity(ActivityType.sleeperSpy);
  });

  tearDown(() {
    for (final review in stores) {
      review.dispose();
    }
    stores.clear();
  });

  test(
    'role review survives app restart and isolates campaigns and people',
    () async {
      final review = store();
      expect(review.loaded, isFalse);
      expect(review.needsReview(sleeper), isFalse);
      await review.load(101);
      expect(review.loaded, isTrue);
      expect(review.needsReview(sleeper), isTrue);
      expect(review.count(game.pool), 1);
      await review.markReviewed(sleeper);
      expect(review.needsReview(sleeper), isFalse);

      final reopened = store();
      await reopened.load(101);
      expect(reopened.needsReview(sleeper), isFalse);
      final other = game.pool[1]..sleeperAgent = true;
      expect(reopened.needsReview(other), isTrue);
      await reopened.load(102);
      expect(reopened.needsReview(sleeper), isTrue);
      await reopened.markReviewed(other);
      await reopened.load(101);
      expect(reopened.needsReview(sleeper), isFalse);
      expect(reopened.needsReview(other), isTrue);
      expect(
        (await SharedPreferences.getInstance()).getString('unrelatedSetting'),
        'keep',
      );
    },
  );

  test('only material role changes invite another review', () async {
    final review = store();
    await review.load(101);
    await review.markReviewed(sleeper);
    sleeper.infiltration += 0.03;
    game.gameState.date = game.gameState.date.add(const Duration(days: 28));
    sleeper.daysHospitalized++;
    expect(review.needsReview(sleeper), isFalse);

    sleeper.activity = Activity(ActivityType.sleeperEmbezzle);
    expect(review.needsReview(sleeper), isTrue);
    await review.markReviewed(sleeper);
    sleeper.workLocation = game.sites.firstWhere(
      (site) => site.idString != sleeper.workLocationId,
    );
    expect(review.needsReview(sleeper), isTrue);
    await review.markReviewed(sleeper);
    sleeper.type = creatureTypes.values.firstWhere(
      (type) => type.id != sleeper.typeId,
    );
    expect(review.needsReview(sleeper), isTrue);
    await review.markReviewed(sleeper);
    sleeper.hidingDaysLeft = 3;
    expect(review.needsReview(sleeper), isTrue);
    await review.markReviewed(sleeper);
    sleeper.hidingDaysLeft = 2;
    expect(review.needsReview(sleeper), isFalse);
    sleeper.hidingDaysLeft = 0;
    expect(review.needsReview(sleeper), isTrue);
  });

  test(
    'reading and acknowledging roles leaves campaign and RNG unchanged',
    () async {
      final before = jsonEncode(game.gameState.toJson());
      reseedRNG(seed: 20261018);
      final rolls = List.generate(8, (_) => lcsRandom(100000));
      reseedRNG(seed: 20261018);
      final review = store();
      await review.load(game.gameState.uniqueGameId);
      review.count(game.pool);
      sleeperOrderUnavailableReason(sleeper);
      await review.markReviewed(sleeper);
      expect(jsonEncode(game.gameState.toJson()), before);
      expect(List.generate(8, (_) => lcsRandom(100000)), rolls);
    },
  );

  test('late campaign loads cannot overwrite the current campaign', () async {
    final first = Completer<SharedPreferences>();
    final second = Completer<SharedPreferences>();
    var calls = 0;
    final review = store(
      preferences: () => calls++ == 0 ? first.future : second.future,
    );
    final a = review.load(101);
    final b = review.load(102);
    final preferences = await SharedPreferences.getInstance();
    second.complete(preferences);
    await b;
    await review.markReviewed(sleeper);
    first.complete(preferences);
    await a;
    expect(review.loaded, isTrue);
    expect(review.needsReview(sleeper), isFalse);
    final reopened = store();
    await reopened.load(101);
    expect(reopened.needsReview(sleeper), isTrue);
    await reopened.load(102);
    expect(reopened.needsReview(sleeper), isFalse);
  });

  test('storage failure keeps review usable in memory', () async {
    final review = store(preferences: () async => throw StateError('offline'));
    await review.load(101);
    expect(review.loaded, isTrue);
    expect(review.needsReview(sleeper), isTrue);
    await review.markReviewed(sleeper);
    expect(review.needsReview(sleeper), isFalse);
  });

  test('pending load and acknowledgement are safe after disposal', () async {
    final preferences = Completer<SharedPreferences>();
    final review = store(preferences: () => preferences.future);
    var notifications = 0;
    review.addListener(() => notifications++);
    final pending = review.load(101);
    review.dispose();
    final before = notifications;
    preferences.complete(await SharedPreferences.getInstance());
    await pending;
    await review.markReviewed(sleeper);
    await review.load(102);
    expect(notifications, before);
    expect(review.needsReview(sleeper), isFalse);
  });

  test(
    'unavailable sleepers can be reviewed but dead or active crew cannot',
    () async {
      final review = store();
      await review.load(101);
      sleeper.vacationDaysLeft = 2;
      expect(review.needsReview(sleeper), isTrue);
      await review.markReviewed(sleeper);
      sleeper.vacationDaysLeft = 1;
      expect(review.needsReview(sleeper), isFalse);
      sleeper.alive = false;
      expect(review.needsReview(sleeper), isFalse);
      expect(review.count(game.pool), 0);
    },
  );

  test(
    'eligibility exactly matches original sleeper roster including clinic staff',
    () {
      void check() {
        final sourceEligible =
            sleeper.alive &&
            sleeper.sleeperAgent &&
            sleeper.align == Alignment.liberal &&
            !sleeper.inHiding &&
            !sleeper.hospitalized &&
            sleeper.vacationDaysLeft == 0;
        expect(sleeperOrderUnavailableReason(sleeper) == null, sourceEligible);
      }

      check();
      sleeper.alive = false;
      check();
      sleeper.alive = true;
      sleeper.align = Alignment.moderate;
      check();
      sleeper.align = Alignment.liberal;
      for (final days in [-1, 0, 1]) {
        sleeper.vacationDaysLeft = days;
        check();
      }
      sleeper.vacationDaysLeft = 0;
      for (final days in [-1, 0, 1]) {
        sleeper.hidingDaysLeft = days;
        check();
      }
      sleeper.hidingDaysLeft = 0;
      final clinic = game.sites.firstWhere(
        (site) => site.type == SiteType.clinic,
      );
      sleeper.workLocation = clinic;
      sleeper.location = clinic;
      expect(sleeperOrderUnavailableReason(sleeper), isNull);
      check();
      sleeper.location = game.sites.firstWhere(
        (site) => site.type == SiteType.clinic && site != clinic,
      );
      expect(sleeperOrderUnavailableReason(sleeper), contains('hospitalized'));
      check();
      sleeper.location = game.sites.firstWhere(
        (site) => site.type == SiteType.universityHospital,
      );
      check();
      sleeper.sleeperAgent = false;
      check();
    },
  );
}
