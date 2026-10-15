import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/items/item.dart';
import 'package:lcs_new_age/vehicles/vehicle.dart';

// References only the exact item/vehicle already shown by an original reader.
// This metadata is ephemeral and never serialized or used to execute an action.
final _items = Expando<Item>();
final _vehicles = Expando<Vehicle>();

void describeChoiceItem(Console console, String key, Item item) {
  final action = console.actions
      .where((a) => a.key == normalizeConsoleKey(key))
      .firstOrNull;
  if (action != null) _items[action] = item;
}

void describeChoiceVehicle(Console console, String key, Vehicle vehicle) {
  final action = console.actions.where((a) => a.key == key).firstOrNull;
  if (action != null) _vehicles[action] = vehicle;
}

Item? choiceItem(ConsoleAction action) => _items[action];
Vehicle? choiceVehicle(ConsoleAction action) => _vehicles[action];
