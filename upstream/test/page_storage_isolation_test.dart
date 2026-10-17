import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/modern/direct_content.dart';
import 'package:lcs_new_age/modern/mechanics_help.dart';

void main() {
  for (final notes in [false, true]) {
    testWidgets(
      '${notes ? 'recruitment keyboard notes' : 'mechanics'} expansion keeps its bool separate from saved scroll offset',
      (tester) async {
        final bucket = PageStorageBucket();
        BuildContext? scrollContext;
        const scrollOffset = 466.666;
        const instruction = 'Press a Letter to select a Profession';
        final console = Console()..mvaddstr(22, 0, instruction);
        final details = notes
            ? DirectContent(
                console: console,
                onAction: (_) {},
                journalPage: true,
              )
            : const ActivityMechanicsPanel(
                mechanics: ActivityMechanics(
                  type: ActivityType.recruiting,
                  title: 'Recruiting',
                  summary: 'Meet potential recruits.',
                  details: 'Choose a profession to arrange a meeting.',
                ),
              );
        Future<void> mount(bool showDetails) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: PageStorage(
                  bucket: bucket,
                  child: SingleChildScrollView(
                    key: const PageStorageKey('journal-management-scroll'),
                    child: Builder(
                      builder: (context) {
                        scrollContext = context;
                        // Reproduce an already-scrolled journal before this tile mounts.
                        bucket.writeState(context, scrollOffset);
                        return showDetails
                            ? details
                            : const SizedBox(height: 1200);
                      },
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        await mount(true);
        expect(tester.takeException(), isNull);
        expect(find.byType(ExpansionTile), findsOneWidget);
        await tester.tap(find.text(notes ? 'Notes' : 'How it works'));
        await tester.pumpAndSettle();
        expect(bucket.readState(scrollContext!), scrollOffset);
        expect(
          bucket.readState(tester.element(find.byType(ExpansionTile))),
          isTrue,
        );

        await mount(false);
        await mount(true);
        expect(tester.takeException(), isNull);
        expect(
          find.text(
            notes ? instruction : 'Choose a profession to arrange a meeting.',
          ),
          findsOneWidget,
        );
        expect(bucket.readState(scrollContext!), scrollOffset);
        expect(
          bucket.readState(tester.element(find.byType(ExpansionTile))),
          isTrue,
        );
      },
    );
  }
}
