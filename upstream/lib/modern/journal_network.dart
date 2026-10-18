import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lcs_new_age/basemode/activate_sleepers.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/organisation_context.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/gamestate/time.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/modern/crew_dossier.dart';
import 'package:lcs_new_age/modern/crew_portrait.dart';
import 'package:lcs_new_age/modern/journal_order_icon.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/mechanics_help.dart';
import 'package:lcs_new_age/modern/organisation_controller.dart';
import 'package:lcs_new_age/monthly/sleeper_update.dart';

String sleeperOrderTitle(ActivityType type) => switch (type) {
  ActivityType.none => 'Lay Low',
  ActivityType.sleeperLiberal => 'Advocate Liberalism',
  ActivityType.sleeperRecruit => 'Expand Sleeper Network',
  ActivityType.sleeperSpy => 'Uncover Secrets',
  ActivityType.sleeperEmbezzle => 'Embezzle Funds',
  ActivityType.sleeperSteal => 'Steal Equipment',
  ActivityType.sleeperJoinLcs => 'Recall to active crew',
  _ => type.label,
};

String nextSleeperResolution(DateTime date) {
  final next = DateTime(date.year, date.month + 1, 1);
  return '1 ${getMonth(next.month)} ${next.year}';
}

/// A permanent, read-only network directory around the original order readers.
/// Drafts are local; only commitOrder may change a campaign assignment.
class JournalNetworkView extends StatefulWidget {
  const JournalNetworkView({
    super.key,
    required this.console,
    required this.controller,
    required this.onInspect,
    required this.onCloseInspection,
    this.inspectedPerson,
    this.onDraftChanged,
  });

  final Console console;
  final OrganisationController controller;
  final ValueChanged<Creature> onInspect;
  final VoidCallback onCloseInspection;
  final Creature? inspectedPerson;
  final ValueChanged<bool>? onDraftChanged;

  @override
  State<JournalNetworkView> createState() => JournalNetworkViewState();
}

class JournalNetworkViewState extends State<JournalNetworkView> {
  final _detailScroll = ScrollController();
  final _roleCardKey = GlobalKey();
  final _choicesKey = GlobalKey();
  int? _selectedId;
  ConsoleAction? _draft;
  int? _draftRevision;
  bool _routing = false;
  bool _mechanicsOpen = false;
  String? _category;
  String? _notice;

  OrganisationController get controller => widget.controller;
  Console get console => widget.console;
  List<Creature> get _agents =>
      game.pool.where((p) => p.alive && p.sleeperAgent).toList();
  Creature? get _person {
    final agents = _agents;
    return agents.where((p) => p.id == _selectedId).firstOrNull ??
        agents.where((p) => p.id == controller.selectedPersonId).firstOrNull ??
        agents.firstOrNull;
  }

  bool get _busy => _routing || controller.busy;
  bool get _validDraft =>
      _draft != null &&
      _draftRevision == console.revision.value &&
      console.actions.contains(_draft) &&
      activityOrderFrame(console)?.actorId == _person?.id &&
      activityOrderFrame(console)?.sleeper == true;

  bool get hasPreparedOrder => _validDraft;

  void _reveal(GlobalKey target) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final targetContext = target.currentContext;
      if (mounted && targetContext != null) {
        unawaited(Scrollable.ensureVisible(targetContext, alignment: .1));
      }
    });
  }

  @override
  void dispose() {
    _detailScroll.dispose();
    super.dispose();
  }

  void _clearDraft() {
    final hadDraft = _draft != null;
    _draft = null;
    _draftRevision = null;
    if (hadDraft) widget.onDraftChanged?.call(false);
  }

  void _select(Creature person) {
    widget.onCloseInspection();
    setState(() {
      _selectedId = person.id;
      _category = null;
      _notice = null;
      _clearDraft();
    });
  }

  Future<bool> _ensureOrders(Creature person) async {
    final frame = activityOrderFrame(console);
    if (frame?.sleeper == true && frame?.actorId == person.id) return true;
    return controller.openOrders(person.id);
  }

  Future<void> _browse(String categoryId, {bool layLow = false}) async {
    final person = _person;
    if (person == null ||
        _busy ||
        sleeperOrderUnavailableReason(person) != null) {
      return;
    }
    widget.onCloseInspection();
    setState(() {
      _routing = true;
      _notice = null;
      _clearDraft();
    });
    try {
      if (!await _ensureOrders(person) || !mounted) return;
      final category = console.actions
          .where(
            (a) =>
                a.entityId == categoryId &&
                const {
                  'sleeper-category',
                  'sleeper-category-selected',
                }.contains(a.entityType),
          )
          .firstOrNull;
      if (category == null ||
          !await controller.browseCategory(
            category,
            revision: console.revision.value,
          ) ||
          !mounted) {
        return;
      }
      setState(() => _category = categoryId);
      if (layLow) {
        final action = _orderAction(ActivityType.none);
        if (action != null && action.enabled) _prepare(action);
      } else {
        _reveal(_choicesKey);
      }
    } finally {
      if (mounted) setState(() => _routing = false);
    }
  }

  ConsoleAction? _orderAction(ActivityType type) => console.actions
      .where(
        (a) =>
            a.entityType == 'sleeper-activity' &&
            a.entityCategory == _person?.id.toString() &&
            a.entityId == type.name,
      )
      .firstOrNull;

  void _prepare(ConsoleAction action) {
    final person = _person;
    if (person == null ||
        !controller.canNavigate ||
        sleeperOrderUnavailableReason(person) != null ||
        action.entityType != 'sleeper-activity' ||
        action.entityCategory != person.id.toString() ||
        !action.enabled ||
        !console.actions.contains(action)) {
      return;
    }
    if (activityTypeForAction(action) == person.activity.type) {
      setState(() {
        _clearDraft();
        _notice = null;
      });
      _reveal(_roleCardKey);
      return;
    }
    setState(() {
      _draft = action;
      _draftRevision = console.revision.value;
      _notice = null;
    });
    widget.onDraftChanged?.call(true);
    _reveal(_roleCardKey);
  }

  Future<void> _recall() async {
    final person = _person;
    if (person == null ||
        _busy ||
        sleeperOrderUnavailableReason(person) != null) {
      return;
    }
    setState(() {
      _routing = true;
      _notice = null;
      _clearDraft();
    });
    try {
      if (!await _ensureOrders(person) || !mounted) return;
      final action = _orderAction(ActivityType.sleeperJoinLcs);
      if (action != null) _prepare(action);
    } finally {
      if (mounted) setState(() => _routing = false);
    }
  }

  Future<void> _confirm() async {
    if (_busy ||
        !_validDraft ||
        !controller.canNavigate ||
        sleeperOrderUnavailableReason(_person!) != null) {
      return;
    }
    final person = _person!;
    final action = _draft!;
    final revision = _draftRevision!;
    setState(() => _routing = true);
    try {
      if (!await controller.commitOrder(action, revision: revision) ||
          !mounted) {
        return;
      }
      await controller.networkReviews.markReviewed(person);
      if (!mounted) return;
      setState(() {
        _clearDraft();
        _category = null;
        _notice = person.activity.type == ActivityType.sleeperJoinLcs
            ? 'Recall confirmed. Returns on the next eligible day.'
            : 'Standing order confirmed. Repeats until changed.';
      });
    } finally {
      if (mounted) setState(() => _routing = false);
    }
  }

  Future<void> _keepCurrent() async {
    final person = _person;
    if (person == null || _busy || !controller.networkReviews.loaded) return;
    await controller.networkReviews.markReviewed(person);
    if (mounted) setState(() => _notice = 'Current role reviewed.');
  }

  /// Prevent the original immediate-assignment keys from bypassing the draft.
  bool handleGameShortcut(String key) {
    final normalized = normalizeConsoleKey(key);
    if (_mechanicsOpen) {
      if (normalized == 'Escape') {
        unawaited(Navigator.of(context, rootNavigator: true).maybePop());
      }
      return true;
    }
    if (widget.inspectedPerson != null) {
      if (normalized == 'Escape') widget.onCloseInspection();
      return true;
    }
    if (_busy || !controller.canNavigate) return true;
    if (normalized == 'Escape') {
      setState(() {
        _clearDraft();
        _category = null;
      });
      return true;
    }
    if (normalized == 'Enter') {
      if (_validDraft) unawaited(_confirm());
      return true;
    }
    if (normalized == 'a' || normalized == 'b') {
      unawaited(
        _browse(normalized == 'a' ? 'sleeper-advocacy' : 'sleeper-espionage'),
      );
      return true;
    }
    if (normalized == 'c') {
      unawaited(_recall());
      return true;
    }
    final frame = activityOrderFrame(console);
    if (frame?.sleeper == true) {
      final action = console.actions
          .where(
            (a) =>
                a.key == normalized &&
                a.entityType == 'sleeper-activity' &&
                a.enabled,
          )
          .firstOrNull;
      if (action != null) _prepare(action);
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([controller, controller.networkReviews]),
    builder: (context, _) => LayoutBuilder(
      builder: (context, bounds) {
        final stacked =
            bounds.maxWidth < 1000 &&
            MediaQuery.textScalerOf(context).scale(14) > 16;
        if (_agents.isEmpty) return _empty();
        if (stacked) {
          return ListView(
            key: const ValueKey('network-stacked-scroll'),
            children: [
              SizedBox(height: 380, child: _roster()),
              const SizedBox(height: 10),
              if (widget.inspectedPerson != null)
                SizedBox(height: bounds.maxHeight, child: _detail())
              else
                _detail(scroll: false),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _roster()),
            const JournalBinding(width: 26),
            Expanded(child: _detail()),
          ],
        );
      },
    ),
  );

  Widget _empty() => JournalSurface(
    key: const ValueKey('network-empty'),
    padding: const EdgeInsets.all(22),
    child: Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/modern/journal_network_empty_v1.webp',
              width: 250,
              height: 165,
              excludeFromSemantics: true,
            ),
            const SizedBox(height: 12),
            const Text('Undercover network', style: JournalPalette.title),
            const SizedBox(height: 9),
            const Text('No sleeper agents yet.', style: JournalPalette.heading),
            const SizedBox(height: 8),
            const SizedBox(
              width: 520,
              child: Text(
                'When a recruit stays at their workplace as a sleeper, they appear here. '
                'Choose a monthly standing order or keep them laying low to build infiltration.',
                textAlign: TextAlign.center,
                style: JournalPalette.body,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _roster() {
    final agents = _agents;
    final reviews = controller.networkReviews.count(agents);
    return JournalSurface(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              JournalIllustratedIcon(icon: JournalIcon.network, size: 46),
              SizedBox(width: 8),
              Expanded(
                child: Text('Undercover network', style: JournalPalette.title),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            '${agents.length} ${agents.length == 1 ? 'agent' : 'agents'}'
            '${reviews > 0 ? ' · $reviews to review' : ''}',
            style: JournalPalette.small,
          ),
          const Text(
            'Choose an agent, then a standing order.',
            style: JournalPalette.body,
          ),
          const SizedBox(height: 10),
          _timing(),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              key: const ValueKey('network-roster'),
              children: [for (final person in agents) _agentRow(person)],
            ),
          ),
          const Divider(color: JournalPalette.rule),
          const Text(
            'Lay Low builds infiltration. No daily reassignment needed.',
            style: JournalPalette.small,
          ),
        ],
      ),
    );
  }

  Widget _timing() => DecoratedBox(
    decoration: BoxDecoration(
      color: JournalPalette.inset,
      border: Border.all(color: JournalPalette.rule),
    ),
    child: Padding(
      padding: const EdgeInsets.all(9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.calendar_month_outlined,
            size: 19,
            color: JournalPalette.brassDark,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              'Monthly standing orders\n'
              'Next resolution: ${nextSleeperResolution(game.date)}',
              key: const ValueKey('network-next-resolution'),
              style: JournalPalette.small,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _agentRow(Creature person) {
    final reason = sleeperOrderUnavailableReason(person);
    final review = controller.networkReviews.needsReview(person);
    final infiltration = (person.infiltration * 100).round();
    final title = sleeperOrderTitle(person.activity.type);
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: journalTabDecoration(selected: person.id == _person?.id),
          child: Semantics(
            button: true,
            selected: person.id == _person?.id,
            label:
                'Select sleeper ${person.name}. ${person.type.name}. '
                'Current order $title. Infiltration $infiltration percent.'
                '${reason == null ? '' : ' $reason.'}'
                '${review ? ' Review role.' : ''}',
            excludeSemantics: true,
            child: InkWell(
              key: ValueKey('network-agent:${person.id}'),
              onTap: _busy ? null : () => _select(person),
              child: Padding(
                padding: const EdgeInsets.all(9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CrewPortrait(person: person, size: 46),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(person.name, style: JournalPalette.heading),
                          Text(
                            person.workLocation.getName(
                              short: true,
                              includeCity: true,
                            ),
                            style: JournalPalette.small,
                          ),
                          Text(title, style: JournalPalette.body),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              Expanded(
                                child: LinearProgressIndicator(
                                  value: person.infiltration.clamp(0.0, 1.0),
                                  color: JournalPalette.olive,
                                  backgroundColor: JournalPalette.inset,
                                  minHeight: 6,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '$infiltration%',
                                style: JournalPalette.small,
                              ),
                            ],
                          ),
                          if (reason != null)
                            Text(reason, style: JournalPalette.small),
                          if (review)
                            Padding(
                              padding: const EdgeInsets.only(top: 5),
                              child: _tag(
                                'Review role',
                                JournalPalette.selected,
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
        ),
      ),
    );
  }

  Widget _tag(String text, Color background) => DecoratedBox(
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(3),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      child: Text(text, style: JournalPalette.small),
    ),
  );

  Widget _detail({bool scroll = true}) {
    final inspected = widget.inspectedPerson;
    if (inspected != null) {
      return JournalSurface(
        padding: const EdgeInsets.all(10),
        child: CrewInspector(
          person: inspected,
          onClose: widget.onCloseInspection,
          compact: true,
        ),
      );
    }
    final person = _person!;
    final reason = sleeperOrderUnavailableReason(person);
    final current = person.activity.type;
    final pending = _validDraft ? activityTypeForAction(_draft!) : null;
    final displayed = pending ?? current;
    final help = activityMechanics(
      displayed,
      actor: person,
      activity: pending == null ? person.activity : Activity(displayed),
      sleeper: true,
    );
    final canChoose = !_busy && reason == null && controller.canNavigate;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CrewPortrait(person: person, size: 70),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(person.name, style: JournalPalette.title),
                  Text(person.type.name, style: JournalPalette.body),
                  Text(
                    person.workLocation.getName(short: true, includeCity: true),
                    style: JournalPalette.small,
                  ),
                  TextButton.icon(
                    onPressed: _busy ? null : () => widget.onInspect(person),
                    icon: const Icon(Icons.badge_outlined, size: 16),
                    label: const Text('View dossier'),
                  ),
                ],
              ),
            ),
          ],
        ),
        const Divider(height: 22, color: JournalPalette.rule),
        Text(
          'Current order · ${sleeperOrderTitle(current)}',
          key: const ValueKey('network-current-order'),
          style: JournalPalette.heading,
        ),
        Text(
          current == ActivityType.sleeperJoinLcs
              ? 'Next eligible day · needs an available safehouse outside siege.'
              : 'Monthly standing order · repeats until changed.',
          style: JournalPalette.small,
        ),
        const SizedBox(height: 7),
        Tooltip(
          message:
              'Infiltration is job access and trust, not a success percentage.',
          child: Text(
            '${(person.infiltration * 100).round()}% infiltration',
            style: JournalPalette.body,
          ),
        ),
        if (reason != null) ...[
          const SizedBox(height: 10),
          _tag('Cannot change orders: $reason', JournalPalette.inset),
        ],
        const SizedBox(height: 12),
        JournalSurface(
          key: _roleCardKey,
          inset: true,
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                pending == null
                    ? 'Current role'
                    : 'Prepared change · not confirmed',
                style: JournalPalette.small.copyWith(
                  color: pending == null
                      ? JournalPalette.muted
                      : JournalPalette.danger,
                ),
              ),
              const SizedBox(height: 7),
              Row(
                children: [
                  JournalOrderIcon(type: displayed, size: 34),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      sleeperOrderTitle(displayed),
                      style: JournalPalette.heading,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(help.summary, style: JournalPalette.body),
              const SizedBox(height: 6),
              Text(
                displayed == ActivityType.sleeperJoinLcs
                    ? 'Next eligible day · requires an LCS safehouse outside siege.'
                    : 'Next resolution: ${nextSleeperResolution(game.date)}',
                style: JournalPalette.small,
              ),
              if (displayed == ActivityType.sleeperSpy ||
                  displayed == ActivityType.sleeperSteal)
                _deadDrop(person, displayed),
              if (displayed == ActivityType.none)
                const Text(
                  '+1–5 infiltration points each month, up to 100%.',
                  style: JournalPalette.body,
                ),
              if (help.requirements.isNotEmpty)
                Text(help.requirements, style: JournalPalette.small),
              if (help.risk.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    help.risk,
                    style: JournalPalette.small.copyWith(
                      color: JournalPalette.danger,
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('network-order-mechanics'),
                  onPressed: _busy ? null : () => _showMechanics(help),
                  icon: const Icon(Icons.info_outline, size: 16),
                  label: const Text('Order mechanics'),
                ),
              ),
              if (pending != null) ...[
                FilledButton.icon(
                  key: const ValueKey('network-confirm-order'),
                  onPressed: canChoose ? () => unawaited(_confirm()) : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: JournalPalette.olive,
                  ),
                  icon: const Icon(Icons.check, size: 18),
                  label: Text(
                    pending == ActivityType.sleeperJoinLcs
                        ? 'Confirm recall'
                        : 'Confirm standing order',
                  ),
                ),
                TextButton(
                  key: const ValueKey('network-cancel-order'),
                  onPressed: _busy ? null : () => setState(_clearDraft),
                  child: const Text('Cancel prepared change'),
                ),
              ] else
                FilledButton.icon(
                  key: const ValueKey('network-keep-order'),
                  onPressed: !_busy && controller.networkReviews.loaded
                      ? () => unawaited(_keepCurrent())
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: JournalPalette.olive,
                  ),
                  icon: const Icon(Icons.check, size: 18),
                  label: Text(
                    current == ActivityType.none
                        ? 'Keep Lay Low'
                        : 'Keep current order',
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 15),
        const Text('Choose a standing role', style: JournalPalette.heading),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            OutlinedButton(
              key: const ValueKey('network-lay-low'),
              onPressed: canChoose
                  ? () => unawaited(_browse('sleeper-advocacy', layLow: true))
                  : null,
              child: const Text('Lay Low'),
            ),
            OutlinedButton(
              key: const ValueKey('network-advocacy'),
              onPressed: canChoose
                  ? () => unawaited(_browse('sleeper-advocacy'))
                  : null,
              child: const Text('Advocacy'),
            ),
            OutlinedButton(
              key: const ValueKey('network-espionage'),
              onPressed: canChoose
                  ? () => unawaited(_browse('sleeper-espionage'))
                  : null,
              child: const Text('Espionage'),
            ),
          ],
        ),
        Column(
          key: _choicesKey,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _tasks(person),
        ),
        const Divider(height: 25, color: JournalPalette.rule),
        OutlinedButton.icon(
          key: const ValueKey('network-recall'),
          onPressed: canChoose ? () => unawaited(_recall()) : null,
          icon: const Icon(Icons.person_add_alt, size: 18),
          label: const Text('Recall to active crew'),
        ),
        const Text(
          'Returns on the next eligible day. Requires an LCS safehouse outside siege.',
          style: JournalPalette.small,
        ),
        if (_notice != null || controller.message != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _notice ?? controller.message!,
                style: JournalPalette.small,
              ),
            ),
          ),
      ],
    );
    return JournalSurface(
      padding: const EdgeInsets.all(12),
      child: scroll
          ? Scrollbar(
              controller: _detailScroll,
              thumbVisibility: true,
              child: SingleChildScrollView(
                key: const ValueKey('network-detail-scroll'),
                controller: _detailScroll,
                child: content,
              ),
            )
          : content,
    );
  }

  Widget _deadDrop(Creature person, ActivityType order) {
    final camp = game.sites
        .where(
          (site) =>
              site.type == SiteType.homelessEncampment &&
              site.city == person.workLocation.city,
        )
        .firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (order == ActivityType.sleeperSpy &&
              !sleeperHasDocumentSource(person)) ...[
            Text(
              'No document source for this profession or workplace. '
              'Choose another role; snooping still risks exposure.',
              key: const ValueKey('network-no-document-source'),
              style: JournalPalette.body.copyWith(color: JournalPalette.danger),
            ),
            const SizedBox(height: 6),
          ],
          Text(
            camp == null
                ? 'No dead-drop camp in this workplace’s city.'
                : 'Dead drop: ${camp.getName(short: false, includeCity: true)}. '
                      'Use Bases → Move equipment between bases to collect its stock.',
            key: const ValueKey('network-dead-drop'),
            style: JournalPalette.body,
          ),
          if (order == ActivityType.sleeperSteal && person.workSite == null)
            const Text(
              'No workplace equipment source. Choose another role.',
              style: JournalPalette.small,
            ),
          if (order == ActivityType.sleeperSpy) ...[
            const SizedBox(height: 6),
            const Text(
              'Special editions are chosen before sleepers resolve. Newly leaked '
              'documents can be offered at the following monthly decision; '
              'they must be stored at an LCS-controlled site.',
              key: ValueKey('network-edition-timing'),
              style: JournalPalette.small,
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _tasks(Creature person) {
    final frame = activityOrderFrame(console);
    if (_category == null ||
        frame?.sleeper != true ||
        frame?.actorId != person.id) {
      return const [];
    }
    final tasks = console.actions.where(
      (a) =>
          a.entityType == 'sleeper-activity' &&
          a.entityId != ActivityType.none.name &&
          a.entityId != ActivityType.sleeperJoinLcs.name,
    );
    return [
      for (final action in tasks)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: OutlinedButton.icon(
            key: ValueKey('network-task:${action.entityId}'),
            onPressed:
                !_busy &&
                    controller.canNavigate &&
                    sleeperOrderUnavailableReason(person) == null &&
                    action.enabled
                ? () => _prepare(action)
                : null,
            icon: JournalOrderIcon(
              type: activityTypeForAction(action)!,
              size: 27,
            ),
            label: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sleeperOrderTitle(activityTypeForAction(action)!)),
                if (!action.enabled)
                  Text(action.label, style: JournalPalette.small),
              ],
            ),
          ),
        ),
    ];
  }

  Future<void> _showMechanics(ActivityMechanics help) async {
    if (_mechanicsOpen) return;
    _mechanicsOpen = true;
    final scaler = MediaQuery.textScalerOf(context);
    try {
      await showDialog<void>(
        context: context,
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: scaler),
          child: AlertDialog(
            title: Text(sleeperOrderTitle(help.type)),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(help.summary),
                    const SizedBox(height: 8),
                    Text(help.timing),
                    if (help.requirements.isNotEmpty)
                      Text('Needs: ${help.requirements}'),
                    if (help.risk.isNotEmpty) Text(help.risk),
                    if (help.calculation case final calculation?) ...[
                      const SizedBox(height: 12),
                      ActivityCalculationView(calculation: calculation),
                    ],
                    if (help.details.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(help.details),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close'),
              ),
            ],
          ),
        ),
      );
    } finally {
      _mechanicsOpen = false;
    }
  }
}
