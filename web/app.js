"use strict";
/* Deadeye Obfuscator — UI controller. Talks to web/worker.js (Fengari). */

/* ---------- presets & config ---------- */
const PASS_META = [
  ["CommentRemoval", "Remove comments"],
  ["DeadCode",       "Dead-code injection"],
  ["Rename",         "Rename variables"],
  ["Flatten",        "Control-flow flattening"],
  ["NumberObf",      "Number obfuscation"],
  ["StringObf",      "String obfuscation"],
  ["StringSplit",    "String splitting"],
  ["ConstantPool",   "Constant pool"],
  ["Minify",         "Minify"],
  ["AntiTamper",     "Anti-tamper"],
];
const BUILTIN_PRESETS = {
  max:  { CommentRemoval:true, DeadCode:true,  Rename:true, Flatten:true,  NumberObf:true, StringObf:true, StringSplit:true,  ConstantPool:true, Minify:true, AntiTamper:true },
  fast: { CommentRemoval:true, DeadCode:false, Rename:true, Flatten:false, NumberObf:true, StringObf:true, StringSplit:false, ConstantPool:true, Minify:true, AntiTamper:true },
};
function defaultConfig() {
  return {
    preset: "max",
    passes: { ...BUILTIN_PRESETS.max },
    virtualizePrefix: "vm_",
    virtualizeAll: false,
    vmLightweight: false,
    variableLength: 12,
    deadCodeProbability: 0.45,
    junkPoolMin: 50,
    junkPoolMax: 100,
  };
}
const state = { config: defaultConfig(), files: [] /* {id,name,buffer} */ };
let fileSeq = 0;

/* ---------- tiny DOM helpers ---------- */
const $ = (id) => document.getElementById(id);
const el = (tag, cls, txt) => { const e = document.createElement(tag); if (cls) e.className = cls; if (txt != null) e.textContent = txt; return e; };
const fmtBytes = (n) => n < 1024 ? n + " B" : n < 1048576 ? (n/1024).toFixed(1) + " KB" : (n/1048576).toFixed(2) + " MB";

/* ---------- build pass toggles ---------- */
function buildPassToggles() {
  const wrap = $("passes");
  for (const [key, label] of PASS_META) {
    const l = el("label", "switch");
    const cb = el("input"); cb.type = "checkbox"; cb.id = "pass_" + key; cb.checked = state.config.passes[key] !== false;
    cb.addEventListener("change", () => {
      state.config.passes[key] = cb.checked;
      state.config.preset = "custom"; $("preset").value = "custom";
    });
    l.appendChild(cb); l.appendChild(el("span", null, label));
    wrap.appendChild(l);
  }
}
function syncPassToggles() {
  for (const [key] of PASS_META) $("pass_" + key).checked = state.config.passes[key] !== false;
}

/* ---------- preset dropdown ---------- */
function applyBuiltinPreset(name) {
  state.config.preset = name;
  state.config.passes = { ...BUILTIN_PRESETS[name] };
  if (name === "fast") { state.config.virtualizeAll = false; $("virtualizeAll").checked = false; }
  syncPassToggles();
}
$("preset").addEventListener("change", (e) => {
  const v = e.target.value;
  if (v === "max" || v === "fast") applyBuiltinPreset(v); else state.config.preset = "custom";
});

/* ---------- virtualization + tuning bindings ---------- */
$("virtualizePrefix").addEventListener("input", (e) => { state.config.virtualizePrefix = e.target.value; });
$("virtualizeAll").addEventListener("change", (e) => { state.config.virtualizeAll = e.target.checked; });
$("vmLightweight").addEventListener("change", (e) => { state.config.vmLightweight = e.target.checked; });

function bindSlider(id, key, fmt) {
  const input = $(id), out = $(id + "Out");
  const update = () => {
    let v = (id === "deadCodeProbability") ? parseFloat(input.value) : parseInt(input.value, 10);
    state.config[key] = v; out.textContent = fmt ? fmt(v) : v;
  };
  input.addEventListener("input", update); update();
}
bindSlider("variableLength", "variableLength");
bindSlider("deadCodeProbability", "deadCodeProbability", (v) => v.toFixed(2));
bindSlider("junkPoolMin", "junkPoolMin");
bindSlider("junkPoolMax", "junkPoolMax");
// keep min <= max
$("junkPoolMin").addEventListener("input", () => {
  if (state.config.junkPoolMin > state.config.junkPoolMax) {
    state.config.junkPoolMax = state.config.junkPoolMin;
    $("junkPoolMax").value = state.config.junkPoolMin; $("junkPoolMaxOut").textContent = state.config.junkPoolMin;
  }
});
$("junkPoolMax").addEventListener("input", () => {
  if (state.config.junkPoolMax < state.config.junkPoolMin) {
    state.config.junkPoolMin = state.config.junkPoolMax;
    $("junkPoolMin").value = state.config.junkPoolMax; $("junkPoolMinOut").textContent = state.config.junkPoolMax;
  }
});

/* ---------- named presets (localStorage + import/export) ---------- */
const LS_KEY = "deadeye.presets";
function loadSaved() { try { return JSON.parse(localStorage.getItem(LS_KEY) || "{}"); } catch { return {}; } }
function storeSaved(obj) { try { localStorage.setItem(LS_KEY, JSON.stringify(obj)); } catch {} }
function refreshSavedDropdown() {
  const sel = $("savedPresets"); const saved = loadSaved();
  sel.innerHTML = '<option value="">— saved presets —</option>';
  for (const name of Object.keys(saved).sort()) sel.appendChild(new Option(name, name));
}
function snapshot() { return JSON.parse(JSON.stringify(state.config)); }
function applyConfig(cfg) {
  state.config = Object.assign(defaultConfig(), cfg);
  state.config.passes = Object.assign({ ...BUILTIN_PRESETS.max }, cfg.passes || {});
  // reflect into DOM
  $("preset").value = ["max","fast"].includes(state.config.preset) ? state.config.preset : "custom";
  $("virtualizePrefix").value = state.config.virtualizePrefix;
  $("virtualizeAll").checked = !!state.config.virtualizeAll;
  $("vmLightweight").checked = !!state.config.vmLightweight;
  $("variableLength").value = state.config.variableLength; $("variableLengthOut").textContent = state.config.variableLength;
  $("deadCodeProbability").value = state.config.deadCodeProbability; $("deadCodeProbabilityOut").textContent = Number(state.config.deadCodeProbability).toFixed(2);
  $("junkPoolMin").value = state.config.junkPoolMin; $("junkPoolMinOut").textContent = state.config.junkPoolMin;
  $("junkPoolMax").value = state.config.junkPoolMax; $("junkPoolMaxOut").textContent = state.config.junkPoolMax;
  syncPassToggles();
  updateCostMeter();
}

/* ---------- estimated output cost ---------- */
// Weights reflect the real runtime/size impact of each option (from the project's
// perf work): whole-program virtualization dominates, control-flow flattening and
// dead-code are next, VMLightweight sharply mitigates virtualization, number-obf
// is nearly free, minify/rename cost nothing at runtime, anti-tamper is one-time.
function estimateCost(cfg) {
  const p = cfg.passes || {};
  const on = (k) => p[k] !== false;
  const num = (v) => { const n = Number(v); return Number.isFinite(n) ? n : 0; };
  const prefixActive = String(cfg.virtualizePrefix || "").trim().length > 0;
  let s = 0;
  if (cfg.virtualizeAll)      s += cfg.vmLightweight ? 20 : 48; // the big lever
  else if (prefixActive)      s += cfg.vmLightweight ? 3 : 6;   // selective, only matching fns
  if (on("Flatten"))          s += 18;
  if (on("DeadCode"))         s += 4 + num(cfg.deadCodeProbability) * 16; // scales with the slider
  if (on("StringSplit"))      s += 8;
  if (on("StringObf"))        s += 3;
  if (on("ConstantPool"))     s += 2 + num(cfg.junkPoolMax) / 100 * 3;    // junk ratio => bigger pool
  if (on("NumberObf"))        s += 2;
  if (on("AntiTamper"))       s += 3; // load-time only, not hot path
  if (num(cfg.variableLength) > 20) s += 1;
  return Math.max(0, Math.min(100, Math.round(s)));
}
const COST_BANDS = [
  { max: 8,   label: "Very light", color: "#3fb950" },
  { max: 22,  label: "Light",      color: "#86c34a" },
  { max: 45,  label: "Moderate",   color: "#c9c421" },
  { max: 70,  label: "Heavy",      color: "#e3861f" },
  { max: 90,  label: "Very heavy", color: "#f0652f" },
  { max: 101, label: "Extreme",    color: "#f85149" },
];
function updateCostMeter() {
  const score = estimateCost(state.config);
  const band = COST_BANDS.find((b) => score <= b.max) || COST_BANDS[COST_BANDS.length - 1];
  $("costMarker").style.left = score + "%";
  const lbl = $("costLabel");
  lbl.textContent = band.label;
  lbl.style.color = band.color;
  $("costTrack").setAttribute("aria-valuenow", String(score));
  $("costTrack").setAttribute("aria-valuetext", band.label);
}
$("presetSave").addEventListener("click", () => {
  const name = $("presetName").value.trim(); if (!name) return;
  const saved = loadSaved(); saved[name] = snapshot(); storeSaved(saved);
  refreshSavedDropdown(); $("savedPresets").value = name; $("presetName").value = "";
});
$("presetLoad").addEventListener("click", () => {
  const name = $("savedPresets").value; if (!name) return;
  const saved = loadSaved(); if (saved[name]) applyConfig(saved[name]);
});
$("presetDelete").addEventListener("click", () => {
  const name = $("savedPresets").value; if (!name) return;
  const saved = loadSaved(); delete saved[name]; storeSaved(saved); refreshSavedDropdown();
});
$("presetExport").addEventListener("click", () => {
  const blob = new Blob([JSON.stringify(snapshot(), null, 2)], { type: "application/json" });
  triggerDownload("deadeye-preset.json", blob);
});
$("presetImport").addEventListener("click", () => $("presetImportFile").click());
$("presetImportFile").addEventListener("change", async (e) => {
  const f = e.target.files[0]; if (!f) return;
  try { applyConfig(JSON.parse(await f.text())); } catch { alert("Invalid preset JSON"); }
  e.target.value = "";
});

/* ---------- file intake ---------- */
function addFile(name, buffer) { state.files.push({ id: ++fileSeq, name, buffer }); renderFileList(); updateRunEnabled(); }
async function addFromFileList(fileList) {
  for (const f of fileList) addFile(f.name || "input.lua", await f.arrayBuffer());
}
function renderFileList() {
  const ul = $("filelist"); ul.innerHTML = "";
  for (const f of state.files) {
    const li = el("li");
    li.appendChild(el("span", "fname", f.name));
    li.appendChild(el("span", "fsize", fmtBytes(f.buffer.byteLength)));
    const x = el("button", "x", "×"); x.title = "Remove"; x.setAttribute("aria-label", "Remove " + f.name);
    x.addEventListener("click", () => { state.files = state.files.filter(g => g.id !== f.id); renderFileList(); updateRunEnabled(); });
    li.appendChild(x); ul.appendChild(li);
  }
}
$("pickFiles").addEventListener("click", async () => {
  if (window.showOpenFilePicker) {
    try {
      const handles = await window.showOpenFilePicker({ multiple: true,
        types: [{ description: "Lua", accept: { "text/plain": [".lua"] } }] });
      for (const h of handles) { const f = await h.getFile(); addFile(f.name, await f.arrayBuffer()); }
      return;
    } catch (e) { if (e && e.name === "AbortError") return; } // fall through on other errors
  }
  $("fileInput").click();
});
$("fileInput").addEventListener("change", (e) => { addFromFileList(e.target.files); e.target.value = ""; });
$("pasteAdd").addEventListener("click", () => {
  const code = $("pasteArea").value; if (!code.trim()) return;
  addFile("pasted.lua", new TextEncoder().encode(code).buffer); $("pasteArea").value = "";
});
const dz = $("dropzone");
["dragenter","dragover"].forEach(ev => dz.addEventListener(ev, (e) => { e.preventDefault(); dz.classList.add("drag"); }));
["dragleave","drop"].forEach(ev => dz.addEventListener(ev, (e) => { e.preventDefault(); dz.classList.remove("drag"); }));
dz.addEventListener("drop", (e) => { if (e.dataTransfer && e.dataTransfer.files.length) addFromFileList(e.dataTransfer.files); });
dz.addEventListener("keydown", (e) => { if (e.key === "Enter" || e.key === " ") { e.preventDefault(); $("pickFiles").click(); } });
$("clearBtn").addEventListener("click", () => { state.files = []; renderFileList(); $("results").innerHTML = ""; $("log").textContent = ""; if (!running) showProgress(false); updateRunEnabled(); });

/* ---------- worker orchestration ---------- */
let worker = null, workerReady = false, running = false;
let runSeq = 0, queue = [], pending = null;
let totalFiles = 0, fileIndex = 0, curSteps = 1, curStep = 0;

function setStatus(stateName, text) { const s = $("status"); s.dataset.state = stateName; $("statusText").textContent = text; }
function log(line) { const p = $("log"); p.textContent += line + "\n"; p.scrollTop = p.scrollHeight; }
function updateRunEnabled() { $("runBtn").disabled = !(workerReady && state.files.length && !running); }

// Number of "[*] …" stage lines the worker will print for this config. Mirrors
// the pipeline in Main.lua: Tokenizing, Parsing, Virtualizing and Emitting are
// always printed; the rest print only when their pass is enabled (Rename prints
// twice — passes 1 and 2).
function expectedStages(cfg) {
  const p = cfg.passes || {};
  let n = 4; // Tokenizing, Parsing, Virtualizing, Emitting
  if (p.DeadCode    !== false) n += 1;
  if (p.Rename      !== false) n += 2;
  if (p.Flatten     !== false) n += 1;
  if (p.NumberObf   !== false) n += 1;
  if (p.StringObf   !== false) n += 1;
  if (p.StringSplit !== false) n += 1;
  if (p.ConstantPool!== false) n += 1;
  if (p.Minify      !== false) n += 1;
  return n;
}
function showProgress(on) { $("progress").hidden = !on; if (on) $("progress").classList.remove("done"); }
function setProgress(step, steps, stageText) {
  const pct = Math.max(0, Math.min(100, Math.round((step / steps) * 100)));
  $("progressFill").style.width = pct + "%";
  $("progressPct").textContent = pct + "%";
  $("progressBar").setAttribute("aria-valuenow", String(pct));
  const prefix = totalFiles > 1 ? `(${fileIndex}/${totalFiles}) ` : "";
  if (stageText != null) $("progressStage").textContent = prefix + stageText;
}

function initWorker() {
  worker = new Worker("worker.js");
  worker.onmessage = (ev) => {
    const m = ev.data;
    if (m.type === "ready") { workerReady = true; setStatus("ready", `Engine ready — ${m.count} modules loaded`); updateRunEnabled(); return; }
    if (m.type === "log") {
      log(m.line);
      if (m.line.indexOf("[*]") !== -1) {
        curStep = Math.min(curStep + 1, curSteps - 1); // leave the last slice for the no-print finalize/anti-tamper phase
        const stage = m.line.replace(/^.*\[\*\]\s*/, "").replace(/\.*$/, "");
        setProgress(curStep, curSteps, curStep >= curSteps - 1 ? "Finalizing…" : stage);
      }
      return;
    }
    if (m.type === "result") { onResult(m); return; }
    if (m.type === "error") {
      if (m.fatal) { setStatus("error", "Engine failed to load"); log("FATAL: " + m.message); return; }
      setProgress(curSteps, curSteps, "failed");
      renderResult({ name: m.name, error: m.message }); next();
    }
  };
  worker.onerror = (e) => { setStatus("error", "Worker error"); log("Worker error: " + (e.message || e)); };
  worker.postMessage({ type: "init", moduleBase: "modules/" });
}

$("runBtn").addEventListener("click", () => {
  if (!workerReady || running || !state.files.length) return;
  running = true; updateRunEnabled();
  setStatus("busy", "Obfuscating…"); $("spinner").hidden = false;
  $("results").innerHTML = ""; $("log").textContent = "";
  $("logBox").open = true;
  totalFiles = state.files.length; fileIndex = 0;
  showProgress(true);
  queue = state.files.map(f => f.id);
  next();
});
function next() {
  if (!queue.length) {
    running = false; pending = null; $("spinner").hidden = true; setStatus("ready", "Done");
    $("progress").classList.add("done"); setProgress(1, 1, "Done");
    setTimeout(() => { if (!running) showProgress(false); }, 900);
    updateRunEnabled();
    return;
  }
  const id = queue.shift();
  const f = state.files.find(g => g.id === id);
  if (!f) return next();
  pending = f;
  fileIndex += 1;
  curSteps = expectedStages(snapshot()) + 1; // +1 reserved for finalize/anti-tamper (no print line)
  curStep = 0;
  setProgress(0, curSteps, "Starting…");
  const copy = f.buffer.slice(0); // transfer a copy; keep original for re-runs
  log(`\n===== ${f.name} =====`);
  worker.postMessage({ type: "run", id: ++runSeq, name: f.name, source: copy, config: snapshot() }, [copy]);
}
function onResult(m) { setProgress(curSteps, curSteps, "Done"); renderResult(m); next(); }

/* ---------- results UI ---------- */
function outName(name) { return name.replace(/\.lua$/i, "") + ".obfuscated.lua"; }
function renderResult(m) {
  const card = el("div", "result" + (m.error ? " err" : ""));
  const head = el("div", "result-head");
  head.appendChild(el("span", "fname", outName(m.name)));
  if (m.error) {
    head.appendChild(el("span", "meta", "failed"));
    card.appendChild(head);
    card.appendChild(el("div", "errmsg", m.error));
    $("results").appendChild(card);
    return;
  }
  const bytes = new Uint8Array(m.output);
  head.appendChild(el("span", "meta ok", `${fmtBytes(bytes.length)} · ${m.ms} ms · seed ${m.seed}`));
  card.appendChild(head);

  const acts = el("div", "result-actions");
  const dl = el("button", "btn primary", "Download");
  dl.addEventListener("click", () => saveBytes(outName(m.name), bytes));
  const cp = el("button", "btn ghost", "Copy");
  cp.addEventListener("click", async () => {
    try { await navigator.clipboard.writeText(new TextDecoder().decode(bytes)); cp.textContent = "Copied ✓"; setTimeout(() => cp.textContent = "Copy", 1200); }
    catch { cp.textContent = "Copy failed"; }
  });
  acts.appendChild(dl); acts.appendChild(cp); card.appendChild(acts);

  // preview (truncated so a multi-MB file doesn't freeze the DOM)
  const text = new TextDecoder().decode(bytes);
  const CAP = 20000;
  const pre = el("pre", null, text.length > CAP ? text.slice(0, CAP) + "\n\n… preview truncated (" + fmtBytes(bytes.length) + ") — download for the full file" : text);
  card.appendChild(pre);
  $("results").appendChild(card);
}

/* ---------- downloads ---------- */
function triggerDownload(name, blob) {
  const url = URL.createObjectURL(blob);
  const a = el("a"); a.href = url; a.download = name; document.body.appendChild(a); a.click();
  a.remove(); setTimeout(() => URL.revokeObjectURL(url), 1000);
}
async function saveBytes(name, bytes) {
  const blob = new Blob([bytes], { type: "text/plain" });
  if (window.showSaveFilePicker) {
    try {
      const h = await window.showSaveFilePicker({ suggestedName: name,
        types: [{ description: "Lua", accept: { "text/plain": [".lua"] } }] });
      const w = await h.createWritable(); await w.write(blob); await w.close(); return;
    } catch (e) { if (e && e.name === "AbortError") return; } // fall through
  }
  triggerDownload(name, blob);
}

/* ---------- boot ---------- */
buildPassToggles();
refreshSavedDropdown();
// Any change to a Settings control re-estimates the output cost. Delegated so it
// also covers the pass checkboxes created at runtime; runs after each control's
// own handler has updated state.config (target-phase listeners fire before this
// bubbling one).
document.querySelector(".config").addEventListener("input", updateCostMeter);
document.querySelector(".config").addEventListener("change", updateCostMeter);
updateCostMeter();
initWorker();
