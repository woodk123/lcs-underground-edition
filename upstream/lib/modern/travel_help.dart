import 'package:lcs_new_age/basemode/plan_site_visit.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/gamestate/squad.dart';
import 'package:lcs_new_age/location/location.dart';
import 'package:lcs_new_age/location/site.dart';

/// Display-only notes for this route. Availability still comes from the
/// original planner's actions; departure rechecks vehicles, funds and access.
/// The fee uses the member's base city, as in daily/advance_day.dart.
List<String> travelNotices(Location destination, Squad? squad) {
  if (squad == null || squad.members.isEmpty) return const [];
  final cost = destination.city.id != squad.members.first.base?.cityId
      ? squad.members.length * intercityTicketPrice
      : 0;
  return [
    if (cost > 0) '\$$cost',
    if (destination.area != squad.site?.area &&
        !squad.members.any((member) => member.preferredCar != null))
      'needs car',
    if (cost > 0 && cost > game.ledger.funds) 'not enough cash',
    if (destination is Site && destination.isClosed) 'closed',
    if (destination is Site && destination.siege.underSiege) 'under siege',
  ];
}

List<String> intercityTravelNotices(Squad? squad) {
  if (squad == null || squad.members.isEmpty) return const [];
  final cost = squad.members.length * intercityTicketPrice;
  return [
    '\$$cost',
    if (!squad.members.any((member) => member.preferredCar != null))
      'needs car',
    if (cost > game.ledger.funds) 'not enough cash',
  ];
}

String travelSuffix(Iterable<String> notices) =>
    notices.map((notice) => ' ($notice)').join();
