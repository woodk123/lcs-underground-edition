import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Alignment;
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activate_sleepers.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/basemode/base_actions.dart';
import 'package:lcs_new_age/basemode/disbanding.dart';
import 'package:lcs_new_age/basemode/flag.dart';
import 'package:lcs_new_age/basemode/invest_in_location.dart';
import 'package:lcs_new_age/basemode/review_mode.dart';
import 'package:lcs_new_age/common_actions/equipment.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/sort_creatures.dart';
import 'package:lcs_new_age/daily/shopsnstuff.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/items/ammo.dart';
import 'package:lcs_new_age/items/ammo_type.dart';
import 'package:lcs_new_age/items/clothing.dart';
import 'package:lcs_new_age/items/flag.dart';
import 'package:lcs_new_age/items/flag_type.dart';
import 'package:lcs_new_age/items/loot.dart';
import 'package:lcs_new_age/items/loot_type.dart';
import 'package:lcs_new_age/items/weapon.dart';
import 'package:lcs_new_age/location/compound_upgrades.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/siege.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/main.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/monthly/lcs_monthly.dart';
import 'package:lcs_new_age/politics/alignment.dart' show Alignment;
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/sitemode/haul_kidnap.dart';
import 'package:lcs_new_age/sitemode/shop.dart' show shopTypes, ShopUI;
import 'package:lcs_new_age/talk/talk_outside_combat.dart';

import 'test_support.dart';

/// These are rendered source-handler journeys, using explicitly prepared
/// prerequisites. They do not claim that the fixture earned these conditions.
void main() {
  final captureCounts = <String, int>{};
  Future<void> capture(WidgetTester tester) async {
    if (Platform.environment['LCS_CAPTURE_SCREENS'] == null) return;
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('remaining-screen-capture')),
    );
    final name = tester.testDescription.replaceAll(
      RegExp(r'[^A-Za-z0-9_-]+'),
      '-',
    );
    final sequence = captureCounts.update(
      name,
      (value) => value + 1,
      ifAbsent: () => 1,
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final directory = Directory('../reports/remaining-screens-captures');
      await directory.create(recursive: true);
      await File(
        '${directory.path}/$name-$sequence.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  late String fixture;
  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
    final font = FontLoader('JournalSerif')
      ..addFont(rootBundle.load('fonts/journal/LibreBaskerville-Variable.ttf'));
    await font.load();
  });
  setUp(() {
    engine.console = Console();
    game.gameState = decodeSaveContents(fixture).gameState!;
    game.mode = GameMode.base;
    game.activeSquadMember = null;
    journalReadingScale.value = 1;
  });

  Future<void> play(
    WidgetTester tester,
    Size size,
    double scale,
    Future<void> Function() run,
    Future<void> Function() interact,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    journalReadingScale.value = scale;
    var finished = false;
    Object? failure;
    final flow = run().then(
      (_) => finished = true,
      onError: (Object error) {
        failure = error;
        finished = true;
      },
    );
    try {
      await tester.pumpWidget(
        const RepaintBoundary(
          key: ValueKey('remaining-screen-capture'),
          child: MainApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        finished,
        isFalse,
        reason: 'Prepared menu must reach a real reader.',
      );
      expect(engine.console.awaitingInput, isTrue);
      expect(tester.takeException(), isNull);
      await capture(tester);
      await interact();
      await tester.pumpAndSettle();
      expect(
        finished,
        isTrue,
        reason: 'Visible exit must return from the menu.',
      );
      expect(failure, isNull);
      expect(tester.takeException(), isNull);
    } finally {
      // Drain a reader even when a visibility assertion fails.
      for (var i = 0; i < 30 && !finished; i++) {
        if (engine.console.awaitingInput) engine.console.sendInput('Escape');
        await tester.pump(const Duration(milliseconds: 10));
      }
      if (!finished && !engine.console.awaitingInput) {
        await tester.pump(const Duration(seconds: 5));
      }
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      journalReadingScale.value = 1;
      if (finished) await flow;
    }
  }

  Future<void> action(WidgetTester tester, String key) async {
    final source = engine.console.actions.firstWhere(
      (a) => a.key == normalizeConsoleKey(key) && a.enabled,
    );
    final direct = find.byKey(
      ValueKey('direct-action:${source.y}:${source.x}:${source.key}'),
    );
    final cleaned =
        source.intentLabel ??
        source.label.replaceFirst(RegExp(r'^\S+\s+-\s*'), '').trim();
    final personIndex = int.tryParse(key);
    final namedPerson =
        personIndex != null &&
            personIndex > 0 &&
            personIndex <= game.squad.length
        ? find.text(game.squad[personIndex - 1].name, findRichText: true)
        : find.text(cleaned, findRichText: true);
    final finder = direct.evaluate().isNotEmpty ? direct : namedPerson.first;
    expect(
      finder,
      findsOneWidget,
      reason: 'Source control ${source.label} must render.',
    );
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    expect(finder.hitTestable(), findsOneWidget);
    await tester.tap(finder);
    await tester.pumpAndSettle();
    await capture(tester);
  }

  Future<void> keyboardExit(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  }

  for (final (size, scale) in [
    (const Size(1280, 800), 1.0),
    (const Size(1024, 720), 1.5),
  ]) {
    final variant = '${size.width.toInt()}x${size.height.toInt()} / $scale';
    for (final reader in ['equipment', 'reorder', 'kidnap', 'release']) {
      testWidgets('nested $reader choices are visible and cancel at $variant', (
        tester,
      ) async {
        if (reader == 'release') {
          game.squad[1].prisoner = Creature();
          game.squad[1].prisoner!.align = Alignment.conservative;
        }
        Future<void> run() async {
          engine.addOptionText(19, 1, 'x', 'X - Stale command');
          if (reader == 'kidnap' || reader == 'release') {
            game.mode = GameMode.site;
          }
          if (reader == 'equipment') {
            await equip([Clothing('CLOTHING_TOGA')]);
          } else if (reader == 'reorder') {
            await orderparty();
          } else if (reader == 'kidnap') {
            await kidnapattempt();
          } else {
            await releasehostage();
          }
        }

        await play(tester, size, scale, run, () async {
          if (reader == 'equipment') await action(tester, 'a');
          final before = jsonEncode(game.gameState.toJson());
          expect(engine.console.actions.any((a) => a.key == 'x'), isFalse);
          for (final choice in engine.console.actions) {
            final finder = find.byKey(
              ValueKey('direct-action:${choice.y}:${choice.x}:${choice.key}'),
            );
            expect(
              finder.hitTestable(),
              findsOneWidget,
              reason:
                  'Nested $reader choice ${choice.key} must be visible on entry.',
            );
          }
          if (reader == 'reorder') {
            await action(tester, '1');
            for (final choice in engine.console.actions) {
              expect(
                find
                    .byKey(
                      ValueKey(
                        'direct-action:${choice.y}:${choice.x}:${choice.key}',
                      ),
                    )
                    .hitTestable(),
                findsOneWidget,
              );
            }
          }
          await action(tester, 'Enter');
          expect(jsonEncode(game.gameState.toJson()), before);
          if (reader == 'equipment') await action(tester, 'Enter');
        });
      });
    }
    testWidgets(
      'kidnap target rejects invalid keys and cancels without changes at $variant',
      (tester) async {
        game.mode = GameMode.site;
        game.encounter.clear();
        for (final name in ['First target', 'Second target']) {
          game.encounter.add(
            Creature()
              ..name = name
              ..type = game.squad.first.type
              ..align = Alignment.conservative
              ..nonCombatant = true,
          );
        }
        final before = jsonEncode(game.gameState.toJson());
        await play(tester, size, scale, kidnapattempt, () async {
          await action(tester, '2');
          expect(engine.console.screen, 'kidnap_target');
          expect(engine.console.actions.map((a) => a.key), ['a', 'b', 'Enter']);
          engine.console.sendInput('z');
          await tester.pumpAndSettle();
          expect(engine.console.screen, 'kidnap_target');
          expect(jsonEncode(game.gameState.toJson()), before);
          for (final choice in engine.console.actions) {
            expect(
              find
                  .byKey(
                    ValueKey(
                      'direct-action:${choice.y}:${choice.x}:${choice.key}',
                    ),
                  )
                  .hitTestable(),
              findsOneWidget,
            );
          }
          await action(tester, 'Enter');
          expect(jsonEncode(game.gameState.toJson()), before);
        });
        await play(tester, size, scale, kidnapattempt, () async {
          await action(tester, '2');
          await keyboardExit(tester);
          expect(jsonEncode(game.gameState.toJson()), before);
        });
      },
    );

    testWidgets(
      'release choices disable empty hands and free only selected hostage at $variant',
      (tester) async {
        game.mode = GameMode.site;
        game.siteAlarm =
            true; // Isolate the release from the separate alarm response.
        final first = Creature()..align = Alignment.conservative;
        final second = Creature()..align = Alignment.conservative;
        game.squad[0].prisoner = first;
        game.squad[1].prisoner = second;
        for (final person in game.squad.skip(2)) {
          person.prisoner = null;
        }
        await play(tester, size, scale, releasehostage, () async {
          expect(
            engine.console.actions.singleWhere((a) => a.key == '3').enabled,
            isFalse,
          );
          await action(tester, '2');
          expect(game.squad[0].prisoner, same(first));
          expect(game.squad[1].prisoner, isNull);
          expect(game.encounter, contains(second));
          expect(game.encounter, isNot(contains(first)));
        });
      },
    );
    testWidgets('safehouse investment buys rations and exits at $variant', (
      tester,
    ) async {
      final site = game.sites.firstWhere((s) => s.upgradable);
      game.ledger.forceSetFunds(100000);
      final rations = site.compound.rations;
      await play(tester, size, scale, () => investInLocation(site), () async {
        await action(tester, 'r');
        expect(site.compound.rations, rations + 20);
        expect(game.ledger.funds, 99850);
        await action(tester, 'Enter');
      });
    });

    testWidgets('flag selector cancels without purchasing at $variant', (
      tester,
    ) async {
      final site = game.activeSquad!.site!;
      game.ledger.forceSetFunds(100);
      final flag = site.flyingFlagId;
      await play(tester, size, scale, () => selectAndFlyFlag(site), () async {
        expect(engine.console.actions.any((a) => a.enabled), isTrue);
        await action(tester, 'Escape');
      });
      expect(site.flyingFlagId, flag);
      expect(game.ledger.funds, 100);
    });

    for (final owned in [false, true]) {
      testWidgets(
        'flag ${owned ? 'owned' : 'purchase'} confirmation at $variant',
        (tester) async {
          final site = game.activeSquad!.site!;
          site.hasFlag = false;
          site.flyingFlagId = '';
          site.loot.clear();
          if (owned) site.loot.add(Flag.fromType(flagTypes.values.first));
          game.ledger.forceSetFunds(100);
          await play(
            tester,
            size,
            scale,
            () => selectAndFlyFlag(site, ownedOnly: owned),
            () async {
              final choice = engine.console.actions.firstWhere(
                (a) => a.enabled && RegExp(r'^[a-z]$').hasMatch(a.key),
              );
              await action(tester, choice.key);
              await action(tester, 'Enter');
            },
          );
          expect(site.hasFlag, isTrue);
          expect(game.ledger.funds, owned ? 100 : 80);
          if (owned) expect(site.loot.whereType<Flag>(), isEmpty);
        },
      );
    }

    for (final affordable in [false, true]) {
      testWidgets(
        'safehouse camera ${affordable ? 'purchase' : 'unaffordable'} at $variant',
        (tester) async {
          final site = game.sites.firstWhere((s) => s.upgradable);
          site.compound.cameras = false;
          game.ledger.forceSetFunds(affordable ? 100000 : 0);
          await play(
            tester,
            size,
            scale,
            () => investInLocation(site),
            () async {
              final camera = engine.console.actions.singleWhere(
                (a) => a.key == 'c',
              );
              expect(camera.enabled, affordable);
              if (affordable) await action(tester, 'c');
              await action(tester, 'Enter');
            },
          );
          expect(site.compound.cameras, affordable);
          expect(
            game.ledger.funds,
            affordable ? 100000 - CompoundUpgrade.cameras.price : 0,
          );
        },
      );
    }

    testWidgets('promotion roster exits without promotions at $variant', (
      tester,
    ) async {
      final contacts = game.pool.map((p) => p.hireId).toList();
      await play(
        tester,
        size,
        scale,
        promoteliberals,
        () => keyboardExit(tester),
      );
      expect(game.pool.map((p) => p.hireId), contacts);
    });

    testWidgets('disbanded status recreates movement at $variant', (
      tester,
    ) async {
      oldForceMonth = -1;
      game.gameState.disbandTime = game.year;
      for (final person in game.pool) {
        person.juice = 1000;
      }
      bool? continueDisbanding;
      await play(tester, size, scale, () async {
        continueDisbanding = await showDisbandingScreen();
      }, () => action(tester, 'r'));
      expect(continueDisbanding, isFalse);
    });

    for (final category in ReviewMode.values) {
      testWidgets('populated ${category.name} review exits at $variant', (
        tester,
      ) async {
        final person = game.pool.first;
        switch (category) {
          case ReviewMode.all:
          case ReviewMode.liberals:
            break;
          case ReviewMode.hostages:
            person.align = Alignment.conservative;
          case ReviewMode.clinic:
            person.location = game.sites.firstWhere(
              (s) => s.type == SiteType.universityHospital,
            );
          case ReviewMode.justice:
            person.location = game.sites.firstWhere(
              (s) => s.type == SiteType.prison,
            );
            person.sentence = 3;
          case ReviewMode.sleepers:
            person.sleeperAgent = true;
          case ReviewMode.dead:
            person.die();
          case ReviewMode.away:
            person.vacationDaysLeft = 3;
        }
        await play(tester, size, scale, () => reviewMode(category), () async {
          final tools = find.byKey(const ValueKey('personnel-tools'));
          final journalDirectory =
              category == ReviewMode.all && tools.evaluate().isNotEmpty;
          if (journalDirectory) {
            await tester.ensureVisible(tools);
            await tester.pumpAndSettle();
            await tester.tap(tools);
            await tester.pumpAndSettle();
          }
          await action(tester, 'a');
          await keyboardExit(tester);
          if (journalDirectory) {
            // This isolated source reader has no outer HQ loop. Exit it
            // directly, without asking the journal controller to await HQ.
            await tester.tap(find.byTooltip('Switch readable / classic view'));
            await tester.pumpAndSettle();
          }
          await keyboardExit(tester);
        });
      });
    }

    for (final bulk in [false, true]) {
      testWidgets(
        'sleeper ${bulk ? 'bulk' : 'roster'} menu exits at $variant',
        (tester) async {
          final person = game.pool.first;
          person.sleeperAgent = true;
          person.workLocation = person.location;
          await play(
            tester,
            size,
            scale,
            bulk ? activateSleepersBulk : activateSleepers,
            () async {
              if (bulk) {
                await action(tester, '2');
                await action(tester, 'a');
                expect(person.activity.type, ActivityType.sleeperLiberal);
                await keyboardExit(tester);
              } else {
                await action(tester, 'a');
                await action(tester, 'Enter');
                await action(tester, 'Enter');
              }
            },
          );
        },
      );
    }

    for (final shop in [
      'ARMSDEALER',
      'PAWNSHOP',
      'DEPARTMENT_STORE',
      'OUBLIETTE',
    ]) {
      testWidgets('$shop entrance and exit at $variant', (tester) async {
        final site = game.activeSquad!.site!;
        site.name =
            'A very long department store name for location heading checks';
        game.activeSquad!.activity = Activity(
          ActivityType.visit,
          idString: site.idString,
        );
        await play(tester, size, scale, () => shopVisit(site, shop), () async {
          expect(find.text(site.getName(includeCity: true)), findsOneWidget);
          await keyboardExit(tester);
        });
      });
    }

    testWidgets('shop buyer cancel, revisit and purchase target at $variant', (
      tester,
    ) async {
      final site = game.activeSquad!.site!;
      game.ledger.forceSetFunds(10000);
      final first = game.squad[0];
      final second = game.squad[1];
      final firstClothes = first.equippedClothing;
      await play(
        tester,
        size,
        scale,
        () => shopVisit(site, 'OUBLIETTE'),
        () async {
          final before = jsonEncode(game.gameState.toJson());
          await action(tester, 'b');
          expect(engine.console.screen, 'shop_buyer');
          expect(engine.console.actions.map((a) => a.key).toSet(), {
            for (var i = 0; i < game.squad.length; i++) '${i + 1}',
            'Enter',
          });
          expect(engine.console.actions.any((a) => a.key == 'a'), isFalse);
          for (final choice in engine.console.actions) {
            final finder = find.byKey(
              ValueKey('direct-action:${choice.y}:${choice.x}:${choice.key}'),
            );
            expect(
              finder.hitTestable(),
              findsOneWidget,
              reason:
                  'Every buyer choice and cancellation must be visible on entry.',
            );
          }
          await capture(tester);
          await action(tester, 'Enter');
          expect(jsonEncode(game.gameState.toJson()), before);
          await action(tester, 'b');
          await keyboardExit(tester);
          expect(jsonEncode(game.gameState.toJson()), before);
          await action(tester, 'b');
          await action(tester, '2');
          expect(jsonEncode(game.gameState.toJson()), before);
          await action(tester, 'c'); // Halloween costumes.
          await action(tester, 'a'); // Purchase the actual source Toga option.
          expect(second.clothing.type.idName, 'CLOTHING_TOGA');
          expect(first.equippedClothing, same(firstClothes));
          expect(game.ledger.funds, 9975);
          await action(tester, 'Enter');
          await action(tester, 'b');
          await action(tester, 'Enter'); // Cancelling keeps the second buyer.
          await action(tester, 'c');
          await action(
            tester,
            'b',
          ); // Judicial robes must go to the same person.
          expect(second.clothing.type.idName, 'CLOTHING_BLACKROBE');
          expect(first.equippedClothing, same(firstClothes));
          expect(game.ledger.funds, 9925);
          await action(tester, 'Enter');
          await action(tester, 'Enter');
        },
      );
    });

    testWidgets('dealership entrance and leave at $variant', (tester) async {
      final site = game.activeSquad!.site!;
      await play(
        tester,
        size,
        scale,
        () => dealership(site),
        () => action(tester, 'Enter'),
      );
    });

    testWidgets(
      'dealership purchase belongs to selected buyer and sells at $variant',
      (tester) async {
        final site = game.activeSquad!.site!;
        game.vehiclePool.clear();
        for (final person in game.squad) {
          person.preferredCarId = null;
        }
        game.ledger.forceSetFunds(1000000);
        await play(tester, size, scale, () => dealership(site), () async {
          await action(tester, 'b');
          await action(tester, '2');
          await action(tester, 'g');
          await action(tester, 'a');
          await action(tester, 'a');
          expect(game.vehiclePool, hasLength(1));
          final car = game.vehiclePool.single;
          expect(game.squad[1].preferredCarId, car.id);
          expect(game.squad[0].preferredCarId, isNull);
          final afterPurchase = game.ledger.funds;
          expect(afterPurchase, lessThan(1000000));
          await action(tester, 'Enter');
        });
        // A purchase reserves a car. Prepare the distinct driven-car sale
        // state before starting another original dealership visit.
        final car = game.vehiclePool.single;
        game.squad.first.carId = car.id;
        final afterPurchase = game.ledger.funds;
        await play(tester, size, scale, () => dealership(site), () async {
          final sale = engine.console.actions.singleWhere((a) => a.key == 's');
          final saleButton = find.byKey(
            ValueKey('direct-action:${sale.y}:${sale.x}:${sale.key}'),
          );
          expect(
            saleButton.hitTestable(),
            findsOneWidget,
            reason:
                'Sell must be visible before expanding or scrolling the roster.',
          );
          await action(tester, 's');
          expect(game.vehiclePool, isEmpty);
          expect(game.ledger.funds, greaterThan(afterPurchase));
          await action(tester, 'Enter');
        });
      },
    );

    for (final key in ['w', 'c', 'a']) {
      testWidgets('bulk pawn $key confirms and cancels at $variant', (
        tester,
      ) async {
        final base = game.squad.first.base!;
        final goods = switch (key) {
          'w' => Weapon('WEAPON_BASEBALLBAT'),
          'c' => Clothing('CLOTHING_BLACKDRESS'),
          _ => Ammo(
            ammoTypes.values.firstWhere((type) => type.fenceValue > 0).idName,
            stackSize: 200,
          ),
        };
        base.loot
          ..clear()
          ..add(goods);
        game.ledger.forceSetFunds(100);
        final proceeds = goods.stackFenceValue.round();
        await play(
          tester,
          size,
          scale,
          () => shopTypes['PAWNSHOP']!.sellLoot(game.activeSquad!),
          () async {
            final before = jsonEncode(game.gameState.toJson());
            await action(tester, key);
            expect(engine.console.actions.map((a) => a.key).toSet(), {
              'y',
              'n',
            });
            expect(jsonEncode(game.gameState.toJson()), before);
            await capture(tester);
            await action(tester, 'n');
            expect(jsonEncode(game.gameState.toJson()), before);
            // Revisit and cancel with the original Escape keyboard equivalent.
            await action(tester, key);
            await keyboardExit(tester);
            expect(jsonEncode(game.gameState.toJson()), before);
            await action(tester, key);
            await action(tester, 'y');
            expect(engine.console.eventTitle, 'Shopping report');
            expect(
              engine.console.eventMessage,
              contains('Sale proceeds: \$$proceeds'),
            );
            expect(
              engine.console.eventMessage,
              contains('Sold: ${goods.type.name} ×${goods.stackSize}'),
            );
            expect(
              engine.console.eventMessage,
              contains('medical expenses are recorded separately'),
            );
            await tester.tap(find.text('Continue'));
            await tester.pumpAndSettle();
            expect(base.loot, isEmpty);
            expect(game.ledger.funds, 100 + proceeds);
            await action(tester, 'Enter');
          },
        );
      });
    }

    testWidgets('selective pawn quantity and sale at $variant', (tester) async {
      final base = game.squad.first.base!;
      base.loot.clear();
      final goods = Loot(LootTypeIds.cheapJewelry, stackSize: 3);
      base.loot.add(goods);
      final unsellable = Clothing(game.squad.first.clothing.type.idName)
        ..bloody = true;
      expect(unsellable.isForSale, isFalse);
      base.loot.add(unsellable);
      game.ledger.forceSetFunds(100);
      await play(
        tester,
        size,
        scale,
        () => shopTypes['PAWNSHOP']!.sellLoot(game.activeSquad!),
        () async {
          await action(tester, 'f');
          final forbidden = engine.console.actions.firstWhere(
            (a) =>
                a.label.contains(stripConsoleColors(unsellable.equipTitle())),
          );
          expect(forbidden.enabled, isFalse);
          final sale = engine.console.actions.firstWhere(
            (a) => a.label.contains(goods.equipTitle()),
          );
          await action(tester, sale.key);
          expect(engine.console.textInput, isTrue);
          await tester.enterText(find.byType(TextField), '2');
          await tester.tap(find.text('Confirm text'));
          for (var i = 0; i < 10; i++) {
            await tester.pump(const Duration(milliseconds: 40));
          }
          await tester.pumpAndSettle();
          await action(tester, 'Enter');
          expect(engine.console.eventTitle, 'Shopping report');
          await tester.tap(find.text('Continue'));
          await tester.pumpAndSettle();
          expect(goods.stackSize, 1);
          expect(base.loot, contains(unsellable));
          expect(game.ledger.funds, 100 + (2 * goods.fenceValue).round());
          await action(tester, 'Enter');
        },
      );
    });

    testWidgets('empty current-data mask selector cancels at $variant', (
      tester,
    ) async {
      final buyer = game.squad.first;
      final original = buyer.equippedClothing;
      game.ledger.forceSetFunds(100);
      await play(
        tester,
        size,
        scale,
        () => shopTypes['DEPARTMENT_STORE']!.maskselect(buyer),
        () async {
          await action(tester, 'Escape');
        },
      );
      expect(game.ledger.funds, 100);
      expect(buyer.equippedClothing, same(original));
    });
    testWidgets('shop ammunition purchase debits its box price at $variant', (
      tester,
    ) async {
      final ammunition = shopTypes['PAWNSHOP']!.departments.firstWhere(
        (s) => s.ui == ShopUI.ammo,
      );
      final item = ammunition.items.firstWhere(
        (item) => item.display() && item.isAvailable(),
      );
      game.ledger.forceSetFunds(100000);
      await play(
        tester,
        size,
        scale,
        () => ammunition.enter(game.activeSquad!),
        () async {
          final firstProduct = engine.console.actions.firstWhere(
            (a) => a.key == 'a',
          );
          expect(firstProduct.label, contains(item.description));
          await action(tester, 'a');
          expect(game.ledger.funds, 100000 - item.price(false));
          await keyboardExit(tester);
        },
      );
    });

    for (final kind in [ShopUI.weapons, ShopUI.ammo]) {
      testWidgets(
        'unaffordable ${kind.name} controls stay disabled at $variant',
        (tester) async {
          final department = shopTypes['PAWNSHOP']!.departments.firstWhere(
            (s) => s.ui == kind,
          );
          game.ledger.forceSetFunds(0);
          await play(
            tester,
            size,
            scale,
            () => department.enter(game.activeSquad!),
            () async {
              final product = engine.console.actions.firstWhere(
                (a) => a.key == 'a',
              );
              expect(product.enabled, isFalse);
              final button = find.byKey(
                ValueKey(
                  'direct-action:${product.y}:${product.x}:${product.key}',
                ),
              );
              expect(button, findsOneWidget);
              await tester.ensureVisible(button);
              await tester.tap(button);
              await tester.pumpAndSettle();
              expect(game.ledger.funds, 0);
              expect(engine.console.awaitingInput, isTrue);
              await keyboardExit(tester);
            },
          );
        },
      );
    }
    for (final page in [0, 1]) {
      testWidgets(
        'weapon page ${page + 1} purchase matches displayed choice at $variant',
        (tester) async {
          final department = shopTypes['PAWNSHOP']!.departments.firstWhere(
            (s) => s.ui == ShopUI.weapons,
          );
          final products = department.items
              .where((item) => item.display())
              .toList();
          // Weapon pages contain six products, each occupying two source rows.
          final chosen = products[page * 6 + 1];
          final buyer = game.squad.first;
          game.ledger.forceSetFunds(100000);
          await play(
            tester,
            size,
            scale,
            () => department.enter(game.activeSquad!),
            () async {
              if (page != 0) await action(tester, ']');
              final source = engine.console.actions.singleWhere(
                (a) => a.key == 'b',
              );
              expect(source.label, contains(chosen.description));
              await action(tester, 'b');
              expect(buyer.weapon.type.idName, chosen.itemId);
              expect(game.ledger.funds, 100000 - chosen.price(false));
              await keyboardExit(tester);
            },
          );
        },
      );
    }

    testWidgets('clothing purchase matches displayed choice at $variant', (
      tester,
    ) async {
      final department = shopTypes['OUBLIETTE']!.departments.firstWhere(
        (s) => s.ui == ShopUI.clothes,
      );
      final chosen = department.items
          .where((item) => item.display())
          .elementAt(1);
      final buyer = game.squad.first;
      game.ledger.forceSetFunds(100000);
      await play(
        tester,
        size,
        scale,
        () => department.enter(game.activeSquad!),
        () async {
          final source = engine.console.actions.singleWhere(
            (a) => a.key == 'b',
          );
          expect(source.label, contains(chosen.description));
          await action(tester, 'b');
          expect(buyer.clothing.type.idName, chosen.itemId);
          expect(game.ledger.funds, 100000 - chosen.price(false));
          await keyboardExit(tester);
        },
      );
    });
    for (final screen in SortingScreens.values) {
      testWidgets('${screen.name} sorting choice at $variant', (tester) async {
        await play(
          tester,
          size,
          scale,
          () => sortingPrompt(screen),
          () => action(tester, 'b'),
        );
        expect(game.activeSortingChoice[screen], CreatureSortMethod.name);
      });
    }

    testWidgets(
      'squadless base assignment applies selected destination at $variant',
      (tester) async {
        final person = game.pool.first;
        person.squad = null;
        final destination = game.sites.firstWhere(
          (site) => site.type == SiteType.warehouse,
        );
        destination.controller = SiteController.lcs;
        destination.siege.activeSiegeType = SiegeType.none;
        await play(tester, size, scale, assignNewBasesToTheSquadless, () async {
          final target = engine.console.actions.firstWhere(
            (a) =>
                a.label.contains(
                  destination.getName(short: true, includeCity: true),
                ) &&
                int.tryParse(a.key) != null,
          );
          await action(tester, target.key);
          await action(tester, 'a');
          expect(person.base, destination);
          await keyboardExit(tester);
        });
      },
    );

    for (final publish in [false, true]) {
      testWidgets(
        'special edition ${publish ? 'selects secret' : 'cancels'} at $variant',
        (tester) async {
          final site = game.activeSquad!.site!;
          site.controller = SiteController.lcs;
          for (final owned in game.sites.where(
            (s) => s.controller == SiteController.lcs,
          )) {
            owned.loot.clear();
          }
          final document = Loot(LootTypeIds.policeRecords, stackSize: 2);
          site.loot.add(document);
          LootType? chosen;
          await play(tester, size, scale, () async {
            chosen = await chooseSpecialEdition();
          }, () => action(tester, publish ? 'a' : 'Enter'));
          expect(chosen?.idName, publish ? document.typeName : null);
          expect(document.stackSize, publish ? 1 : 2);
        },
      );
    }

    Future<void> conversationContinue(WidgetTester tester) async {
      final next = find.text('Continue');
      expect(next, findsOneWidget);
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pumpAndSettle();
      await capture(tester);
    }

    testWidgets('bank teller decline preserves campaign at $variant', (
      tester,
    ) async {
      final actor = game.squad.first;
      final teller = game.pool.last;
      final funds = game.ledger.funds;
      await play(tester, size, scale, () async {
        await talkToBankTeller(actor, teller);
      }, () => action(tester, 'c'));
      expect(game.ledger.funds, funds);
    });

    testWidgets('rental offer can be declined at $variant', (tester) async {
      final actor = game.squad.first;
      final landlord = game.pool.last;
      game.activeSite = game.sites.firstWhere(
        (s) => s.type == SiteType.apartment,
      );
      final owner = game.activeSite!.controller;
      final funds = game.ledger.funds;
      await play(
        tester,
        size,
        scale,
        () async {
          await heyIWantToRentARoom(actor, landlord);
        },
        () async {
          await conversationContinue(tester);
          await conversationContinue(tester);
          await action(tester, 'b');
          await conversationContinue(tester);
          await conversationContinue(tester);
        },
      );
      expect(game.activeSite!.controller, owner);
      expect(game.ledger.funds, funds);
    });

    testWidgets(
      'conversation opens gun shop and leaves without buying at $variant',
      (tester) async {
        final actor = game.squad.first;
        final dealer = game.pool.last;
        game.siteAlarm = false;
        final funds = game.ledger.funds;
        await play(
          tester,
          size,
          scale,
          () async {
            await heyINeedAGun(actor, dealer);
          },
          () async {
            await conversationContinue(tester);
            await conversationContinue(tester);
            await action(tester, 'Enter');
          },
        );
        expect(game.ledger.funds, funds);
      },
    );

    testWidgets(
      'rental acceptance charges deposit then cancellation relocates possessions at $variant',
      (tester) async {
        final actor = game.squad.first;
        final landlord = game.pool.last;
        final apartment = game.sites.firstWhere(
          (s) => s.type == SiteType.apartment,
        );
        final fallback = game.sites.firstWhere(
          (s) =>
              s.city == apartment.city && s.type == SiteType.homelessEncampment,
        );
        game.activeSite = apartment;
        game.ledger.forceSetFunds(10000);
        apartment.loot.clear();
        final possession = Loot(LootTypeIds.cheapJewelry);
        apartment.loot.add(possession);
        await play(
          tester,
          size,
          scale,
          () async {
            await heyIWantToRentARoom(actor, landlord);
          },
          () async {
            await conversationContinue(tester);
            await conversationContinue(tester);
            await action(tester, 'a');
            await conversationContinue(tester);
            await conversationContinue(tester);
          },
        );
        expect(apartment.controller, SiteController.lcs);
        expect(game.ledger.funds, 9350);
        expect(apartment.rent, 650);
        expect(actor.base, apartment);
        for (final person in game.squad) {
          person.location = apartment;
        }
        await play(
          tester,
          size,
          scale,
          () async {
            await heyIWantToCancelMyRoom(actor, landlord);
          },
          () async {
            await conversationContinue(tester);
            await conversationContinue(tester);
            await conversationContinue(tester);
          },
        );
        expect(apartment.controller, SiteController.unaligned);
        expect(apartment.loot, isEmpty);
        expect(fallback.loot, contains(possession));
        expect(actor.base, fallback);
        expect(actor.location, fallback);
        expect(game.ledger.funds, 9350);
      },
    );
    testWidgets(
      'base destination pages wrap and assign last-page target at $variant',
      (tester) async {
        final person = game.pool.first;
        final city = person.base!.city;
        person.squad = null;
        final destinations = game.sites
            .where((s) => s.city == city)
            .take(11)
            .toList();
        expect(destinations, hasLength(11));
        for (final site in game.sites) {
          site.controller = destinations.contains(site)
              ? SiteController.lcs
              : SiteController.unaligned;
          site.siege.activeSiegeType = SiegeType.none;
        }
        person.base = destinations.first;
        person.location = destinations.first;
        await play(tester, size, scale, assignNewBasesToTheSquadless, () async {
          final first = engine.console.actions
              .singleWhere((a) => a.key == '1')
              .label;
          await action(tester, '0');
          expect(
            engine.console.actions.singleWhere((a) => a.key == '1').label,
            isNot(first),
          );
          await action(tester, '2');
          await action(tester, 'a');
          expect(person.base, destinations[10]);
          await action(tester, '0');
          expect(
            engine.console.actions.singleWhere((a) => a.key == '1').label,
            first,
          );
          await action(tester, 'Enter');
        });
      },
    );

    for (final burn in [false, true]) {
      testWidgets(
        'flag ${burn ? 'burn' : 'wave'} source animation remains visible at $variant',
        (tester) async {
          final site = game.activeSquad!.site!;
          final flag = flagTypes.values.firstWhere((f) => f.burns == burn);
          site.hasFlag = true;
          site.flyingFlagId = flag.idName;
          site.siege.activeSiegeType = SiegeType.police;
          site.siege.resetFlagProtests();
          final burned = game.stats.flagsBurned;
          engine.console.screen = 'headquarters';
          engine.addOptionText(24, 0, 'f', 'F - Protest with the flag');
          await play(
            tester,
            size,
            scale,
            () async {
              await engine.getKey();
              if (burn) {
                await burnFlag(site);
              } else {
                await waveFlag(site);
              }
            },
            () async {
              // Do not settle the timed animation before checking its live frame.
              expect(engine.console.sendInput('f'), isTrue);
              await tester.pump(const Duration(milliseconds: 80));
              await capture(tester);
              expect(
                find.byType(burn ? FlagBurningAnimation : FlagGleamAnimation),
                findsOneWidget,
              );
              await tester.pump(const Duration(seconds: 5));
            },
          );
          expect(site.hasFlag, !burn);
          expect(game.stats.flagsBurned, burned + (burn ? 1 : 0));
          expect(
            burn ? site.siege.flagBurnUsed : site.siege.flagWaveUsed,
            isTrue,
          );
        },
      );
    }
  }
}

Future<void> shopVisit(Site site, String kind) => shop(site, kind);
