import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lcs_new_age/gamestate/time.dart';
import 'package:lcs_new_age/modern/journal_recruitment.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/movement_daily_plan.dart';

enum DailyPlanDestination { orders, profile, squad }

typedef DailyPlanRequest = ({int personId, DailyPlanDestination destination});

/// Reading preferences belong to the journal, not the campaign or reader.
class DailyPlanController extends ChangeNotifier {
  DailyPlanController() {
    search.addListener(notifyListeners);
  }

  final TextEditingController search = TextEditingController();
  int? _campaignId;
  DailyPlanFilter filter = DailyPlanFilter.all;
  int? selectedId;
  final expandedIds = <int>{};
  bool showMeetings = false;
  double scrollOffset = 0;

  void useSnapshot(MovementDailyPlan snapshot) {
    if (_campaignId != snapshot.campaignId) {
      _campaignId = snapshot.campaignId;
      search.clear();
      filter = DailyPlanFilter.all;
      selectedId = null;
      expandedIds.clear();
      showMeetings = false;
      scrollOffset = 0;
    }
    if (!snapshot.people.any((person) => person.id == selectedId)) {
      selectedId =
          snapshot.people
              .where((person) => person.id == snapshot.currentPersonId)
              .firstOrNull
              ?.id ??
          snapshot.people.firstOrNull?.id;
    }
  }

  void selectFilter(DailyPlanFilter value) {
    filter = value;
    notifyListeners();
  }

  void selectPerson(int id) {
    selectedId = id;
    notifyListeners();
  }

  void toggleDetails(int id) {
    if (!expandedIds.add(id)) expandedIds.remove(id);
    notifyListeners();
  }

  void toggleMeetings() {
    showMeetings = !showMeetings;
    notifyListeners();
  }

  @override
  void dispose() {
    search.removeListener(notifyListeners);
    search.dispose();
    super.dispose();
  }
}

/// Layout and local inspection only. The journal revalidates every navigation
/// request against its captured campaign and original input revision.
class JournalDailyPlan extends StatefulWidget {
  const JournalDailyPlan({
    super.key,
    required this.snapshot,
    required this.controller,
    required this.portraitBuilder,
    required this.onRequest,
    required this.onClose,
    this.navigationUnavailableReason,
  });

  final MovementDailyPlan snapshot;
  final DailyPlanController controller;
  final Widget Function(int personId) portraitBuilder;
  final ValueChanged<DailyPlanRequest> onRequest;
  final VoidCallback onClose;
  final String? navigationUnavailableReason;

  @override
  State<JournalDailyPlan> createState() => _JournalDailyPlanState();
}

class _JournalDailyPlanState extends State<JournalDailyPlan> {
  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: widget.controller.scrollOffset,
  )..addListener(_rememberScroll);

  void _rememberScroll() => widget.controller.scrollOffset = _scroll.offset;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
    },
    child: Dialog(
      key: const ValueKey('daily-plan-board'),
      backgroundColor: JournalPalette.page,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1120),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) => _content(context),
          ),
        ),
      ),
    ),
  );

  Widget _content(BuildContext context) {
    final snapshot = widget.snapshot;
    final controller = widget.controller;
    final query = controller.search.text.trim().toLowerCase();
    final visible = snapshot.people.where(
      (person) =>
          person.matches(controller.filter) &&
          (query.isEmpty || person.contains(query)),
    );
    final selected = snapshot.people
        .where((person) => person.id == controller.selectedId)
        .firstOrNull;
    return DefaultTextStyle.merge(
      style: JournalPalette.small,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Daily plan', style: JournalPalette.heading),
              ),
              IconButton(
                key: const ValueKey('daily-plan-close'),
                tooltip: 'Close daily plan',
                onPressed: widget.onClose,
                icon: const Icon(
                  Icons.close,
                  semanticLabel: 'Close daily plan',
                ),
              ),
            ],
          ),
          Text(
            '${snapshot.date.day} ${getMonth(snapshot.date.month)} ${snapshot.date.year} · Living crew and sleeper agents',
          ),
          const SizedBox(height: 6),
          TextField(
            key: const ValueKey('daily-plan-search'),
            controller: controller.search,
            decoration: const InputDecoration(
              labelText: 'Search daily plan',
              prefixIcon: Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 2,
            children: [
              for (final filter in DailyPlanFilter.values)
                ChoiceChip(
                  key: ValueKey('daily-plan-filter:${filter.name}'),
                  label: Text(
                    '${dailyPlanFilterLabel(filter)} (${snapshot.count(filter)})',
                  ),
                  selected: controller.filter == filter,
                  onSelected: (_) => controller.selectFilter(filter),
                ),
            ],
          ),
          if (controller.filter == DailyPlanFilter.needsOrder)
            const Text(
              'Available active crew currently Laying Low. Leaving this order in place can be intentional.',
            ),
          const Divider(),
          Expanded(
            child: Scrollbar(
              controller: _scroll,
              thumbVisibility: true,
              child: ListView(
                key: const ValueKey('daily-plan-list'),
                controller: _scroll,
                padding: const EdgeInsets.only(right: 10),
                children: [
                  if (visible.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('No people match this view.'),
                    ),
                  for (final person in visible) _person(person),
                  TextButton.icon(
                    key: const ValueKey('daily-plan-meetings'),
                    onPressed: controller.toggleMeetings,
                    icon: Icon(
                      controller.showMeetings
                          ? Icons.expand_less
                          : Icons.expand_more,
                    ),
                    label: Text(
                      'Recruitment meetings (${snapshot.meetings.length})',
                    ),
                  ),
                  if (controller.showMeetings) ...[
                    Text(
                      snapshot.meetingsPaused
                          ? 'Follow-ups are paused while the organisation is disbanding.'
                          : 'Follow-ups run after daily work, independently of daily Recruiting orders.',
                    ),
                    if (snapshot.meetings.isEmpty)
                      const Text('No recruitment follow-ups pending.'),
                    for (final meeting in snapshot.meetings) _meeting(meeting),
                  ],
                ],
              ),
            ),
          ),
          const Divider(),
          if (selected != null) _actions(selected),
          if (widget.navigationUnavailableReason != null)
            Text(widget.navigationUnavailableReason!),
        ],
      ),
    );
  }

  Widget _person(MovementDailyPlanPerson person) {
    final controller = widget.controller;
    final expanded = controller.expandedIds.contains(person.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: JournalSurface(
        inset: controller.selectedId == person.id,
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MergeSemantics(
                  child: Semantics(
                    label: 'Select daily plan for ${person.name}',
                    button: true,
                    selected: controller.selectedId == person.id,
                    child: InkWell(
                      key: ValueKey('daily-plan-person:${person.id}'),
                      onTap: () => controller.selectPerson(person.id),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: ExcludeSemantics(
                          child: widget.portraitBuilder(person.id),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(person.name, style: JournalPalette.heading),
                      if (widget.snapshot.currentPersonId == person.id)
                        const Text(
                          'Current actor',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      Text(
                        '${person.unavailable
                            ? 'Unavailable'
                            : person.needsOrder
                            ? 'Needs order'
                            : 'Assigned'} · ${person.status} · ${person.condition}',
                      ),
                      Text(
                        person.effectiveOrder,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(person.location),
                      if (person.meetings.isNotEmpty)
                        Text(
                          'Recruitment follow-ups: ${person.meetings.length}',
                        ),
                    ],
                  ),
                ),
                IconButton(
                  key: ValueKey('daily-plan-details:${person.id}'),
                  tooltip:
                      '${expanded ? 'Hide' : 'Show'} daily plan details for ${person.name}',
                  onPressed: () => controller.toggleDetails(person.id),
                  icon: Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    semanticLabel:
                        '${expanded ? 'Hide' : 'Show'} daily plan details for ${person.name}',
                  ),
                ),
              ],
            ),
            if (expanded) ...[
              const Divider(),
              Text(
                'Personal order: ${person.personalOrder}${person.sleeper ? ' (sleeper standing order)' : ''}',
              ),
              Text('Squad: ${person.squadName ?? 'Outside squads'}'),
              if (person.squadOrder != null) ...[
                Text(
                  'Squad order overrides personal work: ${person.squadOrder}',
                ),
                const Text(
                  'Departure is checked when the day runs, including access, transport and funds.',
                ),
              ],
              if (person.availabilityReason != null)
                Text(person.availabilityReason!),
              Text(person.medicalDetails),
              for (final meeting in person.meetings) _meeting(meeting),
            ],
          ],
        ),
      ),
    );
  }

  Widget _actions(MovementDailyPlanPerson person) {
    final navigationEnabled = widget.navigationUnavailableReason == null;
    final orderReason = person.orderUnavailableReason;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Selected: ${person.name}',
          key: const ValueKey('daily-plan-selected'),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            Tooltip(
              message: 'Orders for ${person.name}',
              excludeFromSemantics: true,
              child: OutlinedButton(
                key: ValueKey('daily-plan-orders:${person.id}'),
                onPressed: navigationEnabled && orderReason == null
                    ? () => widget.onRequest((
                        personId: person.id,
                        destination: DailyPlanDestination.orders,
                      ))
                    : null,
                child: Text(
                  'Orders',
                  semanticsLabel: 'Orders for ${person.name}',
                ),
              ),
            ),
            Tooltip(
              message: 'Profile for ${person.name}',
              excludeFromSemantics: true,
              child: OutlinedButton(
                key: ValueKey('daily-plan-profile:${person.id}'),
                onPressed: navigationEnabled
                    ? () => widget.onRequest((
                        personId: person.id,
                        destination: DailyPlanDestination.profile,
                      ))
                    : null,
                child: Text(
                  'Profile',
                  semanticsLabel: 'Profile for ${person.name}',
                ),
              ),
            ),
            if (person.squadId != null)
              Tooltip(
                message: 'View ${person.squadName} squad',
                excludeFromSemantics: true,
                child: OutlinedButton(
                  key: ValueKey('daily-plan-squad:${person.id}'),
                  onPressed: navigationEnabled
                      ? () => widget.onRequest((
                          personId: person.id,
                          destination: DailyPlanDestination.squad,
                        ))
                      : null,
                  child: Text(
                    'View squad',
                    semanticsLabel: 'View ${person.squadName} squad',
                  ),
                ),
              ),
          ],
        ),
        if (orderReason != null) Text(orderReason),
      ],
    );
  }

  Widget _meeting(PendingRecruitmentMeeting meeting) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Text(
      [
        '${meeting.recruiterName} → ${meeting.prospectName} · ${meeting.profession}',
        '${meeting.readiness} · ${meeting.freeSlots} free recruitment slots',
        if (meeting.inPerson)
          'In person at ${meeting.meetingPlace}'
        else
          'Remote follow-up; prospect at ${meeting.meetingPlace}',
        'Recruiter: ${meeting.recruiterLocation}',
        if (meeting.venueWarning != null) meeting.venueWarning!,
      ].join('\n'),
    ),
  );
}
