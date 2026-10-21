import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/modern/decision_help.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/legal_penalties.dart';

class LegalStatusSummary extends StatelessWidget {
  const LegalStatusSummary({super.key, required this.person});
  final Creature person;

  @override
  Widget build(BuildContext context) {
    final charges = person.wantedForCrimes.entries.where((e) => e.value > 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          charges.isEmpty
              ? 'No current wanted charges'
              : 'Wanted for: ${charges.map((e) => '${e.key.wantedFor} ×${e.value}').join(' · ')}',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: charges.isEmpty ? JournalPalette.ink : JournalPalette.danger,
          ),
        ),
        Text('Personal heat: ${person.heat}'),
        LegalStatusExplanation(person: person),
        DecisionGuideButton(topic: DecisionTopic.heat, actor: person),
      ],
    );
  }
}

class LegalStatusExplanation extends StatelessWidget {
  const LegalStatusExplanation({super.key, required this.person});
  final Creature person;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        person.isCriminal
            ? '${person.heat == 0 ? 'Zero heat does not clear these offences. ' : ''}'
                  'If arrested, these offences become court charges. More serious '
                  'offences and repeated counts strengthen the prosecution’s case '
                  'and can increase prison time if convicted. '
                  'Heat measures police attention, not guilt or an arrest percentage.'
            : 'Heat measures police attention, not an arrest percentage. '
                  'Wanted offences and past convictions are separate records.',
        style: const TextStyle(fontSize: 11, color: JournalPalette.muted),
      ),
      if (person.isCriminal) PossiblePenaltiesTooltip(person: person),
    ],
  );
}

class PossiblePenaltiesTooltip extends StatefulWidget {
  const PossiblePenaltiesTooltip({super.key, required this.person});
  final Creature person;

  @override
  State<PossiblePenaltiesTooltip> createState() =>
      _PossiblePenaltiesTooltipState();
}

class _PossiblePenaltiesTooltipState extends State<PossiblePenaltiesTooltip> {
  final _tooltip = GlobalKey<TooltipState>();
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final message = possiblePenalties(widget.person);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape &&
            Tooltip.dismissAllToolTips()) {
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      // WidgetSpan is scaled by Text.rich itself. Scale the content explicitly
      // so its scroll viewport still uses the actual window dimensions.
      child: MediaQuery(
        data: media.copyWith(textScaler: TextScaler.noScaling),
        child: Tooltip(
          key: _tooltip,
          triggerMode: TooltipTriggerMode.manual,
          waitDuration: const Duration(milliseconds: 300),
          showDuration: const Duration(seconds: 30),
          enableTapToDismiss: false,
          decoration: BoxDecoration(
            color: const Color(0xff30342b),
            borderRadius: BorderRadius.circular(6),
          ),
          excludeFromSemantics: true,
          positionDelegate: (position) => Offset(
            (position.target.dx - position.tooltipSize.width / 2)
                .clamp(
                  12,
                  math.max(
                    12,
                    position.overlaySize.width -
                        position.tooltipSize.width -
                        12,
                  ),
                )
                .toDouble(),
            (position.target.dy +
                            position.verticalOffset +
                            position.tooltipSize.height <=
                        position.overlaySize.height - 12
                    ? position.target.dy + position.verticalOffset
                    : position.target.dy -
                          position.verticalOffset -
                          position.tooltipSize.height)
                .clamp(
                  12,
                  math.max(
                    12,
                    position.overlaySize.height -
                        position.tooltipSize.height -
                        12,
                  ),
                )
                .toDouble(),
          ),
          richMessage: WidgetSpan(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: math.min(440, math.max(1, size.width - 48)),
                maxHeight: size.height * .55,
              ),
              child: SingleChildScrollView(
                key: const ValueKey('possible-penalties-scroll'),
                child: Text(
                  message,
                  textScaler: media.textScaler,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ),
          ),
          child: MediaQuery(
            data: media,
            child: Semantics(
              tooltip: message,
              child: TextButton.icon(
                focusNode: _focus,
                onPressed: () {
                  _focus.requestFocus();
                  if (!(_tooltip.currentState?.ensureTooltipVisible() ??
                      false)) {
                    Tooltip.dismissAllToolTips();
                  }
                },
                icon: const Icon(Icons.info_outline, size: 16),
                label: const Text('Possible penalties'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
