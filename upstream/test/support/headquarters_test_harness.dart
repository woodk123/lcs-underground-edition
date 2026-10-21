import 'package:lcs_new_age/basemode/activate_regulars.dart';
import 'package:lcs_new_age/basemode/activate_sleepers.dart';
import 'package:lcs_new_age/basemode/base_mode.dart';
import 'package:lcs_new_age/basemode/media_overview.dart';
import 'package:lcs_new_age/basemode/plan_site_visit.dart';
import 'package:lcs_new_age/basemode/review_mode.dart';
import 'package:lcs_new_age/engine/engine.dart' as engine;
import 'package:lcs_new_age/gamestate/game_state.dart' as game;

/// Only replaces the headquarters dispatch boundary. Every shared command
/// enters the original source reader. Suites override [dispatch] for their
/// explicit extra branches, or provide an actual headquarters [reader].
class HeadquartersTestHarness {
  HeadquartersTestHarness({Future<void> Function()? reader}) {
    done = _run(reader);
  }

  late final Future<void> done;
  bool stopped = false;
  bool finished = false;
  final dispatched = <int>[];

  Future<void> _run(Future<void> Function()? reader) async {
    try {
      if (reader != null) {
        await reader();
        return;
      }
      while (!stopped) {
        engine.erase();
        final location = game.activeSquad?.site ?? game.activeSafehouse;
        baseModeSquadSafehouseDisplay(location);
        baseModeOptionsDisplay(location);
        final key = await engine.getKey();
        if (stopped) break;
        dispatched.add(key);
        await dispatch(key);
      }
    } finally {
      finished = true;
    }
  }

  Future<void> dispatch(int key) async {
    switch (key) {
      case engine.Key.r:
        await reviewAssetsAndFormSquads();
      case engine.Key.a:
        await activateRegulars();
      case engine.Key.b:
        await activateSleepers();
      case engine.Key.f:
        await planSiteVisit();
      case engine.Key.m:
        await mediaOverview();
    }
  }

  /// Real-time shutdown; widget suites retain their own fake-async pumping.
  Future<void> stop() async {
    stopped = true;
    for (var step = 0; step < 40 && !finished; step++) {
      if (engine.console.awaitingInput) {
        engine.console.sendInput(engine.console.textInput ? 'Enter' : 'Escape');
      }
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    await done.timeout(const Duration(seconds: 2));
  }
}
