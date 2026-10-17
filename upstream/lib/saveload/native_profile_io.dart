import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

String? _dataDirectory;
String? get nativeDataDirectory => _dataDirectory;

/// Explicit profiles isolate both campaigns and preferences. APPDATA alone
/// cannot redirect the Windows preferences plugin's known-folder lookup.
Future<void> configureNativeProfile(List<String> arguments) async {
  final directories = arguments
      .where((a) => a.startsWith('--data-directory='))
      .toList();
  if (directories.isEmpty) {
    _dataDirectory = null;
    return;
  }
  if (directories.length != 1) {
    throw ArgumentError('Supply one data directory.');
  }
  final directory = directories.single.substring('--data-directory='.length);
  if (!path.isAbsolute(directory)) {
    throw ArgumentError('The data directory must be an absolute path.');
  }
  final root = await Directory(
    path.normalize(directory),
  ).create(recursive: true);
  final preferences = await ProfilePreferences.open(
    File(path.join(root.path, 'preferences.json')),
  );
  SharedPreferencesStorePlatform.instance = preferences;
  _dataDirectory = root.path;
}

/// Uses the plugin's standard filtering/type behavior with a profile-local
/// backing file, rather than reading or migrating a player's default settings.
class ProfilePreferences extends InMemorySharedPreferencesStore {
  ProfilePreferences._(this.file, Map<String, Object> data)
    : super.withData(data);

  final File file;
  Future<void> _pending = Future.value();

  static Future<ProfilePreferences> open(File file) async {
    final data = file.existsSync()
        ? Map<String, Object>.from(jsonDecode(await file.readAsString()) as Map)
        : <String, Object>{};
    return ProfilePreferences._(file, data);
  }

  Future<void> _persist() {
    _pending = _pending.then((_) async {
      final values = await super.getAllWithParameters(
        GetAllParameters(filter: PreferencesFilter(prefix: '')),
      );
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(jsonEncode(values), flush: true);
      await temporary.rename(file.path);
    });
    return _pending;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    await super.setValue(valueType, key, value);
    await _persist();
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    await super.remove(key);
    await _persist();
    return true;
  }

  @override
  Future<bool> clearWithParameters(ClearParameters parameters) async {
    await super.clearWithParameters(parameters);
    await _persist();
    return true;
  }
}
