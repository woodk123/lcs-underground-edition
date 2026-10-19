import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/creature/operation_record.dart';
import 'package:lcs_new_age/creature/skills.dart';
import 'package:lcs_new_age/gamestate/game_state.dart';
import 'package:lcs_new_age/gamestate/ledger.dart';
import 'package:lcs_new_age/gamestate/squad.dart';
import 'package:lcs_new_age/items/item.dart';
import 'package:lcs_new_age/justice/crimes.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/politics/alignment.dart';
import 'package:lcs_new_age/politics/views.dart';
import 'package:lcs_new_age/sitemode/operation_cleanup.dart';

/// Observe the source handler's complete operation without rolling, resolving
/// charges, moving loot or advancing its input reader. Commit only on return.
class OperationHistoryCapture {
  OperationHistoryCapture(Site site)
    : _game = gameState,
      _site = site,
      _squad = activeSquad,
      _date = date,
      _siteName = site.getName(includeCity: true),
      _siege = site.siege.underSiege,
      _closed = site.closed,
      _security = site.highSecurity,
      _controller = site.controller,
      _siteHeat = site.heat,
      _poolIds = pool.map((p) => p.id).toSet(),
      _opinion = Map.of(politics.publicOpinion),
      _income = ledger.totalIncome,
      _expense = ledger.totalExpense,
      _pawnIncome = ledger.income[Income.pawn] ?? 0,
      _loot = _countItems(activeSquad?.loot ?? []),
      _poolBefore = {
        for (final person in pool)
          if (person.alive) person: _PersonBefore(person),
      } {
    _people = {
      for (final person in operationParticipants(siegeSite: site))
        if (_poolBefore.containsKey(person)) person: _poolBefore[person]!,
    };
  }

  final GameState _game;
  final Site _site;
  final Squad? _squad;
  final DateTime _date;
  final String _siteName;
  final bool _siege;
  final int _closed, _security, _siteHeat;
  final SiteController _controller;
  final Set<int> _poolIds;
  final Map<View, double> _opinion;
  final int _income, _expense, _pawnIncome;
  final Map<String, int> _loot;
  final Map<Creature, _PersonBefore> _poolBefore;
  late final Map<Creature, _PersonBefore> _people;
  bool _finished = false;
  String? returnReport;

  void finish() {
    if (_finished || !identical(gameState, _game)) return;
    _finished = true;
    final rescued = _poolBefore.entries
        .where(
          (entry) =>
              !_people.containsKey(entry.key) &&
              entry.value.imprisoned &&
              entry.key.alive &&
              !entry.key.imprisoned,
        )
        .toList();
    for (final entry in rescued) {
      _people[entry.key] = entry.value;
    }
    final joined = pool
        .where((p) => !_poolIds.contains(p.id) && p.align == Alignment.liberal)
        .toList();
    for (final person in joined) {
      _people.putIfAbsent(person, () => _PersonBefore(person));
    }
    final results = <String>[
      if (rescued.isNotEmpty)
        'Rescued from custody: ${rescued.map((e) => e.key.name).join(', ')}.',
      if (joined.isNotEmpty)
        'Joined the movement: ${joined.map((p) => p.name).join(', ')}.',
      if (_site.closed != _closed)
        'Site closure: $_closed → ${_site.closed} days.',
      if (_site.highSecurity != _security)
        'Heightened security: $_security → ${_site.highSecurity} days.',
      if (_site.heat != _siteHeat) 'Site heat: $_siteHeat → ${_site.heat}.',
      if (_site.controller != _controller)
        'Site control: ${_controlLabel(_controller)} → ${_controlLabel(_site.controller)}.',
    ];
    final financialResults = [
      'Cash received during operation: \$${ledger.totalIncome - _income} '
          '(pawn sales: \$${(ledger.income[Income.pawn] ?? 0) - _pawnIncome}).',
      'Expenses during operation: \$${ledger.totalExpense - _expense}.',
      'Net cash during operation: ${ledger.totalIncome - _income - (ledger.totalExpense - _expense) < 0 ? '-' : '+'}'
          '\$${(ledger.totalIncome - _income - (ledger.totalExpense - _expense)).abs()}.',
    ];
    if (ledger.totalIncome != _income || ledger.totalExpense != _expense) {
      results.addAll(financialResults);
    }
    final haul = <String>[];
    // Captured/killed squads may still retain a loot list awaiting cleanup.
    // It is not a successful haul unless someone actually returned with it.
    if (_squad?.members.any((p) => _outcome(p) == OperationOutcome.returned) ??
        false) {
      final carried = _countItems(_squad!.loot);
      for (final entry in carried.entries) {
        final gained = entry.value - (_loot[entry.key] ?? 0);
        if (gained > 0) haul.add('Carried out: ${entry.key} ×$gained.');
      }
    }
    results.addAll(haul);
    final opinion = <View, double>{
      for (final entry in politics.publicOpinion.entries)
        if ((entry.value - (_opinion[entry.key] ?? entry.value)).abs() > 1e-9)
          entry.key: entry.value - _opinion[entry.key]!,
    };
    final records = <Creature, OperationRecord>{};
    var significant = results.isNotEmpty || opinion.isNotEmpty;
    for (final entry in _people.entries) {
      final person = entry.key;
      final before = entry.value;
      final charges = <Crime, int>{
        for (final crime in Crime.values)
          if ((person.wantedForCrimes[crime] ?? 0) >
              (before.charges[crime] ?? 0))
            crime:
                person.wantedForCrimes[crime]! - (before.charges[crime] ?? 0),
      };
      final xp = <Skill, int>{
        for (final skill in Skill.values)
          if (person.skillXP(skill) > (before.xp[skill] ?? 0))
            skill: person.skillXP(skill) - (before.xp[skill] ?? 0),
      };
      final injuries = _injuries(person).difference(before.injuries).toList();
      final outcome = _outcome(person);
      final juiceChange = person.juice - before.juice;
      final bloodChange = person.blood - before.blood;
      significant =
          significant ||
          charges.isNotEmpty ||
          xp.isNotEmpty ||
          injuries.isNotEmpty ||
          juiceChange != 0 ||
          bloodChange != 0 ||
          person.heat != before.heat ||
          outcome != OperationOutcome.returned;
      records[person] = OperationRecord(
        date: _date,
        siteName: _siteName,
        siege: _siege,
        outcome: outcome,
        participants: _people.values.map((p) => p.name).toList(),
        heatBefore: before.heat,
        heatAfter: person.heat,
        juiceChange: juiceChange,
        bloodChange: bloodChange,
        newCharges: charges,
        trainingXp: xp,
        injuries: injuries,
        squadResults: List.of(results),
        opinionChanges: Map.of(opinion),
      );
    }
    if (records.isNotEmpty) {
      returnReport = [
        _siteName,
        if (haul.isEmpty)
          'No newly collected loot returned with the squad.'
        else
          ...haul,
        ...financialResults,
        'These cash figures cover the site operation only. Travel, later sales and later medical bills are separate. Carried loot is inventory, not cash received.',
        for (final entry in records.entries)
          '${entry.key.name}: ${entry.value.outcome.name}'
              '${entry.value.bloodChange == 0 ? '' : ' · blood change ${entry.value.bloodChange}'}'
              '${entry.value.injuries.isEmpty ? ' · no new recorded injuries' : ' · ${entry.value.injuries.join('; ')}'}',
      ].join('\n');
    }
    if (!significant) return;
    for (final entry in records.entries) {
      final history = entry.key.operationHistory;
      history.add(entry.value);
      if (history.length > operationHistoryLimit) {
        history.removeRange(0, history.length - operationHistoryLimit);
      }
    }
  }
}

class _PersonBefore {
  _PersonBefore(Creature p)
    : name = p.name,
      imprisoned = p.imprisoned,
      heat = p.heat,
      juice = p.juice,
      blood = p.blood,
      charges = Map.of(p.wantedForCrimes),
      xp = Map.of(p.rawSkillXP),
      injuries = _injuries(p);
  final String name;
  final bool imprisoned;
  final int heat, juice, blood;
  final Map<Crime, int> charges;
  final Map<Skill, int> xp;
  final Set<String> injuries;
}

OperationOutcome _outcome(Creature p) => !p.alive
    ? OperationOutcome.killed
    : p.imprisoned
    ? OperationOutcome.captured
    : p.missing
    ? OperationOutcome.missing
    : OperationOutcome.returned;

String _controlLabel(SiteController controller) => switch (controller) {
  SiteController.lcs => 'LCS',
  SiteController.ccs => 'CCS',
  SiteController.unaligned => 'Unaligned',
};

Map<String, int> _countItems(Iterable<Item> items) {
  final counts = <String, int>{};
  for (final item in items) {
    final name = item.type.name;
    counts.update(
      name,
      (n) => n + item.stackSize,
      ifAbsent: () => item.stackSize,
    );
  }
  return counts;
}

Set<String> _injuries(Creature p) => {
  ...p.body.allSpecialInjuries(),
  for (final part in p.body.parts)
    if (part.wounded)
      '${part.name}: ${[if (part.missing) 'missing', if (part.shot) 'shot', if (part.cut) 'cut', if (part.bruised) 'bruised', if (part.burned) 'burned', if (part.torn) 'torn', if (part.bleeding > 0) 'bleeding', if (part.relativeHealth < 1) '${(part.relativeHealth * 100).round()}% tissue health'].join(', ')}',
};
