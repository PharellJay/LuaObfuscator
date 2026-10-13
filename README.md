# Deadeye Obfuscator

**A Lua obfuscator with a bytecode virtual machine — written entirely in Lua.**

Deadeye's headline protection is **VM-based virtualization**: it compiles your
functions into a custom, per-build-randomized bytecode and runs them under a
hand-written interpreter emitted into the output. The original logic of a
virtualized function no longer exists as code — it becomes opaque data executed
by the VM. Around that, a chain of classic source-to-source passes hardens
everything else, and the tool emits a single file that behaves identically to the
original while being far harder to read, diff, decompile, or statically analyze.

The whole toolchain — lexer, parser, expression IR, the VM compiler/interpreter
generator, and every transformation pass — is **implemented 100% in pure Lua**,
with no external dependencies. The obfuscated output is likewise plain Lua (5.3+).

> Intended for protecting your own Lua source (game scripts, anti-cheat logic,
> licensed tooling). Only obfuscate code you own or are authorized to modify.

## Highlights

- **Bytecode VM (virtualization) — the core feature.** Functions are compiled to
  a private instruction set and run under an interpreter emitted into the output;
  the original source of a virtualized function is gone, replaced by data.
  Virtualize selectively by name prefix, or **everything** with one toggle
  (`Config.VirtualizeAll`). Handles arithmetic/logic/bitwise, all control flow,
  varargs, multiple returns, methods, nested functions, **closures with shared
  upvalues**, and coroutines — with graceful native fallback for anything it
  can't safely compile.
- **Per-build hardening.** The VM's opcode numbering is permuted and its constants
  — **both strings and numbers** — are encrypted with a fresh key on every build,
  so two builds of the same input differ and generic devirtualizers can't rely on
  fixed opcodes or read literals out of the blob.
- **Real control-flow flattening.** Function bodies are lowered into dispatch
  state machines, including bodies that contain `return`s and `break`s.
- **Pure Lua, no dependencies.** Entire implementation and output are plain Lua.
- **Everything still runs.** A round-trip test harness proves the obfuscated
  output behaves identically to the source across a broad fixture suite (also in
  a stress mode that virtualizes every function).

## Requirements

- **Lua 5.3+** (uses 5.3 integer/bitwise operators). Lua 5.4 works as well.

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

The obfuscated file is written to `Output/<OutputPath>`. Intermediate stages
(`Output/after_emit.lua`, `Output/preminify.lua`) are also dumped to make
debugging a pass easier.

## Virtualization (the VM)

Any **top-level global function whose name begins with `Config.VirtualizePrefix`**
(default `"vm_"`) is compiled to the VM instead of being emitted as Lua. For
example:

```lua
function vm_check(key)        -- compiled to bytecode + interpreter
    return hash(key) == SECRET
end
```

becomes, in the output, roughly `vm_check = <interp>(<encrypted bytecode blob>)`
— the arithmetic, comparisons, and the constant `SECRET` no longer appear as
source (or in the compiled bytecode's constant table). Set
`Config.VirtualizePrefix = nil` (or `""`) to disable prefix-based selection.

**Selecting what to virtualize:**

- **By prefix (selective):** name the functions you want protected with the
  `Config.VirtualizePrefix` prefix (default `"vm_"`) — e.g. protect only your
  license check and leave hot paths native.
- **Everything (`Config.VirtualizeAll = true`):** virtualize *every* eligible
  top-level function, prefix ignored. Maximum coverage at higher runtime cost;
  ineligible functions safely stay native.

**Supported in virtualized functions:** arithmetic / logic / comparison / concat
/ length / unary ops, locals and globals, `if`/`elseif`/`else`, `while`,
numeric and generic `for`, `repeat`, `break`, `goto`/labels' callers, tables
(including trailing `...`), multiple return values, varargs (`...`, `select`),
method / cross / recursive calls, nested functions, and **closures with shared
mutable upvalues**. Coroutines (`yield`/`resume`) work through virtualized code.

**Graceful fallback:** anything the compiler can't yet handle makes that one
function stay native (compiled under `pcall`), so virtualization never produces
broken output — it just protects less.

## Transformation passes

Beyond the VM, each pass is a standalone module. They run in a fixed pipeline
(`Main.lua:Obfuscate`): AST passes first, then text passes on the emitted source.

| Pass | Module | What it does |
|------|--------|--------------|
| Comment removal | `CommentRemover.lua` | Strips line/block comments without touching string literals. |
| Virtualization | `vm/*.lua` | Compiles `vm_`-prefixed functions to the bytecode VM (see above). |
| Dead code injection | `DeadCodeInjector.lua` | Inserts junk locals and never-taken blocks guarded by runtime opaque predicates. |
| Variable renaming | `VariableRenamer.lua` | Scope-aware renaming of locals to random `_xxxx` names; runs twice. |
| Control-flow flattening | `ControlFlowFlattening.lua` | Lowers statement blocks into dispatch state machines (handles `return`/`break` via a sentinel protocol). |
| Integer obfuscation | `NumericalObfuscator.lua` | Replaces numeric literals with hex, XOR closures, multiply/add chains, `load`-based expressions, and mixed-boolean-arithmetic identities. |
| String obfuscation | `LexicalObfuscator.lua` | Encodes string literals as self-decoding XOR closures. |
| String splitting | `StringSplitter.lua` | Breaks literals into concatenated fragments on escape-safe boundaries. |
| Constant pooling | `ConstantPooling.lua` | Collects constants into a shuffled pool table padded with junk, rewriting references through it. |
| Minification | `Minify.lua` | Collapses whitespace and tightens operators into a single line. |
| Anti-tamper | `Utils.lua` | Environment check + integrity checksum, then loads the body via `load(string.char(...))`; editing the payload breaks it. |

An expression IR (`ExprAST.lua`) reconstructs a real tree from the parser's token
lists; it backs the VM compiler and a precedence-aware emitter.

The random seed is drawn from a crypto RNG where available (`GenerateSecureSeed`),
or pin it with `RandomSeed` for reproducible output.

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
| `Config.VirtualizePrefix` | `"vm_"` | Name prefix selecting top-level functions to virtualize; `nil`/`""` disables prefix-based selection. |
| `Config.VirtualizeAll` | `false` | When `true`, virtualize **every** eligible top-level function (prefix ignored); ineligible functions safely stay native. Maximum coverage, higher runtime cost. |
| `Config.Passes.*` | all `true` | Per-pass on/off switches (CommentRemoval, DeadCode, Rename, Flatten, NumberObf, StringObf, StringSplit, ConstantPool, Minify, AntiTamper). |

## Testing

`run_tests.lua` is a round-trip harness: for every fixture it runs the original
and the obfuscated output and compares stdout + exit status, so a regression in
any pass shows up immediately.

```sh
lua run_tests.lua
# or point it at a specific interpreter:
LUA_BIN=/path/to/lua lua run_tests.lua
# also validate the expression-IR emit path:
USE_EXPR_AST=1 lua run_tests.lua
# stress mode: virtualize every eligible function in every fixture:
VIRTUALIZE_ALL=1 lua run_tests.lua
```

Fixtures live in `test/fixtures/` and cover closures, varargs, metatables,
coroutines, `goto`, bitwise ops, control-flow edge cases, and the VM feature set.

## Project layout

```
Main.lua              -- entry point; drives Obfuscate()
Config.lua            -- all tunable settings
Libraries.lua         -- requires every module in order
Reader.lua            -- file input
Lexer.lua / Parser.lua / Emitter.lua   -- tokenize -> AST -> source
ExprAST.lua           -- expression IR (tree from token lists + precedence-aware emit)
vm/                   -- bytecode VM: Opcodes, Compiler, Interp, Serializer, Virtualize
*Obfuscator / *Splitter / *Pooling ... -- the transformation passes
Utils.lua             -- shared helpers (seed, random names, anti-tamper)
run_tests.lua         -- round-trip correctness harness
test/fixtures/        -- harness inputs
Input/                -- source files to obfuscate
Output/               -- results + intermediate dumps (after_emit, preminify)
```

## License

MIT — see [LICENSE](LICENSE). Copyright (c) 2026 Pharell Jay Jeyakumar.
