import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/modern/journal_city_plan.dart';

const places = [
  JournalMapPlace(
    id: 'Site10',
    name: 'Warehouse',
    kind: 'site',
    enabled: true,
    current: true,
    details: ['Heat: 3', 'Secrecy: 8'],
  ),
  JournalMapPlace(
    id: 'Site11',
    name: 'Factory',
    kind: 'site',
    enabled: false,
    details: ['Closed down', 'Need car'],
  ),
  JournalMapPlace(
    id: 'district:university',
    name: 'University District',
    kind: 'district',
    enabled: true,
    queued: true,
  ),
  JournalMapPlace(
    id: 'city:Seattle',
    name: 'Seattle',
    kind: 'city',
    enabled: true,
  ),
];

Finder block(String id) => find.byKey(ValueKey('journal-map-place:$id'));

Future<void> mount(
  WidgetTester tester, {
  List<JournalMapPlace> data = places,
  ValueChanged<String>? onSelect,
  String? selectedId,
  Size size = const Size(600, 540),
  double textScale = 1,
  bool showLabels = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: JournalCityPlan(
            places: data,
            onSelect: onSelect ?? (_) {},
            selectedId: selectedId,
            showLabels: showLabels,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('only supplied known places become selectable blocks', (
    tester,
  ) async {
    await mount(tester);
    for (final place in places) {
      expect(block(place.id), findsOneWidget);
    }
    expect(find.byType(TextButton), findsNWidgets(places.length));
    expect(find.text('A secret enemy base'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'click reports the exact source ID once and does not select itself',
    (tester) async {
      final actions = <String>[];
      await mount(tester, onSelect: actions.add);
      await tester.tap(block('district:university'));
      await tester.pumpAndSettle();
      expect(actions, ['district:university']);
      expect(
        tester.widget<JournalCityPlan>(find.byType(JournalCityPlan)).selectedId,
        isNull,
      );
      expect(places[2].queued, isTrue);
      expect(places[0].details, ['Heat: 3', 'Secrecy: 8']);
    },
  );

  testWidgets(
    'unavailable block cannot dispatch and retains its real reasons',
    (tester) async {
      final actions = <String>[];
      await mount(tester, onSelect: actions.add);
      final button = tester.widget<TextButton>(block('Site11'));
      expect(button.onPressed, isNull);
      await tester.tap(block('Site11'));
      await tester.pumpAndSettle();
      expect(actions, isEmpty);
      expect(
        find.byTooltip('Factory. site. Unavailable. Closed down. Need car'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'selection, current location, queued status and facts are accessible',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await mount(tester, selectedId: 'Site10');
      expect(
        find.bySemanticsLabel(
          'Warehouse. site. Current location. Selected. Heat: 3. Secrecy: 8',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'University District. district. Queued destination',
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.my_location), findsOneWidget);
      expect(find.byIcon(Icons.flag), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets(
    'source order changes do not move stable destination identities',
    (tester) async {
      await mount(tester);
      final before = {
        for (final place in places) place.id: tester.getRect(block(place.id)),
      };
      await mount(tester, data: places.reversed.toList());
      for (final place in places) {
        expect(tester.getRect(block(place.id)), before[place.id]);
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('zoom and fit work without dispatching a destination', (
    tester,
  ) async {
    final actions = <String>[];
    await mount(tester, onSelect: actions.add);
    final viewer = tester.widget<InteractiveViewer>(
      find.byKey(const ValueKey('journal-city-pan-zoom')),
    );
    final controller = viewer.transformationController!;
    final initial = controller.value.clone();
    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pumpAndSettle();
    expect(controller.value.entry(0, 0), greaterThan(initial.entry(0, 0)));
    await tester.tap(find.byTooltip('Fit all locations'));
    await tester.pumpAndSettle();
    expect(controller.value.storage, initial.storage);
    await tester.drag(
      find.byKey(const ValueKey('journal-city-pan-zoom')),
      const Offset(30, 40),
    );
    await tester.pumpAndSettle();
    expect(controller.value.storage, isNot(initial.storage));
    expect(actions, isEmpty);
  });

  testWidgets(
    'source list update removes stale places and refits remaining ones',
    (tester) async {
      final actions = <String>[];
      await mount(tester, onSelect: actions.add);
      await mount(tester, data: [places[0]], onSelect: actions.add);
      expect(block('Site11'), findsNothing);
      expect(block('district:university'), findsNothing);
      expect(block('Site10'), findsOneWidget);
      await tester.tap(block('Site10'));
      await tester.pumpAndSettle();
      expect(actions, ['Site10']);
    },
  );

  for (final width in [400.0, 600.0]) {
    testWidgets('bounded ${width.toInt()}px page remains usable at 150% text', (
      tester,
    ) async {
      final actions = <String>[];
      await mount(
        tester,
        size: Size(width, 470),
        textScale: 1.5,
        onSelect: actions.add,
      );
      expect(tester.takeException(), isNull);
      final bounds = tester.getRect(
        find.byKey(const ValueKey('journal-city-plan')),
      );
      for (final place in places) {
        final rect = tester.getRect(block(place.id));
        expect(bounds.contains(rect.center), isTrue);
      }
      await tester.tap(block('city:Seattle'));
      await tester.pumpAndSettle();
      expect(actions, ['city:Seattle']);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'complete index keeps long names and every large-campaign place',
    (tester) async {
      final data = List.generate(
        48,
        (i) => JournalMapPlace(
          id: 'site:$i',
          name: 'Known location $i with a long descriptive source name',
          kind: 'site',
          enabled: i != 47,
          details: [if (i == 47) 'No transport available'],
        ),
      );
      final actions = <String>[];
      await mount(tester, data: data, onSelect: actions.add);
      for (final place in data) {
        expect(block(place.id), findsOneWidget);
      }
      await tester.tap(find.byTooltip('Show location index'));
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsNWidgets(48));
      final last = find.byKey(const ValueKey('journal-map-index:site:46'));
      await tester.ensureVisible(last);
      await tester.pumpAndSettle();
      await tester.tap(last);
      await tester.pumpAndSettle();
      expect(actions, ['site:46']);
      expect(
        find.text('Known location 47 with a long descriptive source name'),
        findsOneWidget,
      );
      expect(find.textContaining('No transport available'), findsOneWidget);
      await tester.tap(find.byTooltip('Show city plan'));
      await tester.pumpAndSettle();
      expect(block('site:47'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('keyboard activation dispatches only the focused real place', (
    tester,
  ) async {
    final actions = <String>[];
    await mount(tester, onSelect: actions.add);
    bool focused() =>
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<TextButton>()
            ?.key ==
        const ValueKey('journal-map-place:Site10');
    for (var step = 0; step < 20 && !focused(); step++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
    }
    expect(focused(), isTrue);
    expect(actions, isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(actions, ['Site10']);
  });

  testWidgets('hidden labels preserve full destination semantics and tooltip', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await mount(tester, showLabels: false);
    expect(find.text('Warehouse'), findsNothing);
    expect(
      find.bySemanticsLabel(
        'Warehouse. site. Current location. Heat: 3. Secrecy: 8',
      ),
      findsOneWidget,
    );
    expect(
      find.byTooltip('Warehouse. site. Current location. Heat: 3. Secrecy: 8'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('empty known-state has no phantom interactive buildings', (
    tester,
  ) async {
    await mount(tester, data: []);
    expect(find.byType(TextButton), findsNothing);
    expect(find.text('No known locations in this view.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
