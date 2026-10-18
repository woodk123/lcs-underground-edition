import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/items/item.dart';
import 'package:lcs_new_age/vehicles/vehicle.dart';

// References only the exact item/vehicle already shown by an original reader.
// This metadata is ephemeral and never serialized or used to execute an action.
final _items = Expando<Item>();
final _vehicles = Expando<Vehicle>();
final _itemTypes = Expando<String>();
final _vehicleTypes = Expando<String>();
final _descriptions =
    Expando<Map<int, ({ConsoleAction action, String text})>>();

ConsoleAction? _choiceAction(Console console, String key) =>
    console.actions.where((action) => action.key == key).firstOrNull ??
    console.actions
        .where((action) => action.key == normalizeConsoleKey(key))
        .firstOrNull;

void describeChoiceItem(Console console, String key, Item item) {
  final action = _choiceAction(console, key);
  if (action != null) _items[action] = item;
}

void describeChoiceVehicle(Console console, String key, Vehicle vehicle) {
  final action = _choiceAction(console, key);
  if (action != null) _vehicles[action] = vehicle;
}

/// Catalogue previews never construct an item or vehicle, allocate an ID or
/// consume the gameplay random stream. Metadata belongs to this exact action.
void describeChoiceItemType(Console console, String key, String typeId) {
  final action = _choiceAction(console, key);
  if (action != null) _itemTypes[action] = typeId;
}

void describeChoiceVehicleType(Console console, String key, String typeId) {
  final action = _choiceAction(console, key);
  if (action != null) _vehicleTypes[action] = typeId;
}

/// A full-width continuation authored by a catalogue reader, tied to its live
/// choice. Replaced readers cannot inherit an earlier product's description.
void describeChoiceItemDescription(
  Console console,
  String key,
  int row,
  String text,
) {
  final action = _choiceAction(console, key);
  if (action == null) return;
  (_descriptions[console] ??= {})[row] = (action: action, text: text);
}

String? choiceItemDescription(Console console, int row) {
  final description = _descriptions[console]?[row];
  return description != null && console.actions.contains(description.action)
      ? description.text
      : null;
}

Item? choiceItem(ConsoleAction action) => _items[action];
Vehicle? choiceVehicle(ConsoleAction action) => _vehicles[action];
String? choiceItemTypeId(ConsoleAction action) =>
    choiceItem(action)?.type.idName ?? _itemTypes[action];
String? choiceVehicleTypeId(ConsoleAction action) =>
    choiceVehicle(action)?.typeName ?? _vehicleTypes[action];
