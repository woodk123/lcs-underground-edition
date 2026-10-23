import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lcs_new_age/engine/console.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/gamestate/squad.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/modern/organisation_controller.dart';
import 'package:lcs_new_age/modern/organisation_visit_flow.dart';
import 'package:lcs_new_age/utils/lcsrandom.dart';

import 'support/campaign_fixture.dart';

/// A deliberately paused reader, not a simulated gameplay outcome. Actual
/// planner paging, draft cancellation and queuing run in the journal journeys.
class _PausedVisitController extends OrganisationController {
  _PausedVisitController({required super.console, required this.target});
  final Site target;
  final entered = Completer<void>();
  final release = Completer<void>();
  int sendAttempts = 0;

  @override
  bool get canNavigate => true;

  @override
  Future<bool> openSection(String key) async {
    expect(key, 'f');
    entered.complete();
    await release.future;
    console.screen = 'planning';
    console.actions.add(
      ConsoleAction(
        key: 'a',
        label: 'District',
        enabled: true,
        y: 0,
        x: 0,
        width: 8,
        entityType: 'district',
        entityId: target.district.idString,
      ),
    );
    return true;
  }

  @override
  Future<bool> sendAction(ConsoleAction action, {required int revision}) async {
    sendAttempts++;
    return false;
  }
}

enum _Interruption { squadChanged, requestInvalidated, disposed }

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CampaignFixture fixture;
  setUpAll(() async {
    fixture = await CampaignFixture.load('test/saves/felix_1_0.json');
  });

  for (final interruption in _Interruption.values) {
    test(
      'late planner cannot send a district action after $interruption',
      () async {
        fixture.restoreHeadquarters(console: Console());
        // This empty second squad is a declared identity fixture only.
        final other = Squad();
        game.squads.add(other);
        var selected = game.activeSquad;
        final target = game.sites.firstWhere(
          (site) => !site.hidden && site.city == selected?.site?.city,
        );
        final controller = _PausedVisitController(
          console: Console(),
          target: target,
        );
        final flow = OrganisationVisitFlow(
          console: () => controller.console,
          controller: () => controller,
          squad: () => selected,
        );
        var disposed = false;
        addTearDown(() {
          if (!disposed) flow.dispose();
          controller.dispose();
        });
        flow.selectLocation(target);
        final before = campaignSnapshot();
        reseedRNG(seed: 73216);
        final rolls = List.generate(8, (_) => lcsRandom(100000));
        reseedRNG(seed: 73216);
        final queued = flow.queue(
          undercover: false,
          onPrepare: () {},
          onPrepared: () {},
        );
        await controller.entered.future;
        switch (interruption) {
          case _Interruption.squadChanged:
            selected = other;
          case _Interruption.requestInvalidated:
            flow.invalidate();
          case _Interruption.disposed:
            flow.dispose();
            disposed = true;
        }
        controller.release.complete();
        expect(await queued, isFalse);
        expect(controller.sendAttempts, 0);
        expect(campaignSnapshot(), before);
        expect(List.generate(8, (_) => lcsRandom(100000)), rolls);
      },
    );
  }
}
