# Changes from New Age

The Underground Edition retains the original Dart/Flutter engine and campaign content. It adds an illustrated journal interface, crew portraits/dossiers, city maps, assignment cards and scoped navigation. UI controls use source-authored command identities and eligibility rather than recreating gameplay handlers.

## Engine and save fixes

- Unaffordable clothing/flag crafting no longer consumes recycled cloth.
- Calendar advancement avoids skipped or repeated dates across daylight-saving changes.
- Failed saves stop day advancement or exit before campaign progress changes.
- Invalid imports are rejected without partially replacing the active campaign.
- Legacy saves retain equipped clothing quality/protection during migration.
- Inspecting saves does not consume the active campaign RNG.
- Completed campaign totals are recorded once.
- Guilty and lenient trial outcomes retain the full charged counts in conviction history, including earlier cases. Acquittals and retrials add no convictions; sentencing calculations are unchanged.
- Free Clinic admissions persist across daily turns, exclude patients from ordinary work/squad allocation, and discharge through the existing recovery handler. The clinic's original support and free treatment are preserved; university treatment and billing remain unchanged. Clinic sleeper staff remain at work.
- Car pursuit animation preserves gameplay RNG, command revisions and authored report text, yields at a positive cadence, bounds overlapping cars and stops on all exits. Departing pursuers are removed from the distance map; enemy obstacle crashes also work without an active site story. Driving and combat calculations are unchanged.
- A severe-injury notice after an operation starts with a fresh reader, so its professional-treatment warning and Continue control cannot be hidden by the preceding field screen.

## Interface and portrait behavior

- Orders are prepared locally, with explicit confirmation and safe cancellation. Switching crew members retains the category and map; ordinary confirmations keep the category open for repeated assignments.
- Destination labels show relevant travel prices and requirements; general travel rules are available on request.
- Squad visits use the original destination planner and shared order card.
- Skill levels sit next to their names; XP is secondary.
- Clipboard profiles use the structured personnel dossier; crew and equipment lists use ruled journal rows with compact controls.
- Left-hand selection follows profile tabs and equipment rows without resetting scroll or changing equipment; profile arrow navigation keeps the left-hand selection in sync.
- Field encounters retain the source's visible names, equipment and health. Retreat exposes clickable directions and cancellation; movement availability follows the original frightened-occupant exception.
- Field portrait dossiers keep the map and current decision in place and block game commands while inspecting. Speaker choices show Persuasion, Seduction and Disguise beside their names.
- Conversation retries keep their own choices. Hostage threats, bluffing, surrender and rental acceptance display the eligibility already enforced by their original handlers.
- Hospital admission, discharge bills and court defense use journal pages with contextual notes, portraits, condition and concise source-authored choices. Unpaid bills are explicit; full charges and health/legal mechanics remain available on demand. Court defense begins on a fresh page so long charge lists cannot hide its choices or Law/Persuasion values.
- Intermediate map-generation frames show a journal progress note until the next source reader is ready, retaining the selected person and organisation layout.
- On-foot pursuit decisions use a journal page with current source controls, visible pursuers and working read-only dossiers. Street arrests use an appropriate pursuit introduction; stale pursuit controls cannot reach later readers.
- Car pursuits share the journal page with current road conditions, vehicle gaps and contextual obstacle controls. Equipment, orders, bailout and surrender expose the availability already accepted by the original reader. Solo car introductions describe the person being pursued; retries and nested equipment/status readers retain command isolation.
- Full formulas and requirements are available through Order mechanics; cards keep key timing, estimates, costs and risks visible.
- Portrait age compatibility takes precedence over avoiding duplicates. Clearly mismatched saved assignments are repaired once; appropriate identities persist across saves and birthdays.
- The founder identity page previews and rerolls an age-compatible portrait alongside the generated names. The selected face survives background creation and saves without consuming gameplay RNG.
- Founder attributes and skills use two compact columns when space permits; values stay beside their labels and detailed help remains in tooltips.
- Background bonus tooltips compare current and projected levels, effective attributes, training ceilings and relevant uses. Computers also explains Hacker Den requirements and solo hacking odds. The reader and preview share typed bonuses; previews never run world/equipment callbacks or consume campaign RNG/IDs. Two reward descriptions now include Music/First Aid bonuses that were already granted by the original game.
- The public-name field and campaign buttons sit beneath the question on the left page, with wrapping controls for enlarged text.
- Founder portrait selection keeps its original assignment age through background creation, headquarters and saves, including birthdays at an age-cohort boundary.
- Crew and personnel illustrations depict contemporary grassroots activists.

See [architecture](ARCHITECTURE.md), [testing](TESTING.md) and [portrait details](PORTRAIT_LIBRARY.md). Detailed development history and retired reviews remain available through Git history and the original release artifacts.
