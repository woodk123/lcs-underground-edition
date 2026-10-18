import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/sitemode/sitemap.dart';

/// Read-only general knowledge; never runs an action, eligibility roll or preview.
/// Audit sources: map_specials.dart and miscactions.dart (facility handlers),
/// sitemode.dart (entry/exit), daily/shopsnstuff.dart and advance_day.dart (services),
/// sleeper_update.dart, daily/siege.dart and lcs_monthly.dart (later effects).
({String opportunities, String risks}) locationEffects(
  SiteType type,
) => switch (type) {
  SiteType.insuranceOffice => (
    opportunities:
        "Approve members of the public’s denied claims for Juice and public support. "
        "Steal Healthcare Documents for a Guardian exposé. An Insurance CEO sleeper "
        "can embezzle, leak evidence and warn of medical-debt raids.",
    risks:
        "Claims and stolen records do not clear your squad’s hospital debt. Safe "
        "attempts can fail and be noticed; publishing the evidence can provoke "
        "corporate retaliation. Expand each facility below for checks, rewards and "
        "limits.",
  ),
  SiteType.nursingHome => (
    opportunities:
        "Help residents for Juice, retirement opinion and LCS approval. Steal "
        "elder-abuse evidence for a Guardian exposé. The administrator can become a "
        "sleeper through the normal conversion system.",
    risks:
        "Care is unavailable during an alarm and each resident allows one completed "
        "attempt. Record theft risks detection and charges; publishing can provoke "
        "corporate retaliation. Helping one resident does not change the whole "
        "facility’s care rules.",
  ),
  SiteType.cosmeticsLab => (
    opportunities:
        "Free rabbits with Security for Juice and an animal-rescue news event. Smash "
        "laboratory equipment for Juice and an animal-research opinion effect. "
        "Research files can support a Guardian exposé.",
    risks:
        "Cage attempts can fail and be noticed. Destruction starts suspicion and "
        "risks vandalism charges. News coverage depends on the whole operation, "
        "including any violence.",
  ),
  SiteType.geneticsLab => (
    opportunities:
        "Free genetically altered creatures with Security for Juice and a rescue news "
        "event. Research files can support a Guardian exposé. Laboratory sabotage "
        "affects animal-research opinion.",
    risks:
        "Released creatures may confront you and can raise the alarm. Cage attempts "
        "are limited. Sabotage starts suspicion and risks vandalism charges; it does "
        "not directly change genetic-research law.",
  ),
  SiteType.sweatshop => (
    opportunities:
        "Meet workers, including people eligible for the normal rescue interaction. "
        "Smash production equipment for 5 Juice per tile (cap 200) and a vandalism "
        "news event. Operation coverage can affect labour and immigration opinion.",
    risks:
        "Sabotage starts suspicion and risks detection and vandalism charges. "
        "Rescuing workers requires an available squad slot or carrier and an escape. "
        "Destroying equipment does not directly increase wages.",
  ),
  SiteType.dirtyIndustry => (
    opportunities:
        "Smash industrial equipment for 5 Juice per tile (cap 200) and a "
        "pollution-opinion effect. Meet workers; operation coverage can also affect "
        "labour issues.",
    risks:
        "Sabotage starts suspicion and risks detection and vandalism charges. The "
        "opinion effect is filtered by public interest and LCS support. Pollution law "
        "changes through politics, not immediately through sabotage.",
  ),
  SiteType.nuclearPlant => (
    opportunities:
        "Use reactor controls for a Hard Science attempt: ordinary success shuts down "
        "the reactor for 100 Juice (cap 1,000) and a nuclear-power opinion effect. An "
        "armory can supply military equipment.",
    risks:
        "Any reactor attempt raises the alarm and risks terrorism charges. Under "
        "Elite Liberal nuclear law, success releases waste instead, loses Juice and "
        "sharply hurts LCS approval. Armory raids always summon armed defenders.",
  ),
  SiteType.policeStation => (
    opportunities:
        "Open the lockup with Formidable Security for 50 Juice (cap 1,000), prisoner "
        "encounters and recovery of your own detained members at this site. Police "
        "records can support a Guardian exposé.",
    risks:
        "Failed lock attempts still risk detection and aiding-escape charges and use "
        "up the lockup interaction. Rescued members need free squad slots or "
        "carriers, then an escape; they gain an escaping-prison charge.",
  ),
  SiteType.courthouse => (
    opportunities:
        "Open the lockup to recover detained crew and meet prisoners. Influence a "
        "jury using Hard Persuasion and Challenging Law. Judge files can support a "
        "Guardian exposé.",
    risks:
        "Lockup attempts risk detection and aiding-escape charges. A failed jury "
        "intervention risks jury-tampering charges; failing both checks raises the "
        "alarm. Jury success does not resolve your crew’s pending court cases.",
  ),
  SiteType.prison => (
    opportunities:
        "Control rooms release prisoners and can recover your jailed crew: low "
        "security for fixed sentences, medium for life sentences, high for death row. "
        "Each control gives 50 Juice (cap 1,000) without a lockpicking check.",
    risks:
        "Each control starts suspicion, risks detection and aiding-escape charges, "
        "and adds site crime. Bring squad slots or carriers for your people and "
        "escape. Current death-penalty law changes the number of other prisoners "
        "generated.",
  ),
  SiteType.intelligenceHQ => (
    opportunities:
        "Hack the supercomputer with Heroic Computers for an intelligence disk and 50 "
        "Juice (cap 1,000). If the CCS is active and its backers are still "
        "undiscovered, also recover their backer list.",
    risks:
        "An alarm prevents hacking. An actual attempt can fail, be noticed and incur "
        "treason charges. Publishing intelligence evidence also risks treason charges "
        "and retaliation; theft alone does not publish it.",
  ),
  SiteType.corporateHQ => (
    opportunities:
        "Crack the records safe with Formidable Security to obtain two sets of "
        "corporate files and 50 Juice (cap 1,000). Bring files home for separate "
        "Guardian exposés.",
    risks:
        "An actual safe attempt is used up even on failure and risks detection and "
        "theft charges. Publishing corporate evidence can provoke corporate raids. "
        "Public reaction also depends on the rest of the operation.",
  ),
  SiteType.ceoHouse => (
    opportunities:
        "Find the corporate CEO while the site is calm, and crack the private safe "
        "for a weapon, valuables or publishable scandals. A converted CEO can become "
        "a lucrative sleeper.",
    risks:
        "The CEO hides during an alarm, site alienation or a siege. A conservative "
        "former hostage can ambush you with mercenaries and dogs. Safe attempts are "
        "limited; publishing scandals can provoke corporate retaliation.",
  ),
  SiteType.amRadioStation || SiteType.cableNewsStation => (
    opportunities:
        "Take over a studio to broadcast on a random issue. Squad attributes, "
        "relevant speaking skills and size determine reception; a strong show can "
        "influence opinion. Media files can support a Guardian exposé.",
    risks:
        "Starting a takeover always raises the alarm. Living conservatives in the "
        "current encounter prevent the broadcast. A poor show can backfire; a "
        "completed show risks speech-related charges and may leave security waiting. "
        "Publishing media evidence can provoke conservative mobs.",
  ),
  SiteType.bank => (
    opportunities:
        "Open the vault with Heroic Security, Hard Computers and a recognized "
        "manager. Collect cash separately: each pile is \$20,000 in squad loot, "
        "credited only if you bring it out.",
    risks:
        "A failed lock check uses up the vault attempt. Manager eligibility is "
        "limited; a local sleeper loses cover when used. Successful entry risks "
        "bank-robbery charges, and collecting cash can accelerate the response and "
        "bring SWAT teams.",
  ),
  SiteType.armyBase => (
    opportunities:
        "An armory can supply weapons, ammunition and armour. The first successful "
        "army-base armory haul includes the M250. Secret documents can support a "
        "Guardian exposé.",
    risks:
        "Breaking into the armory always raises the alarm and brings soldiers. A loot "
        "haul risks theft and treason charges; an empty armory still risks treason. "
        "Publishing secret documents risks treason and retaliation.",
  ),
  SiteType.whiteHouse => (
    opportunities:
        "Reach the Oval Office to encounter the President and guards while the site "
        "is calm. An armory and secret documents offer equipment and evidence "
        "opportunities.",
    risks:
        "During an alarm, six Secret Service agents ambush you instead of the "
        "President. A conservative President who was your hostage also triggers an "
        "ambush. Armory raids always raise the alarm and bring mercenaries; "
        "secret-document publication risks treason and retaliation.",
  ),
  SiteType.clinic => (
    opportunities:
        "Admit all living injured members of the visiting squad for inpatient "
        "recovery. The free clinic adds no new medical bills. Patients recover with "
        "medical support and return to their base on discharge, or a homeless camp if "
        "their base is unavailable.",
    risks:
        "Admission removes patients from their squad and active duties; reassign them "
        "afterwards. Clinic medical support is lower than the university hospital’s. "
        "Existing medical debt is not erased. Discharge occurs when fully healed or "
        "after 60 days.",
  ),
  SiteType.universityHospital => (
    opportunities:
        "Admit all living injured members of the visiting squad for inpatient "
        "recovery. The hospital provides stronger medical support than the free "
        "clinic. Patients return to their base on discharge, or a homeless camp if "
        "their base is unavailable.",
    risks:
        "Hospital bills accumulate as treatment is performed, depending on healthcare "
        "law; Elite Liberal healthcare adds no charges. There is no upfront price "
        "quote. At discharge choose to pay or leave debt owed. Patients leave their "
        "squad on admission and need reassignment afterwards; the stay ends when "
        "healed or after 60 days.",
  ),
  SiteType.pawnShop => (
    opportunities:
        "Buy available equipment and sell eligible unwanted items. The stock list "
        "below shows regular prices under current laws; undercover purchase prices "
        "can differ.",
    risks:
        "Buying spends LCS funds. Ordinary quick selling excludes protected evidence; "
        "keep documents you intend to publish. Stock and legal availability can "
        "change with the law.",
  ),
  SiteType.departmentStore => (
    opportunities:
        "Buy clothing and supplies from the departments shown below. The catalogue "
        "uses current laws and regular prices; choose actual purchases on arrival.",
    risks:
        "Purchases spend LCS funds. Availability and undercover prices can differ. "
        "Clothing condition and suitability matter for disguises; buying an outfit "
        "does not guarantee access.",
  ),
  SiteType.oubliette => (
    opportunities:
        "Buy specialist clothing and equipment from the catalogue below. Choose "
        "actual purchases on arrival.",
    risks:
        "Purchases spend LCS funds. An outfit’s appearance is not a guarantee that it "
        "fits a particular location; inspect the clothing ratings for the "
        "destination.",
  ),
  SiteType.armsDealer => (
    opportunities:
        "Buy black-market weapons and ammunition from the catalogue below. Check "
        "which ammunition each weapon accepts before buying.",
    risks:
        "Purchases spend LCS funds. Carrying suspicious weapons can expose the squad "
        "at checkpoints or during operations even when the purchase itself succeeds.",
  ),
  SiteType.carDealership => (
    opportunities:
        "Buy used vehicles or sell the assigned buyer’s current vehicle. A living "
        "car-salesman sleeper in this city provides discounted purchase prices.",
    risks:
        "Sale value is 80% of the vehicle’s base price, reduced to one tenth of that "
        "if it has any heat. Purchases spend LCS funds; choose the buyer carefully "
        "because selling uses their assigned car.",
  ),
  SiteType.tenement || SiteType.apartment => (
    opportunities:
        "Meet residents and the landlord. Arrange rented accommodation through the "
        "rental interaction; the location guide itself makes no commitment.",
    risks:
        "Rent is a recurring cost and unpaid rent can lead to eviction. Private homes "
        "are restricted; residents encountered there become hostile to intruders. "
        "Landlords in high-security buildings can have mercenary bodyguards.",
  ),
  SiteType.upscaleApartment => (
    opportunities:
        "Meet wealthy residents and the landlord, arrange rented accommodation, or "
        "search for valuables and landlord papers. Landlord evidence can support a "
        "housing exposé.",
    risks:
        "Rent is a recurring cost and unpaid rent can lead to eviction. Private homes "
        "are restricted. A high-security landlord can have mercenary bodyguards, and "
        "publishing landlord papers can cause eviction by sharply increasing "
        "publishers’ rent.",
  ),
  SiteType.warehouse => (
    opportunities:
        "Ordinary abandoned warehouses begin as LCS-controlled shelter. Inspect the "
        "Bases chapter for moving crew and improving security. An unaligned warehouse "
        "can also be captured after sufficient site disruption.",
    risks:
        "LCS control does not make a base safe from raids. Heat, residents’ crimes "
        "and protection still matter. Capturing an unaligned site is a separate "
        "operation, not a result of reading this guide.",
  ),
  SiteType.drugHouse => (
    opportunities:
        "Meet the occupants or attempt to take an unaligned drug house as a base "
        "through sufficient disruption during an operation.",
    risks:
        "Taking control can involve armed opposition and leaves a base that still "
        "needs heat management and protection. A visit alone does not secure "
        "ownership.",
  ),
  SiteType.homelessEncampment => (
    opportunities:
        "LCS-controlled shelter available without rent. Use Bases to station crew "
        "here; tents can provide encounters. Sleeper document leaks are delivered to "
        "the camp in their work city.",
    risks:
        "Shelter is not protection from raids. Check heat, local threats and security "
        "before gathering wanted crew or valuable evidence here.",
  ),
  SiteType.bombShelter || SiteType.bunker || SiteType.barAndGrill => (
    opportunities:
        "Meet occupants and, at a CCS-controlled site, confront a CCS leader. A quiet "
        "leadership room has the leader alone; an alarm or siege adds five "
        "vigilantes. Base availability depends on control.",
    risks:
        "A bouncer may refuse entry. Alerting the site before reaching leadership "
        "increases opposition. Confrontation, theft and destruction can lead to armed "
        "combat and criminal charges.",
  ),
  SiteType.fireStation => (
    opportunities:
        "Meet firefighters through ordinary encounters. The location’s possible loose "
        "loot includes firefighting clothing and ordinary valuables.",
    risks:
        "Stealing or attacking can raise alarms and criminal charges. There is no "
        "special fire-service control here that automatically changes fire policy or "
        "protects your bases.",
  ),
  SiteType.juiceBar ||
  SiteType.latteStand ||
  SiteType.veganCoOp ||
  SiteType.internetCafe ||
  SiteType.publicPark => (
    opportunities:
        "Meet people for conversation and possible recruitment. Occupied seating, "
        "tents or workstations can provide encounters where the map includes them. "
        "Recruitment follows the normal dialogue and meeting rules.",
    risks:
        "People’s alignment and willingness to talk vary. A public venue is not "
        "immunity from detection or charges: weapons, violence, theft and trespass "
        "can still provoke a response.",
  ),
  SiteType.liberalPartyHQ => (
    opportunities:
        "Meet people through ordinary encounters and use the normal conversation and "
        "recruitment options. This location has no special party-management service.",
    risks:
        "Visiting does not automatically change laws, win an election or add party "
        "members to your crew. Political outcomes still follow the campaign’s normal "
        "opinion and election systems.",
  ),
  SiteType.downtown ||
  SiteType.commercialDistrict ||
  SiteType.universityDistrict ||
  SiteType.industrialDistrict ||
  SiteType.outOfTown => (
    opportunities:
        "Open this district to choose one of its known buildings. Each building’s "
        "guide explains its own services, encounters and operation opportunities.",
    risks:
        "A district is a navigation group, not a single operation. Access, travel, "
        "restrictions and risks depend on the destination you choose.",
  ),
};

const locationOperationConsequences =
    'Operation coverage can help or hurt public support according to your actions and how they are reported. '
    'Enough disruption can close a site or increase security on later visits. '
    'Carried cash and evidence must survive the escape. Evidence is published separately through the monthly Guardian choice, consuming one copy. '
    'Opinion effects influence politics; they do not immediately rewrite laws. '
    'Squad Juice rewards apply to each living member up to the stated cap; members already above it keep their existing Juice. '
    'Suspicion timers count down only while site crime is above 5 and no alarm is active; they are not guaranteed escape deadlines. '
    'Attempt limits below apply to the current operation’s map, not a permanent campaign-wide ban.';

/// Possible map facilities, not a promise that a room or its occupants exist.
/// Paragraph one is deliberately short enough for a hover/long-press hint.
String? locationFeatureHelp(TileSpecial feature) => switch (feature) {
  TileSpecial.insuranceClaimsTerminal =>
    "Approve a member of the public’s denied insurance claim with an Average "
        "Computers check.\n\n"
        "Reward: success gives 5 Juice (cap 200), improves LCS approval and applies a "
        "healthcare-opinion effect filtered by public interest and LCS support. The "
        "hacker gains 20 Computers training on success or failure.\n\n"
        "Attempt limit: success or failure uses up this terminal; declining leaves it "
        "available. The override itself adds no alarm or criminal charge. Your "
        "squad’s own hospital bills remain unchanged.",
  TileSpecial.insuranceFiles =>
    "Crack the safe with Formidable Security to recover Healthcare Documents for "
        "a Guardian exposé.\n\n"
        "Reward: success gives one set of insurance-fraud evidence and 50 Juice (cap "
        "1,000). Bring the documents to an LCS-controlled base. At the monthly "
        "Guardian special-edition choice, publishing consumes one copy; declining "
        "keeps it. Impact depends on publisher numbers and Writing, or Persuasion "
        "with a penalty for streamers.\n\n"
        "Publication improves healthcare opinion, LCS recognition and approval, and "
        "sometimes women’s rights, LGBT rights or civil rights. Publishers gain 20 "
        "Juice (cap 1,000). It can provoke corporate retaliation; it does not pay "
        "your crew’s medical debt.\n\n"
        "Attempt limit and risk: agreeing uses up this safe even if the check fails "
        "or nobody can attempt it, and triggers a detection check. Success adds 40 "
        "site crime and possible theft charges. Declining leaves the safe available.",
  TileSpecial.nursingHomeFiles =>
    "Crack the safe with Formidable Security to recover elder-abuse evidence for "
        "a Guardian exposé.\n\n"
        "Reward: one set of evidence and 50 Juice (cap 1,000). Bring the documents to "
        "an LCS-controlled base. At the monthly Guardian special-edition choice, "
        "publishing consumes one copy; declining keeps it. Impact depends on "
        "publisher numbers and Writing, or Persuasion with a penalty for streamers.\n\n"
        "Publication improves retirement opinion, LCS recognition and approval; some "
        "stories also affect healthcare or civil rights. Publishers gain 20 Juice "
        "(cap 1,000). Publishing marks corporations as offended and can contribute to "
        "retaliation.\n\n"
        "Attempt limit and risk: agreeing uses up this safe even if the check fails "
        "or nobody can attempt it, and triggers a detection check. Success adds 40 "
        "site crime and possible theft charges. Declining leaves the safe available.",
  TileSpecial.corporateFiles =>
    "Crack the records safe with Formidable Security for two sets of corporate "
        "files.\n\n"
        "Reward: success gives 50 Juice (cap 1,000) and adds 40 site crime. Bring the "
        "documents to an LCS-controlled base. At the monthly Guardian special-edition "
        "choice, publishing consumes one copy; declining keeps it. Impact depends on "
        "publisher numbers and Writing, or Persuasion with a penalty for streamers. "
        "Corporate exposés can improve corporate-related opinion but provoke "
        "corporate retaliation.\n\n"
        "Attempt limit and risk: an actual attempt uses up the safe even on failure, "
        "triggers a detection check, adds 3 site crime and possible theft charges. If "
        "nobody can attempt the lock, it remains available. Declining leaves it "
        "available.",
  TileSpecial.ceoSafe =>
    "Crack the CEO’s safe with Formidable Security for valuables and possible "
        "scandal evidence.\n\n"
        "Contents: the first haul includes a Desert Eagle and nine spare magazines if "
        "it has not already been found. Other independent finds can include "
        "\$1,000–\$10,000, jewellery, photos, love letters and tax papers. Later safes "
        "can be empty. A nonempty result gives 50 Juice (cap 1,000), adds 40 site "
        "crime and possible theft charges.\n\n"
        "Bring the documents to an LCS-controlled base. At the monthly Guardian "
        "special-edition choice, publishing consumes one copy; declining keeps it. "
        "Impact depends on publisher numbers and Writing, or Persuasion with a "
        "penalty for streamers. Publishing CEO scandals can provoke corporate "
        "retaliation.\n\n"
        "Attempt limit and risk: agreeing uses up the safe even on failure or if "
        "nobody can attempt it, and triggers a detection check. Declining leaves it "
        "available.",
  TileSpecial.insuranceCEO =>
    "Meet the Insurance CEO if alive and present; conversion can make them a "
        "valuable sleeper agent.\n\n"
        "Sleeper options: embezzle up to \$50,000 per month at full infiltration, or "
        "spy for insurance-fraud evidence. Embezzlement can cost infiltration or lead "
        "to arrest; successful leaks cost 20 infiltration points. A CEO sleeper also "
        "supplies a warning naming the safehouse when a medical-debt raid is "
        "scheduled; this does not stop the raid.\n\n"
        "Their liberal-influence assignment affects a random issue, not specifically "
        "healthcare. They have Business-based social attacks. The normal hostage "
        "relationship and release system can lead to sleeper recruitment; it is not "
        "automatic.\n\n"
        "Encounter risk: a conservative CEO you previously held hostage calls four "
        "mercenaries, raises the alarm and immediately attacks. Meeting or converting "
        "them does not cancel your squad’s medical bills or directly change "
        "healthcare law.",
  TileSpecial.ceoOffice =>
    "Meet the corporate CEO while the site is calm; conversion can make them a "
        "powerful sleeper.\n\n"
        "The CEO hides if there is an alarm, site alienation or a siege. If present "
        "and still conservative after being your hostage, they call three mercenaries "
        "and two guard dogs, raise the alarm and attack immediately.\n\n"
        "Sleeper options include corporate influence, corporate-document leaks and "
        "embezzlement at the \$50,000 × infiltration monthly tier. Leaks and "
        "embezzlement risk exposure. Conversion follows the normal "
        "recruitment/hostage systems; entering the study does not reform the company.",
  TileSpecial.nursingHomeManager =>
    "Meet the administrator if alive and present; conversion can provide a "
        "sleeper with access to elder-abuse evidence.\n\n"
        "Sleeper options include influencing healthcare, retirement and genetics "
        "opinion; leaking elder-abuse evidence; or embezzling at the \$5,000 × "
        "infiltration monthly tier. Leaks and embezzlement risk exposure. Normal "
        "conversion rules apply.\n\n"
        "Encounter risk: a conservative administrator who was your hostage raises the "
        "alarm and attacks with two nurses, or two guards and a guard dog at high "
        "security. Meeting or converting them does not automatically improve the "
        "home’s care rules.",
  TileSpecial.nursingHomePatient =>
    "Check on a resident while the site is calm; their situation determines the "
        "skill needed.\n\n"
        "Checks range from Automatic to Average and can use Psychology, First Aid, "
        "Security, Writing, Computers or Music. The current handler chooses the squad "
        "member with the lowest level in that skill. Success gives 5 Juice (cap 200), "
        "improves LCS approval and applies a retirement-opinion effect filtered by "
        "public interest and LCS support.\n\n"
        "The helper trains the relevant skill on success or failure. One completed "
        "care attempt per resident; an alarm prevents care and leaves the resident "
        "available for later. Helping does not recruit the resident or produce "
        "evidence items.",
  TileSpecial.nursingHomePatientDone =>
    "This resident has already had a care attempt.\n\n"
        "Success or failure completes the interaction. Revisiting grants no further "
        "care reward during this operation.",
  TileSpecial.cagedRabbits =>
    "Open the cage with Very Easy Security to release laboratory rabbits.\n\n"
        "Success gives 3 Juice (cap 100), adds 1 site crime and an animal-rescue news "
        "event, and sets or shortens the suspicion timer to 20–29.\n\n"
        "An actual attempt triggers a detection check and uses up this cage even on "
        "failure. Declining or having nobody able to attempt it leaves the cage "
        "available. Released rabbits do not join your squad.",
  TileSpecial.cagedMonsters =>
    "Open the cage with Average Security to release genetically altered "
        "creatures.\n\n"
        "Success gives 5 Juice (cap 200), adds 1 site crime and a rescue news event, "
        "and sets or shortens the suspicion timer to 20–29. There is a 50% chance of "
        "encountering 1–6 released creatures; a conservative creature raises the "
        "alarm.\n\n"
        "An actual attempt uses up the cage even on failure. Failed attempts trigger "
        "a detection check; successful releases can still create danger through the "
        "creatures and suspicion. Declining or having nobody able to attempt it "
        "leaves the cage available.",
  TileSpecial.labEquipment =>
    "Smash the laboratory equipment for 5 Juice (cap 200) and an animal-research "
        "opinion effect.\n\n"
        "The opinion effect has strength 2 before public-interest and LCS-support "
        "filtering. This applies in genetics labs too; it does not directly change "
        "genetics opinion or research law.\n\n"
        "Cost and risk: no skill check is needed to smash it. The tile is used up and "
        "left with debris, adds 2 site crime and possible vandalism charges, sets or "
        "shortens the suspicion timer to 20–29, and triggers a Heroic detection "
        "check.",
  TileSpecial.sweatshopEquipment =>
    "Smash the production equipment for 5 Juice (cap 200) and a vandalism news "
        "event.\n\n"
        "The direct reward is Juice. Any labour-opinion effect comes through "
        "operation coverage; smashing this tile does not directly raise wages or "
        "change working conditions.\n\n"
        "Cost and risk: no skill check is needed to smash it. The tile is used up and "
        "left with debris, adds 2 site crime and possible vandalism charges, sets or "
        "shortens the suspicion timer to 20–29, and triggers a Heroic detection "
        "check.",
  TileSpecial.polluterEquipment =>
    "Smash the industrial equipment for 5 Juice (cap 200) and a pollution-opinion "
        "effect.\n\n"
        "The opinion effect has strength 2 before public-interest and LCS-support "
        "filtering. It does not immediately change pollution law.\n\n"
        "Cost and risk: no skill check is needed to smash it. The tile is used up and "
        "left with debris, adds 2 site crime and possible vandalism charges, sets or "
        "shortens the suspicion timer to 20–29, and triggers a Heroic detection "
        "check.",
  TileSpecial.displayCase =>
    "Smash the display case for 5 Juice (cap 200) and a vandalism news event.\n\n"
        "Smashing the display does not provide valuable loot.\n\n"
        "Cost and risk: no skill check is needed to smash it. The tile is used up and "
        "left with debris, adds 2 site crime and possible vandalism charges, sets or "
        "shortens the suspicion timer to 20–29, and triggers a Heroic detection "
        "check.",
  TileSpecial.intelSupercomputer =>
    "Use Heroic Computers to steal an intelligence disk; an active alarm prevents "
        "hacking.\n\n"
        "Success gives 50 Juice (cap 1,000). If the CCS is active and its government "
        "backers are undiscovered, also obtain their backer list and advance that "
        "investigation.\n\n"
        "An actual attempt uses up the computer even on failure, triggers a detection "
        "check, adds 3 site crime and possible treason charges. No eligible hacker or "
        "declining leaves it available. Bring evidence home for a separate Guardian "
        "publication; publishing intelligence evidence also risks treason and "
        "retaliation.",
  TileSpecial.radioBroadcastStudio || TileSpecial.cableBroadcastStudio =>
    "Take over the studio to broadcast on a random issue; starting always raises "
        "the alarm.\n\n"
        "Any living conservative in the current encounter blocks the show. Otherwise "
        "performance uses the living squad’s Intelligence, Heart, Charisma, Music, "
        "Religion, Science, Business and Persuasion, with a squad-size bonus. Each "
        "participant trains Persuasion by 50.\n\n"
        "A completed show increases LCS recognition and affects approval, the random "
        "issue and free-speech opinion; poor reception can backfire. Carrying a "
        "currently legal gun also affects gun-control opinion. Forcing a conservative "
        "host from this medium on air boosts performance and another issue, but risks "
        "terrorism charges. A completed broadcast adds possible disturbing-the-peace "
        "and unlawful-speech charges, and uses up the studio. Security may confront "
        "you afterwards. If conservatives prevent the show, the studio remains "
        "available but the alarm stays raised.",
  TileSpecial.armory =>
    "Break into weapons storage: the alarm always sounds and armed defenders "
        "always arrive.\n\n"
        "Loot can include rifles, spare magazines and armour. At an army base, the "
        "first haul includes the M250 with nine spare magazines if not already found. "
        "A nonempty haul gives 50 Juice (cap 1,000), adds 40 site crime and possible "
        "theft and treason charges.\n\n"
        "A later armory can be empty; that still risks treason. Expect 2–5 defenders "
        "after a haul or 4–9 if empty: soldiers at an army base, mercenaries "
        "elsewhere. Agreeing uses up the armory; declining leaves it available.",
  TileSpecial.bankVault =>
    "Open three locks in sequence: Heroic Security, Hard Computers, then "
        "recognized bank-manager biometrics.\n\n"
        "Biometrics: bring a bank-manager recruit who joined fewer than 30 days ago "
        "and was not kidnapped, carry a bank-manager hostage, or use a bank-manager "
        "sleeper based at this bank. Using the sleeper exposes them, gives them a "
        "bank-robbery charge and returns them to active duty at your base.\n\n"
        "Success adds 20 site crime and possible bank-robbery charges; collect cash "
        "separately. A failed lock check uses up the vault and triggers detection. "
        "Missing biometrics leaves it available, but still triggers detection; a "
        "later attempt repeats the checks. Declining leaves it available.",
  TileSpecial.bankMoney =>
    "Take a cash pile to add \$20,000 to squad loot; escape with it to fund the "
        "movement.\n\n"
        "Each pile is used up and adds 20 site crime. Collection can start or "
        "accelerate the alarm response. At a late alarm stage it can bring "
        "nine-person SWAT teams, up to two through this cash-collection mechanic. "
        "Taking cash is not an immediate deposit into LCS funds.",
  TileSpecial.bankTeller =>
    "Meet a teller while the bank is calm.\n\n"
        "During an alarm or siege the window is empty. This is a normal person "
        "encounter; meeting the teller does not give cash or replace the bank-manager "
        "biometrics required by the vault. Entering uses up the teller interaction.",
  TileSpecial.policeStationLockup || TileSpecial.courthouseLockup =>
    "Open the cells with Formidable Security to meet prisoners and recover your "
        "detained crew at this site.\n\n"
        "Success gives 50 Juice (cap 1,000), generates 2–9 prisoner NPCs and sets or "
        "shortens the suspicion timer to 20–29. Your detained members can rejoin free "
        "squad slots or be carried; available carriers and space limit rescues. "
        "Recovered crew gain an escaping-prison charge and still need to escape.\n\n"
        "An actual attempt uses up the lockup even on failure, triggers a Hard "
        "detection check and risks aiding-escape charges. Success adds 20 site crime, "
        "plus the attempt’s 2 at a police station or 3 at a courthouse. New prisoner "
        "NPCs use normal encounter interactions; they are not automatically "
        "recruited.",
  TileSpecial.prisonControl ||
  TileSpecial.prisonControlLow ||
  TileSpecial.prisonControlMedium ||
  TileSpecial.prisonControlHigh =>
    "Release prisoners without a lockpicking check and recover your jailed crew "
        "from this wing.\n\n"
        "Your crew: low security holds fixed sentences, medium holds life sentences, "
        "high holds death row. Free squad slots or carriers limit how many you "
        "recover; they gain escaping-prison charges and must escape. Other generated "
        "prisoner NPCs require normal encounter interactions, not automatic "
        "recruitment.\n\n"
        "Reward and risk: 50 Juice (cap 1,000), 30 site crime, possible aiding-escape "
        "charges, a detection check and a suspicion timer of 20–29 if sooner. Current "
        "death-penalty law changes NPC prisoner numbers; high security has none under "
        "Elite Liberal law. Agreeing uses up the control even if nobody is rescued; "
        "declining leaves it available.",
  TileSpecial.courthouseJuryRoom =>
    "Influence a jury with both Hard Persuasion and Challenging Law; an alarm "
        "prevents the attempt.\n\n"
        "The advocate is chosen by combined Charisma, Intelligence, Persuasion and "
        "Law. They train both skills by 50; other living squad members train each by "
        "25. Passing both checks gives the advocate 25 Juice (cap 200, or 1,000 under "
        "Arch-Conservative death-penalty law).\n\n"
        "Passing only one check still risks jury-tampering charges. Failing both also "
        "raises the alarm, adds 10 site crime and confronts you with 12 jurors. Any "
        "accepted attempt uses up the room. The verdict is a generated case, not one "
        "of your crew’s pending trials.",
  TileSpecial.nuclearControlRoom =>
    "Attempt reactor shutdown with Hard Science; under Elite Liberal nuclear law "
        "this instead releases nuclear waste.\n\n"
        "Living squad members try in order until one passes. Ordinary success gives "
        "100 Juice (cap 1,000), applies a strength-15 nuclear-power opinion effect "
        "and adds 50 site crime. If nobody passes, the threatening note still gives "
        "15 Juice (cap 500).\n\n"
        "Waste release instead applies a strength-15 nuclear-power opinion effect and "
        "a severe LCS-approval penalty, loses 40 Juice (floor −50), stuns the "
        "operator for 15 and adds 25 site crime.\n\n"
        "Every accepted attempt uses up the control, raises the alarm, adds a further "
        "5 site crime and possible terrorism charges. Declining leaves the control "
        "available.",
  TileSpecial.securityCheckpoint || TileSpecial.securityMetalDetectors =>
    "Entry checks can block adjacent doors or expose suspicious weapons.\n\n"
        "Without employee access, security checks clothing suitability, blood, "
        "damage, quality and age under 16. Crew based here can supply employee "
        "access; a matching guard working for you can bypass weapon rejection. Metal "
        "detectors are stricter about concealed weapons.\n\n"
        "A suspicious weapon detected by the metal detector raises the alarm, except "
        "under Arch-Conservative gun law. Passing opens adjacent doors; rejection "
        "makes them unpickable through this checkpoint interaction. During an "
        "existing alarm the checkpoint is abandoned.",
  TileSpecial.securitySecondVisit =>
    "This checkpoint has already assessed the squad.\n\n"
        "Revisiting does not repeat the original entry inspection. Doors and any "
        "alarm raised by the first check retain their current state.",
  TileSpecial.clubBouncer =>
    "The bouncer assesses every squad member before admitting the group.\n\n"
        "Entry normally requires age 21 or older, appropriate clean undamaged "
        "top-quality clothing and no suspicious weapons. Non-police outfits can "
        "require Average Disguise; at the bar, trans crew face Hard Disguise under "
        "laws short of Elite Liberal LGBT rights. Arch-Conservative gender law also "
        "excludes women.\n\n"
        "High-security bars enforce a guest list; CCS shelters and bunkers refuse "
        "outsiders. A local matching contact can bypass the assessment. Rejection "
        "locks the adjacent doors; forcing a confrontation can alert the site. "
        "LCS-controlled locations skip the assessment.",
  TileSpecial.clubBouncerSecondVisit =>
    "The bouncer has already assessed the squad.\n\n"
        "Revisiting follows the bouncer’s return interaction; it is not a new "
        "recruitment or reward opportunity. Previous door and alarm consequences "
        "still matter.",
  TileSpecial.apartmentLandlord =>
    "Meet the landlord if alive and present, then use the rental dialogue to "
        "arrange a base.\n\n"
        "Renting commits LCS funds to recurring rent; reading this guide does not "
        "rent anything. High-security landlords who are not liberal bring two "
        "mercenary bodyguards. During a siege, or if the landlord is absent, the "
        "office is unavailable.",
  TileSpecial.computer =>
    "An occupied workstation can provide a person to talk to through normal "
        "encounter rules.\n\n"
        "During an alarm, site alienation or siege the workstation is unavailable. "
        "This ordinary workstation has no insurance-claim or intelligence-file "
        "hacking action. Occupants and availability depend on the current site and "
        "map.",
  TileSpecial.table || TileSpecial.tent =>
    "Outside a siege, an occupied table or tent provides an encounter for normal "
        "conversation and recruitment.\n\n"
        "During an alarm or site alienation the occupants are hiding, but the "
        "encounter still occurs. Tables generate a normal group; tents generate one "
        "person. Entering uses up this interaction. Meeting them does not guarantee "
        "recruitment or an opinion reward.",
  TileSpecial.parkBench =>
    "A park bench can provide an encounter with seated visitors while the site is "
        "calm.\n\n"
        "During an alarm or site alienation the bench is empty. Entering uses up the "
        "interaction. Occupants use normal conversation and recruitment rules; they "
        "do not join automatically.",
  TileSpecial.ccsBoss =>
    "At a CCS-controlled site, encounter a CCS leader; elsewhere the leadership "
        "area is empty.\n\n"
        "A calm encounter has the leader alone. An alarm or siege adds five CCS "
        "vigilantes. Confronting leadership can advance the struggle against the CCS "
        "through the normal combat and campaign systems. Entering alone does not "
        "defeat the faction.",
  TileSpecial.ovalOfficeNW ||
  TileSpecial.ovalOfficeNE ||
  TileSpecial.ovalOfficeSW ||
  TileSpecial.ovalOfficeSE =>
    "Meet the President with two Secret Service guards while the site is calm.\n\n"
        "During an alarm the President is absent and six agents ambush the squad with "
        "an immediate attack. A conservative President you previously held hostage "
        "instead appears with six agents, raises the alarm and attacks immediately.\n\n"
        "Entering uses up the Oval Office encounter. Normal conversation, combat and "
        "conversion rules apply; merely entering does not change laws or replace the "
        "President.",
  TileSpecial.signOne || TileSpecial.signTwo || TileSpecial.signThree =>
    "Read the sign for information about this part of the building.\n\n"
        "Reading is not a rescue, theft or political action and supplies no loot or "
        "Juice reward.",
  TileSpecial.stairsUp || TileSpecial.stairsDown =>
    "Move between floors using the stairs.\n\n"
        "Changing floors continues the current operation; it does not end the visit "
        "or bank carried loot.",
  TileSpecial.none => null,
};

/// Full mechanics stay in the scrollable expansion, including on small screens.
String? locationFeatureSummary(TileSpecial feature) =>
    locationFeatureHelp(feature)?.split('\n\n').first;
