import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/engine/agenda_context.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/console_widget.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/engine/ledger_context.dart';
import 'package:lcs_new_age/engine/media_context.dart';
import 'package:lcs_new_age/engine/organisation_context.dart';
import 'package:lcs_new_age/gamestate/game_mode.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/gamestate/time.dart';
import 'package:lcs_new_age/modern/article_view.dart';
import 'package:lcs_new_age/modern/city_planning_view.dart';
import 'package:lcs_new_age/modern/crew_dossier.dart';
import 'package:lcs_new_age/modern/crew_portrait.dart';
import 'package:lcs_new_age/modern/decision_help.dart';
import 'package:lcs_new_age/modern/direct_content.dart';
import 'package:lcs_new_age/modern/full_site_map.dart';
import 'package:lcs_new_age/modern/headquarters_view.dart';
import 'package:lcs_new_age/modern/journal_agenda.dart';
import 'package:lcs_new_age/modern/journal_creation.dart';
import 'package:lcs_new_age/modern/journal_ledger.dart';
import 'package:lcs_new_age/modern/journal_legislation.dart';
import 'package:lcs_new_age/modern/journal_media.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/journal_title.dart';
import 'package:lcs_new_age/modern/organisation_controller.dart';
import 'package:lcs_new_age/modern/organisation_journal.dart';
import 'package:lcs_new_age/modern/tactical_map.dart';

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
  set _textScale(double value) => journalReadingScale.value = value;
  int _tab = 0;
  int _renderedRevision = -1;
  bool _wasTextInput = false;
  late final OrganisationController _organisation;
  bool _journalSession = false;
  String _lastConsoleScreen = 'generic';
  int _journalSection = 0;
  final _journalKey = GlobalKey<OrganisationJournalState>();
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
    _organisation = OrganisationController(console: console);
    _organisation.addListener(_organisationChanged);
    _journalSession = hq && game.pool.isNotEmpty;
    _lastConsoleScreen = console.screen;
    console.revision.addListener(_refresh);
  }

  void _organisationChanged() {
    if (mounted) setState(() {});
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
    if (hq && game.pool.isNotEmpty) {
      _journalSession = true;
      if (_lastConsoleScreen != 'headquarters' && !_organisation.busy) {
        _journalSection = 0;
      }
    }
    _lastConsoleScreen = console.screen;
    if (title) _journalSession = false;
    if (console.textInput && !_wasTextInput) {
      _entry.text = console.textInputValue;
      _entry.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _entry.text.length,
      );
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
    if (!_helpOpen &&
        !_navigating &&
        !_organisation.busy &&
        _renderedRevision == console.revision.value) {
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
    if (_inspectedPersonId != null &&
        !console.textInput &&
        event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() => _inspectedPersonId = null);
      return KeyEventResult.handled;
    }
    if (_entryFocus.hasFocus) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        _send('Escape');
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (_helpOpen ||
        _sending ||
        _navigating ||
        _organisation.busy ||
        event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (!_keyboard.hasPrimaryFocus &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.space)) {
      // Let the focused button's ActivateIntent handle Enter / Space.
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.f1) {
      unawaited(_help());
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        event.character == null &&
            ![
              LogicalKeyboardKey.enter,
              LogicalKeyboardKey.escape,
              LogicalKeyboardKey.backspace,
              LogicalKeyboardKey.arrowUp,
              LogicalKeyboardKey.arrowDown,
              LogicalKeyboardKey.arrowLeft,
              LogicalKeyboardKey.arrowRight,
              LogicalKeyboardKey.pageUp,
              LogicalKeyboardKey.pageDown,
            ].contains(event.logicalKey)) {
      return KeyEventResult.ignored;
    }
    final journalKey = event.logicalKey == LogicalKeyboardKey.enter
        ? 'Enter'
        : event.logicalKey == LogicalKeyboardKey.escape
        ? 'Escape'
        : event.character;
    if (journalKey != null &&
        _journalKey.currentState?.handleGameShortcut(journalKey) == true) {
      return KeyEventResult.handled;
    }
    if (!_classic &&
        ledgerReportFrame(console)?.management == true &&
        (journalKey == 'Enter' || journalKey == 'Escape')) {
      unawaited(_ledgerAction(ledgerReportFrame(console)!.closeAction.key));
      return KeyEventResult.handled;
    }
    if (!_classic &&
        mediaOverviewFrame(console) != null &&
        (journalKey == 'Enter' || journalKey == 'Escape')) {
      unawaited(_mediaAction(journalKey!));
      return KeyEventResult.handled;
    }
    console.keyEvent(event);
    return KeyEventResult.handled;
  }

  Future<void> _submitText() async {
    if (_sending || !console.textInput) return;
    final value = _entry.text;
    setState(() {
      _sending = true;
    });
    final oldValue = console.textInputValue;
    for (var i = 0; i < oldValue.length; i++) {
      if (!await _textKey('Backspace')) break;
    }
    for (final char in value.characters) {
      if (!await _textKey(char)) break;
    }
    await _textKey('Enter');
    if (mounted) {
      setState(() {
        _sending = false;
        _entry.clear();
      });
      _keyboard.requestFocus();
    }
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
                const Text(
                  'Click people, tasks and places directly. Tab moves between controls; Enter or Space activates the focused control. In Orders, letter shortcuts browse groups and prepare tasks; Enter confirms a prepared job card and Esc cancels it. Enter continues messages and arrows move during operations. Required names use the text field. F1 opens this guide. Classic view retains the original menu shortcuts.',
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
      _keyboard.requestFocus();
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
        _journalSession && !title && !classic && game.mode == GameMode.base;
    return Focus(
      focusNode: _keyboard,
      autofocus: true,
      onKeyEvent: _onKey,
      child: MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(_textScale)),
        child: console.eventMessage != null && !classic
            ? journal
                  ? Theme(data: buildJournalTheme(), child: _journalDesktop())
                  : _journalFallback(compact)
            : creation != null && !classic
            ? JournalCreationPage(
                console: console,
                context: creation,
                onAction: _send,
                inputBar: _inputBar(creation: true),
                onHelp: _help,
                readingControl: PopupMenuButton<double>(
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
              )
            : title && !classic
            ? JournalTitlePage(console: console, onAction: _send, onHelp: _help)
            : journal
            ? Theme(data: buildJournalTheme(), child: _journalDesktop())
            : !classic
            ? _journalFallback(compact)
            : Column(
                children: [
                  _topbar(compact),
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
                                    ? _withCrewInspector(_headquarters(compact))
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
    );
  }

  Widget _topbar(bool compact) => LayoutBuilder(
    builder: (context, bounds) {
      final narrow = bounds.maxWidth < 650;
      return Container(
        height: 60,
        padding: EdgeInsets.symmetric(horizontal: narrow ? 8 : 18),
        color: ink,
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: vermilion,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(Icons.bolt, color: paper, size: 23),
            ),
            const SizedBox(width: 10),
            Text(
              narrow ? 'LCS' : 'LIBERAL CRIME SQUAD',
              style: TextStyle(
                color: paper,
                fontSize: narrow ? 13 : 14,
                fontWeight: FontWeight.w800,
                letterSpacing: narrow ? 0 : 1,
              ),
            ),
            const Spacer(),
            if (!title) ...[
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${game.day} ${getMonth(game.month).substring(0, 3)} ${game.year}',
                    key: const ValueKey('campaign-date'),
                    style: const TextStyle(color: paper, fontSize: 12),
                  ),
                  Text(
                    '\$${game.ledger.funds}',
                    key: const ValueKey('campaign-funds'),
                    style: const TextStyle(
                      color: Color(0xFFB2C1BA),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              SizedBox(width: narrow ? 4 : 18),
            ],
            PopupMenuButton<double>(
              tooltip: 'Reading size',
              initialValue: _textScale,
              onSelected: (value) => setState(() => _textScale = value),
              icon: const Icon(Icons.text_fields, color: paper, size: 22),
              itemBuilder: (_) => [
                for (final scale in [1.0, 1.25, 1.5])
                  PopupMenuItem(
                    value: scale,
                    child: Text('${(scale * 100).round()}%'),
                  ),
              ],
            ),
            IconButton(
              tooltip: 'Switch readable / classic view',
              onPressed: () => setState(() => _classic = !_classic),
              icon: Icon(
                _classic ? Icons.view_agenda_outlined : Icons.terminal,
                color: paper,
                size: 22,
              ),
            ),
            IconButton(
              tooltip: 'Field guide',
              onPressed: _help,
              icon: const Icon(Icons.help_outline, color: paper, size: 22),
            ),
          ],
        ),
      );
    },
  );
  Widget _sectionStrip() => Container(
    height: 44,
    decoration: const BoxDecoration(
      color: JournalPalette.inset,
      border: Border(bottom: BorderSide(color: line)),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (index, label, command) in <(int, String, String?)>[
            (0, 'Headquarters', null),
            (1, 'People', 'r'),
            (2, 'Assignments', 'a'),
            (3, 'Operations', 'f'),
            (4, 'Agenda', 'l'),
            (5, 'Media', 'm'),
            (6, 'Equipment', 'e'),
          ])
            TextButton(
              key: ValueKey('section:$index'),
              onPressed:
                  _canSwitchSections &&
                      (!hq ||
                          command == null ||
                          _action(command)?.enabled == true)
                  ? () => _navigateTo(index, command)
                  : null,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                foregroundColor: _currentSection() == index ? teal : ink,
                backgroundColor: _currentSection() == index
                    ? teal.withValues(alpha: .1)
                    : null,
              ),
              child: Text(label, style: const TextStyle(fontSize: 12)),
            ),
        ],
      ),
    ),
  );

  Widget _sidebar() => Container(
    width: 190,
    height: double.infinity,
    decoration: const BoxDecoration(
      color: JournalPalette.inset,
      border: Border(right: BorderSide(color: line)),
    ),
    padding: const EdgeInsets.fromLTRB(10, 18, 10, 12),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _eyebrow('THE MOVEMENT'),
          const SizedBox(height: 16),
          _nav(Icons.grid_view_outlined, 'Headquarters', 0, null),
          _nav(Icons.people_outline, 'People & squads', 1, 'r'),
          _nav(Icons.fact_check_outlined, 'Daily assignments', 2, 'a'),
          _nav(Icons.explore_outlined, 'Operations', 3, 'f'),
          _nav(Icons.account_balance_outlined, 'Liberal Agenda', 4, 'l'),
          _nav(Icons.newspaper_outlined, 'Media & impact', 5, 'm'),
          _nav(Icons.backpack_outlined, 'Equipment', 6, 'e'),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              _canSwitchSections
                  ? 'Switch sections directly. Time advances when you end the day.'
                  : tactical
                  ? 'Finish or leave the site before returning to the movement.'
                  : 'Complete this choice before switching sections.',
              style: const TextStyle(color: muted, fontSize: 11),
            ),
          ),
          if (hq)
            TextButton.icon(
              onPressed: () => _choose('x'),
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const Text('Save & exit'),
            ),
        ],
      ),
    ),
  );
  Widget _nav(IconData icon, String text, int index, String? key) {
    final enabled =
        _canSwitchSections &&
        (!hq || key == null || _action(key)?.enabled == true);
    final active = hq && index == 0 || !hq && _currentSection() == index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: TextButton(
        key: ValueKey('section:$index'),
        onPressed: enabled ? () => _navigateTo(index, key) : null,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          backgroundColor: active
              ? teal.withValues(alpha: .1)
              : Colors.transparent,
          foregroundColor: active ? teal : ink,
          disabledForegroundColor: muted.withValues(alpha: .65),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 19),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
                        'Open source · GPL-2.0',
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
    showFirstSteps: _guide,
    onDismissFirstSteps: () => setState(() => _guide = false),
  );

  Future<void> _openJournalSection(int section) async {
    if (!_organisation.canNavigate) return;
    setState(() {
      _journalSection = section;
      _inspectedPersonId = null;
    });
    switch (section) {
      case 0:
      case 5:
        await _organisation.returnToHeadquarters();
      case 1:
        if (await _organisation.openSection('r')) {
          final finance = _action('v');
          if (finance?.enabled == true) {
            await _organisation.sendAction(
              finance!,
              revision: console.revision.value,
            );
          }
        }
      case 2:
        if (await _organisation.openSection('r')) {
          final justice = _action('4');
          if (justice?.enabled == true) {
            await _organisation.sendAction(
              justice!,
              revision: console.revision.value,
            );
          }
        }
      case 3:
        await _organisation.openSection('l');
      case 4:
        await _organisation.openSection('m');
      case 6:
        await _organisation.returnToHeadquarters();
      case 7:
        await _organisation.returnToHeadquarters();
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
        await _organisation.returnToHeadquarters();
        if (mounted && hq) setState(() => _journalSection = 0);
      }
    } else {
      _send(key);
    }
  }

  Future<void> _mediaAction(String key) async {
    final action = _action(key);
    if (action == null) return;
    if (action.key == 'Enter' || action.key == 'Escape') {
      if (await _organisation.sendAction(
            action,
            revision: console.revision.value,
          ) &&
          mounted &&
          hq) {
        setState(() => _journalSection = 0);
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
      detail = _eventMessageView();
    } else if (isLegislativeVoteScreen(console)) {
      detail = JournalLegislationView(console: console, onAction: _send);
    } else if (ledgerReportFrame(console) != null) {
      detail = JournalLedgerOverview(console: console, onAction: _ledgerAction);
    } else if (agendaOverviewFrame(console) != null) {
      detail = JournalAgendaView(console: console, onAction: _send);
    } else if (mediaOverviewFrame(console) != null) {
      detail = JournalMediaOverview(console: console, onAction: _mediaAction);
    } else if (_journalSection == 7 && !console.textInput) {
      detail = _journalOptions();
    } else if (!primary) {
      detail = _workspace(false, true);
    } else if (_journalSection == 2 &&
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
      section: isLegislativeVoteScreen(console)
          ? 3
          : ledgerReportFrame(console) != null
          ? 1
          : agendaOverviewFrame(console) != null
          ? 3
          : mediaOverviewFrame(console) != null
          ? 4
          : _journalSection,
      fullSpreadDetail:
          console.eventMessage != null ||
          isLegislativeVoteScreen(console) ||
          ledgerReportFrame(console) != null ||
          agendaOverviewFrame(console) != null ||
          mediaOverviewFrame(console) != null ||
          console.screen == 'article' && console.article != null,
      onSection: _openJournalSection,
      detail: detail,
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
                  if (hq || _journalSession || game.mode == GameMode.site)
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

  Widget _eventMessageView() => JournalSurface(
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
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: console.awaitingInput ? () => _send('Enter') : null,
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: const Text('Continue'),
          ),
        ),
      ],
    ),
  );

  Widget _fieldOperation() => LayoutBuilder(
    builder: (context, bounds) {
      final narrow = bounds.maxWidth < 1000;
      final movementEnabled =
          !fieldPrompt &&
          (!game.siteAlarm || !game.encounter.any((person) => person.isEnemy));
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: narrow ? 3 : 5,
                  child: TacticalMapView(
                    onMove: _send,
                    showHeading: false,
                    showMovementControls: false,
                    movementEnabled: movementEnabled,
                  ),
                ),
                JournalBinding(width: narrow ? 16 : 26),
                Expanded(
                  flex: narrow ? 2 : 3,
                  child: JournalSurface(
                    key: const ValueKey('journal-operation-report'),
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Scrollbar(
                            controller: _operationScroll,
                            thumbVisibility: true,
                            child: SingleChildScrollView(
                              controller: _operationScroll,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    fieldPrompt
                                        ? console.eventTitle ?? 'Field decision'
                                        : 'Squad & orders',
                                    key: fieldPrompt
                                        ? const ValueKey('journal-field-prompt')
                                        : null,
                                    style: JournalPalette.heading,
                                  ),
                                  const SizedBox(height: 8),
                                  if (!fieldPrompt)
                                    Wrap(
                                      key: const ValueKey(
                                        'journal-operation-crew',
                                      ),
                                      spacing: 8,
                                      runSpacing: 6,
                                      children: [
                                        for (final person in game.squad)
                                          Tooltip(
                                            message:
                                                '${person.name} · ${person.blood}/${person.maxBlood} blood',
                                            child: InkWell(
                                              onTap: () => _openDossier(person),
                                              child: CrewPortrait(
                                                person: person,
                                                size: 40,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  const SizedBox(height: 10),
                                  if (fieldPrompt &&
                                      console.eventMessage != null)
                                    Text(
                                      console.eventMessage!,
                                      key: const ValueKey(
                                        'journal-field-announcement',
                                      ),
                                      style: const TextStyle(
                                        fontSize: 16,
                                        height: 1.5,
                                      ),
                                    )
                                  else
                                    DirectContent(
                                      console: console,
                                      onAction: _send,
                                      onInspect: _openDossier,
                                      hiddenRows: {
                                        if (fieldPrompt) ...{
                                          for (var row = 0; row < 9; row++) row,
                                          23,
                                          24,
                                        } else
                                          for (var row = 11; row <= 22; row++)
                                            row,
                                      },
                                      leadingActionRows: fieldPrompt
                                          ? const {}
                                          : const {23, 24},
                                      rowMaxColumns: fieldPrompt
                                          ? {
                                              for (
                                                var row = 11;
                                                row <= 22;
                                                row++
                                              )
                                                row: 55,
                                            }
                                          : const {},
                                      showActions: !fieldPrompt,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (fieldPrompt &&
                            console.eventMessage == null &&
                            console.actions.isNotEmpty)
                          ConstrainedBox(
                            constraints: BoxConstraints(
                              maxHeight: bounds.maxHeight * .45,
                            ),
                            child: SingleChildScrollView(
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final action in console.actions)
                                    _actionButton(action),
                                ],
                              ),
                            ),
                          ),
                        if (fieldPrompt &&
                            (console.eventMessage != null ||
                                console.textInput ||
                                console.actions.isEmpty))
                          _inputBar(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          JournalSurface(
            key: const ValueKey('journal-operation-controls'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: _movementStrip(),
          ),
        ],
      );
    },
  );

  Widget _workspace(bool classic, bool compact) {
    final profile = console.journalProfile;
    if (!classic && profile != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: console.textInput
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Rename ${profile.person.name}',
                      style: JournalPalette.heading,
                    ),
                  )
                : CrewDossier(
                    person: profile.person,
                    embedded: true,
                    page: profile.page,
                    onPage: (next) {
                      final delta = (next - profile.page) % 3;
                      if (delta != 0) _send(delta == 1 ? 'Down' : 'Up');
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: console.textInput
                ? _inputBar()
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final action in console.actions)
                        if (!{'Up', 'Down'}.contains(action.key))
                          _actionButton(
                            action,
                            label: switch (action.key) {
                              'Left' => 'Previous crew member',
                              'Right' => 'Next crew member',
                              _ => null,
                            },
                          ),
                    ],
                  ),
          ),
        ],
      );
    }
    final journal = !classic;
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
        : console.journalPeople.isNotEmpty && console.recruitment == null
        ? 'Crew & choices'
        : _screenHeading(rows);
    return Padding(
      padding: EdgeInsets.all(compact ? 12 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!planning) ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        heading,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -.6,
                        ),
                      ),
                    ],
                  ),
                ),
                if (article || fullMap)
                  TextButton.icon(
                    key: const ValueKey('specialized-return'),
                    onPressed: () => _send('Enter'),
                    icon: Icon(
                      fullMap ? Icons.arrow_back : Icons.arrow_forward,
                      size: 18,
                    ),
                    label: Text(fullMap ? 'Back to operation' : 'Continue'),
                  )
                else if (_action('Escape') != null)
                  TextButton.icon(
                    onPressed: () => _send('Escape'),
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: const Text('Back'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (tactical) ...[_movementStrip(), const SizedBox(height: 14)],
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: classic
                      ? const SizedBox()
                      : Material(
                          color: journal
                              ? JournalPalette.card
                              : const Color(0xFFFCFAF5),
                          shape: RoundedRectangleBorder(
                            side: BorderSide(
                              color: journal ? JournalPalette.rule : line,
                            ),
                            borderRadius: BorderRadius.circular(
                              journal ? 2 : 7,
                            ),
                          ),
                          child: planning
                              ? LayoutBuilder(
                                  builder: (context, constraints) => Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: CityPlanningView(
                                      console: console,
                                      onAction: _send,
                                      viewportHeight:
                                          constraints.maxHeight - 32,
                                    ),
                                  ),
                                )
                              : console.screen == 'article' &&
                                    console.article != null
                              ? ArticleView(article: console.article!)
                              : SingleChildScrollView(
                                  padding: const EdgeInsets.all(14),
                                  child: rows.isEmpty
                                      ? const Center(
                                          child: CircularProgressIndicator(),
                                        )
                                      : Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            for (final graphic
                                                in console.graphics)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  bottom: 20,
                                                ),
                                                child: Align(
                                                  alignment:
                                                      Alignment.centerLeft,
                                                  child: SizedBox(
                                                    width: 400,
                                                    child: AspectRatio(
                                                      aspectRatio:
                                                          (graphic.right -
                                                              graphic.left) /
                                                          (graphic.bottom -
                                                              graphic.top) *
                                                          .44,
                                                      child: graphic.graphic,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            if (tactical &&
                                                game.activeSite != null) ...[
                                              TacticalMapView(
                                                onMove: _send,
                                                showMovementControls: false,
                                                movementEnabled:
                                                    !game.siteAlarm ||
                                                    !game.encounter.any(
                                                      (person) =>
                                                          person.isEnemy,
                                                    ),
                                              ),
                                              const SizedBox(height: 22),
                                              _eyebrow('OPERATION REPORT'),
                                              const SizedBox(height: 12),
                                            ],
                                            if (console.screen == 'full_map')
                                              const FullSiteMap()
                                            else if (console.screen ==
                                                'planning')
                                              CityPlanningView(
                                                console: console,
                                                onAction: _send,
                                              )
                                            else
                                              DirectContent(
                                                console: console,
                                                onAction: _send,
                                                onInspect: _openDossier,
                                                textInput: console.textInput,
                                                hiddenRows: tactical
                                                    ? {
                                                        for (
                                                          var row = 11;
                                                          row <= 22;
                                                          row++
                                                        )
                                                          row,
                                                      }
                                                    : const {},
                                                maxColumn: tactical ? 54 : 80,
                                              ),
                                          ],
                                        ),
                                ),
                        ),
                ),
                if (classic && !compact) ...[
                  const SizedBox(width: 22),
                  SizedBox(width: 286, child: _choicePanel()),
                ],
              ],
            ),
          ),
          if (classic && compact) SizedBox(height: 180, child: _choicePanel()),
          if (!planning &&
              !article &&
              !fullMap &&
              (console.textInput || console.actions.isEmpty)) ...[
            const SizedBox(height: 10),
            _inputBar(),
          ],
        ],
      ),
    );
  }

  String _screenHeading(List<String> rows) {
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

  Widget _movementStrip() => Wrap(
    spacing: 8,
    runSpacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      const Padding(
        padding: EdgeInsets.only(right: 10),
        child: Text(
          'Move your squad',
          style: TextStyle(fontWeight: FontWeight.w600),
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
          onPressed:
              fieldPrompt ||
                  (game.siteAlarm &&
                      game.encounter.any((person) => person.isEnemy))
              ? null
              : () => _send(direction),
          icon: Icon(icon, size: 20),
        ),
      SizedBox(
        width: 280,
        height: 36 * _textScale,
        child: Text(
          fieldPrompt
              ? 'Answer the current prompt to continue.'
              : game.siteAlarm && game.encounter.any((person) => person.isEnemy)
              ? 'Resolve the encounter or choose Flee.'
              : 'Click an adjacent tile or use the arrow keys.',
          style: const TextStyle(color: muted, fontSize: 12),
        ),
      ),
    ],
  );

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
            _keycap(a.key == 'Enter' ? '↵' : a.key.toUpperCase()),
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
    final row = console.buffer[action.y].map((c) => c.glyph).join();
    final start = (action.x + action.width).clamp(0, console.width);
    var end = console.width;
    for (final other in console.actions) {
      if (other.y == action.y && other.x > action.x && other.x < end) {
        end = other.x;
      }
    }
    return start < end ? row.substring(start, end).trim() : '';
  }

  Widget _inputBar({bool creation = false}) {
    if (!console.textInput) {
      return Align(
        alignment: Alignment.centerRight,
        child: FilledButton(
          onPressed: () => _send('Enter'),
          child: const Text('Continue'),
        ),
      );
    }
    final field = TextField(
      key: creation ? const ValueKey('creation-public-name') : null,
      focusNode: _entryFocus,
      controller: _entry,
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
      child: Text(creation ? 'Begin campaign' : 'Confirm text'),
    );
    final cancel = TextButton(
      onPressed: _sending ? null : () => _send('Escape'),
      child: Text(creation ? 'Use original name' : 'Cancel'),
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
    return Row(
      children: [
        Expanded(child: field),
        const SizedBox(width: 8),
        submit,
        cancel,
      ],
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
  Widget _keycap(String key) => Container(
    constraints: const BoxConstraints(minWidth: 24),
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
    decoration: BoxDecoration(
      color: ink.withValues(alpha: .055),
      borderRadius: BorderRadius.circular(3),
      border: Border.all(color: ink.withValues(alpha: .12)),
    ),
    child: Text(
      key,
      textAlign: TextAlign.center,
      style: const TextStyle(
        color: muted,
        fontSize: 10,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
  Widget _statusbar() => Container(
    height: 24,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: const BoxDecoration(
      color: JournalPalette.inset,
      border: Border(top: BorderSide(color: line)),
    ),
    child: Row(
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: const BoxDecoration(color: teal, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _navigating
                ? 'Opening section…'
                : title
                ? 'NEW AGE  /  1.5.6'
                : tactical
                ? 'OPERATION IN PROGRESS'
                : hq
                ? 'PLANNING  ·  Time advances only when you end the day'
                : console.navigation?.note ?? 'Choose an action on this screen',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, color: muted),
          ),
        ),
        const Text(
          'F1  FIELD GUIDE',
          style: TextStyle(fontSize: 9, letterSpacing: 1, color: muted),
        ),
      ],
    ),
  );
}
