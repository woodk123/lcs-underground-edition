import 'package:flutter/material.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/gamestate/squad.dart';
import 'package:lcs_new_age/location/siege.dart' as siege;
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/modern/crew_portrait.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/mechanics_help.dart';

const _ink = JournalPalette.ink;
const _paper = JournalPalette.page;
const _muted = JournalPalette.muted;
const _teal = JournalPalette.olive;
const _red = JournalPalette.danger;
const _rule = JournalPalette.rule;

/// A compact view of the live campaign. Only commands exposed by this exact
/// console frame can issue orders; portraits and explanations are read-only.
class HeadquartersView extends StatefulWidget {
  const HeadquartersView({
    super.key,
    required this.console,
    required this.onAction,
    required this.onInspect,
    this.showFirstSteps = true,
    this.onDismissFirstSteps,
  });

  final Console console;
  final ValueChanged<String> onAction;
  final ValueChanged<Creature> onInspect;
  final bool showFirstSteps;
  final VoidCallback? onDismissFirstSteps;

  @override
  State<HeadquartersView> createState() => _HeadquartersViewState();
}

class _HeadquartersViewState extends State<HeadquartersView> {
  ConsoleAction? _action(String key) => widget.console.actions
      .where((action) => action.key.toLowerCase() == key.toLowerCase())
      .firstOrNull;

  VoidCallback? _command(ConsoleAction? action, int revision) {
    if (action == null || !action.enabled) return null;
    return () {
      if (widget.console.revision.value == revision &&
          widget.console.actions.contains(action) &&
          action.enabled) {
        widget.onAction(action.key);
      }
    };
  }

  @override
  Widget build(BuildContext context) {
    final revision = widget.console.revision.value;
    final location = game.activeSquad?.site ?? game.activeSafehouse;
    final danger = location?.siege.underSiege == true;
    final queued = game.squads
        .where((squad) => squad.activity.type == ActivityType.visit)
        .toList();
    final crew =
        game.activeSquad?.members ??
        game.pool.where((person) => person.isActiveLiberal).toList();
    final wait = _action('w');
    final cancel = _action('c');
    final save = _action('x');
    final switchingToSiege =
        game.pool.any((person) => person.site?.siege.underAttack == true) &&
        !danger;
    final used = <String>{'a', 'f', 'e', 'w', 'x', 's', 'r'};
    if (cancel?.enabled == true) used.add('c');
    if (danger && _action('g') != null) used.add('g');
    for (final person in crew) {
      final selection = _selection(person);
      if (selection != null) used.add(selection.key.toLowerCase());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 880;
        final padding = constraints.maxWidth < 600 ? 16.0 : 22.0;
        final roster = _roster(crew, revision);
        final overview = _overview(location, queued, revision);
        return SingleChildScrollView(
          key: const ValueKey('headquarters-scroll'),
          padding: EdgeInsets.all(padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 18,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: constraints.maxWidth < 600
                        ? constraints.maxWidth - padding * 2
                        : 245,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('DAILY BRIEFING', style: _eyebrow),
                        const Text(
                          'Headquarters',
                          style: TextStyle(
                            fontSize: 27,
                            fontWeight: FontWeight.w700,
                            color: _ink,
                            height: 1.25,
                          ),
                        ),
                        Text(
                          location?.getName(includeCity: true) ??
                              'Your movement',
                          style: const TextStyle(fontSize: 12, color: _muted),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (wait != null)
                    Tooltip(
                      message: switchingToSiege
                          ? 'Selects the threatened safehouse. No time passes.'
                          : 'Advance one day: carry out squad orders, process '
                                'daily assignments and see their results.',
                      child: FilledButton.icon(
                        key: const ValueKey('hq-commit'),
                        style: FilledButton.styleFrom(
                          backgroundColor: _red,
                          minimumSize: const Size(48, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                        ),
                        onPressed: _command(wait, revision),
                        icon: Icon(
                          switchingToSiege
                              ? Icons.warning_amber_rounded
                              : Icons.arrow_forward,
                          size: 18,
                        ),
                        label: Text(_clean(wait.label)),
                      ),
                    ),
                  if (cancel?.enabled == true)
                    _button(
                      cancel!,
                      revision,
                      icon: Icons.cancel_outlined,
                      explanation:
                          'Cancel ${game.activeSquad?.name ?? 'the selected squad'}’s '
                          'departure. Other squads keep their orders; no time passes.',
                    ),
                  if (save != null)
                    _button(
                      save,
                      revision,
                      label: 'Save & exit',
                      icon: Icons.save_outlined,
                      explanation:
                          'Save this campaign, then return to the title screen.',
                    ),
                ],
              ),
              if (danger) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _red.withValues(alpha: .08),
                    border: Border.all(color: _red.withValues(alpha: .35)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 16,
                    runSpacing: 6,
                    children: [
                      Text(
                        location!.siege.underAttack
                            ? 'Safehouse under attack — respond now.'
                            : 'Safehouse surrounded — a siege is in progress.',
                        style: const TextStyle(
                          color: _red,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      if (wait == null)
                        const Text(
                          'Resolve the attack before advancing time.',
                          style: TextStyle(fontSize: 12, color: _ink),
                        ),
                      if (_action('g') case final giveUp?)
                        _button(giveUp, revision),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  if (_action('a') case final action?)
                    _quickAction(
                      action,
                      revision,
                      'Daily assignments',
                      Icons.fact_check_outlined,
                      'Choose individual work: raise funds, recruit, train or '
                          'build influence. Assignments run when the day advances.'
                          '${action.enabled ? '' : '\nNo active crew member is free of a squad order. Review crew availability or cancel a departure.'}',
                    ),
                  if (_action('f') case final action?)
                    _quickAction(
                      action,
                      revision,
                      danger ? _clean(action.label) : 'Plan an operation',
                      danger ? Icons.security : Icons.explore_outlined,
                      danger
                          ? 'Use the original siege response options for this '
                                'safehouse.${action.enabled ? '' : '\nSelect a nonempty squad first.'}'
                          : 'Inspect city locations and queue a visit for the '
                                'selected squad. Travel begins when the day advances.'
                                '${action.enabled ? '' : '\nSelect a nonempty squad first.'}',
                    ),
                  if (_action('e') case final action?)
                    _quickAction(
                      action,
                      revision,
                      'Equipment',
                      Icons.backpack_outlined,
                      'Distribute the current location’s equipment to the squad. '
                          'Changing equipment does not advance time.'
                          '${action.enabled ? '' : '\nSelect a nonempty squad first.'}',
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 7, child: roster),
                    const SizedBox(width: 20),
                    Expanded(flex: 4, child: overview),
                  ],
                )
              else ...[
                roster,
                const SizedBox(height: 18),
                overview,
              ],
              const SizedBox(height: 10),
              ExpansionTile(
                key: const PageStorageKey('hq-more-commands'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 12),
                title: const Text(
                  'More headquarters commands',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Squads, locations, vehicles, politics and other controls',
                  style: TextStyle(fontSize: 11, color: _muted),
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final action in widget.console.actions.where(
                          (action) => !used.contains(action.key.toLowerCase()),
                        ))
                          _button(action, revision),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  ConsoleAction? _selection(Creature person) => widget.console.actions
      .where(
        (action) =>
            action.entityType == 'person' &&
            action.entityId == person.id.toString(),
      )
      .firstOrNull;

  Widget _roster(List<Creature> crew, int revision) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              game.activeSquad?.name.isNotEmpty == true
                  ? '${game.activeSquad!.name} · ${crew.length} crew'
                  : 'Available crew · ${crew.length}',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
            ),
          ),
          if (_action('r') case final review?)
            TextButton(
              key: const ValueKey('hq-manage-crew'),
              onPressed: _command(review, revision),
              child: const Text(
                'Manage squads',
                style: TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
      if (game.activeSquad?.activity.type == ActivityType.visit)
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            'Squad visit overrides individual daily tasks on the next day.',
            style: TextStyle(fontSize: 12, color: _teal),
          ),
        ),
      if (crew.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Text(
            'No active crew available. Review people and squads to see who is '
            'away, hospitalized or assigned elsewhere.',
            style: TextStyle(color: _muted, fontSize: 13),
          ),
        ),
      for (final person in crew) _crewRow(person, revision),
    ],
  );

  Widget _crewRow(Creature person, int revision) {
    final order = person.squad?.activity;
    final overridden = order != null && order.type != ActivityType.none;
    final assignment = overridden ? order : person.activity;
    final bleeding = person.body.parts.any((part) => part.bleeding > 0);
    final injured =
        person.blood < person.maxBlood ||
        person.body.parts.any((part) => part.wounded);
    final selection = _selection(person);
    final selected = game.activeSquadMember?.id == person.id;
    final mechanics = activityMechanics(
      assignment.type,
      actor: person,
      activity: assignment,
    );
    final explanation = [
      mechanics.summary,
      if (mechanics.factors.isNotEmpty) mechanics.factors,
      if (mechanics.risk.isNotEmpty) mechanics.risk,
      mechanics.timing,
      if (overridden && person.activity.type != order.type)
        'Replaces individual task: ${person.activity.description}.',
    ].join('\n');
    return Container(
      key: ValueKey('hq-crew:${person.id}'),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .62),
        border: Border.all(color: selected ? _teal : _rule),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Inspect ${person.name}',
            child: InkWell(
              key: ValueKey('hq-portrait:${person.id}'),
              onTap: () => widget.onInspect(person),
              borderRadius: BorderRadius.circular(10),
              child: CrewPortrait(person: person, size: 44, borderRadius: 10),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  person.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: _ink,
                  ),
                ),
                Tooltip(
                  message: explanation,
                  child: Text(
                    assignment.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: overridden ? _teal : _muted,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message:
                'Blood ${person.blood} of ${person.maxBlood}. '
                'Inspect the dossier for wounds, healing and health details.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${person.blood}/${person.maxBlood} blood',
                  style: TextStyle(
                    color: injured ? _red : _muted,
                    fontSize: 11,
                  ),
                ),
                if (bleeding || injured)
                  Text(
                    bleeding ? 'Bleeding' : 'Injured',
                    style: const TextStyle(
                      color: _red,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            key: ValueKey('hq-dossier:${person.id}'),
            onPressed: () => widget.onInspect(person),
            tooltip: 'Dossier: ${person.name}',
            icon: const Icon(Icons.person_search_outlined, size: 19),
          ),
          if (selection != null)
            IconButton(
              key: ValueKey('hq-select:${person.id}'),
              onPressed: _command(selection, revision),
              tooltip: selected
                  ? 'Open original record for ${person.name}'
                  : 'Select ${person.name} in squad',
              icon: Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 18,
                color: selected ? _teal : _muted,
              ),
            ),
        ],
      ),
    );
  }

  Widget _overview(Site? location, List<Squad> queued, int revision) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: _ink,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                'assets/modern/safehouse.webp',
                fit: BoxFit.cover,
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: _ink.withValues(alpha: .82),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'THE MOVEMENT',
                    style: TextStyle(
                      color: Color(0xFFC5D4C6),
                      fontSize: 10,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    game.slogan,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _paper, fontSize: 13),
                  ),
                  if (_action('s') case final slogan?)
                    TextButton(
                      key: const ValueKey('hq-command:s'),
                      style: TextButton.styleFrom(
                        foregroundColor: _paper,
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(48, 32),
                      ),
                      onPressed: _command(slogan, revision),
                      child: const Text(
                        'Change slogan',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      if (location != null) ...[
        const SizedBox(height: 12),
        Text(
          'Heat ${location.heat} · Protection ${location.heatProtection}',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: location.heat > location.heatProtection ? _red : _ink,
          ),
        ),
        const SizedBox(height: 3),
        const Text(
          'Raw attention and secrecy points, not percentages. Heat above '
          'protection allows police to search for this safehouse.',
          style: TextStyle(fontSize: 11, color: _muted, height: 1.4),
        ),
        if (location.upgradable && siege.numberEating(location) > 0)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              siege.foodDaysLeft(location) > 0
                  ? 'Food: ${siege.foodDaysLeft(location)} days for '
                        '${siege.numberEating(location)} people'
                  : 'Insufficient food stores for '
                        '${siege.numberEating(location)} people',
              style: TextStyle(
                fontSize: 12,
                color: siege.foodDaysLeft(location) > 3 ? _muted : _red,
              ),
            ),
          ),
      ],
      const SizedBox(height: 14),
      Text(
        queued.isEmpty ? 'No visits queued' : '${queued.length} visits queued',
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: _ink,
        ),
      ),
      const SizedBox(height: 4),
      if (queued.isEmpty)
        const Text(
          'Daily assignments run on the next day. Inspecting crew and '
          'locations does not advance time.',
          style: TextStyle(fontSize: 12, color: _muted, height: 1.4),
        )
      else ...[
        for (final squad in queued)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              '${squad.name} → '
              '${squad.activity.location?.getName(includeCity: true) ?? squad.activity.description}'
              '\nNext day · ${squad.members.length} crew',
              style: const TextStyle(fontSize: 12, color: _teal, height: 1.4),
            ),
          ),
        const Text(
          'Squad visits replace individual daily tasks. A closed or besieged '
          'destination cancels departure; cars and travel funds are checked '
          'when the squad leaves.',
          style: TextStyle(fontSize: 11, color: _muted, height: 1.4),
        ),
      ],
      if (widget.showFirstSteps && game.pool.length <= 3) ...[
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: _teal.withValues(alpha: .07),
            borderRadius: BorderRadius.circular(6),
          ),
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Text(
                  'Start with fundraising or community work, then advance '
                  'the day to see results. Recruit before risky operations.',
                  style: TextStyle(fontSize: 12, color: _teal, height: 1.4),
                ),
              ),
              if (widget.onDismissFirstSteps != null)
                IconButton(
                  tooltip: 'Dismiss first steps',
                  onPressed: widget.onDismissFirstSteps,
                  icon: const Icon(Icons.close, size: 17),
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  padding: EdgeInsets.zero,
                ),
            ],
          ),
        ),
      ],
    ],
  );

  Widget _quickAction(
    ConsoleAction action,
    int revision,
    String label,
    IconData icon,
    String explanation,
  ) => _button(
    action,
    revision,
    label: label,
    icon: icon,
    explanation: explanation,
  );

  Widget _button(
    ConsoleAction action,
    int revision, {
    String? label,
    IconData? icon,
    String? explanation,
  }) {
    final button = OutlinedButton.icon(
      key: ValueKey('hq-command:${action.key}'),
      onPressed: _command(action, revision),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 40),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        side: const BorderSide(color: _rule),
      ),
      icon: icon == null ? const SizedBox.shrink() : Icon(icon, size: 17),
      label: Text(
        label ?? _clean(action.label),
        style: const TextStyle(fontSize: 12),
      ),
    );
    return explanation == null
        ? button
        : Tooltip(message: explanation, child: button);
  }
}

const _eyebrow = TextStyle(
  fontSize: 10,
  letterSpacing: 1.5,
  fontWeight: FontWeight.w700,
  color: _muted,
);

String _clean(String text) {
  var label = stripConsoleColors(text).trim();
  if (label.startsWith('(') && label.endsWith(')')) {
    label = label.substring(1, label.length - 1);
  }
  return label.replaceFirst(RegExp(r'^\s*\S+\s+[-–—]\s*'), '').trim();
}
