# Deadeye Obfuscator

A multi-pass source-to-source obfuscator for Lua. It parses a Lua script into an AST, rewrites it through a chain of independent transformation passes, and emits a single minified file that behaves identically to the original while being far harder to read, diff, or statically analyze.

> Intended for protecting your own Lua source (game scripts, anti-cheat logic, licensed tooling). Only obfuscate code you own or are authorized to modify.

## Features

Each pass is a standalone module and runs in a fixed pipeline:

| Pass | Module | What it does |
|------|--------|--------------|
| Comment removal | `CommentRemover.lua` | Strips line and block comments without touching string literals. |
| Dead code injection | `DeadCodeInjector.lua` | Inserts junk locals and never-taken `if` blocks between statements (probability configurable). |
| Variable renaming | `VariableRenamer.lua` | Scope-aware renaming of locals to random `_xxxx` identifiers; runs twice so names introduced by later passes are also renamed. |
| Control-flow flattening | `ControlFlowFlattening.lua` | Hoists declarations and reorders/flattens statement blocks, staying under Lua's ~200-register limit. |
| Integer obfuscation | `NumericalObfuscator.lua` | Replaces numeric literals with hex, XOR-decode closures, multiply/add chains, or `loadstring`-based expressions. |
| String obfuscation | `LexicalObfuscator.lua` | Encodes string literals as self-decoding XOR closures (pure Lua 5.1, no `bit32` dependency). |
| String splitting | `StringSplitter.lua` | Breaks literals into concatenated fragments on escape-safe boundaries. |
| Constant pooling | `ConstantPooling.lua` | Collects constants into a shuffled pool table padded with configurable junk entries, and rewrites references through it. |
| Minification | `Minify.lua` | Collapses whitespace and tightens operators into a single line. |
| Anti-tamper | `Utils.lua` | Wraps the payload in an environment check and loads the body via `load(string.char(...))`. |

The random seed is drawn from a crypto RNG where available (`GenerateSecureSeed`), or you can pin it for reproducible output.

## Requirements

- **Lua 5.3+** (uses integer operators such as `|`). Lua 5.4 works as well.

## Project layout

```
Main.lua              -- entry point; drives the pipeline
Config.lua            -- all tunable settings
Libraries.lua         -- requires every module in order
Reader.lua            -- file input
Lexer.lua / Parser.lua / Emitter.lua   -- tokenize -> AST -> source
*Obfuscator / *Splitter / *Pooling ... -- the transformation passes
Utils.lua             -- shared helpers (seed, random names, anti-tamper)
Input/                -- source files to obfuscate
Output/               -- results + intermediate dumps (after_emit, preminify)
```

## Usage

1. Put the script you want to obfuscate in `Input/` (e.g. `Input/testinput.lua`).
2. Point `Config.lua` at it and name the output:

   ```lua
   InputPath  = "testinput.lua"   -- relative to Input/
   OutputPath = "testresult.lua"  -- written to Output/
   ```

3. Run from the project root:

   ```sh
   lua Main.lua
   ```

The obfuscated file is written to `Output/<OutputPath>`. Intermediate stages (`Output/after_emit.lua`, `Output/preminify.lua`) are also dumped to make debugging a pass easier.

## Configuration

All knobs live in `Config.lua`:

| Setting | Default | Meaning |
|---------|---------|---------|
| `InputPath` | `"testinput.lua"` | Source file inside `Input/`. |
| `OutputPath` | `"testresult.lua"` | Result file inside `Output/`. |
| `VariableLength` | `12` | Length of generated variable names. |
| `DeadCodeInjectProbability` | `0.45` | Chance (0.0–1.0) of injecting a dead block before each statement. |
| `JunkPoolRatioMin` / `JunkPoolRatioMax` | `50` / `100` | Percentage range of junk entries added to the constant pool. |
| `RandomSeed` | `nil` | Set a number to force a fixed seed for reproducible output. |

## How it fits together

`Main.lua` calls `Obfuscate(code)`, which runs the passes above in order and returns the final string. The early passes operate on the AST (`Tokenize` → `Parse` → transform → `Emit`); the later passes operate on the emitted source text. This split keeps structural rewrites (renaming, flattening, dead code) separate from lexical rewrites (number/string encoding, pooling, minify).

## License

MIT — see [LICENSE](LICENSE). Copyright (c) 2026 Pharell Jay Jeyakumar.
