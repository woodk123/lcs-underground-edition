import 'dart:math' as math;

import 'package:flutter/material.dart';

const journalSiteArtPaper = Color(0xFFEDE0BD);

/// Keys are the engine's stable SiteType names, independent of renamed sites.
/// Each cell contains a dedicated building or small-site illustration.
const journalSiteArt = <String, ({int atlas, int cell, int columns})>{
  'clinic': (atlas: 1, cell: 0, columns: 4),
  'universityHospital': (atlas: 1, cell: 1, columns: 4),
  'pawnShop': (atlas: 1, cell: 2, columns: 4),
  'departmentStore': (atlas: 1, cell: 3, columns: 4),
  'oubliette': (atlas: 1, cell: 4, columns: 4),
  'armsDealer': (atlas: 1, cell: 5, columns: 4),
  'carDealership': (atlas: 1, cell: 6, columns: 4),
  'homelessEncampment': (atlas: 1, cell: 7, columns: 4),
  'tenement': (atlas: 1, cell: 8, columns: 4),
  'apartment': (atlas: 1, cell: 9, columns: 4),
  'upscaleApartment': (atlas: 1, cell: 10, columns: 4),
  'bombShelter': (atlas: 1, cell: 11, columns: 4),
  'cosmeticsLab': (atlas: 1, cell: 12, columns: 4),
  'geneticsLab': (atlas: 1, cell: 13, columns: 4),
  'policeStation': (atlas: 1, cell: 14, columns: 4),
  'courthouse': (atlas: 1, cell: 15, columns: 4),
  'prison': (atlas: 2, cell: 0, columns: 4),
  'intelligenceHQ': (atlas: 2, cell: 1, columns: 4),
  'fireStation': (atlas: 2, cell: 2, columns: 4),
  'sweatshop': (atlas: 2, cell: 3, columns: 4),
  'dirtyIndustry': (atlas: 2, cell: 4, columns: 4),
  'nuclearPlant': (atlas: 2, cell: 5, columns: 4),
  'warehouse': (atlas: 2, cell: 6, columns: 4),
  'corporateHQ': (atlas: 2, cell: 7, columns: 4),
  'ceoHouse': (atlas: 2, cell: 8, columns: 4),
  'amRadioStation': (atlas: 2, cell: 9, columns: 4),
  'cableNewsStation': (atlas: 2, cell: 10, columns: 4),
  'drugHouse': (atlas: 2, cell: 11, columns: 4),
  'juiceBar': (atlas: 2, cell: 12, columns: 4),
  'latteStand': (atlas: 2, cell: 13, columns: 4),
  'veganCoOp': (atlas: 2, cell: 14, columns: 4),
  'internetCafe': (atlas: 2, cell: 15, columns: 4),
  'barAndGrill': (atlas: 3, cell: 0, columns: 3),
  'publicPark': (atlas: 3, cell: 1, columns: 3),
  'bunker': (atlas: 3, cell: 2, columns: 3),
  'armyBase': (atlas: 3, cell: 3, columns: 3),
  'bank': (atlas: 3, cell: 4, columns: 3),
  'insuranceOffice': (atlas: 3, cell: 5, columns: 3),
  'nursingHome': (atlas: 3, cell: 6, columns: 3),
  'liberalPartyHQ': (atlas: 3, cell: 7, columns: 3),
  'whiteHouse': (atlas: 3, cell: 8, columns: 3),
};

/// Building art is always separate from the city/district atlas. Unknown future
/// types use a generic office building until a dedicated illustration is added.
class JournalSiteArtwork extends StatelessWidget {
  const JournalSiteArtwork({super.key, this.siteType});
  final String? siteType;

  @override
  Widget build(BuildContext context) {
    final art = journalSiteArt[siteType] ?? journalSiteArt['corporateHQ']!;
    return ColoredBox(
      color: journalSiteArtPaper,
      child: LayoutBuilder(
        builder: (context, bounds) {
          final side = math.min(bounds.maxWidth, bounds.maxHeight);
          final imageSide = side * art.columns;
          return Center(
            child: SizedBox.square(
              dimension: side,
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment(
                    -1 + 2 * (art.cell % art.columns) / (art.columns - 1),
                    -1 + 2 * (art.cell ~/ art.columns) / (art.columns - 1),
                  ),
                  minWidth: imageSide,
                  maxWidth: imageSide,
                  minHeight: imageSide,
                  maxHeight: imageSide,
                  child: Image.asset(
                    'assets/modern/site_atlas_${art.atlas}_v1.webp',
                    width: imageSide,
                    height: imageSide,
                    fit: BoxFit.fill,
                    excludeFromSemantics: true,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
