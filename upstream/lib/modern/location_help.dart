import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/site.dart';

/// General knowledge about a building, not its generated rooms or occupants.
String locationPurpose(SiteType type) => switch (type) {
  SiteType.clinic =>
    'Free inpatient medical care for wounded crew. Visiting opens admission options.',
  SiteType.universityHospital =>
    'Inpatient hospital care for wounded crew. Treatment can generate law-dependent medical bills.',
  SiteType.pawnShop =>
    'Buy equipment or sell unwanted items. Stock follows current laws.',
  SiteType.departmentStore => 'Shop for clothing and supplies.',
  SiteType.oubliette => 'Specialist clothing and equipment shop.',
  SiteType.armsDealer => 'Black-market weapons and ammunition.',
  SiteType.carDealership =>
    'Buy a used car for squad transport or sell the buyer’s assigned vehicle.',
  SiteType.homelessEncampment =>
    'A place to shelter the crew and meet people living on the streets.',
  SiteType.tenement =>
    'Low-income housing. A place to meet residents or arrange a base.',
  SiteType.apartment =>
    'Residential apartments. A place to meet residents or arrange a base.',
  SiteType.upscaleApartment => 'Wealthy residents and private apartments.',
  SiteType.bombShelter ||
  SiteType.bunker => 'Sheltered premises that can serve as a crew base.',
  SiteType.warehouse => 'Abandoned premises that can serve as a crew base.',
  SiteType.cosmeticsLab =>
    'Cosmetics research and animal-testing facilities. A target for an animal-rights operation.',
  SiteType.geneticsLab =>
    'Genetics research facilities. A target for an operation focused on genetic research.',
  SiteType.policeStation =>
    'Police offices and detention facilities. An operation here risks confrontation with police.',
  SiteType.courthouse =>
    'Courts and legal offices. A target for an operation focused on the justice system.',
  SiteType.prison =>
    'Incarcerated people and prison staff. Restricted access and guarded facilities.',
  SiteType.intelligenceHQ =>
    'Intelligence agency offices. Restricted access and guarded facilities.',
  SiteType.fireStation => 'Firefighters and emergency-service facilities.',
  SiteType.sweatshop =>
    'Garment workers and factory facilities. A target for a workers’ rights operation.',
  SiteType.dirtyIndustry =>
    'Industrial workers and factory facilities. A target for an environmental operation.',
  SiteType.nuclearPlant =>
    'Nuclear power facilities. Restricted access and guarded areas.',
  SiteType.corporateHQ =>
    'Corporate staff and business offices. A target for an operation against corporate power.',
  SiteType.ceoHouse =>
    'A corporate leader’s private residence. Expect restricted access.',
  SiteType.amRadioStation =>
    'Radio staff and broadcasting facilities. A target for a media operation.',
  SiteType.cableNewsStation =>
    'News staff and television facilities. A target for a media operation.',
  SiteType.drugHouse =>
    'Premises associated with drug dealing. Entering can lead to confrontation.',
  SiteType.juiceBar => 'A public social venue where the crew can meet people.',
  SiteType.latteStand => 'A coffee venue where the crew can meet people.',
  SiteType.veganCoOp =>
    'A community food co-op where the crew can meet people.',
  SiteType.internetCafe =>
    'A public internet café where the crew can meet people.',
  SiteType.barAndGrill =>
    'A bar and grill with a conservative clientele. An operation can lead to confrontation.',
  SiteType.publicPark =>
    'A public gathering place where the crew can meet people.',
  SiteType.armyBase =>
    'Military personnel and facilities. Restricted access and armed security.',
  SiteType.bank =>
    'Bank staff and financial facilities. Public areas and secured private areas.',
  SiteType.insuranceOffice =>
    'Insurance staff and offices. A target for an operation focused on health insurance.',
  SiteType.nursingHome =>
    'Residents and care staff. A target for an operation focused on elder care.',
  SiteType.liberalPartyHQ =>
    'Political premises with ordinary encounters and conversation options.',
  SiteType.whiteHouse =>
    'Government offices and protected leadership. Restricted access and armed security.',
  SiteType.downtown =>
    'Central city offices and institutions. Open the district to inspect known buildings.',
  SiteType.commercialDistrict =>
    'Shops and businesses. Open the district to inspect known buildings.',
  SiteType.universityDistrict =>
    'Campus, medical and social venues. Open the district to inspect known buildings.',
  SiteType.industrialDistrict =>
    'Factories and industrial premises. Open the district to inspect known buildings.',
  SiteType.outOfTown =>
    'Places outside the city centre. Travel may require a car.',
};

String locationAccess(Site site) {
  final notes = <String>[
    if (site.isClosed) 'Closed to visits',
    if (site.siege.underSiege) 'Under siege',
    if (site.isSafehouse) 'LCS safehouse',
    if (site.hasHighSecurity) 'High security',
  ];
  if (notes.isNotEmpty) return notes.join(' · ');
  return switch (site.type) {
    SiteType.downtown ||
    SiteType.commercialDistrict ||
    SiteType.universityDistrict ||
    SiteType.industrialDistrict ||
    SiteType.outOfTown => 'District · Choose a building',
    SiteType.clinic || SiteType.universityHospital => 'Treatment visit',
    SiteType.pawnShop ||
    SiteType.departmentStore ||
    SiteType.oubliette ||
    SiteType.armsDealer ||
    SiteType.carDealership => 'Shopping visit',
    SiteType.publicPark ||
    SiteType.juiceBar ||
    SiteType.latteStand ||
    SiteType.veganCoOp ||
    SiteType.internetCafe =>
      'Public venue · Actions can still attract attention',
    _ => 'Site operation · Private areas may be restricted',
  };
}
