import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/modern/journal_city_plan.dart';
import 'package:lcs_new_age/modern/journal_site_art.dart';

void main() {
  test('every engine building type has its own illustration cell', () {
    final sites = SiteType.values.takeWhile(
      (type) => type != SiteType.downtown,
    );
    expect(
      journalSiteArt.keys.toSet(),
      sites.map((type) => EnumName(type).name).toSet(),
    );
    expect(
      journalSiteArt.values.map((art) => (art.atlas, art.cell)).toSet().length,
      sites.length,
    );
    for (final art in journalSiteArt.values) {
      expect(art.cell, inInclusiveRange(0, art.columns * art.columns - 1));
    }
  });

  testWidgets('renamed sites use their types and never district art', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: JournalCityPlan(
            places: const [
              JournalMapPlace(
                id: 'clinic',
                name: 'A custom name',
                kind: 'site',
                siteType: 'clinic',
                enabled: true,
              ),
              JournalMapPlace(
                id: 'cafe',
                name: 'A custom name',
                kind: 'site',
                siteType: 'internetCafe',
                enabled: true,
              ),
              JournalMapPlace(
                id: 'park',
                name: 'A custom name',
                kind: 'site',
                siteType: 'publicPark',
                enabled: true,
              ),
              JournalMapPlace(
                id: 'future',
                name: 'Unknown future building',
                kind: 'site',
                enabled: true,
              ),
            ],
            onSelect: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final entry in {
      'clinic': 'clinic',
      'cafe': 'internetCafe',
      'park': 'publicPark',
      'future': 'corporateHQ',
    }.entries) {
      final image = tester.widget<Image>(
        find.descendant(
          of: find.byKey(ValueKey('journal-map-place:${entry.key}')),
          matching: find.byType(Image),
        ),
      );
      final art = journalSiteArt[entry.value]!;
      expect(
        (image.image as AssetImage).assetName,
        'assets/modern/site_atlas_${art.atlas}_v1.png',
      );
    }
    expect(tester.takeException(), isNull);
  });
}
