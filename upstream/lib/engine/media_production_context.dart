import 'package:lcs_new_age/basemode/activities.dart';
import 'package:lcs_new_age/creature/creature.dart';
import 'package:lcs_new_age/items/loot_type.dart';

/// Staff whose current standing order contributes to special-edition reach.
/// The monthly source and its planning view must apply the same active check
/// to writers and streamers, including custody, absence and sleeper status.
Iterable<Creature> guardianSpecialEditionPublishers(
  Iterable<Creature> people,
) => people.where(
  (person) =>
      person.isActiveLiberal &&
      (person.activity.type == ActivityType.writeGuardian ||
          person.activity.type == ActivityType.streamGuardian),
);

/// Authoritative evidence accepted by the monthly Liberal Guardian reader.
/// The production directory and the original publishing decision share this
/// list so an inventory preview cannot promise an unsupported publication.
const guardianSpecialEditionEvidenceIds = <String>[
  LootTypeIds.amRadioFiles,
  LootTypeIds.cableNewsFiles,
  LootTypeIds.ccsBackerList,
  LootTypeIds.ceoLoveLetters,
  LootTypeIds.ceoPhotos,
  LootTypeIds.ceoTaxPapers,
  LootTypeIds.corpFiles,
  LootTypeIds.intHqDisk,
  LootTypeIds.judgeFiles,
  LootTypeIds.policeRecords,
  LootTypeIds.prisonFiles,
  LootTypeIds.researchFiles,
  LootTypeIds.secretDocuments,
  LootTypeIds.landlordPapers,
  LootTypeIds.insuranceFraudEvidence,
  LootTypeIds.elderAbuseEvidence,
];
