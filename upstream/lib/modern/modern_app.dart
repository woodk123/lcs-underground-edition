import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/devtools/development_bridge.dart';
import 'package:lcs_new_age/engine/agenda_context.dart';
import 'package:lcs_new_age/engine/changelog.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/console_widget.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/engine/ledger_context.dart';
import 'package:lcs_new_age/engine/media_context.dart';
import 'package:lcs_new_age/engine/organisation_context.dart';
import 'package:lcs_new_age/engine/pursuit_context.dart';
import 'package:lcs_new_age/engine/recovery_context.dart';
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/gamestate/time.dart';
import 'package:lcs_new_age/modern/article_view.dart';
import 'package:lcs_new_age/modern/base_management_controller.dart';
import 'package:lcs_new_age/modern/city_planning_view.dart';
import 'package:lcs_new_age/modern/crew_dossier.dart';
import 'package:lcs_new_age/modern/crew_portrait.dart';
import 'package:lcs_new_age/modern/decision_help.dart';
import 'package:lcs_new_age/modern/direct_content.dart';
import 'package:lcs_new_age/modern/full_site_map.dart';
import 'package:lcs_new_age/modern/game_input_policy.dart';
import 'package:lcs_new_age/modern/headquarters_view.dart';
import 'package:lcs_new_age/modern/journal_agenda.dart';
import 'package:lcs_new_age/modern/journal_creation.dart';
import 'package:lcs_new_age/modern/journal_field_operation_view.dart';
import 'package:lcs_new_age/modern/journal_ledger.dart';
import 'package:lcs_new_age/modern/journal_legislation.dart';
import 'package:lcs_new_age/modern/journal_media.dart';
import 'package:lcs_new_age/modern/journal_media_production.dart';
import 'package:lcs_new_age/modern/journal_navigation_shortcuts.dart';
import 'package:lcs_new_age/modern/journal_navigation_state.dart';
import 'package:lcs_new_age/modern/journal_preferences.dart';
import 'package:lcs_new_age/modern/journal_profile_view.dart';
import 'package:lcs_new_age/modern/journal_pursuit.dart';
import 'package:lcs_new_age/modern/journal_recovery.dart';
import 'package:lcs_new_age/modern/journal_sections.dart';
import 'package:lcs_new_age/modern/journal_shortcuts.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/journal_title.dart';
import 'package:lcs_new_age/modern/journal_workspace_view.dart';
import 'package:lcs_new_age/modern/juice_indicator.dart';
import 'package:lcs_new_age/modern/modern_shell_chrome.dart';
import 'package:lcs_new_age/modern/organisation_controller.dart';
import 'package:lcs_new_age/modern/organisation_journal.dart';
import 'package:lcs_new_age/modern/tactical_map.dart';
import 'package:lcs_new_age/utils/game_options.dart';
import 'package:lcs_new_age/utils/game_version.dart';

const ink = JournalPalette.ink;
const paper = JournalPalette.page;
const muted = JournalPalette.muted;
const vermilion = JournalPalette.binding;
const teal = JournalPalette.olive;
const line = JournalPalette.rule;

ThemeData buildModernTheme() => buildJournalTheme();

class ModernGameShell extends StatefulWidget {
  const ModernGameShell({super.key});
  @override
  State<ModernGameShell> createState() => _ModernGameShellState();
}

class _ModernGameShellState extends State<ModernGameShell> {
  final _keyboard = FocusNode(debugLabel: 'Game keyboard');
  final _entry = TextEditingController();
  final _entryFocus = FocusNode(debugLabel: 'Text prompt');
  final _operationScroll = ScrollController();
  bool _classic = false, _guide = true, _helpOpen = false, _sending = false;
  bool _navigating = false;
  (int, String?)? _navigationTarget;
  int? _inspectedPersonId;
  double get _textScale => journalReadingScale.value;
  set _textScale(double value) {
    journalReadingScale.value = value;
    gameOptions.journalScale = value;
    unawaited(gameOptions.saveJournalScale());
  }

  int _tab = 0;
  int _renderedRevision = -1;
  bool _wasTextInput = false;
  late final OrganisationController _organisation;
  late final JournalNavigationState _journalNavigation;
  bool _mediaProduction = false;
  bool _keyboardTraversal = false;
  final _journalKey = GlobalKey<OrganisationJournalState>();
  final _ledgerKey = GlobalKey<JournalLedgerOverviewState>();
  Console get console => engine.console;
  bool get hq => console.screen == 'headquarters';
  bool get title => console.screen == 'title';
  bool get tactical => console.screen == 'tactical';
  bool get fieldPrompt => console.screen == 'field_prompt';
  Creature? get _inspectedPerson =>
      game.pool.where((person) => person.id == _inspectedPersonId).firstOrNull;
  bool get _canSwitchSections =>
      !_helpOpen &&
      console.eventMessage == null &&
      !console.textInput &&
      game.mode == GameMode.base &&
      !title &&
      (hq || console.navigation != null);

  @override
  void initState() {
    super.initState();
    _journalNavigation = JournalNavigationState(
      screen: console.screen,
      hasCrew: game.pool.isNotEmpty,
    );
    _organisation = OrganisationController(console: console);
    _organisation.addListener(_organisationChanged);
    console.revision.addListener(_refresh);
    // A source await may already exist before this shell mounts (for example
    // after restoring a session). Initialise its editor and focus as well.
    _refresh();
    if (developmentToolsEnabled) {
      developmentBridge.attachUi(
        this,
        blockedReason: _developmentBlockedReason,
        inputText: _developmentInputText,
        prepareSourceInput: () {
          _journalKey.currentState?.prepareForSourceInput();
          if (!_classic &&
              _journalNavigation.section != JournalSection.organisation) {
            setState(
              () => _journalNavigation.section = JournalSection.organisation,
            );
          }
        },
      );
    }
  }

  GameInputState _inputState() {
    if (!mounted) {
      return const GameInputState(
        mounted: false,
        renderedRevisionCurrent: false,
      );
    }
    final focused = FocusManager.instance.primaryFocus?.context;
    return GameInputState(
      classic: _classic,
      overlayOpen: ModalRoute.of(context)?.isCurrent == false,
      changelogOpen: ChangelogWidget.globalKey.currentState?.showing ?? false,
      inspecting: _inspectedPersonId != null,
      sourceTextInput: console.textInput,
      helpOpen: _helpOpen,
      sending: _sending,
      navigating: _navigating,
      controllerBusy: _organisation.busy,
      openingJournalSection: _journalNavigation.openingSection,
      hasDraft: _journalKey.currentState?.hasUnconfirmedDraft ?? false,
      entryFocused: _entryFocus.hasFocus,
      editableFocused:
          focused?.widget is EditableText ||
          focused?.findAncestorStateOfType<EditableTextState>() != null,
      keyboardTraversal: _keyboardTraversal,
      gameHasPrimaryFocus: _keyboard.hasPrimaryFocus,
      journalAvailable: _journalKey.currentState != null,
      renderedRevisionCurrent: _renderedRevision == console.revision.value,
    );
  }

  String? _developmentBlockedReason({bool allowSending = false}) =>
      GameInputPolicy.developmentBlockedReason(
        _inputState(),
        allowSending: allowSending,
      );

  Future<bool> _developmentInputText(String value, String submit) async {
    if (_developmentBlockedReason() != null || !console.textInput) return false;
    final inputConsole = console;
    var expected = inputConsole.textInputValue;
    setState(() {
      _sending = true;
      _entry.text = value;
      _entry.selection = TextSelection.collapsed(offset: value.length);
    });
    Future<bool> character(String key, String next) async {
      if (_developmentBlockedReason(allowSending: true) != null ||
          !identical(console, inputConsole) ||
          !inputConsole.textInput ||
          inputConsole.textInputValue != expected ||
          !inputConsole.sendInput(key)) {
        return false;
      }
      for (var attempt = 0; attempt < 100; attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        if (!mounted ||
            !identical(console, inputConsole) ||
            !inputConsole.textInput ||
            _developmentBlockedReason(allowSending: true) != null) {
          return false;
        }
        if (inputConsole.awaitingInput && inputConsole.lastKey == null) {
          if (inputConsole.textInputValue != next) return false;
          expected = next;
          return true;
        }
      }
      return false;
    }

    try {
      while (expected.isNotEmpty) {
        if (!await character(
          'Backspace',
          expected.characters.skipLast(1).toString(),
        )) {
          return false;
        }
      }
      for (final char in value.characters) {
        if (!await character(char, expected + char)) return false;
      }
      if (_developmentBlockedReason(allowSending: true) != null ||
          !identical(console, inputConsole) ||
          !inputConsole.textInput ||
          inputConsole.textInputValue != expected) {
        return false;
      }
      // A source command has the same presentation reset as physical input.
      _journalKey.currentState?.prepareForSourceInput();
      final accepted = inputConsole.sendInput(submit);
      await Future<void>.delayed(Duration.zero);
      return accepted;
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _keyboard.requestFocus();
      }
    }
  }

  void _organisationChanged() {
    if (!mounted) return;
    final finishedCommand = _journalNavigation.observeController(
      atHeadquarters: hq,
      busy: _organisation.busy,
    );
    setState(() {});
    if (finishedCommand &&
        !_helpOpen &&
        (ModalRoute.of(context)?.isCurrent ?? true)) {
      if (console.textInput) {
        _restoreTextEntryFocus();
      } else {
        _keyboard.requestFocus();
      }
    }
  }

  void _refresh() {
    if (!mounted) return;
    if (fieldPrompt) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && fieldPrompt && _operationScroll.hasClients) {
          _operationScroll.jumpTo(0);
        }
      });
    }
    _journalNavigation.observeReader(
      screen: console.screen,
      hasCrew: game.pool.isNotEmpty,
      controllerBusy: _organisation.busy,
    );
    if (console.textInput && !_wasTextInput) {
      _entry.text = console.textInputValue;
      _entry.selection = TextSelection.collapsed(offset: _entry.text.length);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && console.textInput && !_helpOpen) {
          _entryFocus.requestFocus();
        }
      });
    }
    _wasTextInput = console.textInput;
    if (title || game.mode != GameMode.base || _inspectedPerson == null) {
      _inspectedPersonId = null;
    }
    setState(() {});
  }

  @override
  void dispose() {
    if (developmentToolsEnabled) developmentBridge.detachUi(this);
    console.revision.removeListener(_refresh);
    _organisation.removeListener(_organisationChanged);
    _organisation.dispose();
    _keyboard.dispose();
    _entry.dispose();
    _entryFocus.dispose();
    _operationScroll.dispose();
    super.dispose();
  }

  void _send(String key) {
    if (GameInputPolicy.canSendRenderedAction(_inputState())) {
      final wasTextInput = console.textInput;
      final accepted = console.sendInput(key);
      if (accepted && _inspectedPersonId != null && !wasTextInput) {
        setState(() => _inspectedPersonId = null);
      }
      _keyboard.requestFocus();
    }
  }

  ConsoleAction? _action(String key) {
    for (final a in console.actions) {
      if (a.key.toLowerCase() == key.toLowerCase()) return a;
    }
    return null;
  }

  void _choose(String key) {
    final a = _action(key);
    if (a?.enabled == true) _send(a!.key);
  }

  Future<void> _navigateTo(int index, String? key) async {
    if (!_canSwitchSections) return;
    if (!hq && index == _currentSection()) return;
    _navigationTarget = (index, key);
    if (_navigating) return;
    setState(() {
      _navigating = true;
      _inspectedPersonId = null;
    });
    try {
      for (var step = 0; step < 20 && mounted; step++) {
        if (!console.awaitingInput) {
          await Future<void>.delayed(const Duration(milliseconds: 16));
          continue;
        }
        if (hq) {
          final target = _navigationTarget!;
          if (target.$2 != null) {
            final action = _action(target.$2!);
            if (action?.enabled != true) break;
            console.sendInput(action!.key);
          }
          if (mounted) setState(() => _tab = target.$1);
          break;
        }
        final navigation = console.navigation;
        if (navigation == null ||
            console.textInput ||
            game.mode != GameMode.base) {
          break;
        }
        final revision = console.revision.value;
        if (!console.sendInput(navigation.backKey)) break;
        // The next original await must explicitly declare its own safe exit.
        for (var wait = 0; wait < 120 && mounted; wait++) {
          await Future<void>.delayed(const Duration(milliseconds: 8));
          if (console.revision.value != revision && console.awaitingInput) {
            break;
          }
        }
      }
    } finally {
      _navigationTarget = null;
      if (mounted) setState(() => _navigating = false);
      if (mounted) _keyboard.requestFocus();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.tab) {
      _keyboardTraversal = true;
    }
    final decision = GameInputPolicy.keyboard(
      _inputState(),
      event,
      alt: HardwareKeyboard.instance.isAltPressed,
      control: HardwareKeyboard.instance.isControlPressed,
      meta: HardwareKeyboard.instance.isMetaPressed,
      shift: HardwareKeyboard.instance.isShiftPressed,
    );
    switch (decision.route) {
      case GameKeyRoute.ignore:
        return KeyEventResult.ignored;
      case GameKeyRoute.closeInspection:
        setState(() => _inspectedPersonId = null);
        return KeyEventResult.handled;
      case GameKeyRoute.submitEditedText:
        // The editor's existing replay guard handles an already-running submit.
        unawaited(_submitText(terminalKey: 'Escape'));
        return KeyEventResult.handled;
      case GameKeyRoute.openHelp:
        unawaited(_help());
        return KeyEventResult.handled;
      case GameKeyRoute.journalSection:
        if (_canSwitchSections && _organisation.canNavigate) {
          unawaited(_openJournalSectionFromShortcut(decision.section!.id));
        }
        return KeyEventResult.handled;
      case GameKeyRoute.journalCommand:
        _journalKey.currentState!.handleGlobalCommand(decision.command!);
        return KeyEventResult.handled;
      case GameKeyRoute.readerHandlers:
        break;
    }
    _keyboardTraversal = false;
    final journalKey = keyEventToString(event);
    if (journalKey.isEmpty) return KeyEventResult.ignored;
    if (!_classic &&
        _ledgerKey.currentState?.handleGameShortcut(event) == true) {
      return KeyEventResult.handled;
    }
    if (_journalKey.currentState?.handleGameShortcut(journalKey) == true) {
      return KeyEventResult.handled;
    }
    // The visible form owns edits. Tabbing to another control must not type
    // into the hidden source mvgetstr reader behind that form.
    if (console.textInput) return KeyEventResult.ignored;
    if (!_classic) {
      _journalKey.currentState?.prepareForSourceInput();
      if (_journalNavigation.section != JournalSection.organisation) {
        setState(
          () => _journalNavigation.section = JournalSection.organisation,
        );
      }
    }
    if (!_keyboard.hasPrimaryFocus) _keyboard.requestFocus();
    console.keyEvent(event);
    return KeyEventResult.handled;
  }

  Future<void> _submitText({String terminalKey = 'Enter'}) async {
    if (_sending || !console.textInput) return;
    final value = _entry.text;
    setState(() {
      _sending = true;
    });
    final oldValue = console.textInputValue;
    for (var i = 0; i < oldValue.characters.length; i++) {
      if (!await _textKey('Backspace')) break;
    }
    for (final char in value.characters) {
      if (!await _textKey(char)) break;
    }
    await _textKey(terminalKey);
    if (mounted) {
      setState(() {
        _sending = false;
        _entry.clear();
      });
      _keyboard.requestFocus();
    }
  }

  void _restoreTextEntryFocus() {
    if (!console.textInput) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && console.textInput && !_helpOpen) {
        _entryFocus.requestFocus();
      }
    });
  }

  Future<bool> _textKey(String key) async {
    for (var attempt = 0; attempt < 100; attempt++) {
      if (!mounted || !console.textInput) return false;
      if (console.sendInput(key)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return false;
  }

  Future<void> _help() async {
    setState(() {
      _helpOpen = true;
    });
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('A small movement. A long game.'),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Change the country by shifting public opinion, influencing elections and advancing the Liberal Agenda. Every recruit, skill, law and consequence from New Age remains in play.',
                ),
                const SizedBox(height: 20),
                _helpStep(
                  '01',
                  'Build your foundation',
                  'Choose a squad from the portrait tabs, then click a crew member on the left page. Open Orders, choose an activity group and an illustrated task. The job card shows its timing, cost, risks and relevant skills. Confirm assigns it; Cancel leaves the previous assignment intact.',
                ),
                _helpStep(
                  '02',
                  'Plan before you act',
                  'Open Crew pool to add or remove people with the arrows, or drag them between pages. A squad holds up to six. Click a skill heading to compare real ratings. City Maps lets you inspect known places; Prepare a visit opens the original destination choices. Confirm queues a visit until you advance the day.',
                ),
                _helpStep(
                  '03',
                  'See the consequences',
                  'The bottom-right day control carries out personal assignments and queued visits. Its label changes when a siege or attack needs attention. Undercover agents act monthly. Use the Newspaper and Agenda tabs to follow public opinion, laws and government. The Current orders report explains the assignments for the selected crew.',
                ),
                const Divider(),
                const Text(
                  'Decision guides',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Text(
                  'Read current values, rules and comparisons without changing the campaign.',
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final topic in DecisionTopic.values)
                      DecisionGuideButton(
                        topic: topic,
                        actor:
                            _inspectedPerson ??
                            game.activeSquadMember ??
                            game.squad.firstOrNull,
                      ),
                  ],
                ),
                const Divider(),
                const Text(
                  'Controls',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  '$journalNavigationHelp\n\nKeyboard works in graphical view. At headquarters: 1–6 selects a squad member, pressing that number again opens their profile, and 0 clears the selection. F opens squad visits, N selects the next squad, A opens assignments, and W carries out plans or waits a day. In the visit planner, letter keys open districts and queue buildings immediately; Back returns one original level and cancels a queued departure at the city root. You can also browse the city map and choose Queue visit in one action. Visits replace earlier daily assignments; travel runs when you advance the day. Game keys follow the original menus in every view: category defaults and task or destination selections take effect on the same key as Classic, and Back returns one original menu level. Pointer task cards can still be prepared and confirmed with their visible controls. Tab moves between controls; Enter or Space activates the focused control. Enter continues messages and arrows move during operations. Required names use the text field. F1 opens this guide. Classic view retains the original menu shortcuts.',
                ),
                const SizedBox(height: 14),
                const Text(
                  'Saving',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const Text(
                  'Use Save & Exit at headquarters, then Continue or Load & Manage Saves. The original autosave and export systems are preserved. Browser saves belong to this browser and address. Export important campaigns from save management.',
                ),
                const SizedBox(height: 14),
                const Text(
                  'New Age is political satire with mature themes. Content and tone options are available from the title screen.',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Back to the game'),
          ),
        ],
      ),
    );
    if (mounted) {
      setState(() {
        _helpOpen = false;
      });
      if (console.textInput) {
        _restoreTextEntryFocus();
      } else {
        _keyboard.requestFocus();
      }
    }
  }

  Future<void> _openDossier(Creature person) async {
    if (!_helpOpen && !_navigating) {
      setState(() => _inspectedPersonId = person.id);
    }
  }

  Widget _withCrewInspector(Widget workspace) {
    final person = _inspectedPerson;
    if (person == null || title || _classic) return workspace;
    final index = game.squad.indexOf(person);
    final inspector = CrewInspector(
      person: person,
      onClose: () => setState(() => _inspectedPersonId = null),
      compact: true,
      actions: [
        if (hq && index >= 0 && game.activeSquadMember != person)
          CrewDossierAction(
            label: 'Select in squad',
            icon: Icons.person_pin_outlined,
            onPressed: () {
              if (hq &&
                  index < game.squad.length &&
                  identical(game.squad[index], person)) {
                _send('${index + 1}');
                setState(() => _inspectedPersonId = null);
              }
            },
          ),
      ],
    );
    return LayoutBuilder(
      builder: (context, bounds) {
        if (bounds.maxWidth >= 720) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: workspace),
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
                child: SizedBox(
                  width: bounds.maxWidth >= 1050 ? 310 : 280,
                  child: inspector,
                ),
              ),
            ],
          );
        }
        return Column(
          children: [
            Expanded(child: workspace),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: SizedBox(height: bounds.maxHeight * .42, child: inspector),
            ),
          ],
        );
      },
    );
  }

  Widget _helpStep(String n, String title, String body) => Padding(
    padding: const EdgeInsets.only(bottom: 18),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          n,
          style: const TextStyle(
            color: vermilion,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(body),
            ],
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    _renderedRevision = console.revision.value;
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 1100;
    final classic = _classic || console.mouseEventMode;
    final creation = console.creation;
    final journal =
        _journalNavigation.active &&
        !title &&
        !classic &&
        game.mode == GameMode.base;
    return NotificationListener<JournalPreferencesClosedNotification>(
      onNotification: (_) {
        _restoreTextEntryFocus();
        return true;
      },
      child: FocusTraversalGroup(
        policy: ReadingOrderTraversalPolicy(),
        child: Listener(
          onPointerDown: (_) {
            _keyboardTraversal = false;
            _journalKey.currentState?.pointerInputStarted();
          },
          child: Focus(
            focusNode: _keyboard,
            autofocus: true,
            onKeyEvent: _onKey,
            child: MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(_textScale)),
              child: console.eventMessage != null && !classic
                  ? journal
                        ? Theme(
                            data: buildJournalTheme(),
                            child: _journalDesktop(),
                          )
                        : _journalFallback(compact)
                  : creation != null && !classic
                  ? JournalCreationPage(
                      console: console,
                      context: creation,
                      onAction: _send,
                      inputBar: _inputBar(creation: true),
                      onHelp: _help,
                      readingControl: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const JournalPreferencesButton(),
                          PopupMenuButton<double>(
                            tooltip: 'Reading size',
                            initialValue: _textScale,
                            onSelected: (value) =>
                                setState(() => _textScale = value),
                            icon: const Icon(
                              Icons.text_fields,
                              color: JournalPalette.brassDark,
                            ),
                            itemBuilder: (_) => [
                              for (final scale in [1.0, 1.25, 1.5])
                                PopupMenuItem(
                                  value: scale,
                                  child: Text('${(scale * 100).round()}%'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    )
                  : title && !classic
                  ? JournalTitlePage(
                      console: console,
                      onAction: _send,
                      onHelp: _help,
                    )
                  : journal
                  ? Theme(data: buildJournalTheme(), child: _journalDesktop())
                  : !classic
                  ? _journalFallback(compact)
                  : Column(
                      children: [
                        _topbar(),
                        if (!title && width < 900) _sectionStrip(),
                        Expanded(
                          child: Row(
                            children: [
                              if (!title && width >= 900) _sidebar(),
                              Expanded(
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: title && !_classic
                                          ? _titlePage(compact)
                                          : hq && !classic
                                          ? _withCrewInspector(
                                              _headquarters(compact),
                                            )
                                          : _withCrewInspector(
                                              _workspace(classic, compact),
                                            ),
                                    ),
                                    Positioned.fill(
                                      child: ExcludeFocus(
                                        excluding: !classic,
                                        child: Offstage(
                                          offstage: !classic,
                                          child: Padding(
                                            padding: EdgeInsets.fromLTRB(
                                              20,
                                              100,
                                              compact ? 20 : 340,
                                              compact ? 300 : 90,
                                            ),
                                            child: ConsoleWidget(
                                              console,
                                              key: ConsoleWidget.globalKey,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        _statusbar(),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _topbar() => ModernShellTopBar(
    date: title
        ? null
        : '${game.day} ${getMonth(game.month).substring(0, 3)} ${game.year}',
    funds: title ? null : '\$${game.ledger.funds}',
    textScale: _textScale,
    classic: _classic,
    onTextScale: (value) => setState(() => _textScale = value),
    onClassic: () => setState(() => _classic = !_classic),
    onHelp: _help,
  );

  List<ModernShellSection> _shellSections() => [
    for (final (index, icon, label, shortLabel, command)
        in <(int, IconData, String, String, String?)>[
          (0, Icons.grid_view_outlined, 'Headquarters', 'Headquarters', null),
          (1, Icons.people_outline, 'People & squads', 'People', 'r'),
          (
            2,
            Icons.fact_check_outlined,
            'Daily assignments',
            'Assignments',
            'a',
          ),
          (3, Icons.explore_outlined, 'Operations', 'Operations', 'f'),
          (4, Icons.account_balance_outlined, 'Liberal Agenda', 'Agenda', 'l'),
          (5, Icons.newspaper_outlined, 'Media & impact', 'Media', 'm'),
          (6, Icons.backpack_outlined, 'Equipment', 'Equipment', 'e'),
        ])
      ModernShellSection(
        id: index,
        icon: icon,
        label: label,
        shortLabel: shortLabel,
        selected: _currentSection() == index,
        onSelect:
            _canSwitchSections &&
                (!hq || command == null || _action(command)?.enabled == true)
            ? () => _navigateTo(index, command)
            : null,
      ),
  ];

  Widget _sectionStrip() => ModernShellSectionStrip(sections: _shellSections());

  Widget _sidebar() => ModernShellSidebar(
    sections: _shellSections(),
    note: _canSwitchSections
        ? 'Switch sections directly. Time advances when you end the day.'
        : tactical
        ? 'Finish or leave the site before returning to the movement.'
        : 'Complete this choice before switching sections.',
    onSaveExit: hq ? () => _choose('x') : null,
  );

  Widget _titlePage(bool compact) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: IntrinsicHeight(
          child: Row(
            children: [
              Expanded(
                flex: compact ? 1 : 5,
                child: Padding(
                  padding: EdgeInsets.all(compact ? 28 : 64),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _eyebrow('A POLITICAL STRATEGY GAME'),
                      const SizedBox(height: 26),
                      Text(
                        'Change\nthe story.',
                        style: TextStyle(
                          fontSize: compact ? 52 : 72,
                          fontWeight: FontWeight.w800,
                          height: 1.02,
                          letterSpacing: -3,
                          color: ink,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const SizedBox(
                        width: 420,
                        child: Text(
                          'Build a movement. Shape public opinion. Take on a country sliding toward authoritarianism.',
                          style: TextStyle(
                            fontSize: 19,
                            height: 1.6,
                            color: muted,
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),
                      if (_action('c')?.enabled == true) ...[
                        _titleChoice(
                          'c',
                          'Continue your campaign',
                          primary: true,
                        ),
                        const SizedBox(height: 10),
                      ],
                      _titleChoice(
                        'n',
                        'Start a new movement',
                        primary: _action('c')?.enabled != true,
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final a in console.actions.where(
                            (a) => !['c', 'n'].contains(a.key.toLowerCase()),
                          ))
                            TextButton(
                              onPressed: a.enabled ? () => _send(a.key) : null,
                              child: Text(_clean(a.label)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 30),
                      const Divider(),
                      const SizedBox(height: 14),
                      const Text(
                        'ONE FOUNDER. COUNTLESS POSSIBILITIES.',
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.bold,
                          color: muted,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'The complete New Age simulation, with a new perspective.\nRecruitment · covert operations · elections · consequences',
                        style: TextStyle(fontSize: 12, color: muted),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Original game by Tarn Adams · New Age by Ashley S. Fox\n'
                        'The Underground Edition by Kevin Wood\n'
                        'Open source · GPL-2.0\n'
                        '$gameVersionLabel',
                        style: TextStyle(fontSize: 11, color: muted),
                      ),
                    ],
                  ),
                ),
              ),
              if (!compact)
                Expanded(
                  flex: 6,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        'assets/modern/city_panorama.webp',
                        fit: BoxFit.cover,
                      ),
                      Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Color(0xDD142831)],
                          ),
                        ),
                      ),
                      const Positioned(
                        left: 42,
                        right: 36,
                        bottom: 50,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'THE CITY IS LISTENING.',
                              style: TextStyle(
                                color: Color(0xFFDED8C9),
                                letterSpacing: 2,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 12),
                            Text(
                              'What will you\ngive it to believe?',
                              style: TextStyle(
                                color: paper,
                                fontSize: 37,
                                height: 1.18,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  Widget _titleChoice(String key, String text, {bool primary = false}) =>
      SizedBox(
        width: 340,
        child: primary
            ? FilledButton(
                onPressed: () => _choose(key),
                style: FilledButton.styleFrom(backgroundColor: vermilion),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(text)),
                    const Icon(Icons.north_east, size: 18),
                  ],
                ),
              )
            : OutlinedButton(
                onPressed: () => _choose(key),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(text)),
                    const Icon(Icons.arrow_forward, size: 18),
                  ],
                ),
              ),
      );

  Widget _headquarters(bool compact) => HeadquartersView(
    console: console,
    onAction: _send,
    onInspect: _openDossier,
    showFirstSteps: _guide && JournalPreferences.of(context).showGuidance,
    onDismissFirstSteps: () => setState(() => _guide = false),
  );

  Future<void> _openJournalSection(int sectionId) async {
    final section = JournalSection.fromId(sectionId);
    if (section == null ||
        !_organisation.canNavigate ||
        !_journalNavigation.beginSection(section)) {
      return;
    }
    setState(() => _inspectedPersonId = null);
    try {
      switch (section.destination) {
        case JournalSectionDestination.headquarters:
          await _organisation.returnToHeadquarters();
        case JournalSectionDestination.personnelDirectory:
          await _organisation.openPersonnelDirectory();
        case JournalSectionDestination.sourceReader:
          if (await _organisation.openSection(section.sourceRoute.first)) {
            for (final key in section.sourceRoute.skip(1)) {
              final action = _action(key);
              if (action?.enabled != true) break;
              if (!await _organisation.sendAction(
                action!,
                revision: console.revision.value,
              )) {
                break;
              }
            }
          }
      }
    } finally {
      _journalNavigation.finishSection();
      if (mounted) {
        setState(() {});
        if (!console.textInput) _keyboard.requestFocus();
      }
    }
  }

  Future<void> _openJournalSectionFromShortcut(int section) async {
    await _openJournalSection(section);
    if (mounted && !console.textInput) {
      _journalKey.currentState?.revealSection(section);
      _keyboard.requestFocus();
    }
  }

  Future<void> _ledgerAction(String key) async {
    final frame = ledgerReportFrame(console);
    if (frame == null) return;
    if (frame.management && key == frame.closeAction.key) {
      if (await _organisation.sendAction(
        frame.closeAction,
        revision: console.revision.value,
      )) {
        if (mounted) {
          setState(
            () => _journalNavigation.section = JournalSection.organisation,
          );
        }
      }
    } else {
      _send(key);
    }
  }

  Future<void> _mediaAction(String key) async {
    // The original paged reader accepts Escape as Back even though its visible
    // authored control is Enter. Resolve that alias to the current Back action.
    final action =
        _action(key) ??
        (key == 'Escape' && console.navigation?.section == 'media'
            ? _action(console.navigation!.backKey) ?? _action('Enter')
            : null);
    if (action == null) return;
    if (action.key == 'Enter' || action.key == 'Escape') {
      if (await _organisation.sendAction(
            action,
            revision: console.revision.value,
          ) &&
          mounted &&
          hq) {
        setState(
          () => _journalNavigation.section = JournalSection.organisation,
        );
      }
    } else {
      _send(action.key);
    }
  }

  Widget _journalDesktop() {
    final primary =
        hq ||
        console.screen == 'organisation' ||
        squadAllocationFrame(console) != null ||
        console.screen == 'planning' ||
        activityOrderFrame(console) != null;
    Widget? detail;
    if (console.eventMessage != null) {
      detail = _eventMessageView(embeddedJournal: true);
    } else if (isLegislativeVoteScreen(console)) {
      detail = JournalLegislationView(console: console, onAction: _send);
    } else if (ledgerReportFrame(console) != null) {
      detail = JournalLedgerOverview(
        key: _ledgerKey,
        console: console,
        onAction: _ledgerAction,
        history: _organisation.monthlyLedgerHistory,
      );
    } else if (agendaOverviewFrame(console) != null) {
      detail = JournalAgendaView(console: console, onAction: _send);
    } else if (mediaOverviewFrame(console) != null) {
      detail = _mediaDesk();
    } else if (_journalNavigation.section == JournalSection.options &&
        !console.textInput) {
      detail = _journalOptions();
    } else if (_journalNavigation.section == JournalSection.network &&
        !console.textInput &&
        console.journalProfile == null &&
        (primary ||
            _organisation.busy ||
            console.navigation?.section == 'assignments')) {
      // The Network owns its roster and inspector while using the original
      // sleeper readers underneath. Required decisions retain their own view.
      detail = null;
    } else if (_journalNavigation.section == JournalSection.people &&
        !console.textInput &&
        console.journalProfile == null &&
        activityOrderFrame(console) == null &&
        squadAllocationFrame(console) == null &&
        (hq || console.screen == 'personnel-directory' || _organisation.busy)) {
      detail = null;
    } else if (_journalNavigation.section == JournalSection.bases &&
        !console.textInput &&
        console.journalProfile == null &&
        (hq ||
            BaseManagementController.ownsScreen(console) ||
            _organisation.busy)) {
      detail = null;
    } else if (!primary || console.screen == 'organisation') {
      detail = _workspace(false, true, embeddedJournal: true);
    } else if (_journalNavigation.section == JournalSection.justice &&
        console.screen == 'organisation' &&
        _action('4')?.enabled != true) {
      detail = const JournalSurface(
        lined: true,
        child: Center(
          child: Text('No crew are currently in the justice system.'),
        ),
      );
    }
    final inspected = _inspectedPerson;
    final index = inspected == null ? -1 : game.squad.indexOf(inspected);
    return OrganisationJournal(
      key: _journalKey,
      console: console,
      controller: _organisation,
      onAction: _send,
      onInspect: _openDossier,
      onHelp: _help,
      onClassic: () => setState(() => _classic = !_classic),
      onTextScale: (value) => setState(() => _textScale = value),
      textScale: _textScale,
      section:
          (hq && _organisation.headquarters?.siege != null
                  ? JournalSection.organisation
                  : isLegislativeVoteScreen(console)
                  ? JournalSection.agenda
                  : ledgerReportFrame(console) != null
                  ? JournalSection.ledger
                  : agendaOverviewFrame(console) != null
                  ? JournalSection.agenda
                  : mediaOverviewFrame(console) != null
                  ? JournalSection.newspaper
                  : _journalNavigation.section)
              .id,
      fullSpreadDetail:
          console.screen == 'organisation' ||
          console.eventMessage != null ||
          recoveryContext(console) != null ||
          console.screen == 'squad_choice' ||
          console.screen == 'kidnap_target' ||
          isLegislativeVoteScreen(console) ||
          ledgerReportFrame(console) != null ||
          agendaOverviewFrame(console) != null ||
          mediaOverviewFrame(console) != null ||
          console.screen == 'article' && console.article != null,
      onSection: _openJournalSection,
      detail: detail,
      peopleToolsBuilder: (_) => _workspace(false, true, embeddedJournal: true),
      inspectedPerson: inspected,
      onCloseInspection: () {
        if (_inspectedPersonId != null) {
          setState(() => _inspectedPersonId = null);
        }
      },
      inspectorActions: [
        if (hq &&
            inspected != null &&
            index >= 0 &&
            game.activeSquadMember != inspected)
          CrewDossierAction(
            label: 'Select in squad',
            icon: Icons.person_pin_outlined,
            onPressed: () {
              _send('${index + 1}');
              setState(() => _inspectedPersonId = null);
            },
          ),
      ],
    );
  }

  Widget _mediaDesk() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 5,
        children: [
          ChoiceChip(
            key: const ValueKey('media-archive-tab'),
            label: const Text('Archive'),
            selected: !_mediaProduction,
            onSelected: (_) => setState(() => _mediaProduction = false),
          ),
          ChoiceChip(
            key: const ValueKey('media-production-tab'),
            label: const Text('Production'),
            selected: _mediaProduction,
            onSelected: (_) => setState(() => _mediaProduction = true),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Expanded(
        child: _mediaProduction
            ? JournalMediaProductionView(
                enabled: _organisation.canNavigate,
                onOpenArchive: () => setState(() => _mediaProduction = false),
                onAssign: (request) async {
                  if (!_organisation.canNavigate) return;
                  setState(() {
                    _journalNavigation.section = JournalSection.organisation;
                    _inspectedPersonId = null;
                  });
                  // Leave the archive first: its source frame owns section 4
                  // until it closes. Stage only after section 0 has rendered,
                  // otherwise didUpdateWidget would discard the new draft.
                  if (!await _organisation.returnToHeadquarters()) return;
                  await WidgetsBinding.instance.endOfFrame;
                  if (!mounted) return;
                  await _journalKey.currentState?.preparePersonOrder(
                    request.person,
                    categoryId: 'activism',
                    activity: request.activity,
                  );
                },
                onOpenPeople: () =>
                    unawaited(_openJournalSection(peopleJournalSection)),
                onOpenBases: () =>
                    unawaited(_openJournalSection(basesJournalSection)),
                onOpenStores: () =>
                    unawaited(_openJournalSection(basesJournalSection)),
              )
            : JournalMediaOverview(console: console, onAction: _mediaAction),
      ),
    ],
  );

  Widget _journalOptions() => JournalSurface(
    lined: true,
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Journal options', style: JournalPalette.title),
          const SizedBox(height: 18),
          const Text('Reading size', style: JournalPalette.heading),
          const SizedBox(height: 9),
          Wrap(
            spacing: 8,
            children: [
              for (final scale in [1.0, 1.25, 1.5])
                OutlinedButton(
                  onPressed: () => setState(() => _textScale = scale),
                  child: Text('${(scale * 100).round()}%'),
                ),
            ],
          ),
          const SizedBox(height: 14),
          const JournalPreferencesControls(),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _help,
            icon: const Icon(Icons.help_outline),
            label: const Text('Field guide'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => setState(() => _classic = true),
            icon: const Icon(Icons.terminal),
            label: const Text('Classic compatibility view'),
          ),
          const SizedBox(height: 18),
          const Text('Campaign options', style: JournalPalette.heading),
          const SizedBox(height: 8),
          const Text(
            'Save the campaign and return to the title screen to change game content and start options.',
            style: JournalPalette.body,
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _organisation.canNavigate
                ? () => _organisation.openSection('x')
                : null,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save & exit'),
          ),
        ],
      ),
    ),
  );

  Widget _journalFallback(bool compact) => KeyedSubtree(
    key: ValueKey('journal-specialist-viewport:${MediaQuery.sizeOf(context)}'),
    child: Stack(
      children: [
        Positioned.fill(child: _journalUtilityBody(compact)),
        Positioned.fill(
          child: ExcludeFocus(
            child: Offstage(
              child: ConsoleWidget(console, key: ConsoleWidget.globalKey),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _journalUtilityBody(bool compact) => Theme(
    data: buildJournalTheme(),
    child: DecoratedBox(
      key: const ValueKey('journal-specialist-shell'),
      decoration: const BoxDecoration(
        color: JournalPalette.leather,
        image: DecorationImage(
          image: AssetImage(JournalPalette.leatherAsset),
          fit: BoxFit.cover,
          opacity: .7,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 8 : 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            JournalSurface(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  JournalIllustratedIcon(
                    icon: tactical || game.mode == GameMode.site
                        ? JournalIcon.operations
                        : JournalIcon.reports,
                    size: compact ? 34 : 42,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'LIBERAL CRIME SQUAD',
                          style: JournalPalette.small,
                        ),
                        Text(
                          (tactical || game.mode == GameMode.site)
                              ? 'Field operation'
                              : 'The movement’s journal',
                          style: JournalPalette.heading,
                        ),
                        if (game.mode == GameMode.site &&
                            game.activeSite != null)
                          Text(
                            '${game.activeSite!.getName()} · Level ${game.locz + 1}',
                            style: JournalPalette.small,
                          ),
                      ],
                    ),
                  ),
                  if (hq ||
                      _journalNavigation.active ||
                      game.mode == GameMode.site)
                    Text(
                      '${game.day} ${getMonth(game.month).substring(0, 3)} ${game.year} · \$${game.ledger.funds}',
                      style: JournalPalette.small,
                    ),
                  PopupMenuButton<double>(
                    tooltip: 'Reading size',
                    initialValue: _textScale,
                    onSelected: (value) => setState(() => _textScale = value),
                    icon: const Icon(
                      Icons.text_fields,
                      color: JournalPalette.brassDark,
                    ),
                    itemBuilder: (_) => [
                      for (final scale in [1.0, 1.25, 1.5])
                        PopupMenuItem(
                          value: scale,
                          child: Text('${(scale * 100).round()}%'),
                        ),
                    ],
                  ),
                  const JournalPreferencesButton(),
                  IconButton(
                    tooltip: 'Switch readable / classic view',
                    onPressed: () => setState(() => _classic = true),
                    icon: const Icon(
                      Icons.terminal,
                      color: JournalPalette.brassDark,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Field guide',
                    onPressed: _help,
                    icon: const Icon(
                      Icons.menu_book_outlined,
                      color: JournalPalette.brassDark,
                    ),
                  ),
                ],
              ),
            ),
            if (_canSwitchSections) _sectionStrip(),
            const SizedBox(height: 8),
            Expanded(
              child: fieldPrompt
                  ? _fieldOperation()
                  : console.eventMessage != null
                  ? _eventMessageView()
                  : isLegislativeVoteScreen(console)
                  ? JournalLegislationView(console: console, onAction: _send)
                  : tactical || fieldPrompt
                  ? _fieldOperation()
                  : JournalSurface(
                      padding: EdgeInsets.zero,
                      child: Material(
                        type: MaterialType.transparency,
                        child: hq
                            ? _headquarters(compact)
                            : _workspace(false, compact),
                      ),
                    ),
            ),
            const SizedBox(height: 6),
            _statusbar(),
          ],
        ),
      ),
    ),
  );

  Widget _eventMessageView({bool embeddedJournal = false}) => JournalSurface(
    key: const ValueKey('journal-event-message'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          console.eventTitle ?? 'Campaign update',
          style: JournalPalette.heading,
        ),
        const SizedBox(height: 18),
        Expanded(
          child: SingleChildScrollView(
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 840),
                child: Text(
                  console.eventMessage!,
                  key: const ValueKey('journal-current-announcement'),
                  style: const TextStyle(fontSize: 17, height: 1.55),
                ),
              ),
            ),
          ),
        ),
        if (!embeddedJournal) const SizedBox(height: 12),
        if (!embeddedJournal)
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: console.awaitingInput ? () => _send('Enter') : null,
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: const JournalCommandLabel(
                shortcut: 'Enter',
                label: 'Continue',
                primary: true,
              ),
            ),
          ),
      ],
    ),
  );

  void _sendFieldAction(ConsoleAction action, int revision) {
    if (_inspectedPersonId == null &&
        action.enabled &&
        console.revision.value == revision &&
        console.actions.any((current) => identical(current, action))) {
      _send(action.key);
    }
  }

  Widget _withFieldInspector(Widget field) {
    final person = _inspectedPerson;
    if (person == null) return field;
    void close() => setState(() => _inspectedPersonId = null);
    return Stack(
      children: [
        Positioned.fill(child: ExcludeFocus(child: field)),
        Positioned.fill(
          child: ModalBarrier(
            color: Colors.black26,
            dismissible: true,
            onDismiss: close,
            semanticsLabel: 'Close character dossier',
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: CrewInspector(person: person, onClose: close, compact: true),
          ),
        ),
      ],
    );
  }

  Widget _fieldOperation() => _withFieldInspector(
    LayoutBuilder(
      builder: (context, bounds) {
        final narrow = bounds.maxWidth < 1000;
        final revision = console.revision.value;
        final actions = List<ConsoleAction>.of(console.actions);
        final movementEnabled = actions.any(
          (action) => action.entityType == 'field-direction' && action.enabled,
        );
        final fieldActor = game.activeSquadMember ?? game.squad.firstOrNull;
        void sendFieldAction(String key) {
          final action = actions
              .where((action) => action.key == key)
              .firstOrNull;
          if (action != null) _sendFieldAction(action, revision);
        }

        return JournalFieldOperationView(
          narrow: narrow,
          maxHeight: bounds.maxHeight,
          reportScrollController: _operationScroll,
          map: TacticalMapView(
            onMove: sendFieldAction,
            showHeading: false,
            showMovementControls: false,
            movementEnabled: movementEnabled,
          ),
          heading: Text(
            fieldPrompt
                ? console.eventTitle ?? 'Field decision'
                : 'Squad & orders',
            key: fieldPrompt ? const ValueKey('journal-field-prompt') : null,
            style: JournalPalette.heading,
          ),
          actorStatus: fieldActor == null
              ? null
              : JuiceBadge(person: fieldActor, compact: true, showHelp: false),
          crew: !fieldPrompt
              ? Wrap(
                  key: const ValueKey('journal-operation-crew'),
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final person in game.squad)
                      Tooltip(
                        message:
                            '${person.name} · Juice ${person.juice} · ${person.blood}/${person.maxBlood} blood',
                        child: Semantics(
                          button: true,
                          label: 'Inspect ${person.name} dossier',
                          child: InkWell(
                            key: ValueKey('field-inspect:${person.id}'),
                            onTap: () => _openDossier(person),
                            child: CrewPortrait(person: person, size: 40),
                          ),
                        ),
                      ),
                  ],
                )
              : null,
          body: fieldPrompt && console.eventMessage != null
              ? Text(
                  console.eventMessage!,
                  key: const ValueKey('journal-field-announcement'),
                  style: const TextStyle(fontSize: 16, height: 1.5),
                )
              : DirectContent(
                  console: console,
                  onAction: sendFieldAction,
                  onInspect: _openDossier,
                  hiddenRows: {
                    if (fieldPrompt) ...{
                      for (var row = 0; row < 9; row++) row,
                      23,
                      24,
                    },
                  },
                  leadingActionRows: fieldPrompt ? const {} : const {23, 24},
                  rowMaxColumns: {for (var row = 11; row <= 22; row++) row: 55},
                  showActions: !fieldPrompt,
                  hideActionLabels: fieldPrompt,
                  excludedActionTypes: const {'field-direction'},
                ),
          choices:
              fieldPrompt &&
                  console.eventMessage == null &&
                  console.actions.isNotEmpty
              ? Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final action in actions)
                      if (action.entityType != 'field-direction')
                        OutlinedButton(
                          onPressed: action.enabled
                              ? () => _sendFieldAction(action, revision)
                              : null,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              JournalShortcutBadge(shortcut: action.key),
                              const SizedBox(width: 10),
                              Flexible(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_clean(action.label)),
                                    if (action.entityType == 'field-speaker' &&
                                        action.intentLabel != null)
                                      Text(
                                        action.intentLabel!,
                                        style: JournalPalette.small,
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                  ],
                )
              : null,
          input:
              fieldPrompt &&
                  (console.eventMessage != null ||
                      console.textInput ||
                      console.actions.isEmpty)
              ? _inputBar()
              : null,
          movement: _movementStrip(),
        );
      },
    ),
  );

  Widget _workspace(
    bool classic,
    bool compact, {
    bool embeddedJournal = false,
  }) {
    if (!classic && pursuitContext(console) != null) {
      return JournalPursuitView(console: console, onAction: _send);
    }
    if (!classic && recoveryContext(console) != null) {
      return JournalRecoveryView(console: console, onAction: _send);
    }
    final profile = console.journalProfile;
    if (!classic && profile != null) {
      return JournalProfileView(
        name: profile.person.name,
        editing: console.textInput,
        dossier: CrewDossier(
          person: profile.person,
          embedded: true,
          page: profile.page,
          pageShortcuts: [
            for (final action in console.actions)
              if (action.enabled && {'Up', 'Down'}.contains(action.key))
                action.key,
          ],
          onPage: (next) {
            final delta = (next - profile.page) % 3;
            if (delta != 0) _send(delta == 1 ? 'Down' : 'Up');
          },
        ),
        controls: profile.confirming
            ? DirectContent(
                console: console,
                onAction: _send,
                journalPage: true,
                hiddenRows: {for (var row = 0; row < 22; row++) row},
              )
            : console.textInput
            ? _inputBar()
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final action in console.actions)
                    if (!{'Up', 'Down'}.contains(action.key))
                      _profileAction(action),
                ],
              ),
      );
    }
    if (!classic &&
        console.screen == 'generic' &&
        !console.awaitingInput &&
        console.graphics.isNotEmpty) {
      return JournalLiveGraphicView(graphic: _sourceGraphics());
    }
    if (!classic &&
        console.screen == 'generic' &&
        !console.awaitingInput &&
        !console.textInput &&
        console.actions.isEmpty &&
        console.eventMessage == null) {
      // Source handlers may paint map generation or other intermediate buffers
      // while the day is still processing. Only an awaited reader is a choice.
      return const JournalProcessingView();
    }
    if (embeddedJournal &&
        console.screen != 'article' &&
        console.screen != 'full_map') {
      return _journalManagementPage();
    }
    final planning = !classic && console.screen == 'planning';
    final article =
        !classic && console.screen == 'article' && console.article != null;
    final fullMap = !classic && console.screen == 'full_map';
    final rows = console.buffer
        .map((r) => r.map((c) => c.glyph).join().trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final heading = tactical
        ? 'Field operation'
        : console.screen == 'article'
        ? 'Media report'
        : console.locationHeading != null
        ? console.locationHeading!
        : console.journalPeople.isNotEmpty && console.recruitment == null
        ? 'Crew & choices'
        : _screenHeading(rows);
    final content = classic
        ? const SizedBox()
        : planning
        ? LayoutBuilder(
            builder: (context, constraints) => Padding(
              padding: const EdgeInsets.all(16),
              child: CityPlanningView(
                console: console,
                onAction: _send,
                viewportHeight: constraints.maxHeight - 32,
              ),
            ),
          )
        : console.screen == 'article' && console.article != null
        ? ArticleView(article: console.article!)
        : SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: rows.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final graphic in console.graphics)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: SizedBox(
                              width: 400,
                              child: AspectRatio(
                                aspectRatio:
                                    (graphic.right - graphic.left) /
                                    (graphic.bottom - graphic.top) *
                                    .44,
                                child: graphic.graphic,
                              ),
                            ),
                          ),
                        ),
                      if (tactical && game.activeSite != null) ...[
                        TacticalMapView(
                          onMove: _send,
                          showMovementControls: false,
                          movementEnabled:
                              !game.siteAlarm ||
                              !game.encounter.any((person) => person.isEnemy),
                        ),
                        const SizedBox(height: 22),
                        _eyebrow('OPERATION REPORT'),
                        const SizedBox(height: 12),
                      ],
                      if (console.screen == 'full_map')
                        const FullSiteMap()
                      else if (console.screen == 'planning')
                        CityPlanningView(console: console, onAction: _send)
                      else
                        DirectContent(
                          console: console,
                          onAction: _send,
                          onInspect: _openDossier,
                          textInput: console.textInput,
                          hiddenRows: tactical
                              ? {for (var row = 11; row <= 22; row++) row}
                              : const {},
                          maxColumn: tactical ? 54 : 80,
                        ),
                    ],
                  ),
          );
    return JournalWorkspaceView(
      classic: classic,
      compact: compact,
      planning: planning,
      heading: heading,
      content: content,
      returnControl: (article || fullMap) && !embeddedJournal
          ? TextButton.icon(
              key: const ValueKey('specialized-return'),
              onPressed: () => _send('Enter'),
              icon: Icon(
                fullMap ? Icons.arrow_back : Icons.arrow_forward,
                size: 18,
              ),
              label: JournalCommandLabel(
                shortcut: 'Enter',
                label: fullMap ? 'Back to operation' : 'Continue',
              ),
            )
          : _action('Escape') != null
          ? TextButton.icon(
              onPressed: () => _send('Escape'),
              icon: const Icon(Icons.arrow_back, size: 18),
              label: const JournalCommandLabel(
                shortcut: 'Escape',
                label: 'Back',
              ),
            )
          : null,
      movement: tactical ? _movementStrip() : null,
      choices: classic ? _choicePanel() : null,
      input:
          !planning &&
              !article &&
              !fullMap &&
              (console.textInput || console.actions.isEmpty)
          ? _inputBar()
          : null,
    );
  }

  Widget _profileAction(ConsoleAction action) {
    final (label, icon) = switch (action.key) {
      'Enter' => ('Back to directory', Icons.arrow_back),
      'Left' => ('Previous', Icons.chevron_left),
      'Right' => ('Next', Icons.chevron_right),
      'a' => ('Assign a task', Icons.assignment_outlined),
      'n' => ('Change name', Icons.edit_outlined),
      'g' => ('Change gender', Icons.person_outline),
      _ => (_clean(action.label), Icons.chevron_right),
    };
    return JournalProfileActionView(
      key: ValueKey('journal-profile-control:${action.key}'),
      shortcut: action.key,
      label: label,
      icon: icon,
      onPressed: action.enabled ? () => _send(action.key) : null,
    );
  }

  Widget _journalManagementPage() {
    final rows = console.buffer
        .map((row) => row.map((cell) => cell.glyph).join().trim())
        .where((row) => row.isNotEmpty)
        .toList();
    final heading = rows.isEmpty ? 'Organisation' : _screenHeading(rows);
    final navigation = console.navigation;
    final selected = _organisation.selectedPerson;
    final squadOnly = const {
      'equipment',
      'vehicles',
    }.contains(navigation?.section);
    final selectedId =
        selected != null &&
            (!squadOnly || game.squad.any((person) => person.id == selected.id))
        ? selected.id
        : game.squad.firstOrNull?.id;
    return JournalManagementView(
      heading: heading == 'Equip the Squad' ? 'Equipment' : heading,
      backControl: navigation == null
          ? null
          : TextButton.icon(
              key: const ValueKey('journal-management-back'),
              onPressed: () => _send(navigation.backKey),
              icon: const Icon(Icons.arrow_back, size: 16),
              label: JournalCommandLabel(
                shortcut: navigation.backKey,
                label: 'Back',
              ),
              style: TextButton.styleFrom(minimumSize: const Size(40, 34)),
            ),
      scrollStorageId: console.recruitmentTarget == null
          ? 'journal-management-scroll:${navigation?.section ?? 'entry'}'
          : 'recruitment-targets:${console.recruitmentTarget!.recruiter.id}:${console.recruitmentTarget!.page}',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (console.graphics.isNotEmpty) _sourceGraphics(),
          DirectContent(
            console: console,
            onAction: _send,
            onInspect: _openDossier,
            textInput: console.textInput,
            journalPage: true,
            selectedPersonId: selectedId,
            hiddenRows: const {0},
          ),
        ],
      ),
      input: console.textInput ? _inputBar() : null,
    );
  }

  Widget _sourceGraphics() {
    final graphics = console.graphics
        .where((g) => g.right > g.left && g.bottom > g.top)
        .toList();
    if (graphics.isEmpty) return const SizedBox.shrink();
    final bounds = graphics
        .map((g) => Rect.fromLTRB(g.left, g.top, g.right, g.bottom))
        .reduce((a, b) => a.expandToInclude(b));
    return Align(
      alignment: Alignment.center,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: AspectRatio(
            aspectRatio: bounds.width / bounds.height,
            child: LayoutBuilder(
              builder: (context, size) => Stack(
                children: [
                  // Keep the source's layering: an animation replaces the
                  // flag already painted at the same console coordinates.
                  for (final graphic in graphics)
                    Positioned(
                      left:
                          (graphic.left - bounds.left) /
                          bounds.width *
                          size.maxWidth,
                      top:
                          (graphic.top - bounds.top) /
                          bounds.height *
                          size.maxHeight,
                      width:
                          (graphic.right - graphic.left) /
                          bounds.width *
                          size.maxWidth,
                      height:
                          (graphic.bottom - graphic.top) /
                          bounds.height *
                          size.maxHeight,
                      child: graphic.graphic,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _screenHeading(List<String> rows) {
    final location = console.locationHeading;
    if (location != null && location.isNotEmpty) return location;
    for (final row in rows) {
      final title = row
          .replaceFirst(RegExp(r'\s*Money:\s*\$[-\d,]+.*$'), '')
          .replaceAll(RegExp(r'[═─—━]{2,}'), ' ')
          .replaceAll('===', '')
          .replaceAll(RegExp(r'\s{2,}'), ' ')
          .trim();
      if (title.length < 5 ||
          title.contains('CODE NAME') && title.contains('HEALTH')) {
        continue;
      }
      final lower = title.toLowerCase();
      if (lower.contains('assign tasks to liberals')) {
        return 'Daily assignments';
      }
      if (lower.contains('choosing the right liberal vehicle')) {
        return 'Vehicles';
      }
      if (lower.contains('equip the squad')) return 'Equipment';
      if (lower.contains('save game management')) return 'Saved campaigns';
      if (lower.contains('where will the squad go')) return 'Plan an operation';
      if (lower.contains('status of the liberal agenda')) {
        return 'The Liberal Agenda';
      }
      return title;
    }
    return 'Preparing your campaign';
  }

  int _currentSection() {
    if (hq) return 0;
    return switch (console.navigation?.section) {
      'people' => 1,
      'assignments' => 2,
      'operations' => 3,
      'agenda' => 4,
      'media' => 5,
      'equipment' => 6,
      _ => _tab,
    };
  }

  Widget _movementStrip() {
    final revision = console.revision.value;
    final directions = {
      for (final action in console.actions)
        if (action.entityType == 'field-direction') action.key: action,
    };
    final fleeing = directions.values.any(
      (action) => action.entityCategory == 'escape',
    );
    final canMove = directions.values.any((action) => action.enabled);
    final escapeAction = console.actions
        .where((action) => action.key.toLowerCase() == 'v' && action.enabled)
        .firstOrNull;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: Text(
            fleeing ? 'Choose an escape direction' : 'Move your squad',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        for (final (direction, icon) in [
          ('Left', Icons.arrow_back),
          ('Up', Icons.arrow_upward),
          ('Down', Icons.arrow_downward),
          ('Right', Icons.arrow_forward),
        ])
          IconButton.outlined(
            tooltip: 'Move ${direction.toLowerCase()}',
            onPressed: directions[direction]?.enabled == true
                ? () => _sendFieldAction(directions[direction]!, revision)
                : null,
            icon: Icon(icon, size: 20),
          ),
        SizedBox(
          width: 280,
          height: 36 * _textScale,
          child: Text(
            fieldPrompt && !fleeing
                ? 'Answer the current prompt to continue.'
                : !canMove
                ? escapeAction == null
                      ? 'Resolve the current decision to move.'
                      : 'Resolve the encounter or choose ${escapeAction.label}.'
                : 'Click an adjacent tile or use the arrow keys.',
            style: const TextStyle(color: muted, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _choicePanel() => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: const Color(0xFFEAEAE1),
      border: Border.all(color: line),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _eyebrow('AVAILABLE CHOICES'),
        const SizedBox(height: 14),
        if (tactical) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final (direction, icon) in [
                ('Left', Icons.arrow_back),
                ('Up', Icons.arrow_upward),
                ('Down', Icons.arrow_downward),
                ('Right', Icons.arrow_forward),
              ])
                IconButton.outlined(
                  tooltip: 'Move ${direction.toLowerCase()}',
                  onPressed:
                      game.siteAlarm &&
                          game.encounter.any((person) => person.isEnemy)
                      ? null
                      : () => _send(direction),
                  icon: Icon(icon, size: 20),
                ),
            ],
          ),
          if (game.siteAlarm && game.encounter.any((person) => person.isEnemy))
            const Text(
              'Resolve the encounter or choose Flee to move.',
              style: TextStyle(fontSize: 11, color: vermilion),
            ),
          const SizedBox(height: 12),
        ],
        Expanded(
          child: ListView(
            children: [
              for (final a in console.actions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _actionButton(a, full: true),
                ),
              if (console.actions.isEmpty)
                FilledButton(
                  onPressed: console.textInput
                      ? _submitText
                      : () => _send('Enter'),
                  child: Text(
                    console.textInput ? 'Confirm text' : 'Continue →',
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
  Widget _actionButton(ConsoleAction a, {bool full = false, String? label}) =>
      OutlinedButton(
        onPressed: a.enabled ? () => _send(a.key) : null,
        style: OutlinedButton.styleFrom(
          backgroundColor: a.enabled
              ? const Color(0xFFFCFAF5)
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          alignment: Alignment.centerLeft,
        ),
        child: Row(
          mainAxisSize: full ? MainAxisSize.max : MainAxisSize.min,
          children: [
            JournalShortcutBadge(shortcut: a.key),
            const SizedBox(width: 10),
            if (full)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label ?? _clean(a.label),
                      style: const TextStyle(fontSize: 13, height: 1.35),
                    ),
                    if (a.label.endsWith(':') && _selection(a).isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        '${_selection(a)}  ↻',
                        style: const TextStyle(
                          fontSize: 11,
                          color: teal,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              )
            else
              Flexible(
                child: Text(
                  label ?? _clean(a.label),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
      );
  String _selection(ConsoleAction action) {
    if (action.y < 0 || action.y >= console.height) return '';
    final row = console.buffer[action.y];
    final start = (action.x + action.width).clamp(0, console.width);
    var end = console.width;
    for (final other in console.actions) {
      if (other.y == action.y && other.x > action.x && other.x < end) {
        end = other.x;
      }
    }
    return start < end
        ? row.skip(start).take(end - start).map((c) => c.glyph).join().trim()
        : '';
  }

  Widget _inputBar({bool creation = false}) {
    if (!console.textInput) {
      return Align(
        alignment: Alignment.centerRight,
        child: FilledButton(
          onPressed: () => _send('Enter'),
          child: const JournalCommandLabel(
            shortcut: 'Enter',
            label: 'Continue',
            primary: true,
          ),
        ),
      );
    }
    final field = TextField(
      key: creation ? const ValueKey('creation-public-name') : null,
      focusNode: _entryFocus,
      controller: _entry,
      selectAllOnFocus: false,
      onSubmitted: (_) => unawaited(_submitText()),
      decoration: InputDecoration(
        isDense: true,
        hintText: creation ? 'Your public name' : 'Enter a name or answer',
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
      ),
    );
    final submit = FilledButton(
      onPressed: _sending ? null : _submitText,
      child: JournalCommandLabel(
        shortcut: 'Enter',
        label: creation ? 'Begin campaign' : 'Confirm text',
        primary: true,
      ),
    );
    final cancel = TextButton(
      onPressed: _sending ? null : () => _send('Escape'),
      child: Text(creation ? 'Use original name' : 'Cancel edits'),
    );
    if (creation) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          field,
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [submit, cancel]),
        ],
      );
    }
    return LayoutBuilder(
      builder: (context, bounds) {
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        if (bounds.maxWidth / scale < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              field,
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 6, children: [submit, cancel]),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: field),
            const SizedBox(width: 8),
            submit,
            cancel,
          ],
        );
      },
    );
  }

  String _clean(String label) => label
      .replaceAll(RegExp(r'&[A-Za-z]'), '')
      .replaceFirst(RegExp(r'^\(?[A-Za-z0-9?]+\s*[-–:]\s*'), '')
      .trim();
  Widget _eyebrow(String text) => Text(
    text,
    style: const TextStyle(
      color: muted,
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.5,
    ),
  );
  Widget _statusbar() => ModernShellStatusBar(
    text: _navigating
        ? 'Opening section…'
        : title
        ? 'UNDERGROUND  /  $gameVersion'
        : tactical
        ? 'OPERATION IN PROGRESS'
        : hq
        ? 'PLANNING  ·  Time advances only when you end the day'
        : console.navigation?.note ?? 'Choose an action on this screen',
  );
}
