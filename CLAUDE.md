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
- `zphp serve` built-in HTTP server with persistent VM workers (no per-request bootstrap)
- fast cold starts, small binary, low memory footprint

## what this project does NOT do

- C extension compatibility (no PDO, no mbstring via C - pure zig reimplementations where needed)
- 100% Zend edge-case compatibility (the 95% that matters)
- JIT compilation (interpreter first, JIT is a future consideration)
- FFI support (not initially)
- web server (not a replacement for nginx/apache - `zphp serve` is zphp's built-in HTTP server for both dev and production use)

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
    types.zig           - gettype, is_string, is_array, intval, strval, etc.
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
9. `zphp serve` (built-in HTTP server with pre-loaded VM pool)
10. fibers (PHP 8.1 cooperative multitasking)
11. async I/O hooks (suspend fibers on I/O, optional future work)

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
- `std.crypto.hash.Md5.hash` takes 3 args: `(data, &out_buf, .{})` - not 2
- C system libraries: always set `link_libc = true` on the module, otherwise dynamic symbol resolution segfaults on Linux at runtime
- prefer manual `extern` declarations with `callconv(.c)` over `@cImport` for C library bindings. `@cImport` macro translation breaks across platforms

## external dependencies

- **libpcre2** - linked via zig's system library support for regex (preg_* functions). install: `apt install libpcre2-dev` (ubuntu), `brew install pcre2` (macos). CI workflow installs it in the build step. uses manual extern declarations (not @cImport) for cross-platform reliability. `link_libc = true` is required on all modules that link pcre2

## current status

phase 1 complete: full pipeline from source to execution. zphp can run real PHP scripts.

### what exists
- `src/pipeline/token.zig` - 145 PHP 8.x token types, case-insensitive keyword lookup (42 tests in lexer)
- `src/pipeline/lexer.zig` - full PHP lexer with HTML/PHP modal lexing
- `src/pipeline/ast.zig` - flat array AST, 52 node tags (closure_expr, cast_expr, const_decl, switch_stmt/case/default, match_expr/arm, class_decl/method/property, new_expr, method_call, static_call)
- `src/pipeline/parser.zig` - Pratt-based recursive descent parser with 2-token lookahead for cast detection, class declaration parsing with visibility modifier skipping, method call detection in property access (52 tests)
- `src/pipeline/bytecode.zig` - ~64 opcodes (call_indirect, closure_bind, define_const, dup, cast_int/float/string/bool/array, class_decl, new_obj, get_prop, set_prop, method_call, static_call), Chunk struct, ObjFunction struct
- `src/pipeline/compiler.zig` - single-pass AST -> bytecode compiler with jump patching, function compilation, numeric literal parsing, string interpolation
- `src/runtime/value.zig` - PHP Value tagged union (null, bool, int, float, string, array, object) with arithmetic, truthiness, string-aware comparison, formatting. PhpObject struct with property hashmap (4 tests)
- `src/runtime/vm.zig` - stack-based bytecode interpreter with per-frame variable scoping, function calls, closures with captures, arrays, foreach, switch/match, constants table, type casts, native function dispatch, class registry, object instantiation, property access, method dispatch with $this binding, output capture (93 integration tests)
- `src/stdlib/` - 150+ native PHP functions split by domain:
  - `registry.zig` - central registration, imports all domain modules and registers their functions with the VM
  - `strings.zig` - substr/strpos/str_replace/explode/implode/trim/ltrim/rtrim/strtolower/strtoupper/str_contains/str_starts_with/str_ends_with/str_repeat/str_pad/ucfirst/lcfirst/strcmp/strncmp/ord/chr/str_split/substr_count/substr_replace/str_word_count/nl2br/wordwrap/chunk_split/number_format/sprintf/printf/addslashes/stripslashes/htmlspecialchars/htmlspecialchars_decode/html_entity_decode/hex2bin/bin2hex/mb_strlen/mb_substr/mb_strtolower/mb_strtoupper/str_getcsv/base64_encode/base64_decode/urlencode/urldecode/rawurlencode/rawurldecode/md5/sha1/strrev
  - `arrays.zig` - push/pop/shift/keys/values/merge/slice/reverse/unique/sort/rsort/search/in_array/key_exists/range/array_map/array_filter/usort/array_splice/array_combine/array_chunk/array_pad/array_flip/array_column/array_fill/array_fill_keys/array_intersect/array_diff/array_diff_key/array_count_values/array_sum/array_product/array_walk/array_unshift/shuffle/array_rand/ksort/krsort/asort/arsort
  - `math.zig` - abs/floor/ceil/round/min/max/rand/pow/sqrt/log/log2/log10/exp/pi/fmod/intdiv/base_convert/bindec/octdec/hexdec/decbin/decoct/dechex
  - `types.zig` - gettype/is_array/is_null/is_int/is_float/is_string/is_bool/is_numeric/intval/floatval/strval/boolval/isset/empty/count/strlen/var_dump/print_r/define/defined/constant
  - `json.zig` - json_encode/json_decode
  - `io.zig` - file_get_contents/file_put_contents/file_exists/is_file/is_dir/basename/dirname/pathinfo/realpath/time/microtime/date
  - `pcre.zig` - preg_match/preg_match_all/preg_replace/preg_split (FFI bindings to libpcre2)
- `src/main.zig` - CLI entry point with `zphp run <file>`, imports all modules for test discovery
- 215 unit tests total across all modules
- 44 PHP compatibility test files in tests/ verified against PHP 8.3

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
- ~54 opcodes: constants, variable get/set, arithmetic, comparison, logical, bitwise, jumps, call/return, call_indirect, echo, halt, dup, cast_int/float/string/bool/array, define_const, closure_bind
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
- control flow: if/elseif/else, while, do-while, for, foreach, switch/case/default (with fallthrough), break, continue
- match expression: strict comparison, multi-value arms, default, returns a value
- functions: declaration, calls, return with/without value, nested calls, parameter passing
- closures: anonymous functions, arrow functions (fn($x) => expr), assigned to variables, passed as arguments
- callbacks: closures and named function strings as callbacks to array_map, array_filter, usort
- arrays: literals with integer and string keys, access, assignment, mixed key types
- foreach: iterate arrays with value only or key => value
- constants: 40+ predefined PHP constants, `define()`, `const NAME = value`, `defined()`, `constant()`
- type casting: `(int)`, `(float)`, `(string)`, `(bool)`, `(array)`
- native functions: 150+ stdlib functions across strings, arrays, math, types, json, io, pcre (see src/stdlib/ for complete list)
- string interpolation: `"Hello $name"`, `"{$var}"`, `"$arr[0]"`, `"{$arr['key']}"`, escaped `\$`
- classes: declaration with properties (with defaults) and methods, `new ClassName(args)`, `$obj->method(args)`, `$obj->prop`, `$this` binding in methods, `__construct` auto-call, `ClassName::method()` static calls, `extends` inheritance, `parent::method()` calls
- exceptions: try/catch/finally, throw, typed catch with instanceof checking, multi-catch, nested try/catch with propagation, re-throw on no match, built-in Exception/RuntimeException/etc classes
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
- currently 30 test files covering all supported features
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

### constants and type casting
- VM has a `php_constants` table (StringHashMap) pre-populated with 40+ PHP constants in `initConstants()`
- `get_var` opcode checks frame vars first, then falls through to `php_constants`, then returns null
- predefined constants: PHP_EOL, PHP_INT_MAX/MIN, PHP_INT_SIZE, PHP_VERSION, PHP_SAPI, PHP_OS, DIRECTORY_SEPARATOR, PATH_SEPARATOR, STR_PAD_LEFT/RIGHT/BOTH, SORT_REGULAR/NUMERIC/STRING/ASC/DESC, JSON_PRETTY_PRINT/UNESCAPED_SLASHES/UNESCAPED_UNICODE, E_ERROR/WARNING/NOTICE/ALL, PHP_FLOAT_MAX/MIN/EPSILON, M_PI/E/SQRT2/LN2/LN10, INF, NAN, TRUE/FALSE/NULL
- `define('NAME', value)` native function writes to `php_constants`
- `const NAME = value;` compiles to value expression + `define_const` opcode
- `defined()` and `constant()` native functions for runtime constant queries
- type casting: `(int)`, `(integer)`, `(float)`, `(double)`, `(real)`, `(string)`, `(bool)`, `(boolean)`, `(array)` parsed via 2-token lookahead in `parsePrimaryExpr`. disambiguates `(int)$x` from `($x + 1)` by checking if token after `(` is a known cast type and token after that is `)`. compiles to dedicated cast opcodes that use existing Value conversion methods

### switch/match compilation
- switch uses a hidden temp variable (`__switch_N`) to store the subject, avoiding stack management issues with fallthrough
- two-phase layout: phase 1 emits comparison chain (get_var + case value + `equal` + jump-to-body), phase 2 emits all bodies sequentially (enables fallthrough - no break means execution flows into next body)
- multi-value cases (`case 1: case 2:`) merged into one node with multiple values. comparison uses `jump_if_true` to short-circuit to body on first match
- break compiles to `jump` with break_jumps patching, same mechanism as loops
- match uses same temp var approach but with `identical` (strict comparison). each arm compiles result expression and jumps to end. no fallthrough. match is an expression (leaves result on stack)
- match with no matching arm and no default returns null (PHP would throw UnhandledMatchError, but we don't have exceptions yet)
- `Value.equal` was fixed to do string comparison when both operands are strings (was converting to float, causing `"php" == "js"` to be true)

### class system architecture
- `PhpObject` struct: `class_name` + `StringHashMapUnmanaged(Value)` for properties. stored as `Value.object` (pointer semantics, like arrays)
- `ClassDef` struct in VM: name, methods hashmap (name -> arity), properties list (name + default value), optional parent class name
- class declarations compile methods as `ClassName::methodName` functions in the global function table, then emit `class_decl` opcode with inline metadata (method names/arities, property names/defaults, parent)
- property default expressions compile BEFORE the `class_decl` opcode so values are on the stack when the opcode handler reads them
- `new_obj` opcode: creates PhpObject, walks parent chain to init property defaults, looks up `ClassName::__construct` and calls it via `runUntilFrame` (nested execution). constructor gets `$this` in its frame vars
- `method_call` opcode: object is on stack below args. resolveMethod walks the class parent chain to find `ClassName::methodName`. creates new frame with `$this` bound to the object, sets params, continues execution in the same runLoop (no nested call needed - return_val handles frame pop)
- `get_prop`/`set_prop` opcodes: pop object from stack, read/write property by name on the PhpObject
- `static_call` opcode: resolves `ClassName::methodName` and calls via existing `callNamedFunction` (no `$this` binding)
- property names stripped of `$` prefix at compile time (PHP variables have `$` but property names in objects don't)
- visibility modifiers (public/protected/private) are parsed and skipped - not enforced yet

### exception handling architecture
- `ExceptionHandler` struct: catch_ip (absolute jump target), frame_count/sp (state to restore), chunk pointer
- VM maintains a stack of 32 exception handlers (push_handler/pop_handler)
- `throw` opcode: pops exception from stack, unwinds frames to handler's frame_count, restores sp, pushes exception, jumps to catch_ip
- catch clauses compiled inline with `instance_check` type testing. `dup` exception, push class name, `instance_check` (walks parent chain), `jump_if_false` to skip. if no catch matches, re-throw opcode propagates to next handler
- `instance_check` opcode: `isInstanceOf()` walks the class parent chain, so `catch (Exception $e)` catches RuntimeException etc
- finally blocks compile after both normal and catch paths - they execute on both code paths (no special opcode needed since they're reached by normal flow)
- built-in Exception class registered at VM init with native method implementations for __construct, getMessage, getCode. native methods get `$this` via a temporary frame pushed around the native call
- built-in exception hierarchy: Exception, RuntimeException, InvalidArgumentException, LogicException, BadMethodCallException, OverflowException, TypeError
- when throw fires inside a function/method, frame unwinding cleans up call frames back to the handler's level, correctly crossing function boundaries

### dangling pointer gotcha in temp variable names
switch/match compilation generates temp variable names like `__match_0` using `std.fmt.allocPrint` (heap allocated, tracked in string_allocs). originally used stack-allocated `bufPrint` which caused use-after-free when the constant pool held a pointer to the expired stack buffer. the bug was latent - only manifested when other changes shifted the stack layout enough to overwrite the buffer. rule: any string stored in the constant pool must be either a source slice or a heap allocation tracked by string_allocs

### roadmap (in execution order)

each step should unlock the maximum amount of real PHP code with the minimum architecture change. language features and stdlib gaps are interleaved so that each feature is immediately usable.

**1. PHP constants + type casting** (DONE)
two small language changes that fix silent breakage. constants: add a constants table (string -> Value) checked before variables at compile time. pre-populate with PHP's predefined constants (STR_PAD_LEFT, PHP_INT_MAX, PHP_EOL, SORT_ASC, etc.). support `define('NAME', value)` and `const NAME = value`. type casting: `(int)`, `(string)`, `(array)`, `(bool)`, `(float)`. parser change (cast as prefix expression) + compiler emits conversion opcodes. most conversion logic already exists in Value

**2. switch + match** (DONE)
switch compiles to two-phase layout: comparison chain (using temp var + loose equality) then sequential bodies (enables fallthrough). break patches to end. match compiles similarly but uses strict identity, each arm emits its result expression and jumps to end. no new opcodes except `dup` (added but switch/match use temp vars instead)

**3. stdlib expansion pass 1 - fill the gaps that block real scripts** (IN PROGRESS)
pure additions to the domain files in src/stdlib/, no architecture changes needed.

done (see src/stdlib/ for complete list - 150+ functions across strings, arrays, math, types, json, io, pcre modules)

remaining:
- string: `quoted_printable_encode`, `quoted_printable_decode`
- array: `compact`, `extract`, `array_multisort`
- type/misc: `settype`, `var_export`, `unset` (as function)
- date/time: `strtotime`, `mktime`, `gmdate`
- output: `ob_start`, `ob_get_clean`, `ob_end_clean`, `header` (no-op or warning in CLI)

note: `compact` and `extract` require access to the calling scope's variables, which native functions don't currently have. these may need a VM-level mechanism or special opcode treatment

**4. classes (basic)** (IN PROGRESS)
declaration, `new`, properties, methods, `$this`, `__construct`. enough to instantiate objects and call methods. this is the minimum viable OOP that unlocks simple class-based code

done:
- class declaration parsing (skips visibility modifiers, parses methods and properties with defaults)
- `new ClassName(args)` expression
- `$obj->method(args)` method calls with `$this` binding
- `$obj->prop` property read/write
- `__construct` called automatically on new
- property defaults set from class definition
- `ClassName::method()` static call syntax (parsed and compiled, dispatches to `ClassName::method` function)
- PhpObject struct with string-keyed property hashmap
- ClassDef registry in VM (name, methods, properties with defaults, optional parent)
- method resolution walks parent chain for inheritance support
- `gettype()` returns "object" for objects

done (continued):
- `extends` keyword for single inheritance
- inherited constructors (child without __construct uses parent's)
- `parent::method()` and `parent::__construct()` calls
- `self::method()` calls
- multi-level inheritance (A -> B -> C) with correct parent:: resolution at each level
- `parent::` resolves relative to the defining class, not $this->class_name (prevents infinite recursion in deep hierarchies)
- `currentDefiningClass()` extracts class name from the function name pattern `ClassName::methodName`
- inherited property defaults (parent properties set first, child can override)

remaining:
- `static` methods/properties
- visibility enforcement (public/protected/private)
- `instanceof` operator (currently mapped to identical, needs own opcode)
- abstract classes, interfaces, traits (step 5)

**5. classes (advanced)**
inheritance with `extends`, `parent::`, `static` methods/properties, visibility (public/protected/private), abstract classes, interfaces, traits. needed for any real composer package

**6. try/catch/throw** (DONE)
exceptions are objects in PHP, so this depends on basic classes. compile try/catch as exception handler frames with jump targets. throw creates an exception object and unwinds to the nearest handler

**7. stdlib expansion pass 2 - OOP-dependent functions**
functions that return or consume objects: `DateTime`, `SplStack`, `ArrayObject`, `json_decode` with object return, `PDO` stubs. these depend on the class system being in place

**8. generators/yield**
`yield` and `yield from`. needed for lazy iteration patterns common in modern PHP. requires a new coroutine-like execution model - each generator gets its own suspended call frame

**9. package manager**
composer.json parsing, packagist API client, semver dependency resolution (SAT solver), install to vendor/, autoloader generation. this is the differentiator that makes zphp a toolchain replacement. depends on classes + file I/O + json

**10. `zphp serve` - built-in HTTP server (pre-loaded VM pool)**
the primary way to serve PHP applications with zphp. replaces PHP's built-in web server (`php -S`), and makes Swoole/Workerman/FrankenPHP/RoadRunner unnecessary for zphp users.

architecture: two layers, cleanly separated.
- **zig HTTP layer** (async): accepts connections, parses HTTP, reads/writes responses. uses zig's native I/O (epoll/kqueue/io_uring). this layer is naturally async - the event loop lives here, not in PHP-land
- **PHP VM layer** (synchronous): PHP scripts execute top-to-bottom within each request. no async primitives needed in PHP code

execution model: on startup, `zphp serve` compiles the application once (parse -> compile to bytecode). spawns N worker threads, each with its own VM instance sharing the compiled bytecode and function/class definitions. incoming requests dispatch to an available worker with a fresh variable scope (clean `$_GET`, `$_POST`, `$_SERVER`, local vars). the scope is wiped after each request, the worker is reused. no re-parsing, no re-compiling, no bootstrap cost per request.

this is what RoadRunner and FrankenPHP worker mode achieve through Go-PHP bridging (Goridge IPC, CGO), but zphp gets it natively - the HTTP server and the PHP VM are in the same binary, same memory space, same language. zero IPC, zero serialization, zero protocol overhead.

key design decisions:
- application stays loaded. compiled bytecode and function/class tables are shared (read-only) across workers
- each request gets a clean scope: fresh superglobals, clean local variables, clean output buffer
- worker count configurable (default: CPU cores). each worker handles one request at a time, sequentially
- the zig async layer handles connection concurrency (thousands of connections), the PHP layer handles request logic (one at a time per worker)
- no need for opcache (the bytecode is already in memory), no need for preloading (the app is already loaded)

**11. fibers (PHP 8.1 cooperative multitasking)**
`Fiber::start()`, `Fiber::suspend()`, `Fiber::resume()`. cooperative multitasking within a single request. each fiber gets its own suspended call frame and stack. this is a VM feature, not a server feature - works with or without `zphp serve`. required for many modern PHP libraries (e.g. ReactPHP, Amp)

**12. async I/O hooks (optional, future)**
the Swoole play, but native. hook I/O operations (database queries, HTTP calls, file reads) to suspend the current fiber while waiting, allowing other fibers in the same worker to make progress. this turns the synchronous-per-worker model into a concurrent-per-worker model without changing how PHP code looks. this is the most ambitious item - it requires deep integration between the VM's fiber system and the zig HTTP layer's event loop. not needed for the initial `zphp serve` to be fast and useful

## competitive positioning

every existing PHP performance project - PHP-FPM, Swoole, Workerman, FrankenPHP, RoadRunner - orbits the Zend engine. PHP-FPM *is* Zend. Swoole *extends* Zend via a C extension. Workerman *runs on* Zend as pure PHP. FrankenPHP *embeds* Zend into Caddy via CGO. RoadRunner *manages* Zend processes from Go. none of them replace the engine itself. they optimize the layers around it - process model, I/O model, request lifecycle - but the actual PHP interpretation is always Zend.

zphp is the only project that replaces Zend entirely. the analogy is bun: bun replaced V8 + npm + webpack + jest with a single Zig binary. zphp replaces Zend + composer + phpunit + php-cs-fixer with a single Zig binary. this is a fundamentally different bet.

what makes zphp unique:
- **toolchain unification** - `zphp run`, `zphp install`, `zphp test`, `zphp fmt`, `zphp build`, `zphp serve` - one binary, one tool. no other PHP project does this
- **compile to standalone binary** - `zphp build` bundles bytecode + runtime into a single executable. this distribution model doesn't exist in the PHP world at all
- **zero C dependencies in the distributed binary** - pure Zig (pcre2 is linked at build time, baked into the binary). users never need to install anything beyond zphp itself
- **`zphp serve` with pre-loaded VM** - the HTTP server and the PHP VM are in the same binary, same memory space, same language. no IPC, no serialization, no FastCGI protocol overhead. this is what FrankenPHP and RoadRunner achieve through complex bridging (CGO, Goridge), but zphp gets it natively because the server IS the runtime
- **fresh memory model** - Zig's allocator model, arena allocation, tagged union values in 16 bytes. no decades of Zend memory management decisions to carry

the tradeoff: existing projects get full Zend compatibility for free (every PECL extension, every C binding, every edge case). zphp earns compatibility function by function, targeting the 95% of semantics that real-world code actually uses.

## self-improvement

keep this CLAUDE.md up to date. after making changes, review and update: architecture notes, design decisions, gotchas, anything the next session needs to know. this is not optional.
