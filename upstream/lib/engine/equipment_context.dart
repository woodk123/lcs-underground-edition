import 'package:flutter/foundation.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/items/item.dart';

enum EquipmentPhase { inventory, giveItem, increaseAmmo, decreaseAmmo, strip }

/// One item and the exact letter authored for it on the current source page.
@immutable
class EquipmentStock {
  const EquipmentStock({
    required this.item,
    required this.action,
    required this.canEquip,
  });

  final Item item;
  final ConsoleAction action;
  final bool canEquip;
}

/// Ephemeral presentation metadata for an original equipment input reader.
/// References describe the actual squad and inventory; they never execute or
/// simulate an equipment change, allocate an item, or become saved state.
@immutable
class EquipmentContext {
  EquipmentContext({
    required this.phase,
    required this.campaignId,
    required Iterable<Creature> people,
    required Iterable<EquipmentStock> stock,
    required Iterable<ConsoleAction> actions,
    required Map<int, String> transportation,
    required this.page,
    required this.itemCount,
    required this.inventoryName,
    this.pendingItem,
    this.notice,
  }) : people = List.unmodifiable(people),
       stock = List.unmodifiable(stock),
       actions = List.unmodifiable(actions),
       transportation = Map.unmodifiable(transportation);

  final EquipmentPhase phase;
  final int campaignId;
  final List<Creature> people;
  final List<EquipmentStock> stock;
  final List<ConsoleAction> actions;
  final Map<int, String> transportation;
  final int page, itemCount;
  final String inventoryName;
  final Item? pendingItem;
  final String? notice;

  int get pageCount => itemCount == 0 ? 1 : (itemCount / 18).ceil();
}

EquipmentContext? equipmentContext(Console console) {
  final frame = console.equipment;
  return console.awaitingInput &&
          !console.textInput &&
          console.eventMessage == null &&
          console.journalProfile == null &&
          console.screen == 'equipment' &&
          frame != null &&
          frame.actions.length == console.actions.length &&
          frame.actions.every(console.actions.contains)
      ? frame
      : null;
}

bool equipmentActionIsCurrent(
  Console console,
  EquipmentContext frame,
  ConsoleAction action,
  int revision,
) =>
    action.enabled &&
    console.revision.value == revision &&
    identical(equipmentContext(console), frame) &&
    frame.actions.contains(action) &&
    console.actions.contains(action) &&
    console.lastKey == null;
