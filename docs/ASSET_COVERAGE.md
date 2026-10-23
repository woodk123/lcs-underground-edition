# Asset coverage audit

Portrait expansion, 23 October 2026: the current asset verifier passes with **306 verified files, 125 runtime images, 88 portrait atlases and 1,402 portraits**. The original 378 identities and their artwork remain intact; 1,024 new identities append after them. Flags and catalogue coverage remain 25 flags, 156 paintings and five exclusions. The catalogue reconciliation below records its earlier 21 October baseline and completion.

Audit date: 21 October 2026. This inventory bounds “missing assets” against the game's authored catalogues and existing visual systems. A generic future-content fallback is not evidence of missing shipped art. Artwork is decorative; names, quantities, condition, installed armor, prices, input and random streams remain owned by the engine.

## Completed catalogue coverage

The completion reconciliation on 21 October 2026 found **zero missing required catalogue illustrations**. The production resolver, its supplemental map and provenance agree on all **156 distinct asset/crop pairs**: 145 equipment types and 11 vehicles. The 113 added equipment paintings occupy eight new transparent runtime atlases, with source masters and generation prompts retained. There are no duplicate type IDs, no shared crop identities and no paintings assigned to the five explicit exclusions.

This was independently checked by extracting the existing renderer ID/rectangle arrays and supplemental `CatalogueArtEntry` records, then comparing every exact type ID, runtime path and crop tuple against provenance. The authored XML catalogue IDs also agree with the coverage inventory. The original missing list below remains an explicitly historical baseline.

The completion asset verifier passed with **177 verified files, 61 runtime images, 24 portrait atlases, 378 portraits, 25 flags, 156 catalogue paintings and five exclusions**. It now enforces authored-catalogue inventory equality, the exact exclusion set, unique complete painting coverage, valid crops and matching source/runtime provenance. Final visual and interaction acceptance remains the QA agent's separate decision; this audit establishes coverage and mapping correctness.

## Definitive catalogue requirements

[`assets/catalogue/coverage.json`](../assets/catalogue/coverage.json) lists all 150 authored equipment IDs and all 11 vehicle IDs, including inherited clothing names. Its `baseline_status` records the start of this task; it is not a claim about the final renderer. `illustration_required` is the enduring coverage requirement. New content must update the inventory and pass the coverage regression.

| Catalogue | Authored IDs | Required illustrations | Initially illustrated | Initially missing |
|---|---:|---:|---:|---:|
| Weapons | 45 | 41 | 16 | 25 |
| Clothing | 64 | 63 | 10 | 53 |
| Ammunition | 9 | 9 | 2 | 7 |
| Loot | 32 | 32 | 4 | 28 |
| Vehicles | 11 | 11 | 11 | 0 |
| Total | 161 | 156 | 43 | 113 |

At baseline `python scripts/verify_assets.py` passed: 148 referenced files, 53 runtime images, 24 portrait atlases, 378 portraits and 25 flags. The 113 gaps were supported text-only item rows in `equipmentArtwork`, rather than broken asset file references. `upstream/lib/modern/catalogue_art.dart` is the production resolver; `assets/catalogue/provenance.json` supplies art geometry/provenance. Its callers include inventory/shop/sale rows, dossiers and comparison guides.

### Explicit equipment exclusions

- `WEAPON_NONE`: no held weapon.
- `CLOTHING_NONE`: no clothing.
- `WEAPON_BITE`, `WEAPON_PROBOSCIS`, `WEAPON_FIRE_BREATH`: intrinsic creature attacks, rather than independent held objects.

`WEAPON_120MM_CANNON` remains required: it is a tangible tank-mounted weapon even though people cannot carry it. Unknown future IDs retain text until explicitly authored. `CLOTHING_BLACKSUIT_AGENT` inherits its Black Suit name from `CLOTHING_BLACKSUIT`; it is a real, separate catalogue ID.

### Armor configurations

The 14 `armor_upgrades.xml` IDs are recorded separately in the JSON. They are configurations on clothing, not independent `ItemType` inventory records. `ARMOR_NONE` and `ARMOR_COSMETIC` expressly do not imply protective equipment. The tailoring/detail UI owns their names and actual protection; `PortraitAppearance.fromPerson` reflects visible armor. A base clothing painting cannot promise which optional armor is installed. Dedicated configuration illustrations are outside this item-type audit.

## Other visual systems

| System | Audit result | Authority / intentional treatment |
|---|---|---|
| Buildings | All 41 building SiteTypes have dedicated cells | `journal_site_art.dart`; `journal_site_art_test.dart` checks exact enum coverage. The five district SiteTypes use district/city illustrations. |
| Orders | All 36 ActivityTypes have a painting | `journal_order_icon.dart`; Visit uses the city painting; recruiting uses personnel art. Shared paintings represent related activities. |
| Tactical fixtures | All tangible TileSpecial fixtures map to object sprites | `tactical_snapshot.dart` `_objectSprite`. No fixture sprite for `none`, stairs, club bouncers or CCS boss: stairs use Canvas symbols and encounter/person markers use their authored symbols. Unsearched loot and mixed dropped piles use crates; already-created single-type dropped piles use catalogue artwork. Tile details show actual dropped stacks and their thumbnails without generating unsearched contents. |
| Tactical surfaces and hazards | Existing terrain/object/hazard atlases retained | `tactical_art.dart`, `tactical_symbols.dart`, `tactical_map.dart`; doors, exits, stairs, units, fog, movement cues and graffiti use Canvas artwork. Unknown tiles intentionally expose no sprite metadata. |
| Portraits | 1,402 persistent portrait IDs in 88 atlases | The original 378 identities are preserved; 1,024 new identities append from ID378. Three manifests retain source/runtime provenance. Portrait clothing deliberately uses eight appearance classes and injury/helmet/face-covering overlays; it does not require 63 separate portraits per person. Saved portrait IDs must never be renumbered. |
| Flags | All 25 catalogue SVGs exist; no orphan SVGs | `verify_assets.py` compares `flags.xml` with shipped files. |
| Journal, city, medical and platform resources | No broken manifest references found | Existing runtime/source hashes, metadata, fonts and atlases are checked by the asset verifier. Live prose, statistics, controls and notices are not missing sprites. |

This audit does not claim that every prose event needs its own illustration, or that every possible character/outfit combination has a bespoke painting. It identifies all gaps in the established catalogue illustration system and all explicit visual fallbacks in the other authored systems.

## Original missing list

The following exact IDs were missing at baseline. Keep this list as task provenance after adding their runtime mappings.

### Weapons (25)

| Type ID | Catalogue name |
|---|---|
| `WEAPON_22_HANDGUN` | .22 Pistol |
| `WEAPON_22_SMG` | .22 SMG |
| `WEAPON_44_REVOLVER` | .44 Magnum |
| `WEAPON_45_HANDGUN` | .45 Pistol |
| `WEAPON_AA12` | AA-12 Auto Shotgun |
| `WEAPON_M4` | M4 Carbine |
| `WEAPON_M7` | M7 Rifle |
| `WEAPON_FLAMETHROWER` | M2 Flamethrower |
| `WEAPON_MOLOTOV` | Molotov Bomb |
| `WEAPON_CHAIN` | Chain |
| `WEAPON_CROSS` | Silver Cross |
| `WEAPON_DAGGER` | Dagger |
| `WEAPON_GAVEL` | Gavel |
| `WEAPON_BANJO` | Banjo |
| `WEAPON_HAMMER` | Dwarven Hammer |
| `WEAPON_MAUL` | Maul of Anrin |
| `WEAPON_NIGHTSTICK` | Steel Baton |
| `WEAPON_PITCHFORK` | Pitchfork |
| `WEAPON_SHANK` | Shank |
| `WEAPON_STAFF` | Wizard's Staff |
| `WEAPON_DAISHO` | Daisho |
| `WEAPON_SWORD` | Zweihänder |
| `WEAPON_SYRINGE` | Syringe |
| `WEAPON_TORCH` | Torch |
| `WEAPON_120MM_CANNON` | 120mm Gun |

### Clothing (53)

| Type ID | Catalogue name |
|---|---|
| `CLOTHING_COMPOSITE_ARMOR` | Composite Armor |
| `CLOTHING_PMC` | PMC Loadout |
| `CLOTHING_TACHARNESS` | Tactical Harness |
| `CLOTHING_ARMYARMOR` | Army Uniform |
| `CLOTHING_MILITARY` | Army Uniform |
| `CLOTHING_CATSUIT` | Black Catsuit |
| `CLOTHING_BLACKDRESS` | Black Dress |
| `CLOTHING_BLACKBLOC` | Black Bloc Outfit |
| `CLOTHING_BLACKSUIT` | Black Suit |
| `CLOTHING_BLACKSUIT_AGENT` | Black Suit |
| `CLOTHING_BLACKCLOTHES` | Black Turtleneck |
| `CLOTHING_BONDAGEGEAR` | Bondage Gear |
| `CLOTHING_BUNKERGEAR` | Firefighter Turnout Gear |
| `CLOTHING_CHEAPDRESS` | Cheap Dress |
| `CLOTHING_CLOWNSUIT` | Clown Suit |
| `CLOTHING_DEATHSQUADUNIFORM` | Death Squad Uniform |
| `CLOTHING_DONKEYSUIT` | Donkey Suit |
| `CLOTHING_ELEPHANTSUIT` | Elephant Suit |
| `CLOTHING_FURSUIT` | Custom Fursuit |
| `CLOTHING_EXPENSIVEDRESS` | Expensive Dress |
| `CLOTHING_EXPENSIVESUIT` | Expensive Suit |
| `CLOTHING_PRISONGUARD` | Guard Uniform |
| `CLOTHING_HEAVYARMOR` | Human Tank Suit |
| `CLOTHING_MITHRIL` | Mithril Mail |
| `CLOTHING_STEELHAUBERK` | Chain Hauberk |
| `CLOTHING_NINJASUIT` | Ninja Costume |
| `CLOTHING_POLICEARMOR` | Police Uniform |
| `CLOTHING_SEALSUIT` | SEAL Armor |
| `CLOTHING_SECURITYUNIFORM` | Security Uniform |
| `CLOTHING_SERVANTUNIFORM` | Servant Uniform |
| `CLOTHING_TOGA` | Toga |
| `CLOTHING_TRENCHCOAT` | Trenchcoat |
| `CLOTHING_HARDHAT` | Safety Vest & Hardhat |
| `CLOTHING_WIFEBEATER` | Tank Top |
| `CLOTHING_WORKCLOTHES` | Work Clothes |
| `CLOTHING_CHEERLEADER` | Cheer Squad Jacket |
| `CLOTHING_PUNK_JACKET` | Punk Jacket |
| `CLOTHING_DUSTER` | Leather Duster |
| `CLOTHING_JERSEY` | Sports Jersey |
| `CLOTHING_CHEF` | Chef's Whites |
| `CLOTHING_SCRUBS` | Medical Scrubs |
| `CLOTHING_TRACKSUIT` | Track Suit |
| `CLOTHING_KIMONO` | Kimono |
| `CLOTHING_STREETWEAR` | Streetwear |
| `CLOTHING_SARONG` | Sarong |
| `CLOTHING_SARI` | Sari |
| `CLOTHING_BOHO` | Bohemian Outfit |
| `CLOTHING_CHIC` | Chic Outfit |
| `CLOTHING_TIE_DYE` | Tie-Dye |
| `CLOTHING_APRON` | Apron |
| `CLOTHING_HABIT` | Religious Habit |
| `CLOTHING_CASSOCK` | Priest's Cassock |
| `CLOTHING_BANDTEE` | Band Tee |

### Ammo (7)

| Type ID | Catalogue name |
|---|---|
| `AMMO_22` | .22 LR Ammo |
| `AMMO_44` | .44 Magnum Ammo |
| `AMMO_45` | .45 ACP Ammo |
| `AMMO_50AE` | .50 AE Ammo |
| `AMMO_556` | 5.56 NATO Ammo |
| `AMMO_68` | 6.8mm Army Ammo |
| `AMMO_GASOLINE` | Gasoline |

### Loot (28)

| Type ID | Catalogue name |
|---|---|
| `LOOT_CHEAPJEWELRY` | Cheap Jewelry |
| `LOOT_DIRTYSOCK` | Dirty Sock |
| `LOOT_FAMILYPHOTO` | Family Photos |
| `LOOT_RECYCLEDCLOTH` | Recycled Cloth |
| `LOOT_EXPENSIVEJEWELRY` | Fine Jewelry |
| `LOOT_TRINKET` | Kitschy Trinket |
| `LOOT_LABEQUIPMENT` | Lab Equipment |
| `LOOT_KIDART` | Macaroni Art |
| `LOOT_SILVERWARE` | Silverware |
| `LOOT_CELLPHONE` | Smartphone |
| `LOOT_PDA` | Tablet |
| `LOOT_WATCH` | Watch |
| `LOOT_CHEMICAL` | Weird Chemical |
| `LOOT_AMRADIOFILES` | AM Radio Memos |
| `LOOT_CABLENEWSFILES` | Cable News Memos |
| `LOOT_CCS_BACKERLIST` | CCS Backer List |
| `LOOT_CEOLOVELETTERS` | CEO Love Letters |
| `LOOT_CEOPHOTOS` | CEO Photos |
| `LOOT_CEOTAXPAPERS` | CEO Tax Papers |
| `LOOT_INTHQDISK` | Intel. HQ Data Disk |
| `LOOT_JUDGEFILES` | Judge Corrupt. Evidence |
| `LOOT_POLICERECORDS` | Police Records |
| `LOOT_PRISONFILES` | Prison Records |
| `LOOT_RESEARCHFILES` | Research Papers |
| `LOOT_CORPFILES` | Secret Corporate Files |
| `LOOT_LANDLORD_PAPERS` | Landlord Papers |
| `LOOT_INSURANCE_DOCUMENTS` | Healthcare Documents |
| `LOOT_RETIREMENT_DOCUMENTS` | Elder Abuse Evidence |

## Validation contract

Run the asset verifier and the focused catalogue QA tests after any mapping change. Require exact required-ID coverage, no unexpected painted exclusions, valid source rectangles, complete decoded transparent artwork, source/runtime hash and alpha checks, preserved campaign state/RNG, and actual production UI rendering at compact and enlarged layouts. Inspect all new crops at thumbnail and larger sizes for clipping, neighboring-object bleed and recognizable silhouettes. Record final evidence in ignored `.local/` or `reports/` paths. These are acceptance requirements; the initial audit alone does not certify final implementation quality.
