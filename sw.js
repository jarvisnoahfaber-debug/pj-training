const C="pj-training-v4",DBC="pj-db-v1";const FILES=["./","index.html","manifest.json","icon-180.png","icon-512.png"];
const DBHOSTS=["cdn.jsdelivr.net","raw.githubusercontent.com"];
self.addEventListener("install",e=>{e.waitUntil(caches.open(C).then(c=>c.addAll(FILES)));self.skipWaiting()});
self.addEventListener("activate",e=>{e.waitUntil(caches.keys().then(k=>Promise.all(k.filter(x=>x!==C&&x!==DBC).map(x=>caches.delete(x)))));self.clients.claim()});
self.addEventListener("fetch",e=>{
  if(e.request.method!=="GET")return;const u=new URL(e.request.url);
  if(DBHOSTS.includes(u.hostname)){ // Übungsdatenbank + Bilder: einmal laden, dann offline aus dem Speicher
    e.respondWith(caches.open(DBC).then(async c=>{const hit=await c.match(e.request);if(hit)return hit;const r=await fetch(e.request);if(r.ok||r.type==="opaque")c.put(e.request,r.clone());return r}));return}
  if(u.origin!==location.origin)return;
  e.respondWith(caches.open(C).then(async c=>{const hit=await c.match(e.request,{ignoreSearch:true});const net=fetch(e.request).then(r=>{if(r.ok)c.put(e.request,r.clone());return r}).catch(()=>hit);return hit||net}))});
