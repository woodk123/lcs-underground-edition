from pathlib import Path
import json,hashlib,urllib.request,re,datetime,collections
root=Path.cwd();out=root/'reports/longevity-combat-20261015'
def read(n):return json.loads((out/n).read_text(encoding='utf-8'))
def game(n):
 r=read(n);s=r['saveData'];return json.loads(s) if isinstance(s,str) else s
natural=read('natural-browser-report.json');rare=read('rare-browser-report.json');reliability=read('reliability-browser-report.json');before=game('natural-start.json');after=game('natural-final.json')
assert len(rare['scenarios'])==10 and all(s['status']=='passed' for s in rare['scenarios']) and rare['errors']==[]
assert reliability['scenarios'][0]['status']=='passed' and reliability['errors']==[]
assert len(natural['scenarios'][0]['days'])==36
assert (datetime.datetime.fromisoformat(after['date'])-datetime.datetime.fromisoformat(before['date'])).days==1096
for p in before['lcs']['pool']:
 q=next(x for x in after['lcs']['pool'] if x['id']==p['id']);assert q['alive'] and q['daysSinceJoined']==p['daysSinceJoined']+1096
income=after['ledger']['totalIncome']-before['ledger']['totalIncome'];expenses=after['ledger']['totalExpense']-before['ledger']['totalExpense'];assert after['ledger']['_funds']==before['ledger']['_funds']+income-expenses
sha=hashlib.sha256((out/'browser-build-final/main.dart.js').read_bytes()).hexdigest();assert rare['runtimeSha256']==reliability['runtimeSha256']==sha
served=hashlib.sha256(urllib.request.urlopen('http://127.0.0.1:8767/main.dart.js').read()).hexdigest();assert sha==served
count=int(re.search(r'\+(\d+): All tests passed!',(out/'regression.log').read_text(encoding='utf-8'))[1]);assert count==518
assert 'No issues found' in (out/'analysis.log').read_text(encoding='utf-8');audit=read('frozen-manifest-audit.json');assert audit['mismatches']==[]
bombers=read('bomber-outcomes.json');counts={k:sum(bool(x[k]) for x in bombers) for k in ['planes','heldOff','pilotThrough','aaDestroyed','solarDestroyed','deaths']}
changes=[{'law':k,'before':v,'after':after['politics']['laws'][k]} for k,v in before['politics']['laws'].items() if after['politics']['laws'][k]!=v]
combined={'scenarios':natural['scenarios']+rare['scenarios']+reliability['scenarios'],'errors':[],'note':'Natural campaign used the previous frozen runtime; all ten combat/siege cases and final save reliability used the refreshed runtime. See individual reports for origin and runtime hashes.'}
(out/'browser-report.json').write_text(json.dumps(combined,indent=2),encoding='utf-8')
summary={'date':'2026-10-15','testsPassed':count,'analysis':'No issues found','finalBuild':str(out/'browser-build-final'),'runtimeSha256':sha,'manifestAudit':audit,'externalChromeCasesPassed':len(combined['scenarios']),'finalRuntimeChromeCasesPassed':11,'naturalCampaign':{'start':before['date'],'end':after['date'],'additionalDays':1096,'monthlyExportsAndReloads':36,'allFiveOriginalCrewAlive':True,'startingFunds':before['ledger']['_funds'],'endingFunds':after['ledger']['_funds'],'income':income,'expenses':expenses,'ledgerReconciles':True,'lawChanges':changes,'presidentialPartyBefore':before['politics']['presidentParty'],'presidentialPartyAfter':after['politics']['presidentParty'],'ccsStates':list(dict.fromkeys(x['ccs'] for x in natural['scenarios'][0]['days'])),'runtimeSha256':natural['runtimeSha256']},'preparedCombat':{'firearmSeeds':24,'knifeSeeds':24,'statsInflated':False,'combatRoundCap':30,'capHandling':'Continue actual foot chase with retreat orders; death outcome can include captured incapacitated survivors. Opponents can also leave the encounter.'},'bomberMatrix':{'seeds':64,'casesWithOutcome':counts},'limitations':['Natural campaign retained the existing quiet fundraising orders; it was not an aggressive combat campaign or a naturally earned victory.','Natural multi-year play ran on the previous frozen build; the resulting save passed import, export, refresh and offline reload on the final build.','Rare siege factions/escalations and defensive equipment were prepared; only normal attributes and skills were used. They were not naturally triggered in this campaign.','Seed matrices are mechanical regression coverage, not statistical balance estimates. Native combat caps after 30 rounds continued through real retreat resolution.','Every possible rare siege assault map, no-AA/no-food combination, multi-year aggressive organisation, extreme-law natural history and ending remains unverified.','Offline check covers an activated service worker and warm cache; first-ever offline installation and browser storage eviction are not covered.']}
(out/'validation-summary.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
text=f'''Liberal Crime Squad: longevity, ordinary combat and rare siege follow-up — 15 October 2026

RESULT
518 tests passed; static analysis clean; release web build succeeded. The service worker injector ran once after each of the two builds in this pass. Final frozen manifest: {audit['resources']} resources, {audit['bytes']} bytes, version {audit['version']}; every CRC matches. Final main.dart.js SHA-256: {sha}.
Actual external installed Chrome, headed, isolated contexts: 12 scenarios passed across the natural campaign and final-build checks; 11 on the final runtime. No browser errors recorded. Player origin 8765 was not used or changed.

NATURAL CAMPAIGN
Continued the existing campaign from 1 November 2023 to 1 November 2026 through 1,096 actual day commands. No time skips, save-state stat changes or scenario substitution. Kept the existing quiet fundraising orders. All five original members remain alive, with exactly 1,096 additional days since joining. Thirty-six monthly exports and reloads checked calendar, roster and ledger. Funds {before['ledger']['_funds']} -> {after['ledger']['_funds']}; income {income}, expenses {expenses}; accounting reconciles. Natural presidential turnover Republican -> Democrat; {len(changes)} laws differ at the endpoint. CCS progressed through inHiding, active, attacks and sieges. This does not demonstrate a naturally triggered safehouse siege or victory.
Natural playback used runtime {natural['runtimeSha256']}. The final campaign save subsequently passed import, export/reload, refresh and warm-cache offline refresh on the final runtime. Monthly screenshots and campaign-YYYY-MM-DD.json checkpoints are retained.

PREPARED SCENARIOS — NORMAL ATTRIBUTES/SKILLS
Chrome: original saved crew with rifles, revolvers, shotgun and knife faced an ordinary police sweep. Two fight rounds then attempted retreat; capture, automatic time passage and trials were resolved with court-appointed defence. A separate immediate-retreat attempt resolved with losses. Outcomes exported and reloaded; losses were not changed into victories. Rare CIA, rural mob, corporate mercenary and CCS surrender preserve outside crew and count exactly two present casualties; CCS captures the warehouse. Medical debt surrender is nonlethal, clears debt and spends only available funds. National Guard, tanks and bomber escalations each advanced a real siege day before surrender and save/reload.
Native: 24 generated handgun combat cases plus 24 combat-knife cases, retaining generated attributes/skills; injuries, bleeding, ammunition reduction, deaths, incapacitation/capture and retreat aftermath. Combat survivors at the 30-round cap continue through the real retreat sequence. Seven additional death outcomes in the firearm records include living captured characters; the enum is not a claim that every character died. No inflated combat rolls.
64 prepared bomber/AA cases: {counts['planes']} air strikes, {counts['heldOff']} held-off/shootdown cases, {counts['pilotThrough']} pilot breakthroughs, {counts['aaDestroyed']} AA losses, {counts['solarDestroyed']} solar losses and {counts['deaths']} cases with crew deaths. Defences and siege escalation were prepared; attributes and skills were unchanged. Counts are observations across deterministic seeds, not a balance estimate.
Also covered dead-squad cleanup, repeat death accounting/political effects, four rare-faction surrender paths with an existing corpse, medical debt settlement at funds 0/100/5000, unoccupied bomber-raid termination, serialization of every native scenario and journal rendering of chase commands.

FIXES CARRIED THROUGH THIS FOLLOW-UP
- Foot-chase defeat cleanup iterates a snapshot while removing squad members, avoiding concurrent modification. The Reflect command is registered as a usable journal action.
- Creature death is idempotent: corpse cleanup cannot add another martyr/kill or repeat political effects.
- An unoccupied safehouse raid ends its siege processing immediately; the cleared siege cannot keep consuming supplies or roll another air strike.
- Classic command-separator commas no longer appear as separate descriptions in journal action cards; legacy command text and gameplay keys are preserved.
Gameplay difficulty and political/story-only law effects were preserved.

EVIDENCE
validation-summary.json, natural-browser-report.json, rare-browser-report.json, reliability-browser-report.json; regression.log, analysis.log, native-before.log, native-final.log, build-final.log, service-worker-final.log; saves/, monthly saves, ordinary-combat-matrix.json, ordinary-knife-matrix.json, bomber-outcomes.json, browser screenshots/text and native transcripts. Reproducible drivers: scripts/longevity_combat_playtest.mjs, ordinary_rare_playtest.mjs, longevity_final_reliability.mjs. Native fixture/test source: upstream/test/longevity_combat_playtest_test.dart.
The first ordinary browser harness stopped at an unhandled trial-choice prompt. This was a driver gap, not a product crash; the driver now selects the displayed court-appointed defence and the final run passes. A report-path collision in the reliability driver was corrected; the natural report is reconstructed from the retained final monthly progress and successful process log, with this provenance disclosed there.

READINESS / REMAINING LIMITS
Suitable for continued playtesting with stronger ordinary-combat, longevity and rare-outcome evidence. Not exhaustive balance or release certification. The quiet natural campaign does not verify a multi-year aggressive organisation. Rare sieges were prepared, not naturally earned. Every assault map, defence/supply combination, extreme-law natural history and naturally earned victory remains outside this pass. Offline testing used a warm cache; first-ever offline install and browser storage eviction remain untested. Previous broader reports remain applicable and are not relabelled as newly verified.
'''
(out/'report.txt').write_text(text,encoding='utf-8');print(json.dumps({'tests':count,'chromeScenarios':12,'finalChromeScenarios':11,'runtime':sha,'report':str(out/'report.txt')},indent=2))
