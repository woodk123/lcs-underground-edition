# Changes from New Age

The Underground Edition retains the original Dart/Flutter engine and campaign content. It adds an illustrated journal interface, crew portraits/dossiers, city maps, assignment cards and scoped navigation. UI controls use source-authored command identities and eligibility rather than recreating gameplay handlers.

## Engine and save fixes

- Unaffordable clothing/flag crafting no longer consumes recycled cloth.
- Calendar advancement avoids skipped or repeated dates across daylight-saving changes.
- Failed saves stop day advancement or exit before campaign progress changes.
- Invalid imports are rejected without partially replacing the active campaign.
- Legacy saves retain equipped clothing quality/protection during migration.
- Inspecting saves does not consume the active campaign RNG.
- Opening personnel review no longer consolidates or rewrites safehouse inventory. Stack consolidation remains part of explicit equipment management.
- Completed campaign totals are recorded once.
- Guilty and lenient trial outcomes retain the full charged counts in conviction history, including earlier cases. Acquittals and retrials add no convictions; sentencing calculations are unchanged.
- Free Clinic admissions persist across daily turns, exclude patients from ordinary work/squad allocation, and discharge through the existing recovery handler. The clinic's original support and free treatment are preserved; university treatment and billing remain unchanged. Clinic sleeper staff remain at work.
- Car pursuit animation preserves gameplay RNG, command revisions and authored report text, yields at a positive cadence, bounds overlapping cars and stops on all exits. Departing pursuers are removed from the distance map; enemy obstacle crashes also work without an active site story. Driving and combat calculations are unchanged.
- A severe-injury notice after an operation starts with a fresh reader, so its professional-treatment warning and Continue control cannot be hidden by the preceding field screen.
- Pursuit and operation cleanup stabilize the people involved without clearing bleeding or prison-escape flags on unrelated patients and off-site squads. Hauled people and local siege reserves retain the existing cleanup effects. Defeated solo actors and dead casualties removed during hauling, promotion or car crashes no longer retain invalid squad IDs.
- Siege responses select defenders at the displayed location instead of retaining a remote squad. Local unsquadded defenders can respond, and the source can select an attacked safehouse when waiting is blocked elsewhere. Police confiscation reports expose a current Continue control.
- The loopback browser server queues cold asset bursts without its former five-connection bottleneck. Its bind address, MIME handling, health endpoint and file protections are unchanged.

## Interface and portrait behavior

- Orders are prepared locally, with explicit confirmation and safe cancellation. Switching crew members retains the category and map; ordinary confirmations keep the category open for repeated assignments.
- Destination labels show relevant travel prices and requirements; general travel rules are available on request.
- Squad visits use the original destination planner and shared order card.
- Skill levels sit next to their names; XP is secondary.
- Juice is visible with character identities, crew rows, dossiers, the directory and field portraits. Dossiers show the current rank's attribute effect and progress to the next milestone; click/tap help explains rounding, alignment exemptions, training ceilings, recruit capacity, courage and activity caps. Directory sorting can compare Juice. Classic and journal displays share exact next-rank thresholds, including negative-Juice recovery. The underlying rank, rewards and gameplay rules are unchanged.
- Clipboard opens a complete personnel directory with counted status filters, global name/status/location search, full locations and hospital bills. Search and filters survive opening and closing a profile. Directory selections resolve exact character IDs through the original source roster pages, retaining rename and other management confirmations. Roster tools preserve the original sorting/reordering controls; squad allocation keeps its existing eligibility rules.
- Left-hand selection follows profile tabs and equipment rows without resetting scroll or changing equipment; profile arrow navigation keeps the left-hand selection in sync.
- Field encounters retain the source's visible names, equipment and health. Retreat exposes clickable directions and cancellation; movement availability follows the original frightened-occupant exception.
- Field portrait dossiers keep the map and current decision in place and block game commands while inspecting. Speaker choices show Persuasion, Seduction and Disguise beside their names.
- Conversation retries keep their own choices. Hostage threats, bluffing, surrender and rental acceptance display the eligibility already enforced by their original handlers.
- Hospital admission, discharge bills and court defense use journal pages with contextual notes, portraits, condition and concise source-authored choices. Unpaid bills are explicit; full charges and health/legal mechanics remain available on demand. Court defense begins on a fresh page so long charge lists cannot hide its choices or Law/Persuasion values.
- Intermediate map-generation frames show a journal progress note until the next source reader is ready, retaining the selected person and organisation layout.
- On-foot pursuit decisions use a journal page with current source controls, visible pursuers and working read-only dossiers. Street arrests use an appropriate pursuit introduction; stale pursuit controls cannot reach later readers.
- Car pursuits share the journal page with current road conditions, vehicle gaps and contextual obstacle controls. Equipment, orders, bailout and surrender expose the availability already accepted by the original reader. Solo car introductions describe the person being pursued; retries and nested equipment/status readers retain command isolation.
- Headquarters sieges show their current source responses in the journal beside the existing squad leaders. Supply/security detail is optional, surrender consequences are contextual, and read-only inspection blocks underlying battle, surrender and wait commands.
- Full formulas and requirements are available through Order mechanics; cards keep key timing, estimates, costs and risks visible.
- Portrait age compatibility takes precedence over avoiding duplicates. Clearly mismatched saved assignments are repaired once; appropriate identities persist across saves and birthdays.
- The founder identity page previews and rerolls an age-compatible portrait alongside the generated names. The selected face survives background creation and saves without consuming gameplay RNG.
- Founder attributes and skills use two compact columns when space permits; values stay beside their labels and detailed help remains in tooltips.
- Background bonus tooltips compare current and projected levels, effective attributes, training ceilings and relevant uses. Computers also explains Hacker Den requirements and solo hacking odds. The reader and preview share typed bonuses; previews never run world/equipment callbacks or consume campaign RNG/IDs. Two reward descriptions now include Music/First Aid bonuses that were already granted by the original game.
- The public-name field and campaign buttons sit beneath the question on the left page, with wrapping controls for enlarged text.
- Founder portrait selection keeps its original assignment age through background creation, headquarters and saves, including birthdays at an age-cohort boundary.
- Crew and personnel illustrations depict contemporary grassroots activists.

## Artwork and player size

- Runtime illustrations, portraits and appearance overlays use WebP quality 90 colour with exact alpha, retaining all dimensions, atlas cells and portrait IDs. Original PNG masters remain available for regeneration. The 17 October 2026 rebuild reduced browser and Windows player ZIPs by approximately 12.1 MB each against the October 16 preview; see [size measurements and validation](BUILDING.md#quality-90-size-measurements-17-october-2026).

See [architecture](ARCHITECTURE.md), [testing](TESTING.md) and [portrait details](PORTRAIT_LIBRARY.md). Detailed development history and retired reviews remain available through Git history and the original release artifacts.
