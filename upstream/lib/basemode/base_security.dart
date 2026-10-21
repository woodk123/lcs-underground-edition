import 'dart:math' as math;

import 'package:lcs_new_age/location/site.dart';

/// The original HQ surveillance thresholds, shared by both presentations.
/// Reading these warnings never rolls for a raid or advances surveillance.
String? baseSurveillanceWarning(Site site) {
  final heat = [
    site.extraHeatFromCIA ~/ 2,
    site.extraHeatFromCCS,
    site.extraHeatFromCorps,
    site.extraHeatFromRuralMobs * 2,
  ].reduce(math.max);
  final protection = site.heatProtection;
  if (heat > protection * .9) return 'Overt';
  if (heat > protection * .6) return 'Likely';
  if (heat > protection * .3) return 'Possible';
  return null;
}
