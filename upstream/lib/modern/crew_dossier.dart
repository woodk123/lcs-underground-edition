import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/creature/attributes.dart';
import 'package:lcs_new_age/creature/body.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/modern/attribute_help.dart';
import 'package:lcs_new_age/modern/crew_portrait.dart';
import 'package:lcs_new_age/modern/decision_help.dart';
import 'package:lcs_new_age/modern/equipment_help.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/mechanics_help.dart';
import 'package:lcs_new_age/modern/skill_help.dart';

const _ink = JournalPalette.ink;
const _muted = JournalPalette.muted;
const _teal = JournalPalette.olive;
const _red = JournalPalette.danger;
const _paper = JournalPalette.card;
const _rule = JournalPalette.rule;

/// A command the host has already checked against the current engine frame.
/// The dossier itself never decides which engine commands are available.
class CrewDossierAction {
  const CrewDossierAction({
    required this.label,
    required this.onPressed,
    this.icon = Icons.arrow_forward,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final bool enabled;
}

/// Opens a local inspector. Inspecting or dismissing consumes no engine input.
Future<void> showCrewDossier(
  BuildContext context, {
  required Creature person,
  List<CrewDossierAction> actions = const [],
}) => showDialog<void>(
  context: context,
  builder: (context) => CrewDossier(person: person, actions: actions),
);

/// A bounded, nonmodal personnel inspector. The host keeps its other controls
/// active and supplies the commands already available in its current frame.
class CrewInspector extends StatelessWidget {
  const CrewInspector({
    super.key,
    required this.person,
    required this.onClose,
    this.actions = const [],
    this.compact = false,
  });

  final Creature person;
  final VoidCallback onClose;
  final List<CrewDossierAction> actions;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final skills = Skill.values.toList()
      ..sort((a, b) {
        final level = person.skill(b).compareTo(person.skill(a));
        return level != 0 ? level : a.displayName.compareTo(b.displayName);
      });
    final assignment = activityMechanics(
      person.activity.type,
      actor: person,
      activity: person.activity,
    );
    final squadOrder = person.squad == null
        ? null
        : activityMechanics(
            person.squad!.activity.type,
            activity: person.squad!.activity,
          );
    final wounds = <String>[
      ...person.body.allSpecialInjuries(),
      for (final part in person.body.parts.where((part) => part.wounded))
        '${part.name}: ${[if (part.missing) 'missing', if (part.shot) 'shot', if (part.cut) 'cut', if (part.bruised) 'bruised', if (part.burned) 'burned', if (part.torn) 'torn', if (part.bleeding > 0) 'bleeding (${part.bleeding})'].join(', ')}',
    ];
    return Theme(
      data: buildJournalTheme(),
      child: Material(
        key: const ValueKey('crew-inspector'),
        color: _paper,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(3),
          side: const BorderSide(color: _rule),
        ),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: journalPaperDecoration(),
          child: DefaultTextStyle.merge(
            style: const TextStyle(
              fontFamily: JournalPalette.serif,
              fontFamilyFallback: ['ModernSans'],
              fontSize: 12,
              height: 1.35,
              color: _ink,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 9, 3, 8),
                  child: Row(
                    children: [
                      CrewPortrait(person: person, size: compact ? 36 : 44),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              person.name.isEmpty
                                  ? 'Unnamed person'
                                  : person.name,
                              key: const ValueKey('crew-inspector-name'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                height: 1.15,
                              ),
                            ),
                            Text(
                              '${person.title} · ${person.blood}/${person.maxBlood} blood',
                              maxLines: 2,
                              style: TextStyle(
                                color: person.blood < person.maxBlood
                                    ? _red
                                    : _teal,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('crew-inspector-close'),
                        tooltip: 'Close crew inspection',
                        visualDensity: VisualDensity.compact,
                        onPressed: onClose,
                        icon: const Icon(Icons.close, size: 17),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: _rule),
                Expanded(
                  child: SingleChildScrollView(
                    key: const ValueKey('crew-inspector-scroll'),
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _inlineFact(
                          'Personal assignment',
                          person.activity.description,
                        ),
                        Text(
                          assignment.summary,
                          style: const TextStyle(color: _muted, fontSize: 11),
                        ),
                        if (assignment.factors.isNotEmpty)
                          _inlineFact('Uses', assignment.factors),
                        if (assignment.cost.isNotEmpty)
                          _inlineFact('Cost', assignment.cost),
                        if (assignment.risk.isNotEmpty)
                          Text(
                            assignment.risk,
                            style: const TextStyle(color: _red, fontSize: 11),
                          ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            assignment.timing,
                            style: const TextStyle(color: _muted, fontSize: 11),
                          ),
                        ),
                        if (assignment.calculation case final calculation?)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 9),
                            child: MechanicsTooltip(
                              message: calculation.text,
                              maxWidth: 520,
                              child: Text(
                                calculation.result,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        if (person.squad != null)
                          _inlineFact(
                            'Squad order',
                            person.squad!.activity.type == ActivityType.none
                                ? 'None · personal assignment applies'
                                : person.squad!.activity.description,
                          ),
                        if (squadOrder != null &&
                            person.squad!.activity.type != ActivityType.none &&
                            person.squad!.activity.type != person.activity.type)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              '${squadOrder.summary} ${squadOrder.timing}',
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        _inlineFact(
                          'Location',
                          person.location?.getName(includeCity: true) ??
                              'Unknown',
                        ),
                        _inlineFact(
                          'Equipment',
                          [
                            stripConsoleColors(
                              person.weapon.equipTitle(full: true),
                            ),
                            person.equippedClothing?.type.name ?? 'No clothing',
                            if (person.car != null)
                              '${person.car!.fullName()} · ${person.isDriver ? 'driver' : 'passenger'}',
                          ].join(' · '),
                        ),
                        if (wounds.isNotEmpty)
                          _inlineFact(
                            'Injuries',
                            wounds.join(' · '),
                            warning: true,
                          ),
                        if (person.hospitalized)
                          _inlineFact(
                            'Recovery',
                            '${person.daysHospitalized} days hospitalized',
                          ),
                        if (person.inHiding)
                          _inlineFact(
                            'Hiding',
                            '${person.hidingDaysLeft} days remaining',
                          ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 9),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 3,
                            children: [
                              const Text(
                                'Strongest skills',
                                style: TextStyle(color: _muted),
                              ),
                              for (final skill in skills.take(4))
                                SkillTooltip(
                                  skill: skill,
                                  actor: person,
                                  child: Text(
                                    '${skill.displayName} ${person.skill(skill)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        _inlineFact('Legal heat', '${person.heat}'),
                        const Text(
                          'Legal heat measures police attention, not a percentage.',
                          style: TextStyle(fontSize: 11, color: _muted),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 3, 8, 7),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      for (final action in actions)
                        FilledButton.icon(
                          onPressed: action.enabled ? action.onPressed : null,
                          icon: Icon(action.icon, size: 15),
                          label: Text(action.label),
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            textStyle: const TextStyle(fontSize: 11),
                          ),
                        ),
                      TextButton.icon(
                        key: const ValueKey('crew-inspector-full'),
                        onPressed: () => showCrewDossier(
                          context,
                          person: person,
                          actions: actions,
                        ),
                        icon: const Icon(Icons.open_in_full, size: 14),
                        label: const Text('Full dossier'),
                        style: TextButton.styleFrom(
                          foregroundColor: _teal,
                          visualDensity: VisualDensity.compact,
                          textStyle: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _inlineFact(String label, String value, {bool warning = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$label  ',
                style: const TextStyle(color: _muted),
              ),
              TextSpan(
                text: value,
                style: TextStyle(
                  color: warning ? _red : _ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
}

class CrewDossier extends StatefulWidget {
  const CrewDossier({
    super.key,
    required this.person,
    this.actions = const [],
    this.embedded = false,
    this.page = 0,
    this.onPage,
  });

  final Creature person;
  final List<CrewDossierAction> actions;
  final bool embedded;
  final int page;
  final ValueChanged<int>? onPage;

  @override
  State<CrewDossier> createState() => _CrewDossierState();
}

class _CrewDossierState extends State<CrewDossier> {
  int _tab = 0;
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: buildJournalTheme(),
    child: widget.embedded
        ? _journalContents()
        : Shortcuts(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
            },
            child: Actions(
              actions: {
                DismissIntent: CallbackAction<DismissIntent>(
                  onInvoke: (_) {
                    Navigator.of(context).pop();
                    return null;
                  },
                ),
              },
              child: Dialog(
                key: const ValueKey('crew-dossier'),
                backgroundColor: JournalPalette.leather,
                surfaceTintColor: Colors.transparent,
                insetPadding: const EdgeInsets.all(20),
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                  side: const BorderSide(color: JournalPalette.brassDark),
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 920,
                    maxHeight: MediaQuery.sizeOf(context).height - 40,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: JournalSurface(
                      padding: EdgeInsets.zero,
                      child: DefaultTextStyle.merge(
                        style: const TextStyle(
                          fontFamily: JournalPalette.serif,
                          fontFamilyFallback: ['ModernSans'],
                          color: _ink,
                          fontSize: 15,
                          height: 1.45,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _topBar(),
                            Flexible(
                              child: SingleChildScrollView(
                                key: const ValueKey('crew-dossier-scroll'),
                                controller: _scroll,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _header(),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        24,
                                        0,
                                        24,
                                        16,
                                      ),
                                      child: Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          _tabButton(
                                            0,
                                            'Overview',
                                            Icons.person_outline,
                                          ),
                                          _tabButton(
                                            1,
                                            'Skills',
                                            Icons.auto_graph,
                                          ),
                                          _tabButton(
                                            2,
                                            'Campaign record',
                                            Icons.history_edu,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Divider(height: 1, color: _rule),
                                    Padding(
                                      padding: const EdgeInsets.all(24),
                                      child: switch (_tab) {
                                        1 => _skills(),
                                        2 => _record(),
                                        _ => _overview(),
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            _footer(),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
  );

  Widget _journalContents() => Material(
    key: const ValueKey('journal-personnel-profile'),
    color: Colors.transparent,
    child: Scrollbar(
      controller: _scroll,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _scroll,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (index, label) in [
                    (0, 'Overview'),
                    (1, 'Skills'),
                    (2, 'Campaign record'),
                  ])
                    Semantics(
                      selected: widget.page == index,
                      child: TextButton(
                        key: ValueKey('journal-profile-tab:$index'),
                        onPressed: () => widget.onPage?.call(index),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(40, 34),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 6,
                          ),
                          backgroundColor: widget.page == index
                              ? JournalPalette.selected
                              : Colors.transparent,
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.all(Radius.circular(2)),
                          ),
                        ),
                        child: Text(label, style: JournalPalette.small),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: switch (widget.page) {
                1 => _skills(),
                2 => _record(),
                _ => _overview(),
              },
            ),
          ],
        ),
      ),
    ),
  );

  Widget _topBar() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 10, 16, 0),
    child: Row(
      children: [
        const Expanded(
          child: Text(
            'PERSONNEL DOSSIER',
            style: TextStyle(
              color: _muted,
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 1.7,
            ),
          ),
        ),
        IconButton(
          key: const ValueKey('crew-dossier-close'),
          tooltip: 'Close dossier',
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close, color: _ink),
        ),
      ],
    ),
  );

  Widget _header() {
    final person = widget.person;
    return Padding(
      padding: widget.embedded
          ? const EdgeInsets.fromLTRB(12, 8, 12, 12)
          : const EdgeInsets.fromLTRB(24, 12, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, bounds) {
              final compact = bounds.maxWidth < 500;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CrewPortrait(
                    person: person,
                    size: widget.embedded
                        ? (compact ? 64 : 76)
                        : compact
                        ? 88
                        : 132,
                    borderRadius: 3,
                  ),
                  SizedBox(
                    width: widget.embedded
                        ? 12
                        : compact
                        ? 16
                        : 24,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          person.name.isEmpty ? 'Unnamed person' : person.name,
                          key: const ValueKey('crew-dossier-name'),
                          style: TextStyle(
                            fontSize: widget.embedded
                                ? (compact ? 20 : 22)
                                : compact
                                ? 24
                                : 32,
                            fontWeight: FontWeight.w800,
                            height: 1.12,
                            letterSpacing: widget.embedded ? 0 : -.7,
                          ),
                        ),
                        if (person.properName.isNotEmpty &&
                            person.properName != person.name) ...[
                          const SizedBox(height: 5),
                          Text(
                            person.properName,
                            style: const TextStyle(color: _muted),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          person.title,
                          style: const TextStyle(
                            color: _teal,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _tag(_capitalize(person.align.name)),
                            _tag(person.type.name),
                            _tag('Age ${person.age}'),
                            if (!person.alive) _tag('Deceased', warning: true),
                            if (person.sleeperAgent) _tag('Sleeper agent'),
                            if (person.kidnapped)
                              _tag('Captive', warning: true),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _tabButton(int value, String label, IconData icon) => TextButton.icon(
    key: ValueKey('crew-dossier-tab-$value'),
    onPressed: () {
      setState(() => _tab = value);
      if (_scroll.hasClients) _scroll.jumpTo(0);
    },
    style: TextButton.styleFrom(
      foregroundColor: _tab == value ? _ink : _muted,
      backgroundColor: _tab == value
          ? JournalPalette.selected
          : JournalPalette.inset,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      side: BorderSide(color: _tab == value ? JournalPalette.binding : _rule),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
    ),
    icon: Icon(icon, size: 18),
    label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
  );

  Widget _overview() {
    final person = widget.person;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _twoColumns(
          _section('Condition', Icons.favorite_border, [
            DecisionGuideButton(topic: DecisionTopic.health, actor: person),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 5,
              children: [
                const Text(
                  'Blood',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  '${person.blood} / ${person.maxBlood}',
                  key: const ValueKey('crew-dossier-blood'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: person.maxBlood == 0
                    ? 0
                    : (person.blood / person.maxBlood).clamp(0, 1),
                minHeight: 8,
                color: person.blood < person.maxBlood ? _red : _teal,
                backgroundColor: _rule,
                semanticsLabel: 'Blood remaining',
              ),
            ),
            const SizedBox(height: 12),
            _fact('Health', '${person.health}'),
            if (person.permanentHealthDamage > 0)
              _fact('Permanent health loss', '${person.permanentHealthDamage}'),
            const SizedBox(height: 8),
            ..._injuries(person),
          ]),
          _section('Current orders', Icons.assignment_outlined, [
            DecisionGuideButton(
              topic: DecisionTopic.availability,
              actor: person,
            ),
            DecisionGuideButton(
              topic: DecisionTopic.recruitment,
              actor: person,
            ),
            _fact('Personal assignment', person.activity.description),
            _orderMechanics(),
            const SizedBox(height: 10),
            _fact('Squad', person.squad?.name ?? 'Unassigned'),
            if (person.squad != null)
              _fact('Squad order', person.squad!.activity.description),
            _fact(
              'Location',
              person.location?.getName(includeCity: true) ?? 'Location unknown',
            ),
            if (person.base != null)
              _fact('Home base', person.base!.getName(includeCity: true)),
            if (person.hospitalized)
              _fact('Hospital', '${person.daysHospitalized} days hospitalized'),
            if (person.inHiding)
              _fact('Hiding', '${person.hidingDaysLeft} days remaining'),
            if (person.vacationDaysLeft > 0)
              _fact('Vacation', '${person.vacationDaysLeft} days remaining'),
            if (person.imprisoned)
              const Text('Currently imprisoned', style: TextStyle(color: _red)),
          ]),
        ),
        const SizedBox(height: 22),
        _twoColumns(
          _section('Equipment', Icons.inventory_2_outlined, [
            Wrap(
              children: [
                DecisionGuideButton(
                  topic: DecisionTopic.weapons,
                  actor: person,
                ),
                DecisionGuideButton(
                  topic: DecisionTopic.clothing,
                  actor: person,
                ),
                DecisionGuideButton(
                  topic: DecisionTopic.vehicles,
                  actor: person,
                ),
              ],
            ),
            EquipmentTooltip(
              type: person.equippedWeapon?.type,
              child: _fact(
                'Weapon',
                person.equippedWeapon == null
                    ? 'No equipped weapon'
                    : stripConsoleColors(
                        person.equippedWeapon!.equipTitle(full: true),
                      ),
              ),
            ),
            if (person.equippedWeapon?.type.usesAmmo == true)
              _fact(
                'Loaded ammunition',
                person.equippedWeapon!.ammo <= 0
                    ? 'Unloaded'
                    : '${person.equippedWeapon!.ammo} rounds · ${person.equippedWeapon!.loadedAmmoType?.name ?? 'Type not recorded'}',
              ),
            EquipmentTooltip(
              type: person.equippedClothing?.type,
              armor: person.equippedClothing?.armor,
              child: _fact(
                'Clothing',
                person.equippedClothing?.type.name ?? 'No equipped clothing',
              ),
            ),
            if (person.equippedClothing != null) ...[
              _fact(
                'Clothing condition',
                [
                  'Quality ${person.equippedClothing!.quality}',
                  if (person.equippedClothing!.bloody) 'Bloodstained',
                  if (person.equippedClothing!.damaged) 'Damaged',
                ].join(' · '),
              ),
              if (person.equippedClothing!.maxBodyArmor > 0 ||
                  person.equippedClothing!.maxHeadArmor > 0 ||
                  person.equippedClothing!.maxLimbArmor > 0)
                _fact(
                  'Armor',
                  '${person.equippedClothing!.armor?.name ?? 'Armor'} · Body ${person.equippedClothing!.bodyArmor}/${person.equippedClothing!.maxBodyArmor} · Head ${person.equippedClothing!.headArmor}/${person.equippedClothing!.maxHeadArmor}',
                ),
            ],
            _fact(
              'Spare ammunition',
              person.spareAmmo == null
                  ? 'None'
                  : stripConsoleColors(
                      person.spareAmmo!.equipTitle(full: true),
                    ),
            ),
            if (person.spareAmmo != null)
              _fact('Ammunition quantity', '${person.spareAmmo!.stackSize}'),
            if (person.car != null)
              _fact(
                'Vehicle',
                '${person.car!.fullName()}${person.isDriver ? ' · Driver' : ' · Passenger'}',
              ),
            if (person.hasWheelchair) _fact('Mobility aid', 'Wheelchair'),
          ]),
          _section('Attributes', Icons.tune, [
            for (final attribute in Attribute.values)
              AttributeTooltip(
                attribute: attribute,
                actor: person,
                child: _fact(
                  _capitalize(attribute.name),
                  '${person.attribute(attribute)}',
                ),
              ),
          ]),
        ),
      ],
    );
  }

  List<Widget> _injuries(Creature person) {
    final descriptions = [
      ...person.body.allSpecialInjuries(),
      for (final part in person.body.parts.where((part) => part.wounded))
        _partDescription(part),
    ];
    return [
      Text(
        descriptions.isEmpty ? 'No recorded injuries' : 'Recorded injuries',
        style: TextStyle(
          color: descriptions.isEmpty ? _muted : _red,
          fontWeight: FontWeight.w700,
        ),
      ),
      for (final description in descriptions)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(description, style: const TextStyle(color: _red)),
        ),
    ];
  }

  String _partDescription(BodyPart part) {
    final details = <String>[
      if (part.missing) 'Missing',
      if (part.shot) 'Shot',
      if (part.cut) 'Cut',
      if (part.bruised) 'Bruised',
      if (part.burned) 'Burned',
      if (part.torn) 'Torn',
      if (part.bleeding > 0) 'Bleeding (${part.bleeding})',
      if (!part.missing && part.relativeHealth < 1)
        '${(part.relativeHealth * 100).round()}% tissue health',
    ];
    return '${part.name} · ${details.join(', ')}';
  }

  Widget _skills() {
    final person = widget.person;
    final skills = Skill.values.toList()
      ..sort((a, b) {
        final level = person.skill(b).compareTo(person.skill(a));
        if (level != 0) return level;
        return a.displayName.compareTo(b.displayName);
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Skills & training',
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 14),
        for (final skill in skills)
          Padding(
            key: ValueKey('crew-dossier-skill:${skill.name}'),
            padding: const EdgeInsets.only(bottom: 20),
            child: SkillTooltip(
              skill: skill,
              actor: person,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    key: ValueKey('crew-dossier-skill-heading:${skill.name}'),
                    container: true,
                    label: '${skill.displayName}: level ${person.skill(skill)}',
                    child: ExcludeSemantics(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              skill.displayName,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${person.skill(skill)}',
                            key: ValueKey(
                              'crew-dossier-skill-level:${skill.name}',
                            ),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: _ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    skill.description,
                    style: const TextStyle(color: _muted, fontSize: 13),
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      SizedBox(
                        width: 72,
                        child: ExcludeSemantics(
                          child: LinearProgressIndicator(
                            value:
                                (person.skillXP(skill) /
                                        skillXpNeeded(person.skill(skill)))
                                    .clamp(0, 1),
                            minHeight: 2,
                            color: _muted.withValues(alpha: .5),
                            backgroundColor: _rule.withValues(alpha: .5),
                            semanticsLabel: '${skill.displayName} experience',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '${person.skillXP(skill)} / ${skillXpNeeded(person.skill(skill))} XP · Attribute cap ${person.skillCap(skill)}',
                          style: const TextStyle(color: _muted, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _record() {
    final person = widget.person;
    final charges = person.wantedForCrimes.entries.where(
      (entry) => entry.value > 0,
    );
    final convictions = person.pastConvictions.entries.where(
      (entry) => entry.value > 0,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _twoColumns(
          _section('Identity & service', Icons.badge_outlined, [
            _fact(
              'Code name',
              person.name.isEmpty ? 'Unnamed person' : person.name,
            ),
            if (person.properName.isNotEmpty) _fact('Name', person.properName),
            _fact('Age', '${person.age}'),
            _fact('Gender', _capitalize(person.gender.simplified.name)),
            _fact('Occupation', person.type.name),
            _fact('Political alignment', _capitalize(person.align.name)),
            _fact('Days since joining', '${person.daysSinceJoined}'),
            _fact('Reputation', '${person.juice} juice · ${person.title}'),
            if (person.boss != null) _fact('Recruited by', person.boss!.name),
            if (!person.alive)
              _fact('Days since death', '${person.daysSinceDeath}'),
          ]),
          _section('Legal record', Icons.balance, [
            DecisionGuideButton(topic: DecisionTopic.heat, actor: person),
            _fact('Heat', '${person.heat}'),
            if (charges.isEmpty)
              const Text(
                'No current wanted charges',
                style: TextStyle(color: _muted),
              ),
            for (final charge in charges)
              _fact(charge.key.wantedFor, '${charge.value}'),
            if (convictions.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text(
                'Past convictions',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              for (final conviction in convictions)
                _fact(conviction.key.wantedFor, '${conviction.value}'),
            ],
            if (person.sentence != 0)
              _fact(
                'Sentence',
                person.sentence < 0
                    ? 'Life in prison'
                    : '${person.sentence} months in prison',
              ),
            if (person.deathPenalty)
              const Text(
                'Death penalty',
                style: TextStyle(color: _red, fontWeight: FontWeight.w700),
              ),
          ]),
        ),
        const SizedBox(height: 24),
        const Text(
          'Portraits are stylized visual identities. The campaign record above supplies this person’s actual traits and history.',
          style: TextStyle(fontSize: 12, color: _muted),
        ),
      ],
    );
  }

  Widget _orderMechanics() {
    final person = widget.person;
    final panel = ActivityMechanicsPanel(
      mechanics: activityMechanics(
        person.activity.type,
        actor: person,
        activity: person.activity,
      ),
    );
    if (!widget.embedded) return panel;
    return ExpansionTile(
      key: const PageStorageKey('journal-profile-order-mechanics'),
      tilePadding: EdgeInsets.zero,
      dense: true,
      title: const Text('Order mechanics', style: JournalPalette.small),
      children: [panel],
    );
  }

  Widget _twoColumns(Widget left, Widget right) => LayoutBuilder(
    builder: (context, bounds) => bounds.maxWidth >= 650
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: left),
              const SizedBox(width: 28),
              Expanded(child: right),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [left, const SizedBox(height: 22), right],
          ),
  );

  Widget _section(String title, IconData icon, List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Icon(icon, size: 19, color: _teal),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
          ),
        ],
      ),
      const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Divider(height: 1, color: _rule),
      ),
      ...children,
    ],
  );

  Widget _fact(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    ),
  );

  Widget _tag(String label, {bool warning = false}) => widget.embedded
      ? Text(
          label,
          style: JournalPalette.small.copyWith(color: warning ? _red : _muted),
        )
      : Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: warning
                ? JournalPalette.danger.withValues(alpha: .08)
                : JournalPalette.inset,
            border: Border.all(
              color: warning
                  ? JournalPalette.danger.withValues(alpha: .3)
                  : _rule,
            ),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            label,
            style: TextStyle(color: warning ? _red : _ink, fontSize: 12),
          ),
        );

  Widget _footer() => Container(
    padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: _rule)),
    ),
    child: Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.end,
      children: [
        for (final action in widget.actions)
          FilledButton.icon(
            onPressed: !action.enabled
                ? null
                : () {
                    Navigator.of(context).pop();
                    action.onPressed();
                  },
            style: FilledButton.styleFrom(
              backgroundColor: _teal,
              foregroundColor: _paper,
            ),
            icon: Icon(action.icon, size: 18),
            label: Text(action.label),
          ),
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: OutlinedButton.styleFrom(foregroundColor: _ink),
          child: const Text('Close dossier'),
        ),
      ],
    ),
  );
}

String _capitalize(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';
