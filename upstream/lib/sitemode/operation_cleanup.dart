import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/gamestate/game_state.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/politics/alignment.dart';

/// Snapshot the people involved before custody, hauling or return-to-base
/// handlers change their locations and squad membership. Siege reserves provide
/// cover fire from this site; people at other sites are not part of the action.
Set<Creature> operationParticipants({Site? siegeSite}) {
  final people = <Creature>{
    ...squad,
    if (siegeSite?.siege.underSiege == true)
      ...pool.where(
        (person) =>
            person.location == siegeSite && person.align == Alignment.liberal,
      ),
  };
  return {
    ...people,
    for (final person in people)
      if (person.prisoner != null) person.prisoner!,
  };
}
