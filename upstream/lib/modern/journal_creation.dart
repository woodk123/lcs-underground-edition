import 'package:flutter/material.dart';
import 'package:lcs_new_age/creature/attributes.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/engine/creation_context.dart';
import 'package:lcs_new_age/modern/age_help.dart';
import 'package:lcs_new_age/modern/attribute_help.dart';
import 'package:lcs_new_age/modern/creation_bonus_help.dart';
import 'package:lcs_new_age/modern/crew_portrait.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/skill_help.dart';

const _effectAttributes = {
  'Strength': Attribute.strength,
  'Agility': Attribute.agility,
  'Intelligence': Attribute.intelligence,
  'Int': Attribute.intelligence,
  'Charisma': Attribute.charisma,
  'Wisdom': Attribute.wisdom,
  'Heart': Attribute.heart,
};
final _effectSkills = {
  for (final skill in Skill.values) skill.displayName: skill,
};
final _effectNames = [..._effectAttributes.keys, ..._effectSkills.keys]
  ..sort((a, b) => b.length.compareTo(a.length));
final _effectPattern = RegExp(
  r'(?:[-+−]\d+\s+)?\b(' + _effectNames.map(RegExp.escape).join('|') + r')\b',
);
final _effectClausePattern = RegExp(r'[-+−]\d+\s+[^,]+');

/// The original campaign/founder readers presented as an open journal.
/// Selections dispatch one existing key. Reading the dossier never dispatches,
/// rolls, constructs a new person or trains the founder. Portrait choices are
/// dispatched to the identity reader as explicit cosmetic actions.
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
                                ? creation.portraitId != null
                                      ? _portraitChooser(creation, revision)
                                      : _chapterNotes(creation)
                                : _founderDossier(creation, creation.founder!),
                          ),
                        ],
                      ),
                    ),
                    if (creation.stage != CreationStage.name) ...[
                      const SizedBox(height: 8),
                      _footer(creation, footerChoices, revision),
                    ],
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
        if (creation.stage == CreationStage.name) ...[
          if (widget.readingControl != null) widget.readingControl!,
          if (widget.onHelp != null)
            IconButton(
              tooltip: 'Field guide',
              onPressed: widget.onHelp,
              icon: const Icon(Icons.menu_book_outlined, size: 20),
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
            if (creation.stage == CreationStage.name)
              KeyedSubtree(
                key: const ValueKey('creation-name-input'),
                child: widget.inputBar,
              ),
            for (var index = 0; index < creation.body.length; index++) ...[
              if (creation.stage == CreationStage.background && index == 1)
                _effects(
                  creation.body[index],
                  key: 'fate',
                  actor: creation.founder,
                  bonuses: creation.pendingBonuses,
                  style: JournalPalette.body,
                )
              else
                Text(creation.body[index], style: JournalPalette.body),
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
                _effects(
                  answer.description,
                  key: answer.key,
                  prefix: 'Effects: ',
                  actor: creation.founder,
                  bonuses: answer.bonuses,
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );

  /// Match display labels only to attach passive help. The source reader still
  /// owns every effect and choice; no bonus is calculated or applied here.
  Widget _effects(
    String description, {
    required String key,
    Creature? actor,
    CreationBonuses? bonuses,
    String prefix = '',
    TextStyle? style,
  }) {
    final textStyle =
        style ?? JournalPalette.small.copyWith(color: JournalPalette.olive);
    final spans = <InlineSpan>[TextSpan(text: prefix)];
    final preview = actor != null && bonuses != null
        ? CreationBonusPreview(actor, bonuses)
        : null;
    var offset = 0;
    for (final clause in _effectClausePattern.allMatches(description)) {
      for (final match in _effectPattern.allMatches(clause.group(0)!)) {
        final start = clause.start + match.start;
        spans.add(TextSpan(text: description.substring(offset, start)));
        final name = match.group(1)!;
        final text = Text(
          match.group(0)!,
          style: textStyle.copyWith(
            decoration: TextDecoration.underline,
            decorationStyle: TextDecorationStyle.dotted,
          ),
        );
        final skill = _effectSkills[name];
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: preview != null
                ? MechanicsTooltip(
                    message: skill != null
                        ? preview.skill(skill)
                        : preview.attribute(_effectAttributes[name]!),
                    child: text,
                  )
                : skill != null
                ? SkillTooltip(skill: skill, actor: actor, child: text)
                : AttributeTooltip(
                    attribute: _effectAttributes[name]!,
                    actor: actor,
                    child: text,
                  ),
          ),
        );
        offset = clause.start + match.end;
      }
    }
    spans.add(TextSpan(text: description.substring(offset)));
    return Semantics(
      key: ValueKey('creation-effects:$key'),
      label: '$prefix$description',
      excludeSemantics: true,
      // WidgetSpan scales its entire child automatically. Scale the surrounding
      // paragraph explicitly instead, leaving the text and popup to each apply
      // the reading preference once, without transforming the tooltip overlay.
      child: Text.rich(
        TextSpan(children: spans),
        textScaler: TextScaler.noScaling,
        style: textStyle.copyWith(
          fontSize: MediaQuery.textScalerOf(context).scale(textStyle.fontSize!),
        ),
      ),
    );
  }

  Widget _portraitChooser(CreationContext creation, int revision) =>
      JournalSurface(
        child: SingleChildScrollView(
          primary: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Founder portrait', style: JournalPalette.heading),
              const SizedBox(height: 18),
              Center(
                child: FounderPortraitPreview(
                  key: const ValueKey('creation-portrait-preview'),
                  portraitId: creation.portraitId!,
                ),
              ),
              const SizedBox(height: 14),
              if (creation.portraitRerollKey case final key?)
                OutlinedButton.icon(
                  key: const ValueKey('creation-reroll-portrait'),
                  onPressed: _dispatch(key, revision, creation),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Reroll portrait'),
                ),
            ],
          ),
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
              const Divider(height: 12),
              if (showAge) ...[
                AgeEffects(person: founder),
                const SizedBox(height: 12),
              ],
              _statTable([
                for (final attribute in Attribute.values)
                  AttributeTooltip(
                    attribute: attribute,
                    actor: founder,
                    child: _statEntry(
                      _capitalized(attribute.name),
                      founder.attribute(attribute),
                      valueKey: ValueKey(
                        'creation-attribute:${attribute.name}',
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 14),
              const Text('Skills', style: JournalPalette.heading),
              const Divider(height: 12),
              _statTable([
                for (final skill in skills)
                  SkillTooltip(
                    key: ValueKey('creation-skill:${skill.name}'),
                    skill: skill,
                    actor: founder,
                    child: _statEntry(skill.displayName, founder.skill(skill)),
                  ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statTable(List<Widget> entries) => LayoutBuilder(
    builder: (context, bounds) {
      final columns =
          bounds.maxWidth / MediaQuery.textScalerOf(context).scale(1) >= 260
          ? 2
          : 1;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < entries.length; index += columns)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: entries[index]),
                  if (columns == 2) ...[
                    const SizedBox(width: 14),
                    Expanded(
                      child: index + 1 < entries.length
                          ? entries[index + 1]
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
        ],
      );
    },
  );

  Widget _statEntry(String label, int value, {Key? valueKey}) => Semantics(
    label: '$label: $value',
    excludeSemantics: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(child: Text(label, style: JournalPalette.small)),
        const SizedBox(width: 6),
        Text(
          '$value',
          key: valueKey,
          style: JournalPalette.small.copyWith(
            color: JournalPalette.ink,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );

  Widget _footer(
    CreationContext creation,
    List<CreationChoice> continues,
    int revision,
  ) => JournalSurface(
    key: const ValueKey('creation-footer'),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: Row(
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
