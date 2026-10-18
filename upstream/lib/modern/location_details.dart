import 'package:flutter/material.dart';
import 'package:lcs_new_age/creature/creature_type.dart';
import 'package:lcs_new_age/items/item_type.dart';
import 'package:lcs_new_age/location/location_type.dart';
import 'package:lcs_new_age/location/site.dart';
import 'package:lcs_new_age/modern/age_help.dart';
import 'package:lcs_new_age/modern/decision_help.dart';
import 'package:lcs_new_age/modern/equipment_help.dart';
import 'package:lcs_new_age/modern/journal_theme.dart';
import 'package:lcs_new_age/modern/location_catalog.dart';
import 'package:lcs_new_age/modern/location_clothing.dart';
import 'package:lcs_new_age/modern/location_effects.dart';
import 'package:lcs_new_age/modern/location_help.dart';
import 'package:lcs_new_age/modern/skill_help.dart';
import 'package:lcs_new_age/sitemode/newencounter.dart';
import 'package:lcs_new_age/sitemode/shop.dart';
import 'package:lcs_new_age/sitemode/sitemap.dart';
import 'package:lcs_new_age/sitemode/stealth.dart';

String? locationShopId(SiteType type) => switch (type) {
  SiteType.pawnShop => 'PAWNSHOP',
  SiteType.departmentStore => 'DEPARTMENT_STORE',
  SiteType.oubliette => 'OUBLIETTE',
  SiteType.armsDealer => 'ARMSDEALER',
  _ => null,
};

bool locationUsesEncounters(SiteType type) =>
    locationShopId(type) == null &&
    !const {
      SiteType.clinic,
      SiteType.universityHospital,
      SiteType.carDealership,
    }.contains(type);

List<({String id, double chance})> locationPeople(
  Site site, {
  bool publicArea = true,
  bool? highSecurity,
  bool alarm = false,
}) {
  if (!locationUsesEncounters(site.type)) return const [];
  final weights = encounterProfile(
    site.type,
    highSecurity ?? site.hasHighSecurity,
    site: site,
    publicArea: publicArea,
    restrictedArea: !publicArea,
    alarm: alarm,
    alarmTimer: alarm ? 100 : 0,
  ).weights;
  final total = weights.values.fold<int>(0, (sum, weight) => sum + weight);
  if (total == 0) return const [];
  return [
    for (final entry in weights.entries)
      (id: entry.key, chance: entry.value * 100 / total),
  ]..sort((a, b) => b.chance.compareTo(a.chance));
}

String locationPeopleSummary(Site site) {
  final people = locationPeople(site);
  if (people.isEmpty) return 'Visiting opens this location’s services.';
  return 'Likely encounters: ${people.take(3).map((p) => '${creatureTypes[p.id]?.name ?? p.id} ${p.chance.toStringAsFixed(1)}%').join(' · ')}';
}

String _words(String name) => name.replaceAllMapped(
  RegExp(r'([a-z])([A-Z])'),
  (match) => '${match[1]} ${match[2]!.toLowerCase()}',
);

String locationFeatureLabel(TileSpecial feature) => switch (feature) {
  TileSpecial.cagedRabbits => 'Caged laboratory rabbits · animal rescue',
  TileSpecial.cagedMonsters => 'Caged genetically altered creatures',
  TileSpecial.labEquipment => 'Laboratory equipment',
  TileSpecial.sweatshopEquipment => 'Garment-production equipment',
  TileSpecial.polluterEquipment => 'Industrial production equipment',
  TileSpecial.intelSupercomputer =>
    'Intelligence supercomputer · sensitive files',
  TileSpecial.ceoSafe => 'CEO safe · valuables and private documents',
  TileSpecial.corporateFiles => 'Corporate records',
  TileSpecial.radioBroadcastStudio => 'Radio broadcast studio',
  TileSpecial.cableBroadcastStudio => 'Television broadcast studio',
  TileSpecial.armory => 'Armory · weapons storage',
  TileSpecial.bankVault => 'Bank vault',
  TileSpecial.bankMoney => 'Cash storage',
  TileSpecial.computer =>
    'Computers · occupied terminals can generate encounters',
  TileSpecial.table => 'Tables · occupied tables can generate encounters',
  TileSpecial.tent => 'Tents · occupants can generate encounters',
  TileSpecial.parkBench =>
    'Park benches · seated visitors can generate encounters',
  TileSpecial.nursingHomeFiles =>
    'Care records · possible elder-abuse evidence',
  TileSpecial.insuranceFiles => 'Insurance records · possible fraud evidence',
  TileSpecial.insuranceClaimsTerminal => 'Insurance claims terminal',
  TileSpecial.insuranceCEO => 'Insurance CEO',
  TileSpecial.ceoOffice => 'CEO’s office',
  TileSpecial.ovalOfficeNW ||
  TileSpecial.ovalOfficeNE ||
  TileSpecial.ovalOfficeSW ||
  TileSpecial.ovalOfficeSE => 'Oval Office',
  TileSpecial.ccsBoss =>
    'CCS leadership area · relevant to CCS-controlled sites',
  _ => _words(feature.name),
};

Future<void> showLocationDetails(BuildContext context, Site site) =>
    showDialog<void>(
      context: context,
      builder: (_) => _LocationDetails(site: site),
    );

class _LocationDetails extends StatefulWidget {
  const _LocationDetails({required this.site});
  final Site site;
  @override
  State<_LocationDetails> createState() => _LocationDetailsState();
}

class _LocationDetailsState extends State<_LocationDetails> {
  int _area = 0;
  late bool _security = widget.site.hasHighSecurity;

  Widget _heading(String text) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 6),
    child: Text(text, style: JournalPalette.heading.copyWith(fontSize: 16)),
  );

  @override
  Widget build(BuildContext context) {
    final site = widget.site;
    final people = locationPeople(
      site,
      publicArea: _area == 0,
      highSecurity: _security,
      alarm: _area == 2,
    );
    final features = <String, TileSpecial>{
      for (final feature
          in locationFeatureCatalog[site.type] ?? const <TileSpecial>[])
        locationFeatureLabel(feature): feature,
    };
    final effects = locationEffects(site.type);
    final publicClothing = locationClothing(site, restricted: false);
    final restrictedClothing = locationClothing(site, restricted: true);
    final sameClothing =
        publicClothing.length == restrictedClothing.length &&
        Iterable.generate(publicClothing.length).every(
          (i) => publicClothing[i].quality == restrictedClothing[i].quality,
        );
    final loot = locationLootCatalog[site.type] ?? const <String>[];
    final shop = shopTypes[locationShopId(site.type)];
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 8, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(site.getName(), style: JournalPalette.heading),
                  ),
                  IconButton(
                    tooltip: 'Close location details',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                key: PageStorageKey('location-guide-scroll:${site.idString}'),
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      locationPurpose(site.type),
                      style: JournalPalette.body,
                    ),
                    const SizedBox(height: 6),
                    Text(locationAccess(site), style: JournalPalette.small),
                    _heading('What your actions can change'),
                    Text(
                      'Opportunities: ${effects.opportunities}',
                      style: JournalPalette.body,
                    ),
                    const SizedBox(height: 8),
                    Text('Risks: ${effects.risks}', style: JournalPalette.body),
                    if (locationUsesEncounters(site.type)) ...[
                      const SizedBox(height: 8),
                      const Text(
                        locationOperationConsequences,
                        style: JournalPalette.small,
                      ),
                    ],
                    if (site.isSafehouse)
                      Wrap(
                        children: [
                          DecisionGuideButton(
                            topic: DecisionTopic.upgrades,
                            site: site,
                          ),
                          DecisionGuideButton(
                            topic: DecisionTopic.heat,
                            site: site,
                          ),
                        ],
                      ),
                    if (shop != null) ...[
                      _heading('Available stock'),
                      const Text(
                        'Current catalogue and regular prices. Purchase availability follows current laws. Undercover buyers can have different prices.',
                        style: JournalPalette.small,
                      ),
                      ..._stock(shop),
                    ],
                    if (site.type == SiteType.carDealership) ...[
                      _heading('Services'),
                      const Text(
                        'Used-car purchases and vehicle sales. You choose the buyer and vehicle on arrival; prices depend on the vehicle offered.',
                        style: JournalPalette.body,
                      ),
                    ],
                    if (site.type == SiteType.clinic ||
                        site.type == SiteType.universityHospital) ...[
                      _heading('Services'),
                      const Text(
                        'Admission treats all living squad members who need care and removes them from the squad. The free clinic adds no bills; university-hospital charges accrue during treatment according to healthcare law. Discharged crew need reassignment. See the opportunities and risks above.',
                        style: JournalPalette.body,
                      ),
                    ],
                    _heading('Normal clothing and disguises'),
                    const Text(
                      'Current laws and site control apply. Examples assume clean, undamaged, best-quality outfits with their original armor. Clothing fit does not guarantee entry. Expand an area to see all clothing ratings.',
                      style: JournalPalette.small,
                    ),
                    _clothing(
                      sameClothing
                          ? 'Clothing throughout this location'
                          : 'Clothing in public areas',
                      'public',
                      publicClothing,
                    ),
                    if (!sameClothing)
                      _clothing(
                        'Clothing in restricted areas',
                        'restricted',
                        restrictedClothing,
                      ),
                    ExpansionTile(
                      key: PageStorageKey(
                        'location-clothing-limits:${site.idString}',
                      ),
                      tilePadding: EdgeInsets.zero,
                      title: const Text('What can still give you away?'),
                      children: const [
                        Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text(
                            clothingDisguiseLimits,
                            style: JournalPalette.small,
                          ),
                        ),
                      ],
                    ),
                    if (locationUsesEncounters(site.type)) ...[
                      _heading('People and likelihood'),
                      const Text(
                        'Each percentage is the chance of a person type when a random encounter generates. It is not the chance of finding or recruiting that person on this visit. Lists reflect current laws and site control.',
                        style: JournalPalette.small,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final (index, label) in [
                            (0, 'Public areas'),
                            (1, 'Restricted areas'),
                            (2, 'Alarm response'),
                          ])
                            ChoiceChip(
                              label: Text(label),
                              selected: _area == index,
                              onSelected: (_) => setState(() => _area = index),
                            ),
                        ],
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('High-security encounter mix'),
                        subtitle: Text(
                          site.hasHighSecurity
                              ? 'This site currently has high security.'
                              : 'Preview the high-security variation; this site is currently standard security.',
                        ),
                        value: _security,
                        onChanged: (value) => setState(() => _security = value),
                      ),
                      if (people.isEmpty)
                        const Text(
                          'No random people are generated by this encounter mix.',
                        ),
                      for (final person in people)
                        _person(person.id, person.chance),
                      _heading('How encounters occur'),
                      const Text(
                        'During an operation, ordinary encounter checks have a 10% chance; waiting forces a check. After a major alarm response (more than 80 ticks), random checks rise to 20%. An existing encounter blocks a new one. Occupied tables, computers, tents and benches can trigger their own encounters. Siege encounters use separate rules. Some area-specific checks can suppress a generated encounter.',
                        style: JournalPalette.small,
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Recruitment still depends on the person’s alignment, your approach and skills. These percentages describe the pool of people, not recruitment success.',
                        style: JournalPalette.small,
                      ),
                    ],
                    _heading('Facilities and things to look for'),
                    const Text(
                      'Possible features from the location’s map templates. Layout, site control and prior actions can change what is present. This does not reveal the current floor plan. Select a facility for its effects and risks; hover or long-press for a hint.',
                      style: JournalPalette.small,
                    ),
                    if (features.isEmpty)
                      const Text(
                        'No dedicated special facility is listed for this site type.',
                      ),
                    for (final feature in features.values) _facility(feature),
                    if (loot.isNotEmpty) ...[
                      _heading('Possible loose items'),
                      const Text(
                        'Possible items across this site type’s loot rules and law variations. Current laws can exclude listed weapons. Individual finds are not guaranteed, and taking them can attract attention.',
                        style: JournalPalette.small,
                      ),
                      for (final item in loot)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: EquipmentTooltip(
                            type: itemTypes[item],
                            child: Text(
                              '• ${itemTypes[item]?.name ?? item}',
                              style: JournalPalette.body,
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _clothing(String title, String area, List<LocationOutfit> outfits) =>
      ExpansionTile(
        key: PageStorageKey('location-clothing:${widget.site.idString}:$area'),
        tilePadding: EdgeInsets.zero,
        title: Text(title, style: JournalPalette.body),
        subtitle: Text(
          clothingFitSummary(outfits),
          style: JournalPalette.small,
        ),
        children: [
          for (final quality in [
            DisguiseQuality.inconspicuous,
            DisguiseQuality.authorityFigure,
            DisguiseQuality.unusual,
            DisguiseQuality.disturbing,
            DisguiseQuality.trespassing,
            DisguiseQuality.alarming,
          ])
            if (outfits.any((outfit) => outfit.quality == quality))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      clothingFitLabel(quality),
                      style: JournalPalette.small.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      outfits
                          .where((outfit) => outfit.quality == quality)
                          .map((outfit) => outfit.type.name)
                          .toSet()
                          .join(' · '),
                      style: JournalPalette.small,
                    ),
                  ],
                ),
              ),
        ],
      );

  Widget _facility(TileSpecial feature) {
    final label = locationFeatureLabel(feature);
    final help = locationFeatureHelp(feature);
    if (help == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 5),
        child: Text('• $label', style: JournalPalette.body),
      );
    }
    return ExpansionTile(
      key: PageStorageKey(
        'location-facility:${widget.site.idString}:${feature.name}',
      ),
      tilePadding: EdgeInsets.zero,
      title: MechanicsTooltip(
        message:
            '${locationFeatureSummary(feature)}\nExpand for checks, rewards and consequences.',
        excludeFromSemantics: true,
        child: Row(
          children: [
            Expanded(child: Text(label, style: JournalPalette.body)),
            const SizedBox(width: 8),
            const Icon(Icons.info_outline, size: 18),
          ],
        ),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(help, style: JournalPalette.small),
          ),
        ),
      ],
    );
  }

  Widget _person(String id, double chance) {
    final type = creatureTypes[id];
    final skills =
        type?.skillPoints.entries.where((e) => e.value.$2 > 0).toList() ?? [];
    skills.sort((a, b) => b.value.$2.compareTo(a.value.$2));
    return ExpansionTile(
      key: PageStorageKey('location-person:${widget.site.idString}:$id'),
      tilePadding: EdgeInsets.zero,
      title: Row(
        children: [
          Expanded(child: Text(type?.name ?? id)),
          Text('${chance.toStringAsFixed(2)}%', style: JournalPalette.body),
        ],
      ),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              [
                'Typical alignment: ${type?.alignment.name == 'any' ? 'varies' : type?.alignment.name ?? 'unknown'}.',
                if (type != null) 'Age range: ${type.age.$1}–${type.age.$2}.',
                if (type != null && !type.tank) ageRangeHelp(type.age),
                if (skills.isNotEmpty)
                  'Base skills: ${skills.map((e) => '${e.key.displayName} ${e.value.$1}–${e.value.$2}').join(' · ')}.',
                'Individual skills and alignment can be modified when the person is generated.',
              ].join('\n'),
              style: JournalPalette.small,
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _stock(Shop shop, {String path = 'root'}) => [
    if (shop.allowSelling)
      const Text('You can also sell items here.', style: JournalPalette.small),
    for (final item in shop.items.where((item) => item.isAvailable()))
      EquipmentTooltip(
        type: itemTypes[item.itemId],
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(item.description ?? item.itemId),
          trailing: Text('\$${item.price(false)}'),
        ),
      ),
    for (final (index, department) in shop.departments.indexed)
      ExpansionTile(
        key: PageStorageKey(
          'location-shop:${widget.site.idString}:$path/$index',
        ),
        tilePadding: EdgeInsets.zero,
        title: Text(department.description ?? 'Department'),
        children: _stock(department, path: '$path/$index'),
      ),
  ];
}
