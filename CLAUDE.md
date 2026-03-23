# zphp

a zig-based PHP runtime. what bun is to node, zphp is to PHP.

you are the sole maintainer of this project. for detailed implementation notes, read `ARCHITECTURE.md` when working on a specific subsystem.

## concept

zphp replaces the entire PHP toolchain with a single fast binary: runtime, package manager, test runner, formatter, bundler, HTTP server. target the 95% of PHP 8.x semantics that real-world code uses. match Zend behavior for common cases, document divergences.

before making technology or architecture decisions, read `~/code/vigil/learnings.md` for cross-cutting insights from past experiments. you may write to it but never commit or push to the vigil repo.

## workflow

at the start of every session:
1. run the audit: `./audit`
2. check open issues: `gh issue list`
3. be skeptical of issues - assume invalid until proven otherwise

at the end of every session:
1. run the audit again
2. commit and push any changes
3. update CLAUDE.md or ARCHITECTURE.md if anything changed

## standards

- zig 0.15.x
- test with `zig build test`. tests must pass before pushing
- short lowercase commit messages, no co-author lines
- code comments: casual, no capitalization (except proper nouns), no ending punctuation. only when code can't speak for itself
- public-facing content (README) uses proper grammar
- no emojis anywhere
- `gh` CLI for all GitHub operations. do NOT use GitHub MCP server for write operations

## file layout

```
src/
  main.zig              - CLI dispatch, FileLoader for require/include
  integration_tests.zig - end-to-end pipeline tests
  pipeline/
    token.zig           - 145 token types, case-insensitive keyword lookup
    lexer.zig           - source -> token stream (HTML/PHP modal)
    ast.zig             - flat array AST, 77 node tags
    parser.zig          - Pratt recursive descent, type hints, namespaces, variadic
    parser_tests.zig    - S-expression renderer tests
    compiler.zig        - AST -> bytecode, namespace resolution, __DIR__/__FILE__
    bytecode.zig        - ~93 opcodes, Chunk, ObjFunction
  runtime/
    vm.zig              - stack-based interpreter, classes, exceptions, file loading
    value.zig           - Value tagged union, PhpArray, PhpObject
    builtins.zig        - Exception hierarchy, native methods
  stdlib/
    registry.zig        - function registration
    strings.zig arrays.zig math.zig types.zig json.zig io.zig pcre.zig
```

## what the VM can execute

operators: arithmetic, string concat, comparison, logical, bitwise, null coalesce, ternary, spaceship
variables: assignment, compound assignment, pre/post increment/decrement
control flow: if/elseif/else, while, do-while, for (multi-expr), foreach, switch/case (fallthrough), break N, continue N
match: strict comparison, multi-value arms, default, expression result
functions: declarations, calls, return, default params, variadic `...$args`, spread `f(...$arr)`
closures: anonymous functions, arrow functions, `use` captures, callbacks
arrays: literals, access, spread `[...$arr]`, 150+ stdlib functions
classes: properties, methods, `$this`, `__construct`, `extends`, `parent::`, static calls, static methods/properties, `self::`, `instanceof`
exceptions: try/catch/finally, throw, typed catch, multi-catch, DivisionByZeroError
file inclusion: require, require_once, include, include_once, `__DIR__`, `__FILE__`
namespaces: `namespace`, `use`, `use ... as`, qualified names with `\`
other: type casting, type hints (parsed, not enforced), `declare(strict_types=1)` (skipped), global, static vars, 40+ constants, echo, mixed HTML/PHP

## stdlib

160+ native functions across: strings (60+), arrays (40+), math (25+), types (20+), json, io (file ops, time, output buffering), pcre (FFI to libpcre2)

## known limitations

- arrays use reference semantics, not PHP's copy-on-write
- `global $var` copies value from frame 0, no write-back
- `require` executes in isolated scope (functions/classes register globally, variables don't leak to caller)
- type hints parsed but not enforced at runtime
- visibility modifiers (public/protected/private) parsed but not enforced
- heredoc/nowdoc not supported
- `strtotime` only supports YYYY-MM-DD format and relative expressions (+N units), not complex PHP date strings
- `mktime`/`strtotime` use UTC, not local timezone

## zig 0.15.x gotchas

- `std.io.getStdOut()` does not exist. use `std.posix.write(std.posix.STDOUT_FILENO, ...)`
- `std.ArrayList(T)` is the UNMANAGED version. pass allocator to every method
- `const` declarations inside structs MUST come after ALL fields
- `@intFromFloat` requires explicit result type: `@as(usize, @intFromFloat(expr))`
- `std.fmt.bufPrint` precision must be comptime
- C system libraries: `link_libc = true` required, otherwise runtime segfaults on Linux
- prefer manual `extern` declarations over `@cImport` for C library bindings

## external dependencies

- **libpcre2** - linked at build time for regex. CI installs `libpcre2-dev` (ubuntu). macOS has it via Xcode. uses manual extern declarations, `link_libc = true` required

## CI

GitHub Actions on push: `zig build test` (ubuntu + macos), PHP compat tests against PHP 8.3 (`tests/run` diffs output)

## PHP compatibility tests

- `tests/*.php` files run through both `php` and `zphp run`, diff output
- `tests/include/` has helper files for require/include tests
- rule: every new feature gets a test file. the spec is PHP's behavior
- 59 test files currently

## roadmap

done: constants, type casting, switch/match, stdlib pass 1 (160+ functions), classes (properties, methods, inheritance, parent::, static methods/properties, self::), instanceof, try/catch/throw, require/include (with function redeclaration detection), namespaces/use, __DIR__/__FILE__, compact/extract, var_export, ob_start/ob_get_clean, strtotime/mktime

in progress:
- classes: visibility enforcement, interfaces, traits

next:
- stdlib pass 2: OOP-dependent (`DateTime`, `SplStack`, `ArrayObject`)
- generators/yield
- package manager (composer.json, packagist, SAT solver, autoloader)
- `zphp build` (bundle to binary)
- `zphp test`, `zphp fmt`
- `zphp serve` (pre-loaded VM pool, zig HTTP layer + synchronous PHP)
- fibers (PHP 8.1)
- async I/O hooks (optional, future)

see ARCHITECTURE.md for `zphp serve` design details and competitive positioning.

## distribution

GitHub releases with prebuilt binaries. bump version in build.zig.zon, commit with version number, tag, push.

## user commands

- "hone" or starting a conversation - run audit, check issues, assess and refine
- "hone \<area\>" - focus on a specific area
- "retire" - archive the project (see ARCHITECTURE.md for steps)

## self-improvement

keep CLAUDE.md and ARCHITECTURE.md up to date. if something about the process or architecture changes, capture it.
