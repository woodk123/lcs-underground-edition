import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/sitemode/sitemap.dart';

/// General knowledge, never a forecast made by running an action or a game roll.
/// Sources: sitemode/map_specials.dart, sitemode/sitemode.dart (operation exit),
/// sitemode/miscactions.dart (broadcasts), newspaper/run_news_cycle.dart,
/// politics/politics.dart and monthly/lcs_monthly.dart (evidence editions).
({String opportunities, String risks}) locationEffects(
  SiteType type,
) => switch (type) {
  SiteType.insuranceOffice => (
    opportunities:
        'Approve denied medical claims at terminals to earn Juice and improve healthcare opinion and LCS approval. Recover fraud evidence for a Liberal Guardian special edition.',
    risks:
        'Claim approval can fail and uses up the terminal attempt. Stealing records risks detection and theft charges. Neither action reduces your crew’s medical bills or directly changes healthcare law.',
  ),
  SiteType.nursingHome => (
    opportunities:
        'Help residents to earn Juice and improve elder-care opinion and LCS approval. Recover evidence of abuse for a Liberal Guardian special edition.',
    risks:
        'Resident care can fail and is unavailable during an alarm. Stealing evidence risks detection and theft charges; frightening or hurting residents can turn people against you.',
  ),
  SiteType.cosmeticsLab => (
    opportunities:
        'Free caged rabbits for Juice and an animal-rescue news story. Destroying lab equipment also affects animal-research opinion.',
    risks:
        'Opening cages and wrecking equipment attract suspicion. Destruction risks vandalism charges; publicity can help or hurt your cause.',
  ),
  SiteType.geneticsLab => (
    opportunities:
        'Free captive creatures for Juice and a rescue news story. Operations here can influence opinion about genetic research.',
    risks:
        'Released creatures can be hostile. Breaking cages and equipment attracts suspicion; lab destruction affects animal-research opinion and risks vandalism charges.',
  ),
  SiteType.sweatshop => (
    opportunities:
        'Meet garment workers; destroying production equipment earns Juice. News coverage can influence labour and immigration opinion.',
    risks:
        'Equipment destruction attracts suspicion and risks vandalism charges. It does not directly raise wages or improve working conditions.',
  ),
  SiteType.dirtyIndustry => (
    opportunities:
        'Destroy industrial equipment for Juice and an immediate effect on pollution opinion. Coverage can also influence labour issues.',
    risks:
        'Sabotage attracts suspicion and risks vandalism charges. It does not directly change pollution law; violence can damage public support.',
  ),
  SiteType.nuclearPlant => (
    opportunities:
        'A successful reactor shutdown earns Juice and shifts nuclear-power opinion. An armory may provide equipment.',
    risks:
        'Reactor tampering always raises the alarm and risks terrorism charges. Under the most liberal nuclear law, the control instead releases waste: success costs Juice and sharply reduces LCS approval.',
  ),
  SiteType.policeStation || SiteType.courthouse => (
    opportunities:
        'Free detainees for Juice and a chance to bring escapees with you. Evidence and operation coverage can support justice-related campaigns; courthouses also offer jury influence.',
    risks:
        'Rescues attract suspicion and risk aiding-escape charges. Failed jury influence can lead to jury-tampering charges or an alarm. Armed responses make an escape plan important.',
  ),
  SiteType.prison => (
    opportunities:
        'Use control rooms to release prisoners for Juice and a chance to bring escapees with you. Operation coverage can influence prison, death-penalty and torture issues.',
    risks:
        'Releasing prisoners attracts suspicion and risks aiding-escape charges. Security wings and current law affect who can be rescued; you still need to escape armed guards.',
  ),
  SiteType.intelligenceHQ => (
    opportunities:
        'Hack the supercomputer for intelligence files, Juice and, when available, evidence of CCS backers. Recovered evidence can support publication.',
    risks:
        'An alarm disables the supercomputer. Hacking risks detection and treason charges; security can make carrying the evidence out difficult.',
  ),
  SiteType.corporateHQ || SiteType.ceoHouse => (
    opportunities:
        'Recover private documents for publication; a CEO safe may also contain cash and valuables. Operations can influence corporate or executive-pay issues.',
    risks:
        'Safe contents vary. Breaking in and taking records risks detection and theft charges; violent publicity can reduce support for the LCS.',
  ),
  SiteType.amRadioStation || SiteType.cableNewsStation => (
    opportunities:
        'Use a studio to reach an audience with a broadcast. Recover media files for publication; coverage can affect media and civil-rights issues.',
    risks:
        'Broadcast results depend on squad skills and audience reception. Taking over the studio raises the alarm and risks speech-related charges; a poor performance can backfire.',
  ),
  SiteType.bank => (
    opportunities:
        'Open the vault and carry out cash to fund the movement. The vault needs Security, Computers and a recognized bank manager’s biometrics.',
    risks:
        'Vault entry risks bank-robbery charges. Taking cash accelerates the alarm response and can bring SWAT teams; a sleeper manager who opens the vault loses their cover.',
  ),
  SiteType.armyBase || SiteType.whiteHouse => (
    opportunities:
        'Recover sensitive documents or equipment. The White House also offers an encounter with the President if security conditions allow.',
    risks:
        'Expect armed resistance. Armory raids always raise the alarm and risk treason charges; the President’s office can become a Secret Service ambush during an alarm.',
  ),
  SiteType.clinic || SiteType.universityHospital => (
    opportunities:
        'Arrange treatment so wounded crew can recover. The clinic and university hospital use different treatment and billing rules.',
    risks:
        'Admitted patients remain away from active duties until discharged. Hospital charges depend on current law; inspect the treatment offer before committing.',
  ),
  SiteType.pawnShop ||
  SiteType.departmentStore ||
  SiteType.oubliette ||
  SiteType.armsDealer ||
  SiteType.carDealership => (
    opportunities:
        'Spend movement funds on supplies or transport; services and any resale options are shown on arrival.',
    risks:
        'Purchases cost money, and stock or eligibility can depend on current law. A shopping visit does not itself change political opinion.',
  ),
  SiteType.tenement || SiteType.apartment || SiteType.upscaleApartment => (
    opportunities:
        'Meet residents and discuss a rental with the landlord. Recovered documents and operation coverage can support housing-related campaigns.',
    risks:
        'Rent creates an ongoing expense. Trespass, theft and violence risk detection and charges; harming residents can undermine public support.',
  ),
  SiteType.warehouse || SiteType.drugHouse => (
    opportunities:
        'These premises can become a base. Sufficient disruption during an operation can secure an unaligned warehouse or drug house for the LCS.',
    risks:
        'Taking a site can involve armed confrontation and leaves heat at the new base. Occupying a building does not make it safe from raids.',
  ),
  SiteType.bombShelter || SiteType.bunker || SiteType.barAndGrill => (
    opportunities:
        'Meet occupants or confront CCS leadership when the site is CCS-controlled. Some premises can serve as a base once available.',
    risks:
        'Bouncers may refuse entry, and an alerted CCS leader can have reinforcements. Confrontation, theft and destruction can provoke violence or charges.',
  ),
  _ => (
    opportunities:
        'Meet people for conversation and possible recruitment. Success depends on the person, your approach and the squad’s skills.',
    risks:
        'A public visit is not automatically a crime. Trespass, theft and violence can attract attention, alienate people and lead to arrest.',
  ),
};

const locationOperationConsequences =
    'News coverage can help or hurt public support, depending on your actions '
    'and how they are reported. Serious disruption can temporarily close a '
    'site or increase security on later visits. Opinion changes do not '
    'immediately change laws.';

/// Descriptions of the original facility handlers, not guaranteed map contents.
String? locationFeatureHelp(TileSpecial feature) => switch (feature) {
  TileSpecial.insuranceClaimsTerminal =>
    'Override a denied medical claim with an average Computers check. '
        'Success awards 5 Juice (cap 200) and improves LCS approval. Its '
        'healthcare-opinion effect depends on public interest and LCS support. '
        'The hacker trains Computers on either result. '
        'Success or failure uses up this terminal; declining leaves it available. '
        'The override itself adds no alarm or criminal charge and does not pay your crew’s medical bills.',
  TileSpecial.insuranceFiles =>
    'Crack the records safe to recover insurance-fraud evidence and earn Juice. '
        'Bring the evidence home for a Liberal Guardian special edition; '
        'taking it does not publish it. The attempt risks detection, and '
        'successful theft adds crime and possible theft charges.',
  TileSpecial.nursingHomeFiles =>
    'Crack the records safe for elder-abuse evidence and Juice. Bring it home '
        'for a Liberal Guardian special edition. The attempt risks detection; '
        'successful theft adds crime and possible theft charges.',
  TileSpecial.corporateFiles =>
    'Crack the safe to recover corporate files for publication and earn Juice. '
        'An attempted break-in risks detection and theft charges; recovering '
        'the files adds substantial site crime. Publication is a separate decision.',
  TileSpecial.ceoSafe =>
    'Crack the safe for a chance at money, valuables, a weapon or private '
        'documents. Contents vary and can be empty. Taking contents earns '
        'Juice but adds site crime and possible theft charges; the attempt risks detection.',
  TileSpecial.insuranceCEO || TileSpecial.ceoOffice =>
    'An encounter with the company’s leader, if present. Entering does not '
        'automatically reform the company. A conservative leader you previously '
        'held hostage can recognize the squad and call armed help.',
  TileSpecial.nursingHomeManager =>
    'Meet the administrator if present. This is a conversation or confrontation, '
        'not an automatic improvement in care. A conservative former hostage '
        'can recognize you and call for help.',
  TileSpecial.nursingHomePatient =>
    'Try to help a resident using the skill their situation needs. Success '
        'earns Juice and improves elder-care opinion and LCS approval; failure '
        'still trains the helper. One care attempt per resident; an alarm prevents care.',
  TileSpecial.nursingHomePatientDone =>
    'This resident has already had a care attempt. Revisiting does not grant another reward.',
  TileSpecial.cagedRabbits =>
    'Open the cage to free laboratory rabbits. Success earns Juice and adds '
        'an animal-rescue event to the operation’s news story. It also adds '
        'site crime and starts a suspicion countdown; opening the cage can be noticed.',
  TileSpecial.cagedMonsters =>
    'Open a difficult cage to free genetically altered creatures. Success '
        'earns Juice and a rescue news event, but adds site crime and suspicion. '
        'The released creatures may appear and can be hostile.',
  TileSpecial.labEquipment =>
    'Destroying the equipment earns Juice and affects animal-research opinion. '
        'It leaves debris, starts suspicion and risks detection and vandalism charges. '
        'It does not directly change research law.',
  TileSpecial.sweatshopEquipment =>
    'Destroying production equipment earns Juice and creates a vandalism news '
        'event. It leaves debris, starts suspicion and risks detection and '
        'vandalism charges. It does not directly raise workers’ wages.',
  TileSpecial.polluterEquipment =>
    'Destroying industrial equipment earns Juice and affects pollution opinion. '
        'It leaves debris, starts suspicion and risks detection and vandalism '
        'charges. It does not directly change pollution law.',
  TileSpecial.intelSupercomputer =>
    'Hack for intelligence files and Juice, plus CCS-backer evidence when that '
        'story is available. An alarm disables the computer. An attempt risks '
        'detection and treason charges; bring recovered files home for publication.',
  TileSpecial.radioBroadcastStudio || TileSpecial.cableBroadcastStudio =>
    'Take over the studio to broadcast to its audience. Reception depends on '
        'the squad’s performance and skills: a strong broadcast can improve '
        'opinion, while a poor one can backfire. Taking over always raises '
        'the alarm and risks speech-related charges; security may be waiting afterwards.',
  TileSpecial.armory =>
    'Breaking in always raises the alarm. You may find weapons, ammunition '
        'and armor, earning Juice but risking theft and treason charges. '
        'The armory can be empty, and armed defenders can arrive.',
  TileSpecial.bankVault =>
    'Opening the vault requires Security and Computers checks, then recognized '
        'bank-manager biometrics. A qualifying recruit, hostage or local sleeper '
        'can supply access. Success risks bank-robbery charges; using a sleeper '
        'exposes them and returns them to active duty. The cash must still be collected.',
  TileSpecial.bankMoney =>
    'Each cash pile adds \$20,000 to squad loot and increases site crime. '
        'Taking cash starts or accelerates the alarm response and can bring '
        'SWAT teams. You still need to escape with the loot.',
  TileSpecial.bankTeller =>
    'Meet a teller while the bank is calm. During an alarm or siege the '
        'window is empty. This encounter does not itself open the vault or give money.',
  TileSpecial.policeStationLockup || TileSpecial.courthouseLockup =>
    'Open the cells to meet and potentially rescue detainees, earning Juice. '
        'An attempt risks detection and aiding-escape charges; success adds '
        'site crime and starts a suspicion countdown. You must still get out.',
  TileSpecial.prisonControl ||
  TileSpecial.prisonControlLow ||
  TileSpecial.prisonControlMedium ||
  TileSpecial.prisonControlHigh =>
    'Release prisoners for a rescue opportunity and Juice. Prisoner numbers '
        'depend on the security wing and current death-penalty law. Releasing '
        'them adds site crime, starts suspicion and risks aiding-escape charges.',
  TileSpecial.courthouseJuryRoom =>
    'Try to influence a jury with Persuasion and Law. Success earns Juice; '
        'the attempt trains both skills. Failure risks jury-tampering charges, '
        'and failing both checks raises the alarm. The room is vacated during an alarm.',
  TileSpecial.nuclearControlRoom =>
    'Reactor tampering needs a hard Science check. A shutdown earns Juice '
        'and shifts nuclear-power opinion. Under the most liberal nuclear law, '
        'success releases waste instead, costing Juice and sharply reducing LCS approval. '
        'Any attempt raises the alarm and risks terrorism charges.',
  TileSpecial.displayCase =>
    'Smash the display for Juice and a vandalism news event. This leaves '
        'debris, starts suspicion and risks detection and vandalism charges; '
        'it does not supply valuable loot.',
  TileSpecial.securityCheckpoint || TileSpecial.securityMetalDetectors =>
    'Security assesses entry and can detect suspicious equipment. A failed '
        'inspection can block access or trigger a confrontation. Metal '
        'detectors make carrying weapons through especially risky.',
  TileSpecial.clubBouncer =>
    'The bouncer assesses the squad before admitting you. Entry can be '
        'refused; pushing a confrontation can alert the people inside.',
  TileSpecial.apartmentLandlord =>
    'Discuss renting an apartment with the landlord. Accepting creates a '
        'base and an ongoing rent obligation; inspecting the location guide does not rent anything.',
  TileSpecial.computer =>
    'An occupied workstation can generate a person to talk to. During an '
        'alarm or after alienating the site, it is unplugged. This is not '
        'the insurance-claim or intelligence-hacking interaction.',
  TileSpecial.table || TileSpecial.tent || TileSpecial.parkBench =>
    'Occupants can generate an encounter for conversation or recruitment. '
        'People may hide or leave during an alarm. Meeting them does not '
        'guarantee recruitment or a political benefit.',
  TileSpecial.ccsBoss =>
    'CCS leadership appears only at a CCS-controlled site. An alarm or siege '
        'brings reinforcements. Confronting the leader can advance the fight '
        'against the CCS, but risks armed combat.',
  TileSpecial.ovalOfficeNW ||
  TileSpecial.ovalOfficeNE ||
  TileSpecial.ovalOfficeSW ||
  TileSpecial.ovalOfficeSE =>
    'Meet the President with Secret Service guards if the site is calm. '
        'During an alarm the President is absent and agents ambush the squad. '
        'Entering the office does not itself change laws.',
  _ => null,
};
