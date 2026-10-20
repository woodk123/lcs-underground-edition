import 'package:shared_preferences/shared_preferences.dart';

class GameOptions {
  static const String _encounterWarningsKey = 'encounterWarnings';
  static const String _mouseInputKey = 'mouseInput';
  static const String _interfacePgUpKey = 'interfacePgUp';
  static const String _fontSizeKey = 'fontSize';
  static const String _lighterToneKey = 'lighterTone';
  static const String _journalScaleKey = 'journalReadingScale';
  static const String _journalCompactKey = 'journalCompactLayout';
  static const String _journalGuidanceKey = 'journalShowGuidance';
  bool encounterWarnings = false;
  bool mouseInput = true;
  double fontSize = 16;
  String interfacePgUp = "[";
  bool lighterTone = false;
  double journalScale = 1;
  bool journalCompact = false;
  bool journalGuidance = true;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    encounterWarnings = prefs.getBool(_encounterWarningsKey) ?? false;
    mouseInput = prefs.getBool(_mouseInputKey) ?? true;
    interfacePgUp = prefs.getString(_interfacePgUpKey) ?? "[";
    fontSize = prefs.getDouble(_fontSizeKey) ?? 16;
    lighterTone = prefs.getBool(_lighterToneKey) ?? false;
    final scale = prefs.getDouble(_journalScaleKey) ?? 1;
    journalScale = const [1.0, 1.25, 1.5].contains(scale) ? scale : 1;
    journalCompact = prefs.getBool(_journalCompactKey) ?? false;
    journalGuidance = prefs.getBool(_journalGuidanceKey) ?? true;
  }

  Future<void> saveJournalPresentation() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_journalCompactKey, journalCompact);
    await prefs.setBool(_journalGuidanceKey, journalGuidance);
  }

  Future<void> saveJournalScale() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_journalScaleKey, journalScale);
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_encounterWarningsKey, encounterWarnings);
    await prefs.setBool(_mouseInputKey, mouseInput);
    await prefs.setString(_interfacePgUpKey, interfacePgUp);
    await prefs.setDouble(_fontSizeKey, fontSize);
    await prefs.setBool(_lighterToneKey, lighterTone);
  }
}

final gameOptions = GameOptions();
