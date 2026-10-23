import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:lcs_new_age/modern/journal_navigation_shortcuts.dart';
import 'package:lcs_new_age/modern/journal_sections.dart';

/// Read-only facts gathered by the shell at an input boundary. Focus queries,
/// traversal state, source-reader validation and all effects stay in the shell.
@immutable
class GameInputState {
  const GameInputState({
    this.mounted = true,
    this.classic = false,
    this.overlayOpen = false,
    this.changelogOpen = false,
    this.inspecting = false,
    this.sourceTextInput = false,
    this.helpOpen = false,
    this.sending = false,
    this.navigating = false,
    this.controllerBusy = false,
    this.openingJournalSection = false,
    this.hasDraft = false,
    this.entryFocused = false,
    this.editableFocused = false,
    this.keyboardTraversal = false,
    this.gameHasPrimaryFocus = true,
    this.journalAvailable = false,
    this.renderedRevisionCurrent = true,
  });

  final bool mounted, classic, overlayOpen, changelogOpen, inspecting;
  final bool sourceTextInput, helpOpen, sending, navigating, controllerBusy;
  final bool openingJournalSection, hasDraft, entryFocused, editableFocused;
  final bool keyboardTraversal, gameHasPrimaryFocus, journalAvailable;
  final bool renderedRevisionCurrent;

  bool get _keyboardBusy => helpOpen || sending || navigating || controllerBusy;
}

enum GameKeyRoute {
  ignore,
  closeInspection,
  submitEditedText,
  openHelp,
  journalSection,
  journalCommand,
  readerHandlers,
}

/// A presentation decision, never an engine command or an action capability.
@immutable
class GameKeyDecision {
  const GameKeyDecision(this.route, {this.section, this.command});
  final GameKeyRoute route;
  final JournalSection? section;
  final JournalGlobalCommand? command;
}

/// Channel-specific priority rules. Physical keys retain their source timing;
/// bridge requests additionally respect drafts, inspections and opening routes.
abstract final class GameInputPolicy {
  static GameKeyDecision keyboard(
    GameInputState state,
    KeyEvent event, {
    bool alt = false,
    bool control = false,
    bool meta = false,
    bool shift = false,
  }) {
    final key = event.logicalKey;
    final down = event is KeyDownEvent;
    if (state.overlayOpen) return const GameKeyDecision(GameKeyRoute.ignore);
    if (!state.classic && state.inspecting && !state.sourceTextInput) {
      return GameKeyDecision(
        down && key == LogicalKeyboardKey.escape
            ? GameKeyRoute.closeInspection
            : GameKeyRoute.ignore,
      );
    }
    if (state.sourceTextInput && down && key == LogicalKeyboardKey.escape) {
      return const GameKeyDecision(GameKeyRoute.submitEditedText);
    }
    if (down && key == LogicalKeyboardKey.f1 && !state._keyboardBusy) {
      return const GameKeyDecision(GameKeyRoute.openHelp);
    }
    if (state.entryFocused ||
        state.editableFocused ||
        state._keyboardBusy ||
        !down && event is! KeyRepeatEvent) {
      return const GameKeyDecision(GameKeyRoute.ignore);
    }
    if (!state.classic &&
        state.journalAvailable &&
        alt &&
        !control &&
        !meta &&
        !shift) {
      final section = JournalSection.forShortcut(key);
      if (section != null) {
        return GameKeyDecision(GameKeyRoute.journalSection, section: section);
      }
      final command = switch (key) {
        LogicalKeyboardKey.keyX => JournalGlobalCommand.saveAndExit,
        LogicalKeyboardKey.keyW => JournalGlobalCommand.advanceDay,
        _ => null,
      };
      if (command != null) {
        return GameKeyDecision(GameKeyRoute.journalCommand, command: command);
      }
    }
    if (state.keyboardTraversal &&
        !state.gameHasPrimaryFocus &&
        (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space)) {
      return const GameKeyDecision(GameKeyRoute.ignore);
    }
    if (const [
          LogicalKeyboardKey.tab,
          LogicalKeyboardKey.altLeft,
          LogicalKeyboardKey.altRight,
          LogicalKeyboardKey.altGraph,
          LogicalKeyboardKey.shiftLeft,
          LogicalKeyboardKey.shiftRight,
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.controlRight,
          LogicalKeyboardKey.metaLeft,
          LogicalKeyboardKey.metaRight,
        ].contains(key) ||
        control ||
        meta ||
        alt) {
      return const GameKeyDecision(GameKeyRoute.ignore);
    }
    return const GameKeyDecision(GameKeyRoute.readerHandlers);
  }

  static bool canSendRenderedAction(GameInputState state) =>
      !state.helpOpen &&
      !state.navigating &&
      !state.controllerBusy &&
      state.renderedRevisionCurrent;

  static String? developmentBlockedReason(
    GameInputState state, {
    bool allowSending = false,
  }) {
    if (!state.mounted) return 'shell_unavailable';
    if (state.changelogOpen) return 'changelog_open';
    if (state.helpOpen || state.overlayOpen) return 'modal_open';
    if (state.inspecting) return 'inspection_open';
    if (state.sending && !allowSending ||
        state.navigating ||
        state.openingJournalSection ||
        state.controllerBusy) {
      return 'ui_busy';
    }
    if (state.hasDraft) return 'unconfirmed_draft';
    if (!state.sourceTextInput && state.editableFocused) {
      return 'text_editor_focused';
    }
    return null;
  }
}
