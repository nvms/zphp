# zphp

a zig-based PHP runtime. what bun is to node, zphp is to PHP.

you are the sole maintainer of this project.

## concept

zphp replaces the entire PHP toolchain with a single fast binary. the PHP ecosystem today is fragmented: `php` (runtime), `composer` (package manager), `phpunit` (testing), `php-cs-fixer` (formatting) - all separate tools, all slow. zphp collapses them into one.

core pillars:
- **runtime** - zig-based PHP interpreter targeting PHP 8.x semantics
- **package manager** - composer-compatible (reads composer.json, pulls from packagist)
- **build** - `zphp build` compiles a project into a standalone binary (bytecode + runtime bundled)
- **test** - built-in test runner
- **fmt** - built-in formatter

the strategy mirrors bun's: target the 95% of PHP semantics that real-world code actually uses. don't aim for 100% Zend compatibility on day one. match Zend behavior for the common cases, document divergences clearly, and iterate.

PHP doesn't have a formal language specification - the Zend Engine's behavior IS the spec. edge cases are defined by reading Zend's C source, not a document. for zphp, this means: match the observable behavior for the 95% case, explicitly document where zphp diverges, and prioritize the semantics that real packages on packagist actually depend on.

## cross-cutting learnings

before making technology or architecture decisions, read `~/code/vigil/learnings.md` for cross-cutting insights from past experiments. if you discover something that would change how a future project approaches a technology or architecture decision, add it to that file - but never commit or push to the vigil repo.

## what this project does

- executes PHP 8.x code: classes, interfaces, traits, enums, fibers, union types, named arguments, match expressions, attributes
- lexer + parser + bytecode compiler + VM interpreter
- built-in package manager: reads composer.json, resolves dependencies from packagist, installs to vendor/
- `zphp build` bundles a PHP project into a single standalone executable
- `zphp test` runs tests (compatible with PHPUnit test structure)
- `zphp fmt` formats PHP code
- `zphp run script.php` executes a PHP file
- `zphp init` scaffolds a new project with composer.json
- `zphp install` installs dependencies
- `zphp repl` interactive PHP shell
- fast cold starts, small binary, low memory footprint

## what this project does NOT do

- C extension compatibility (no PDO, no mbstring via C - pure zig reimplementations where needed)
- 100% Zend edge-case compatibility (the 95% that matters)
- JIT compilation (interpreter first, JIT is a future consideration)
- FFI support (not initially)
- web server (not a replacement for nginx/apache - though `zphp serve` for dev is fine)

## architecture

### layering model

strict downward-only dependency between layers. no layer reaches up. each layer communicates with adjacent layers through narrow, well-defined interfaces.

```
layer 0: primitives     tokens, AST nodes, bytecode opcodes, value types
layer 1: pipeline        lexer -> parser -> compiler -> VM (each consumes prior layer's output)
layer 2: runtime         GC, string interning, array impl, object model (supports the VM)
layer 3: stdlib          built-in functions (pure consumers of the runtime layer)
layer 4: tools           package manager, formatter, test runner, bundler (consumers of layer 0-3)
layer 5: CLI             dispatch to tools + runtime (thin shell)
```

critical boundaries:
- **lexer <-> parser**: token stream only. lexer has zero AST knowledge
- **parser <-> compiler**: AST only. parser has zero bytecode knowledge
- **compiler <-> VM**: bytecode chunks only. compiler has zero execution knowledge
- **VM <-> stdlib**: stdlib functions receive/return Value types through a registered function interface. no reaching into VM internals
- **tools <-> runtime**: tools are independent consumers. the package manager doesn't know about the formatter. the test runner doesn't know about the bundler

this means each component can be tested, replaced, or rewritten independently. want to swap in a JIT later? replace the VM layer, everything above and below stays the same.

### file layout

```
src/
  main.zig              - CLI dispatch (layer 5)

  pipeline/             - layer 1: compilation pipeline
    token.zig           - token types and token struct (layer 0 primitive)
    lexer.zig           - source -> token stream
    ast.zig             - AST node definitions (layer 0 primitive)
    parser.zig          - token stream -> AST
    compiler.zig        - AST -> bytecode chunks
    bytecode.zig        - opcode definitions and chunk format (layer 0 primitive)

  runtime/              - layer 2: execution engine and supporting types
    vm.zig              - bytecode interpreter
    value.zig           - PHP value representation (layer 0 primitive)
    gc.zig              - reference counting + cycle collector
    string.zig          - binary-safe string operations (copy-on-write)
    array.zig           - ordered hashmap (integer + string keys)
    object.zig          - class instances, property tables, method dispatch
    scope.zig           - variable scoping and symbol tables

  stdlib/               - layer 3: built-in function implementations
    registry.zig        - function registration interface
    strings.zig         - strlen, substr, strpos, str_replace, etc.
    arrays.zig          - array_map, array_filter, array_merge, sort, etc.
    math.zig            - abs, ceil, floor, round, rand, etc.
    io.zig              - echo, print, file_get_contents, file_put_contents, etc.
    json.zig            - json_encode, json_decode
    type.zig            - gettype, is_string, is_array, intval, strval, etc.
    pcre.zig            - preg_match, preg_replace

  tools/                - layer 4: standalone tools
    package/            - composer-compatible package manager
      resolver.zig      - dependency resolution (SAT solver)
      packagist.zig     - packagist API client
      composer.zig      - composer.json/composer.lock parsing
      installer.zig     - download and install to vendor/
    build/              - binary bundler
      bundler.zig       - bytecode + runtime -> standalone executable
    fmt/                - code formatter
      formatter.zig     - PHP code formatter (operates on token stream, not AST)
    test/               - test runner
      runner.zig        - discovers and executes test files

build.zig
build.zig.zon
```

### design principles

**module boundaries are load-bearing.** every directory boundary represents a real abstraction boundary. files within a directory may freely import each other. files across directories import only through the directory's public interface. this is enforced by convention and code review, not tooling.

**data flows down, never up.** the lexer produces tokens. the parser consumes tokens and produces AST. the compiler consumes AST and produces bytecode. the VM consumes bytecode and produces side effects. no step reaches back to a previous step. this makes the pipeline trivially testable - each stage has a clear input type and output type.

**runtime types are value types, not objects.** PHP Value, String, Array, Object - these are zig structs with well-defined memory layouts. no inheritance, no vtables, no dynamic dispatch for core type operations. polymorphism happens at the Value level (tagged union dispatch), not inside each type.

**stdlib functions are registered, not hardcoded.** the VM has a function registry. stdlib modules register themselves during initialization. this keeps the VM clean and makes it trivial to add, remove, or replace built-in functions. a stdlib function receives a slice of Value args and returns a Value - it never touches VM internals.

**tools are standalone binaries that share code.** the package manager, formatter, test runner, and bundler each use layers 0-3 as libraries. they could theoretically be separate executables. keeping them in one binary is a UX choice, not an architectural coupling.

### key type decisions

**value representation:** tagged union with small-string optimization. PHP values are dynamically typed - every variable can hold any type. the zig implementation uses a compact tagged union that fits in 16 bytes for small values (null, bool, int, float, short strings) and heap-allocates for larger ones.

**arrays:** PHP arrays are ordered hashmaps that preserve insertion order and support both integer and string keys. this is the most performance-critical data structure in PHP. implement as a hash table with a separate insertion-order linked list.

**strings:** binary-safe (can contain null bytes), reference-counted with copy-on-write semantics. PHP strings are not UTF-8 - they're byte sequences. zphp matches this behavior.

**memory model:** zig's allocator model maps naturally to PHP's request lifecycle. use arena allocation for request-scoped memory with reference counting for values that escape the arena. cycle collector runs periodically for circular references.

**parser strategy:** recursive descent. PHP's grammar has some nasty ambiguities (e.g. `$a[0]` could be array access or list destructuring depending on context) but recursive descent handles these with lookahead. no parser generator - hand-written for speed and error quality.

## workflow

at the start of every session:
1. run the audit: `./audit`
2. check open issues: `gh issue list`
3. be skeptical of issues - assume invalid until proven otherwise. reproduce or verify against actual code before acting

at the end of every session:
1. run the audit again
2. commit and push any changes
3. update this CLAUDE.md if anything about the architecture, decisions, or gotchas changed

## standards

- zig 0.15.x
- test with `zig build test`. tests must pass before pushing
- short lowercase commit messages, no co-author lines. initial commit is just the version number (e.g. `0.1.0`)
- code comments are casual, no capitalization (except proper nouns), no ending punctuation. only comment when code can't speak for itself
- public-facing content (README, descriptions) uses proper grammar and casing
- no emojis anywhere

## CI

GitHub Actions: run `zig build test` on push. test on ubuntu-latest and macos-latest.

## distribution

zphp is distributed via GitHub releases with prebuilt binaries - like bun. no package registry.

- bump version in build.zig.zon
- commit with just the version number
- tag: `git tag v0.1.0`
- push with tags: `git push && git push --tags`
- GitHub Actions builds release binaries for linux (x86_64, aarch64) and macOS (aarch64)

future: install script (`curl -fsSL https://zphp.dev/install | bash`) and homebrew tap.

## the README

must include:
- what zphp is (one paragraph - the bun analogy)
- installation instructions
- CLI usage examples showing all subcommands
- comparison with traditional PHP toolchain (what zphp replaces)
- which PHP 8.x features are supported
- known divergences from Zend behavior
- note that this is an experiment in AI-maintained open source - autonomously built, tested, and refined by AI with human oversight. high quality, rigorously tested, production-grade code

update ~/code/nvms/README.md whenever the project is created, renamed, or has significant changes. zphp should appear with a CI badge and a brief description. standalone projects put badges on their own line below the heading, not inline.

## user commands

- "hone" or just starting a conversation - run the audit, check issues, assess and refine
- "hone <area>" - focus on a specific area (e.g. "hone lexer", "hone vm", "hone package manager")
- critically assess with fresh eyes: read every line, find edge cases, stress the implementation. assume this code runs in mission-critical systems

## development strategy

build in this order:
1. lexer + parser for a meaningful PHP subset (variables, functions, control flow, basic types)
2. bytecode compiler + VM that can execute simple scripts
3. expand language support: classes, interfaces, traits, closures, generators
4. standard library functions (start with the most commonly used)
5. package manager (composer.json parsing, packagist resolution, install)
6. `zphp build` (bundle to binary)
7. `zphp test` (test runner)
8. `zphp fmt` (formatter)

each phase should be testable independently. write comprehensive tests at every stage - the test suite is the specification.

## issue triage

at the start of every session, check open issues (`gh issue list`). be skeptical - assume issues are invalid until proven otherwise. for each issue:
1. read it carefully
2. try to reproduce or verify against actual code
3. if user error or misunderstanding, close with explanation
4. if genuine bug, fix it, add a test, close
5. if valid feature request that fits scope, consider it. if not, close with explanation
6. do not implement feature requests without verifying alignment with the concept

## retirement

if the user says "retire":
1. archive the repo: `gh repo archive nvms/zphp`
2. update repo README with `> [!NOTE]` block explaining why
3. update ~/code/nvms/README.md - move to archived section
4. tell the user the local directory will be moved to archive/ and projects.md will be updated

## use gh CLI for all GitHub operations

do NOT use the GitHub MCP server for creating repos or any write operations. the MCP server is only useful for reading public repos.

## zig 0.15.x gotchas

- `std.io.getStdOut()` does not exist in 0.15.1. use `std.posix.write(std.posix.STDOUT_FILENO, ...)` for stdout or `std.debug.print` for stderr
- `std.StaticStringMap` works and is the right choice for comptime lookup tables
- switch ranges use `...` (inclusive): `'a'...'z'`, `0x80...0xff`
- `@intCast` infers target type from context: `const x: u32 = @intCast(some_usize);`
- `std.ArrayList(T)` is now the UNMANAGED version (no stored allocator). use `.{}` to init, pass allocator to `append(gpa, item)`, `writer(gpa)`, `deinit(gpa)`, `toOwnedSlice(gpa)`. the managed version with stored allocator is deprecated
- `std.ArrayListUnmanaged(T)` is identical to `std.ArrayList(T)` in 0.15.1

## current status

phase 1 complete: full pipeline from source to execution. zphp can run real PHP scripts.

### what exists
- `src/pipeline/token.zig` - 145 PHP 8.x token types, case-insensitive keyword lookup (42 tests in lexer)
- `src/pipeline/lexer.zig` - full PHP lexer with HTML/PHP modal lexing
- `src/pipeline/ast.zig` - flat array AST, 36 node tags (includes closure_expr)
- `src/pipeline/parser.zig` - Pratt-based recursive descent parser (52 tests)
- `src/pipeline/bytecode.zig` - ~47 opcodes (includes call_indirect, closure_bind), Chunk struct, ObjFunction struct
- `src/pipeline/compiler.zig` - single-pass AST -> bytecode compiler with jump patching, function compilation, numeric literal parsing, string interpolation
- `src/runtime/value.zig` - PHP Value tagged union (null, bool, int, float, string) with arithmetic, truthiness, string-aware comparison, formatting (3 tests)
- `src/runtime/vm.zig` - stack-based bytecode interpreter with per-frame variable scoping, function calls, closures with captures, arrays, foreach, native function dispatch, output capture (61 integration tests)
- `src/runtime/stdlib.zig` - 60+ native PHP functions: array (push/pop/shift/keys/values/merge/slice/reverse/unique/sort/rsort/search/in_array/key_exists/range/array_map/array_filter/usort), string (substr/strpos/str_replace/explode/implode/trim/ltrim/rtrim/strtolower/strtoupper/str_contains/str_starts_with/str_ends_with/str_repeat/str_pad/ucfirst/lcfirst), math (abs/floor/ceil/round/min/max/rand), type (gettype/is_array/is_null/is_int/is_float/is_string/is_bool/is_numeric/intval/floatval/strval/isset/empty/count/strlen)
- `src/main.zig` - CLI entry point with `zphp run <file>`, imports all modules for test discovery
- 158 unit tests total across all modules
- 26 PHP compatibility test files in tests/ verified against PHP 8.3

### lexer design decisions
- tokens reference byte offsets into source (zero-copy, no allocations)
- PHP keywords are case-insensitive (lowercased before lookup)
- strings are lexed as single tokens (interpolation handled later by compiler)
- heredocs/nowdocs not yet supported (will produce invalid token)
- `#[` produces hash_bracket token (not treated as comment)
- bare `$` produces dollar token (for variable-variable support later)
- the lexer never errors - invalid input produces `.invalid` tokens
- HTML mode scans for `<?php` (with trailing whitespace) and `<?=` only, no short open tags

### parser design decisions
- flat AST: nodes in a contiguous array, children referenced by u32 index. extra_data array for variable-length children (function params, call args, block statements, echo expressions, array elements)
- root node always at index 0. lhs/rhs = 0 means "no child" for optional fields
- Pratt parser for expressions: single infixPrec() function maps token tags to precedence levels 1-19. right-associative ops (assignment, ??, **) use prec-1 for right side
- short-circuit ops (&&, ||, ??, and, or) get dedicated AST tags (logical_and, logical_or, null_coalesce) for distinct codegen. regular binary ops share a single binary_op tag with the operator stored in main_token
- `elseif` is parsed as nested if_else in the else branch. `else if` (two words) naturally produces the same structure
- function params: just variable nodes for now (no type hints, no defaults, no variadic). return type hints are skipped
- `<?= expr ?>` is transformed into echo_stmt during parsing
- open_tag and close_tag tokens are consumed/skipped by the parser, not represented in the AST
- error recovery: on parse error, skip to next `;`, `}`, or statement keyword and continue
- S-expression renderer in test helpers makes parser tests compact and readable

### compiler design decisions
- single-pass AST walk: compileNode() dispatches on node tag, emits bytecodes
- ~45 opcodes: constants, variable get/set, arithmetic, comparison, logical, bitwise, jumps, call/return, echo, halt
- variables use `get_var`/`set_var` with string name constants (hash map lookup at runtime, not stack slots). simplifies scoping at the cost of performance
- jump patching: emit placeholder u16, record offset, patch when target is known
- control flow: `jump_if_false`/`jump_if_true` peek (don't pop) the condition. explicit `pop` on each path. this supports short-circuit `&&`/`||` cleanly
- functions: compiled as separate Chunks via sub-compiler. function list passed to VM alongside main chunk. VM pre-registers all functions before execution (implicit hoisting)
- compound assignment (`+=` etc.): emits get_var + rhs + op + set_var
- post-increment: emits two get_var (one for expression result, one for modification), add 1, set_var, pop
- string concat: allocates a new string buffer at runtime, tracked by VM for cleanup
- numeric literals: custom parser handles hex (0x), binary (0b), octal (0o), and underscore separators
- string interpolation: double-quoted strings with `$var`, `{$var}`, `$arr[idx]`, `{$arr['key']}` are split into segments at compile time. each segment emits a constant or get_var+array_get, joined with concat ops. escaped `\$` suppresses interpolation. single-quoted strings never interpolate

### VM design decisions
- stack-based: 256-slot value stack, 64 call frames
- per-frame variable scoping via StringHashMapUnmanaged (each call frame has its own variable hash map). correctly isolates function-local variables from the caller
- function params pre-populated in the frame's var map before execution
- output captured in an ArrayListUnmanaged(u8) for testing. integration tests verify the entire pipeline: source -> lex -> parse -> compile -> execute -> output
- runtime-allocated strings tracked in a separate list, freed on VM deinit
- PHP-correct value formatting: true->"1", false->"", null->"", floats that are whole numbers display as integers
- string comparison: `lessThan` and `compare` (spaceship) use lexicographic ordering when both operands are strings, float comparison otherwise. matches PHP behavior for sort/usort on string arrays

### what the VM can execute
- arithmetic: +, -, *, /, %, ** with int/float promotion
- string concatenation: .
- comparison: ==, !=, ===, !==, <, <=, >, >=, <=>
- logical: &&, ||, !, and, or
- bitwise: &, |, ^, ~, <<, >>
- null coalesce: ??
- ternary: ? : and short ternary ?:
- variables: assignment, compound assignment (+=, -=, etc.), pre/post increment/decrement
- control flow: if/elseif/else, while, do-while, for, foreach, break, continue
- functions: declaration, calls, return with/without value, nested calls, parameter passing
- closures: anonymous functions, arrow functions (fn($x) => expr), assigned to variables, passed as arguments
- callbacks: closures and named function strings as callbacks to array_map, array_filter, usort
- arrays: literals with integer and string keys, access, assignment, mixed key types
- foreach: iterate arrays with value only or key => value
- native functions: count(), strlen(), intval(), strval(), is_array(), is_null(), is_int(), is_string()
- string interpolation: `"Hello $name"`, `"{$var}"`, `"$arr[0]"`, `"{$arr['key']}"`, escaped `\$`
- echo: single and multi-expression
- mixed HTML/PHP output

### array implementation
- PhpArray: ordered hashmap with integer and string keys, preserves insertion order
- linear scan for lookups (O(n), correct for small arrays, optimize later)
- auto-increment integer key for append operations
- arrays are reference-semantics (pointer-based). this diverges from PHP's copy-on-write semantics but is correct for most code. known limitation
- VM tracks all array allocations and frees them on deinit (simple GC)
- native function dispatch: VM checks native function table before user function table. native fns receive args slice and return a Value. no stack frame needed

### CLI
- `zphp run <file>` executes a PHP file through the full pipeline
- `zphp version` / `zphp --version` prints version
- bare `zphp` prints version

### PHP compatibility tests
- `tests/` directory contains `.php` files that test specific language features
- `tests/run` script runs each file through both `php` and `zphp run`, diffs output. any divergence fails
- CI runs the comparison against PHP 8.3 via `shivammathur/setup-php`
- rule: every new feature gets a test file added. the spec is PHP's behavior
- currently 26 test files covering all supported features
- double-quoted string escape sequences (\n, \r, \t, \\, \$, \", etc.) are processed at compile time. single-quoted strings only escape \\ and \'
- string interpolation in double-quoted strings: `$var`, `{$var}`, `$arr[idx]`, `{$arr['key']}` - all handled at compile time by splitting into segments and emitting concat ops

### closure architecture
- closures compiled as named functions with generated names (`__closure_0`, `__closure_1`, etc.)
- closure name string pushed as a Value, stored in variables like any other value
- `call_indirect` opcode: pops function name string from stack (below args), looks up and calls the function
- NativeContext has a `vm` pointer and `callFunction(name, args)` method for native functions to invoke PHP callbacks
- `callByName` on the VM re-enters the execution loop via `runUntilFrame(base_frame)` - base_frame tracks where to stop so nested callback execution returns correctly
- `runLoop(base_frame)` is the single execution loop; `run()` calls `runLoop(0)`, `runUntilFrame(n)` calls `runLoop(n)`
- arrow functions (`fn($x) => expr`) are desugared to `closure_expr` with a synthetic block containing a return_stmt
- `use` clause captures variables by value at closure creation time (PHP-correct value semantics)
- `closure_bind` opcode: reads a variable from the current scope and stores it in the VM's captures table keyed by closure name
- captures table is a flat list of (closure_name, var_name, value) entries, scanned at call time to pre-populate the frame's vars before params
- string function names also work as callbacks: `array_map('trim', $arr)` passes the string through the same `callByName` path

### roadmap (in execution order)

each step should unlock the maximum amount of real PHP code with the minimum architecture change. language features and stdlib gaps are interleaved so that each feature is immediately usable.

**1. PHP constants + type casting**
two small language changes that fix silent breakage. constants: add a constants table (string -> Value) checked before variables at compile time. pre-populate with PHP's predefined constants (STR_PAD_LEFT, PHP_INT_MAX, PHP_EOL, SORT_ASC, etc.). support `define('NAME', value)` and `const NAME = value`. type casting: `(int)`, `(string)`, `(array)`, `(bool)`, `(float)`. parser change (cast as prefix expression) + compiler emits conversion opcodes. most conversion logic already exists in Value

**2. switch + match**
switch: jump table over cases with fallthrough semantics and break/default. match: PHP 8 expression-based strict comparison, no fallthrough, returns a value. both very common in real PHP code

**3. stdlib expansion pass 1 - fill the gaps that block real scripts**
these are pure additions to stdlib.zig, no architecture changes needed:
- string: `strcmp`, `strncmp`, `str_word_count`, `str_split`, `substr_count`, `substr_replace`, `sprintf`, `printf`, `number_format`, `nl2br`, `wordwrap`, `str_getcsv`, `chunk_split`, `ord`, `chr`, `hex2bin`, `bin2hex`, `md5`, `sha1`, `base64_encode`, `base64_decode`, `urlencode`, `urldecode`, `rawurlencode`, `rawurldecode`, `html_entity_decode`, `htmlspecialchars`, `htmlspecialchars_decode`, `addslashes`, `stripslashes`, `quoted_printable_encode`, `quoted_printable_decode`, `strtolower`, `strtoupper`, `mb_strlen`, `mb_substr`, `mb_strtolower`, `mb_strtoupper`
- array: `array_splice`, `array_combine`, `array_chunk`, `array_pad`, `array_flip`, `array_column`, `array_fill`, `array_fill_keys`, `array_intersect`, `array_diff`, `array_diff_key`, `array_count_values`, `array_sum`, `array_product`, `array_walk`, `compact`, `extract`, `ksort`, `krsort`, `asort`, `arsort`, `array_multisort`, `array_unshift`, `array_rand`, `shuffle`
- math: `pow`, `sqrt`, `log`, `log2`, `log10`, `exp`, `pi`, `fmod`, `intdiv`, `base_convert`, `bindec`, `octdec`, `hexdec`, `decbin`, `decoct`, `dechex`
- type/misc: `settype`, `boolval`, `var_export`, `unset` (as function), `compact`, `extract`, `print_r` (real impl), `var_dump` (real impl)
- json: `json_encode`, `json_decode`
- date/time: `time`, `microtime`, `date`, `strtotime`, `mktime`, `gmdate`
- file: `file_get_contents`, `file_put_contents`, `file_exists`, `is_file`, `is_dir`, `realpath`, `basename`, `dirname`, `pathinfo`
- output: `ob_start`, `ob_get_clean`, `ob_end_clean`, `header` (no-op or warning in CLI)
- pcre: `preg_match`, `preg_match_all`, `preg_replace`, `preg_split`

prioritize within this list: `sprintf`, `json_encode`/`json_decode`, `strcmp`, `array_splice`, `array_combine`, `var_dump`/`print_r` (real implementations), and the file functions. these are the ones most likely to block real scripts

**4. classes (basic)**
declaration, `new`, properties, methods, `$this`, `__construct`. enough to instantiate objects and call methods. this is the minimum viable OOP that unlocks simple class-based code

**5. classes (advanced)**
inheritance with `extends`, `parent::`, `static` methods/properties, visibility (public/protected/private), abstract classes, interfaces, traits. needed for any real composer package

**6. try/catch/throw**
exceptions are objects in PHP, so this depends on basic classes. compile try/catch as exception handler frames with jump targets. throw creates an exception object and unwinds to the nearest handler

**7. stdlib expansion pass 2 - OOP-dependent functions**
functions that return or consume objects: `DateTime`, `SplStack`, `ArrayObject`, `json_decode` with object return, `PDO` stubs. these depend on the class system being in place

**8. generators/yield**
`yield` and `yield from`. needed for lazy iteration patterns common in modern PHP. requires a new coroutine-like execution model - each generator gets its own suspended call frame

**9. package manager**
composer.json parsing, packagist API client, semver dependency resolution (SAT solver), install to vendor/, autoloader generation. this is the differentiator that makes zphp a toolchain replacement. depends on classes + file I/O + json

## self-improvement

keep this CLAUDE.md up to date. after making changes, review and update: architecture notes, design decisions, gotchas, anything the next session needs to know. this is not optional.
