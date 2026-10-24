import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/basemode/front_business_management.dart';
import 'package:lcs_new_age/basemode/invest_in_location.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/creature_type.dart';
import 'package:lcs_new_age/daily/activities/front_business.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/location/front_business.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/siege.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

String _frame(Console console) => console.buffer
    .map((row) => row.map((cell) => cell.glyph).join())
    .join('\n');

Future<void> _drive(
  Future<void> Function() reader,
  String Function(Console console) choose,
) async {
  final console = engine.console;
  void respond() {
    if (!console.awaitingInput || console.lastKey != null) return;
    expect(console.sendInput(choose(console)), isTrue);
  }

  console.revision.addListener(respond);
  try {
    await reader().timeout(const Duration(seconds: 5));
  } finally {
    console.revision.removeListener(respond);
  }
}

void main() {
  late String fixture;
  late Site site;
  late List<Creature> crew;

  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
  });
  setUp(() {
    final save = SaveFile.fromJson(jsonDecode(fixture) as Map<String, dynamic>);
    game.gameState = game.GameState.fromJson(save.saveData);
    engine.console = Console();
    site = game.sites.firstWhere((s) => s.type == SiteType.warehouse);
    site.controller = SiteController.lcs;
    site.siege = Siege();
    site.closed = 0;
    site.businessFront = true;
    site.frontBusiness = FrontBusiness();
    game.pool.clear();
    game.squads.clear();
    crew = List.generate(
      3,
      (i) =>
          Creature.fromId(
              CreatureTypeIds.officeWorker,
              align: Alignment.liberal,
            )
            ..name = 'Printer $i'
            ..base = site
            ..location = site,
    );
    game.pool.addAll(crew);
    game.ledger.forceSetFunds(10000);
  });

  test('investment exposes shop navigation with a source entity', () async {
    var step = 0;
    await _drive(() => investInLocation(site), (console) {
      if (step++ == 0) {
        expect(console.screen, 'base-investment');
        final action = console.actions.singleWhere(
          (a) => a.entityType == 'front-business-open',
        );
        expect(action.entityId, site.idString);
        return action.key;
      }
      if (step == 2) expect(console.screen, 'front-business');
      return 'Enter';
    });
    expect(step, 3);
  });

  test(
    'opening and cancelling setup changes neither campaign state nor RNG',
    () async {
      site.businessFront = false;
      final before = jsonEncode(game.gameState.toJson());
      reseedRNG(seed: 87531);
      final expectedRoll = lcsRandom(1000000);
      reseedRNG(seed: 87531);
      var step = 0;
      await _drive(() => manageFrontBusiness(site), (console) {
        expect(console.screen, 'front-business');
        expect(console.navigation!.section, 'bases');
        if (step++ == 0) return 's';
        if (step == 2) {
          expect(_frame(console), contains('Total setup: \$4500'));
          expect(
            console.actions.singleWhere((a) => a.key == 'y').entityType,
            'front-business-confirm',
          );
        }
        return 'Enter';
      });
      expect(step, 3);
      expect(jsonEncode(game.gameState.toJson()), before);
      expect(lcsRandom(1000000), expectedRoll);
    },
  );

  test(
    'confirmed setup charges exactly once and returns to management',
    () async {
      site.frontBusiness = null;
      final funds = game.ledger.funds;
      var step = 0;
      await _drive(() => manageFrontBusiness(site), (console) {
        switch (step++) {
          case 0:
            return 's';
          case 1:
            return 'y';
          default:
            expect(
              console.actions.any((a) => a.entityType == 'front-business-mode'),
              isTrue,
            );
            return 'Enter';
        }
      });
      expect(site.frontBusiness, isNotNull);
      expect(game.ledger.funds, funds - 1500);
    },
  );

  test('editing a name then Escape preserves name and campaign RNG', () async {
    final original = site.frontBusiness!.name;
    final before = jsonEncode(game.gameState.toJson());
    reseedRNG(seed: 43179);
    final expectedRoll = lcsRandom(1000000);
    reseedRNG(seed: 43179);
    var step = 0;
    await _drive(() => manageFrontBusiness(site), (console) {
      switch (step++) {
        case 0:
          return 'n';
        case 1:
          expect(console.textInput, isTrue);
          return 'Q';
        case 2:
          expect(console.textInputValue, '${original}Q');
          return 'Escape';
        default:
          return 'Enter';
      }
    });
    expect(site.frontBusiness!.name, original);
    expect(jsonEncode(game.gameState.toJson()), before);
    expect(lcsRandom(1000000), expectedRoll);
  });

  test(
    'staff can be replaced immediately after a different ordinary order',
    () async {
      assignPrintShopWorker(site, crew[0]);
      assignPrintShopWorker(site, crew[1]);
      crew[0].activity = Activity(ActivityType.donations);
      var step = 0;
      await _drive(() => manageFrontBusiness(site), (console) {
        switch (step++) {
          case 0:
            return 'a';
          case 1:
            final action = console.actions.singleWhere(
              (a) =>
                  a.entityType == 'front-business-staff' &&
                  a.entityId == crew[2].id.toString(),
            );
            expect(action.enabled, isTrue);
            expect(action.entityCategory, site.idString);
            return action.key;
          default:
            return 'Enter';
        }
      });
      expect(site.frontBusiness!.staffIds, [crew[1].id, crew[2].id]);
      expect(crew[0].activity.type, ActivityType.donations);
      expect(crew[2].activity.type, ActivityType.workPrintShop);
    },
  );

  test(
    'mode change, close and revisit retain settings and release workers',
    () async {
      assignPrintShopWorker(site, crew.first);
      var step = 0;
      await _drive(
        () => manageFrontBusiness(site),
        (console) => switch (step++) {
          0 => 'm',
          1 => 'z',
          _ => 'Enter',
        },
      );
      expect(site.frontBusiness!.mode, FrontBusinessMode.closed);
      expect(crew.first.activity.type, ActivityType.none);
      await _drive(() => manageFrontBusiness(site), (console) {
        expect(_frame(console), contains('Temporarily closed'));
        expect(_frame(console), contains('Staff slots: 0/2'));
        return 'Enter';
      });
    },
  );

  test(
    'rush offer inspection, acceptance and cancellation use authored actions',
    () async {
      site.frontBusiness!.rushOrderPending = true;
      final funds = game.ledger.funds;
      final before = jsonEncode(game.gameState.toJson());
      await _drive(() => manageFrontBusiness(site), (console) {
        expect(
          _frame(console),
          contains('+\$100 sales; replaces movement printing'),
        );
        return 'Enter';
      });
      expect(jsonEncode(game.gameState.toJson()), before);
      var step = 0;
      await _drive(() => manageFrontBusiness(site), (console) {
        if (step++ == 0) {
          final offer = console.actions.singleWhere(
            (a) =>
                a.entityType == 'front-business-offer' &&
                a.entityId == 'accept',
          );
          return offer.key;
        }
        expect(_frame(console), contains('Accepted; waiting'));
        return 'Enter';
      });
      expect(site.frontBusiness!.rushOrderAccepted, isTrue);
      expect(game.ledger.funds, funds);
      step = 0;
      await _drive(() => manageFrontBusiness(site), (console) {
        if (step++ == 0) {
          final decline = console.actions.singleWhere(
            (a) =>
                a.entityType == 'front-business-offer' &&
                a.entityId == 'decline',
          );
          expect(decline.label, contains('Cancel accepted'));
          return decline.key;
        }
        return 'Enter';
      });
      expect(site.frontBusiness!.rushOrderPending, isFalse);
      expect(game.ledger.funds, funds);
    },
  );
}
