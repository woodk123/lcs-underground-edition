import 'package:flutter/material.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/modern/injury_status.dart';

/// Current facts, never a simulated battle or a promise of survival.
class SquadReadiness {
  SquadReadiness(Iterable<Creature> members) : people = List.of(members);
  final List<Creature> people;

  int get emptyGuns =>
      people.where((p) => p.weapon.type.usesAmmo && p.weapon.ammo == 0).length;
  int get injured => people.where((p) => crewInjurySummary(p) != null).length;
  List<Creature> medicsFor(Creature patient) =>
      people
          .where(
            (p) =>
                p.alive &&
                p.id != patient.id &&
                p.stunned <= 0 &&
                p.blood > 40 &&
                p.skill(Skill.firstAid) > 0,
          )
          .toList()
        ..sort(
          (a, b) => b.skill(Skill.firstAid).compareTo(a.skill(Skill.firstAid)),
        );

  String get summary =>
      '${people.length} crew · ${people.where((p) => p.equippedWeapon != null).length} armed · '
      '$emptyGuns empty guns · $injured injured · '
      '${people.where((p) => p.alive && p.stunned <= 0 && p.blood > 40 && p.skill(Skill.firstAid) > 0).length} First Aid helpers';

  List<String> details(Creature p) {
    final medics = medicsFor(p);
    return [
      if (p.equippedWeapon == null)
        'Natural attack: ${p.weapon.type.name}'
      else
        'Weapon: ${p.weapon.type.name}',
      if (p.weapon.type.usesAmmo)
        'Ammo: ${p.weapon.ammo} loaded · ${p.weapon.acceptableAmmo.contains(p.spareAmmo?.type) ? p.spareAmmo?.stackSize ?? 0 : 0} compatible spare rounds'
      else
        'Does not require cartridge ammunition.',
      if (crewInjurySummary(p) case final injury?)
        injury.details
      else
        '${p.blood}/${p.maxBlood} blood · No recorded injuries',
      if (medics.isEmpty)
        'No eligible squadmate with First Aid can treat this person’s bleeding.'
      else
        'Bleeding support: ${medics.first.name} · First Aid ${medics.first.skill(Skill.firstAid)}',
    ];
  }
}

class SquadReadinessView extends StatelessWidget {
  const SquadReadinessView({super.key, required this.readiness});
  final SquadReadiness readiness;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Combat readiness',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      Text(readiness.summary),
      const Text(
        'Medical help uses another living squadmate who is not stunned and has more than 40 blood. First Aid must pass a hard check; it is not guaranteed.',
      ),
      for (final person in readiness.people) ...[
        const Divider(),
        Text(person.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        for (final line in readiness.details(person)) Text(line),
      ],
    ],
  );
}
