import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum OrganisationReviewKind {
  returned,
  assignmentFinished,
  newRecruit,
  visitFinished,
}

/// Jobs that can be prepared again without replaying saved target selections.
/// The real order reader still checks eligibility and requires confirmation.
String? previousOrderCategory(ActivityType? type) => switch (type) {
  ActivityType.donations ||
  ActivityType.sellTshirts ||
  ActivityType.sellArt ||
  ActivityType.sellMusic => 'legal',
  ActivityType.sellDrugs ||
  ActivityType.prostitution ||
  ActivityType.ccfraud => 'illegal',
  ActivityType.stealCars || ActivityType.recruiting => 'acquisition',
  ActivityType.communityService ||
  ActivityType.trouble ||
  ActivityType.graffiti ||
  ActivityType.hacking ||
  ActivityType.writeGuardian => 'activism',
  _ => null,
};

/// A follow-up to an observed change, rather than a demand to stop resting.
@immutable
class OrganisationReviewNotice {
  const OrganisationReviewNotice({
    required this.id,
    required this.personId,
    required this.title,
    required this.detail,
    required this.kind,
    this.previousActivity,
  });

  factory OrganisationReviewNotice._fromJson(Map<String, dynamic> json) =>
      OrganisationReviewNotice(
        id: json['id'] as String,
        personId: json['personId'] as int,
        title: json['title'] as String,
        detail: json['detail'] as String,
        kind: OrganisationReviewKind.values.byName(json['kind'] as String),
        previousActivity: ActivityType.values
            .where((type) => type.name == json['previousActivity'])
            .firstOrNull,
      );

  final String id;
  final int personId;
  final String title;
  final String detail;
  final OrganisationReviewKind kind;
  final ActivityType? previousActivity;

  Map<String, dynamic> _toJson() => {
    'id': id,
    'personId': personId,
    'title': title,
    'detail': detail,
    'kind': kind.name,
    if (previousActivity != null) 'previousActivity': previousActivity!.name,
  };
}

/// Local presentation history for the People desk, separate from campaign saves.
///
/// Call [observe] at safe headquarters snapshots. The first observation only
/// establishes a baseline: it does not invent historical returns or completions.
/// Newly observed squadless crew and observed returns stay reviewable. A
/// training order or queued squad visit ending counts as finished only after
/// the date advances. Observing a deliberate same-day cancellation updates the
/// baseline without producing a notice. Resting is always a valid choice.
class OrganisationReviewStore extends ChangeNotifier {
  OrganisationReviewStore({Future<SharedPreferences> Function()? preferences})
    : _preferencesLoader = preferences ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _preferencesLoader;
  final Map<int, _PersonSnapshot> _previous = {};
  final Map<String, OrganisationReviewNotice> _notices = {};
  SharedPreferences? _preferences;
  Future<void> _tail = Future<void>.value();
  Future<void> _writes = Future<void>.value();
  int? _campaignId;
  int? _previousDay;
  int _generation = 0;
  bool _loaded = false;
  bool _disposed = false;

  bool get loaded => _loaded;
  List<OrganisationReviewNotice> get notices =>
      List.unmodifiable(_notices.values);

  String _key(int campaignId) => 'organisationReview.v1.$campaignId';

  /// Copies every game field before any asynchronous load or storage operation.
  /// Old campaign loads and observations cannot change a newer campaign's UI.
  Future<void> observe(
    int campaignId,
    Iterable<Creature> people,
    DateTime date,
  ) {
    if (_disposed) return Future<void>.value();
    final observation = _Observation(people, date);
    if (_campaignId != campaignId) {
      final generation = ++_generation;
      _campaignId = campaignId;
      _loaded = false;
      _preferences = null;
      _previousDay = null;
      _previous.clear();
      _notices.clear();
      _tail = _load(campaignId, generation);
      notifyListeners();
    }
    final generation = _generation;
    return _tail = _tail.then((_) async {
      if (_disposed || generation != _generation) return;
      if (_apply(observation)) await _persist(campaignId);
    });
  }

  Future<void> _load(int campaignId, int generation) async {
    SharedPreferences? preferences;
    int? previousDay;
    final previous = <int, _PersonSnapshot>{};
    final notices = <String, OrganisationReviewNotice>{};
    try {
      // A quick switch back must read the previous campaign's latest write.
      await _writes;
      preferences = await _preferencesLoader();
      final saved = preferences.getString(_key(campaignId));
      if (saved != null) {
        final json = Map<String, dynamic>.from(jsonDecode(saved) as Map);
        previousDay = json['day'] as int;
        for (final value in json['people'] as List) {
          final person = _PersonSnapshot.fromJson(
            Map<String, dynamic>.from(value as Map),
          );
          previous[person.id] = person;
        }
        for (final value in json['notices'] as List) {
          final notice = OrganisationReviewNotice._fromJson(
            Map<String, dynamic>.from(value as Map),
          );
          notices[notice.id] = notice;
        }
      }
    } catch (_) {
      // Corrupt or unavailable local storage must never stop real game controls.
      previousDay = null;
      previous.clear();
      notices.clear();
    }
    if (_disposed || generation != _generation) return;
    _preferences = preferences;
    _previousDay = previousDay;
    _previous.addAll(previous);
    _notices.addAll(notices);
    _loaded = true;
    notifyListeners();
  }

  bool _apply(_Observation observation) {
    final oldDay = _previousDay;
    var noticesChanged = false;
    // Loading an older save from this campaign establishes a fresh baseline.
    if (oldDay != null && observation.day < oldDay) {
      noticesChanged = _notices.isNotEmpty;
      _notices.clear();
      _previous.clear();
      _previousDay = null;
    }

    final before = _notices.length;
    _notices.removeWhere((_, notice) {
      final person = observation.people[notice.personId];
      return person == null ||
          !person.available ||
          person.activity != ActivityType.none ||
          person.queuedSquadVisit ||
          (const {
                OrganisationReviewKind.returned,
                OrganisationReviewKind.newRecruit,
              }.contains(notice.kind) &&
              person.squadId != null);
    });
    noticesChanged |= before != _notices.length;

    if (_previousDay != null) {
      for (final person in observation.people.values) {
        final previous = _previous[person.id];
        if (!person.available ||
            person.activity != ActivityType.none ||
            person.queuedSquadVisit) {
          continue;
        }
        OrganisationReviewNotice? notice;
        if (previous == null && person.squadId == null) {
          notice = OrganisationReviewNotice(
            id: '${person.id}.newRecruit.${observation.day}',
            personId: person.id,
            title: 'New crew member',
            detail:
                '${person.name} joined the organisation. Daily orders and '
                'squad membership are separate: choose an order or a squad, '
                'or keep laying low.',
            kind: OrganisationReviewKind.newRecruit,
          );
        } else if (previous?.returnable == true && person.squadId == null) {
          notice = OrganisationReviewNotice(
            id: '${person.id}.returned.${observation.day}',
            personId: person.id,
            title: switch (previous!.availability) {
              'hospital' => 'Returned from hospital',
              'sleeper' => 'Sleeper recalled',
              'custody' => 'Returned from custody',
              _ => 'Returned to the organisation',
            },
            detail:
                '${person.name} is available again. Choose an order or a squad, '
                'or keep laying low.',
            kind: OrganisationReviewKind.returned,
          );
        } else if (previous?.available == true &&
            previous!.queuedSquadVisit &&
            observation.day > _previousDay!) {
          // Safe HQ history proves the order ended, not that travel succeeded:
          // a closed destination or failed departure clears the same order.
          notice = OrganisationReviewNotice(
            id: '${person.id}.visitFinished.${observation.day}',
            personId: person.id,
            title: 'Visit order ended',
            detail:
                'The squad order to visit '
                '${previous.squadVisitDestination ?? 'a location'} has ended. '
                '${person.name} is available for daily work. '
                'Choose another order, prepare another visit, or keep laying low.',
            kind: OrganisationReviewKind.visitFinished,
            previousActivity: previousOrderCategory(previous.activity) == null
                ? null
                : previous.activity,
          );
        } else if (previous?.available == true &&
            previous!.training &&
            observation.day > _previousDay!) {
          notice = OrganisationReviewNotice(
            id: '${person.id}.assignmentFinished.${observation.day}',
            personId: person.id,
            title: 'Assignment finished',
            detail:
                '${person.name} stopped ${previous.activityDescription}. '
                'Choose another order or keep laying low.',
            kind: OrganisationReviewKind.assignmentFinished,
          );
        }
        if (notice != null && !_notices.containsKey(notice.id)) {
          _notices.removeWhere((_, value) => value.personId == person.id);
          _notices[notice.id] = notice;
          noticesChanged = true;
        }
      }
    }

    final snapshotsChanged =
        _previousDay != observation.day ||
        !mapEquals(_previous, observation.people);
    _previousDay = observation.day;
    _previous
      ..clear()
      ..addAll(observation.people);
    if (noticesChanged) notifyListeners();
    return noticesChanged || snapshotsChanged;
  }

  Future<void> acknowledge(String id) {
    if (_disposed || !_loaded || _notices.remove(id) == null) {
      return Future<void>.value();
    }
    notifyListeners();
    return _persist(_campaignId!);
  }

  Future<void> acknowledgePerson(int personId) {
    if (_disposed || !_loaded) return Future<void>.value();
    final before = _notices.length;
    _notices.removeWhere((_, notice) => notice.personId == personId);
    if (before == _notices.length) return Future<void>.value();
    notifyListeners();
    return _persist(_campaignId!);
  }

  Future<void> _persist(int campaignId) {
    final preferences = _preferences;
    if (preferences == null || _disposed) return Future<void>.value();
    final saved = jsonEncode({
      'day': _previousDay,
      'people': _previous.values.map((person) => person.toJson()).toList(),
      'notices': _notices.values.map((notice) => notice._toJson()).toList(),
    });
    return _writes = _writes.then((_) async {
      try {
        await preferences.setString(_key(campaignId), saved);
      } catch (_) {
        // Keep working in memory when the device cannot save UI history.
      }
    });
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _generation++;
    super.dispose();
  }
}

class _Observation {
  _Observation(Iterable<Creature> people, DateTime date)
    : day = date.year * 10000 + date.month * 100 + date.day,
      people = {
        for (final person in people) person.id: _PersonSnapshot(person),
      };

  final int day;
  final Map<int, _PersonSnapshot> people;
}

@immutable
class _PersonSnapshot {
  _PersonSnapshot(Creature person)
    : id = person.id,
      name = person.name,
      availability = switch (person) {
        Creature(alive: false) => 'unavailable',
        Creature(isLiberal: false) => 'unavailable',
        Creature(missing: true) => 'unavailable',
        Creature(hospitalized: true) => 'hospital',
        Creature(sleeperAgent: true) => 'sleeper',
        Creature(imprisoned: true) => 'custody',
        Creature(hidingDaysLeft: != 0) => 'away',
        Creature(away: true) => 'away',
        _ => 'active',
      },
      activity = person.activity.type,
      activityDescription = person.activity.description,
      squadId = person.squadId,
      queuedSquadVisit = person.squad?.activity.type == ActivityType.visit,
      squadVisitDestination = person.squad?.activity.type == ActivityType.visit
          ? person.squad?.activity.location?.getName()
          : null;

  _PersonSnapshot.fromJson(Map<String, dynamic> json)
    : id = json['id'] as int,
      name = json['name'] as String,
      availability = json['availability'] as String,
      activity = ActivityType.values.byName(json['activity'] as String),
      activityDescription = json['activityDescription'] as String,
      squadId = json['squadId'] as int?,
      queuedSquadVisit = json['queuedSquadVisit'] as bool? ?? false,
      squadVisitDestination = json['squadVisitDestination'] as String?;

  final int id;
  final String name;
  final String availability;
  final ActivityType activity;
  final String activityDescription;
  final int? squadId;
  final bool queuedSquadVisit;
  final String? squadVisitDestination;

  bool get available => availability == 'active';
  bool get returnable =>
      const {'hospital', 'sleeper', 'away', 'custody'}.contains(availability);
  bool get training => const {
    ActivityType.study,
    ActivityType.takeClass,
    ActivityType.teachLiberalArts,
    ActivityType.teachFighting,
    ActivityType.teachCovert,
  }.contains(activity);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'availability': availability,
    'activity': activity.name,
    'activityDescription': activityDescription,
    'squadId': squadId,
    'queuedSquadVisit': queuedSquadVisit,
    'squadVisitDestination': squadVisitDestination,
  };

  @override
  bool operator ==(Object other) =>
      other is _PersonSnapshot &&
      id == other.id &&
      name == other.name &&
      availability == other.availability &&
      activity == other.activity &&
      activityDescription == other.activityDescription &&
      squadId == other.squadId &&
      queuedSquadVisit == other.queuedSquadVisit &&
      squadVisitDestination == other.squadVisitDestination;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    availability,
    activity,
    activityDescription,
    squadId,
    queuedSquadVisit,
    squadVisitDestination,
  );
}
