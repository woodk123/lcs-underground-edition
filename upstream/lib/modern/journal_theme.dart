import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Reading preference shared by journal pages and app-level overlays.
final journalReadingScale = ValueNotifier<double>(1);

/// Material colours observed in the original Gangsters organiser, with new
/// artwork and contrast chosen for live, scalable Flutter text.
abstract final class JournalPalette {
  static const desk = Color(0xFF29251D);
  static const leather = Color(0xFF4A241E);
  static const page = Color(0xFFE9E6CD);
  static const card = Color(0xFFF4EFDB);
  static const inset = Color(0xFFE1DFC4);
  static const ink = Color(0xFF25291F);
  static const muted = Color(0xFF585E47);
  static const rule = Color(0xFFA1A184);
  static const brass = Color(0xFFA29156);
  static const brassLight = Color(0xFFE1D5A7);
  static const brassDark = Color(0xFF625431);
  static const binding = Color(0xFF8C3829);
  static const olive = Color(0xFF455D35);
  static const selected = Color(0xFFF2DFA2);
  static const danger = Color(0xFF9B312D);
  static const paperAsset = 'assets/modern/journal_paper_v1.webp';
  static const leatherAsset = 'assets/modern/journal_leather_v1.webp';
  static const serif = 'JournalSerif';

  static const title = TextStyle(
    fontFamily: serif,
    fontFamilyFallback: ['ModernSans'],
    fontSize: 23,
    fontWeight: FontWeight.w700,
    height: 1.2,
    color: ink,
  );
  static const heading = TextStyle(
    fontFamily: serif,
    fontFamilyFallback: ['ModernSans'],
    fontSize: 17,
    fontWeight: FontWeight.w700,
    height: 1.3,
    color: ink,
  );
  static const body = TextStyle(
    fontFamily: serif,
    fontFamilyFallback: ['ModernSans'],
    fontSize: 14,
    height: 1.45,
    color: ink,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  static const small = TextStyle(
    fontFamily: serif,
    fontFamilyFallback: ['ModernSans'],
    fontSize: 12,
    height: 1.4,
    color: muted,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

/// Cosmetic art selection only; it never selects or changes a campaign person.
@immutable
class JournalVisuals extends ThemeExtension<JournalVisuals> {
  const JournalVisuals({
    this.portraitAsset = 'assets/modern/journal_portraits_v1.webp',
    this.iconAsset = 'assets/modern/journal_icons_v1.webp',
    this.crewAsset = 'assets/modern/activist_crew_v1.webp',
  });
  final String portraitAsset;
  final String iconAsset;
  final String crewAsset;

  @override
  JournalVisuals copyWith({
    String? portraitAsset,
    String? iconAsset,
    String? crewAsset,
  }) => JournalVisuals(
    portraitAsset: portraitAsset ?? this.portraitAsset,
    iconAsset: iconAsset ?? this.iconAsset,
    crewAsset: crewAsset ?? this.crewAsset,
  );

  @override
  JournalVisuals lerp(covariant JournalVisuals? other, double t) =>
      other == null || t < .5 ? this : other;
}

enum JournalIcon {
  crew,
  accounts,
  law,
  diplomacy,
  newspaper,
  reports,
  city,
  options,
  business,
  personnel,
  activism,
  operations,
  network,
  people,
  bases,
  stores,
  leadership,
  captives,
  media,
}

/// Original pictorial art, ordered like the original organiser's eight tabs and
/// four order groups. Rectangles include each full illustration and a quiet
/// transparent margin; equal-quarter cuts would clip several of the paintings.
const journalIconSourceRects = <Rect>[
  Rect.fromLTWH(22, 69, 355, 297),
  Rect.fromLTWH(387, 95, 345, 254),
  Rect.fromLTWH(749, 50, 335, 323),
  Rect.fromLTWH(1104, 98, 326, 204),
  Rect.fromLTWH(24, 409, 351, 275),
  Rect.fromLTWH(411, 399, 295, 271),
  Rect.fromLTWH(736, 399, 363, 287),
  Rect.fromLTWH(1106, 409, 308, 288),
  Rect.fromLTWH(27, 741, 332, 272),
  Rect.fromLTWH(376, 717, 355, 316),
  Rect.fromLTWH(750, 696, 337, 333),
  Rect.fromLTWH(1089, 746, 342, 288),
];

final _iconAtlases = <String, Future<ui.Image?>>{};

Future<ui.Image?> _loadIconAtlas(String asset) => _iconAtlases.putIfAbsent(
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

/// Decorative illustration inside a labelled live control. It deliberately
/// contributes no extra focus stop, event handler, tooltip, or spoken label.
class JournalIllustratedIcon extends StatelessWidget {
  const JournalIllustratedIcon({super.key, required this.icon, this.size = 48});
  final JournalIcon icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final visuals =
        Theme.of(context).extension<JournalVisuals>() ?? const JournalVisuals();
    final isCrew = icon == JournalIcon.crew || icon == JournalIcon.personnel;
    final isNetwork = icon == JournalIcon.network;
    final isOperations = icon.index >= JournalIcon.people.index;
    final asset = isOperations
        ? 'assets/modern/journal_operations_icons_v1.webp'
        : isNetwork
        ? 'assets/modern/journal_network_emblem_v1.webp'
        : isCrew
        ? visuals.crewAsset
        : visuals.iconAsset;
    return ExcludeSemantics(
      child: IgnorePointer(
        child: SizedBox.square(
          dimension: size,
          child: FutureBuilder<ui.Image?>(
            future: _loadIconAtlas(asset),
            builder: (context, snapshot) => snapshot.data == null
                ? Icon(_fallbackIcon(icon), color: JournalPalette.brassDark)
                : CustomPaint(
                    painter: _JournalIconPainter(
                      snapshot.data!,
                      isOperations
                          ? Rect.fromLTWH(
                              ((icon.index - JournalIcon.people.index) % 3) *
                                  snapshot.data!.width /
                                  3,
                              ((icon.index - JournalIcon.people.index) ~/ 3) *
                                  snapshot.data!.height /
                                  2,
                              snapshot.data!.width / 3,
                              snapshot.data!.height / 2,
                            )
                          : isCrew || isNetwork
                          ? Rect.fromLTWH(
                              0,
                              0,
                              snapshot.data!.width.toDouble(),
                              snapshot.data!.height.toDouble(),
                            )
                          : journalIconSourceRects[icon.index],
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  IconData _fallbackIcon(JournalIcon icon) => switch (icon) {
    JournalIcon.crew || JournalIcon.personnel => Icons.groups,
    JournalIcon.network => Icons.visibility_outlined,
    JournalIcon.people => Icons.groups_outlined,
    JournalIcon.bases => Icons.home_work_outlined,
    JournalIcon.stores => Icons.inventory_2_outlined,
    JournalIcon.leadership => Icons.account_tree_outlined,
    JournalIcon.captives => Icons.lock_outline,
    JournalIcon.media => Icons.newspaper_outlined,
    JournalIcon.accounts => Icons.account_balance_wallet_outlined,
    JournalIcon.law => Icons.balance,
    JournalIcon.diplomacy => Icons.handshake_outlined,
    JournalIcon.newspaper => Icons.newspaper,
    JournalIcon.reports => Icons.insights,
    JournalIcon.city => Icons.map_outlined,
    JournalIcon.options => Icons.settings_outlined,
    JournalIcon.business => Icons.paid_outlined,
    JournalIcon.activism => Icons.campaign_outlined,
    JournalIcon.operations => Icons.explore_outlined,
  };
}

class _JournalIconPainter extends CustomPainter {
  const _JournalIconPainter(this.image, this.source);
  final ui.Image image;
  final Rect source;

  @override
  void paint(Canvas canvas, Size size) {
    final fitted = applyBoxFit(BoxFit.contain, source.size, size);
    final destination = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );
    canvas.drawImageRect(
      image,
      source,
      destination,
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(covariant _JournalIconPainter oldDelegate) =>
      oldDelegate.image != image || oldDelegate.source != source;
}

ThemeData buildJournalTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: JournalPalette.olive,
    primary: JournalPalette.olive,
    onPrimary: JournalPalette.card,
    secondary: JournalPalette.brassDark,
    onSecondary: JournalPalette.card,
    tertiary: JournalPalette.binding,
    onTertiary: JournalPalette.card,
    surface: JournalPalette.page,
    onSurface: JournalPalette.ink,
    error: JournalPalette.danger,
    outline: JournalPalette.rule,
  );
  return ThemeData(
    useMaterial3: true,
    fontFamily: JournalPalette.serif,
    fontFamilyFallback: const ['ModernSans'],
    extensions: const [JournalVisuals()],
    colorScheme: scheme,
    scaffoldBackgroundColor: JournalPalette.desk,
    canvasColor: JournalPalette.page,
    dividerColor: JournalPalette.rule,
    disabledColor: JournalPalette.muted,
    textTheme: const TextTheme(
      headlineLarge: JournalPalette.title,
      headlineMedium: JournalPalette.title,
      titleLarge: JournalPalette.heading,
      titleMedium: JournalPalette.heading,
      titleSmall: JournalPalette.body,
      bodyLarge: JournalPalette.body,
      bodyMedium: JournalPalette.body,
      bodySmall: JournalPalette.small,
      labelLarge: TextStyle(
        fontFamily: JournalPalette.serif,
        fontFamilyFallback: ['ModernSans'],
        fontSize: 13,
        fontWeight: FontWeight.w700,
        height: 1.3,
        color: JournalPalette.ink,
      ),
      labelMedium: JournalPalette.small,
      labelSmall: JournalPalette.small,
    ),
    visualDensity: VisualDensity.standard,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 42),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        textStyle: JournalPalette.body.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 42),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        foregroundColor: JournalPalette.ink,
        backgroundColor: JournalPalette.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        side: const BorderSide(color: JournalPalette.brassDark),
        textStyle: JournalPalette.body.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 40),
        foregroundColor: JournalPalette.olive,
        textStyle: JournalPalette.body.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(42, 42),
        foregroundColor: JournalPalette.ink,
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: JournalPalette.card,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderSide: BorderSide(color: JournalPalette.brassDark),
        borderRadius: BorderRadius.all(Radius.circular(3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: JournalPalette.olive, width: 2),
        borderRadius: BorderRadius.all(Radius.circular(3)),
      ),
    ),
    tooltipTheme: const TooltipThemeData(
      textStyle: TextStyle(
        fontFamily: 'ModernSans',
        fontSize: 13,
        color: JournalPalette.card,
        height: 1.4,
      ),
      decoration: BoxDecoration(
        color: JournalPalette.ink,
        borderRadius: BorderRadius.all(Radius.circular(3)),
      ),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      waitDuration: Duration(milliseconds: 450),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: JournalPalette.olive,
      linearTrackColor: JournalPalette.inset,
    ),
  );
}

/// The image is decoration only. Names, facts, and controls stay live widgets.
BoxDecoration journalPaperDecoration({bool inset = false}) => BoxDecoration(
  color: inset ? JournalPalette.inset : JournalPalette.page,
  image: const DecorationImage(
    image: AssetImage(JournalPalette.paperAsset),
    fit: BoxFit.cover,
    opacity: 0.22,
    filterQuality: FilterQuality.low,
  ),
  border: Border.all(color: JournalPalette.rule),
  borderRadius: BorderRadius.circular(3),
  boxShadow: const [
    BoxShadow(color: Color(0x16000000), blurRadius: 3, offset: Offset(1, 2)),
  ],
);

BoxDecoration journalTabDecoration({
  bool selected = false,
  bool enabled = true,
}) => BoxDecoration(
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: selected
        ? const [JournalPalette.card, JournalPalette.selected]
        : const [JournalPalette.page, JournalPalette.inset],
  ),
  border: Border.all(
    color: selected ? JournalPalette.binding : JournalPalette.brassDark,
    width: selected ? 2 : 1,
  ),
  borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
  boxShadow: enabled
      ? const [
          BoxShadow(
            color: Color(0x26000000),
            offset: Offset(0, -1),
            blurRadius: 2,
          ),
        ]
      : const [],
);

/// A quiet live panel on the journal page, optionally with ledger ruling.
class JournalSurface extends StatelessWidget {
  const JournalSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.inset = false,
    this.lined = false,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool inset;
  final bool lined;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: journalPaperDecoration(inset: inset),
    child: CustomPaint(
      painter: lined ? const _LedgerRuling() : null,
      child: Padding(padding: padding, child: child),
    ),
  );
}

class _LedgerRuling extends CustomPainter {
  const _LedgerRuling();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = JournalPalette.rule.withValues(alpha: 0.18)
      ..strokeWidth = 0.6;
    for (var y = 28.0; y < size.height; y += 28) {
      canvas.drawLine(Offset(9, y), Offset(size.width - 9, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LedgerRuling oldDelegate) => false;
}

/// Decorative spine. It neither handles input nor contributes spoken content.
/// The three pairs of brass rings match the original organiser's structure.
class JournalBinding extends StatelessWidget {
  const JournalBinding({super.key, this.width = 26});
  final double width;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: IgnorePointer(
      child: SizedBox(
        width: width,
        child: const CustomPaint(painter: _BindingPainter()),
      ),
    ),
  );
}

class _BindingPainter extends CustomPainter {
  const _BindingPainter();
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final spine = Rect.fromLTWH(
      size.width * .28,
      0,
      size.width * .44,
      size.height,
    );
    canvas.drawRect(
      spine,
      Paint()
        ..shader = const LinearGradient(
          colors: [
            JournalPalette.brassDark,
            JournalPalette.binding,
            Color(0xFF5B251E),
            JournalPalette.binding,
          ],
        ).createShader(spine),
    );
    canvas.drawLine(
      Offset(size.width * .47, 0),
      Offset(size.width * .47, size.height),
      Paint()
        ..color = JournalPalette.brassLight.withValues(alpha: .5)
        ..strokeWidth = 1,
    );
    if (size.height < 12) return;
    for (final fraction in [.045, .5, .955]) {
      for (final displacement in [-5.0, 5.0]) {
        final y = (size.height * fraction + displacement).clamp(
          3.0,
          size.height - 3,
        );
        final ring = RRect.fromRectAndRadius(
          Rect.fromLTWH(1, y - 3, size.width - 2, 6),
          const Radius.circular(3),
        );
        canvas.drawRRect(
          ring.shift(const Offset(0, 1.5)),
          Paint()..color = const Color(0x5C000000),
        );
        canvas.drawRRect(
          ring,
          Paint()
            ..shader = const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                JournalPalette.brassDark,
                JournalPalette.brassLight,
                JournalPalette.brass,
                JournalPalette.brassDark,
              ],
            ).createShader(ring.outerRect),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BindingPainter oldDelegate) => false;
}
