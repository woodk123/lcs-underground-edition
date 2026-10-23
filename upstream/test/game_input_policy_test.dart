import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/modern/game_input_policy.dart';
import 'package:lcs_new_age/modern/journal_navigation_shortcuts.dart';
import 'package:lcs_new_age/modern/journal_sections.dart';

const _a = KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.keyA,
  logicalKey: LogicalKeyboardKey.keyA,
  timeStamp: Duration.zero,
);
const _escape = KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.escape,
  logicalKey: LogicalKeyboardKey.escape,
  timeStamp: Duration.zero,
);
const _f1 = KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.f1,
  logicalKey: LogicalKeyboardKey.f1,
  timeStamp: Duration.zero,
);
const _enter = KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.enter,
  logicalKey: LogicalKeyboardKey.enter,
  timeStamp: Duration.zero,
);
const _space = KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.space,
  logicalKey: LogicalKeyboardKey.space,
  timeStamp: Duration.zero,
);
const _people = KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.digit2,
  logicalKey: LogicalKeyboardKey.digit2,
  timeStamp: Duration.zero,
);
const _wait = KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.keyW,
  logicalKey: LogicalKeyboardKey.keyW,
  timeStamp: Duration.zero,
);
const _save = KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.keyX,
  logicalKey: LogicalKeyboardKey.keyX,
  timeStamp: Duration.zero,
);

void main() {
  for (final (name, state, event, expected)
      in <(String, GameInputState, KeyEvent, GameKeyRoute)>[
        (
          'overlay precedes inspection and editor Escape',
          const GameInputState(
            overlayOpen: true,
            inspecting: true,
            sourceTextInput: true,
            sending: true,
          ),
          _escape,
          GameKeyRoute.ignore,
        ),
        (
          'overlay precedes F1',
          const GameInputState(overlayOpen: true),
          _f1,
          GameKeyRoute.ignore,
        ),
        (
          'inspection Escape precedes busy state',
          const GameInputState(inspecting: true, controllerBusy: true),
          _escape,
          GameKeyRoute.closeInspection,
        ),
        (
          'inspection owns F1',
          const GameInputState(inspecting: true),
          _f1,
          GameKeyRoute.ignore,
        ),
        (
          'Classic leaves inspection handling to its own path',
          const GameInputState(classic: true, inspecting: true),
          _a,
          GameKeyRoute.readerHandlers,
        ),
        (
          'editor Escape precedes inspection, focus and submission busy state',
          const GameInputState(
            inspecting: true,
            sourceTextInput: true,
            entryFocused: true,
            editableFocused: true,
            sending: true,
          ),
          _escape,
          GameKeyRoute.submitEditedText,
        ),
        (
          'F1 precedes focused editor ownership',
          const GameInputState(
            sourceTextInput: true,
            entryFocused: true,
            editableFocused: true,
          ),
          _f1,
          GameKeyRoute.openHelp,
        ),
        (
          'entry field owns ordinary text',
          const GameInputState(entryFocused: true),
          _a,
          GameKeyRoute.ignore,
        ),
        (
          'search owns ordinary text',
          const GameInputState(editableFocused: true),
          _a,
          GameKeyRoute.ignore,
        ),
        (
          'search owns Escape',
          const GameInputState(editableFocused: true),
          _escape,
          GameKeyRoute.ignore,
        ),
        (
          'help cannot reopen while open',
          const GameInputState(helpOpen: true),
          _f1,
          GameKeyRoute.ignore,
        ),
        (
          'submission blocks ordinary keys',
          const GameInputState(sending: true),
          _a,
          GameKeyRoute.ignore,
        ),
        (
          'navigation blocks ordinary keys',
          const GameInputState(navigating: true),
          _a,
          GameKeyRoute.ignore,
        ),
        (
          'controller work blocks ordinary keys',
          const GameInputState(controllerBusy: true),
          _a,
          GameKeyRoute.ignore,
        ),
        (
          'raw source key can discard a pointer draft',
          const GameInputState(hasDraft: true),
          _wait,
          GameKeyRoute.readerHandlers,
        ),
        (
          'chapter opening retains physical reader timing',
          const GameInputState(openingJournalSection: true),
          _a,
          GameKeyRoute.readerHandlers,
        ),
        (
          'changelog retains its existing physical handler path',
          const GameInputState(changelogOpen: true),
          _a,
          GameKeyRoute.readerHandlers,
        ),
        (
          'physical keys do not depend on a rendered action revision',
          const GameInputState(renderedRevisionCurrent: false),
          _a,
          GameKeyRoute.readerHandlers,
        ),
        (
          'unfocused source text still permits local reader handlers first',
          const GameInputState(sourceTextInput: true),
          _a,
          GameKeyRoute.readerHandlers,
        ),
        (
          'Tab Enter belongs to a deliberately focused control',
          const GameInputState(
            keyboardTraversal: true,
            gameHasPrimaryFocus: false,
          ),
          _enter,
          GameKeyRoute.ignore,
        ),
        (
          'Tab Space belongs to a deliberately focused control',
          const GameInputState(
            keyboardTraversal: true,
            gameHasPrimaryFocus: false,
          ),
          _space,
          GameKeyRoute.ignore,
        ),
        (
          'pointer-retained Enter keeps source timing',
          const GameInputState(gameHasPrimaryFocus: false),
          _enter,
          GameKeyRoute.readerHandlers,
        ),
        (
          'pointer-retained Space keeps source timing',
          const GameInputState(gameHasPrimaryFocus: false),
          _space,
          GameKeyRoute.readerHandlers,
        ),
        (
          'game focus receives Enter after traversal',
          const GameInputState(keyboardTraversal: true),
          _enter,
          GameKeyRoute.readerHandlers,
        ),
        (
          'key release never forwards input',
          const GameInputState(),
          const KeyUpEvent(
            physicalKey: PhysicalKeyboardKey.keyA,
            logicalKey: LogicalKeyboardKey.keyA,
            timeStamp: Duration.zero,
          ),
          GameKeyRoute.ignore,
        ),
        (
          'held source keys keep repeating',
          const GameInputState(),
          const KeyRepeatEvent(
            physicalKey: PhysicalKeyboardKey.keyA,
            logicalKey: LogicalKeyboardKey.keyA,
            timeStamp: Duration.zero,
          ),
          GameKeyRoute.readerHandlers,
        ),
        (
          'held F1 does not reopen help',
          const GameInputState(),
          const KeyRepeatEvent(
            physicalKey: PhysicalKeyboardKey.f1,
            logicalKey: LogicalKeyboardKey.f1,
            timeStamp: Duration.zero,
          ),
          GameKeyRoute.readerHandlers,
        ),
        (
          'held inspection Escape does not close inspection',
          const GameInputState(inspecting: true),
          const KeyRepeatEvent(
            physicalKey: PhysicalKeyboardKey.escape,
            logicalKey: LogicalKeyboardKey.escape,
            timeStamp: Duration.zero,
          ),
          GameKeyRoute.ignore,
        ),
        (
          'Tab stays with traversal',
          const GameInputState(),
          const KeyDownEvent(
            physicalKey: PhysicalKeyboardKey.tab,
            logicalKey: LogicalKeyboardKey.tab,
            timeStamp: Duration.zero,
          ),
          GameKeyRoute.ignore,
        ),
        (
          'modifier key stays with the platform',
          const GameInputState(),
          const KeyDownEvent(
            physicalKey: PhysicalKeyboardKey.shiftLeft,
            logicalKey: LogicalKeyboardKey.shiftLeft,
            timeStamp: Duration.zero,
          ),
          GameKeyRoute.ignore,
        ),
      ]) {
    test(
      name,
      () => expect(GameInputPolicy.keyboard(state, event).route, expected),
    );
  }

  test('Alt routes describe the existing section and global command', () {
    const state = GameInputState(journalAvailable: true, hasDraft: true);
    final section = GameInputPolicy.keyboard(state, _people, alt: true);
    expect(section.route, GameKeyRoute.journalSection);
    expect(section.section, JournalSection.people);
    expect(
      GameInputPolicy.keyboard(state, _wait, alt: true).command,
      JournalGlobalCommand.advanceDay,
    );
    expect(
      GameInputPolicy.keyboard(state, _save, alt: true).command,
      JournalGlobalCommand.saveAndExit,
    );
    // The current journal control still decides whether a draft/report allows it.
  });

  test('combined modifiers, Classic, missing journal and focused search suppress Alt routes', () {
    for (final state in [
      const GameInputState(classic: true, journalAvailable: true),
      const GameInputState(),
      const GameInputState(journalAvailable: true, editableFocused: true),
    ]) {
      expect(
        GameInputPolicy.keyboard(state, _people, alt: true).route,
        GameKeyRoute.ignore,
      );
    }
    const state = GameInputState(journalAvailable: true);
    expect(
      GameInputPolicy.keyboard(state, _people, alt: true, shift: true).route,
      GameKeyRoute.ignore,
    );
    expect(
      GameInputPolicy.keyboard(state, _people, alt: true, control: true).route,
      GameKeyRoute.ignore,
    );
    expect(
      GameInputPolicy.keyboard(state, _people, alt: true, meta: true).route,
      GameKeyRoute.ignore,
    );
    expect(
      GameInputPolicy.keyboard(state, _a, control: true).route,
      GameKeyRoute.ignore,
    );
    expect(
      GameInputPolicy.keyboard(state, _a, meta: true).route,
      GameKeyRoute.ignore,
    );
    expect(
      GameInputPolicy.keyboard(state, _a, shift: true).route,
      GameKeyRoute.readerHandlers,
    );
    expect(
      GameInputPolicy.keyboard(state, _f1, control: true).route,
      GameKeyRoute.openHelp,
    );
    expect(
      GameInputPolicy.keyboard(
        const GameInputState(sourceTextInput: true),
        _escape,
        alt: true,
      ).route,
      GameKeyRoute.submitEditedText,
    );
  });

  for (final (name, state, reason) in <(String, GameInputState, String?)>[
    (
      'unmounted precedes every overlay',
      const GameInputState(
        mounted: false,
        changelogOpen: true,
        overlayOpen: true,
      ),
      'shell_unavailable',
    ),
    (
      'changelog precedes modal',
      const GameInputState(changelogOpen: true, overlayOpen: true),
      'changelog_open',
    ),
    (
      'overlay precedes inspection',
      const GameInputState(overlayOpen: true, inspecting: true),
      'modal_open',
    ),
    (
      'help precedes busy',
      const GameInputState(helpOpen: true, controllerBusy: true),
      'modal_open',
    ),
    (
      'inspection includes Classic and source text',
      const GameInputState(
        classic: true,
        inspecting: true,
        sourceTextInput: true,
      ),
      'inspection_open',
    ),
    ('submission is busy', const GameInputState(sending: true), 'ui_busy'),
    (
      'navigation precedes draft',
      const GameInputState(navigating: true, hasDraft: true),
      'ui_busy',
    ),
    (
      'opening a chapter is busy',
      const GameInputState(openingJournalSection: true),
      'ui_busy',
    ),
    (
      'controller work is busy',
      const GameInputState(controllerBusy: true),
      'ui_busy',
    ),
    (
      'draft precedes search',
      const GameInputState(hasDraft: true, editableFocused: true),
      'unconfirmed_draft',
    ),
    (
      'draft blocks source text too',
      const GameInputState(hasDraft: true, sourceTextInput: true),
      'unconfirmed_draft',
    ),
    (
      'search retains its editor',
      const GameInputState(editableFocused: true),
      'text_editor_focused',
    ),
    (
      'source text permits the bridge editor replay',
      const GameInputState(sourceTextInput: true, editableFocused: true),
      null,
    ),
    ('available reader is allowed', const GameInputState(), null),
  ]) {
    test(
      'bridge: $name',
      () => expect(GameInputPolicy.developmentBlockedReason(state), reason),
    );
  }

  test('bridge replay allowance relaxes only its own sending flag', () {
    expect(
      GameInputPolicy.developmentBlockedReason(
        const GameInputState(sending: true),
        allowSending: true,
      ),
      isNull,
    );
    for (final state in [
      const GameInputState(sending: true, navigating: true),
      const GameInputState(sending: true, openingJournalSection: true),
      const GameInputState(sending: true, controllerBusy: true),
    ]) {
      expect(
        GameInputPolicy.developmentBlockedReason(state, allowSending: true),
        'ui_busy',
      );
    }
    expect(
      GameInputPolicy.developmentBlockedReason(
        const GameInputState(sending: true, hasDraft: true),
        allowSending: true,
      ),
      'unconfirmed_draft',
    );
  });

  test(
    'rendered control guard preserves its own narrower revision boundary',
    () {
      for (final state in [
        const GameInputState(),
        const GameInputState(hasDraft: true),
        const GameInputState(inspecting: true),
        const GameInputState(sending: true),
        const GameInputState(openingJournalSection: true),
        const GameInputState(editableFocused: true),
      ]) {
        expect(GameInputPolicy.canSendRenderedAction(state), isTrue);
      }
      for (final state in [
        const GameInputState(helpOpen: true),
        const GameInputState(navigating: true),
        const GameInputState(controllerBusy: true),
        const GameInputState(renderedRevisionCurrent: false),
      ]) {
        expect(GameInputPolicy.canSendRenderedAction(state), isFalse);
      }
    },
  );
}
