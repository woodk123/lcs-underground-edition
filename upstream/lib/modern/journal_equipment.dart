import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/equipment_context.dart';
import 'package:lcs_new_age/items/ammo.dart';
import 'package:lcs_new_age/items/clothing.dart';
import 'package:lcs_new_age/items/item.dart';
import 'package:lcs_new_age/modern/catalogue_art.dart';
import 'package:lcs_new_age/modern/crew_portrait.dart';
import 'package:lcs_new_age/modern/equipment_help.dart';
import 'package:lcs_new_age/modern/equipment_preparation.dart';
import 'package:lcs_new_age/modern/journal_preferences.dart';
import 'package:lcs_new_age/modern/journal_shortcuts.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/squad_readiness.dart';

/// Presentation for the current equipment reader. Browsing changes local state;
/// every equipment change still dispatches one exact original source action.
class JournalEquipmentView extends StatefulWidget {
  const JournalEquipmentView({
    super.key,
    required this.console,
    required this.onAction,
    this.selectedPersonId,
    this.onInspect,
    this.onSelect,
  });

  final Console console;
  final ValueChanged<String> onAction;
  final int? selectedPersonId;
  final ValueChanged<Creature>? onInspect, onSelect;

  @override
  State<JournalEquipmentView> createState() => _JournalEquipmentViewState();
}

class _JournalEquipmentViewState extends State<JournalEquipmentView> {
  final _search = TextEditingController();
  final _loadoutScroll = ScrollController();
  EquipmentFilter _filter = EquipmentFilter.all;
  Item? _preview;
  int? _personId;
  String? _browsingIdentity;
  (String, int)? _requestedReveal;
  int? _revealedPersonId;
  int _revealGeneration = 0;

  String? get _storageId {
    final frame = equipmentContext(widget.console);
    return frame == null
        ? null
        : 'equipment-browsing:${frame.campaignId}:${frame.people.map((person) => person.id).join(':')}';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _restoreBrowsing();
  }

  void _restoreBrowsing() {
    final id = _storageId;
    if (_browsingIdentity != id && id != null) {
      _requestedReveal = null;
      _revealedPersonId = null;
      _revealGeneration++;
      final stored = PageStorage.maybeOf(context)
          ?.readState(context, identifier: id);
      if (stored is _EquipmentBrowsing) {
        _search.text = stored.search;
        _filter = stored.filter;
        _preview = stored.preview;
        _revealedPersonId = stored.revealedPersonId;
        final frame = equipmentContext(widget.console)!;
        final selected = _selectedPerson(frame);
        if (frame.phase == EquipmentPhase.inventory &&
            selected != null &&
            selected.id == _revealedPersonId) {
          // The inner ScrollPosition restores its own PageStorage offset.
          // A same-selection revisit should retain deliberate manual scrolling.
          _requestedReveal = (id, selected.id);
        }
      } else {
        _search.clear();
        _filter = EquipmentFilter.all;
        _preview = null;
      }
      _browsingIdentity = id;
    }
  }

  void _rememberBrowsing() {
    final id = _storageId;
    if (id != null) {
      PageStorage.maybeOf(context)?.writeState(
        context,
        _EquipmentBrowsing(_search.text, _filter, _preview, _revealedPersonId),
        identifier: id,
      );
    }
  }

  bool _current(EquipmentContext frame, int revision) =>
      mounted &&
      identical(equipmentContext(widget.console), frame) &&
      widget.console.revision.value == revision;

  Creature? _selectedPerson(EquipmentContext frame) =>
      frame.people.where((person) => person.id == _personId).firstOrNull ??
      frame.people.firstOrNull;

  void _selectPerson(EquipmentContext frame, Creature person, int revision) {
    if (!_current(frame, revision)) return;
    setState(() {
      _personId = person.id;
      _requestedReveal =
          null; // Explicit local clicks also reveal the same person.
    });
    widget.onSelect?.call(person);
  }

  void _revealSelectedCard(BuildContext cardContext, int personId) {
    final id = _storageId;
    if (id == null || _requestedReveal == (id, personId)) return;
    final request = (id, personId);
    _requestedReveal = request;
    final generation = ++_revealGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final frame = equipmentContext(widget.console);
      if (!mounted ||
          !cardContext.mounted ||
          generation != _revealGeneration ||
          _requestedReveal != request ||
          _storageId != id ||
          frame == null ||
          _selectedPerson(frame)?.id != personId ||
          !_loadoutScroll.hasClients ||
          !_loadoutScroll.position.hasContentDimensions) {
        return;
      }
      final target = cardContext.findRenderObject();
      if (target == null || !target.attached) return;
      // Use this position directly: Scrollable.ensureVisible also scrolls outer
      // ancestors, which would move the inventory/filter/comparison workspace.
      unawaited(
        _loadoutScroll.position.ensureVisible(
          target,
          alignment: 0,
          duration: Duration.zero,
        ),
      );
      _revealedPersonId = personId;
      _rememberBrowsing();
    });
  }

  @override
  void initState() {
    super.initState();
    _personId = widget.selectedPersonId;
  }

  @override
  void didUpdateWidget(covariant JournalEquipmentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedPersonId != widget.selectedPersonId) {
      _personId = widget.selectedPersonId;
    }
    _restoreBrowsing();
  }

  @override
  void dispose() {
    _search.dispose();
    _loadoutScroll.dispose();
    super.dispose();
  }

  VoidCallback? _command(
    EquipmentContext frame,
    ConsoleAction action,
    int revision,
  ) => action.enabled
      ? () {
          if (mounted &&
              equipmentActionIsCurrent(
                widget.console,
                frame,
                action,
                revision,
              )) {
            widget.onAction(action.key);
          }
        }
      : null;

  Widget _sourceButton(
    EquipmentContext frame,
    ConsoleAction action,
    int revision, {
    String? label,
    String? semanticLabel,
    bool directIdentity = true,
    bool available = true,
  }) {
    final activate = available ? _command(frame, action, revision) : null;
    final title = (label ?? action.intentLabel ?? action.label)
        .replaceFirst(
          RegExp(
            '^${RegExp.escape(action.key)}\\s*[-–:]\\s*',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
    final actor = frame.people
        .where(
          (person) =>
              {'person', 'equipment-recipient'}.contains(action.entityType) &&
              person.id.toString() == action.entityId,
        )
        .firstOrNull;
    final accessible =
        semanticLabel ??
        (actor != null
            ? '${action.key} ${actor.name}${action.intentLabel == null ? '' : ' · ${action.intentLabel}'}'
            : title);
    return MergeSemantics(
      child: Semantics(
        key: directIdentity
            ? ValueKey('direct-action:${action.y}:${action.x}:${action.key}')
            : ValueKey('equipment-apply:${action.key}'),
        button: true,
        enabled: activate != null,
        label: accessible,
        child: OutlinedButton(
          onPressed: activate,
          child: ExcludeSemantics(
            child: JournalCommandLabel(shortcut: action.key, label: title),
          ),
        ),
      ),
    );
  }

  Widget _art(Item item, {double width = 76, double height = 45}) {
    final art = equipmentArtwork(item.type.idName);
    return art == null
        ? Icon(
            item is Clothing ? Icons.checkroom : Icons.inventory_2_outlined,
            size: 30,
            color: JournalPalette.muted,
          )
        : CatalogueIllustration(art: art, width: width, height: height);
  }

  Widget _card(List<Widget> children, {bool selected = false}) => Material(
    color: selected ? JournalPalette.selected : JournalPalette.card,
    shape: RoundedRectangleBorder(
      side: BorderSide(
        color: selected ? JournalPalette.olive : JournalPalette.rule,
      ),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );

  Widget _personSelector(
    EquipmentContext frame,
    Creature person,
    int revision,
    int selectedId, {
    bool compact = false,
  }) => MergeSemantics(
    child: Semantics(
      key: ValueKey('equipment-person-row:${person.id}'),
      button: true,
      selected: person.id == selectedId,
      label: 'Select equipment for ${person.name}',
      child: TextButton(
        key: ValueKey('equipment-person:${person.id}'),
        onPressed: () => _selectPerson(frame, person, revision),
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          alignment: Alignment.centerLeft,
          backgroundColor: compact && person.id == selectedId
              ? JournalPalette.selected
              : null,
        ),
        child: ExcludeSemantics(
          child: Text(
            person.name,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ),
    ),
  );

  Widget _person(
    EquipmentContext frame,
    Creature person,
    SquadReadiness readiness,
    int revision,
    int selectedId, {
    bool selectableHeader = true,
  }) {
    final loadout = EquipmentLoadout(person, readiness);
    final action = frame.actions
        .where(
          (action) =>
              action.entityId == person.id.toString() &&
              (action.entityType == 'person' ||
                  action.entityType == 'equipment-recipient'),
        )
        .firstOrNull;
    return Builder(
      key: ValueKey('equipment-loadout:${person.id}'),
      builder: (cardContext) {
        if (selectableHeader && person.id == selectedId) {
          _revealSelectedCard(cardContext, person.id);
        }
        return _card([
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CrewPortrait(person: person, size: 56),
              const SizedBox(width: 8),
              Expanded(
                child: selectableHeader
                    ? _personSelector(frame, person, revision, selectedId)
                    : Text(
                        person.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
              if (widget.onInspect != null)
                IconButton(
                  tooltip: 'Inspect ${person.name}',
                  onPressed: () {
                    if (_current(frame, revision)) widget.onInspect!(person);
                  },
                  icon: const Icon(Icons.badge_outlined, size: 20),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _art(person.weapon),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loadout.weaponName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Text(loadout.skill),
                    Text(loadout.ammunition, style: JournalPalette.small),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _art(person.clothing, width: 45, height: 42),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Outfit: ${loadout.outfitName}'),
                    Text(loadout.condition, style: JournalPalette.small),
                  ],
                ),
              ),
            ],
          ),
          for (final warning in loadout.warnings)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                warning,
                style: const TextStyle(
                  color: JournalPalette.danger,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (action != null && frame.phase == EquipmentPhase.inventory) ...[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: _sourceButton(
                frame,
                action,
                revision,
                label: frame.phase == EquipmentPhase.inventory
                    ? 'Unequip weapon'
                    : switch (frame.phase) {
                        EquipmentPhase.giveItem => 'Give to ${person.name}',
                        EquipmentPhase.increaseAmmo =>
                          'Give ammo to ${person.name}',
                        EquipmentPhase.decreaseAmmo =>
                          'Drop ammo for ${person.name}',
                        EquipmentPhase.strip => 'Strip ${person.name}',
                        EquipmentPhase.inventory => 'Unequip weapon',
                      },
              ),
            ),
          ],
        ], selected: person.id == selectedId);
      },
    );
  }

  Widget _comparison(
    EquipmentContext frame,
    Creature person,
    Item candidate,
    int revision,
  ) {
    final current = equipmentReplacedBy(person, candidate);
    final choice = frame.stock
        .where((choice) => identical(choice.item, candidate))
        .firstOrNull;
    Widget values(String title, Item? item) => _card([
      Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      if (item == null)
        const Text('None carried')
      else ...[
        _art(item, width: 120, height: 64),
        Text(
          item.type.name,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        for (final line in equipmentFacts(item, person: person))
          Text(line, style: JournalPalette.small),
      ],
    ]);
    return Column(
      key: const ValueKey('equipment-compare'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Compare equipment for ${person.name}',
          style: JournalPalette.heading,
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, bounds) {
            final cards = [
              values('Current', current),
              values('Selected item', candidate),
            ];
            return bounds.maxWidth < 470
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [cards[0], const SizedBox(height: 8), cards[1]],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: cards[0]),
                      const SizedBox(width: 8),
                      Expanded(child: cards[1]),
                    ],
                  );
          },
        ),
        if (choice != null && choice.canEquip) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: _sourceButton(
              frame,
              choice.action,
              revision,
              label: 'Equip ${candidate.type.name}',
              directIdentity: false,
            ),
          ),
          if (frame.people.length > 1)
            const Text(
              'Choose who receives it after pressing Equip.',
              style: JournalPalette.small,
            ),
        ],
        if (choice != null && !choice.canEquip)
          const Text(
            'This item cannot be equipped by the current squad.',
            style: JournalPalette.small,
          ),
        Material(
          type: MaterialType.transparency,
          child: ExpansionTile(
            key: PageStorageKey(
              'equipment-item-details:${candidate.type.idName}',
            ),
            title: const Text('Equipment details'),
            children: [
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  equipmentHelp(
                    candidate.type,
                    armor: candidate is Clothing ? candidate.armor : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _stock(EquipmentContext frame, int revision) {
    final search = _search.text.trim().toLowerCase();
    final shown = frame.stock
        .where(
          (choice) =>
              equipmentMatchesFilter(choice.item, _filter) &&
              '${choice.item.type.name} ${equipmentStockSummary(choice.item)}'
                  .toLowerCase()
                  .contains(search),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(frame.inventoryName, style: JournalPalette.heading),
        Text(
          'Page ${frame.page + 1} of ${frame.pageCount} · ${frame.itemCount} stock entries',
          key: const ValueKey('equipment-page'),
          style: JournalPalette.small,
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('equipment-search'),
          controller: _search,
          onChanged: (_) {
            setState(() {});
            _rememberBrowsing();
          },
          decoration: const InputDecoration(
            labelText: 'Filter this page',
            prefixIcon: Icon(Icons.search),
            isDense: true,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 5,
          runSpacing: 4,
          children: [
            for (final filter in EquipmentFilter.values)
              ChoiceChip(
                key: ValueKey('equipment-filter:${filter.name}'),
                label: Text(switch (filter) {
                  EquipmentFilter.all => 'All',
                  EquipmentFilter.weapons => 'Weapons',
                  EquipmentFilter.outfits => 'Outfits',
                  EquipmentFilter.ammo => 'Ammo',
                  EquipmentFilter.other => 'Other',
                }),
                selected: filter == _filter,
                onSelected: (_) {
                  setState(() => _filter = filter);
                  _rememberBrowsing();
                },
              ),
          ],
        ),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              frame.itemCount == 0 ? 'No items in this inventory.' : 'No matches on this page. Other pages keep their original keys.',
            ),
          ),
        for (final choice in shown)
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: _card([
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      key: ValueKey('equipment-stock:${choice.action.key}'),
                      onPressed: () {
                        if (!_current(frame, revision)) return;
                        setState(() => _preview = choice.item);
                        _rememberBrowsing();
                      },
                      style: TextButton.styleFrom(
                        alignment: Alignment.centerLeft,
                      ),
                      child: Row(
                        children: [
                          _art(choice.item, width: 65, height: 44),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${choice.item.type.name}${choice.item.stackSize > 1 && choice.item is! Ammo && !choice.item.type.isMoney ? ' ×${choice.item.stackSize}' : ''}',
                                  semanticsLabel:
                                      'Preview ${choice.item.type.name}',
                                ),
                                Text(
                                  equipmentStockSummary(choice.item),
                                  style: JournalPalette.small,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _sourceButton(
                    frame,
                    choice.action,
                    revision,
                    label: choice.canEquip ? 'Equip' : 'Cannot equip',
                    available: choice.canEquip,
                    semanticLabel: choice.canEquip
                        ? 'Equip ${choice.item.type.name}, shortcut ${journalShortcutLabel(choice.action.key)}'
                        : 'Cannot equip ${choice.item.type.name}',
                  ),
                ],
              ),
              if (identical(choice.item, _preview)) ...[
                const Divider(height: 18),
                _comparison(
                  frame,
                  frame.people
                          .where((person) => person.id == _personId)
                          .firstOrNull ??
                      frame.people.first,
                  choice.item,
                  revision,
                ),
              ],
            ], selected: identical(choice.item, _preview)),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.console.revision,
    builder: (context, _) {
      final frame = equipmentContext(widget.console);
      if (frame == null || frame.people.isEmpty) return const SizedBox.shrink();
      if (frame.phase == EquipmentPhase.inventory &&
          !frame.stock.any((choice) => identical(choice.item, _preview))) {
        _preview = null;
      }
      final revision = widget.console.revision.value;
      final selected = _selectedPerson(frame)!;
      final readiness = SquadReadiness(frame.people);
      final stockActions = frame.stock.map((choice) => choice.action).toSet();
      final personActions = frame.actions
          .where(
            (action) =>
                action.entityType == 'person' ||
                action.entityType == 'equipment-recipient',
          )
          .toSet();
      return FocusTraversalGroup(
        policy: ReadingOrderTraversalPolicy(),
        child: DefaultTextStyle.merge(
          style: JournalPalette.body,
          child: Column(
            key: const ValueKey('journal-equipment-view'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                selected.name,
                key: const ValueKey('equipment-selected-person'),
                style: JournalPalette.heading,
              ),
              Text(
                readiness.summary,
                key: const ValueKey('equipment-readiness'),
                style: JournalPalette.small,
              ),
              if (frame.phase == EquipmentPhase.inventory &&
                  frame.people.length > 1)
                const Text(
                  'Preview stock to compare. Equip lets you choose who receives it.',
                  style: JournalPalette.small,
                ),
              if (frame.notice != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    frame.notice!,
                    style: const TextStyle(color: JournalPalette.danger),
                  ),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final action in frame.actions)
                    if (!stockActions.contains(action) &&
                        (!personActions.contains(action) ||
                            frame.phase != EquipmentPhase.inventory))
                      _sourceButton(
                        frame,
                        action,
                        revision,
                        label: switch (action.key) {
                          'Up' => 'Increase ammo allocation',
                          'Down' => 'Decrease ammo allocation',
                          's' => 'Strip a squad member',
                          'PageUp' => 'Previous page',
                          'PageDown' => 'Next page',
                          _ => null,
                        },
                      ),
                ],
              ),
              if (frame.phase != EquipmentPhase.inventory) ...[
                const SizedBox(height: 10),
                Text(switch (frame.phase) {
                  EquipmentPhase.giveItem =>
                    'Who receives ${frame.pendingItem!.type.name}?',
                  EquipmentPhase.increaseAmmo =>
                    'Who receives more ammunition?',
                  EquipmentPhase.decreaseAmmo => 'Who drops spare ammunition?',
                  EquipmentPhase.strip => 'Who should strip their equipment?',
                  EquipmentPhase.inventory => '',
                }, style: JournalPalette.heading),
                const Text(
                  'Choose a recipient, or Cancel to leave equipment unchanged.',
                  style: JournalPalette.small,
                ),
              ],
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, bounds) {
                  if (frame.phase == EquipmentPhase.inventory &&
                      bounds.maxWidth < 600) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          key: const ValueKey('equipment-crew-selector'),
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            for (final person in frame.people)
                              _personSelector(
                                frame,
                                person,
                                revision,
                                selected.id,
                                compact: true,
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _person(
                          frame,
                          selected,
                          readiness,
                          revision,
                          selected.id,
                          selectableHeader: false,
                        ),
                      ],
                    );
                  }
                  final columns = bounds.maxWidth >= 720 ? 2 : 1;
                  final width = (bounds.maxWidth - (columns - 1) * 8) / columns;
                  return ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: frame.phase == EquipmentPhase.inventory
                          ? 285
                          : 420,
                    ),
                    child: Scrollbar(
                      controller: _loadoutScroll,
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        controller: _loadoutScroll,
                        key: const PageStorageKey('equipment-loadout-scroll'),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final person in frame.people)
                              SizedBox(
                                width: width,
                                child: _person(
                                  frame,
                                  person,
                                  readiness,
                                  revision,
                                  selected.id,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              Material(
                type: MaterialType.transparency,
                child: ExpansionTile(
                  key: const PageStorageKey('equipment-preparation-details'),
                  title: const Text('Preparation details'),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Total learned skill levels: ${EquipmentLoadout(selected, readiness).totalSkillLevels}. The named weapon skill above is the level used for that weapon; neither value is an attack probability.',
                          ),
                          if (frame.transportation[selected.id]
                              case final transport? when transport.isNotEmpty)
                            Text('Transport: $transport'),
                          const SizedBox(height: 8),
                          SquadReadinessView(readiness: readiness),
                          if (JournalPreferences.of(context).showGuidance)
                            const Text(
                              'Keyboard letters equip immediately. Number keys unequip that person’s weapon; selecting a portrait only changes the comparison. Up/Down allocate ammunition. Equipment changes do not advance the day.',
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (frame.pendingItem case final pending?) ...[
                const Divider(height: 20),
                _comparison(frame, selected, pending, revision),
              ],
              if (frame.phase == EquipmentPhase.inventory) ...[
                const Divider(height: 20),
                _stock(frame, revision),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class _EquipmentBrowsing {
  const _EquipmentBrowsing(
    this.search,
    this.filter,
    this.preview,
    this.revealedPersonId,
  );
  final String search;
  final EquipmentFilter filter;
  final Item? preview;
  final int? revealedPersonId;
}
