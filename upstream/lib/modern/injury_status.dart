import 'package:lcs_new_age/creature/body.dart';
import 'package:lcs_new_age/creature/creature.dart';

/// Locations on the human medical illustration, from the patient's perspective.
enum InjuryRegion { head, torso, leftArm, rightArm, leftLeg, rightLeg }

/// Presentation priorities, not additional damage or treatment thresholds.
enum InjurySeverity { healthy, minor, serious, critical, missing }

/// Compact roster warning, using the same recorded findings as the medical plate.
/// A healthy person needs no badge; blood loss and permanent damage still count
/// even when there are no visible wounds.
({String label, String details, bool urgent})? crewInjurySummary(
  Creature person,
) {
  final affected = injuryLocations(person).where((entry) => entry.affected);
  final bleeding = person.body.parts.any((part) => part.bleeding > 0);
  final fraction = person.blood / person.maxBlood;
  final critical = affected.any(
    (entry) => entry.severity == InjurySeverity.critical,
  );
  final label = !person.alive
      ? 'Deceased'
      : bleeding
      ? 'Bleeding'
      : fraction < .25
      ? 'Very low blood'
      : critical
      ? 'Critical injury'
      : fraction < .75
      ? 'Low blood'
      : affected.isNotEmpty
      ? 'Injured'
      : fraction < 1
      ? 'Recovering'
      : person.permanentHealthDamage > 0
      ? 'Health loss'
      : null;
  if (label == null) return null;
  return (
    label: label,
    details: [
      label,
      '${person.blood}/${person.maxBlood} blood',
      for (final entry in affected)
        '${entry.name}: ${entry.findings.join(', ')}',
      if (person.permanentHealthDamage > 0)
        'Permanent maximum-health loss: ${person.permanentHealthDamage}',
      'Open dossier for injury details.',
    ].join('\n'),
    urgent: !person.alive || bleeding || fraction < .5 || critical,
  );
}

/// A detached, read-only description of one recorded location or special injury.
class InjuryLocation {
  InjuryLocation({
    required this.id,
    required this.name,
    required this.region,
    required this.severity,
    required List<String> findings,
    required List<String> effects,
    required this.care,
    this.tissueHealth,
    this.bleeding = 0,
    this.internal = false,
  }) : findings = List.unmodifiable(findings),
       effects = List.unmodifiable(effects);

  final String id;
  final String name;
  final InjuryRegion? region;
  final InjurySeverity severity;
  final List<String> findings;
  final List<String> effects;
  final String care;

  /// The stored tissue fraction, not effectiveness. Combat can take it below 0.
  final double? tissueHealth;
  final int bleeding;
  final bool internal;

  bool get affected => severity != InjurySeverity.healthy;
}

/// Reads injury state without rolling dice, treating wounds or changing a save.
///
/// Every actual body part is present, including healthy and nonhuman parts.
/// Special injuries have separate entries so overlapping organs are not hidden
/// by their containing body part. Global permanent health loss belongs to the
/// character summary and is deliberately not attributed to an individual part.
List<InjuryLocation> injuryLocations(Creature person) {
  final body = person.body;
  final human = body is HumanoidBody && body.type == BodyType.human;
  final mappedParts = body is HumanoidBody
      ? [
          body.head,
          body.torso,
          body.leftArm,
          body.rightArm,
          body.leftLeg,
          body.rightLeg,
        ]
      : <BodyPart>[];
  final parts = human
      ? [
          ...mappedParts,
          ...body.parts.where((part) => !mappedParts.contains(part)),
        ]
      : body.parts;
  final locations = <InjuryLocation>[
    for (final part in parts) _bodyPartLocation(body, part, human: human),
  ];
  if (body is! HumanoidBody) return List.unmodifiable(locations);

  InjuryRegion? region(InjuryRegion value) => human ? value : null;

  void organ({
    required bool injured,
    required String id,
    required String name,
    required String finding,
    required int modifier,
    int dailyLoss = 1,
  }) {
    if (!injured) return;
    locations.add(
      InjuryLocation(
        id: id,
        name: name,
        region: region(InjuryRegion.torso),
        severity: InjurySeverity.critical,
        findings: [finding],
        effects: [_modifierEffect(modifier), _untreatedEffect(dailyLoss)],
        care: _majorInjuryCare,
        internal: true,
      ),
    );
  }

  organ(
    injured: body.puncturedRightLung,
    id: 'right-lung',
    name: 'Right lung',
    finding: 'Collapsed lung',
    modifier: 2,
  );
  organ(
    injured: body.puncturedLeftLung,
    id: 'left-lung',
    name: 'Left lung',
    finding: 'Collapsed lung',
    modifier: 2,
  );
  organ(
    injured: body.puncturedHeart,
    id: 'heart',
    name: 'Heart',
    finding: 'Punctured heart',
    modifier: 2,
    dailyLoss: 9,
  );
  organ(
    injured: body.puncturedLiver,
    id: 'liver',
    name: 'Liver',
    finding: 'Damaged liver',
    modifier: 1,
  );
  organ(
    injured: body.puncturedStomach,
    id: 'stomach',
    name: 'Stomach',
    finding: 'Injured stomach',
    modifier: 1,
  );
  organ(
    injured: body.puncturedRightKidney,
    id: 'right-kidney',
    name: 'Right kidney',
    finding: 'Damaged kidney',
    modifier: 1,
  );
  organ(
    injured: body.puncturedLeftKidney,
    id: 'left-kidney',
    name: 'Left kidney',
    finding: 'Damaged kidney',
    modifier: 1,
  );
  organ(
    injured: body.puncturedSpleen,
    id: 'spleen',
    name: 'Spleen',
    finding: 'Damaged spleen',
    modifier: 1,
  );

  void spine({
    required InjuryState state,
    required String id,
    required String name,
    required int modifier,
    required bool fullParalysis,
  }) {
    if (state == InjuryState.healthy) return;
    final untreated = state == InjuryState.untreated;
    locations.add(
      InjuryLocation(
        id: id,
        name: name,
        region: region(id == 'neck' ? InjuryRegion.head : InjuryRegion.torso),
        severity: untreated ? InjurySeverity.critical : InjurySeverity.serious,
        findings: ['Broken${untreated ? ' · untreated' : ' · stabilized'}'],
        effects: [
          _modifierEffect(modifier),
          if (fullParalysis)
            'Arms and legs are paralyzed; cannot walk or wield weapons. '
                'Strength and Agility are severely reduced.'
          else
            'This injury paralyzes the legs and prevents walking. By itself, '
                'it halves Strength and quarters Agility, with normal '
                'attribute rounding.',
          if (untreated) _untreatedEffect(1),
        ],
        care: untreated
            ? 'Medical care can stabilize this injury and stop its daily '
                  'deterioration. Stabilization does not reverse paralysis '
                  'or remove the injury modifier.'
            : 'Stabilized: no further daily deterioration from this injury. '
                  'Paralysis and the injury modifier remain; ordinary '
                  'healing does not restore the damaged spine.',
        internal: true,
      ),
    );
  }

  spine(
    state: body.neck,
    id: 'neck',
    name: 'Neck',
    modifier: 75,
    fullParalysis: true,
  );
  spine(
    state: body.upperSpine,
    id: 'upper-spine',
    name: 'Upper spine',
    modifier: 25,
    fullParalysis: true,
  );
  spine(
    state: body.lowerSpine,
    id: 'lower-spine',
    name: 'Lower spine',
    modifier: 50,
    fullParalysis: false,
  );

  void missingFacePart({
    required bool missing,
    required String id,
    required String name,
    required int charismaLoss,
    List<String> additionalEffects = const [],
  }) {
    if (!missing) return;
    locations.add(
      InjuryLocation(
        id: id,
        name: name,
        region: region(InjuryRegion.head),
        severity: InjurySeverity.missing,
        findings: ['Missing'],
        effects: [
          'Charisma −$charismaLoss before the attribute minimum.',
          ...additionalEffects,
        ],
        care: _permanentLossCare,
      ),
    );
  }

  final eyeEffects = body.intactEyes == 0
      ? [
          'Both eyes are missing: cannot see. Combined eye loss adds 5 '
              'to the injury modifier.',
        ]
      : ['One eye remains: sight is retained.'];
  missingFacePart(
    missing: body.missingRightEye,
    id: 'right-eye',
    name: 'Right eye',
    charismaLoss: 2,
    additionalEffects: eyeEffects,
  );
  missingFacePart(
    missing: body.missingLeftEye,
    id: 'left-eye',
    name: 'Left eye',
    charismaLoss: 2,
    additionalEffects: eyeEffects,
  );
  missingFacePart(
    missing: body.missingNose,
    id: 'nose',
    name: 'Nose',
    charismaLoss: 3,
  );
  missingFacePart(
    missing: body.missingTongue,
    id: 'tongue',
    name: 'Tongue',
    charismaLoss: 3,
  );

  if (body.missingTeeth) {
    final charismaLoss = 1 + (body.halfTeeth ? 1 : 0) + (body.noTeeth ? 1 : 0);
    locations.add(
      InjuryLocation(
        id: 'teeth',
        name: 'Teeth',
        region: region(InjuryRegion.head),
        severity: body.noTeeth
            ? InjurySeverity.missing
            : body.halfTeeth
            ? InjurySeverity.serious
            : InjurySeverity.minor,
        findings: ['${body.teeth} of ${body.maxTeeth} teeth remain'],
        effects: ['Charisma −$charismaLoss before the attribute minimum.'],
        care: _permanentLossCare,
      ),
    );
  }

  if (body.ribs < body.maxRibs) {
    // The existing modifier deliberately uses fixed counts of 10 and 5,
    // rather than fractions of the body's configurable maximum rib count.
    final modifier =
        (body.ribs < 10 ? 1 : 0) +
        (body.ribs < 5 ? 1 : 0) +
        (body.ribs <= 0 ? 1 : 0);
    locations.add(
      InjuryLocation(
        id: 'ribs',
        name: 'Ribs',
        region: region(InjuryRegion.torso),
        severity: InjurySeverity.serious,
        findings: ['${body.maxRibs - body.ribs} broken · ${body.ribs} intact'],
        effects: [
          if (modifier > 0)
            _modifierEffect(modifier)
          else
            'No additional injury modifier at this rib count.',
          _untreatedEffect(1),
        ],
        care: _majorInjuryCare,
        internal: true,
      ),
    );
  }

  return List.unmodifiable(locations);
}

const String _majorInjuryCare =
    'Medical support makes daily stabilization possible. University hospitals '
    'provide stronger support than basic care. Recovery depends on medical '
    'skill and daily treatment checks; there is no fixed recovery date.';
const String _permanentLossCare =
    'Permanent loss. Daily healing and hospital care do not replace missing parts.';

String _modifierEffect(int modifier) =>
    'Adds $modifier to the injury modifier used by combat and injury-affected checks.';

String _untreatedEffect(int dailyLoss) =>
    'If daily treatment fails: $dailyLoss blood lost, with a risk of permanent '
    'maximum-health loss.';

InjuryLocation _bodyPartLocation(
  Body body,
  BodyPart part, {
  required bool human,
}) {
  final humanoid = body is HumanoidBody ? body : null;
  final region = !human
      ? null
      : identical(part, humanoid!.head)
      ? InjuryRegion.head
      : identical(part, humanoid.torso)
      ? InjuryRegion.torso
      : identical(part, humanoid.leftArm)
      ? InjuryRegion.leftArm
      : identical(part, humanoid.rightArm)
      ? InjuryRegion.rightArm
      : identical(part, humanoid.leftLeg)
      ? InjuryRegion.leftLeg
      : identical(part, humanoid.rightLeg)
      ? InjuryRegion.rightLeg
      : null;
  final id = switch (region) {
    InjuryRegion.head => 'head',
    InjuryRegion.torso => 'torso',
    InjuryRegion.leftArm => 'left-arm',
    InjuryRegion.rightArm => 'right-arm',
    InjuryRegion.leftLeg => 'left-leg',
    InjuryRegion.rightLeg => 'right-leg',
    null => part.name.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-'),
  };
  final findings = <String>[
    if (part.nastyOff) 'Severed · unstabilized',
    if (part.cleanOff) 'Missing · stabilized',
    if (part.shot) 'Shot',
    if (part.cut) 'Cut',
    if (part.bruised) 'Bruised',
    if (part.burned) 'Burned',
    if (part.torn) 'Torn',
    if (part.bleeding > 0) 'Bleeding (${part.bleeding})',
    if (part.relativeHealth < 1 && !part.missing) 'Tissue damage',
    if (!part.wounded) 'No recorded injuries',
  ];
  final effects = <String>[];
  if (part.missing) {
    if (part.critical) {
      effects.add('Loss of this vital location is fatal.');
    } else if (region == InjuryRegion.leftArm ||
        region == InjuryRegion.rightArm) {
      effects.add(
        humanoid!.intactArms == 0
            ? 'Both arms are missing: cannot wield weapons.'
            : humanoid.fullParalysis
            ? 'The remaining arm is paralyzed; cannot wield weapons.'
            : 'One arm remains usable; this loss has no separate injury modifier.',
      );
    } else if (region == InjuryRegion.leftLeg ||
        region == InjuryRegion.rightLeg) {
      effects.add(
        humanoid!.intactLegs == 0
            ? 'Both legs are missing: cannot walk. Agility is quartered, '
                  'with normal attribute rounding.'
            : humanoid.partialParalysis
            ? 'The remaining leg is paralyzed; cannot walk.'
            : 'One leg remains: walking is still possible.',
      );
    } else {
      effects.add('This body part is missing.');
    }
    if (part.nastyOff) {
      effects.add('Failed daily stabilization costs 4 blood.');
    }
  } else if (part.wounded) {
    if (part.relativeHealth < 1) {
      effects.add('Further hits can more easily sever this location.');
    }
    effects.add(
      'This wound alone adds no separate combat or movement penalty.',
    );
  }
  if (part.bleeding > 0) {
    effects.add(
      'Uncontrolled bleeding can drain blood and damage tissue during '
      'operations. Loss per turn is not guaranteed: clotting or First Aid '
      'may stop it.',
    );
  }

  final severity = !part.wounded
      ? InjurySeverity.healthy
      : part.missing
      ? InjurySeverity.missing
      : part.relativeHealth <= 0 || part.bleeding >= 3
      ? InjurySeverity.critical
      : part.shot ||
            part.cut ||
            part.torn ||
            part.bleeding > 0 ||
            part.relativeHealth < .5
      ? InjurySeverity.serious
      : InjurySeverity.minor;
  final care = !part.wounded
      ? 'No treatment needed for this location.'
      : part.nastyOff
      ? 'Needs medical stabilization to stop further daily blood loss. '
            'Treatment leaves this part missing; it does not regrow.'
      : part.bleeding > 0
      ? 'First Aid during an operation or daily medical care can stop bleeding. '
            '${part.missing ? _permanentLossCare : 'Non-bleeding wounds clear near full blood during daily injury recovery.'}'
      : part.missing
      ? _permanentLossCare
      : 'Non-bleeding wounds clear near full blood during daily injury recovery. '
            'Tissue health is not a percentage of combat effectiveness.';

  return InjuryLocation(
    id: id,
    name: part.name,
    region: region,
    severity: severity,
    findings: findings,
    effects: effects,
    care: care,
    tissueHealth: part.relativeHealth,
    bleeding: part.bleeding,
  );
}
