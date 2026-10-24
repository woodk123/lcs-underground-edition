# Prison orders and working print shops

These systems extend the existing prison and business-front mechanics. They use
the original gameplay readers in both Classic and journal views.

## Prison standing orders

Open **Justice**, then **Manage prison orders** (`U` in the original roster).
An imprisoned person's original profile also exposes **Prison orders** (`P`).
Choose a prisoner and a standing order:

| Order | Effect |
|---|---|
| Keep your head down | Retains ordinary prison processing without an additional project. |
| Study Law / Study Writing | Requests real skill experience each month, subject to training limits and prison laws. |
| Build contacts | Attempts to establish contacts shared by LCS prisoners in the same institution. Failed organising can lose contacts and Juice. |
| Document conditions | Attempts to collect an existing publishable prison dossier over three successful monthly steps. Contacts help; confiscation can set progress back. |

Only living Liberal members serving a sentence at an actual prison can work on
projects. Police custody, court, sleeper staff, death row and the final month
before release do not qualify. Labour camps restrict studying; rehabilitation
does not produce an abuse dossier. The reader explains current restrictions.

Orders are separate from ordinary daily activities. They resolve once per month
after the original random prison event, with eligibility checked again after any
escape, death or renunciation. Existing sentences, executions, commutation,
release and rescue remain authoritative. When everyone is unavailable outside
prison, the game offers a monthly prison-planning reader before automatic time
passing resumes.

A prisoner can complete one dossier per imprisonment. Delivery uses an accessible
LCS location in the prison's city; the source report names it. If no destination
is available, completed material remains pending, including after release or
rescue. Publishing still uses the Guardian's existing special-edition rules.

## Working print shops

Open **Bases → Manage print shop**, or use `S` from the original investment menu.
An owned, upgradable public base outside siege or closure can host a shop.
Equipment costs $1,500, plus the existing business-front cost if cover is not
already installed. Setup has a source-owned confirmation and cancellation.

Assign up to two people who are available and present at their own base. Staffing
replaces their daily assignment. Squad orders and other assignments take
precedence; absent staff cannot produce income or influence.

| Mode | Daily effect per eligible worker |
|---|---|
| Commercial work | Gross $45 + 8 × Business + 3 × Writing, with each skill capped at 8 for this calculation; $20 running costs and 5 requested Business XP. |
| Movement printing | $20 running costs for 2–8 Free Speech background influence and 5 requested Writing XP. Only affordable workers operate. |
| Temporarily closed | No output or running costs; staff return to Lay Low. |

Movement printing does not count as staffing a Guardian special edition. Income
and costs appear in the existing ledger. The management reader retains the last
trading report. Closed, unstaffed and besieged shops have no running costs. Losing
the premises or dismantling the front ends the shop and its work orders.

After seven staffed operating days, a customer offers a rush order. Accepting
reserves the next eligible trading day for commercial work with a $100 sales
bonus, replacing any movement printing that day. It pays nothing in advance.
Declining or cancelling clears the offer. Closed, besieged and unstaffed shops
retain an accepted job until they can fulfil it; offers do not stack.

## Save compatibility

The saved additions are optional `prisonActivity` state on people and
`frontBusiness` state on sites. Historical campaigns default to no project and
no managed shop; existing business-front secrecy is retained. New order and
ledger categories are serialized with their stable names. Pending documents,
project progress, shop staffing and processing stamps survive save transfers.

The save compatibility identifier remains 1.5.6. This preserves loading of
historical campaigns in the new build; older builds may reject new activity or
ledger categories in exports written by this build. Export important campaigns
before switching builds.

## Verification

Focused regressions are `prison_activity_test.dart`,
`prison_management_test.dart`, `front_business_test.dart`,
`front_business_management_test.dart` and `prison_shop_journal_test.dart` under
`upstream/test/`. They use declared prepared campaigns; they do not represent
earning those scenarios through ordinary play. Run the common
[shared acceptance journey](TESTING.md#shared-acceptance-journey) for creation,
orders, navigation and save integration.
