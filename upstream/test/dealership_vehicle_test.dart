import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/daily/shopsnstuff.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/vehicles/vehicle.dart';
import 'package:lcs_new_age/vehicles/vehicle_type.dart';

import 'campaign_acceptance_test.dart' show playChoices, roundTripLiveCampaign;
import 'test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(ensureGameDataLoaded);
  setUp(() async {
    game.gameState = decodeSaveContents(
      await File('test/saves/felix_1_0.json').readAsString(),
    ).gameState!;
    applyBugFixes('1.5.6');
    engine.console = Console();
    game.vehiclePool.clear();
  });

  test(
    'source dealership sale clears only sold-car assignments across crew and persists',
    () async {
      final sold = Vehicle(VehicleTypeIds.jeep)..heat = 1;
      final kept = Vehicle(VehicleTypeIds.jeep);
      game.vehiclePool.addAll([sold, kept]);
      final buyer = game.squad.first;
      final other = game.pool.firstWhere((person) => person != buyer);
      buyer
        ..carId = sold.id
        ..isDriver = true
        ..preferredCarId = kept.id
        ..preferredDriver = true;
      other
        ..carId = kept.id
        ..isDriver = true
        ..preferredCarId = sold.id
        ..preferredDriver = true;
      final funds = game.ledger.funds;
      final price = (sold.type.price * .8).round() ~/ 10;
      await playChoices(() => dealership(buyer.site!), (_, actions, prompt) {
        if (prompt == 0) {
          expect(
            actions.singleWhere((action) => action.key == 's').enabled,
            true,
          );
          return 's';
        }
        expect(
          actions.singleWhere((action) => action.key == 's').enabled,
          false,
        );
        return 'Enter';
      });
      expect(game.vehiclePool, [kept]);
      expect(game.ledger.funds, funds + price);
      expect(buyer.carId, isNull);
      expect(buyer.isDriver, false);
      expect(buyer.preferredCarId, kept.id);
      expect(buyer.preferredDriver, true);
      expect(other.carId, kept.id);
      expect(other.isDriver, true);
      expect(other.preferredCarId, isNull);
      expect(other.preferredDriver, false);
      roundTripLiveCampaign();
    },
  );

  test(
    'load repair clears orphan vehicle assignments and preserves valid ones',
    () {
      final kept = Vehicle(VehicleTypeIds.jeep);
      game.vehiclePool.add(kept);
      final first = game.pool.first;
      final second = game.pool[1];
      first
        ..carId = 999999
        ..isDriver = true
        ..preferredCarId = kept.id
        ..preferredDriver = true;
      second
        ..carId = kept.id
        ..isDriver = true
        ..preferredCarId = 999999
        ..preferredDriver = true;
      roundTripLiveCampaign();
      applyBugFixes('1.5.6');
      expect(game.pool.first.carId, isNull);
      expect(game.pool.first.isDriver, false);
      expect(game.pool.first.preferredCarId, kept.id);
      expect(game.pool.first.preferredDriver, true);
      expect(game.pool[1].carId, kept.id);
      expect(game.pool[1].isDriver, true);
      expect(game.pool[1].preferredCarId, isNull);
      expect(game.pool[1].preferredDriver, false);
      roundTripLiveCampaign();
    },
  );
}
