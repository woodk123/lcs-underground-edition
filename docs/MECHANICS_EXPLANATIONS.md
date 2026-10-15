# Contextual mechanics explanations

The modern task screen explains the current assignment inline, including its
purpose, relevant current skill values, requirements, cost, risk and timing.
Task cards carry short purposes and disabled tasks explain the missing
requirement. Extra details expand in place without suspending the original
reader. The same pure help API is used by crew inspection.

The original `assignTask` loop updates the assignment as a category or task is
chosen. `Enter` exits the screen; it does not commit staged work or advance time.
The modern control therefore says **Done**, and the inline note states these
semantics. Done stays at the compact actor header. Equipment, attributes and skills expand in place from the original report without consuming input or changing the campaign. The seven category controls use a compact wrapping layout; task
choices use available width instead of leaving a long category column beside
an almost empty task column. Opening a category can select a suggested task,
which is stated beside the categories.

`ConsoleAction.entityType` of `activity` or `activity-confirm` carries the exact
`ActivityType.name`; `entityCategory` carries the current actor's numeric ID.
Display strings, action letters and row positions are not used to infer
mechanics identity. Original keys, order, enabled conditions and effects remain
authoritative. The regular assignment menus declare their safe navigation exit;
nested skill, crafting, prisoner and text prompts do not inherit that tag.

Sleeper menus carry explicit `sleeper-activity` identities and a sleeper
confirmation context. Their bulk selector carries `sleeper-bulk-selected`, so
even a preview without a selected person knows it describes undercover work.
Sleeper Lay Low rebuilds infiltration by 1–5 percentage points at month end,
capped at 100%; ordinary daily clothing care may also run. Active crew Lay Low
retains the laundry/mending explanation. Escape exits the sleeper list,
individual task menu and bulk menu without changing the assignment; X is
deliberately not used as the navigation exit.

Regular bulk menus use exact `BulkActivity.mechanicsId` policy identities rather than
pretending the suggested task is always one concrete activity. Legal
Fundraising compares the original estimates separately for each person;
Liberal Activism and Guardian choose among different concrete tasks. The
selected bulk policy is explained before any person is assigned. Selecting a
policy changes no assignment; selecting a person applies it immediately.

## Source-to-explanation audit

| Visible mechanic | Authoritative source | Explanation boundary |
| --- | --- | --- |
| Assignment mutation, category defaults, disabled tasks, Done | `upstream/lib/basemode/activate_regulars.dart` | Presentation annotations only. The selected task already applies; execution waits for daily processing. |
| Daily task timing, squad precedence, wheelchair, community service | `upstream/lib/daily/activities/solo_activities.dart`, `upstream/lib/basemode/activate_regulars.dart` | Individual task effects run during the day. A squad visit takes precedence. Community service gives 1 Juice up to 10; no arrest check is implemented in that activity. |
| Donations, art, clothing, music and public mood | `upstream/lib/daily/activities/fundraising.dart`, `arrest.dart` | No predicted payout or preview roll. Music actually uses **Music and Street Smarts**, despite the original help/footer saying Business. Instrumentless earnings have a one-quarter multiplier. Legal public fundraising can still attract police through existing heat or indecent clothing. |
| Brownies and prostitution | `upstream/lib/daily/activities/fundraising.dart`, assignment availability | Describes law/skill dependencies and arrest consequences without invented success chances or guaranteed daily earnings. |
| Hacking and credit-card fraud | `upstream/lib/daily/activities/hacking.dart`, assignment availability | Requires Computers and Hacker Den. Distinguishes best-roll-plus-team hacking from summed-roll fraud. Traceable crimes create heat; success is not a guarantee of remaining unnoticed. |
| Writing versus streaming | `upstream/lib/daily/activities/guardian.dart` | Correct Writing/Persuasion roll plus knowledge skills. Streaming multiplies its expression by four and requires a studio. No promise of a fourfold final political result for unequal skills. |
| Free practice and paid classes | `upstream/lib/daily/activities/learning.dart`, `upstream/lib/creature/skills.dart` | Practice base training is 5 XP, class base training is 50 minus 5 times current skill, before training modifiers. Classes cost $30/day, stop at level 10/personal potential, and only taught skills appear. |
| Teaching | `upstream/lib/daily/activities/teaching.dart` | Actual subjects, topic/Teaching skill relationship, eligible same-city students, workload and $20/$60/$100 maximum supply costs. No speculative estimate of a current class's workload or training gain. |
| Clothing, flags and laundry | `upstream/lib/daily/activities/clothing_creation.dart`, `flag_creation.dart`, `clothing_repair.dart` | Chosen supplies and reusable cloth costs, failure outcomes, inventory destination and completion semantics. Laundry does not invent a Tailoring success roll; damaged clothing trains Tailoring. |
| Graffiti, disobedience, recruitment, car theft and burial | Corresponding files under `upstream/lib/daily/activities/` | Explains equipment, useful skills, interaction timing and charges. Graffiti can acquire spraypaint and continue in the same daily handler, rather than asserting the older help's first-day delay. |
| Hospital and prisoner care | `upstream/lib/daily/shopsnstuff.dart`, `upstream/lib/daily/hostages/tend_hostage.dart`, assignment availability | Hospital admission removes squad membership and may generate bills. Prisoner selection occurs here; treatment choices occur when care is processed. Care uses Psychology twice plus clothing power, best group Business/Religion/Science and prisoner resistance; Persuasion is not claimed as a factor. |
| Sleeper timing and roles | `upstream/lib/monthly/sleeper_update.dart`, `upstream/lib/daily/activities/sleeper_join_lcs.dart` | Sleeper effects run at month end; joining active service uses the daily routine and waits if no viable LCS safehouse exists. Successful spy document leaks also cost 20 infiltration points. Recruitment depends on workplace encounters and subordinate capacity, rather than infiltration. The legacy Conservative activity has no dedicated case in the current monthly effect switch. |
| Heat, Secrecy and Juice | `upstream/lib/location/site.dart`, `upstream/lib/daily/siege.dart`, daily activity handlers | Raw Heat is compared with protection called Secrecy. Neither is a success percentage; exceeding protection permits search progression, not a guaranteed immediate raid. Juice is activist credibility, separate from money/skills. |

## Verification

`upstream/test/mechanics_help_test.dart` checks exact activity identity rather
than label matching, corrected implemented formula examples, availability
reasons, daily versus monthly timing, all enum coverage, unchanged serialized
campaign state and unchanged next 12 random results after every help preview.
The real task-menu widget scenario changes to Sell Art, verifies that inline
help follows the current selection, expands details without consuming the
waiting input reader or changing the campaign, and proves Done preserves the
assignment without advancing the date. Existing direct-content tests verify
the proportional roster, narrow layout, disabled action behavior and exact
case-sensitive vehicle commands remain intact.

Real sleeper individual and bulk menu scenarios verify exact authored activity
metadata, explicit undercover Lay Low context, monthly versus daily timing,
selection before application, assignment preservation on Escape and unchanged
campaign state/input revision while expanding help. The real regular bulk menu
scenario verifies Legal Fundraising is explained as a per-person policy rather
than a fixed Donations task. Pure help checks include both ordinary and sleeper
contexts and every original bulk policy without consuming RNG.

Help is descriptive and read-only: it calls no activity handlers, original
blocking help routines, training functions, income estimators or dice rolls.
