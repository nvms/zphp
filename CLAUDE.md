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

phase 1 in progress: lexer and parser complete. bytecode compiler + VM next.

### what exists
- `src/pipeline/token.zig` - all PHP 8.x token types (145 variants), case-insensitive keyword lookup via StaticStringMap, Token struct with u32 start/end byte offsets
- `src/pipeline/lexer.zig` - full PHP lexer with HTML/PHP modal lexing, comprehensive tests (42 tests)
- `src/pipeline/ast.zig` - AST node definitions. flat array design: nodes stored contiguously with u32 indices, extra_data array for variable-length children. 35 node tags covering literals, operators, control flow, functions, arrays, property access
- `src/pipeline/parser.zig` - Pratt-based recursive descent parser with 52 tests. handles full PHP operator precedence (19 levels), all assignment operators, short-circuit ops, ternary (including short form), postfix chains (calls, indexing, property access), function declarations, control flow (if/elseif/else, while, do-while, for, foreach), array literals, mixed HTML/PHP, error recovery
- `src/main.zig` - CLI entry point, imports pipeline modules for test discovery

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

### next up
- bytecode compiler (AST -> bytecode chunks)
- VM interpreter (execute bytecode)
- start with: arithmetic, variables, echo, function calls, if/while

## self-improvement

keep this CLAUDE.md up to date. after making changes, review and update: architecture notes, design decisions, gotchas, anything the next session needs to know. this is not optional.
