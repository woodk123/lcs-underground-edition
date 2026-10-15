import 'package:flutter/material.dart';
import 'package:lcs_new_age/creature/attributes.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/creation_context.dart';
import 'package:lcs_new_age/modern/attribute_help.dart';
import 'package:lcs_new_age/modern/crew_portrait.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/skill_help.dart';

/// The original campaign/founder readers presented as an open journal.
/// Selections dispatch one existing key. Reading the dossier never dispatches,
/// rolls, constructs a new person, trains or modifies the founder.
class JournalCreationPage extends StatefulWidget {
  const JournalCreationPage({
    super.key,
    required this.console,
    required this.context,
    required this.onAction,
    required this.inputBar,
    this.onHelp,
    this.readingControl,
  });

  final Console console;
  final CreationContext context;
  final ValueChanged<String> onAction;
  final Widget inputBar;
  final VoidCallback? onHelp;
  final Widget? readingControl;

  @override
  State<JournalCreationPage> createState() => _JournalCreationPageState();
}

class _JournalCreationPageState extends State<JournalCreationPage> {
  final _mainScroll = ScrollController();
  final _dossierScroll = ScrollController();
  int? _sentRevision;

  @override
  void didUpdateWidget(JournalCreationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.console, widget.console)) _sentRevision = null;
    if (oldWidget.context.stage != widget.context.stage ||
        oldWidget.context.step != widget.context.step) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _mainScroll.hasClients) _mainScroll.jumpTo(0);
      });
    }
  }

  @override
  void dispose() {
    _mainScroll.dispose();
    _dossierScroll.dispose();
    super.dispose();
  }

  ConsoleAction? _action(String key) {
    final normalized = normalizeConsoleKey(key);
    return widget.console.actions
        .where((action) => action.key == key || action.key == normalized)
        .firstOrNull;
  }

  VoidCallback? _dispatch(
    String key,
    int revision,
    CreationContext creation, {
    bool acknowledge = false,
  }) {
    final console = widget.console;
    final action = _action(key);
    final emptyAcknowledgement = acknowledge && console.actions.isEmpty;
    if (!console.awaitingInput ||
        !identical(console.creation, creation) ||
        _sentRevision == revision ||
        action?.enabled == false ||
        action == null && !emptyAcknowledgement) {
      return null;
    }
    return () {
      if (!mounted ||
          console.revision.value != revision ||
          !identical(console.creation, creation) ||
          !console.awaitingInput ||
          _sentRevision == revision ||
          (console.nextKeyEvent?.isCompleted ?? false)) {
        return;
      }
      if (action != null) {
        if (!console.actions.contains(action) ||
            !action.enabled ||
            !identical(_action(key), action)) {
          return;
        }
      } else if (!emptyAcknowledgement || console.actions.isNotEmpty) {
        return;
      }
      _sentRevision = revision;
      widget.onAction(action?.key ?? 'Enter');
    };
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: buildJournalTheme(),
    child: AnimatedBuilder(
      animation: widget.console.revision,
      builder: (context, _) => LayoutBuilder(
        builder: (context, bounds) {
          final creation = widget.context;
          final revision = widget.console.revision.value;
          final narrow = bounds.maxWidth < 1000;
          final margin = narrow ? 10.0 : 18.0;
          final dossierWidth = narrow ? 246.0 : 330.0;
          final footerChoices = creation.choices
              .where((choice) => normalizeConsoleKey(choice.key) == 'Enter')
              .toList();
          final answers = creation.choices
              .where((choice) => normalizeConsoleKey(choice.key) != 'Enter')
              .toList();
          return DecoratedBox(
            key: const ValueKey('journal-creation-page'),
            decoration: const BoxDecoration(
              color: JournalPalette.leather,
              image: DecorationImage(
                image: AssetImage(JournalPalette.leatherAsset),
                fit: BoxFit.cover,
                opacity: .7,
              ),
            ),
            child: Padding(
              padding: EdgeInsets.all(margin),
              child: DefaultTextStyle.merge(
                style: JournalPalette.body,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _masthead(creation, narrow),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _mainPage(
                              creation,
                              answers,
                              revision,
                              narrow,
                            ),
                          ),
                          JournalBinding(width: narrow ? 22 : 30),
                          SizedBox(
                            width: dossierWidth,
                            child: creation.founder == null
                                ? _chapterNotes(creation)
                                : _founderDossier(creation, creation.founder!),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    _footer(creation, footerChoices, revision),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );

  Widget _masthead(CreationContext creation, bool narrow) => JournalSurface(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    child: Row(
      children: [
        JournalIllustratedIcon(
          icon: _icon(creation.stage),
          size: narrow ? 40 : 50,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'THE MOVEMENT · ${_chapter(creation.stage).toUpperCase()}',
                style: JournalPalette.small.copyWith(
                  fontSize: 10,
                  letterSpacing: 1,
                ),
              ),
              Semantics(
                header: true,
                child: Text(
                  creation.title,
                  key: const ValueKey('creation-title'),
                  style: JournalPalette.title.copyWith(
                    fontSize: narrow ? 20 : 25,
                  ),
                ),
              ),
              if (creation.subtitle.isNotEmpty)
                Text(creation.subtitle, style: JournalPalette.small),
            ],
          ),
        ),
        if (creation.step != null && creation.totalSteps != null) ...[
          const SizedBox(width: 8),
          Text(
            '${creation.step} / ${creation.totalSteps}',
            key: const ValueKey('creation-step'),
            style: JournalPalette.heading,
          ),
        ],
      ],
    ),
  );

  Widget _mainPage(
    CreationContext creation,
    List<CreationChoice> answers,
    int revision,
    bool narrow,
  ) => JournalSurface(
    padding: EdgeInsets.all(narrow ? 12 : 18),
    child: Scrollbar(
      controller: _mainScroll,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _mainScroll,
        key: const ValueKey('creation-main-scroll'),
        primary: false,
        padding: const EdgeInsets.only(right: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (creation.prompt.isNotEmpty) ...[
              Text(
                creation.prompt,
                key: const ValueKey('creation-prompt'),
                style: JournalPalette.heading.copyWith(fontSize: 19),
              ),
              const SizedBox(height: 13),
            ],
            for (final paragraph in creation.body) ...[
              Text(paragraph, style: JournalPalette.body),
              const SizedBox(height: 14),
            ],
            for (final field in creation.fields) ...[
              _field(field, creation, revision),
              const SizedBox(height: 10),
            ],
            if (answers.isNotEmpty) ...[
              const Divider(height: 8),
              Text(
                creation.stage == CreationStage.background
                    ? 'Choose the next part of your history.'
                    : 'Choose an option.',
                style: JournalPalette.small,
              ),
              const SizedBox(height: 10),
              for (final answer in answers) ...[
                _answer(answer, creation, revision),
                const SizedBox(height: 9),
              ],
            ],
            if (creation.stage == CreationStage.name && creation.body.isEmpty)
              const Text(
                'Choose the name your movement will know you by.',
                style: JournalPalette.body,
              ),
          ],
        ),
      ),
    ),
  );

  Widget _field(CreationField field, CreationContext creation, int revision) {
    final activate = _dispatch(field.key, revision, creation);
    final generatedName =
        creation.stage == CreationStage.identity &&
        const {'a', 'b'}.contains(normalizeConsoleKey(field.key));
    return OutlinedButton(
      key: ValueKey('creation-field:${field.key}'),
      onPressed: activate,
      style: OutlinedButton.styleFrom(
        backgroundColor: JournalPalette.card,
        padding: const EdgeInsets.all(12),
        alignment: Alignment.centerLeft,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(field.label, style: JournalPalette.small),
                const SizedBox(height: 4),
                Text(
                  field.value,
                  style: JournalPalette.heading.copyWith(fontSize: 16),
                ),
                if (field.description.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(field.description, style: JournalPalette.small),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            generatedName ? Icons.refresh : Icons.sync,
            size: 19,
            color: JournalPalette.brassDark,
          ),
        ],
      ),
    );
  }

  Widget _answer(
    CreationChoice answer,
    CreationContext creation,
    int revision,
  ) => OutlinedButton(
    key: ValueKey('creation-choice:${answer.key}'),
    onPressed: _dispatch(answer.key, revision, creation),
    style: OutlinedButton.styleFrom(
      backgroundColor: JournalPalette.card,
      padding: const EdgeInsets.all(12),
      alignment: Alignment.centerLeft,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: JournalPalette.inset,
            border: Border.all(color: JournalPalette.rule),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Text(answer.key.toUpperCase(), style: JournalPalette.small),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                answer.label,
                style: JournalPalette.body.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (answer.description.isNotEmpty) ...[
                const SizedBox(height: 7),
                Text(
                  'Effects: ${answer.description}',
                  style: JournalPalette.small.copyWith(
                    color: JournalPalette.olive,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );

  Widget _chapterNotes(CreationContext creation) => JournalSurface(
    lined: true,
    child: SingleChildScrollView(
      primary: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('A movement begins', style: JournalPalette.heading),
          const SizedBox(height: 18),
          const Center(
            child: JournalIllustratedIcon(icon: JournalIcon.crew, size: 128),
          ),
          const SizedBox(height: 20),
          Text(
            creation.stage == CreationStage.setup
                ? 'Set the country’s starting climate, its rival movement and '
                      'the rhythm of combat on the facing page.'
                : 'Set your founder’s identity on the facing page. The founder’s '
                      'dossier appears after you continue.',
            style: JournalPalette.body,
          ),
          const SizedBox(height: 18),
          const Divider(),
          for (final stage in CreationStage.values)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  JournalIllustratedIcon(icon: _icon(stage), size: 27),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      _chapter(stage),
                      style: JournalPalette.small.copyWith(
                        color: stage == creation.stage
                            ? JournalPalette.binding
                            : JournalPalette.muted,
                        fontWeight: stage == creation.stage
                            ? FontWeight.w700
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );

  Widget _founderDossier(CreationContext creation, Creature founder) {
    final skills = Skill.values.toList()
      ..sort((a, b) {
        final level = founder.skill(b).compareTo(founder.skill(a));
        return level == 0 ? a.displayName.compareTo(b.displayName) : level;
      });
    final showAge =
        creation.stage != CreationStage.background || (creation.step ?? 1) > 1;
    return JournalSurface(
      key: const ValueKey('creation-founder-dossier'),
      lined: true,
      padding: const EdgeInsets.all(12),
      child: Scrollbar(
        controller: _dossierScroll,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _dossierScroll,
          primary: false,
          key: const ValueKey('creation-dossier-scroll'),
          padding: const EdgeInsets.only(right: 7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Founder dossier', style: JournalPalette.heading),
              const SizedBox(height: 11),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CrewPortrait(person: founder, size: 52, showStatus: false),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          founder.name.isEmpty ? 'Your founder' : founder.name,
                          key: const ValueKey('creation-founder-name'),
                          style: JournalPalette.heading.copyWith(fontSize: 14),
                        ),
                        if (showAge)
                          Text(
                            'Age ${founder.age}',
                            key: const ValueKey('creation-founder-age'),
                            style: JournalPalette.small,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text('Attributes', style: JournalPalette.heading),
              const Text(
                'Hover an attribute for its uses and calculations.',
                style: JournalPalette.small,
              ),
              const Divider(height: 12),
              for (final attribute in Attribute.values)
                AttributeTooltip(
                  attribute: attribute,
                  actor: founder,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _capitalized(attribute.name),
                            style: JournalPalette.small,
                          ),
                        ),
                        Text(
                          '${founder.attribute(attribute)}',
                          key: ValueKey('creation-attribute:${attribute.name}'),
                          style: JournalPalette.body.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              const Text('Skills', style: JournalPalette.heading),
              const Text(
                'Hover a skill for its uses and calculations.',
                style: JournalPalette.small,
              ),
              const Divider(height: 12),
              for (final skill in skills)
                SkillTooltip(
                  key: ValueKey('creation-skill:${skill.name}'),
                  skill: skill,
                  actor: founder,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            skill.displayName,
                            style: JournalPalette.small,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${founder.skill(skill)}',
                          style: JournalPalette.body.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _footer(
    CreationContext creation,
    List<CreationChoice> continues,
    int revision,
  ) => JournalSurface(
    key: const ValueKey('creation-footer'),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: creation.stage == CreationStage.name
        ? KeyedSubtree(
            key: const ValueKey('creation-name-input'),
            child: widget.inputBar,
          )
        : Row(
            children: [
              if (widget.onHelp != null)
                IconButton(
                  tooltip: 'Field guide',
                  onPressed: widget.onHelp,
                  icon: const Icon(Icons.menu_book_outlined, size: 20),
                ),
              if (widget.readingControl != null) widget.readingControl!,
              Expanded(
                child: Text(_footerNote(creation), style: JournalPalette.small),
              ),
              if (continues.isNotEmpty)
                FilledButton.icon(
                  key: const ValueKey('creation-continue'),
                  onPressed: _dispatch(continues.first.key, revision, creation),
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  label: Text(continues.first.label),
                )
              else if (creation.choices.isEmpty)
                FilledButton.icon(
                  key: const ValueKey('creation-continue'),
                  onPressed: _dispatch(
                    'Enter',
                    revision,
                    creation,
                    acknowledge: true,
                  ),
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  label: const Text('Continue'),
                ),
            ],
          ),
  );

  String _footerNote(CreationContext creation) => switch (creation.stage) {
    CreationStage.setup => 'Click a setting to cycle its choices.',
    CreationStage.identity =>
      'Generated names here · Public name on the final page.',
    CreationStage.background =>
      creation.choices.isEmpty
          ? 'Acknowledge this chapter to continue.'
          : 'Each answer becomes part of your history.',
    CreationStage.briefing => 'Your movement’s story begins here.',
    CreationStage.name => '',
  };

  JournalIcon _icon(CreationStage stage) => switch (stage) {
    CreationStage.setup => JournalIcon.options,
    CreationStage.identity => JournalIcon.crew,
    CreationStage.background => JournalIcon.personnel,
    CreationStage.briefing => JournalIcon.newspaper,
    CreationStage.name => JournalIcon.reports,
  };

  String _chapter(CreationStage stage) => switch (stage) {
    CreationStage.setup => 'Campaign',
    CreationStage.identity => 'Identity',
    CreationStage.background => 'Background',
    CreationStage.briefing => 'The beginning',
    CreationStage.name => 'Your public name',
  };

  String _capitalized(String text) =>
      '${text[0].toUpperCase()}${text.substring(1)}';
}
