import 'package:flutter/foundation.dart';
import 'package:lcs_new_age/creature/creature_type.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/gamestate/time.dart';
import 'package:lcs_new_age/location/site.dart';

@immutable
class BaseRentSummary {
  const BaseRentSummary({
    required this.title,
    required this.detail,
    this.warning,
    this.collectionDate,
    this.forcedEviction = false,
  });

  final String title, detail;
  final String? warning;
  final DateTime? collectionDate;
  final bool forcedEviction;
}

/// Mirrors the public rent conditions in advance_day.dart's _doRent without
/// running it, changing a lease or treating forced-eviction sentinels as bills.
BaseRentSummary baseRentSummary(Site site) {
  final landlord = game.pool.any(
    (person) =>
        person.alive &&
        person.sleeperAgent &&
        person.type.id == CreatureTypeIds.landlord &&
        person.workSite == site,
  );
  if (landlord) {
    return const BaseRentSummary(
      title: 'Rent waived by undercover landlord',
      detail:
          'At collection, a living landlord sleeper working here makes this base rent-free.',
    );
  }
  final forcedEviction =
      site.rent >= 1000000 || site.chargesRent && site.rent == 0;
  if (!forcedEviction && site.rent == 0) {
    return const BaseRentSummary(
      title: 'No monthly rent',
      detail: 'This base has no rent payment.',
    );
  }
  final collection = DateTime(
    game.year,
    game.month + (site.newRental || game.day > 3 ? 1 : 0),
    3,
  );
  final timing =
      'Collection runs when you advance from ${collection.day} ${getMonth(collection.month)} ${collection.year}.';
  final exemption = site.newRental
      ? ' New lease: exempt from collection until next month.'
      : '';
  const consequence =
      'Eviction moves residents and stored gear to the local homeless camp; base upgrades are lost.';
  return BaseRentSummary(
    title: forcedEviction
        ? 'Lease no longer valid'
        : 'Rent \$${site.rent}/month · collected on the 3rd',
    detail: '$timing$exemption',
    warning: forcedEviction
        ? 'Eviction is due at collection unless an undercover landlord working here secures the base. $consequence'
        : game.ledger.funds < site.rent
        ? 'Current cash is \$${site.rent - game.ledger.funds} short of this rent. Income and other expenses before collection can change that. $consequence'
        : 'Collection is automatic; a cash shortfall causes eviction. $consequence',
    collectionDate: collection,
    forcedEviction: forcedEviction,
  );
}
