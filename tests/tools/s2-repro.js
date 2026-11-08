'use strict';
const W=require('path').resolve(__dirname,'../..');
const { Sim } = require(W+'/tests/sim/sim.js');
const NM=+process.env.NM||10, ST=+process.env.ST||300;
const sim = new Sim({ seed: 7303 });
sim.addMember('Gm',0); sim.addMember('Of1',1); sim.addMember('Of2',1);
for (let i=1;i<=NM;i++) sim.addMember('Mb'+i,5);
const cs = sim.roster.map(r=>sim.client(r.name));
for (const c of cs) { c.login(); sim.run(0.5+sim.rand()); }
cs[0].run('return A.SaveSettings({ squadsEnabled = true, bench = 2, minCreateRank = 9, officerRanks = { 1 }, banned = {}, compEnabled = true })');
const t0=Date.now();
const ok=sim.settle(ST,10);
console.log('converged',ok,'simt',Math.round(sim.t),'real',(Date.now()-t0)/1000);
const ids = c => c.val('(function() local t={} for k,r in pairs(NS.state) do if type(r)=="table" then for id,_ in pairs(r) do t[#t+1]=k..":"..tostring(id) end end end table.sort(t) return table.concat(t," ") end)()')[0].split(' ');
const all=new Set(); const per={};
for (const c of cs){ per[c.name]=new Set(ids(c)); per[c.name].forEach(x=>all.add(x)); }
for (const c of cs){ const miss=[...all].filter(x=>!per[c.name].has(x)); if(miss.length) console.log(c.name,'missing',miss.length,miss.slice(0,8).join(' ')); }
console.log(JSON.stringify(sim.stats));
