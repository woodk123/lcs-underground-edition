import {readFile,writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
const base=resolve(import.meta.dirname,'../reports/campaign-systems-20261015/browser-build');
const source=await readFile(resolve(base,'sw.js'),'utf8');const resources=JSON.parse(source.match(/const RESOURCES = (\{[^\n]+\});/)[1]);
const table=Array.from({length:256},(_,n)=>{for(let k=0;k<8;k++)n=n&1?0xedb88320^(n>>>1):n>>>1;return n>>>0;});
const crc=b=>{let c=0xffffffff;for(const x of b)c=table[(c^x)&255]^(c>>>8);return((c^0xffffffff)>>>0).toString(16);};
const mismatches=[];let bytes=0;for(const [path,expected]of Object.entries(resources)){const b=await readFile(resolve(base,path));bytes+=b.length;const actual=crc(b);if(actual!==expected)mismatches.push({path,expected,actual});}
const result={resources:Object.keys(resources).length,bytes,version:source.match(/const VERSION = '([^']+)'/)[1],mismatches};await writeFile(resolve(base,'../frozen-manifest-audit.json'),JSON.stringify(result,null,2));console.log(JSON.stringify(result));if(mismatches.length)process.exitCode=1;
