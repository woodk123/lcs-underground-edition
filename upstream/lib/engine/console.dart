// ignore_for_file: constant_identifier_names

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:lcs_new_age/engine/console_char.dart';
import 'package:lcs_new_age/engine/console_graphic.dart';
import 'package:lcs_new_age/engine/creation_context.dart';
import 'package:lcs_new_age/utils/colors.dart';
import 'package:lcs_new_age/utils/game_options.dart';

const CONSOLE_WIDTH = 80;
const CONSOLE_HEIGHT = 25;

/// A choice exposed by the original game, before its terminal formatting.
@immutable
class ConsoleAction {
  const ConsoleAction({
    required this.key,
    required this.label,
    required this.enabled,
    required this.y,
    required this.x,
    required this.width,
    this.intentLabel,
    this.entityType,
    this.entityId,
    this.entityCategory,
  });

  final String key;
  final String label;
  final bool enabled;
  final int y;
  final int x;
  final int width;
  final String? intentLabel;
  // Presentation identity for entities already exposed by the current choice.
  // These fields never enumerate other locations or change input behavior.
  final String? entityType;
  final String? entityId;
  final String? entityCategory;
}

/// Uses the same color escape rules as [Console.addstrx]. Literal ampersands
/// (for example, "Equipment & Vehicles") remain readable.
String stripConsoleColors(String text) {
  final plain = StringBuffer();
  for (int i = 0; i < text.length; i++) {
    if ((text[i] == '&' || text[i] == '^') &&
        i + 1 < text.length &&
        colorMap.containsKey(text[i + 1])) {
      i++;
    } else {
      plain.write(text[i]);
    }
  }
  return plain.toString();
}

String normalizeConsoleKey(String key) {
  // Legacy mouse regions use the engine's control-character codes.
  const controls = {
    '\r': 'Enter',
    '\n': 'Enter',
    '\b': 'Backspace',
    '\t': 'Tab',
    '\x1b': 'Escape',
    '\x10': 'Shift',
    '\x11': 'Up',
    '\x12': 'Down',
    '\x13': 'Right',
    '\x14': 'Left',
    ' ': 'Space',
  };
  if (controls.containsKey(key)) return controls[key]!;
  final trimmed = key.trim();
  final lower = trimmed.toLowerCase();
  const named = {
    'any': 'Enter',
    'enter': 'Enter',
    'return': 'Enter',
    'backspace': 'Backspace',
    'tab': 'Tab',
    'shift': 'Shift',
    'arrowup': 'Up',
    'up': 'Up',
    'arrowdown': 'Down',
    'down': 'Down',
    'arrowright': 'Right',
    'right': 'Right',
    'arrowleft': 'Left',
    'left': 'Left',
    'space': 'Space',
    'escape': 'Escape',
    'esc': 'Escape',
    'pageup': 'PageUp',
    'pgup': 'PageUp',
    'pagedown': 'PageDown',
    'pgdn': 'PageDown',
  };
  for (final entry in named.entries) {
    if (lower == entry.key ||
        lower.startsWith('${entry.key} ') ||
        lower.startsWith('${entry.key}/')) {
      return entry.value;
    }
  }
  // Some original menus pass a key prefix such as "A - ".
  if (trimmed.length == 1 || RegExp(r'^[A-Za-z0-9?]\s+-').hasMatch(trimmed)) {
    return trimmed[0].toLowerCase();
  }
  return '';
}

@immutable
class ConsoleNavigation {
  const ConsoleNavigation({
    required this.section,
    this.backKey = 'Escape',
    this.note,
  });
  final String section;
  final String backKey;
  final String? note;
}

@immutable
class ConsoleArticle {
  const ConsoleArticle({
    required this.title,
    required this.publisher,
    required this.body,
    required this.date,
    this.byline,
    this.effects = const {},
  });
  final String title, publisher, body;
  final String? byline;
  final DateTime date;
  final Map<String, double> effects;
}

class Console {
  Color currentForeground = lightGray;
  Color currentBackground = black;
  int y = 0;
  int x = 0;
  int? hoverX;
  int? hoverY;
  int get width => CONSOLE_WIDTH;
  int get height => CONSOLE_HEIGHT;
  final List<List<ConsoleChar>> buffer = List.generate(
    CONSOLE_HEIGHT,
    (y) => List.generate(CONSOLE_WIDTH, (x) => ConsoleChar.blank()),
  );
  final List<KeyEvent> keyEvents = [];
  final List<ConsoleGraphic> graphics = [];
  final List<ConsoleAction> actions = [];
  String screen = 'generic';
  ConsoleNavigation? navigation;
  ConsoleArticle? article;
  CreationContext? creation;
  // Full text of the current original showMessage acknowledgement. This is
  // presentation metadata only; the retained buffer and input reader remain.
  String? eventMessage;

  void showArticle({
    required String title,
    required String publisher,
    required String body,
    required DateTime date,
    String? byline,
    Map<String, double> effects = const {},
  }) {
    article = ConsoleArticle(
      title: title,
      publisher: publisher,
      body: body,
      date: date,
      byline: byline,
      effects: Map.unmodifiable(effects),
    );
    screen = 'article';
  }

  bool textInput = false;
  String textInputValue = '';
  int textInputLimit = 0;
  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  Completer<KeyEvent>? nextKeyEvent;
  KeyEvent? lastKey;
  bool stale = true;
  VoidCallback? repaint;
  bool _readingInput = false;

  bool get awaitingInput => _readingInput;

  void flush() {
    stale = true;
    revision.value++;
    repaint?.call();
  }

  void addAction(
    String key,
    String text, {
    bool enabled = true,
    bool caseSensitive = false,
    String? intentLabel,
  }) {
    if (y < 0 || y >= height || x < 0 || x >= width) return;
    final label = stripConsoleColors(text).trim();
    final normalizedKey = caseSensitive && key.length == 1
        ? key
        : normalizeConsoleKey(key);
    if (label.isEmpty || normalizedKey.isEmpty) return;
    actions.removeWhere(
      (action) =>
          action.y == y &&
          action.x == x &&
          (action.key == normalizedKey || !caseSensitive),
    );
    actions.add(
      ConsoleAction(
        key: normalizedKey,
        label: label,
        enabled: enabled,
        y: y,
        x: x,
        width: min(stripConsoleColors(text).length, width - x),
        intentLabel: intentLabel,
      ),
    );
  }

  void annotateAction(String key, String intentLabel) {
    final lookup = actions.any((action) => action.key == key)
        ? key
        : normalizeConsoleKey(key);
    for (var index = 0; index < actions.length; index++) {
      final action = actions[index];
      if (action.key != lookup) continue;
      actions[index] = ConsoleAction(
        key: action.key,
        label: action.label,
        enabled: action.enabled,
        y: action.y,
        x: action.x,
        width: action.width,
        intentLabel: intentLabel,
        entityType: action.entityType,
        entityId: action.entityId,
        entityCategory: action.entityCategory,
      );
    }
  }

  void annotateActionEntity(
    String key, {
    required String type,
    required String id,
    String? category,
  }) {
    final lookup = actions.any((action) => action.key == key)
        ? key
        : normalizeConsoleKey(key);
    for (var index = 0; index < actions.length; index++) {
      final action = actions[index];
      if (action.key != lookup) continue;
      actions[index] = ConsoleAction(
        key: action.key,
        label: action.label,
        enabled: action.enabled,
        y: action.y,
        x: action.x,
        width: action.width,
        intentLabel: action.intentLabel,
        entityType: type,
        entityId: id,
        entityCategory: category,
      );
    }
  }

  // Mouse event handling
  /// Describes a nested prompt's exact choices without changing its key reader.
  void replaceActions(Map<String, String> choices) {
    navigation = null;
    actions.clear();
    var row = 0;
    for (final entry in choices.entries) {
      final key = normalizeConsoleKey(entry.key);
      if (key.isEmpty) continue;
      actions.add(
        ConsoleAction(
          key: key,
          label: stripConsoleColors(entry.value),
          enabled: true,
          y: row++ % height,
          x: 0,
          width: min(width, entry.value.length),
        ),
      );
    }
  }

  bool mouseEventMode = false;
  void Function(int y, int x, bool isDown)? onMouseEvent;

  void enableMouseEvents(void Function(int y, int x, bool isDown) callback) {
    mouseEventMode = true;
    onMouseEvent = callback;
  }

  void disableMouseEvents() {
    mouseEventMode = false;
    onMouseEvent = null;
  }

  void handleMouseEvent(int y, int x, bool isDown) {
    if (y < 0 || y >= height || x < 0 || x >= width) return;
    if (mouseEventMode && onMouseEvent != null) {
      onMouseEvent!(y, x, isDown);
    }
  }

  void setColor(Color foreground, Color background) {
    currentForeground = foreground;
    currentBackground = background;
  }

  void move(int y, int x) {
    this.y = y;
    this.x = x;
  }

  void erase() {
    navigation = null;
    article = null;
    creation = null;
    eventMessage = null;
    for (List<ConsoleChar> row in buffer) {
      row.fillRange(0, CONSOLE_WIDTH, ConsoleChar.blank());
    }
    graphics.clear();
    actions.clear();
    screen = 'generic';
    textInput = false;
    textInputValue = '';
    textInputLimit = 0;
  }

  void eraseArea({
    int startY = 0,
    int startX = 0,
    int endY = CONSOLE_HEIGHT,
    int endX = CONSOLE_WIDTH,
  }) {
    for (int y = max(startY, 0); y < min(endY, buffer.length); y++) {
      for (int x = max(startX, 0); x < min(endX, buffer[y].length); x++) {
        buffer[y][x] = ConsoleChar.blank();
      }
    }
    graphics.removeWhere(
      (g) =>
          g.left < endX &&
          g.right > startX &&
          g.top < endY &&
          g.bottom > startY,
    );
    actions.removeWhere(
      (action) =>
          action.y >= startY &&
          action.y < endY &&
          action.x < endX &&
          action.x + action.width > startX,
    );
  }

  void eraseLine(int y) => eraseArea(startY: y, endY: y + 1);

  void addchar(String c, {String? mouseClickKey}) {
    if (y < 0 || y >= buffer.length) return;
    if (x < 0 || x >= buffer[y].length) return;
    if (c == '█') {
      buffer[y][x] = ConsoleChar(
        ' ',
        currentForeground,
        currentForeground,
        mouseClickKey: mouseClickKey,
      );
    } else {
      buffer[y][x] = ConsoleChar(
        c,
        currentForeground,
        currentBackground,
        mouseClickKey: mouseClickKey,
      );
    }
    x++;
  }

  void registerMouseRegion(
    int y,
    int x,
    int width,
    int height,
    String key, {
    bool noHighlight = false,
  }) {
    for (int row = max(y, 0); row < min(y + height, this.height); row++) {
      for (int col = max(x, 0); col < min(x + width, this.width); col++) {
        buffer[row][col].mouseClickKey = key;
        buffer[row][col].noHighlight = noHighlight;
      }
    }
  }

  void handleMouseClick(int y, int x) {
    if (y < 0 || y >= buffer.length || x < 0 || x >= buffer[y].length) return;
    if (!gameOptions.mouseInput) return;
    String? key = buffer[y][x].mouseClickKey;
    key ??= "`";
    keyEvent(
      KeyDownEvent(
        logicalKey: LogicalKeyboardKey.keyA,
        physicalKey: PhysicalKeyboardKey.keyA,
        character: key,
        timeStamp: const Duration(),
      ),
    );
  }

  void mvaddchar(int y, int x, String c, {String? mouseClickKey}) {
    move(y, x);
    addchar(c, mouseClickKey: mouseClickKey);
  }

  void addstr(String s, {String? mouseClickKey}) {
    for (var i = 0; i < s.length; i++) {
      addchar(s[i], mouseClickKey: mouseClickKey);
    }
  }

  void mvaddstr(int y, int x, String s, {String? mouseClickKey}) {
    move(y, x);
    addstr(s, mouseClickKey: mouseClickKey);
  }

  void addstrx(String s, {bool restoreOldColor = true, String? mouseClickKey}) {
    const Color dummy = Color(0x00000000);
    bool validColorKey(int i) {
      return i < s.length - 1 && colorMap.containsKey(s[i + 1]);
    }

    Color oldBackground = currentBackground;
    Color oldForeground = currentForeground;
    for (var i = 0; i < s.length; i++) {
      if (s[i] == '&' && validColorKey(i)) {
        Color newColor = colorMap[s[++i]]!;
        if (newColor == dummy) newColor = oldForeground;
        setColor(newColor, currentBackground);
      } else if (s[i] == '^' && validColorKey(i)) {
        Color newColor = colorMap[s[++i]]!;
        if (newColor == dummy) newColor = oldBackground;
        setColor(currentForeground, newColor);
      } else {
        addchar(s[i], mouseClickKey: mouseClickKey);
      }
    }
    if (restoreOldColor) {
      setColor(oldForeground, oldBackground);
    }
  }

  void mvaddstrx(
    int y,
    int x,
    String s, {
    bool restoreOldColor = true,
    String? mouseClickKey,
  }) {
    move(y, x);
    addstrx(s, restoreOldColor: restoreOldColor, mouseClickKey: mouseClickKey);
  }

  void keyEvent(KeyEvent event) {
    // A second click in the same event turn must not overwrite the first choice
    // or complete an already completed Completer.
    if (nextKeyEvent?.isCompleted ?? false) return;
    lastKey = event;
    nextKeyEvent?.complete(event);
  }

  /// Dispatches a modern interface choice through the unchanged engine input.
  /// Drops clicks made while a previous choice is still being processed.
  bool sendInput(String key) {
    if (!_readingInput ||
        lastKey != null ||
        (nextKeyEvent?.isCompleted ?? false)) {
      return false;
    }
    final normalized = normalizeConsoleKey(key);
    if (normalized.isEmpty) return false;
    final (logical, physical, character) = switch (normalized) {
      'Enter' => (LogicalKeyboardKey.enter, PhysicalKeyboardKey.enter, '\r'),
      'Escape' => (
        LogicalKeyboardKey.escape,
        PhysicalKeyboardKey.escape,
        '\x1b',
      ),
      'Backspace' => (
        LogicalKeyboardKey.backspace,
        PhysicalKeyboardKey.backspace,
        '\b',
      ),
      'Tab' => (LogicalKeyboardKey.tab, PhysicalKeyboardKey.tab, '\t'),
      'Shift' => (LogicalKeyboardKey.shift, PhysicalKeyboardKey.shiftLeft, ''),
      'Up' => (LogicalKeyboardKey.arrowUp, PhysicalKeyboardKey.arrowUp, ''),
      'Down' => (
        LogicalKeyboardKey.arrowDown,
        PhysicalKeyboardKey.arrowDown,
        '',
      ),
      'Left' => (
        LogicalKeyboardKey.arrowLeft,
        PhysicalKeyboardKey.arrowLeft,
        '',
      ),
      'Right' => (
        LogicalKeyboardKey.arrowRight,
        PhysicalKeyboardKey.arrowRight,
        '',
      ),
      'PageUp' => (LogicalKeyboardKey.pageUp, PhysicalKeyboardKey.pageUp, '['),
      'PageDown' => (
        LogicalKeyboardKey.pageDown,
        PhysicalKeyboardKey.pageDown,
        ']',
      ),
      'Space' => (LogicalKeyboardKey.space, PhysicalKeyboardKey.space, ' '),
      _ => (
        LogicalKeyboardKey.keyA,
        PhysicalKeyboardKey.keyA,
        key.length == 1 ? key : normalized,
      ),
    };
    keyEvent(
      KeyDownEvent(
        logicalKey: logical,
        physicalKey: physical,
        character: character,
        timeStamp: Duration.zero,
      ),
    );
    return true;
  }

  Future<String> getkey() async {
    return keyEventToString(await getKeyEvent());
  }

  Future<KeyEvent> getKeyEvent() async {
    _readingInput = true;
    try {
      flush();
      while (true) {
        while (lastKey == null) {
          nextKeyEvent = Completer<KeyEvent>();
          await nextKeyEvent!.future;
          nextKeyEvent = null;
        }
        final result = lastKey!;
        lastKey = null;
        if (keyEventToString(result).isNotEmpty) return result;
      }
    } finally {
      _readingInput = false;
      navigation = null;
      if (screen == 'headquarters' || screen == 'tactical') actions.clear();
      // Main-screen markers describe one awaited decision. Notifications and
      // nested prompts may reuse the buffer without calling erase().
      screen = 'generic';
    }
  }

  String checkkey() {
    flush();
    String character = lastKey?.character ?? '';
    lastKey = null;
    return character;
  }

  void addGraphic(ConsoleGraphic graphic) {
    graphics.add(graphic);
  }
}

String keyEventToString(KeyEvent event) {
  switch (event.logicalKey) {
    case LogicalKeyboardKey.arrowUp:
      return "Up";
    case LogicalKeyboardKey.arrowDown:
      return "Down";
    case LogicalKeyboardKey.arrowLeft:
      return "Left";
    case LogicalKeyboardKey.arrowRight:
      return "Right";
    case LogicalKeyboardKey.pageUp:
      return "[";
    case LogicalKeyboardKey.pageDown:
      return "]";
    case LogicalKeyboardKey.tab:
      return "Tab";
    case LogicalKeyboardKey.escape:
      return "Escape";
    case LogicalKeyboardKey.backspace:
      return "Backspace";
    case LogicalKeyboardKey.enter:
      return "Enter";
    case LogicalKeyboardKey.shift:
      return "Shift";
    case LogicalKeyboardKey.less:
      return "<";
    case LogicalKeyboardKey.greater:
      return ">";
    default:
      return event.character ?? '';
  }
}
