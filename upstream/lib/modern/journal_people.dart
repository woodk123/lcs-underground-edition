import 'package:flutter/material.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/modern/crew_portrait.dart';
import 'package:lcs_new_age/modern/journal_recruitment.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/personnel_directory.dart';
import 'package:lcs_new_age/politics/alignment.dart' as politics;

enum JournalPeopleScope { people, leadership, captives }

/// These readers deliberately mirror the original handlers without changing
/// assignments, contacts, locations, time or random state.
List<Creature> captiveAssignedTenders(
  Creature captive,
  Iterable<Creature> people,
) => people
    .where(
      (person) =>
          person.alive &&
          person.activity.type == ActivityType.interrogation &&
          person.activity.idInt == captive.id,
    )
    .toList();

List<Creature> captivePresentTenders(
  Creature captive,
  Iterable<Creature> people,
) => captiveAssignedTenders(captive, people)
    .where(
      (person) =>
          person.location != null && person.location == captive.location,
    )
    .toList();

List<Creature> captiveTenderCandidates(
  Creature captive,
  Iterable<Creature> people,
) => captive.align != politics.Alignment.conservative || captive.site == null
    ? const []
    : people
          .where(
            (person) =>
                personnelAvailableForOrders(person) &&
                person.location == captive.location,
          )
          .toList();

Creature? leadershipPromotionTarget(
  Creature person,
  Iterable<Creature> people,
) {
  final contact = people
      .where((p) => p.alive && p.id == person.hireId)
      .firstOrNull;
  return people.where((p) => p.alive && p.id == contact?.hireId).firstOrNull;
}

String? leadershipPromotionUnavailableReason(
  Creature person,
  Iterable<Creature> people,
) {
  if (!person.alive || person.align != politics.Alignment.liberal) {
    return 'Not a living Liberal';
  }
  if (person.hidingDaysLeft != 0) return 'Unavailable while in hiding';
  if (person.seduced) return 'Follows their lover only';
  final target = leadershipPromotionTarget(person, people);
  if (target == null) return 'Already at the top of this contact chain';
  if (!person.brainwashed && target.subordinatesLeft <= 0) {
    return '${target.name} has no free recruitment slots';
  }
  return null;
}

/// A permanent entry to the people left out of the current squad, plus the
/// organisation's contact chain and the actual staffing of its captives.
class JournalPeopleView extends StatefulWidget {
  const JournalPeopleView({
    super.key,
    required this.people,
    required this.directoryController,
    required this.onOpenProfile,
    required this.onAssignOrder,
    required this.onJoinSquad,
    required this.onOpenPromotionTools,
    required this.onAssignTender,
    this.onPromotePerson,
    this.onTools,
    this.onScopeChanged,
    this.initialScope = JournalPeopleScope.people,
    this.headerArt,
    this.reviewPanel,
    this.scopeArtBuilder,
    this.enabled = true,
  });

  final List<Creature> people;
  final PersonnelDirectoryController directoryController;
  final ValueChanged<Creature> onOpenProfile,
      onAssignOrder,
      onJoinSquad,
      onAssignTender;
  final ValueChanged<Creature>? onPromotePerson;
  final VoidCallback? onTools;
  final VoidCallback onOpenPromotionTools;
  final ValueChanged<JournalPeopleScope>? onScopeChanged;
  final JournalPeopleScope initialScope;
  final Widget? headerArt;
  final Widget? reviewPanel;
  final Widget Function(JournalPeopleScope)? scopeArtBuilder;
  final bool enabled;

  @override
  State<JournalPeopleView> createState() => JournalPeopleViewState();
}

class JournalPeopleViewState extends State<JournalPeopleView> {
  late JournalPeopleScope _scope = widget.initialScope;
  int? _staffingId;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            widget.scopeArtBuilder?.call(_scope) ??
                widget.headerArt ??
                const Icon(
                  Icons.groups_outlined,
                  color: JournalPalette.olive,
                  size: 32,
                ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('People', style: JournalPalette.heading),
                  Text(
                    'Every person, every place in the organisation.',
                    style: JournalPalette.small,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        JournalRecruitmentOverview(),
        const SizedBox(height: 8),
        if (widget.reviewPanel case final panel?) ...[
          panel,
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 7,
          runSpacing: 5,
          children: [
            for (final scope in JournalPeopleScope.values)
              ChoiceChip(
                key: ValueKey('people-scope:${scope.name}'),
                selected: _scope == scope,
                selectedColor: JournalPalette.selected,
                label: Text(switch (scope) {
                  JournalPeopleScope.people => 'All people',
                  JournalPeopleScope.leadership => 'Leadership',
                  JournalPeopleScope.captives => 'Captives',
                }),
                onSelected: widget.enabled
                    ? (_) {
                        setState(() {
                          _scope = scope;
                          _staffingId = null;
                        });
                        widget.onScopeChanged?.call(scope);
                      }
                    : null,
              ),
          ],
        ),
        const Divider(color: JournalPalette.rule),
        Expanded(
          child: switch (_scope) {
            JournalPeopleScope.people => PersonnelDirectory(
              people: widget.people,
              controller: widget.directoryController,
              onOpen: widget.onOpenProfile,
              onAssignOrder: widget.onAssignOrder,
              onJoinSquad: widget.onJoinSquad,
              onTools: widget.onTools,
              enabled: widget.enabled,
            ),
            JournalPeopleScope.leadership => _leadership(),
            JournalPeopleScope.captives => _captives(),
          },
        ),
      ],
    ),
  );

  Widget _leadership() {
    final people =
        widget.people
            .where((p) => p.alive && p.align == politics.Alignment.liberal)
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    return ListView(
      key: const PageStorageKey('people-leadership'),
      children: [
        const Text(
          'Recruitment follows the contact chain',
          style: JournalPalette.heading,
        ),
        const SizedBox(height: 6),
        const Text(
          'Each leader has their own recruitment capacity, based on Juice. Promotion moves a person up one contact in the chain and frees a slot under their former contact.',
          style: JournalPalette.small,
        ),
        const SizedBox(height: 7),
        const Text(
          'Seduced contacts follow their lover. Enlightened contacts do not use recruitment slots. The original promotion roster checks eligibility.',
          style: JournalPalette.small,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('people-promotion-tools'),
            onPressed: widget.enabled ? widget.onOpenPromotionTools : null,
            icon: const Icon(Icons.account_tree_outlined, size: 17),
            label: const Text('Open promotion roster'),
          ),
        ),
        if (people.isEmpty)
          const _EmptyPeople(
            message: 'No living Liberals in the contact chain.',
          ),
        for (final person in people) _leadershipCard(person),
      ],
    );
  }

  Widget _leadershipCard(Creature person) {
    final contact = widget.people
        .where((p) => p.id == person.hireId)
        .firstOrNull;
    final direct = widget.people
        .where((p) => p.alive && p.hireId == person.id)
        .toList();
    final target = leadershipPromotionTarget(person, widget.people);
    final blocked = leadershipPromotionUnavailableReason(person, widget.people);
    return _PeopleCard(
      key: ValueKey('leadership-person:${person.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _personHeading(
            person,
            subtitle: 'Juice ${person.juice} · ${person.title}',
          ),
          const SizedBox(height: 7),
          Text(
            'Contact: ${contact?.name ?? (person.hireId == null ? 'Movement leader' : 'No living contact')}',
            style: JournalPalette.body,
          ),
          Text(
            'Recruitment capacity: ${person.maxSubordinates} · ${person.subordinatesLeft > 0 ? person.subordinatesLeft : 0} free slots',
            style: JournalPalette.body,
          ),
          const SizedBox(height: 5),
          Text(
            'Living direct contacts (${direct.length}): ${direct.isEmpty ? 'None' : direct.map((p) => p.name).join(', ')}',
            style: JournalPalette.small,
          ),
          const SizedBox(height: 5),
          Text(
            blocked ?? 'After promotion: ${target!.name}',
            style: JournalPalette.small.copyWith(
              color: blocked == null
                  ? JournalPalette.olive
                  : JournalPalette.muted,
            ),
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 7,
            runSpacing: 5,
            children: [
              OutlinedButton.icon(
                key: ValueKey('leadership-profile:${person.id}'),
                onPressed: widget.enabled
                    ? () => widget.onOpenProfile(person)
                    : null,
                icon: const Icon(Icons.person_outline, size: 16),
                label: const Text('Dossier'),
              ),
              OutlinedButton.icon(
                key: ValueKey('leadership-promote:${person.id}'),
                onPressed: widget.enabled && blocked == null
                    ? () {
                        if (widget.onPromotePerson case final promote?) {
                          promote(person);
                        } else {
                          widget.onOpenPromotionTools();
                        }
                      }
                    : null,
                icon: const Icon(Icons.upgrade, size: 16),
                label: const Text('Promote'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _captives() {
    final captives =
        widget.people
            .where((p) => p.alive && p.align != politics.Alignment.liberal)
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    return ListView(
      key: const PageStorageKey('people-captives'),
      children: [
        const Text('Captive staffing', style: JournalPalette.heading),
        const SizedBox(height: 6),
        const Text(
          'A tender must be at the captive’s actual location. Moving a tender away clears their assignment when the day runs. Unattended captives may escape.',
          style: JournalPalette.small,
        ),
        const SizedBox(height: 10),
        if (captives.isEmpty)
          const _EmptyPeople(
            message:
                'No captives. Captives and their assigned crew appear here when present.',
          ),
        for (final captive in captives) _captiveCard(captive),
      ],
    );
  }

  Widget _captiveCard(Creature captive) {
    final present = captivePresentTenders(captive, widget.people);
    final assigned = captiveAssignedTenders(captive, widget.people);
    final away = assigned.where((person) => !present.contains(person)).toList();
    final candidates = captiveTenderCandidates(captive, widget.people);
    return _PeopleCard(
      key: ValueKey('captive-person:${captive.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _personHeading(captive, subtitle: personnelLocation(captive)),
          const SizedBox(height: 8),
          Text(
            present.isEmpty
                ? 'UNATTENDED · No tender present'
                : '${present.length} tender${present.length == 1 ? '' : 's'} present',
            key: ValueKey('captive-staffing:${captive.id}'),
            style: JournalPalette.body.copyWith(
              color: present.isEmpty
                  ? JournalPalette.danger
                  : JournalPalette.olive,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            'Assigned here: ${present.isEmpty ? 'None' : present.map((p) => p.name).join(', ')}',
            style: JournalPalette.small,
          ),
          if (away.isNotEmpty)
            Text(
              'Away from captive: ${away.map((p) => p.name).join(', ')}. These assignments will be cleared when the day runs.',
              style: JournalPalette.small.copyWith(
                color: JournalPalette.danger,
              ),
            ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 7,
            runSpacing: 5,
            children: [
              OutlinedButton.icon(
                key: ValueKey('captive-profile:${captive.id}'),
                onPressed: widget.enabled
                    ? () => widget.onOpenProfile(captive)
                    : null,
                icon: const Icon(Icons.person_outline, size: 16),
                label: const Text('Dossier'),
              ),
              OutlinedButton.icon(
                key: ValueKey('captive-staff:${captive.id}'),
                onPressed: widget.enabled
                    ? () => setState(
                        () => _staffingId = _staffingId == captive.id
                            ? null
                            : captive.id,
                      )
                    : null,
                icon: const Icon(Icons.assignment_ind_outlined, size: 16),
                label: const Text('Manage staffing'),
              ),
            ],
          ),
          for (final tender in present)
            TextButton(
              key: ValueKey('captive-tender-orders:${captive.id}:${tender.id}'),
              onPressed: widget.enabled && personnelAvailableForOrders(tender)
                  ? () => widget.onAssignOrder(tender)
                  : null,
              child: Text('Change ${tender.name}’s order'),
            ),
          if (_staffingId == captive.id) ...[
            const Divider(color: JournalPalette.rule),
            Text(
              candidates.isEmpty
                  ? 'No available active crew at this location. Use squad or base management to move crew here first.'
                  : 'Choose crew at this location. Their current order is replaced only after you confirm Tend to Hostages. Choose the captive in the original target picker if several are present.',
              style: JournalPalette.small,
            ),
            for (final tender in candidates)
              Padding(
                padding: const EdgeInsets.only(top: 7),
                child: OutlinedButton(
                  key: ValueKey(
                    'captive-choose-tender:${captive.id}:${tender.id}',
                  ),
                  onPressed: widget.enabled
                      ? () => widget.onAssignTender(tender)
                      : null,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tender.name, style: JournalPalette.body),
                        Text(
                          'Current order: ${tender.activity.description}',
                          style: JournalPalette.small,
                        ),
                        const Text(
                          'Review tending order →',
                          style: JournalPalette.small,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _personHeading(Creature person, {required String subtitle}) => Row(
    children: [
      CrewPortrait(person: person, size: 45),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              person.name,
              style: JournalPalette.body.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(subtitle, style: JournalPalette.small),
          ],
        ),
      ),
    ],
  );
}

class _PeopleCard extends StatelessWidget {
  const _PeopleCard({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      color: JournalPalette.card.withValues(alpha: .5),
      border: Border.all(color: JournalPalette.rule),
      borderRadius: BorderRadius.circular(3),
    ),
    child: child,
  );
}

class _EmptyPeople extends StatelessWidget {
  const _EmptyPeople({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 26),
    child: Text(
      message,
      style: JournalPalette.body,
      textAlign: TextAlign.center,
    ),
  );
}
