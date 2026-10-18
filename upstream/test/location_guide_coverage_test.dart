import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/location_catalog.dart';
import 'package:lcs_new_age/modern/location_details.dart';
import 'package:lcs_new_age/modern/location_effects.dart';
import 'package:lcs_new_age/saveload/save_load.dart';
import 'package:lcs_new_age/sitemode/sitemap.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'test_support.dart';

void main() {
  late String fixture;
  setUpAll(() async {
    await ensureGameDataLoaded();
    fixture = await File('test/saves/felix_1_0.json').readAsString();
    final serif = FontLoader('JournalSerif');
    serif.addFont(
      rootBundle.load('fonts/journal/LibreBaskerville-Variable.ttf'),
    );
    await serif.load();
  });
  setUp(() {
    engine.console = Console();
    game.gameState = decodeSaveContents(fixture).gameState!;
    journalReadingScale.value = 1;
  });

  test('every location and facility has discoverable mechanics help', () {
    for (final type in SiteType.values) {
      final effects = locationEffects(type);
      expect(effects.opportunities.trim(), isNotEmpty, reason: type.name);
      expect(effects.risks.trim(), isNotEmpty, reason: type.name);
    }
    for (final feature in TileSpecial.values) {
      if (feature == TileSpecial.none) continue;
      expect(
        locationFeatureHelp(feature)?.trim(),
        isNotEmpty,
        reason: feature.name,
      );
      expect(
        locationFeatureSummary(feature)?.trim(),
        isNotEmpty,
        reason: feature.name,
      );
    }
  });

  for (final (name, size, scale) in [
    ('desktop', const Size(1280, 720), 1.0),
    ('compact enlarged', const Size(800, 600), 1.5),
    ('narrow', const Size(390, 844), 1.0),
  ]) {
    testWidgets('all location guides and expanded facilities work at $name', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(() {
        tester.view.resetDevicePixelRatio();
        tester.view.resetPhysicalSize();
      });
      late BuildContext host;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildJournalTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Builder(
            builder: (context) {
              host = context;
              return const Scaffold(body: SizedBox.expand());
            },
          ),
        ),
      );
      final site = game.sites.first;
      final originalType = site.type;
      addTearDown(() => site.type = originalType);
      // Reuse an existing site: constructing one would itself advance campaign
      // IDs and RNG before inspection. Each site's baseline includes its type.
      for (final type in SiteType.values) {
        site.type = type;
        final before = jsonEncode(game.gameState.toJson());
        reseedRNG(seed: 47291);
        final expectedRolls = List.generate(8, (_) => lcsRandom(1000000));
        reseedRNG(seed: 47291);
        final closed = showLocationDetails(host, site);
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '$name ${type.name} open',
        );
        final scroll = find.byKey(
          PageStorageKey('location-guide-scroll:${site.idString}'),
        );
        expect(scroll, findsOneWidget);
        // Several map tiles describe one facility (the Oval Office quadrants);
        // the guide presents one entry per label.
        final facilities = {
          for (final feature in locationFeatureCatalog[type] ?? <TileSpecial>[])
            locationFeatureLabel(feature): feature,
        };
        for (final feature in facilities.values) {
          final tile = find.byKey(
            PageStorageKey(
              'location-facility:${site.idString}:${feature.name}',
            ),
          );
          await tester.ensureVisible(tile);
          await tester.pumpAndSettle();
          // The title remains reachable even when the expanded help is taller
          // than the viewport; exercise the real expansion and its text layout.
          await tester.tap(
            find.descendant(of: tile, matching: find.byType(ListTile)).first,
          );
          await tester.pumpAndSettle();
          expect(
            find.descendant(
              of: tile,
              matching: find.text(locationFeatureHelp(feature)!),
            ),
            findsOneWidget,
            reason: '${type.name} ${feature.name} expanded',
          );
          expect(
            tester.takeException(),
            isNull,
            reason: '$name ${type.name} ${feature.name}',
          );
        }
        // Exercise the bottom of the long guide and its close action.
        final scrollable = find
            .descendant(of: scroll, matching: find.byType(Scrollable))
            .first;
        final state = tester.state<ScrollableState>(scrollable);
        state.position.jumpTo(state.position.maxScrollExtent);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Close location details'));
        await tester.pumpAndSettle();
        await closed;
        expect(
          tester.takeException(),
          isNull,
          reason: '$name ${type.name} close',
        );
        expect(
          jsonEncode(game.gameState.toJson()),
          before,
          reason: '$name ${type.name} inspection changed campaign',
        );
        expect(
          List.generate(8, (_) => lcsRandom(1000000)),
          expectedRolls,
          reason: '$name ${type.name} inspection consumed gameplay RNG',
        );
      }
    }, timeout: const Timeout(Duration(minutes: 10)));
  }
}
