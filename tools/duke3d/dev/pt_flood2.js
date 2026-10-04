const fs=require('fs');const L=process.argv[2]||'E1L1'
const raw={};for(const n of ['E1L1','E1L2','E1L3','E1L4','E1L5','E1L6'])raw[n]=JSON.parse(fs.readFileSync('dist/duke/maps/'+n+'.json'))
globalThis.blockmashDukeMaps=raw;globalThis.blockmashDukeTiles=JSON.parse(fs.readFileSync('dist/duke/manifest.json')).tiles
const {getDuke}=require(process.cwd()+'/src/mashup/surface/dukeworld');const {makePhys,doorOpen,liftTarget,transports}=require(process.cwd()+'/src/mashup/surface/dukephys')
const d=getDuke().maps.find(m=>m.name===L);const S=d.m.sectors;const Y=z=>d.zToY(z)
// open every door
S.forEach((s,si)=>{const o=doorOpen(d.m,si);if(o){s.fz=o.f1;s.cz=o.c1;s.__open=true}})
const {explosives}=require(process.cwd()+'/src/mashup/surface/dukephys');for(const b of explosives(d)){S[b.si].fz=b.f1;S[b.si].cz=b.c1;S[b.si].__open=true}
const lifts=new Map();S.forEach((s,si)=>{const t=liftTarget(d.m,si);if(t){lifts.set(si,{f1:Math.min(t.f1,s.fz),lo:Math.max(t.f1,s.fz)});s.fz=Math.max(t.f1,s.fz)}})
const P=makePhys(d);const T=transports(d)
const goals=d.m.sprites.filter(s=>s.pic===142&&Math.abs(s.x)<1e6).map(s=>{const w=d.toWorld(s.x,s.y);return {x:w.x,z:w.z,y:Y(s.z)}})
const key=(x,z,y)=>Math.round(x*2)+','+Math.round(z*2)+','+Math.round(y*2)
const seen=new Set();const q=[];const push=(x,z,y,from)=>{const k=key(x,z,y);if(seen.has(k))return;seen.add(k);q.push({x,z,y,from})}
push(d.start.x,d.start.z,d.start.y,null)
let found=null;let n=0;const H=1.5,JUMP=2.0,STEP=0.8
const dirs=[];for(let a=0;a<8;a++)dirs.push([Math.cos(a*Math.PI/4)*0.5,Math.sin(a*Math.PI/4)*0.5])
while(q.length&&n<(+process.env.MAXN||400000)){const s=q.shift();n++
 for(const g of goals)if(Math.hypot(g.x-s.x,g.z-s.z)<1.4&&Math.abs(g.y-(s.y+1))<2.5){found=s;break};if(found)break
 const sec=P.sectorFor(s.x,s.z,s.y)
 for(const t of T)if(t.from===sec&&s.y<Y(S[sec].fz)+1.5){const nx=s.x+t.dx,nz=s.z+t.dz;const g=P.ground(nx,nz,s.y+t.dy);if(g)push(nx,nz,g.floor,s)}
 if(lifts.has(sec)&&Math.abs(s.y-Y(lifts.get(sec).lo))<0.1){push(s.x,s.z,Y(lifts.get(sec).f1),s)}
 for(const [dx,dz] of dirs){ // running jump, simulated like the client controller
  {let x=s.x,z=s.z,y=s.y,vy=0.5,ok=false;for(let t=0;t<24;t++){const r=P.slide(x,z,y,dx*0.5,dz*0.5,0.3,1.5);x=r.x;z=r.z;const g=P.ground(x,z,y);y+=vy;vy=(vy-0.08)*0.98;if(!g)break;if(y+1.5>g.ceil){y=Math.min(y,g.ceil-1.5);if(vy>0)vy=0}if(y<=g.floor){y=g.floor;ok=true;break}}
   if(ok&&Math.hypot(x-s.x,z-s.z)>0.6)push(x,z,y,s)}
for(const [hy,h] of [[0,H],[JUMP,0.9],[0,0.9]]){const yy=s.y+hy;const r=P.slide(s.x,s.z,yy,dx,dz,0.3,h,STEP);if(Math.hypot(r.x-s.x,r.z-s.z)<0.2)continue;const g=P.ground(r.x,r.z,yy,0.3,STEP);if(!g)continue;if(g.ceil-g.floor<0.9)continue;push(r.x,r.z,g.floor,s)}}}
console.log(L,'states',n,'found',!!found)
if(found){let c=found,k=0;const path=[];while(c){path.unshift(c);c=c.from};console.log('path len',path.length,'start',path[0],'end',found);fs.writeFileSync('/tmp/'+L+'_path.json',JSON.stringify(path.map(p=>[+p.x.toFixed(2),+p.y.toFixed(2),+p.z.toFixed(2)])))}
else{ // report farthest/highest reached sectors
 const secs=new Set();for(const k of seen){const [x,z,y]=k.split(',').map(Number);secs.add(P.sectorFor(x/2,z/2,y/2))};console.log('sectors reached',secs.size,'of',S.length,[...secs].join(' '))}
const W=d.m.walls;const secs=new Set();for(const k of seen){const [x,z,y]=k.split(',').map(Number);secs.add(P.sectorFor(x/2,z/2,y/2))};secs.delete(-1)
const area=si=>{let a=0;for(let i=S[si].wallptr;i<S[si].wallptr+S[si].wallnum;i++){const p=W[i],q=W[p.p2];a+=p.x*q.y-q.x*p.y}return Math.abs(a)/2/512/512}
const out=new Map()
for(const s of secs)for(let i=S[s].wallptr;i<S[s].wallptr+S[s].wallnum;i++){const w=W[i],n=w.ns;if(n<0||secs.has(n)||area(n)<0.6)continue;const up=Y(S[n].fz)-Y(S[s].fz);const gap=Math.min(Y(S[n].cz),Y(S[s].cz))-Math.max(Y(S[n].fz),Y(S[s].fz));const a=d.toWorld(w.x,w.y);const k=s+'->'+n;if(!out.has(k))out.set(k,`${k} lt${S[n].lotag} up ${up.toFixed(2)} gap ${gap.toFixed(2)} area ${area(n).toFixed(1)} at ${a.x.toFixed(1)},${a.z.toFixed(1)} wcst ${w.cstat}`)}
console.log([...out.values()].join('\n'))
console.log("key",[55,69,223,295,219,220,221,222,218,203,215,216,217,165,166,257,138,110,111,112,108,229].map(s=>s+(secs.has(s)?'Y':'n')).join(' '))
