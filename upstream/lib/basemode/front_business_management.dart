import 'package:flutter/widgets.dart' show StringCharacters;
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/daily/activities/front_business.dart';
import 'package:lcs_new_age/engine/engine.dart';
import 'package:lcs_new_age/gamestate/game_state.dart';
import 'package:lcs_new_age/gamestate/ledger.dart';
import 'package:lcs_new_age/location/compound_upgrades.dart';
import 'package:lcs_new_age/location/front_business.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/utils/colors.dart';
import 'package:lcs_new_age/utils/interface_options.dart';

int printShopSetupCost(Site site) =>
    FrontBusiness.equipmentCost +
    (site.businessFront ? 0 : CompoundUpgrade.businessFront.price);

bool _canSetUp(Site site) =>
    site.controller == SiteController.lcs &&
    site.upgradable &&
    !site.discreet &&
    !site.siege.underSiege &&
    !site.isClosed;

bool setUpPrintShop(Site site) {
  if (!_canSetUp(site) ||
      site.frontBusiness != null ||
      ledger.funds < printShopSetupCost(site)) {
    return false;
  }
  ledger.subtractFunds(printShopSetupCost(site), Expense.compoundUpgrades);
  site.businessFront = true;
  site.frontBusiness = FrontBusiness();
  return true;
}

void _action(String key, String type, Site site, {String? id}) =>
    console.annotateActionEntity(
      key,
      type: type,
      id: id ?? site.idString,
      category: site.idString,
    );

void _reader({String backKey = 'Enter'}) {
  console.screen = 'front-business';
  declareMenuNavigation('bases', backKey: backKey);
}

Future<bool> _confirmSetUp(Site site) async {
  erase();
  mvaddstrc(0, 0, white, 'Equip a working print shop');
  mvaddstr(3, 0, 'Premises: ${site.getName()}');
  mvaddstr(5, 0, 'Print-shop equipment: \$${FrontBusiness.equipmentCost}');
  mvaddstr(
    6,
    0,
    site.businessFront
        ? 'Existing business front retained.'
        : 'Business-front cover: \$${CompoundUpgrade.businessFront.price}',
  );
  mvaddstr(
    8,
    0,
    'Total setup: \$${printShopSetupCost(site)}. Available: \$${ledger.funds}.',
  );
  mvaddstr(
    10,
    0,
    'Running costs: \$20 per active worker/day; maximum 2 staff.',
  );
  mvaddstr(
    11,
    0,
    'Commercial sales cover costs. Movement printing needs cash.',
  );
  addOptionText(
    15,
    0,
    'Y',
    'Y - Pay for setup',
    enabledWhen: ledger.funds >= printShopSetupCost(site) && _canSetUp(site),
  );
  _action('y', 'front-business-confirm', site, id: 'setup');
  addOptionText(17, 0, 'Enter', 'Enter - Cancel');
  _reader();
  return await getKey() == Key.y && setUpPrintShop(site);
}

Future<void> _rename(Site site) async {
  final shop = site.frontBusiness!;
  final inputConsole = console;
  var draft = shop.name;
  inputConsole.textInput = true;
  try {
    while (true) {
      erase();
      inputConsole.textInput = true;
      mvaddstrc(0, 0, white, 'Name the print shop');
      mvaddstr(3, 0, 'Enter saves; Escape cancels. Maximum 40 characters.');
      mvaddstr(6, 0, '$draft▂');
      inputConsole.textInputValue = draft;
      inputConsole.textInputLimit = 40;
      _reader(backKey: 'Escape');
      final key = await getKeyCaseSensitive();
      if (key.codePoint == Key.escape || key.codePoint == Key.menuExit) return;
      if (key.codePoint == Key.enter) {
        if (draft.trim().isNotEmpty) shop.name = draft.trim();
        return;
      }
      if (key.codePoint == Key.backspace) {
        draft = draft.characters.skipLast(1).toString();
      } else if (key.characters.length == 1 &&
          draft.characters.length < 40 &&
          !key.runes.any((r) => r < 32 || (r >= 127 && r <= 159))) {
        draft += key;
      }
    }
  } finally {
    inputConsole.textInput = false;
    inputConsole.textInputValue = '';
    inputConsole.textInputLimit = 0;
  }
}

Future<void> _manageStaff(Site site) async {
  var page = 0;
  while (site.frontBusiness != null) {
    final shop = site.frontBusiness!;
    final currentStaff = pool
        .where(
          (p) =>
              shop.staffIds.contains(p.id) &&
              p.activity.type == ActivityType.workPrintShop &&
              p.activity.idString == site.idString,
        )
        .toList();
    final people = pool
        .where(
          (p) =>
              shop.staffIds.contains(p.id) ||
              frontBusinessWorkerUnavailableReason(site, p) == null,
        )
        .toList();
    final pages = ((people.length + 5) ~/ 6).clamp(1, 100000);
    page = page.clamp(0, pages - 1);
    erase();
    mvaddstrc(0, 0, white, '${shop.name}: staffing');
    mvaddstr(
      2,
      0,
      'Choose up to 2 people. Selecting a worker replaces their daily order.',
    );
    mvaddstr(
      3,
      0,
      'Squad travel and other orders take precedence; absent staff do not earn.',
    );
    mvaddstr(
      4,
      0,
      'Choose a selected worker again to release them to Lay Low.',
    );
    if (people.isEmpty) {
      mvaddstr(7, 0, 'No eligible crew present at this base.');
    }
    final shown = people.skip(page * 6).take(6).toList();
    for (var i = 0; i < shown.length; i++) {
      final person = shown[i];
      final assigned =
          shop.staffIds.contains(person.id) &&
          person.activity.type == ActivityType.workPrintShop &&
          person.activity.idString == site.idString;
      final reason = frontBusinessWorkerUnavailableReason(site, person);
      final key = String.fromCharCode(Key.a + i);
      addOptionText(
        7 + i * 2,
        0,
        key,
        '$key - ${assigned ? "[Staff] " : ""}${person.name}',
        enabledWhen:
            assigned ||
            (reason == null &&
                shop.mode != FrontBusinessMode.closed &&
                frontBusinessUnavailableReason(site) == null &&
                currentStaff.length < FrontBusiness.maxStaff),
      );
      _action(key, 'front-business-staff', site, id: person.id.toString());
      mvaddstr(
        8 + i * 2,
        4,
        reason ??
            '${person.activity.description}; commercial net \$${printShopGrossFor(person) - 20}/day',
      );
    }
    if (pages > 1) addPageButtons(y: 21, x: 0, current: page + 1, max: pages);
    addOptionText(24, 0, 'Enter', 'Enter - Back');
    _reader();
    final key = await getKey();
    if (isBackKey(key)) return;
    if (isPageUp(key)) page = (page - 1 + pages) % pages;
    if (isPageDown(key)) page = (page + 1) % pages;
    if (key >= Key.a && key < Key.a + shown.length) {
      final person = shown[key - Key.a];
      if (currentStaff.contains(person)) {
        unassignPrintShopWorker(site, person);
      } else {
        assignPrintShopWorker(site, person);
      }
    }
  }
}

/// Source-authored management reader, also used by the journal interface.
Future<void> manageFrontBusiness(Site site) async {
  while (true) {
    erase();
    final shop = site.frontBusiness;
    mvaddstrc(0, 0, white, shop?.name ?? 'Working print shop');
    mvaddstr(1, 0, '${site.getName()} | Funds: \$${ledger.funds}');
    if (shop == null) {
      mvaddstr(
        4,
        0,
        'Equip a staffed print shop alongside this base\'s business front.',
      );
      mvaddstr(
        6,
        0,
        'Setup: \$${printShopSetupCost(site)}${site.businessFront ? " (existing front retained)" : " (cover + equipment)"}',
      );
      mvaddstr(
        8,
        0,
        'Commercial work earns income; movement printing promotes Free Speech.',
      );
      mvaddstr(
        10,
        0,
        'At most 2 staff; \$20 running costs per working person/day.',
      );
      mvaddstr(
        11,
        0,
        'Closed, unstaffed and besieged shops have no running costs.',
      );
      if (!_canSetUp(site)) {
        mvaddstr(
          13,
          0,
          'Needs an owned, public, upgradable base outside a siege or closure.',
        );
      }
      addOptionText(
        16,
        0,
        'S',
        'S - Set up print shop (\$${printShopSetupCost(site)})',
        enabledWhen:
            _canSetUp(site) && ledger.funds >= printShopSetupCost(site),
      );
      _action('s', 'front-business-setup', site);
    } else {
      final staff = pool
          .where(
            (p) =>
                shop.staffIds.contains(p.id) &&
                p.activity.type == ActivityType.workPrintShop &&
                p.activity.idString == site.idString,
          )
          .toList();
      mvaddstr(
        3,
        0,
        'Mode: ${shop.mode.label} | Staff slots: ${staff.length}/2',
      );
      final staffNames = staff.map((p) => p.name).join(', ');
      mvaddstr(4, 0, 'Staff: ${staffNames.isEmpty ? "None" : staffNames}');
      mvaddstr(
        5,
        0,
        frontBusinessUnavailableReason(site) ??
            'Present staff work only with their print-shop daily order.',
      );
      mvaddstr(
        7,
        0,
        'Last day: ${shop.lastProcessedDay ?? "None"}; sales \$${shop.lastGross}, costs \$${shop.lastCost}',
      );
      mvaddstr(8, 0, shop.lastReport);
      mvaddstr(
        10,
        0,
        'Commercial: \$45 + 8 x Business + 3 x Writing gross per staff/day.',
      );
      mvaddstr(
        11,
        0,
        'Skills capped at 8 for sales; cost \$20 per staff/day; trains Business.',
      );
      mvaddstr(
        12,
        0,
        'Movement: \$20/staff; +2..8 Free Speech influence/day; trains Writing.',
      );
      if (shop.rushOrderPending) {
        mvaddstr(
          13,
          0,
          'Rush offer: next staffed day +\$100 sales; replaces movement printing.',
        );
        if (shop.rushOrderAccepted) {
          mvaddstr(
            14,
            0,
            'Accepted; waiting for the next staffed, open trading day.',
          );
        }
        addOptionText(
          21,
          0,
          'Y',
          'Y - Accept rush order',
          enabledWhen: !shop.rushOrderAccepted,
        );
        _action('y', 'front-business-offer', site, id: 'accept');
        addOptionText(
          22,
          0,
          'D',
          shop.rushOrderAccepted
              ? 'D - Cancel accepted rush order'
              : 'D - Decline rush order',
        );
        _action('d', 'front-business-offer', site, id: 'decline');
      } else {
        mvaddstr(
          13,
          0,
          'Next rush offer in ${FrontBusiness.rushOrderInterval - shop.operatingDaysSinceOffer} staffed operating days.',
        );
      }
      addOptionText(15, 0, 'C', 'C - Commercial work');
      _action('c', 'front-business-mode', site, id: 'commercial');
      addOptionText(16, 0, 'M', 'M - Movement printing: Free Speech');
      _action('m', 'front-business-mode', site, id: 'movement');
      addOptionText(17, 0, 'Z', 'Z - Temporarily close and release staff');
      _action('z', 'front-business-mode', site, id: 'closed');
      addOptionText(19, 0, 'A', 'A - Manage staff');
      _action('a', 'front-business-staffing', site);
      addOptionText(20, 0, 'N', 'N - Name this business');
      _action('n', 'front-business-name', site);
    }
    addOptionText(24, 0, 'Enter', 'Enter - Back');
    _reader();
    final key = await getKey();
    if (isBackKey(key)) return;
    if (shop == null) {
      if (key == Key.s &&
          _canSetUp(site) &&
          ledger.funds >= printShopSetupCost(site)) {
        await _confirmSetUp(site);
      }
    } else {
      if (key == Key.c) {
        setFrontBusinessMode(site, FrontBusinessMode.commercial);
      }
      if (key == Key.m) setFrontBusinessMode(site, FrontBusinessMode.movement);
      if (key == Key.z) setFrontBusinessMode(site, FrontBusinessMode.closed);
      if (key == Key.a) await _manageStaff(site);
      if (key == Key.n) await _rename(site);
      if (key == Key.y) acceptPrintShopRushOrder(site);
      if (key == Key.d) declinePrintShopRushOrder(site);
    }
  }
}
