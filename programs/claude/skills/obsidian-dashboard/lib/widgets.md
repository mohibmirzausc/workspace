# Widget cookbook

Copy-paste dataviewjs widgets. **Remember: one dataviewjs block per COLUMN** —
concatenate the widgets you want into one block's `innerHTML`, wrapped in a
flex-gap div. Each snippet below returns an `html` string fragment; combine them.

Column skeleton (this is the pattern — put chosen widgets between the markers):

    ```dataviewjs
    const NOISE = ["_Templates","_Scripts","_Experiments",".obsidian"];
    const clean = () => dv.pages().where(p => !NOISE.some(x => p.file.path.includes(x)));
    const pad = n => String(n).padStart(2,"0");
    const iso = d => `${d.getFullYear()}-${pad(d.getMonth()+1)}-${pad(d.getDate())}`;
    let html = "";

    // >>> paste widget fragments here, each appending to `html` <<<

    const T = dv.container;
    T.innerHTML = '<div style="display:flex;flex-direction:column;gap:8px;">' + html + '</div>';
    // >>> attach any listeners AFTER innerHTML (see interactive widgets) <<<
    ```

---

## Stats card
```js
const stat = (k,v)=>`<div class="stat"><span>${k}</span><span>${v}</span></div>`;
const pages = clean();
html += `<div class="widget" style="align-items:stretch;"><h1>STATS</h1>`
  + stat("NOTES", pages.length)
  + stat("OPEN TASKS", pages.file.tasks.where(t=>!t.completed).length)
  + stat("DONE TASKS", pages.file.tasks.where(t=>t.completed).length)
  + `</div>`;
```

## Tasks (click text → jump, checkbox → complete)
```js
const tasks = clean().file.tasks.where(t=>!t.completed).sort(t=>t.text,"asc").slice(0,8);
html += '<div class="widget" style="align-items:stretch;"><h1>TASKS</h1>';
if (!tasks.length) html += '<span style="font-size:small;opacity:.5;">All done ✨</span>';
else tasks.forEach(t => {
  const label = t.text.replace(/\[\[([^\]|]+)\|([^\]]+)\]\]/g,"$2").replace(/\[\[([^\]]+)\]\]/g,"$1")
    .replace(/#[\w/-]+/g,"").replace(/[🔺⏫🔼🔽🔁]/g,"").replace(/[📅⏳🛫✅]\s?\d{4}-\d{2}-\d{2}/g,"").replace(/\s+/g," ").trim();
  html += `<div style="display:flex;align-items:center;gap:10px;padding:6px 10px;background:var(--code-background);border-radius:var(--bases-cards-radius);font-size:small;">
    <input type="checkbox" style="width:16px;height:16px;accent-color:var(--text-accent);cursor:pointer;flex-shrink:0;" data-path="${t.path}" data-line="${t.line}">
    <span style="flex:1;text-align:left;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;cursor:pointer;" onclick="app.workspace.openLinkText('${t.path}','',false)">${label}</span></div>`;
});
html += '</div>';
// listener (after innerHTML):
// T.querySelectorAll('input[data-path]').forEach(cb => cb.addEventListener("click", async e => {
//   e.stopPropagation(); const f=app.vault.getAbstractFileByPath(cb.dataset.path); if(!f)return;
//   const L=(await app.vault.read(f)).split("\n"); const i=+cb.dataset.line;
//   if(L[i]){L[i]=L[i].replace("- [ ]","- [x]"); await app.vault.modify(f,L.join("\n"));} }));
```

## Mini calendar (this week, today highlighted, dots for daily notes)
```js
const DAILY = "Daily Notes"; // adjust to your daily-notes folder
const dailyExists = d => !!app.vault.getAbstractFileByPath(`${DAILY}/${iso(d)}.md`);
const today = new Date(), dow = today.getDay(), monOff = dow===0?-6:1-dow;
const start = new Date(today); start.setDate(today.getDate()+monOff);
const names = ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"];
html += '<div class="mini-calendar">';
for (let i=0;i<7;i++){ const d=new Date(start); d.setDate(start.getDate()+i);
  let c="cal-day"; if(d.toDateString()===today.toDateString())c+=" today"; else if(dailyExists(d))c+=" has-note";
  html += `<div class="${c}"><div class="cal-label">${names[i]}</div><div class="cal-num">${d.getDate()}</div></div>`; }
html += '</div>';
```

## Daily streak
```js
let streak=0; { const d=new Date(); let g=0; while(dailyExists(d)&&g<365){streak++; d.setDate(d.getDate()-1); g++;} }
html += `<div class="widget"><h1>STREAK</h1><span style="font-size:small;">${streak}d</span></div>`;
```

## Tag cloud (clickable → search)
```js
const counts={}; clean().file.etags.forEach(t=>{const k=t.replace(/^#/,""); counts[k]=(counts[k]||0)+1;});
html += '<div class="widget" style="padding:12px;"><h1>TAGS</h1><div style="display:flex;flex-wrap:wrap;gap:6px;justify-content:center;">';
Object.entries(counts).sort((a,b)=>b[1]-a[1]).slice(0,12).forEach(([t,c])=>{
  html += `<a href="obsidian://search?query=tag%3A${encodeURIComponent(t)}" style="background:var(--code-background);padding:4px 10px;border-radius:var(--bases-cards-radius);font-size:small;text-decoration:none;color:var(--text-normal);">#${t} (${c})</a>`; });
html += '</div></div>';
```

## Recent notes (built as divs — avoids the <ul> width gotcha)
```js
const recent = clean().where(p=>!/^(readme|index)$/i.test(p.file.name)).sort(p=>p.file.mtime,"desc").slice(0,8);
html += '<div class="recent-notes"><ul>';
recent.forEach(p => {
  const date = new Date(p.file.mtime).toLocaleDateString(undefined,{day:"numeric",month:"short"});
  html += `<li onclick="app.workspace.openLinkText('${p.file.path.replace(/'/g,"\\'")}','',false)" style="cursor:pointer;">
    <a class="internal-link">${p.file.name}</a><span class="recent-date">${date}</span></li>`;
});
html += '</ul></div>';
```

## Quick-access nav buttons
```js
const NAV = [["Home","obsidian://open?file=Home"],["Tasks","obsidian://search?query=path%3ATasks"]];
html += '<div style="display:flex;flex-direction:column;gap:8px;">';
NAV.forEach(([label,href]) => html += `<a class="nav-item" href="${href}">${label}</a>`);
html += '</div>';
```

## Interactive habit tracker (state in a per-day note's frontmatter)
```js
const HABITS = ["Exercise","Read","Meditate"];
const DIR = "Habits";
const path = `${DIR}/${iso(new Date())}.md`;
let file = app.vault.getAbstractFileByPath(path);
if (!file) { if(!app.vault.getAbstractFileByPath(DIR)) await app.vault.createFolder(DIR).catch(()=>{});
  file = await app.vault.create(path, `---\n${HABITS.map(h=>`${h}: false`).join("\n")}\n---\n`); }
const fm = (await app.vault.read(file)).split("---")[1] || "";
html += '<div class="widget" style="align-items:stretch;"><h1>HABITS</h1>';
HABITS.forEach(h => { const on = new RegExp(`^${h}:\\s*true\\s*$`,"m").test(fm);
  html += `<div style="display:flex;align-items:center;gap:10px;padding:6px 10px;background:var(--code-background);border-radius:var(--bases-cards-radius);font-size:small;">
    <input type="checkbox" ${on?"checked":""} style="width:16px;height:16px;accent-color:var(--text-accent);cursor:pointer;" data-habit="${h}">
    <span style="opacity:${on?".9":".5"};">${h}</span></div>`; });
html += '</div>';
// listener (after innerHTML):
// T.querySelectorAll('input[data-habit]').forEach(cb => cb.addEventListener("click", async () => {
//   const f=app.vault.getAbstractFileByPath(path); const L=(await app.vault.read(f)).split("\n");
//   const i=L.findIndex(l=>l.startsWith(cb.dataset.habit+":"));
//   if(i>=0){L[i]=`${cb.dataset.habit}: ${cb.checked}`; await app.vault.modify(f,L.join("\n"));} }));
```

## Chart (Charts plugin — habit trend / metric over time)
```js
const labels=[], data=[];
for (let i=6;i>=0;i--){ const d=new Date(); d.setDate(d.getDate()-i);
  labels.push(`${pad(d.getMonth()+1)}/${pad(d.getDate())}`); data.push(/* compute value for d */ 0); }
window.renderChart({ type:"bar", data:{ labels, datasets:[{ label:"Metric", data }] },
  options:{ scales:{ y:{ beginAtZero:true } } } }, this.container);
```

## Progress bar (any ratio — task completion, goal, etc.)
```js
const pct = total ? Math.round(100*done/total) : 0;
html += `<div class="widget" style="align-items:stretch;"><h1>PROGRESS</h1>
  <div style="height:8px;border-radius:6px;background:var(--background-modifier-border);overflow:hidden;"><div style="height:100%;width:${pct}%;background:var(--text-accent);"></div></div>
  <div style="text-align:center;font-size:small;opacity:.7;">${pct}%</div></div>`;
```

## Observability widgets (vault-health / status dashboards)

Vitals (counts):
```js
const stat=(k,v)=>`<div class="stat"><span>${k}</span><span>${v}</span></div>`;
const p = clean();
html += `<div class="widget" style="align-items:stretch;"><h1>VITALS</h1>`
  + stat("NOTES", p.length)
  + stat("TASKS", p.file.tasks.length)
  + stat("TAGS", new Set(p.file.etags.array()).size)
  + `</div>`;
```

Orphan notes (no inbound or outbound links):
```js
const orphans = clean().where(x => x.file.inlinks.length===0 && x.file.outlinks.length===0
  && !/^(readme|index)$/i.test(x.file.name)).sort(x=>x.file.mtime,"desc").slice(0,10);
html += '<div class="widget" style="align-items:stretch;"><h1>ORPHANS</h1>';
if (!orphans.length) html += '<span style="font-size:small;opacity:.5;">None 🎉</span>';
else orphans.forEach(x => html += `<div style="padding:6px 10px;background:var(--code-background);border-radius:var(--bases-cards-radius);font-size:small;cursor:pointer;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;" onclick="app.workspace.openLinkText('${x.file.path.replace(/'/g,"\\'")}','',false)">${x.file.name}</div>`);
html += '</div>';
```

Stale notes (untouched longest — sort mtime ascending):
```js
const stale = clean().where(x=>!/^(readme|index)$/i.test(x.file.name)).sort(x=>x.file.mtime,"asc").slice(0,8);
html += '<div class="widget" style="align-items:stretch;"><h1>STALE</h1>';
stale.forEach(x => { const d=new Date(x.file.mtime).toLocaleDateString(undefined,{month:"short",day:"numeric"});
  html += `<div style="display:flex;justify-content:space-between;gap:8px;padding:6px 10px;background:var(--code-background);border-radius:var(--bases-cards-radius);font-size:small;cursor:pointer;" onclick="app.workspace.openLinkText('${x.file.path.replace(/'/g,"\\'")}','',false)"><span style="overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${x.file.name}</span><span style="opacity:.5;flex-shrink:0;">${d}</span></div>`; });
html += '</div>';
```

Top folders (bar chart by note count — tally + max-normalized bars):
```js
const folders={}; clean().forEach(x=>{const f=x.file.folder||"(root)"; folders[f]=(folders[f]||0)+1;});
const top=Object.entries(folders).sort((a,b)=>b[1]-a[1]).slice(0,6);
const max=top.length?top[0][1]:1;
html += '<div class="widget" style="align-items:stretch;"><h1>TOP FOLDERS</h1>';
top.forEach(([f,n])=>{ const w=Math.round(100*n/max);
  html += `<div style="padding:6px 10px;background:var(--code-background);border-radius:var(--bases-cards-radius);font-size:small;"><div style="display:flex;justify-content:space-between;"><span style="overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">${f.split("/").pop()||f}</span><span style="opacity:.6;">${n}</span></div><div style="height:5px;border-radius:4px;background:var(--background-modifier-border);margin-top:3px;overflow:hidden;"><div style="height:100%;width:${w}%;background:var(--text-accent);"></div></div></div>`; });
html += '</div>';
```

## Professional polish CSS (add to the snippet — powers the pretty widgets)

Replace `.dash` with your class. These classes are used by the "pretty" widget
variants below.
```css
.dash { --color-blue:#4772fa; --color-green:#22c55e; --color-purple:#a855f7; --color-orange:#f59e0b; --color-red:#ef4444; }
/* big-number stat tiles */
.dash .tile-grid { display:grid; grid-template-columns:1fr 1fr; gap:8px; width:100%; }
.dash .tile { background:var(--background-primary); border-radius:12px; padding:12px 10px; display:flex; flex-direction:column; align-items:center; gap:2px; border-left:3px solid var(--a,var(--text-accent)); transition:transform .15s ease; }
.dash .tile:hover { transform:translateY(-2px); }
.dash .tile-icon { font-size:1.1rem; }
.dash .tile-val { font-size:1.6rem; font-weight:800; color:var(--a,var(--text-accent)); line-height:1; }
.dash .tile-label { font-size:.7rem; text-transform:uppercase; letter-spacing:.08em; opacity:.6; }
/* completion ring */
.dash .ring { width:110px; height:110px; border-radius:50%; margin:4px auto; background:conic-gradient(var(--text-accent) calc(var(--pct)*1%), var(--background-modifier-border) 0); display:flex; align-items:center; justify-content:center; }
.dash .ring-inner { width:82px; height:82px; border-radius:50%; background:var(--code-background); display:flex; align-items:center; justify-content:center; font-size:1.5rem; font-weight:800; color:var(--text-accent); }
/* sub-caption, badge, empty */
.dash .sub { font-size:.72rem; opacity:.55; margin:-4px 0 6px; text-align:center; }
.dash .badge { background:var(--text-accent); color:var(--bg-color); border-radius:999px; padding:1px 8px; font-size:.7rem; font-weight:700; margin-left:6px; }
.dash .empty { text-align:center; font-size:small; opacity:.5; padding:8px; }
/* hover rows */
.dash .row { display:flex; align-items:center; gap:8px; padding:8px 10px; background:var(--background-primary); border-radius:10px; font-size:small; cursor:pointer; transition:background .15s ease, transform .15s ease; }
.dash .row:hover { background:var(--background-modifier-hover); transform:translateX(3px); }
.dash .row-dot { width:8px; height:8px; border-radius:50%; background:var(--a,var(--text-accent)); flex-shrink:0; }
.dash .row-text { flex:1; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
.dash .row-meta { opacity:.5; font-size:.72rem; flex-shrink:0; }
.dash .row-arrow { opacity:0; transition:opacity .15s ease; color:var(--text-accent); }
.dash .row:hover .row-arrow { opacity:1; }
/* labeled bars */
.dash .bar-row { padding:5px 2px; }
.dash .bar-head { display:flex; justify-content:space-between; font-size:small; margin-bottom:4px; }
.dash .bar-track { height:7px; border-radius:5px; background:var(--background-modifier-border); overflow:hidden; }
.dash .bar-fill { height:100%; border-radius:5px; background:linear-gradient(90deg,var(--color-blue),var(--text-accent)); }
```

## Pretty stat tiles (2×2 big numbers with icons + color)
```js
const tile=(icon,label,val,accent)=>`<div class="tile" style="--a:${accent};"><div class="tile-icon">${icon}</div><div class="tile-val">${val}</div><div class="tile-label">${label}</div></div>`;
const p = clean();
html += `<div class="widget" style="align-items:stretch;"><h1>📊 Vitals</h1><div class="tile-grid">`
  + tile("📝","Notes",p.length,"var(--color-blue)")
  + tile("✅","Tasks",p.file.tasks.length,"var(--color-green)")
  + tile("🏷️","Tags",new Set(p.file.etags.array()).size,"var(--color-purple)")
  + `</div></div>`;
```

## Completion ring (conic-gradient donut)
```js
const done=/*n*/0, open=/*n*/0, pct=(open+done)?Math.round(100*done/(open+done)):0;
html += `<div class="widget"><h1>🎯 Completion</h1>
  <div class="ring" style="--pct:${pct};"><div class="ring-inner">${pct}%</div></div>
  <div style="display:flex;gap:14px;font-size:small;opacity:.75;"><span>🟢 ${done}</span><span>⚪ ${open}</span></div></div>`;
```

## Pretty hover row (for any list — orphans, stale, links)
```js
html += `<div class="row" onclick="app.workspace.openLinkText('${path.replace(/'/g,"\\'")}','',false)">
  <span class="row-dot" style="--a:var(--color-red);"></span>
  <span class="row-text">${name}</span><span class="row-arrow">→</span></div>`;
```

## Embedded Base (native DB view of notes) — outside the columns
```
## PROJECTS
![[Projects.base]]
```
Bases operate on note **frontmatter**, not task checkboxes — great for a
project/metadata DB, not for individual tasks.
