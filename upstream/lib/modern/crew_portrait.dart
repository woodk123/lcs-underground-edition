import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/gender.dart';
import 'package:lcs_new_age/creature/portrait.dart';
import 'package:lcs_new_age/modern/decision_help.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/skill_help.dart';

const _portraitAsset = 'assets/modern/crew_portraits_v1.png';
const _ink = JournalPalette.ink;
const _teal = JournalPalette.olive;
const _red = JournalPalette.danger;

/// A visual identity, not a simulated appearance or an extra campaign roll.
///
/// IDs survive saves and renames, so the same person keeps the same illustration.
/// The finite illustration bank can be shared by multiple people. Actual age,
/// gender, injuries and other traits are always given by the dossier's text.
int stablePortraitIndex(Creature person) => ensurePortraitId(person);

int _legacyPortraitIndex(Creature person) {
  final choices = switch (person.gender.simplified) {
    Gender.male => const [1, 3, 5, 6, 9, 11, 13, 14],
    Gender.female => const [0, 2, 4, 7, 8, 10, 12, 15],
    _ => const [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
  };
  return choices[(person.id * 13 + 7) % choices.length];
}

final _atlases = <String, Future<ui.Image?>>{};
Future<ui.Image?> _loadAtlas(String asset) => _atlases.putIfAbsent(
  asset,
  () async {
    try {
      final bytes = await rootBundle.load(asset);
      final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } catch (_) {
      return null;
    }
  },
);

/// A compact illustrated crew identity, with a factual availability indicator.
///
/// Adults use a generated editorial illustration bank. Children and nonhuman
/// creatures use initials or an appropriate symbol rather than an adult face.
class CrewPortrait extends StatelessWidget {
  const CrewPortrait({
    super.key,
    required this.person,
    this.size = 64,
    this.borderRadius = 12,
    this.showStatus = true,
  });

  final Creature person;
  final double size;
  final double borderRadius;
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    final journal = Theme.of(context).extension<JournalVisuals>();
    final asset = journal?.portraitAsset ?? _portraitAsset;
    final portraitId = person.human && person.age >= 18
        ? stablePortraitIndex(person)
        : -1;
    final portrait = portraitId >= 0 ? portraitCatalog[portraitId] : null;
    final radius = journal != null && borderRadius == 12 ? 3.0 : borderRadius;
    final status = !person.alive
        ? 'Deceased'
        : !person.isLiberal
        ? 'Not active crew'
        : person.away || person.imprisoned || person.sleeperAgent
        ? 'Away from the active crew'
        : person.blood < person.maxBlood ||
              person.body.parts.any((part) => part.wounded)
        ? 'Injured'
        : 'Available';
    final color = status == 'Deceased' || status == 'Injured'
        ? _red
        : status == 'Not active crew'
        ? JournalPalette.muted
        : status == 'Away from the active crew'
        ? const Color(0xFFA67635)
        : _teal;
    return Semantics(
      image: true,
      label: '${person.name} portrait. $status.',
      child: MechanicsTooltip(
        excludeFromSemantics: true,
        message: crewAvailabilityHelp(
          person,
        ).split('\n\n').take(3).join('\n\n'),
        child: ExcludeSemantics(
          child: SizedBox.square(
            dimension: size,
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: _ink,
                    borderRadius: BorderRadius.circular(radius),
                    border: Border.all(color: const Color(0xFFD6D7CB)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      (radius - 1).clamp(0, radius),
                    ),
                    child: person.human && person.age >= 18
                        ? FutureBuilder<ui.Image?>(
                            key: ValueKey(portrait!.asset),
                            future: _loadAtlas(portrait.asset),
                            builder: (context, snapshot) =>
                                snapshot.connectionState != ConnectionState.done
                                ? _fallback()
                                : snapshot.data == null
                                ? FutureBuilder<ui.Image?>(
                                    future: _loadAtlas(asset),
                                    builder: (context, legacy) =>
                                        legacy.data == null
                                        ? _fallback()
                                        : CustomPaint(
                                            painter: _PortraitPainter(
                                              legacy.data!,
                                              _legacyPortraitIndex(person),
                                            ),
                                          ),
                                  )
                                : CustomPaint(
                                    painter: _PortraitPainter(
                                      snapshot.data!,
                                      portrait.cell,
                                    ),
                                  ),
                          )
                        : _fallback(),
                  ),
                ),
                if (showStatus)
                  Positioned(
                    right: 3,
                    bottom: 3,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: JournalPalette.card,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fallback() {
    if (!person.human) {
      return Icon(
        person.type.tank ? Icons.precision_manufacturing : Icons.pets,
        size: size * .46,
        color: const Color(0xFFE4E0D1),
      );
    }
    final words = person.name.trim().split(RegExp(r'\s+'));
    final initials = words
        .where((word) => word.isNotEmpty)
        .take(2)
        .map((word) => word.characters.first.toUpperCase())
        .join();
    return Center(
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: TextStyle(
          fontFamily: 'ModernSans',
          fontSize: size * .32,
          fontWeight: FontWeight.w700,
          color: const Color(0xFFE4E0D1),
        ),
      ),
    );
  }
}

class _PortraitPainter extends CustomPainter {
  const _PortraitPainter(this.image, this.index);

  final ui.Image image;
  final int index;

  @override
  void paint(Canvas canvas, Size size) {
    final width = image.width / 4;
    final height = image.height / 4;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(index % 4 * width, index ~/ 4 * height, width, height),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_PortraitPainter oldDelegate) =>
      oldDelegate.image != image || oldDelegate.index != index;
}
