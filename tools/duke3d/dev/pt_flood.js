const fs=require('fs');const L=process.argv[2]||'E1L1'
const raw={};for(const n of ['E1L1','E1L2','E1L3','E1L4','E1L5','E1L6'])raw[n]=JSON.parse(fs.readFileSync('dist/duke/maps/'+n+'.json'))
globalThis.blockmashDukeMaps=raw;globalThis.blockmashDukeTiles=JSON.parse(fs.readFileSync('dist/duke/manifest.json')).tiles
const {getDuke}=require('./src/mashup/surface/dukeworld');const {makePhys,doorOpen,liftTarget,transports}=require('./src/mashup/surface/dukephys')
const d=getDuke().maps.find(m=>m.name===L);const S=d.m.sectors;const Y=z=>d.zToY(z)
// open every door
S.forEach((s,si)=>{const o=doorOpen(d.m,si);if(o){s.fz=o.f1;s.cz=o.c1;s.__open=true}})
const lifts=new Map();S.forEach((s,si)=>{const t=liftTarget(d.m,si);if(t)lifts.set(si,t)})
const P=makePhys(d);const T=transports(d)
const goals=d.m.sprites.filter(s=>s.pic===142&&Math.abs(s.x)<1e6).map(s=>{const w=d.toWorld(s.x,s.y);return {x:w.x,z:w.z,y:Y(s.z)}})
const key=(x,z,y)=>Math.round(x*2)+','+Math.round(z*2)+','+Math.round(y*2)
const seen=new Set();const q=[];const push=(x,z,y,from)=>{const k=key(x,z,y);if(seen.has(k))return;seen.add(k);q.push({x,z,y,from})}
push(d.start.x,d.start.z,d.start.y,null)
let found=null;let n=0;const H=1.5,JUMP=1.7,STEP=0.8
const dirs=[];for(let a=0;a<8;a++)dirs.push([Math.cos(a*Math.PI/4)*0.5,Math.sin(a*Math.PI/4)*0.5])
while(q.length&&n<400000){const s=q.shift();n++
 for(const g of goals)if(Math.hypot(g.x-s.x,g.z-s.z)<1.4&&Math.abs(g.y-(s.y+1))<2.5){found=s;break};if(found)break
 const sec=P.sectorFor(s.x,s.z,s.y)
 for(const t of T)if(t.from===sec&&s.y<Y(S[sec].fz)+1.5){const nx=s.x+t.dx,nz=s.z+t.dz;const g=P.ground(nx,nz,s.y+t.dy);if(g)push(nx,nz,g.floor,s)}
 if(lifts.has(sec)){push(s.x,s.z,Y(lifts.get(sec).f1),s);push(s.x,s.z,Y(d.m.sectors[sec].fz),s)}
 for(const [dx,dz] of dirs){for(const [hy,h] of [[0,H],[JUMP,0.9],[0,0.9]]){const yy=s.y+hy;const r=P.slide(s.x,s.z,yy,dx,dz,0.3,h,STEP);if(Math.hypot(r.x-s.x,r.z-s.z)<0.2)continue;const g=P.ground(r.x,r.z,yy,0.3,STEP);if(!g)continue;if(g.ceil-g.floor<0.9)continue;push(r.x,r.z,g.floor,s)}}}
console.log(L,'states',n,'found',!!found)
if(found){let c=found,k=0;const path=[];while(c){path.unshift(c);c=c.from};console.log('path len',path.length,'start',path[0],'end',found)}
else{ // report farthest/highest reached sectors
 const secs=new Set();for(const k of seen){const [x,z,y]=k.split(',').map(Number);secs.add(P.sectorFor(x/2,z/2,y/2))};console.log('sectors reached',secs.size,'of',S.length,[...secs].join(' '))}
{const secs=new Set();for(const k of seen){const [x,z,y]=k.split(',').map(Number);secs.add(P.sectorFor(x/2,z/2,y/2))}
const W=d.m.walls;secs.delete(-1);for(const s of secs)for(let i=S[s].wallptr;i<S[s].wallptr+S[s].wallnum;i++){const w=W[i],n=w.ns;if(n<0||secs.has(n))continue;const up=Y(S[n].fz)-Y(S[s].fz);const gap=Math.min(Y(S[n].cz),Y(S[s].cz))-Math.max(Y(S[n].fz),Y(S[s].fz));if(up<=1.6&&gap>=0.95){const a=d.toWorld(w.x,w.y),b=d.toWorld(W[w.p2].x,W[w.p2].y);console.log(s,'->',n,'up',up.toFixed(2),'gap',gap.toFixed(2),'len',Math.hypot(a.x-b.x,a.z-b.z).toFixed(2),'at',a.x.toFixed(1),a.z.toFixed(1))}}}
