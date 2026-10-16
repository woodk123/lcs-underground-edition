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

## Interface and portrait behavior

- Orders are prepared locally, with explicit confirmation and safe cancellation. Switching crew members retains the category and map; ordinary confirmations keep the category open for repeated assignments.
- Destination labels show relevant travel prices and requirements; general travel rules are available on request.
- Squad visits use the original destination planner and shared order card.
- Skill levels sit next to their names; XP is secondary.
- Full formulas and requirements are available through Order mechanics; cards keep key timing, estimates, costs and risks visible.
- Portrait age compatibility takes precedence over avoiding duplicates. Clearly mismatched saved assignments are repaired once; appropriate identities persist across saves and birthdays.
- The founder identity page previews and rerolls an age-compatible portrait alongside the generated names. The selected face survives background creation and saves without consuming gameplay RNG.
- Founder attributes and skills use two compact columns when space permits; values stay beside their labels and detailed help remains in tooltips.
- Background bonus tooltips compare current and projected levels, effective attributes, training ceilings and relevant uses. Computers also explains Hacker Den requirements and solo hacking odds. The reader and preview share typed bonuses; previews never run world/equipment callbacks or consume campaign RNG/IDs. Two reward descriptions now include Music/First Aid bonuses that were already granted by the original game.
- The public-name field and campaign buttons sit beneath the question on the left page, with wrapping controls for enlarged text.
- Founder portrait selection keeps its original assignment age through background creation, headquarters and saves, including birthdays at an age-cohort boundary.
- Crew and personnel illustrations depict contemporary grassroots activists.

See [architecture](ARCHITECTURE.md), [testing](TESTING.md) and [portrait details](PORTRAIT_LIBRARY.md). Detailed development history and retired reviews remain available through Git history and the original release artifacts.
