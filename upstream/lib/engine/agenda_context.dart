import 'package:flutter/foundation.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/politics/alignment.dart';

@immutable
class AgendaOffice {
  const AgendaOffice({
    required this.role,
    required this.name,
    required this.alignment,
  });
  final String role, name;
  final DeepAlignment alignment;
}

@immutable
class AgendaChamber {
  AgendaChamber({required this.name, required List<int> counts})
    : counts = List.unmodifiable(counts);
  final String name;

  /// Exact source summarizePoliticalBody order: arch-conservative to elite.
  final List<int> counts;
}

@immutable
class AgendaLaw {
  const AgendaLaw({
    required this.id,
    required this.name,
    required this.alignment,
    required this.description,
  });
  final String id, name, description;
  final DeepAlignment alignment;
}

@immutable
class AgendaPoll {
  const AgendaPoll({
    required this.issue,
    required this.statement,
    required this.percent,
    required this.percentLabel,
    required this.interest,
    required this.interestLabel,
  });
  final String issue, statement, percentLabel, interestLabel;
  final double percent;
  final int interest;
}

@immutable
class AgendaOverviewFrame {
  AgendaOverviewFrame({
    this.endingTitle,
    required this.page,
    required this.pageCount,
    required this.pageTitle,
    required List<AgendaOffice> offices,
    required List<AgendaOffice> court,
    required List<AgendaChamber> chambers,
    required List<AgendaLaw> laws,
    required List<AgendaPoll> polls,
    required List<String> notes,
    required List<ConsoleAction> controls,
  }) : offices = List.unmodifiable(offices),
       court = List.unmodifiable(court),
       chambers = List.unmodifiable(chambers),
       laws = List.unmodifiable(laws),
       polls = List.unmodifiable(polls),
       notes = List.unmodifiable(notes),
       controls = List.unmodifiable(controls);
  final int page, pageCount;
  final String? endingTitle;
  final String pageTitle;
  final List<AgendaOffice> offices, court;
  final List<AgendaChamber> chambers;
  final List<AgendaLaw> laws;
  final List<AgendaPoll> polls;
  final List<String> notes;
  final List<ConsoleAction> controls;
}

/// Local presentation collection populated alongside the original printer.
/// It is not a game model, save field or a second political rules engine.
class AgendaCapture {
  AgendaCapture({
    this.endingTitle,
    required this.page,
    required this.pageCount,
    required this.pageTitle,
  });
  final int page, pageCount;
  final String? endingTitle;
  final String pageTitle;
  final offices = <AgendaOffice>[];
  final court = <AgendaOffice>[];
  final chambers = <AgendaChamber>[];
  final laws = <AgendaLaw>[];
  final polls = <AgendaPoll>[];
  final notes = <String>[];

  AgendaOverviewFrame frame(Iterable<ConsoleAction> controls) =>
      AgendaOverviewFrame(
        endingTitle: endingTitle,
        page: page,
        pageCount: pageCount,
        pageTitle: pageTitle,
        offices: offices,
        court: court,
        chambers: chambers,
        laws: laws,
        polls: polls,
        notes: notes,
        controls: controls.toList(),
      );
}

final _agendaFrames = Expando<AgendaOverviewFrame>();

void describeAgendaOverview(Console console, AgendaOverviewFrame frame) =>
    _agendaFrames[console] = frame;

/// Consumed awaits and disband prompts never inherit a stale chapter. Forced
/// endings carry their own frame without granting ordinary chapter navigation.
AgendaOverviewFrame? agendaOverviewFrame(Console console) {
  final frame = _agendaFrames[console];
  return console.awaitingInput &&
          !console.textInput &&
          ((console.screen == 'agenda-records' &&
                  console.navigation?.section == 'agenda') ||
              (console.screen == 'agenda-ending' &&
                  console.navigation == null)) &&
          frame != null &&
          frame.controls.every(console.actions.contains)
      ? frame
      : null;
}
