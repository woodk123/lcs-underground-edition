import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/site.dart';

/// Read-only directory helpers. They never construct sites, consolidate stores,
/// consume random values, or infer a command for another source reader.
List<Site> organisationBases() =>
    List.unmodifiable(game.sites.where((site) => site.isSafehouse));

List<Creature> baseResidents(Site site) => List.unmodifiable(
  game.pool.where((person) => person.alive && person.baseId == site.id),
);

/// Free fallback locations are available without being established LCS bases.
/// Derive this from current use so inspection never claims a location.
bool isAvailableShelter(Site site) =>
    site.isSafehouse &&
    (site.type == SiteType.homelessEncampment ||
        site.type == SiteType.warehouse) &&
    baseResidents(site).isEmpty &&
    !site.creaturesPresent.any((person) => person.alive) &&
    site.loot.isEmpty &&
    !site.compound.upgraded &&
    site.compound.rations == 0 &&
    site.compound.diesel == 0 &&
    site.heat == 0 &&
    !site.siege.underSiege;

String? baseInvestmentUnavailableReason(Site site) {
  if (!game.sites.contains(site) || !site.isSafehouse) {
    return 'This location is no longer an LCS base.';
  }
  if (site.siege.underSiege) {
    return 'Investments and supply purchases are unavailable during a siege.';
  }
  if (!site.upgradable) {
    return 'This type of base cannot be upgraded or stocked.';
  }
  return null;
}

String? storesUnavailableReason() {
  if (!game.sites.any((site) => site.isSafehouse && !site.siege.underSiege)) {
    return 'Equipment needs an LCS destination outside a siege.';
  }
  if (!game.sites.any(
    (site) => !site.siege.underSiege && site.loot.isNotEmpty,
  )) {
    return 'There is no stored equipment outside a siege to transfer.';
  }
  return null;
}

String? baseAssignmentUnavailableReason() {
  if (!game.pool.any(
    (person) => person.isActiveLiberal && person.squad == null,
  )) {
    return 'No active crew are outside squads. Squad members travel together.';
  }
  if (!game.sites.any((site) => site.isSafehouse && !site.siege.underSiege)) {
    return 'Home base assignment needs an LCS base outside a siege.';
  }
  return null;
}
