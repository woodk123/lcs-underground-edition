import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {resolve} from 'node:path';
const root=resolve(import.meta.dirname,'..');const out=resolve(root,'reports/campaign-systems-20261015');
const hash=b=>createHash('sha256').update(b).digest('hex');
const game=async name=>{const r=JSON.parse(await readFile(resolve(out,name+'.json'),'utf8'));return typeof r.saveData==='string'?JSON.parse(r.saveData):r.saveData;};
const before=await game('natural-start'),after=await game('natural-final');const first=await game('large-outcome'),evac=await game('evacuation-outcome');
const report=JSON.parse(await readFile(resolve(out,'browser-report.json'),'utf8'));
assert.equal(report.scenarios.length,13);assert.ok(report.scenarios.every(s=>s.status==='passed'));assert.deepEqual(report.errors,[]);
const delta=(Date.parse(after.date+'Z')-Date.parse(before.date+'Z'))/86400000;assert.equal(delta,180);
for(const p of before.lcs.pool){const q=after.lcs.pool.find(x=>x.id===p.id);assert.ok(q);assert.equal(q.alive,p.alive);assert.equal(q.daysSinceJoined,p.daysSinceJoined+180);}
const income=after.ledger.totalIncome-before.ledger.totalIncome,expenses=after.ledger.totalExpense-before.ledger.totalExpense;assert.equal(after.ledger._funds,before.ledger._funds+income-expenses);
assert.equal(evac.lcs.vehiclePool.length,2);assert.equal(first.lcs.squads.length,3);assert.equal(first.lcs.pool.length,15);assert.equal(first.lcs.pool.filter(p=>p.sleeperAgent).length,2);
const buildHash=hash(await readFile(resolve(root,'upstream/build/web/main.dart.js')));const servedHash=hash(Buffer.from(await(await fetch('http://127.0.0.1:8766/main.dart.js')).arrayBuffer()));assert.equal(buildHash,servedHash);assert.equal(report.runtimeSha256,buildHash);
const tests=await readFile(resolve(out,'full-tests.log'),'utf8');const count=+tests.match(/\+(\d+): All tests passed!/)[1];assert.ok(count>=503);assert.match(await readFile(resolve(out,'analysis.log'),'utf8'),/No issues found/);
const frozen=JSON.parse(await readFile(resolve(out,'frozen-manifest-audit.json'),'utf8'));assert.deepEqual(frozen.mismatches,[]);
const summary={frozenBrowserBuild:resolve(out,'browser-build'),verifiedServiceWorkerManifest:frozen,buildInjectionLog:(await readFile(resolve(out,'service-worker.log'),'utf8')).trim(),date:'2026-10-15',origin:report.origin,testsPassed:count,analysis:'No issues found',webBuild:'passed',serviceWorker:{version:frozen.version,resources:frozen.resources,bytes:frozen.bytes,crcAudit:'all resources match'},runtimeSha256:buildHash,servedSha256:servedHash,browserErrors:report.errors,browserScenarios:report.scenarios.map(s=>({label:s.label,status:s.status,runtimeSha256:s.runtimeSha256})),naturalCampaign:{start:before.date,end:after.date,additionalDays:delta,originalCrewPreserved:true,allFiveAlive:after.lcs.pool.every(p=>p.alive),startingFunds:before.ledger._funds,endingFunds:after.ledger._funds,income,expenses,accountingReconciles:true},organisation:{people:first.lcs.pool.length,squads:first.lcs.squads.length,sleepers:first.lcs.pool.filter(p=>p.sleeperAgent).length,monthEnd:first.date,recordedIncome:first.ledger.totalIncome},escape:{retainedVehicles:evac.lcs.vehiclePool.length,locations:evac.lcs.vehiclePool.map(v=>v.locationId)},readiness:'All five requested follow-up areas exercised. Rare cases use prepared and sometimes amplified fixtures; this is not balance certification or a naturally earned victory.'};
await writeFile(resolve(out,'validation-summary.json'),JSON.stringify(summary,null,2));console.log(JSON.stringify(summary,null,2));
