/* ============================================================
   deep-brief · intake form engine  (v1)

   Drop-in engine for the intake section of a deep-brief page.
   Extracted from the MOD-132 reference brief after browser
   testing; includes three fixes that a code-read misses:

     1. EVENT DELEGATION from document for the action buttons.
        render() replaces #form-root's children on every radio/
        checkbox change, so handlers bound inside it die. A click
        landing before a deferred re-bind silently does nothing.
        This was a REAL bug caught only by clicking in a browser.

     2. #out lives OUTSIDE #form-root (insertAdjacentElement
        "afterend") so re-renders cannot destroy the output block.

     3. Clipboard fallback via execCommand for non-secure
        contexts (file:// has no navigator.clipboard).

   USAGE
   -----
   Define FORM_ID and SCHEMA above this file's contents, provide
   a <div id="form-root"></div> in the page, then include this.
   Supported question types: text, number, textarea, radio,
   checkbox. Optional per-question: hint, placeholder, prefill,
   showIf {id, equals|in}.

   Every non-matrix question automatically gets a
   "note to Claude" talk-back textarea. Output is a fenced
   INTAKE-JSON block, compatible with the intake-form skill.
   State autosaves to localStorage under "intake:<FORM_ID>".
   ============================================================ */

/* ---------------- engine ---------------- */
const KEY="intake:"+FORM_ID;
let state={};
try{ state=JSON.parse(localStorage.getItem(KEY)||"{}") }catch(e){ state={} }
const save=()=>{ try{localStorage.setItem(KEY,JSON.stringify(state))}catch(e){} };

function visible(q){
  if(!q.showIf) return true;
  const src=state[q.showIf.id]&&state[q.showIf.id].value;
  if(src==null||src==="") return false;
  if(q.showIf.equals!=null) return Array.isArray(src)?src.includes(q.showIf.equals):src===q.showIf.equals;
  if(q.showIf.in) return Array.isArray(src)?src.some(v=>q.showIf.in.includes(v)):q.showIf.in.includes(src);
  return true;
}
const get=id=>state[id]||(state[id]={value:"",note:""});

function render(){
  const root=document.getElementById("form-root");
  root.innerHTML="";
  SCHEMA.forEach(sec=>{
    const s=document.createElement("section"); s.className="fsec";
    const vis=sec.questions.filter(visible);
    s.innerHTML='<header><h3><span>'+(sec.ico||"")+'</span><span>'+sec.title+'</span></h3>'+
                (sec.sub?'<p class="fsub">'+sec.sub+'</p>':'')+'</header>';
    const box=document.createElement("div"); box.className="qs";
    vis.forEach(q=>box.appendChild(field(q)));
    s.appendChild(box); root.appendChild(s);
  });
  root.appendChild(bar());
  // a prior Generate should keep its Copy button available across re-renders
  if(window.__lastOut){
    const cb=document.getElementById("copyBtn"); if(cb) cb.style.display="inline-block";
  }
  progress();
}

function field(q){
  const d=document.createElement("div"); d.className="q";
  const st=get(q.id);
  const lab=document.createElement("label"); lab.className="qlab"; lab.textContent=q.label; d.appendChild(lab);
  if(q.hint){ const h=document.createElement("p"); h.className="hint"; h.textContent=q.hint; d.appendChild(h); }

  if(q.type==="text"||q.type==="number"){
    const i=document.createElement("input");
    i.type=q.type==="number"?"number":"text";
    i.placeholder=q.placeholder||""; i.value=st.value||q.prefill||"";
    if(!st.value&&q.prefill) st.value=q.prefill;
    i.oninput=e=>{st.value=e.target.value; save(); progress()};
    d.appendChild(i);
  } else if(q.type==="textarea"){
    const t=document.createElement("textarea");
    t.placeholder=q.placeholder||""; t.value=st.value||"";
    t.oninput=e=>{st.value=e.target.value; save(); progress()};
    d.appendChild(t);
  } else if(q.type==="radio"||q.type==="checkbox"){
    const wrap=document.createElement("div"); wrap.className="opts";
    if(q.type==="checkbox"&&!Array.isArray(st.value)) st.value=Array.isArray(q.prefill)?q.prefill.slice():[];
    if(q.type==="radio"&&!st.value&&q.prefill) st.value=q.prefill;
    q.options.forEach((o,ix)=>{
      const l=document.createElement("label"); l.className="opt";
      const inp=document.createElement("input");
      inp.type=q.type; inp.name=q.id+"_"+FORM_ID; inp.value=o;
      inp.checked = q.type==="radio" ? st.value===o : (st.value||[]).includes(o);
      if(inp.checked) l.classList.add("sel");
      inp.onchange=()=>{
        if(q.type==="radio"){ st.value=o; }
        else { const a=new Set(st.value||[]); inp.checked?a.add(o):a.delete(o); st.value=[...a]; }
        save(); render();
      };
      const sp=document.createElement("span"); sp.textContent=o;
      l.appendChild(inp); l.appendChild(sp); wrap.appendChild(l);
    });
    d.appendChild(wrap);
  }

  const nd=document.createElement("details"); nd.className="note";
  if(st.note) nd.open=true;
  const ns=document.createElement("summary"); ns.textContent="note to Claude";
  const nt=document.createElement("textarea");
  nt.placeholder="Talk back — disagree, add nuance, or explain why you skipped this.";
  nt.value=st.note||"";
  nt.oninput=e=>{st.note=e.target.value; save()};
  nd.appendChild(ns); nd.appendChild(nt); d.appendChild(nd);
  return d;
}

function allVisible(){ return SCHEMA.flatMap(s=>s.questions).filter(visible); }
function answered(q){
  const st=state[q.id]; if(!st) return false;
  return Array.isArray(st.value) ? st.value.length>0 : String(st.value||"").trim()!=="";
}
function progress(){
  const v=allVisible(), n=v.filter(answered).length;
  const el=document.getElementById("cnt"); if(!el) return;
  el.textContent=n+" / "+v.length;
  document.getElementById("pfill").style.width=(v.length?100*n/v.length:0)+"%";
}

function bar(){
  const b=document.createElement("div"); b.id="fbar";
  b.innerHTML='<span class="pr">Answered <b id="cnt">0 / 0</b></span>'+
    '<span class="pbar"><i id="pfill"></i></span>'+
    '<span style="display:flex;gap:9px;flex-wrap:wrap">'+
    '<button type="button" id="genBtn">Generate</button>'+
    '<button type="button" id="copyBtn" style="display:none">Copy JSON</button>'+
    '<button type="button" id="clrBtn" class="ghost">Reset</button></span>';
  return b;
}

/* Event delegation on a stable ancestor. render() replaces #form-root's children,
   so per-element handlers bound inside it die on every re-render (and a click
   landing before a deferred re-bind would silently do nothing). Delegation from
   document survives all re-renders. */
document.addEventListener("click",e=>{
  const t=e.target.closest && e.target.closest("button");
  if(!t) return;
  if(t.id==="genBtn"){ e.preventDefault(); gen(); }
  else if(t.id==="copyBtn"){
    e.preventDefault();
    const txt=window.__lastOut||"";
    if(!txt){ toast("Hit Generate first"); return; }
    const fallback=()=>{
      const ta=document.createElement("textarea");
      ta.value=txt; ta.style.position="fixed"; ta.style.opacity="0";
      document.body.appendChild(ta); ta.select();
      let ok=false; try{ ok=document.execCommand("copy") }catch(_){}
      document.body.removeChild(ta);
      toast(ok?"Copied — paste to Claude":"Copy blocked — select the block manually");
    };
    if(navigator.clipboard&&navigator.clipboard.writeText){
      navigator.clipboard.writeText(txt).then(()=>toast("Copied — paste to Claude"),fallback);
    } else fallback();
  }
  else if(t.id==="clrBtn"){
    e.preventDefault();
    if(confirm("Clear all answers on this form?")){
      state={}; save(); render();
      const o=document.getElementById("out"); if(o){ o.style.display="none"; o.textContent=""; }
      window.__lastOut="";
      const cb=document.getElementById("copyBtn"); if(cb) cb.style.display="none";
      toast("Cleared");
    }
  }
});

function gen(){
  const answers={}, human=[];
  SCHEMA.forEach(sec=>{
    const rows=[];
    sec.questions.filter(visible).forEach(q=>{
      const st=state[q.id]||{};
      const has=Array.isArray(st.value)?st.value.length>0:String(st.value||"").trim()!=="";
      if(!has && !st.note){ answers[q.id]={skipped:true}; rows.push("  · "+q.label+" — (skipped)"); return; }
      answers[q.id]={value:st.value||"", note:st.note||""};
      const shown=Array.isArray(st.value)?st.value.join(", "):st.value;
      rows.push("  · "+q.label+" → "+(shown||"(skipped)")+(st.note?"\n      note: "+st.note:""));
    });
    if(rows.length){ human.push("["+sec.title+"]", ...rows, ""); }
  });
  const json={ form:FORM_ID, answers };
  const block="```INTAKE-JSON\n"+JSON.stringify(json,null,2)+"\n```";
  const full="MOD-132 deep-dive intake\n\n"+human.join("\n")+"\n--- paste the block below to Claude ---\n\n"+block;
  // #out lives OUTSIDE #form-root so re-renders can't destroy it
  let out=document.getElementById("out");
  if(!out){
    out=document.createElement("pre"); out.id="out";
    document.getElementById("form-root").insertAdjacentElement("afterend",out);
  }
  out.textContent=full; out.style.display="block";
  const cb=document.getElementById("copyBtn"); if(cb) cb.style.display="inline-block";
  window.__lastOut=block;
  out.scrollIntoView({behavior:"smooth",block:"center"});
  toast("Ready — hit Copy JSON");
}
function toast(m){ const t=document.getElementById("toast"); t.textContent=m; t.classList.add("show"); setTimeout(()=>t.classList.remove("show"),1900); }

render();