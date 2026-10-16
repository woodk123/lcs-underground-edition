import 'package:flutter/foundation.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/journal_context.dart';

/// A snapshot of one original pursuit reader. The source supplies the
/// visible crew, encounter text and available controls; this owns no game rules.
@immutable
class PursuitContext {
  PursuitContext({
    this.title = 'On-foot pursuit',
    required this.location,
    required this.note,
    Iterable<String> statusLines = const [],
    required Iterable<JournalPersonSummary> people,
    required Iterable<String> encounterLines,
    required Iterable<ConsoleAction> actions,
  }) : statusLines = List.unmodifiable(statusLines),
       people = List.unmodifiable(people),
       encounterLines = List.unmodifiable(encounterLines),
       actions = List.unmodifiable(actions);

  final String title, location, note;
  final List<String> statusLines;
  final List<JournalPersonSummary> people;
  final List<String> encounterLines;
  final List<ConsoleAction> actions;
}

PursuitContext? pursuitContext(Console console) {
  final frame = console.pursuit;
  return console.awaitingInput &&
          !console.textInput &&
          console.eventMessage == null &&
          console.journalProfile == null &&
          console.screen == 'pursuit' &&
          frame != null &&
          frame.actions.length == console.actions.length &&
          frame.actions.every(console.actions.contains)
      ? frame
      : null;
}

/// A retained callback must never send its key to a later original reader.
bool pursuitActionIsCurrent(
  Console console,
  PursuitContext frame,
  ConsoleAction action,
  int revision,
) =>
    action.enabled &&
    console.revision.value == revision &&
    identical(pursuitContext(console), frame) &&
    frame.actions.contains(action) &&
    console.actions.contains(action) &&
    console.lastKey == null;
