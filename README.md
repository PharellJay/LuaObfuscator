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
- **Per-build hardening.** The VM's opcode numbering is permuted, its constants
  — **both strings and numbers** — are encrypted with a fresh key, and the
  interpreter's dispatch handlers are **emitted in a randomized order** on every
  build, so two builds of the same input differ and generic devirtualizers can't
  rely on fixed opcodes, a fixed handler layout, or read literals out of the blob.
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
| Anti-tamper | `Utils.lua` | Environment check, then an integrity-bound loader: the payload is encrypted and its decryption key is derived from a checksum of the ciphertext, so editing any byte (or stripping the check) yields the wrong key and the payload fails to load. The key material is stored split, not as a plaintext constant. One-time cost at startup; no runtime overhead. |

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
| `Config.VMLightweight` | `false` | When `true`, exempt the spliced VM interpreter from dead-code injection and control-flow flattening (renaming and the text passes still apply to it). Large speedup and much smaller output for virtualized code, with **no change to how your own code is obfuscated**; only the interpreter becomes slightly easier to pattern-match (opcodes still permuted, constants still encrypted per build). |
| `Config.Preset` | `"max"` | Strength preset that seeds `Config.Passes`: `"max"` (every pass on, strongest, slowest) or `"fast"` (performance mode — see below). |
| `Config.Passes.*` | from preset | Per-pass on/off switches (CommentRemoval, DeadCode, Rename, Flatten, NumberObf, StringObf, StringSplit, ConstantPool, Minify, AntiTamper). Seeded from `Config.Preset`; override any individual pass after the preset line. |

## Performance modes

Virtualized code runs under an interpreter, so it is inherently slower than
native Lua — the VM is the right tool for the handful of functions that are
worth protecting, not for hot loops. Two presets trade strength against speed:

- **`Config.Preset = "max"` (default):** every pass on. Strongest output;
  highest runtime cost. Use `VirtualizeAll` here only when you want maximum
  coverage and can accept the interpreter overhead everywhere.
- **`Config.Preset = "fast"`:** performance mode. Keeps cheap, effective layers
  (renaming, number/string obfuscation, constant pool, minify, anti-tamper) but
  drops the heaviest runtime passes (**control-flow flattening**, **dead-code
  injection**, **string splitting**) and virtualizes only the functions you
  mark with `VirtualizePrefix`. Markedly faster output that is weaker overall
  but still VM-protects your sensitive functions.

- **`Config.VMLightweight = true` (with any preset):** keep every pass on for
  **your** code, but stop injecting dead code into and flattening the VM
  *interpreter* itself. The interpreter is the same generated code every build
  and is the dominant runtime cost of virtualization, so skipping those two
  passes on it is a large speedup and a much smaller output file while your own
  logic stays exactly as obfuscated. The only tradeoff is that the interpreter
  becomes a little easier to fingerprint — but its opcode numbering is still
  permuted and its constants still encrypted on every build. A good middle
  ground between `"max"` and `"fast"` when you virtualize heavily.

**Best practice for speed without losing protection:** keep the default `"max"`
preset but virtualize *selectively* — give only your license checks, key
routines, and anti-cheat logic the `vm_` prefix, and leave hot paths native.
That concentrates the expensive VM where it matters. Pair it with
`Config.VMLightweight = true` to drop the interpreter's own overhead without
touching how your code is obfuscated. (The interpreter is also tuned so the
per-build number-obfuscation pass no longer rewrites its hot-path constants — a
large speedup over naive virtualization with no loss of strength.)

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
# validate a strength preset across the suite:
PRESET=fast lua run_tests.lua
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
