# Campaign acceptance evidence

Review date: 13 October 2026. This review adds scenario evidence for important retained game systems. It does not change the frozen game source or the release JavaScript. The four new cases in `upstream/test/campaign_acceptance_test.dart` use the shipped Felix 1.0 campaign, its real compatibility migration, the original XML definitions and the original engine functions.

## Verification performed

From `upstream/`:

```powershell
..\.tools\flutter\bin\flutter.bat analyze test/campaign_acceptance_test.dart
..\.tools\flutter\bin\flutter.bat test test/campaign_acceptance_test.dart test/campaign_progression_test.dart test/campaign_endings_test.dart test/modal_choices_test.dart --reporter expanded
```

Results: **clean analysis; 22 passing scenario tests** across these four files. The new acceptance file contributes **four passing cases**. Detailed output is saved in `reports/campaign-acceptance.log`. The release-wide count is recorded separately by the final build owner; this review does not infer it from this subset.

| Scenario | Real operation exercised | Outcome asserted |
|---|---|---|
| A ready candidate joins as a regular | `completeRecruitMeeting` and `sleeperizePrompt`; the actual enabled C offer and A regular-member commands | Exactly one new roster member and recruit statistic; original recruiter/boss link; liberal alignment; regular status; location and base; completed session removed; date and funds unchanged; all persisted state round-trips |
| Police pursuit and voluntary surrender | `attemptArrest` → `soloChaseSequence` → `footChaseSequence` → the actual enabled G Give up choice → `chaseGiveUp` | Original police encounter and arrest messages; captured member alive at the real police station, out of their squad, without weapon/ammo or active assignment; existing charges retained; other squad members and squad inventory retained; temporary pursuit squad cleaned up; original active squad restored; date/funds unchanged; custody survives serialization |
| One armed combat exchange | `combatRound`, including original squad and enemy attacks, aim, ammunition, hit location and damage resolution | Both actors take their turns and expend real ammunition; the fixed-seed opponent actually wounds the liberal; site-crime consequences appear; date does not change; the liberal's resulting blood and ammo survive serialization |
| Theft prosecution through prison release | Original `criminalize` and `captureCreature`; `trial` with the actual C Plead guilty choice; original sentencing and repeated `prison` updates | Two theft counts displayed, plea accepted and guilty verdict shown; a finite real sentence and custody in the real prison; charges/heat cleared; no death penalty; every update reduces the remaining sentence by one; final release returns the living liberal to their base; released state survives serialization |

The input driver supplies commands through `Console.sendInput`, which is the presentation's normal input bridge. No simulated rules, alternate combat implementation, substituted damage roll or storage hook determines these outcomes. The driver checks readiness and the enabled semantic command before the important choices. Recruitment and arrest require the expected exact prompt sequence; combat, trial and prison acknowledgements have a bounded timeout and prompt budget, plus concrete outcome assertions. A new unresolved decision stalls and fails instead of being silently declared successful.

## Existing depth checks reviewed and rerun

The same 22-test run includes these existing checks:

- `campaign_progression_test.dart`: real HQ W command runs fundraising and science training, ages the roster exactly once per day and saves; progression through the next month executes original report/news/financial reset and reloads the whole campaign from an isolated real save database.
- `campaign_endings_test.dart`: 87 consecutive campaign days and three real monthly congressional cycles preserve roster identity and run political changes; original monthly victory and roster defeat gates persist the actual ending/high score, delete the completed save, return through the real title and expose score history. It also checks civil-day daylight-saving transitions and excludes unrelated active campaigns from completed cumulative totals.
- `modal_choices_test.dart`: actual equipment allocation/drop/strip/cancel, vehicle driver/passenger/cancel, squad reorder/cancel and typed quantity decisions assert the chosen member, untouched other members and exact item quantities.

The full application/browser evidence adds direct central person/task/city interaction, actual site travel, tactical door/movement/full map/equipment, real save export/import/restart and offline play. See `BROWSER_QA.md` and the final package-specific report for their build identity. The acceptance cases above are engine integration tests, not a claim that the combat/arrest/trial interfaces were visually played in a browser.

## Fixture boundaries and remaining limits

The ready-recruit fixture explicitly sets eagerness to four; the test proves the complete join route and relationship persistence. It does not claim to earn readiness through earlier conversations. The combat fixture equips two ordinary loaded 9mm handguns, selects a single living squad member and a generated police officer, and prevents the officer from fleeing. Original hit and damage rules still decide the exchange. The theft fixture supplies two charges and custody, then lets the original court determine the sentence. Calling the original monthly prison subsystem repeatedly proves sentence progression/release; it does not advance the campaign calendar itself.

Victory and defeat fixtures exercise valid terminal states. They prove ending access, bookkeeping and cleanup, not that automated ordinary play earned every victory prerequisite. Three monthly political cycles do not cover a full annual election/judicial/constitutional cycle or certify economic balance over decades.

Source equivalence retains all authored systems, but these scenarios still leave combinations unexercised: every recruitment persuasion outcome, sleeper/hostage/interrogation route, multi-floor combat and weapon/injury combination, stealth/chase/escape branch, siege/base loss, jury defense/hung trial/appeal, death row/execution and prison-scene variation. Native graphical interaction remains unverified after the user's stop instruction; no native Computer Use was resumed for this review. These are explicit test limits, not evidence that the corresponding source was omitted.

No acceptance blocker was found in the exercised scenarios. Production release approval must also use the final frozen-package, browser/offline, archive-integrity and fidelity gates in `RELEASE_CHECKLIST.md`.
