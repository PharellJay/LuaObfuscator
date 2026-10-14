/* Deadeye Obfuscator — Web Worker.
 * Runs the REAL Lua obfuscator in-browser via Fengari (Lua 5.3 in JS).
 * The output is ordinary native Lua — Fengari is only the machine that runs
 * the obfuscation step. See web/README.md.
 *
 * Message protocol (from app.js):
 *   { type:'init',  moduleBase }                  -> fetches & caches module sources
 *   { type:'run', id, name, source:ArrayBuffer, config }
 * Replies:
 *   { type:'ready' } | { type:'error', fatal:true, message }
 *   { type:'log', id, line }
 *   { type:'result', id, name, output:ArrayBuffer, seed, ms }
 *   { type:'error', id, name, message }
 */

// fengari-web's UMD wrapper is invoked with the literal `window`, which is
// undefined in a Worker; aliasing it to `self` lets the bundle attach
// `self.fengari`. We deliberately do NOT define `document`, so fengari-web's
// DOM auto-loader (guarded by `typeof document !== "undefined"`) stays off.
if (typeof window === "undefined") { self.window = self; }

// Fengari (Lua 5.3 in JS) — pinned. Provides integer subtype + bitwise ops
// (~ & | << >> //) that the obfuscator and its VM require.
importScripts("https://cdn.jsdelivr.net/npm/fengari-web@0.1.4/dist/fengari-web.js");
importScripts("modules.js"); // defines self.OBFUSCATOR_MODULES

const { lua, lauxlib, lualib, to_luastring, to_jsstring } = self.fengari;
const S = (s) => to_luastring(s);              // JS string -> Lua string (ASCII names)
const pushCFn = lua.lua_pushcfunction || lua.lua_pushjsfunction; // fengari version-proof

let MODULE_BASE = "modules/";
let MODULE_SOURCES = null; // [{ name, bytes:Uint8Array }]
let currentRunId = null;   // so the print shim can tag log lines

/* ---- module loading ------------------------------------------------------ */

async function fetchModules() {
  const list = self.OBFUSCATOR_MODULES;
  const out = [];
  for (const name of list) {
    const path = MODULE_BASE + name.replace(/\./g, "/") + ".lua";
    const resp = await fetch(path);
    if (!resp.ok) throw new Error(`failed to fetch module ${name} (${path}): ${resp.status}`);
    const buf = await resp.arrayBuffer();           // raw bytes: preserves UTF-8 banner exactly
    out.push({ name, bytes: new Uint8Array(buf) });
  }
  return out;
}

/* ---- low-level Lua helpers ----------------------------------------------- */

function luaError(L, prefix) {
  const msg = lua.lua_tojsstring(L, -1);
  lua.lua_pop(L, 1);
  return new Error(prefix + ": " + msg);
}

function runChunk(L, bytes, chunkname) {
  let st = lauxlib.luaL_loadbuffer(L, bytes, bytes.length, S(chunkname));
  if (st !== lua.LUA_OK) throw luaError(L, "load " + chunkname);
  st = lua.lua_pcall(L, 0, lua.LUA_MULTRET, 0);
  if (st !== lua.LUA_OK) throw luaError(L, "run " + chunkname);
}

function runSource(L, jsString, chunkname) {
  runChunk(L, to_luastring(jsString), chunkname);
}

/* print(...) -> postMessage, so the pipeline's "[*] Tokenizing..." etc. stream live */
function installPrint(L) {
  pushCFn(L, function (L) {
    const n = lua.lua_gettop(L);
    const parts = [];
    for (let i = 1; i <= n; i++) {
      const s = lauxlib.luaL_tolstring(L, i); // stringifies any value, pushes result
      parts.push(to_jsstring(s));
      lua.lua_pop(L, 1);
    }
    postMessage({ type: "log", id: currentRunId, line: parts.join("\t") });
    return 0;
  });
  lua.lua_setglobal(L, S("print"));
}

/* Shims that make the CLI-oriented code browser-safe. */
function installShims(L) {
  installPrint(L);
  // require is unnecessary (every file is loaded in order; all APIs are globals)
  // and would otherwise hit the filesystem searcher. Make it a harmless no-op.
  runSource(L, "require = function() return true end", "@shim-require");
  // The only io.open calls reached during Obfuscate() are two already-guarded
  // debug writes (Main.lua) — ReadFile is skipped and GenerateSecureSeed returns
  // early via Config.RandomSeed. Force io.open to a no-op so those writes cleanly
  // no-op regardless of Fengari's partial io implementation.
  runSource(L, "io = io or {}; io.open = function() return nil end", "@shim-io");
  // Skip Main.lua's CLI file-read driver; we call Obfuscate() directly.
  lua.lua_pushboolean(L, 1);
  lua.lua_setglobal(L, S("SUPPRESS_MAIN_DRIVER"));
}

/* ---- config injection ---------------------------------------------------- */

function luaStr(s) { return '"' + String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"'; }
function luaBool(b) { return b ? "true" : "false"; }
function luaInt(v, d) { const n = parseInt(v, 10); return Number.isFinite(n) ? n : d; }
function luaNum(v, d) { const n = Number(v); return Number.isFinite(n) ? n : d; }

const PASS_KEYS = ["CommentRemoval","DeadCode","Rename","Flatten","NumberObf",
  "StringObf","StringSplit","ConstantPool","Minify","AntiTamper"];

function configToLua(cfg, seed) {
  const passes = cfg.passes || {};
  const passLines = PASS_KEYS.map(k => `  ${k}=${luaBool(passes[k] !== false)}`).join(",\n");
  return [
    `Config.Preset=${luaStr(cfg.preset || "custom")}`,
    `Config.Passes={\n${passLines}\n}`,
    `Config.VirtualizePrefix=${luaStr(cfg.virtualizePrefix == null ? "vm_" : cfg.virtualizePrefix)}`,
    `Config.VirtualizeAll=${luaBool(!!cfg.virtualizeAll)}`,
    `Config.VMLightweight=${luaBool(!!cfg.vmLightweight)}`,
    `VariableLength=${luaInt(cfg.variableLength, 12)}`,
    `DeadCodeInjectProbability=${luaNum(cfg.deadCodeProbability, 0.45)}`,
    `JunkPoolRatioMin=${luaInt(cfg.junkPoolMin, 50)}`,
    `JunkPoolRatioMax=${luaInt(cfg.junkPoolMax, 100)}`,
    `Config.RandomSeed=${seed}`, // always a number -> GenerateSecureSeed returns early (no disk/entropy I/O)
  ].join("\n");
}

// A fresh crypto-random 31-bit seed per build (the desirable per-build variation
// for an obfuscator). Always set as Config.RandomSeed so GenerateSecureSeed never
// touches /dev/urandom/os.tmpname in the browser.
function resolveSeed() {
  const a = new Uint32Array(1);
  crypto.getRandomValues(a);
  return (a[0] % 2147483647) + 1;
}

/* ---- one obfuscation run (fresh Lua state each time) --------------------- */

function obfuscate(sourceBytes, cfg) {
  const L = lauxlib.luaL_newstate();
  try {
    lualib.luaL_openlibs(L);
    installShims(L);
    for (const m of MODULE_SOURCES) runChunk(L, m.bytes, "@" + m.name + ".lua");
    const seed = resolveSeed();
    runSource(L, configToLua(cfg, seed), "@config");

    lua.lua_getglobal(L, S("Obfuscate"));
    if (!lua.lua_isfunction(L, -1)) throw new Error("global Obfuscate not defined after load");
    lua.lua_pushlstring(L, sourceBytes, sourceBytes.length);
    const st = lua.lua_pcall(L, 1, 1, 0);
    if (st !== lua.LUA_OK) throw luaError(L, "Obfuscate");
    if (!lua.lua_isstring(L, -1)) throw new Error("Obfuscate did not return a string");
    const bytes = lauxlib.luaL_tolstring(L, -1); // bytes of the result
    const copy = new Uint8Array(bytes.length);
    copy.set(bytes);
    return { bytes: copy, seed };
  } finally {
    lua.lua_close(L);
  }
}

/* ---- message handling ---------------------------------------------------- */

self.onmessage = async (ev) => {
  const msg = ev.data || {};
  if (msg.type === "init") {
    try {
      if (msg.moduleBase) MODULE_BASE = msg.moduleBase;
      MODULE_SOURCES = await fetchModules();
      postMessage({ type: "ready", count: MODULE_SOURCES.length });
    } catch (e) {
      postMessage({ type: "error", fatal: true, message: String(e && e.message || e) });
    }
    return;
  }
  if (msg.type === "run") {
    currentRunId = msg.id;
    const t0 = (self.performance || Date).now();
    try {
      if (!MODULE_SOURCES) throw new Error("worker not initialized");
      const srcBytes = new Uint8Array(msg.source);
      const { bytes, seed } = obfuscate(srcBytes, msg.config || {});
      const ms = Math.round((self.performance || Date).now() - t0);
      postMessage(
        { type: "result", id: msg.id, name: msg.name, output: bytes.buffer, seed, ms },
        [bytes.buffer]
      );
    } catch (e) {
      postMessage({ type: "error", id: msg.id, name: msg.name, message: String(e && e.message || e) });
    } finally {
      currentRunId = null;
    }
    return;
  }
};
