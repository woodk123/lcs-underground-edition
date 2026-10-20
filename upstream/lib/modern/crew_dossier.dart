import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/modern/age_help.dart';
import 'package:lcs_new_age/modern/catalogue_art.dart';
import 'package:lcs_new_age/modern/character_attributes.dart';
import 'package:lcs_new_age/modern/crew_command_panel.dart';
import 'package:lcs_new_age/modern/crew_injury_panel.dart';
import 'package:lcs_new_age/modern/crew_portrait.dart';
import 'package:lcs_new_age/modern/decision_help.dart';
import 'package:lcs_new_age/modern/equipment_help.dart';
import 'package:lcs_new_age/modern/journal_preferences.dart';
import 'package:lcs_new_age/modern/journal_recruitment.dart';
import 'package:lcs_new_age/modern/journal_shortcuts.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/juice_indicator.dart';
import 'package:lcs_new_age/modern/legal_status.dart';
import 'package:lcs_new_age/modern/mechanics_help.dart';
import 'package:lcs_new_age/modern/operation_history_panel.dart';
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
    final preferences = JournalPreferences.of(context);
    final compact = this.compact || preferences.compact;
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
                        LegalStatusSummary(person: person),
                        const SizedBox(height: 10),
                        CharacterRecruitmentMeetings(person: person),
                        const SizedBox(height: 10),
                        CharacterAttributes(person: person),
                        const SizedBox(height: 12),
                        JuiceProgress(person: person),
                        const SizedBox(height: 9),
                        CrewCommandPanel(person: person),
                        const SizedBox(height: 12),
                        _inlineFact('Age', '${person.age}'),
                        const SizedBox(height: 12),
                        _inlineFact(
                          'Personal assignment',
                          person.activity.description,
                        ),
                        if (preferences.showGuidance)
                          Text(
                            assignment.summary,
                            style: const TextStyle(color: _muted, fontSize: 11),
                          ),
                        JuiceActivityHint(
                          person: person,
                          activity: person.activity.type,
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
                        if (preferences.showGuidance)
                          AgeEffects(person: person),
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
    this.pageShortcuts = const [],
  });

  final Creature person;
  final List<CrewDossierAction> actions;
  final bool embedded;
  final int page;
  final ValueChanged<int>? onPage;

  /// Enabled page keys supplied by the current original profile reader.
  final List<String> pageShortcuts;

  @override
  State<CrewDossier> createState() => _CrewDossierState();
}

class _CrewDossierState extends State<CrewDossier> {
  bool get _compact => JournalPreferences.of(context).compact;
  bool get _showGuidance => JournalPreferences.of(context).showGuidance;
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
                                      padding: EdgeInsets.all(
                                        _compact ? 12 : 24,
                                      ),
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
                  if (widget.onPage != null &&
                      widget.pageShortcuts.any(
                        (key) => const {'Up', 'Down'}.contains(key),
                      ))
                    Semantics(
                      key: const ValueKey('journal-profile-page-shortcuts'),
                      label: 'More info',
                      hint:
                          'Keyboard shortcuts: ${widget.pageShortcuts.where((key) => const {'Up', 'Down'}.contains(key)).map(journalShortcutSpokenLabel).join(', ')}',
                      excludeSemantics: true,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final key in widget.pageShortcuts.where(
                              (key) => const {'Up', 'Down'}.contains(key),
                            )) ...[
                              JournalShortcutBadge(shortcut: key),
                              const SizedBox(width: 5),
                            ],
                            const Text(
                              'More info',
                              style: JournalPalette.small,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.all(_compact ? 10 : 16),
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
    final short = !widget.embedded && MediaQuery.sizeOf(context).height < 700;
    final textScale = MediaQuery.textScalerOf(context).scale(15) / 15;
    if (_compact ||
        !widget.embedded &&
            (short || MediaQuery.sizeOf(context).width / textScale < 500)) {
      return Padding(
        key: const ValueKey('crew-dossier-compact-header'),
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CrewPortrait(person: person, size: 64, borderRadius: 3),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    person.name.isEmpty ? 'Unnamed person' : person.name,
                    key: const ValueKey('crew-dossier-name'),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      height: 1.12,
                    ),
                  ),
                  if (person.properName.isNotEmpty &&
                      person.properName != person.name)
                    Text(person.properName, style: JournalPalette.small),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      MechanicsTooltip(
                        message: ageHelp(person),
                        child: Text(
                          '${person.title} · Age ${person.age}',
                          style: JournalPalette.small.copyWith(color: _teal),
                        ),
                      ),
                      JuiceBadge(person: person, compact: true),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      _capitalize(person.align.name),
                      person.type.name,
                      if (!person.alive) 'Deceased',
                      if (person.sleeperAgent) 'Sleeper agent',
                      if (person.kidnapped) 'Captive',
                    ].join(' · '),
                    style: JournalPalette.small,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
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
                        const SizedBox(height: 4),
                        JuiceProgress(person: person),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _tag(_capitalize(person.align.name)),
                            _tag(person.type.name),
                            MechanicsTooltip(
                              message: ageHelp(person),
                              child: _tag('Age ${person.age}'),
                            ),
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
        CharacterRecruitmentMeetings(person: person),
        const SizedBox(height: 12),
        CharacterAttributes(person: person),
        const SizedBox(height: 12),
        if (_compact) ...[_compactDecisionFacts(), const SizedBox(height: 8)],
        CrewCommandPanel(person: person),
        SizedBox(height: _compact ? 10 : 18),
        _section('Condition', Icons.favorite_border, [
          CrewInjuryPanel(person: person),
          const SizedBox(height: 10),
          DecisionGuideButton(topic: DecisionTopic.health, actor: person),
        ]),
        const SizedBox(height: 22),
        _twoColumns(
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
          _section('Equipment', Icons.inventory_2_outlined, [
            if (!_compact)
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  for (final id in [
                    person.equippedWeapon?.type.idName,
                    person.equippedClothing?.type.idName,
                    person.spareAmmo?.type.idName,
                  ])
                    if (equipmentArtwork(id) case final art?)
                      CatalogueIllustration(art: art, width: 92, height: 60),
                ],
              ),
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
            if (!_compact && person.car != null)
              if (vehicleArtwork(person.car!.typeName) case final art?)
                Align(
                  alignment: Alignment.centerLeft,
                  child: CatalogueIllustration(
                    art: art,
                    width: 160,
                    height: 80,
                  ),
                ),
            if (person.car != null)
              _fact(
                'Vehicle',
                '${person.car!.fullName()}${person.isDriver ? ' · Driver' : ' · Passenger'}',
              ),
            if (person.hasWheelchair) _fact('Mobility aid', 'Wheelchair'),
          ]),
        ),
        const SizedBox(height: 22),
        if (_showGuidance) AgeEffects(person: person),
      ],
    );
  }

  Widget _compactDecisionFacts() {
    final person = widget.person;
    return Container(
      key: const ValueKey('crew-decision-summary'),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: JournalPalette.inset,
        border: Border.all(color: _rule),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${person.alive ? '${person.blood}/${person.maxBlood} blood' : 'Deceased'} · ${person.location?.getName(includeCity: true) ?? 'Location unknown'}',
            style: JournalPalette.small,
          ),
          Text(
            'Personal assignment: ${person.activity.description}',
            style: JournalPalette.small,
          ),
          if (person.squad != null)
            Text(
              'Squad: ${person.squad!.name} · ${person.squad!.activity.description}',
              style: JournalPalette.small,
            ),
          Text(
            'Weapon: ${stripConsoleColors(person.weapon.equipTitle(full: true))}'
            '${person.weapon.type.usesAmmo ? ' · ${person.weapon.ammo} loaded · ${person.weapon.acceptableAmmo.contains(person.spareAmmo?.type) ? person.spareAmmo?.stackSize ?? 0 : 0} compatible spare rounds' : ''}',
            style: JournalPalette.small,
          ),
        ],
      ),
    );
  }

  Future<void> _showSkillReference(List<Skill> skills) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Skill descriptions and training rules'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final skill in skills) ...[
              Text(
                '${skill.displayName} ${widget.person.skill(skill)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(skillHelp(skill, actor: widget.person)),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    ),
  );

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
        Row(
          children: [
            const Expanded(
              child: Text(
                'Skills & training',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              key: const ValueKey('crew-dossier-skill-reference'),
              tooltip: 'Skill descriptions and training rules',
              onPressed: () => _showSkillReference(skills),
              icon: const Icon(Icons.info_outline, size: 18),
            ),
          ],
        ),
        SizedBox(height: _compact ? 6 : 14),
        LayoutBuilder(
          builder: (context, bounds) {
            final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
            final columns = (bounds.maxWidth / ((_compact ? 200 : 240) * scale))
                .floor()
                .clamp(1, 3);
            final spacing = _compact ? 14.0 : 22.0;
            final width = (bounds.maxWidth - (columns - 1) * spacing) / columns;
            return Wrap(
              spacing: spacing,
              children: [
                for (final skill in skills)
                  SizedBox(width: width, child: _skillCard(skill)),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _skillCard(Skill skill) {
    final person = widget.person;
    return Padding(
      key: ValueKey('crew-dossier-skill:${skill.name}'),
      padding: EdgeInsets.only(bottom: _compact ? 8 : 20),
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
                      fit: _compact ? FlexFit.tight : FlexFit.loose,
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
                      key: ValueKey('crew-dossier-skill-level:${skill.name}'),
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
            if (_showGuidance) ...[
              const SizedBox(height: 2),
              Text(
                skill.description,
                style: const TextStyle(color: _muted, fontSize: 13),
              ),
            ],
            SizedBox(height: _compact ? 3 : 7),
            Row(
              children: [
                if (!_compact)
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
                if (!_compact) const SizedBox(width: 8),
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
            _fact(
              'Juice · experience & standing',
              '${person.juice} · ${person.title}',
            ),
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
            LegalStatusExplanation(person: person),
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
        OperationHistoryPanel(person: person),
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
      Padding(
        padding: EdgeInsets.symmetric(vertical: _compact ? 6 : 12),
        child: const Divider(height: 1, color: _rule),
      ),
      ...children,
    ],
  );

  Widget _fact(String label, String value) => Padding(
    padding: EdgeInsets.only(bottom: _compact ? 5 : 10),
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
