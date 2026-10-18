import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/engine/base_management_context.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/location/compound_upgrades.dart';
import 'package:lcs_new_age/location/siege.dart' as siege;
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/modern/base_management_controller.dart';
import 'package:lcs_new_age/modern/base_rent_summary.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/organisation_controller.dart';

/// A permanent inventory and safehouse directory. Actions remain the current
/// original investment, equipment-transfer and home-base assignment readers.
class JournalBasesView extends StatefulWidget {
  const JournalBasesView({
    super.key,
    required this.console,
    required this.controller,
    this.onInspect,
    this.onDraftChanged,
  });
  final Console console;
  final OrganisationController controller;
  final ValueChanged<Creature>? onInspect;
  final ValueChanged<bool>? onDraftChanged;

  @override
  State<JournalBasesView> createState() => JournalBasesViewState();
}

class JournalBasesViewState extends State<JournalBasesView> {
  late BaseManagementController _routes;
  int? _selectedId;
  ConsoleAction? _purchase;
  int? _purchaseRevision;
  int _purchaseVersion = 0;
  String? _notice;
  bool _reportedPreparedPurchase = false;

  bool get hasPreparedPurchase => _validPurchase;

  Console get console => widget.console;
  bool get _busy => _routes.busy;
  Site? get _site {
    final bases = organisationBases();
    if (_selectedId == null && console.screen == 'base-investment') {
      final sourceSiteId = console.actions
          .where(
            (action) => const {
              'compound-upgrade',
              'base-supplies',
            }.contains(action.entityType),
          )
          .firstOrNull
          ?.entityCategory;
      final sourceSite = bases
          .where((site) => site.idString == sourceSiteId)
          .firstOrNull;
      if (sourceSite != null) return sourceSite;
    }
    return bases.where((site) => site.id == _selectedId).firstOrNull ??
        bases.where((site) => !isAvailableShelter(site)).firstOrNull ??
        bases.firstOrNull;
  }

  @override
  void initState() {
    super.initState();
    _createRoutes();
    console.revision.addListener(_changed);
  }

  void _createRoutes() {
    _routes = BaseManagementController(organisation: widget.controller)
      ..addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant JournalBasesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _routes.removeListener(_changed);
      _routes.dispose();
      _createRoutes();
    }
    if (oldWidget.console != console) {
      oldWidget.console.revision.removeListener(_changed);
      console.revision.addListener(_changed);
    }
  }

  @override
  void dispose() {
    console.revision.removeListener(_changed);
    _routes.removeListener(_changed);
    _routes.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) _updateState(() {});
  }

  void _updateState(VoidCallback change) {
    setState(change);
    final prepared = hasPreparedPurchase;
    if (prepared != _reportedPreparedPurchase) {
      _reportedPreparedPurchase = prepared;
      widget.onDraftChanged?.call(prepared);
    }
  }

  void _select(Site site) => _updateState(() {
    _selectedId = site.id;
    _purchase = null;
    _notice = null;
  });

  Future<void> _route(Future<bool> Function() route) async {
    if (_busy) return;
    _updateState(() {
      _purchase = null;
      _notice = null;
    });
    await route();
    if (mounted) _updateState(() {});
  }

  Future<void> _send(ConsoleAction action, {String? notice}) async {
    final revision = console.revision.value;
    if (_busy || !action.enabled || !console.actions.contains(action)) return;
    _updateState(() => _purchase = null);
    final success = await _routes.sendAction(action, revision: revision);
    if (mounted) _updateState(() => _notice = success ? notice : null);
  }

  bool get _validPurchase =>
      _purchase != null &&
      _purchaseRevision == console.revision.value &&
      console.awaitingInput &&
      !console.textInput &&
      console.eventMessage == null &&
      console.actions.contains(_purchase) &&
      _purchase!.entityCategory == _site?.idString &&
      console.screen == 'base-investment';

  Future<void> _confirmPurchase(
    ConsoleAction purchase,
    int revision,
    int version,
  ) async {
    if (!_validPurchase ||
        !identical(_purchase, purchase) ||
        _purchaseRevision != revision ||
        _purchaseVersion != version) {
      return;
    }
    await _send(purchase, notice: 'Purchase completed.');
  }

  /// Lets the enclosing journal preserve staged purchase confirmation for
  /// keyboard users. Required messages and text prompts keep their own reader.
  bool handleGameShortcut(String key) {
    if (console.textInput || console.eventMessage != null) return false;
    // This directory may sit over an HQ input reader while inspecting bases.
    // Do not let unlabelled HQ letters run a day, save/exit, change squads, or
    // open a different hidden reader behind the visible directory.
    if (_busy || console.screen == 'headquarters') return true;
    if (!BaseManagementController.ownsScreen(console)) return false;
    final normalized = normalizeConsoleKey(key);
    if (_validPurchase) {
      if (normalized == 'Enter') {
        unawaited(
          _confirmPurchase(_purchase!, _purchaseRevision!, _purchaseVersion),
        );
      } else if (const {'Escape', 'Backspace'}.contains(normalized)) {
        _updateState(() => _purchase = null);
      }
      return true;
    }
    if (const {'Escape', 'Enter', 'Backspace'}.contains(normalized)) {
      unawaited(_route(_routes.closeSource));
      return true;
    }
    final action = console.actions
        .where((action) => action.key == normalized && action.enabled)
        .firstOrNull;
    if (action == null) return true;
    if (console.screen == 'base-investment') {
      if (const {
        'compound-upgrade',
        'base-supplies',
      }.contains(action.entityType)) {
        final site = game.sites
            .where((site) => site.idString == action.entityCategory)
            .firstOrNull;
        if (site != null) {
          _updateState(() {
            _selectedId = site.id;
            _purchase = action;
            _purchaseRevision = console.revision.value;
            _purchaseVersion++;
          });
        }
      }
    } else {
      unawaited(_send(action));
    }
    return true;
  }

  String _label(ConsoleAction action) =>
      stripConsoleColors(action.label).replaceFirst(RegExp(r'^\S+\s*-\s*'), '');

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final directory = _directory();
      final content = _content();
      return Material(
        type: MaterialType.transparency,
        child: DefaultTextStyle(
          style: JournalPalette.body,
          child: constraints.maxWidth < 720
              ? ListView(
                  padding: const EdgeInsets.all(14),
                  children: [directory, const SizedBox(height: 16), content],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 285,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: directory,
                      ),
                    ),
                    const VerticalDivider(width: 1, color: JournalPalette.rule),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: content,
                      ),
                    ),
                  ],
                ),
        ),
      );
    },
  );

  Widget _directory() {
    final bases = organisationBases();
    final inUse = bases.where((site) => !isAvailableShelter(site)).toList();
    final available = bases.where(isAvailableShelter).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            JournalIllustratedIcon(icon: JournalIcon.bases, size: 42),
            SizedBox(width: 10),
            Expanded(
              child: Text('Bases & Stores', style: JournalPalette.title),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'See who lives where, prepare your safehouses, and move stored equipment.',
        ),
        const SizedBox(height: 12),
        _routeButton(
          'Move equipment between bases',
          Icons.inventory_2_outlined,
          storesUnavailableReason(),
          _routes.openStores,
        ),
        const SizedBox(height: 8),
        _routeButton(
          'Assign home bases',
          Icons.group_add_outlined,
          baseAssignmentUnavailableReason(),
          _routes.openSquadlessAssignment,
        ),
        const SizedBox(height: 8),
        const Text(
          'Home base assignment is for active crew outside squads. People in squads move with their squad.',
          style: JournalPalette.small,
        ),
        const Divider(height: 28, color: JournalPalette.rule),
        Text(
          '${inUse.length} ${inUse.length == 1 ? 'base' : 'bases'} in use',
          style: JournalPalette.heading,
        ),
        const SizedBox(height: 8),
        if (inUse.isEmpty)
          const Text(
            'No bases are in use. Available shelters are listed below.',
          ),
        for (final site in inUse) _directorySite(site),
        const Divider(height: 28, color: JournalPalette.rule),
        Text(
          '${available.length} available ${available.length == 1 ? 'shelter' : 'shelters'}',
          style: JournalPalette.heading,
        ),
        const SizedBox(height: 8),
        const Text(
          'Free camps and empty warehouses you can move into. Travel requirements still apply.',
          style: JournalPalette.small,
        ),
        const SizedBox(height: 8),
        if (available.isEmpty) const Text('No unused shelters are available.'),
        for (final site in available) _directorySite(site),
      ],
    );
  }

  Widget _directorySite(Site site) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: _site == site ? JournalPalette.selected : JournalPalette.card,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: JournalPalette.rule),
        borderRadius: BorderRadius.circular(3),
      ),
      child: InkWell(
        onTap: _busy ? null : () => _select(site),
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                site.getName(includeCity: true),
                style: JournalPalette.heading,
              ),
              Text(
                isAvailableShelter(site)
                    ? 'Available shelter · not in use'
                    : '${baseResidents(site).length} based here · ${site.loot.length} stored stacks',
                style: JournalPalette.small,
              ),
              if (site.siege.underSiege)
                Text(
                  site.siege.underAttack ? 'Under attack' : 'Under siege',
                  style: JournalPalette.small.copyWith(
                    color: JournalPalette.danger,
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _routeButton(
    String title,
    IconData icon,
    String? reason,
    Future<bool> Function() route,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      OutlinedButton.icon(
        onPressed: _busy || reason != null
            ? null
            : () => unawaited(_route(route)),
        icon: Icon(icon, size: 19),
        label: Text(title),
      ),
      if (reason != null) Text(reason, style: JournalPalette.small),
    ],
  );

  Widget _content() {
    final site = _site;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_routes.message != null) _note(_routes.message!, danger: true),
        if (_notice != null) _note(_notice!),
        if (console.screen == 'equipment-transfer') ...[
          _transferPanel(),
          const SizedBox(height: 20),
        ],
        if (console.screen == 'base-assignment') ...[
          _assignmentPanel(),
          const SizedBox(height: 20),
        ],
        if (site != null) ...[
          Text(site.getName(includeCity: true), style: JournalPalette.title),
          Text(site.type.name, style: JournalPalette.small),
          if (isAvailableShelter(site))
            _note(
              'Available shelter — not currently in use. '
              'Move your squad here through Organisation or City maps to make it a home base. '
              'Selecting it here only inspects the location.',
            ),
          const SizedBox(height: 14),
          _supplies(site),
          const SizedBox(height: 16),
          _facilities(site),
          const SizedBox(height: 16),
          _residents(site),
          const SizedBox(height: 16),
          _stores(site),
        ],
      ],
    );
  }

  Widget _supplies(Site site) {
    final eaters = siege.numberEating(site);
    final foodDays = siege.foodDaysLeft(site);
    final reason = baseInvestmentUnavailableReason(site);
    return _card('Supplies & preparation', Icons.kitchen_outlined, [
      Wrap(
        spacing: 20,
        runSpacing: 8,
        children: [
          Text(
            '${site.compound.rations} daily rations',
            style: JournalPalette.heading,
          ),
          Text('$eaters people present', style: JournalPalette.body),
          if (eaters > 0)
            Text(
              '$foodDays days of stored food',
              style: JournalPalette.body.copyWith(
                color: site.siege.underSiege && foodDays < 4
                    ? JournalPalette.danger
                    : JournalPalette.ink,
              ),
            ),
          Text(
            '${site.compound.diesel} days of generator fuel',
            style: JournalPalette.body,
          ),
        ],
      ),
      const SizedBox(height: 8),
      const Text(
        'Stored food sustains people during a siege. Fuel runs an installed backup generator.',
        style: JournalPalette.small,
      ),
      const SizedBox(height: 10),
      if (console.screen == 'base-investment' &&
          console.actions.any(
            (action) => action.entityCategory == site.idString,
          ))
        _investmentPanel(site)
      else
        _routeButton(
          'Buy supplies & improve base',
          Icons.construction_outlined,
          reason,
          () => _routes.openInvestment(site.id),
        ),
    ]);
  }

  Widget _facilities(
    Site site,
  ) => _card('Security & facilities', Icons.shield_outlined, [
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final upgrade in CompoundUpgrade.values.where(
          (upgrade) => upgrade.isActiveOn(site),
        ))
          Chip(label: Text(_upgradeName(upgrade))),
        if (!CompoundUpgrade.values.any((upgrade) => upgrade.isActiveOn(site)))
          const Text('No compound upgrades installed.'),
      ],
    ),
    if (site.discreet)
      const Text('Hidden location', style: JournalPalette.small),
    if (site.siege.underSiege && site.siege.lightsOff)
      _note('Power is cut during the siege.', danger: true),
    if (site.siege.underSiege && site.compound.cameras && site.siege.camerasOff)
      _note('Security cameras are off during the siege.', danger: true),
    const SizedBox(height: 5),
    Text('Heat ${site.heat}', style: JournalPalette.small),
    const SizedBox(height: 6),
    _rent(site),
  ]);

  Widget _rent(Site site) {
    final rent = baseRentSummary(site);
    return Column(
      key: ValueKey('base-rent:${site.id}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          rent.title,
          style: JournalPalette.body.copyWith(
            color: rent.forcedEviction
                ? JournalPalette.danger
                : JournalPalette.ink,
          ),
        ),
        Text(rent.detail, style: JournalPalette.small),
        if (rent.warning != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              rent.warning!,
              style: JournalPalette.small.copyWith(
                color: rent.forcedEviction || game.ledger.funds < site.rent
                    ? JournalPalette.danger
                    : JournalPalette.muted,
              ),
            ),
          ),
      ],
    );
  }

  Widget _residents(Site site) {
    final residents = baseResidents(site);
    return _card(
      'People based here · ${residents.length}',
      Icons.groups_outlined,
      [
        if (residents.isEmpty)
          const Text(
            'No living crew or captives have this as their home base.',
          ),
        for (final person in residents)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(person.name, style: JournalPalette.body),
            subtitle: Text(
              person.locationId == site.idString
                  ? (person.squad?.name ?? 'Outside a squad')
                  : 'Currently at ${person.location?.getName(includeCity: true) ?? 'an unknown location'}',
              style: JournalPalette.small,
            ),
            trailing: widget.onInspect == null
                ? null
                : const Icon(Icons.person_search_outlined, size: 20),
            onTap: widget.onInspect == null || _busy
                ? null
                : () => widget.onInspect!(person),
          ),
      ],
    );
  }

  Widget _stores(Site site) => _card(
    'Stored here · ${site.loot.length} stacks',
    Icons.inventory_2_outlined,
    [
      const Text(
        'These items belong to this location. Equip a squad at the same location, or use Move equipment between bases.',
        style: JournalPalette.small,
      ),
      if (site.siege.underSiege)
        _note(
          'Stored equipment at this base cannot be transferred during a siege.',
          danger: true,
        ),
      const SizedBox(height: 8),
      if (site.loot.isEmpty) const Text('No equipment is stored here.'),
      for (final item in site.loot)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            '${item.equipTitle()}${item.stackSize > 1 ? ' ×${item.stackSize}' : ''}',
          ),
        ),
    ],
    illustration: JournalIcon.stores,
  );

  Widget _investmentPanel(Site site) {
    final purchase = _validPurchase ? _purchase : null;
    final purchaseRevision = _purchaseRevision;
    final purchaseVersion = _purchaseVersion;
    final actions = console.actions
        .where(
          (action) =>
              action.entityCategory == site.idString &&
              const {
                'compound-upgrade',
                'base-supplies',
              }.contains(action.entityType),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Available funds: \$${game.ledger.funds}',
          style: JournalPalette.heading,
        ),
        const Text(
          'Choose a purchase, then confirm its cost. Each purchase takes effect immediately.',
          style: JournalPalette.small,
        ),
        for (final action in actions)
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: OutlinedButton(
              onPressed: _busy || !action.enabled
                  ? null
                  : () => _updateState(() {
                      _purchase = action;
                      _purchaseRevision = console.revision.value;
                      _purchaseVersion++;
                    }),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${_label(action)}${action.enabled ? '' : ' — insufficient funds'}',
                ),
              ),
            ),
          ),
        if (purchase != null && purchaseRevision != null) ...[
          const SizedBox(height: 10),
          _note('Purchase: ${_label(purchase)}'),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () => unawaited(
                        _confirmPurchase(
                          purchase,
                          purchaseRevision,
                          purchaseVersion,
                        ),
                      ),
                icon: const Icon(Icons.check),
                label: const Text('Confirm purchase'),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () {
                        if (identical(_purchase, purchase) &&
                            _purchaseRevision == purchaseRevision &&
                            _purchaseVersion == purchaseVersion) {
                          _updateState(() => _purchase = null);
                        }
                      },
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
        TextButton(
          onPressed: _busy
              ? null
              : () => unawaited(_route(_routes.closeSource)),
          child: const Text('Done purchasing'),
        ),
      ],
    );
  }

  Widget _transferPanel() {
    final selectedId = console.actions
        .where((action) => action.entityType == 'equipment-transfer-sort')
        .firstOrNull
        ?.entityCategory;
    final selected = game.sites
        .where((site) => site.idString == selectedId)
        .firstOrNull;
    return _card('Move stored equipment', Icons.local_shipping_outlined, [
      const Text(
        '1. Choose the destination.  2. Move an item stack. Each move takes effect immediately.',
      ),
      const SizedBox(height: 10),
      _destinations('equipment-transfer-destination'),
      const SizedBox(height: 10),
      Text(
        'Destination: ${selected?.getName(includeCity: true) ?? 'choose a base'}',
        style: JournalPalette.heading,
      ),
      for (final action in console.actions.where(
        (action) => action.entityType == 'equipment-transfer-item',
      )) ...[const Divider(height: 13), _transferRow(action, selected)],
      _paging(),
      for (final action in console.actions.where(
        (action) => action.entityType == 'equipment-transfer-sort',
      ))
        TextButton(
          onPressed: _busy ? null : () => unawaited(_send(action)),
          child: Text(_label(action)),
        ),
      TextButton(
        onPressed: _busy ? null : () => unawaited(_route(_routes.closeSource)),
        child: const Text('Done moving equipment'),
      ),
    ]);
  }

  Widget _transferRow(ConsoleAction action, Site? destination) {
    final origin = game.sites
        .where((site) => site.idString == action.entityCategory)
        .firstOrNull;
    final alreadyHere = origin != null && origin == destination;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_label(action)),
              Text(
                'Stored at ${origin?.getName(includeCity: true) ?? 'unknown base'}',
                style: JournalPalette.small,
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        OutlinedButton(
          onPressed:
              _busy || !action.enabled || alreadyHere || destination == null
              ? null
              : () => unawaited(
                  _send(
                    action,
                    notice: 'Equipment moved to ${destination.getName()}.',
                  ),
                ),
          child: Text(alreadyHere ? 'Already here' : 'Move stack'),
        ),
      ],
    );
  }

  Widget _assignmentPanel() {
    final people = console.actions
        .where((action) => action.entityType == 'base-assignment-person')
        .toList();
    final selectedId = people.firstOrNull?.entityCategory;
    final selected = game.sites
        .where((site) => site.idString == selectedId)
        .firstOrNull;
    return _card('Assign home bases', Icons.groups_outlined, [
      const Text(
        '1. Choose a home base.  2. Assign a person outside squads. This changes their assigned base; cross-city moves require a squad.',
      ),
      const SizedBox(height: 10),
      _destinations('base-assignment-destination'),
      const SizedBox(height: 10),
      Text(
        'New home base: ${selected?.getName(includeCity: true) ?? 'choose a base'}',
        style: JournalPalette.heading,
      ),
      for (final action in people) ...[
        const Divider(height: 13),
        _assignmentRow(action, selected),
      ],
      _paging(),
      TextButton(
        onPressed: _busy ? null : () => unawaited(_route(_routes.closeSource)),
        child: const Text('Done assigning bases'),
      ),
    ]);
  }

  Widget _assignmentRow(ConsoleAction action, Site? destination) {
    final person = game.pool
        .where((person) => person.id.toString() == action.entityId)
        .firstOrNull;
    final alreadyHere = person?.base == destination;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(person?.name ?? _label(action), style: JournalPalette.heading),
        Text(
          'Home base: ${person?.base?.getName(includeCity: true) ?? 'none'}',
          style: JournalPalette.small,
        ),
        if (!action.enabled)
          Text(
            person?.base?.siege.underSiege == true &&
                    person?.base == person?.location
                ? 'Cannot reassign while present at a besieged base.'
                : 'Move between cities in a squad.',
            style: JournalPalette.small.copyWith(color: JournalPalette.danger),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed:
                _busy || !action.enabled || alreadyHere || destination == null
                ? null
                : () => unawaited(_send(action, notice: 'Home base assigned.')),
            child: Text(
              alreadyHere ? 'Already based here' : 'Assign home base',
            ),
          ),
        ),
      ],
    );
  }

  Widget _destinations(String type) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final action in console.actions.where(
        (action) =>
            action.entityType == type || action.entityType == '$type-selected',
      ))
        ChoiceChip(
          label: Text(_label(action)),
          selected: action.entityType == '$type-selected',
          onSelected: _busy || !action.enabled
              ? null
              : (_) => unawaited(_send(action)),
        ),
      for (final action in console.actions.where(
        (action) => action.key == '0' && action.label.contains('More Bases'),
      ))
        OutlinedButton(
          onPressed: _busy ? null : () => unawaited(_send(action)),
          child: const Text('More bases'),
        ),
    ],
  );

  Widget _paging() => Wrap(
    spacing: 8,
    children: [
      for (final action in console.actions.where(
        (action) =>
            action.label.contains('Previous Page') ||
            action.label.contains('Next Page'),
      ))
        TextButton(
          onPressed: _busy || !action.enabled
              ? null
              : () => unawaited(_send(action)),
          child: Text(_label(action)),
        ),
    ],
  );

  Widget _note(String text, {bool danger = false}) => Container(
    margin: const EdgeInsets.only(bottom: 9),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: JournalPalette.inset,
      border: Border.all(
        color: danger ? JournalPalette.danger : JournalPalette.rule,
      ),
    ),
    child: Text(
      text,
      style: JournalPalette.body.copyWith(
        color: danger ? JournalPalette.danger : JournalPalette.ink,
      ),
    ),
  );

  Widget _card(
    String title,
    IconData icon,
    List<Widget> children, {
    JournalIcon? illustration,
  }) => Material(
    color: JournalPalette.card,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: JournalPalette.rule),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (illustration != null)
                JournalIllustratedIcon(icon: illustration, size: 36)
              else
                Icon(icon, color: JournalPalette.brassDark, size: 23),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: JournalPalette.heading)),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    ),
  );
}

String _upgradeName(CompoundUpgrade upgrade) => switch (upgrade) {
  CompoundUpgrade.fortify => 'Fortifications',
  CompoundUpgrade.cameras => 'Security cameras',
  CompoundUpgrade.boobyTraps => 'Booby traps',
  CompoundUpgrade.bollards => 'Bollards',
  CompoundUpgrade.generator => 'Backup generator',
  CompoundUpgrade.solarPanels => 'Solar panels',
  CompoundUpgrade.aaGun => 'Anti-aircraft gun',
  CompoundUpgrade.videoRoom => 'Video studio',
  CompoundUpgrade.hackerDen => 'Hacker den',
  CompoundUpgrade.businessFront => 'Business front',
};
