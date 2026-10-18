import 'package:flutter/foundation.dart';
import 'package:lcs_new_age/gamestate/game_state.dart' as game;
import 'package:lcs_new_age/politics/alignment.dart';

@immutable
class CampaignRequirement {
  const CampaignRequirement({
    required this.id,
    required this.title,
    required this.detail,
    required this.met,
  });

  final String id, title, detail;
  final bool met;
}

/// Read-only presentation of the conditions in advance_month.dart's winCheck.
/// Both the Agenda summary and detailed law guide use the same current counts.
List<CampaignRequirement> campaignVictoryRequirements() {
  int elite(Iterable<DeepAlignment> values) =>
      values.where((value) => value == DeepAlignment.eliteLiberal).length;
  CampaignRequirement majority(
    String id,
    String title,
    List<DeepAlignment> body,
  ) {
    final count = elite(body);
    return CampaignRequirement(
      id: id,
      title: title,
      detail:
          '$count/${body.length} Elite Liberal · needs ${body.length ~/ 2 + 1} for a majority',
      met: count * 2 > body.length,
    );
  }

  final politics = game.politics;
  return List.unmodifiable([
    CampaignRequirement(
      id: 'laws',
      title: 'Every law',
      detail:
          '${elite(politics.laws.values)}/${politics.laws.length} at Elite Liberal',
      met: politics.laws.values.every(
        (value) => value == DeepAlignment.eliteLiberal,
      ),
    ),
    majority('court', 'Supreme Court majority', politics.court),
    majority('house', 'House majority', politics.house),
    majority('senate', 'Senate majority', politics.senate),
    CampaignRequirement(
      id: 'executive',
      title: 'Every executive office',
      detail:
          '${elite(politics.exec.values)}/${politics.exec.length} at Elite Liberal',
      met: politics.exec.values.every(
        (value) => value == DeepAlignment.eliteLiberal,
      ),
    ),
    CampaignRequirement(
      id: 'ccs',
      title: 'Conservative Crime Squad',
      detail: game.ccsActive
          ? 'Active · must be defeated'
          : 'Inactive · condition currently met',
      met: !game.ccsActive,
    ),
  ]);
}
