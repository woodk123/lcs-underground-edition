import 'package:flutter/material.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/modern/crew_portrait.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/juice_indicator.dart';
import 'package:lcs_new_age/politics/alignment.dart' as politics;

enum PersonnelFilter {
  all,
  active,
  hospital,
  custody,
  sleepers,
  away,
  hostages,
  dead,
}

enum PersonnelSort { name, status, location, juice }

/// Local reading preferences. None of these controls dispatch engine input.
class PersonnelDirectoryController extends ChangeNotifier {
  PersonnelDirectoryController() {
    search.addListener(_searchChanged);
  }
  final TextEditingController search = TextEditingController();
  PersonnelFilter _filter = PersonnelFilter.all;
  PersonnelSort _sort = PersonnelSort.name;
  PersonnelFilter get filter => _filter;
  PersonnelSort get sort => _sort;
  String get query => search.text.trim();

  void _searchChanged() {
    // A name search must find a hospitalized person even from Active crew.
    _filter = PersonnelFilter.all;
    notifyListeners();
  }

  void selectFilter(PersonnelFilter value) {
    _filter = value;
    notifyListeners();
  }

  void selectSort(PersonnelSort value) {
    _sort = value;
    notifyListeners();
  }

  void clearSearch() => search.clear();
  @override
  void dispose() {
    search.removeListener(_searchChanged);
    search.dispose();
    super.dispose();
  }
}

String personnelFilterLabel(PersonnelFilter filter) => switch (filter) {
  PersonnelFilter.all => 'All',
  PersonnelFilter.active => 'Active',
  PersonnelFilter.hospital => 'Hospital',
  PersonnelFilter.custody => 'Custody',
  PersonnelFilter.sleepers => 'Sleepers',
  PersonnelFilter.away => 'Away',
  PersonnelFilter.hostages => 'Hostages',
  PersonnelFilter.dead => 'Dead',
};

bool _matchesFilter(Creature person, PersonnelFilter filter) =>
    switch (filter) {
      PersonnelFilter.all => true,
      PersonnelFilter.active =>
        person.isActiveLiberal && person.hidingDaysLeft == 0,
      PersonnelFilter.hospital => person.alive && person.hospitalized,
      PersonnelFilter.custody => person.alive && person.imprisoned,
      PersonnelFilter.sleepers => person.alive && person.sleeperAgent,
      PersonnelFilter.away =>
        person.alive &&
            (person.vacationDaysLeft > 0 || person.hidingDaysLeft != 0),
      PersonnelFilter.hostages =>
        person.alive && person.align != politics.Alignment.liberal,
      PersonnelFilter.dead => !person.alive,
    };

String personnelStatus(Creature person) {
  if (!person.alive) return 'Deceased';
  if (person.hospitalized) return 'Hospitalized';
  if (person.imprisoned) return 'In custody';
  if (person.sleeperAgent) return 'Sleeper agent';
  if (person.hidingDaysLeft != 0) return 'In hiding';
  if (person.vacationDaysLeft > 0) return 'On vacation';
  if (person.align != politics.Alignment.liberal) return 'Hostage';
  if (person.isActiveLiberal) return 'Active crew';
  return 'Inactive';
}

String personnelLocation(Creature person) {
  final location = person.location?.getName(includeCity: true);
  if (person.alive && person.hidingDaysLeft == -1) {
    return location == null ? 'No contact' : 'No contact · $location';
  }
  return location ?? 'Location unknown';
}

/// All known personnel, independently of who is eligible for squad allocation.
/// The parent opens the selected person's original, source-owned profile.
class PersonnelDirectory extends StatelessWidget {
  const PersonnelDirectory({
    super.key,
    required this.people,
    required this.controller,
    required this.onOpen,
    this.onClose,
    this.onTools,
    this.enabled = true,
  });
  final List<Creature> people;
  final PersonnelDirectoryController controller;
  final ValueChanged<Creature> onOpen;
  final VoidCallback? onClose;
  final VoidCallback? onTools;
  final bool enabled;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final unique = {
        for (final person in people) person.id: person,
      }.values.toList();
      final counts = {
        for (final filter in PersonnelFilter.values)
          filter: unique
              .where((person) => _matchesFilter(person, filter))
              .length,
      };
      final query = controller.query.toLowerCase();
      final visible =
          unique
              .where(
                (person) =>
                    _matchesFilter(person, controller.filter) &&
                    (query.isEmpty ||
                        [
                          person.name,
                          person.properName,
                          person.title,
                          'Juice ${person.juice}',
                          personnelStatus(person),
                          personnelLocation(person),
                          person.type.name,
                          person.squad?.name ?? '',
                        ].join(' ').toLowerCase().contains(query)),
              )
              .toList()
            ..sort((a, b) {
              final by = switch (controller.sort) {
                PersonnelSort.name => a.name.toLowerCase().compareTo(
                  b.name.toLowerCase(),
                ),
                PersonnelSort.status => personnelStatus(
                  a,
                ).compareTo(personnelStatus(b)),
                PersonnelSort.location => personnelLocation(
                  a,
                ).compareTo(personnelLocation(b)),
                PersonnelSort.juice => b.juice.compareTo(a.juice),
              };
              return by != 0
                  ? by
                  : a.name.compareTo(b.name) != 0
                  ? a.name.compareTo(b.name)
                  : a.id.compareTo(b.id);
            });
      return KeyedSubtree(
        key: const ValueKey('personnel-directory'),
        child: CustomScrollView(
          key: const PageStorageKey('personnel-list'),
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.assignment_ind_outlined,
                        color: JournalPalette.olive,
                        size: 21,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Personnel directory',
                          style: JournalPalette.heading,
                        ),
                      ),
                      if (onClose != null)
                        IconButton(
                          key: const ValueKey('personnel-close'),
                          tooltip: 'Back to organisation',
                          onPressed: enabled ? onClose : null,
                          icon: const Icon(Icons.close, size: 20),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Find everyone in your organisation. Open a name to inspect their dossier.',
                    style: JournalPalette.small,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('personnel-search'),
                    controller: controller.search,
                    style: JournalPalette.body,
                    enabled: enabled,
                    decoration: InputDecoration(
                      labelText: 'Find anyone',
                      hintText: 'Name, status or location',
                      prefixIcon: const Icon(Icons.search, size: 19),
                      suffixIcon: controller.query.isEmpty
                          ? null
                          : IconButton(
                              key: const ValueKey('personnel-clear-search'),
                              tooltip: 'Clear search',
                              onPressed: controller.clearSearch,
                              icon: const Icon(Icons.close, size: 18),
                            ),
                      filled: true,
                      fillColor: JournalPalette.card.withValues(alpha: .6),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final filter in PersonnelFilter.values)
                        Semantics(
                          selected: controller.filter == filter,
                          child: OutlinedButton(
                            key: ValueKey('personnel-filter:${filter.name}'),
                            onPressed: enabled
                                ? () => controller.selectFilter(filter)
                                : null,
                            style: OutlinedButton.styleFrom(
                              backgroundColor: controller.filter == filter
                                  ? JournalPalette.selected
                                  : JournalPalette.card.withValues(alpha: .3),
                              foregroundColor: JournalPalette.ink,
                              side: BorderSide(
                                color: controller.filter == filter
                                    ? JournalPalette.binding
                                    : JournalPalette.rule,
                              ),
                              minimumSize: const Size(44, 44),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            child: Text(
                              '${personnelFilterLabel(filter)} (${counts[filter]})',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 9),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 10,
                    runSpacing: 4,
                    children: [
                      Text(
                        '${visible.length} of ${unique.length} people${controller.filter == PersonnelFilter.all ? ' · All personnel' : ' · ${personnelFilterLabel(controller.filter)}'}',
                        key: const ValueKey('personnel-results'),
                        style: JournalPalette.small,
                      ),
                      DropdownButton<PersonnelSort>(
                        key: const ValueKey('personnel-sort'),
                        value: controller.sort,
                        underline: const SizedBox.shrink(),
                        isDense: false,
                        items: [
                          for (final sort in PersonnelSort.values)
                            DropdownMenuItem(
                              value: sort,
                              child: Text(
                                'Sort: ${switch (sort) {
                                  PersonnelSort.name => 'Name',
                                  PersonnelSort.status => 'Status',
                                  PersonnelSort.location => 'Location',
                                  PersonnelSort.juice => 'Juice',
                                }}',
                                style: JournalPalette.small,
                              ),
                            ),
                        ],
                        onChanged: enabled
                            ? (sort) {
                                if (sort != null) controller.selectSort(sort);
                              }
                            : null,
                      ),
                    ],
                  ),
                  if (onTools != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        key: const ValueKey('personnel-tools'),
                        onPressed: enabled ? onTools : null,
                        icon: const Icon(Icons.tune, size: 15),
                        label: const Text(
                          'Roster tools',
                          style: JournalPalette.small,
                        ),
                      ),
                    ),
                  const Divider(height: 14, color: JournalPalette.rule),
                ],
              ),
            ),
            if (visible.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  key: const ValueKey('personnel-empty'),
                  padding: const EdgeInsets.symmetric(
                    vertical: 24,
                    horizontal: 8,
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.person_search_outlined,
                        color: JournalPalette.muted,
                        size: 30,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        query.isNotEmpty
                            ? 'No matching people'
                            : 'No people in this category',
                        style: JournalPalette.heading,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 7),
                      Text(
                        query.isNotEmpty
                            ? 'Try another name, status or location, or clear your search.'
                            : 'Choose All to see everyone. People remain listed when they enter hospital, custody or hiding.',
                        style: JournalPalette.small,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverList.builder(
                itemCount: visible.length,
                itemBuilder: (context, index) => _person(visible[index]),
              ),
          ],
        ),
      );
    },
  );

  Widget _person(Creature person) {
    final status = personnelStatus(person);
    final color = !person.alive
        ? JournalPalette.muted
        : person.hospitalized || person.imprisoned
        ? JournalPalette.danger
        : JournalPalette.olive;
    final location = personnelLocation(person);
    final condition = [
      if (person.alive) 'Blood ${person.blood}/${person.maxBlood}',
      if (person.alive && person.hospitalized)
        'Medical bill \$${_money(person.medicalBills)}',
      if (person.alive && person.isActiveLiberal && person.squad != null)
        person.squad!.name,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: OutlinedButton(
        key: ValueKey('personnel-person:${person.id}'),
        onPressed: enabled ? () => onOpen(person) : null,
        style: OutlinedButton.styleFrom(
          alignment: Alignment.centerLeft,
          foregroundColor: JournalPalette.ink,
          backgroundColor: JournalPalette.card.withValues(alpha: .4),
          padding: const EdgeInsets.all(11),
          minimumSize: const Size(44, 72),
          side: BorderSide(
            color: person.hospitalized && person.alive
                ? JournalPalette.danger.withValues(alpha: .45)
                : JournalPalette.rule.withValues(alpha: .7),
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        ),
        child: Semantics(
          label:
              'Open dossier for ${person.name}. $status. $location. Juice ${person.juice}, ${person.title}. $condition.',
          excludeSemantics: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CrewPortrait(person: person, size: 42),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      person.name,
                      style: JournalPalette.body.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: JuiceBadge(
                        person: person,
                        compact: true,
                        showHelp: false,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      status,
                      style: JournalPalette.small.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(location, style: JournalPalette.small),
                    const SizedBox(height: 4),
                    Text(condition, style: JournalPalette.small),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              const Padding(
                padding: EdgeInsets.only(top: 3),
                child: Icon(Icons.chevron_right, size: 17),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _money(int value) => value.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
  (match) => '${match[1]},',
);
