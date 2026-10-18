import 'package:flutter/material.dart' hide View;
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/engine/media_production_context.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/gamestate/time.dart';
import 'package:lcs_new_age/items/loot.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/politics/views.dart';

/// A request to open the original activity reader and prepare its order.
/// The directory itself never changes assignments or publishes evidence.
@immutable
class MediaProductionRequest {
  const MediaProductionRequest(this.person, this.activity);
  final Creature person;
  final ActivityType activity;
}

@immutable
class MediaEvidenceStock {
  const MediaEvidenceStock({
    required this.typeId,
    required this.name,
    required this.site,
    required this.quantity,
  });
  final String typeId;
  final String name;
  final Site site;
  final int quantity;
}

bool isGuardianAssignment(ActivityType type) =>
    type == ActivityType.writeGuardian || type == ActivityType.streamGuardian;

/// The same actor and local-studio requirements as activateRegulars/assignTask.
String? mediaProductionUnavailableReason(Creature person, ActivityType type) {
  if (!person.alive) return 'Deceased';
  if (!person.isLiberal) return 'Not active Liberal crew';
  if (person.sleeperAgent) return 'Sleeper agent: manage in Network';
  if (person.imprisoned) return 'In custody';
  if (person.hospitalized) return 'In hospital';
  if (person.vacationDaysLeft > 0) return 'Away on vacation';
  if (person.hidingDaysLeft != 0) return 'In hiding';
  if (!person.isActiveLiberal) return 'Unavailable for daily orders';
  if (person.squad?.activity.type != null &&
      person.squad!.activity.type != ActivityType.none) {
    return 'Squad has an active plan: review in People';
  }
  if (type == ActivityType.streamGuardian &&
      person.site?.compound.videoRoom != true) {
    return 'Needs a studio at this person’s current location';
  }
  return null;
}

/// This is informational: selection eligibility above remains source-owned.
String? mediaProductionDailyWarning(Creature person) {
  final unavailable = mediaProductionUnavailableReason(
    person,
    person.activity.type,
  );
  if (unavailable != null) return unavailable;
  if (person.activity.type == ActivityType.streamGuardian &&
      person.base?.compound.videoRoom != true) {
    return 'Home base has no studio; the daily update will clear streaming.';
  }
  if (person.site?.siege.underSiege == true &&
      person.site?.siege.lightsOff == true) {
    return 'Power cut during siege: the daily update will clear this order.';
  }
  return null;
}

/// Read only: unlike the monthly reader this does not consolidate stacks.
List<MediaEvidenceStock> mediaProductionEvidence() {
  final result = <MediaEvidenceStock>[];
  for (final site in game.sites.where(
    (site) => site.controller == SiteController.lcs,
  )) {
    for (final typeId in guardianSpecialEditionEvidenceIds) {
      final stock = site.loot.whereType<Loot>().where(
        (item) => item.typeName == typeId,
      );
      if (stock.isEmpty) continue;
      result.add(
        MediaEvidenceStock(
          typeId: typeId,
          name: stock.first.type.name,
          site: site,
          quantity: stock.fold(0, (count, item) => count + item.stackSize),
        ),
      );
    }
  }
  return List.unmodifiable(result);
}

String nextMediaProductionReview(DateTime date) {
  final next = DateTime(date.year, date.month + 1, 1);
  return '1 ${getMonth(next.month)} ${next.year}';
}

/// A discoverable planning flow around existing daily orders and month-end
/// special editions. Callbacks route to the real People/Bases/Stores controls.
class JournalMediaProductionView extends StatefulWidget {
  const JournalMediaProductionView({
    super.key,
    required this.onAssign,
    required this.onOpenPeople,
    required this.onOpenBases,
    required this.onOpenStores,
    this.onOpenArchive,
    this.headerArt,
    this.enabled = true,
  });
  final ValueChanged<MediaProductionRequest> onAssign;
  final VoidCallback onOpenPeople;
  final VoidCallback onOpenBases;
  final VoidCallback onOpenStores;
  final VoidCallback? onOpenArchive;
  final Widget? headerArt;
  final bool enabled;

  @override
  State<JournalMediaProductionView> createState() =>
      _JournalMediaProductionViewState();
}

class _JournalMediaProductionViewState
    extends State<JournalMediaProductionView> {
  int? _selectedId;

  Widget _card({required Widget child}) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: JournalPalette.card,
      border: Border.all(color: JournalPalette.rule),
      borderRadius: BorderRadius.circular(3),
    ),
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final people =
        game.pool
            .where(
              (person) =>
                  person.alive && person.isLiberal && !person.sleeperAgent,
            )
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    final selected =
        people.where((p) => p.id == _selectedId).firstOrNull ??
        people.where((p) => p.isActiveLiberal).firstOrNull ??
        people.firstOrNull;
    final producers = people.where(
      (p) => isGuardianAssignment(p.activity.type),
    );
    final evidence = mediaProductionEvidence();
    final publishers = guardianSpecialEditionPublishers(game.pool).toList();
    final influence =
        game.politics.backgroundInfluence.entries
            .where(
              (entry) => View.issues.contains(entry.key) && entry.value != 0,
            )
            .toList()
          ..sort((a, b) => b.value.abs().compareTo(a.value.abs()));
    final influenceTotal = influence.fold(0, (sum, entry) => sum + entry.value);
    final studios = game.sites.where(
      (site) =>
          site.controller == SiteController.lcs && site.compound.videoRoom,
    );
    return JournalSurface(
      key: const ValueKey('journal-media-production'),
      padding: const EdgeInsets.all(16),
      child: ListView(
        key: const ValueKey('media-production-scroll'),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox.square(
                dimension: 64,
                child:
                    widget.headerArt ??
                    const JournalIllustratedIcon(
                      icon: JournalIcon.media,
                      size: 64,
                    ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Liberal Guardian production',
                      style: JournalPalette.title,
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Give crew a daily writing or streaming order. '
                      'Collected evidence is a separate monthly decision.',
                      style: JournalPalette.body,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '1 · Plan daily production',
                  style: JournalPalette.heading,
                ),
                const SizedBox(height: 5),
                const Text(
                  'Confirmed standing orders run as days advance. Writing uses '
                  'Writing; streaming uses Persuasion and requires a local '
                  'studio. Both also use Law, Science, Religion and Business. '
                  'Neither has an activity fee or needs secret documents. '
                  'Streaming multiplies the daily influence calculation by four.',
                  style: JournalPalette.body,
                ),
                const SizedBox(height: 9),
                if (producers.isEmpty)
                  const Text(
                    'No crew currently assigned to writing or streaming.',
                    key: ValueKey('media-production-no-producers'),
                    style: JournalPalette.small,
                  )
                else
                  for (final person in producers)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '${person.name} · '
                        '${person.activity.type == ActivityType.writeGuardian ? 'Writing' : 'Streaming'}'
                        '\n${person.location?.getName(includeCity: true) ?? 'In hiding'}'
                        '\n${mediaProductionDailyWarning(person) ?? 'Standing daily order'}',
                        key: ValueKey('media-producer:${person.id}'),
                        style: JournalPalette.body,
                      ),
                    ),
                const Divider(height: 20),
                if (people.isEmpty)
                  const Text(
                    'No active crew to assign. Open People to review recruits and returnees.',
                    style: JournalPalette.body,
                  )
                else ...[
                  DropdownButtonFormField<int>(
                    key: const ValueKey('media-production-person'),
                    initialValue: selected?.id,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Choose a person',
                    ),
                    items: [
                      for (final person in people)
                        DropdownMenuItem(
                          value: person.id,
                          child: Text(
                            person.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: widget.enabled
                        ? (id) => setState(() => _selectedId = id)
                        : null,
                  ),
                  const SizedBox(height: 7),
                  if (selected != null) ...[
                    Text(
                      '${selected.location?.getName(includeCity: true) ?? 'In hiding'}'
                      ' · Current: ${selected.activity.description}',
                      style: JournalPalette.small,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Writing ${selected.skill(Skill.writing)} · '
                      'Persuasion ${selected.skill(Skill.persuasion)}\n'
                      'Law ${selected.skill(Skill.law)} · '
                      'Science ${selected.skill(Skill.science)} · '
                      'Religion ${selected.skill(Skill.religion)} · '
                      'Business ${selected.skill(Skill.business)}',
                      key: const ValueKey('media-production-person-skills'),
                      style: JournalPalette.small,
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 9,
                      runSpacing: 7,
                      children: [
                        _assignButton(
                          selected,
                          ActivityType.writeGuardian,
                          'Prepare writing order',
                        ),
                        _assignButton(
                          selected,
                          ActivityType.streamGuardian,
                          'Prepare streaming order',
                        ),
                      ],
                    ),
                    if (mediaProductionUnavailableReason(
                          selected,
                          ActivityType.writeGuardian,
                        )
                        case final String reason)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(reason, style: JournalPalette.small),
                      ),
                    if (mediaProductionUnavailableReason(
                          selected,
                          ActivityType.streamGuardian,
                        )
                        case final String reason)
                      if (reason !=
                          mediaProductionUnavailableReason(
                            selected,
                            ActivityType.writeGuardian,
                          ))
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(reason, style: JournalPalette.small),
                        ),
                    const SizedBox(height: 5),
                    const Text(
                      'Review and confirm the prepared order in Organisation.',
                      style: JournalPalette.small,
                    ),
                  ],
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 9,
                  runSpacing: 7,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('media-production-people'),
                      onPressed: widget.enabled ? widget.onOpenPeople : null,
                      icon: const Icon(Icons.people_outline, size: 18),
                      label: const Text('Open People'),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('media-production-bases'),
                      onPressed: widget.enabled ? widget.onOpenBases : null,
                      icon: const Icon(Icons.home_outlined, size: 18),
                      label: const Text('Manage studios in Bases'),
                    ),
                  ],
                ),
                Text(
                  studios.isEmpty
                      ? 'No LCS location has a studio. Writing needs no studio.'
                      : 'Studios: ${studios.map((s) => s.getName(includeCity: true)).join('; ')}. '
                            'Crew must be at a studio to choose streaming; their home base '
                            'must also have one for the daily order to continue.',
                  style: JournalPalette.small,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '2 · Follow the influence you build',
                  style: JournalPalette.heading,
                ),
                const SizedBox(height: 5),
                Text(
                  'Daily posts and streams add background influence on a random '
                  'issue. They do not create a separate archived article each day. '
                  'The next monthly opinion update is ${nextMediaProductionReview(game.date)}: '
                  'accumulated influence and sleeper work compete with '
                  'Conservative media and a random roll. An opinion gain is not '
                  'guaranteed.',
                  key: const ValueKey('media-production-feedback-loop'),
                  style: JournalPalette.body,
                ),
                const SizedBox(height: 9),
                Text(
                  'Current accumulated influence: $influenceTotal net power',
                  key: const ValueKey('media-production-influence-total'),
                  style: JournalPalette.heading,
                ),
                const SizedBox(height: 4),
                const Text(
                  'This includes all contributing activities and influence carried '
                  'from earlier months. Power is not an article count or a '
                  'percentage-point change. After the monthly update, about 66% '
                  'of each issue’s background influence carries forward.',
                  style: JournalPalette.small,
                ),
                const SizedBox(height: 7),
                if (influence.isEmpty)
                  const Text(
                    'No background influence accumulated yet. Confirm a media '
                    'order and advance a day to begin.',
                    key: ValueKey('media-production-no-influence'),
                    style: JournalPalette.body,
                  ),
                if (widget.onOpenArchive != null) ...[
                  const SizedBox(height: 7),
                  OutlinedButton.icon(
                    key: const ValueKey('media-production-archive'),
                    onPressed: widget.enabled ? widget.onOpenArchive : null,
                    icon: const Icon(Icons.newspaper_outlined, size: 18),
                    label: const Text('Review Archive & opinion'),
                  ),
                ],
                if (influence.isNotEmpty)
                  Material(
                    color: Colors.transparent,
                    child: ExpansionTile(
                      key: PageStorageKey(
                        'media-production-influence-breakdown:${game.gameState.uniqueGameId}',
                      ),
                      title: Text(
                        'Issue breakdown (${influence.length})',
                        style: JournalPalette.body,
                      ),
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(bottom: 8),
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final entry in influence)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 3),
                                child: Text(
                                  '${entry.key.label}: ${entry.value > 0 ? '+' : ''}${entry.value} power',
                                  key: ValueKey(
                                    'media-influence:${entry.key.name}',
                                  ),
                                  style: JournalPalette.small,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '3 · Keep evidence for a special edition',
                  style: JournalPalette.heading,
                ),
                const SizedBox(height: 5),
                Text(
                  'Next monthly decision: ${nextMediaProductionReview(game.date)}. '
                  'When evidence is available and you advance into the new month, '
                  'the game automatically asks '
                  'whether to publish one evidence type held at an LCS-controlled '
                  'location. Publishing consumes one copy immediately; declining '
                  'keeps it for later. The publication decision comes before '
                  'sleepers carry out their monthly orders, so files they obtain '
                  'then are available for a later edition. '
                  'The decision is skipped while disbanding.',
                  key: const ValueKey('media-production-monthly-timing'),
                  style: JournalPalette.body,
                ),
                const SizedBox(height: 7),
                Text(
                  '${publishers.length} active '
                  '${publishers.length == 1 ? 'contributor' : 'contributors'} '
                  'currently assigned for special-edition reach.',
                  key: const ValueKey('media-production-publisher-count'),
                  style: JournalPalette.heading,
                ),
                const SizedBox(height: 4),
                const Text(
                  'Keep media staff available and assigned when the month starts. '
                  'For most exposés, reach uses the number of contributors plus '
                  'their best Writing roll, or Persuasion roll minus 5 for a '
                  'streamer. More skilled staff can improve reception; publishing '
                  'without staff is possible but usually has little impact. '
                  'The published story and its recorded opinion effects appear '
                  'in Archive. Some secrets can provoke retaliation.',
                  key: ValueKey('media-production-edition-staffing'),
                  style: JournalPalette.body,
                ),
                const SizedBox(height: 9),
                if (evidence.isEmpty)
                  const Text(
                    'No publishable evidence stored at LCS-controlled locations. '
                    'Recovered files must reach your stores to appear here.',
                    key: ValueKey('media-production-no-evidence'),
                    style: JournalPalette.small,
                  )
                else
                  for (final stock in evidence)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Text(
                        '${stock.name} · ${stock.quantity} '
                        '${stock.quantity == 1 ? 'copy' : 'copies'}'
                        '\n${stock.site.getName(includeCity: true)}',
                        key: ValueKey(
                          'media-evidence:${stock.site.id}:${stock.typeId}',
                        ),
                        style: JournalPalette.body,
                      ),
                    ),
                const SizedBox(height: 7),
                OutlinedButton.icon(
                  key: const ValueKey('media-production-stores'),
                  onPressed: widget.enabled ? widget.onOpenStores : null,
                  icon: const Icon(Icons.inventory_2_outlined, size: 18),
                  label: const Text('Open Stores'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _assignButton(Creature person, ActivityType type, String label) {
    final reason = mediaProductionUnavailableReason(person, type);
    return Tooltip(
      message: reason ?? 'Prepare an order for review and confirmation',
      child: FilledButton(
        key: ValueKey('media-production-assign:${type.name}'),
        onPressed: widget.enabled && reason == null
            ? () {
                if (!game.pool.contains(person) ||
                    mediaProductionUnavailableReason(person, type) != null) {
                  return;
                }
                widget.onAssign(MediaProductionRequest(person, type));
              }
            : null,
        child: Text(label),
      ),
    );
  }
}
