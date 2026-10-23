import 'package:lcs_new_age/modern/journal_sections.dart';

enum _JournalTransition { idle, openingSection, awaitingHeadquarters }

/// Presentation state only. The shell reports reader/controller transitions
/// and keeps command dispatch, source validation and keyboard focus itself.
class JournalNavigationState {
  JournalNavigationState({required String screen, required bool hasCrew})
    : _lastScreen = screen,
      _active = screen == 'headquarters' && hasCrew;

  JournalSection section = JournalSection.organisation;
  String _lastScreen;
  bool _active;
  bool _wasBusy = false;
  _JournalTransition _transition = _JournalTransition.idle;

  bool get active => _active;
  bool get openingSection => _transition == _JournalTransition.openingSection;

  bool beginSection(JournalSection target) {
    if (openingSection) return false;
    _transition = _JournalTransition.openingSection;
    section = target;
    return true;
  }

  void finishSection() => _transition = _JournalTransition.idle;

  void observeReader({
    required String screen,
    required bool hasCrew,
    required bool controllerBusy,
  }) {
    if (screen == 'headquarters' && hasCrew) {
      _active = true;
      if (_lastScreen != 'headquarters' && !openingSection) {
        _transition = _JournalTransition.awaitingHeadquarters;
      }
      _settleReturn(atHeadquarters: true, controllerBusy: controllerBusy);
    }
    _lastScreen = screen;
    if (screen == 'title') _active = false;
  }

  /// A completed command also signals the shell to restore appropriate focus.
  bool observeController({required bool atHeadquarters, required bool busy}) {
    final finishedCommand = _wasBusy && !busy;
    _wasBusy = busy;
    _settleReturn(atHeadquarters: atHeadquarters, controllerBusy: busy);
    return finishedCommand;
  }

  void _settleReturn({
    required bool atHeadquarters,
    required bool controllerBusy,
  }) {
    if (_transition != _JournalTransition.awaitingHeadquarters ||
        !atHeadquarters ||
        controllerBusy) {
      return;
    }
    // Source-owned chapters end at HQ; native HQ chapters retain selection.
    // Keep the return pending through daily work and required report readers:
    // a controller's final busy notification can be the only later signal.
    if (section.returnsToOrganisation) section = JournalSection.organisation;
    _transition = _JournalTransition.idle;
  }
}
