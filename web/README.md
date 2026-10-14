# Deadeye Obfuscator — Web UI

A static, zero-backend front-end for the Deadeye Lua obfuscator. It runs the
**real** obfuscator (the repo's `.lua` sources) in your browser via
[Fengari](https://fengari.io/) (Lua 5.3 compiled to JS), inside a Web Worker.

Nothing is uploaded anywhere — obfuscation happens entirely client-side. The
output is **ordinary native Lua 5.3+**, byte-compatible with what
`lua Main.lua` produces; Fengari is only the engine that runs the obfuscation
step, never part of the output.

## Run locally

```bash
python3 web/serve.py          # http://localhost:8000
python3 web/serve.py 8080     # custom port
```

`serve.py` serves `web/` and maps `/modules/<Name>.lua` to the repo-root `.lua`
sources, so the local URL layout matches production exactly. Open the page,
drop a `.lua` file (or use `Input/testinput.lua`), pick a preset, and click
**Obfuscate**.

> Must be served over HTTP — opening `index.html` via `file://` won't work
> (the worker `fetch()`es the modules and `importScripts` Fengari from a CDN).

## Deploy (GitHub Pages)

`.github/workflows/pages.yml` builds a self-contained site on every push that
touches `web/`, the root `.lua` files, or `vm/`: it copies the web app to the
site root and the `.lua` sources into `modules/`. Enable it once in
**Settings → Pages → Source: GitHub Actions**. The `.lua` files stay the single
source of truth (copied at deploy, never duplicated in git).

To embed in a portfolio site, iframe the Pages URL or reuse these static files.

## How it maps to the CLI

| CLI (`Config.lua`)            | UI control                                   |
|-------------------------------|----------------------------------------------|
| `Config.Preset`               | Preset dropdown (`max` / `fast` / `custom`)  |
| `Config.Passes.*`             | Pass toggles                                 |
| `Config.VirtualizePrefix`     | Virtualization → Prefix                      |
| `Config.VirtualizeAll`        | "Virtualize ALL eligible functions"          |
| `Config.VMLightweight`        | "VM lightweight"                             |
| `VariableLength`              | Variable name length slider                  |
| `DeadCodeInjectProbability`   | Dead-code inject probability slider          |
| `JunkPoolRatioMin/Max`        | Junk pool ratio sliders                       |
| `RandomSeed`                  | (not exposed) — a fresh random seed each build; shown on the result card |

The worker loads every module in `Libraries.lua` order (a no-op `require`, since
all APIs are globals), sets `SUPPRESS_MAIN_DRIVER` to skip the CLI file driver,
applies your settings, and calls the global `Obfuscate(code)` — a fresh Lua
state per run, so there's no cross-run state bleed.

## Notes / limitations

- **Each build uses a fresh random seed** (there's no seed field) — per-build
  variation is exactly what you want from an obfuscator, and the seed used is
  shown on the result card. Output is **not byte-reproducible** anyway, even in
  the native CLI with a fixed `RandomSeed`: Lua randomizes its string-hash seed
  per process, so `pairs()` order (used by nearly every pass) varies, cascading
  through `math.random` consumption. Every build is **behavior-correct**; only
  the exact bytes differ run to run.
- Fengari interprets Lua in JS, so very heavy builds (e.g. `VirtualizeAll` on a
  large file) take longer than native `lua`. The Worker keeps the UI responsive;
  watch the live build log.
- Native file open/save dialogs use the File System Access API where available
  (Chromium); other browsers fall back to a file input and a download.
