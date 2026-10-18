import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Atlas geometry is fractional: the source images do not have to be divisible
/// by their column count. Insetting each crop avoids neighboring-cell bleed.
@immutable
class TacticalAtlas {
  const TacticalAtlas({
    required this.asset,
    required this.columns,
    required this.rows,
    this.cropInset = 1.5,
  });

  final String asset;
  final int columns, rows;
  final double cropInset;

  int get cellCount => columns * rows;

  Rect sourceRect(ui.Image image, int index) {
    RangeError.checkValueInInterval(index, 0, cellCount - 1, 'index');
    final width = image.width / columns;
    final height = image.height / rows;
    return Rect.fromLTWH(
      (index % columns) * width + cropInset,
      (index ~/ columns) * height + cropInset,
      width - cropInset * 2,
      height - cropInset * 2,
    );
  }
}

const tacticalTerrainAtlas = TacticalAtlas(
  asset: 'assets/modern/tactical_terrain_v1.webp',
  columns: 4,
  rows: 4,
);
const tacticalObjectAtlas = TacticalAtlas(
  asset: 'assets/modern/tactical_objects_v1.webp',
  columns: 4,
  rows: 4,
);
const tacticalHazardAtlas = TacticalAtlas(
  asset: 'assets/modern/tactical_hazards_v1.webp',
  columns: 4,
  rows: 2,
);

abstract final class TacticalTerrainCell {
  static const int ivoryLinoleum = 0;
  static const int oliveCarpet = 1;
  static const int concrete = 2;
  static const int oak = 3;
  static const int laboratoryTile = 4;
  static const int flagstone = 5;
  static const int grass = 6;
  static const int gravel = 7;
  static const int brickWall = 8;
  static const int concreteWall = 9;
  static const int plasterWall = 10;
  static const int metalWall = 11;
  static const int studioCarpet = 12;
  static const int earth = 13;
  static const int pavement = 14;
  static const int parchment = 15;
}

abstract final class TacticalObjectCell {
  static const int radioConsole = 0;
  static const int workstation = 1;
  static const int safe = 2;
  static const int files = 3;
  static const int machinery = 4;
  static const int labBench = 5;
  static const int controlConsole = 6;
  static const int cage = 7;
  static const int table = 8;
  static const int crate = 9;
  static const int cash = 10;
  static const int rubble = 11;
  static const int bench = 12;
  static const int tent = 13;
  static const int displayCase = 14;
  static const int checkpoint = 15;
}

abstract final class TacticalHazardCell {
  static const int spreadingFire = 0;
  static const int intenseFire = 1;
  static const int embers = 2;
  static const int rubble = 3;
  static const int blood = 4;
  static const int heavyBlood = 5;
  static const int trap = 6;
  static const int scorch = 7;
}

typedef TacticalSurfaceCells = ({int floor, int wall});

/// Presentation-only choice of materials. SiteType.name is a display name in
/// the engine; identifier aliases also support isolated previews and callers.
TacticalSurfaceCells tacticalSurfacesForSite(String? siteType) {
  switch (siteType) {
    case 'AM Radio Station':
    case 'Cable News Station':
    case 'amRadioStation':
    case 'cableNewsStation':
      return (
        floor: TacticalTerrainCell.studioCarpet,
        wall: TacticalTerrainCell.plasterWall,
      );
    case 'Cosmetics Lab':
    case 'Genetics Lab':
    case 'cosmeticsLab':
    case 'geneticsLab':
      return (
        floor: TacticalTerrainCell.laboratoryTile,
        wall: TacticalTerrainCell.metalWall,
      );
    case 'Free Clinic':
    case 'University Hospital':
    case 'Nursing Home':
    case 'clinic':
    case 'universityHospital':
    case 'nursingHome':
      return (
        floor: TacticalTerrainCell.ivoryLinoleum,
        wall: TacticalTerrainCell.plasterWall,
      );
    case 'Public Park':
    case 'publicPark':
      return (
        floor: TacticalTerrainCell.grass,
        wall: TacticalTerrainCell.brickWall,
      );
    case 'Homeless Camp':
    case 'Rural Areas':
    case 'homelessEncampment':
    case 'outOfTown':
      return (
        floor: TacticalTerrainCell.earth,
        wall: TacticalTerrainCell.brickWall,
      );
    case 'CEO\'s Mansion':
    case 'White House':
    case 'Courthouse':
    case 'ceoHouse':
    case 'whiteHouse':
    case 'courthouse':
      return (
        floor: TacticalTerrainCell.flagstone,
        wall: TacticalTerrainCell.plasterWall,
      );
    case 'Apartment Building':
    case 'Upscale Apartment':
    case 'Juice Bar':
    case 'Latte Stand':
    case 'Vegan Co-op':
    case 'Desert Eagle Bar & Grill':
    case 'apartment':
    case 'upscaleApartment':
    case 'juiceBar':
    case 'latteStand':
    case 'veganCoOp':
    case 'barAndGrill':
      return (
        floor: TacticalTerrainCell.oak,
        wall: TacticalTerrainCell.plasterWall,
      );
    case 'Low Income Housing':
    case 'Drug House':
    case 'tenement':
    case 'drugHouse':
      return (
        floor: TacticalTerrainCell.oak,
        wall: TacticalTerrainCell.brickWall,
      );
    case 'The Oubliette':
    case 'Fallout Shelter':
    case 'Police Station':
    case 'Prison':
    case 'Fire Station':
    case 'Sweatshop':
    case 'Dirty Industry':
    case 'Nuclear Plant':
    case 'Abandoned Warehouse':
    case 'Robert E. Lee Bunker':
    case 'Army Base':
    case 'oubliette':
    case 'bombShelter':
    case 'policeStation':
    case 'prison':
    case 'fireStation':
    case 'sweatshop':
    case 'dirtyIndustry':
    case 'nuclearPlant':
    case 'warehouse':
    case 'bunker':
    case 'armyBase':
      return (
        floor: TacticalTerrainCell.concrete,
        wall: TacticalTerrainCell.concreteWall,
      );
    case 'Downtown':
    case 'Commercial District':
    case 'University District':
    case 'Industrial District':
    case 'downtown':
    case 'commercialDistrict':
    case 'universityDistrict':
    case 'industrialDistrict':
      return (
        floor: TacticalTerrainCell.pavement,
        wall: TacticalTerrainCell.brickWall,
      );
    default:
      return (
        floor: TacticalTerrainCell.oliveCarpet,
        wall: TacticalTerrainCell.plasterWall,
      );
  }
}

/// A borrowed set of atlas images, valid for the lifetime of its artwork
/// wrapper. Consumers paint with these images but must not dispose them.
@immutable
class TacticalArt {
  const TacticalArt({
    required this.terrain,
    required this.objects,
    required this.hazards,
  });

  final ui.Image terrain, objects, hazards;

  void drawTerrain(
    Canvas canvas,
    Rect rect,
    int index, {
    double opacity = .38,
  }) {
    _draw(canvas, rect, terrain, tacticalTerrainAtlas, index, opacity);
  }

  void drawObject(Canvas canvas, Rect rect, int index, {double opacity = 1}) {
    _draw(canvas, rect, objects, tacticalObjectAtlas, index, opacity);
  }

  void drawHazard(Canvas canvas, Rect rect, int index, {double opacity = .9}) {
    _draw(canvas, rect, hazards, tacticalHazardAtlas, index, opacity);
  }

  static void _draw(
    Canvas canvas,
    Rect rect,
    ui.Image image,
    TacticalAtlas atlas,
    int index,
    double opacity,
  ) {
    if (rect.isEmpty || index < 0 || index >= atlas.cellCount || opacity <= 0) {
      return;
    }
    canvas.drawImageRect(
      image,
      atlas.sourceRect(image, index),
      rect,
      Paint()
        ..color = Colors.white.withValues(alpha: opacity.clamp(0.0, 1.0))
        ..filterQuality = FilterQuality.medium,
    );
  }
}

typedef TacticalArtworkBuilder =
    Widget Function(BuildContext context, TacticalArt? art);

/// Shares Flutter's image cache between the tactical and full-site maps. Until
/// all three atlases are available, the builder receives null and can retain
/// the vector field plan. Missing artwork therefore never blocks play.
class TacticalArtwork extends StatefulWidget {
  const TacticalArtwork({super.key, required this.builder});

  final TacticalArtworkBuilder builder;

  @override
  State<TacticalArtwork> createState() => _TacticalArtworkState();
}

class _TacticalArtworkState extends State<TacticalArtwork> {
  final List<_AtlasImage> _images = [
    _AtlasImage(tacticalTerrainAtlas.asset),
    _AtlasImage(tacticalObjectAtlas.asset),
    _AtlasImage(tacticalHazardAtlas.asset),
  ];
  ImageConfiguration? _configuration;
  TacticalArt? _art;
  int _generation = 0;
  bool _resolving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final configuration = createLocalImageConfiguration(context);
    if (configuration == _configuration) return;
    _configuration = configuration;
    _release();
    final generation = _generation;
    _resolving = true;
    for (final image in _images) {
      final stream = AssetImage(image.asset).resolve(configuration);
      final listener = ImageStreamListener(
        (info, synchronousCall) {
          if (!mounted || generation != _generation) {
            info.dispose();
            return;
          }
          final previous = image.info;
          image.info = info;
          _changed();
          previous?.dispose();
        },
        onError: (exception, stackTrace) {
          if (!mounted || generation != _generation) return;
          final previous = image.info;
          image.info = null;
          _changed();
          previous?.dispose();
        },
      );
      image.stream = stream;
      image.listener = listener;
      stream.addListener(listener);
    }
    _resolving = false;
  }

  void _changed() {
    void updateArt() {
      final terrain = _images[0].info;
      final objects = _images[1].info;
      final hazards = _images[2].info;
      _art = terrain == null || objects == null || hazards == null
          ? null
          : TacticalArt(
              terrain: terrain.image,
              objects: objects.image,
              hazards: hazards.image,
            );
    }

    if (_resolving) {
      updateArt();
    } else {
      setState(updateArt);
    }
  }

  void _release() {
    _generation++;
    _art = null;
    for (final image in _images) {
      final listener = image.listener;
      if (listener != null) image.stream?.removeListener(listener);
      image.listener = null;
      image.stream = null;
      image.info?.dispose();
      image.info = null;
    }
  }

  @override
  void dispose() {
    _release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _art);
}

class _AtlasImage {
  _AtlasImage(this.asset);

  final String asset;
  ImageStream? stream;
  ImageStreamListener? listener;
  ImageInfo? info;
}
