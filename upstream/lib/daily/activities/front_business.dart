import 'dart:math';

import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/gamestate/game_state.dart';
import 'package:lcs_new_age/gamestate/ledger.dart';
import 'package:lcs_new_age/location/front_business.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/politics/views.dart';

String? frontBusinessUnavailableReason(Site site) {
  if (site.controller != SiteController.lcs) {
    return 'The LCS no longer controls this base.';
  }
  if (!site.upgradable || site.discreet) {
    return 'This base cannot host a public print shop.';
  }
  if (!site.businessFront) return 'A business front is required.';
  if (site.siege.underSiege) return 'Trading is suspended during a siege.';
  if (site.isClosed) return 'The premises are closed.';
  return null;
}

String? frontBusinessWorkerUnavailableReason(Site site, Creature person) {
  if (!person.isActiveLiberal || person.inHiding) {
    return 'Unavailable for active work';
  }
  if (!person.human) return 'Requires a human crew member';
  if (person.site != site || person.base != site) {
    return 'Must be present at their own base';
  }
  if (person.squad?.activity.type != null &&
      person.squad!.activity.type != ActivityType.none) {
    return 'Squad already has orders';
  }
  if (person.activity.type == ActivityType.visit) return 'Already travelling';
  return null;
}

int printShopGrossFor(Creature person) =>
    45 +
    person.skill(Skill.business).clamp(0, 8) * 8 +
    person.skill(Skill.writing).clamp(0, 8) * 3;

int printShopInfluenceFor(Creature person) =>
    (2 +
            (person.skill(Skill.writing).clamp(0, 8) +
                    person.skill(Skill.business).clamp(0, 8)) ~/
                2)
        .clamp(2, 8);

bool _hasShopOrder(Site site, Creature person) =>
    person.activity.type == ActivityType.workPrintShop &&
    person.activity.idString == site.idString;

void unassignPrintShopWorker(Site site, Creature person) {
  site.frontBusiness?.staffIds.remove(person.id);
  if (_hasShopOrder(site, person)) person.activity = Activity.none();
}

bool assignPrintShopWorker(Site site, Creature person) {
  final shop = site.frontBusiness;
  if (shop == null ||
      shop.mode == FrontBusinessMode.closed ||
      frontBusinessUnavailableReason(site) != null ||
      frontBusinessWorkerUnavailableReason(site, person) != null) {
    return false;
  }
  final retained = pool.where(
    (p) => shop.staffIds.contains(p.id) && _hasShopOrder(site, p),
  );
  shop.staffIds = retained
      .map((p) => p.id)
      .take(FrontBusiness.maxStaff)
      .toList();
  if (!shop.staffIds.contains(person.id) &&
      shop.staffIds.length >= FrontBusiness.maxStaff) {
    return false;
  }
  for (final other in sites.where((s) => s != site)) {
    other.frontBusiness?.staffIds.remove(person.id);
  }
  if (!shop.staffIds.contains(person.id)) shop.staffIds.add(person.id);
  person.activity = Activity(
    ActivityType.workPrintShop,
    idString: site.idString,
  );
  return true;
}

void setFrontBusinessMode(Site site, FrontBusinessMode mode) {
  final shop = site.frontBusiness;
  if (shop == null) return;
  shop.mode = mode;
  if (mode == FrontBusinessMode.closed) {
    for (final person in pool.where((p) => _hasShopOrder(site, p))) {
      person.activity = Activity.none();
    }
    shop.staffIds.clear();
  }
}

bool acceptPrintShopRushOrder(Site site) {
  final shop = site.frontBusiness;
  if (shop == null || !shop.rushOrderPending || shop.rushOrderAccepted) {
    return false;
  }
  shop.rushOrderAccepted = true;
  return true;
}

bool declinePrintShopRushOrder(Site site) {
  final shop = site.frontBusiness;
  if (shop == null || !shop.rushOrderPending) return false;
  shop.rushOrderPending = false;
  shop.rushOrderAccepted = false;
  shop.operatingDaysSinceOffer = 0;
  return true;
}

/// Called once after squad departures and ordinary assignments. Shop workers
/// have an exclusive daily order, so travelling or taking another job wins.
void processFrontBusinesses({bool disbanding = false}) {
  for (final site in sites) {
    final shop = site.frontBusiness;
    if (shop == null) continue;
    if (site.controller != SiteController.lcs ||
        !site.businessFront ||
        !site.upgradable ||
        site.discreet) {
      site.removeFrontBusiness();
      continue;
    }
    final dayStamp = '${date.year}-${date.month}-${date.day}';
    if (shop.lastProcessedDay == dayStamp) continue;
    shop.lastProcessedDay = dayStamp;
    shop.lastGross = 0;
    shop.lastCost = 0;
    shop.lastInfluence = 0;
    shop.lastWorkers = 0;
    final staff = pool
        .where((p) => shop.staffIds.contains(p.id) && _hasShopOrder(site, p))
        .take(FrontBusiness.maxStaff)
        .toList();
    shop.staffIds = staff.map((p) => p.id).toList();
    final unavailable = frontBusinessUnavailableReason(site);
    if (disbanding ||
        shop.mode == FrontBusinessMode.closed ||
        unavailable != null) {
      shop.lastReport = disbanding
          ? 'Movement dispersed; shop inactive.'
          : unavailable ?? 'Temporarily closed; no running costs.';
      continue;
    }
    final workers = staff
        .where((p) => frontBusinessWorkerUnavailableReason(site, p) == null)
        .toList();
    if (workers.isEmpty) {
      shop.lastReport = 'No available staff; no sales or running costs.';
      continue;
    }
    final rushOrder = shop.rushOrderPending && shop.rushOrderAccepted;
    if (shop.mode == FrontBusinessMode.commercial || rushOrder) {
      shop.lastWorkers = workers.length;
      shop.lastGross = workers.fold(
        0,
        (total, p) => total + printShopGrossFor(p),
      );
      if (rushOrder) shop.lastGross += FrontBusiness.rushOrderBonus;
      shop.lastCost = workers.length * FrontBusiness.dailyCostPerWorker;
      ledger.addFunds(shop.lastGross, Income.printShop);
      ledger.subtractFunds(shop.lastCost, Expense.printShop);
      for (final person in workers) {
        person.income =
            printShopGrossFor(person) -
            FrontBusiness.dailyCostPerWorker +
            (rushOrder && person == workers.first
                ? FrontBusiness.rushOrderBonus
                : 0);
        person.train(Skill.business, 5);
      }
      shop.lastReport = rushOrder
          ? 'Rush order completed: +\$${FrontBusiness.rushOrderBonus} sales bonus; no movement printing.'
          : 'Commercial work: ${workers.length} staff; net +\$${shop.lastGross - shop.lastCost}.';
    } else {
      final funded = workers
          .take(max(0, ledger.funds) ~/ FrontBusiness.dailyCostPerWorker)
          .toList();
      shop.lastWorkers = funded.length;
      shop.lastCost = funded.length * FrontBusiness.dailyCostPerWorker;
      for (final person in funded) {
        final influence = printShopInfluenceFor(person);
        politics.addBackgroundInfluence(View.freeSpeech, influence);
        shop.lastInfluence += influence;
        person.train(Skill.writing, 5);
      }
      if (shop.lastCost > 0) {
        ledger.subtractFunds(shop.lastCost, Expense.printShop);
      }
      shop.lastReport = funded.isEmpty
          ? 'Not enough funds for movement printing (\$20 per worker).'
          : 'Free Speech printing: ${funded.length}/${workers.length} staff funded; +${shop.lastInfluence} influence.';
    }
    if (shop.lastWorkers > 0) {
      if (rushOrder) {
        shop.rushOrderPending = false;
        shop.rushOrderAccepted = false;
        shop.operatingDaysSinceOffer = 0;
      } else if (!shop.rushOrderPending) {
        shop.operatingDaysSinceOffer++;
        if (shop.operatingDaysSinceOffer >= FrontBusiness.rushOrderInterval) {
          shop.rushOrderPending = true;
          shop.operatingDaysSinceOffer = 0;
        }
      }
    }
  }
  // Dismantled/lost shops must not strand a stale daily order, including saves
  // from a day in which premises were removed before processing.
  for (final person in pool.where(
    (p) => p.activity.type == ActivityType.workPrintShop,
  )) {
    if (person.activity.location?.frontBusiness == null) {
      person.activity = Activity.none();
    }
  }
}
