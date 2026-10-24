import 'dart:convert';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:lcs_new_age/common_display/common_display.dart';
import 'package:lcs_new_age/creature/portrait.dart';
import 'package:lcs_new_age/daily/recruitment.dart';
import 'package:lcs_new_age/engine/engine.dart';
import 'package:lcs_new_age/gamestate/game_state.dart';
import 'package:lcs_new_age/gamestate/time.dart';
import 'package:lcs_new_age/items/clothing.dart';
import 'package:lcs_new_age/location/city.dart';
import 'package:lcs_new_age/location/district.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/newspaper/news_story.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/politics/laws.dart';
import 'package:lcs_new_age/politics/views.dart';
import 'package:lcs_new_age/saveload/storage/game_storage.dart';
import 'package:lcs_new_age/saveload/storage/storage_factory.dart';
import 'package:lcs_new_age/utils/colors.dart';
import 'package:lcs_new_age/utils/game_version.dart';
import 'package:lcs_new_age/utils/interface_options.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'save_load.g.dart';

late GameStorage _storage;

Future<void> initStorage({GameStorage? storage}) async {
  _storage = storage ?? createGameStorage();
  await _storage.init();

  // Check if we've already migrated
  final prefs = await SharedPreferences.getInstance();
  final bool hasMigrated = prefs.getBool('has_migrated_to_indexeddb') ?? false;

  if (!hasMigrated) {
    final bool migrated = await _migrateFromSharedPreferences();
    if (migrated) {
      await prefs.setBool('has_migrated_to_indexeddb', true);
    }
  }
}

Future<bool> _migrateFromSharedPreferences() async {
  final prefs = await SharedPreferences.getInstance();
  final List<String>? saveGameIds = prefs.getStringList("savedGameIds");
  if (saveGameIds == null) return true;

  bool migrationSuccessful = true;
  for (final gameId in saveGameIds) {
    final String? version = prefs.getString("gameVersion$gameId");
    final String? savedGame = prefs.getString("savedGame$gameId");
    final String? lastPlayed = prefs.getString("lastPlayed$gameId");

    if (savedGame != null) {
      final DateTime? lastPlayedDate = lastPlayed != null
          ? DateTime.tryParse(lastPlayed)
          : null;
      try {
        final saveFile = SaveFile(
          version: version ?? "ERROR",
          saveData: jsonDecode(savedGame),
          gameId: gameId,
          lastPlayed: lastPlayedDate,
        );
        await _storage.saveGame(saveFile);
      } catch (e) {
        debugPrint('Error migrating save game $gameId: $e');
        migrationSuccessful = false;
      }
    }
  }

  // Only delete from SharedPreferences if migration was successful
  if (migrationSuccessful) {
    // Delete all save-related keys
    for (final gameId in saveGameIds) {
      await prefs.remove("gameVersion$gameId");
      await prefs.remove("savedGame$gameId");
      await prefs.remove("lastPlayed$gameId");
    }
    // Delete the list of game IDs
    await prefs.remove("savedGameIds");
  }

  return migrationSuccessful;
}

Future<bool> autoSaveGame() async {
  final saveFile = SaveFile(
    version: saveCompatibilityVersion,
    saveData: gameState.toJson(),
    gameId: gameState.uniqueGameId.toString(),
    lastPlayed: DateTime.now(),
  );
  try {
    await _storage.saveGame(saveFile);
    await _storage.updateLastGameId(saveFile.gameId);
    return true;
  } catch (error) {
    await _showSaveError(
      'Your campaign could not be saved.',
      error,
      explanation:
          'Your current game is still open. No time has advanced. '
          'Check available storage, then try again.',
    );
    return false;
  }
}

@JsonSerializable()
class SaveFile {
  SaveFile({
    required this.version,
    required this.saveData,
    required this.gameId,
    required this.lastPlayed,
    this.gameState,
  });
  factory SaveFile.fromJson(Map<String, dynamic> json) {
    // Older (pre-1.0.2) saves stored saveData as a JSON-encoded string rather
    // than a nested object. Previously this code decoded it based on version
    // number, but migrating between save formats could cause this to be already
    // decoded regardless of version.
    if (json["saveData"] is String) {
      json["saveData"] = jsonDecode(json["saveData"] as String);
    }
    json["saveData"] = _migrateLegacyEquippedClothing(json["saveData"]);
    return _$SaveFileFromJson(json);
  }
  Map<String, dynamic> toJson() => _$SaveFileToJson(this);

  final String gameId;
  final String version;
  final Map<String, dynamic> saveData;
  final DateTime? lastPlayed;
  @JsonKey(includeToJson: false, includeFromJson: false)
  final GameState? gameState;
}

/// Older creature records called their outfit `equippedArmor`. Normalize the
/// schema before any creature deserializers run, including embedded recruits
/// and news-story characters. A current `equippedClothing` field (even null)
/// remains authoritative when a save contains both schemas.
Object? _migrateLegacyEquippedClothing(Object? value) {
  if (value is List) {
    return value.map(_migrateLegacyEquippedClothing).toList();
  } else if (value is Map<String, dynamic>) {
    final migrated = <String, dynamic>{
      for (final entry in value.entries)
        entry.key: _migrateLegacyEquippedClothing(entry.value),
    };
    final legacy = migrated['equippedArmor'];
    if (!migrated.containsKey('equippedClothing') &&
        legacy is Map<String, dynamic> &&
        legacy['typeName'] is String) {
      // Clothing resolves old ids through the existing item migration table.
      final defaults = Clothing(legacy['typeName'] as String);
      final type = defaults.type.idName;
      defaults.quality = (legacy['_quality'] as num?)?.toInt() ?? 1;
      defaults.damaged = false;
      migrated['equippedClothing'] = {
        // Old outfits stored no armor-health fields. Initialize those from
        // the corresponding current outfit so protective gear retains armor.
        ...defaults.toJson(),
        ...legacy,
        'typeName': type,
      };
      migrated.remove('equippedArmor');
    }
    return migrated;
  }
  return value;
}

final _saveVersionPattern = RegExp(r'^\d+(?:\.\d+)+$');

/// The portable JSON envelope shared by native files and browser downloads.
String encodeSaveContents(SaveFile save) => jsonEncode(save.toJson());

/// Validates a complete candidate without replacing the current campaign or
/// writing to storage. Old supported schemas use the same migrations as loads.
SaveFile decodeSaveContents(String contents) {
  Object? decoded;
  try {
    decoded = jsonDecode(contents);
  } on FormatException {
    throw const FormatException('The file is incomplete or is not valid JSON.');
  }
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('This file is not a New Age saved campaign.');
  }
  SaveFile save;
  try {
    save = SaveFile.fromJson(decoded);
  } catch (_) {
    throw const FormatException('The save header is missing or damaged.');
  }
  final candidate = _readCampaign(save);
  return SaveFile(
    version: save.version,
    saveData: save.saveData,
    gameId: save.gameId,
    lastPlayed: save.lastPlayed,
    gameState: candidate,
  );
}

GameState _readCampaign(SaveFile save) {
  if (!_saveVersionPattern.hasMatch(save.version)) {
    throw const FormatException('The save has an unsupported version label.');
  }
  if (compareVersionStrings(save.version, saveCompatibilityVersion) > 0) {
    throw FormatException(
      'This save requires New Age ${save.version} or later. '
      'This build supports save compatibility $saveCompatibilityVersion.',
    );
  }
  final data = save.saveData;
  if (save.gameId.isEmpty ||
      data['cities'] is! List ||
      (data['cities'] as List).isEmpty ||
      data['lcs'] is! Map ||
      (data['lcs'] as Map)['pool'] is! List ||
      data['politics'] is! Map ||
      data['date'] is! String ||
      DateTime.tryParse(data['date'] as String) == null) {
    throw const FormatException('The campaign data is incomplete or damaged.');
  }
  final previous = gameState;
  return withIsolatedRng(() {
    try {
      // Creature constructors allocate ids through the global gameState even
      // when called by a deserializer. Keep those allocations and all migration
      // work away from the open campaign until a validated load is committed.
      gameState = GameState();
      final candidate = GameState.fromJson(data);
      gameState = candidate;
      applyBugFixes(save.version);
      return candidate;
    } catch (_) {
      throw const FormatException(
        'The campaign data is incomplete or damaged.',
      );
    } finally {
      gameState = previous;
    }
  });
}

Future<void> _showSaveError(
  String title,
  Object error, {
  String? explanation,
}) async {
  erase();
  mvaddstrc(1, 1, red, title);
  final detail = error is FormatException ? error.message : error.toString();
  addparagraph(
    3,
    1,
    '${explanation ?? 'Your current campaign has not changed.'}\n\n$detail',
    y2: 20,
  );
  addOptionText(23, 1, 'Enter', 'Enter - Back');
  await acknowledge(title: 'Saved campaigns');
}

String _nameOfFounder(GameState gameState) {
  return gameState.lcs.pool
          .firstWhereOrNull(
            (e) => e.hireId == null && e.align == Alignment.liberal,
          )
          ?.name ??
      "Unknown";
}

Future<bool> loadGameMenu() async {
  while (true) {
    List<SaveFile> saveFiles = await loadGameList();
    if (saveFiles.isEmpty) {
      return false;
    }
    int selectedGame = -1;
    bool import = false;
    erase();
    await pagedInterface(
      count: saveFiles.length,
      headerPrompt: "Liberal Save Game Management System",
      headerKey: {
        4: "IN GAME DATE",
        20: "LCS LEADER",
        50: "LAST PLAYED",
        70: "VERSION",
      },
      footerPrompt:
          "Plus &B+&w to Import a save.  &BEnter&w to return to main menu.",
      lineBuilder: (y, key, index) {
        final SaveFile saveFile = saveFiles[index];
        if (saveFile.gameState == null) {
          setColor(red);
        } else {
          setColor(lightGray);
        }
        DateTime? lastPlayed = saveFile.lastPlayed?.toLocal();
        String version = saveFile.version;
        String inGameDate;
        String founder;
        String lastPlayedStr;
        if (lastPlayed != null) {
          lastPlayedStr =
              "${getMonthShort(lastPlayed.month)} ${lastPlayed.day}, ${lastPlayed.year}";
        } else {
          lastPlayedStr = "Unknown";
        }
        if (saveFile.gameState != null) {
          inGameDate =
              "${getMonthShort(saveFile.gameState!.date.month)} ${saveFile.gameState!.date.day}, ${saveFile.gameState!.date.year}";

          founder = _nameOfFounder(saveFile.gameState!);
        } else {
          inGameDate = "Error";
          founder = "Unavailable - check save details";
        }
        addOptionText(y, 0, key, "$key - ");
        mvaddstr(y, 4, inGameDate);
        mvaddstr(y, 20, founder);
        mvaddstr(y, 50, lastPlayedStr);
        if (_saveVersionPattern.hasMatch(version) &&
            compareVersionStrings(version, "1.2.0") < 0) {
          setColor(orange);
        } else {
          setColor(lightGray);
        }
        mvaddstr(y, 70, version);
        console.annotateActionEntity(
          key,
          type: 'save',
          id: saveFile.gameId,
          label: '$founder · $inGameDate',
        );
      },
      onChoice: (index) async {
        selectedGame = index;
        return true;
      },
      onOtherKey: (key) {
        if (key == Key.plus) {
          import = true;
          return true;
        } else if (isBackKey(key)) {
          return true;
        }
        return false;
      },
    );
    if (import) {
      await importSave();
      continue;
    }
    SaveFile? selectedSave = selectedGame >= 0 ? saveFiles[selectedGame] : null;
    if (selectedSave != null) {
      if (await loadGame(selectedSave)) {
        return true;
      }
    } else {
      return false;
    }
  }
}

Future<bool> loadGame(SaveFile selectedSave) async {
  bool broken = selectedSave.gameState == null;
  String brokenText = broken ? "Unavailable " : "";
  erase();
  int y = 3;
  if (!broken && compareVersionStrings(selectedSave.version, "1.2.0") < 0) {
    brokenText = "Outdated (${selectedSave.version}) ";
    setColor(orange);
    mvaddstr(
      y++,
      1,
      "This older save is expected to load, but some major changes are expected:",
    );
    mvaddstr(y++, 1, "- Many weapons will be renamed or replaced");
    mvaddstr(
      y++,
      1,
      "- Clips in inventory will be replaced with single bullets or shells",
    );
    mvaddstr(
      y++,
      1,
      "- Existing Black Bloc Armor items will become Black Bloc Outfits",
    );
    y++;
  }
  mvaddstrc(1, 1, lightGray, "Manage ${brokenText}Saved Game");
  addOptionText(
    y++,
    1,
    "L",
    "L - ${selectedSave.gameState != null ? "Load Game" : "Check why this save cannot load"}",
  );
  addOptionText(y++, 1, "D", "D - Delete Save");
  addOptionText(y++, 1, "E", "E - Export Save File");
  mvaddstr(++y, 1, "Press the key for the action you want to take.");
  while (true) {
    int c = await getKey();
    if (c == Key.l) {
      return await loadGameFromSave(selectedSave);
    } else if (c == Key.d) {
      await deleteSave(selectedSave);
      return false;
    } else if (c == Key.e) {
      await backupSave(selectedSave);
    } else if (c == Key.q || isBackKey(c)) {
      return false;
    }
  }
}

Future<bool> loadGameFromSave(SaveFile selectedSave) async {
  final previous = gameState;
  try {
    final candidate = _readCampaign(selectedSave);
    gameState = candidate;
    return true;
  } catch (error) {
    gameState = previous;
    await _showSaveError('This campaign could not be loaded.', error);
    return false;
  }
}

Future<void> deleteSave(SaveFile selectedSave) async {
  erase();
  mvaddstrc(1, 1, lightGray, "Delete Saved Game");
  mvaddstr(3, 1, "Are you SURE you want to delete this saved game?");
  addOptionText(5, 1, "Y", "Y - Yes, delete the save.");
  addOptionText(6, 1, "N", "N - No, do not delete the save.");
  while (true) {
    int c = await getKey();
    if (c == Key.y) {
      await deleteSaveGameId(selectedSave.gameId);
      return;
    } else if (c == Key.n) {
      return;
    }
  }
}

Future<void> deleteSaveGameId(String gameId) async {
  await _storage.deleteGame(gameId);
}

Future<void> backupSave(SaveFile selectedSave) async {
  // When trying to figure out which save is which, your founder's
  // name is probably the most memorable thing we've got to offer.
  // If your founder's name is " ", this will return "", but honestly
  // at that point it's your fault.
  final founderFirstName = selectedSave.gameState == null
      ? 'recovery'
      : _nameOfFounder(selectedSave.gameState!).toLowerCase().split(" ").first;
  final now = DateTime.now()
      .toIso8601String()
      .replaceAll("-", "_") // - in YYYY-MM-DD
      .replaceAll("T", "-") // T between date and time
      .replaceAll(":", "_") // : in HH:MM:SS
      .replaceAll(".", "-") // . before ms and us
      .replaceAll("Z", "") // Z at the end if the clock is in UTC
      ;

  try {
    await FileSaver.instance.saveFile(
      name: "lcsna_${founderFirstName}_$now.json",
      bytes: const Utf8Encoder().convert(encodeSaveContents(selectedSave)),
    );
  } catch (error) {
    await _showSaveError('The backup could not be exported.', error);
  }
}

Future<SaveFile?> importSave() async {
  try {
    final result = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ["json"],
      dialogTitle: "Select an LCS: New Age Save File",
    );
    if (result == null) return null;
    final bytes = await result.readAsBytes();
    return await importSaveBytes(bytes);
  } catch (error) {
    await _showSaveError('The save could not be imported.', error);
    return null;
  }
}

/// Import entry point shared by the file picker and recovery tests. Validation
/// completes before a matching existing save can be overwritten.
Future<SaveFile?> importSaveBytes(Uint8List bytes) async {
  try {
    final save = decodeSaveContents(const Utf8Decoder().convert(bytes));
    await saveGameFile(save);
    erase();
    mvaddstrc(1, 1, lightGray, 'Save imported successfully.');
    addOptionText(3, 1, 'Enter', 'Enter - Continue');
    await acknowledge(title: 'Saved campaigns');
    return save;
  } catch (error) {
    await _showSaveError('The save could not be imported.', error);
    return null;
  }
}

Future<void> saveGameFile(SaveFile saveFile) async {
  await _storage.saveGame(saveFile);
}

Future<List<SaveFile>> loadGameList() async {
  final List<String> gameIds = await _storage.listGameIds();
  List<SaveFile> saveFiles = [];

  for (final gameId in gameIds) {
    SaveFile? saveFile;
    try {
      saveFile = await _storage.loadGame(gameId);
    } catch (error) {
      debugPrint('Error reading save game $gameId: $error');
      continue;
    }
    if (saveFile != null) {
      try {
        final GameState gameState = _readCampaign(saveFile);
        saveFiles.add(
          SaveFile(
            version: saveFile.version,
            saveData: saveFile.saveData,
            lastPlayed: saveFile.lastPlayed,
            gameId: saveFile.gameId,
            gameState: gameState,
          ),
        );
      } catch (e) {
        debugPrint('Error loading save game $gameId: $e');
        saveFiles.add(saveFile);
      }
    }
  }

  return saveFiles;
}

Future<void> deleteSaveGame() async {
  await deleteSaveGameId(gameState.uniqueGameId.toString());
}

int compareVersionStrings(String a, String b) {
  List<int> aParts = a.split(".").map(int.parse).toList();
  List<int> bParts = b.split(".").map(int.parse).toList();
  for (int i = 0; i < aParts.length; i++) {
    if (i >= bParts.length) {
      return 1;
    }
    if (aParts[i] > bParts[i]) {
      return 1;
    } else if (aParts[i] < bParts[i]) {
      return -1;
    }
  }
  if (aParts.length < bParts.length) {
    return -1;
  }
  return 0;
}

void applyBugFixes(String version) {
  // Older saves can retain assignments to a sold or otherwise lost vehicle.
  // Repair references without creating a vehicle or changing valid choices.
  final vehicleIds = vehiclePool.map((vehicle) => vehicle.id).toSet();
  for (final person in pool) {
    if (person.carId != null && !vehicleIds.contains(person.carId)) {
      person.carId = null;
      person.isDriver = false;
    }
    if (person.preferredCarId != null &&
        !vehicleIds.contains(person.preferredCarId)) {
      person.preferredCarId = null;
      person.preferredDriver = false;
    }
  }
  gameState.uniqueCreatures.syncWithPool();
  for (RecruitmentSession recruitmentSession in gameState.recruitmentSessions) {
    recruitmentSession.recruiter = pool.firstWhere(
      (p) => p.id == recruitmentSession.recruiterId,
      orElse: () => pool[0],
    );
  }
  if (compareVersionStrings(version, "1.0.5") < 0) {
    // Fix for the bug where CCS safehouses don't get marked as such if you
    // play in "We Didn't Start The Fire" mode
    if (ccsActive) {
      for (Site s in sites.where(
        (s) =>
            s.controller == SiteController.unaligned &&
            [
              SiteType.barAndGrill,
              SiteType.bombShelter,
              SiteType.bunker,
            ].contains(s.type),
      )) {
        s.controller = SiteController.ccs;
      }
    }
  }
  if (compareVersionStrings(version, "1.3.4") < 0) {
    for (NewsStory newsStory in gameState.newsArchive) {
      if (newsStory.byline == "") newsStory.byline = null;
      if (newsStory.newspaperPhotoId == 0 &&
          newsStory.headline != "HELL ON EARTH") {
        newsStory.newspaperPhotoId = null;
      }
    }
  }
  if (compareVersionStrings(version, "1.5.0") < 0) {
    // 1.5: Add new insurance office and nursing home locations
    for (City city in gameState.cities) {
      for (District district in city.districts) {
        if (district.name.contains("Downtown")) {
          district.addSites([SiteType.insuranceOffice]);
        }
        if (district.name.contains("University") ||
            district.name.contains("Brooklyn") ||
            district.name.contains("Hollywood")) {
          district.addSites([SiteType.nursingHome]);
        }
      }
    }
  }
  // Fix ceo and president locations
  if (!uniqueCreatures.ceo.kidnapped &&
      !uniqueCreatures.ceo.missing &&
      uniqueCreatures.ceo.align == Alignment.conservative &&
      uniqueCreatures.ceo.site?.type != SiteType.ceoHouse) {
    uniqueCreatures.ceo.location = sites.firstWhere(
      (s) => s.type == SiteType.ceoHouse,
    );
    uniqueCreatures.ceo.workLocation = uniqueCreatures.ceo.location;
  }
  if (!uniqueCreatures.president.kidnapped &&
      !uniqueCreatures.president.missing &&
      uniqueCreatures.president.align == Alignment.conservative &&
      uniqueCreatures.president.site?.type != SiteType.whiteHouse) {
    uniqueCreatures.president.location = sites.firstWhere(
      (s) => s.type == SiteType.whiteHouse,
    );
    uniqueCreatures.president.workLocation = uniqueCreatures.president.location;
  }
  // Populate any missing laws
  Map<DeepAlignment, int> lawAlignments = {};
  for (DeepAlignment alignment in gameState.politics.laws.values) {
    lawAlignments[alignment] = (lawAlignments[alignment] ?? 0) + 1;
  }
  MapEntry<DeepAlignment, int>? mostCommonLawAlignment = lawAlignments.entries
      .fold(
        null,
        (max, entry) => entry.value > (max?.value ?? 0) ? entry : max,
      );
  for (Law law in Law.values) {
    gameState.politics.laws[law] ??=
        mostCommonLawAlignment?.key ?? DeepAlignment.conservative;
  }
  // Populate any missing public opinion issues
  double publicMood = gameState.politics.publicMood();
  for (View view in View.issues) {
    gameState.politics.publicOpinion[view] ??= publicMood;
    gameState.politics.publicInterest[view] ??= 0;
    gameState.politics.backgroundInfluence[view] ??= 0;
  }
  assignKnownPortraits();
}
