# zphp

a zig-based PHP runtime. what bun is to node, zphp is to PHP.

you are the sole maintainer. read `ARCHITECTURE.md` for implementation details per subsystem. read `~/code/vigil/learnings.md` before technology decisions (don't commit/push to vigil repo).

## workflow

session start: `./audit`, `gh issue list` (be skeptical of issues)
session end: audit again, commit, push, update CLAUDE.md/ARCHITECTURE.md if needed

## standards

zig 0.15.x. `zig build test` must pass before pushing. short lowercase commits, no co-author. no emojis. casual comments only when code can't speak for itself. `gh` CLI for GitHub ops.

## known limitations

- arrays: copy-on-assign with deep clone (recursive). full value semantics at assignment, parameter, capture, and property boundaries
- `global $var`: write-back works for simple cases, but no true reference semantics (arrays modified in-place via reference won't propagate)
- `require`: isolated scope (functions/classes global, variables don't leak)
- type hints: parsed, not enforced. heredoc/nowdoc: supported
- `strtotime`: YYYY-MM-DD and relative only, UTC
- trait conflict resolution (`insteadof`/`as`): fully implemented including visibility changes
- pass-by-reference: works for simple variable args in user-defined and native functions (preg_match $matches, sort, etc.). bytecode scan approach is best-effort - expressions and nested access not supported
- named arguments: works for user-defined functions and ~80 common native functions (see `src/stdlib/native_params.zig`). unlisted natives fall back to positional
- constructor property promotion: works with readonly enforcement
- nullsafe operator (`?->`): full support for property access and method calls, including chaining

## stdlib modules

`src/stdlib/` organized by domain: `filesystem.zig` (file/path/directory ops), `http.zig` (headers, cookies, output buffering), `system.zig` (sleep, getenv, getcwd, uploads), `strings.zig`, `arrays.zig`, `math.zig`, `types.zig`, `json.zig`, `pcre.zig`, `output.zig` (var_dump/print_r), `datetime.zig`, `crypto.zig`, `serialize.zig`, `session.zig`, `testing.zig`, `spl.zig`, `pdo.zig`/`pdo_mysql.zig`/`pdo_pgsql.zig`, `enums.zig`, `exceptions.zig`, `websocket.zig`, `native_params.zig`. `registry.zig` registers all function entries.

## gotchas

**runtime errors**: use `throwBuiltinException` + `continue` for catchable errors, NOT `return error.RuntimeError` (bypasses PHP exception handlers, causes hangs in try/catch). pattern: `if (try self.throwBuiltinException("Error", msg)) continue; return error.RuntimeError;`

**generators**: yield/generator_return opcodes must `return` from runLoop, not `continue` (continue re-enters the loop instead of exiting to the caller)

**fibers**: suspension uses `error.RuntimeError` + `fiber_suspend_pending` flag. the error propagates through all `try` calls in runLoop back to `executeFiber`. `handler_floor` prevents fiber exceptions from leaking into caller exception handlers. `Fiber.RefBinding` is the canonical definition - VM's `RefBinding` aliases it

**catch clauses**: must use `parseQualifiedName()` for types - `\Exception` starts with backslash, not identifier

**visibility**: `findPropertyVisibility`/`findMethodVisibility` return the defining class, not just visibility level. private checks against defining class, not object's runtime class

**stdlib conflicts**: functions registered later in registry.zig overwrite earlier ones. check existing stubs before adding implementations

**trait method copying**: must collect trait methods into a temporary buffer before inserting into `self.functions` - iterating and mutating a HashMap simultaneously causes iterator invalidation and segfaults

**array property defaults**: `initObjectProperties` clones array values so each instance gets its own copy. without this, all instances share the same underlying PhpArray

**foreach continue**: `compileForeach` must set `use_continue_jumps = true` and patch continues before `iter_advance` - otherwise continue jumps to `iter_check`, skipping the advance and causing infinite loops

**zig 0.15.x**: no `std.io.getStdOut()` (use `std.posix.write`). `std.ArrayList(T)` is unmanaged. `const` in structs after all fields. `link_libc = true` required for C libs. `std.http.Client` uses vtable-based Writer in 0.15 - use curl via `std.process.Child.run` for HTTP instead.

## CLI

- `zphp run <file>` - execute PHP file
- `zphp serve <file> [--port N] [--workers N]` - HTTP server with pre-compiled bytecode, VM pooling, keep-alive, static files, ETag/304, gzip, WebSocket, chunked transfer encoding, multipart form data/$_FILES, graceful SIGTERM/SIGINT shutdown
- `zphp test [file]` - test runner with assertion functions, test discovery, TUI output
- `zphp install` - install packages from composer.json, write zphp.lock
- `zphp add <pkg>` / `zphp remove <pkg>` - manage dependencies
- `zphp packages` - list installed packages
- `zphp fmt <file>...` - opinionated PHP formatter (4-space indent, K&R braces, consistent spacing). overwrites in place
- `zphp fmt --check <file>...` - check formatting without modifying (exit 1 if changes needed)

## fmt

`src/fmt.zig`. parses PHP to AST using existing parser, walks AST to emit formatted output. extracts comments from source gaps between tokens (lexer strips trivia). opinionated, no configuration. style: 4-space indent, K&R brace placement, single space around operators, blank lines between declarations. preserves comments. idempotent.

## CI

9 jobs: `zig build test` (ubuntu + macos), serve integration (`tests/serve_test`, 42 assertions), test runner (`tests/test_runner_test`, 15 assertions), packages (`tests/pkg_test`, 10 assertions), fmt (`tests/fmt_test`, 29 assertions), PHP compat (`tests/run`, validated against PHP 8.4), PDO drivers (`tests/pdo_test`, mysql 8.0 + postgres 16 services), examples (`tests/examples_test`, multi-file PHP projects validated against PHP 8.4)

## sessions

`src/stdlib/session.zig`. file-based sessions in `/tmp/sess_<id>`. `session_start()` reads PHPSESSID cookie, loads session file, populates `$_SESSION` in frame 0 vars. `finalizeSession()` called from serve after PHP execution to persist `$_SESSION` back to file. simple null-delimited key/value serialization format. `session_id()`, `session_destroy()`, `session_regenerate_id()`, `session_name()`, `session_status()`, `session_write_close()`, `session_unset()` all implemented. Set-Cookie header emitted for new sessions via `__response_headers` pattern.

## build

`make build` / `make test` / `make compat` / `make examples` / `make all-tests`. the Makefile sets `PKG_CONFIG_PATH` for macOS homebrew keg-only libs (mysql-client, libpq). system deps: libpcre2-dev, libsqlite3-dev, zlib1g-dev, libmysqlclient-dev, libpq-dev (ubuntu). macOS: `brew install mysql-client libpq`.

## roadmap

1. spread operator in function calls - `foo(...$args)` argument forwarding. ubiquitous in framework code
2. first-class enum methods - enum cases calling methods on themselves (`Status::Active->label()`)
3. union type enforcement - `int|string` runtime checking at function boundaries. currently parsed but ignored
4. stdlib coverage gaps - run compat suite systematically, close missing/broken function gaps
5. match expression exhaustiveness - `match` without default should throw `UnhandledMatchError`
6. complex string interpolation - `"${expr}"` and `"{$obj->prop}"` edge cases
7. performance baseline - benchmark against PHP 8.4 on compute-heavy tasks

## websocket

`src/websocket.zig` (protocol) + `src/stdlib/websocket.zig` (PHP class). convention-based: if compiled script defines `ws_onMessage`, WebSocket upgrade is enabled. PHP API: `ws_onOpen($ws)`, `ws_onMessage($ws, $data)`, `ws_onClose($ws)`. `$ws` is a `WebSocketConnection` object with `send($data)` and `close()` methods. VM persists across connection lifetime - state survives between messages without external storage. poll-based event loop multiplexes many connections per worker (HTTP + WebSocket concurrently). all WS connections on a worker share one VM (Node.js model). `tryParseFrame()` provides buffer-based non-blocking frame parsing. protocol: RFC 6455 handshake (SHA-1 + base64 via zig std), frame codec (text/binary/ping/pong/close, client masking, variable-length payloads up to 1MB). message strings tracked in vm.strings for cleanup.

## gzip compression

`src/serve.zig`. uses zlib C FFI (`@cImport(@cInclude("zlib.h"))`) with `deflateInit2` in gzip mode (windowBits 15+16). compresses both static files and PHP output when client sends `Accept-Encoding: gzip`. only compresses text-based MIME types (text/*, application/javascript, application/json, application/xml, image/svg+xml). static files capped at 1MB for in-memory compression - larger files served uncompressed via streaming. adds `Content-Encoding: gzip` and `Vary: Accept-Encoding` headers. skips compression when result would be larger than original. `gzipCompress()` allocates with `compressBound`, resizes to actual compressed size before returning.

## PDO

three drivers: sqlite (`pdo.zig`), mysql (`pdo_mysql.zig`), pgsql (`pdo_pgsql.zig`). `pdo.zig` is the dispatch layer - reads `__driver` property from the PDO object and routes to the appropriate driver. shared utilities: `throwPdo()`, `dupeZ()`.

**sqlite**: C FFI with extern declarations for sqlite3 API. opaque types for db/stmt handles. C pointers stored as i64 in hidden properties (`__db_ptr`, `__stmt_ptr`) via `@intFromPtr`/`@ptrFromInt`. step-based row iteration.

**mysql**: C FFI with libmysqlclient. opaque MYSQL/MYSQL_RES types. `mysql_real_query` + `mysql_store_result` for queries. prepared statements use string interpolation with `mysql_real_escape_string` (not MYSQL_BIND - struct layout varies across platforms). named params rewritten from `:name` to `?`. field names accessed via `mysql_fetch_field` with opaque MYSQL_FIELD (name at offset 0). DSN: `mysql:host=X;port=3306;dbname=X`.

**pgsql**: C FFI with libpq. `PQexec` for simple queries, `PQexecParams` for parameterized queries (true server-side params). results fully materialized - row iteration via `__current_row` counter on PGresult. named params rewritten from `:name` to `$N`, positional `?` to `$N`. DSN: `pgsql:host=X;port=5432;dbname=X`, converted to libpq conninfo string.

all drivers: PDO/PDOStatement classes shared. FETCH_ASSOC/NUM/BOTH modes. positional and named parameter binding. transactions. lastInsertId (postgres uses `SELECT lastval()`). `cleanupResources()` finalizes statements then closes connections per driver.

## crypto

`src/stdlib/crypto.zig`. `password_hash`/`password_verify` use zig's `std.crypto.pwhash.bcrypt` with crypt format (`$2b$...`). `hash`/`hash_hmac` support md5, sha1, sha256, sha384, sha512, crc32. `random_bytes`/`random_int` use `std.crypto.random`. `hash_algos` returns available algorithms. constants: `PASSWORD_DEFAULT`, `PASSWORD_BCRYPT`.

## serialize

`src/stdlib/serialize.zig`. PHP serialize format for scalars, arrays, objects. `formatPhpFloat` matches PHP's `%.14G` format - scientific notation for exp < -4, decimal otherwise up to ~1e18. `unserialize` handles all types including nested structures. malformed input returns false.

## autoloading

`spl_autoload_register` stores callbacks in `vm.autoload_callbacks`. `tryAutoload` in vm.zig invoked from `new_obj` when class not found - iterates callbacks, invokes each with the class name. supports string functions and closures. `spl_autoload_unregister` removes by string match.

## enums

PHP 8.1+ enums implemented. pure enums and backed enums (int/string). cases are singleton PhpObjects stored as static props on a ClassDef with `is_enum=true`. `->name`, `->value` (backed), `::cases()`, `::from()`, `::tryFrom()` all work. enum methods compile as `EnumName::methodName`. `instanceof`, match expressions, and identity comparison (`===`) all work. `NativeContext.call_name` field lets native methods introspect which enum they're called on.

## callables

`call_user_func`/`call_user_func_array` support all PHP callable forms: strings, `[$obj, "method"]`, `["ClassName", "staticMethod"]`, closures. `NativeContext.invokeCallable(callable, args)` is the universal dispatcher. all callback-accepting array functions (array_map, array_filter, usort, array_walk, array_reduce, uasort, uksort, array_find, array_find_key, array_any, array_all) accept all callable forms. `VM.callMethod(obj, method_name, args)` is the public API for calling methods on objects with `$this` binding.

## SPL classes

`SplStack` and `ArrayObject` implemented in `src/stdlib/spl.zig`, registered in `vm.zig` init. both implement `Countable` interface. internal data stored in hidden `__data` property as PhpArray. SplStack iterates LIFO (top to bottom). SplStack methods: push, pop, top, bottom, count, isEmpty, shift, unshift, rewind, current, key, next, valid, toArray. ArrayObject methods: offsetGet, offsetSet, offsetExists, offsetUnset, count, append, getArrayCopy, getIterator, setFlags, getFlags. ArrayAccess bracket syntax (`$ao["key"]`) works - `array_get`/`array_set` opcodes detect objects with `offsetGet`/`offsetSet` methods and dispatch to them. string indexing (`$s[0]`) also works via the same opcode.

## array destructuring

`list($a, $b) = [1, 2]` and `[$a, $b] = [1, 2]` both work. `list_destructure` AST node for `list()` syntax, `array_literal` on LHS of assignment detected in compiler. supports skipped slots (`list($a, , $c)`), nested destructuring, and keyed destructuring (`["x" => $a]`). `compileDestructure` emits dup/array_get/set_var/pop sequences.

## heredoc/nowdoc

`<<<EOT ... EOT` (heredoc, interpolating) and `<<<'EOT' ... EOT` (nowdoc, no interpolation). lexer produces `.heredoc`/`.nowdoc` token tags spanning `<<<` through closing label. parser maps both to `string_literal` AST nodes. compiler extracts body via `extractHeredocBody()` - parses label from lexeme, strips delimiter lines, handles PHP 7.3+ indented closing markers (strips leading whitespace from all body lines based on closing label indentation). heredoc routes through existing escape/interpolation pipeline. nowdoc emits body as-is. closing label recognized when followed by `;`, `)`, `,`, `]`, newline, or EOF.

## first-class callable syntax

`strlen(...)` creates a callable reference. parser detects `...` as the sole argument followed by `)` in `parseCallExpr`, produces `callable_ref` AST node. compiler emits the function name as a string constant - works with `call_indirect`, `call_user_func`, `array_map`, and all callback-accepting functions since they already accept string callable names.

## named arguments

`foo(name: "value")` syntax. parser detects `identifier:` (and keyword names like `class:`) in call args, creates `named_arg` AST node. compiler builds associative array with string keys, routes through `call_spread`. VM resolves named args against `ObjFunction.params` at call time, matching `$param` names (strips leading `$`). works for user-defined functions only - native functions fall back to positional.

## pass-by-reference

`function foo(&$x)` syntax. parser stores ref flag in param node `data.rhs` bit 1. `ObjFunction.ref_params` parallel bool array tracks which params are by-ref. on call, VM scans caller bytecode backwards to find `get_var` instructions and records caller variable names as `RefBinding` entries in the `CallFrame`. `writebackRefs()` on return copies modified values back to caller's frame. best-effort: only works when the arg is a simple variable (not expressions or nested access).

## fibers

PHP 8.1 fibers. `new Fiber(callable)`, `$fiber->start(...$args)`, `$fiber->resume($value)`, `$fiber->getReturn()`, `Fiber::suspend($value)` (static), `isStarted()`/`isRunning()`/`isSuspended()`/`isTerminated()`. Fiber struct in `value.zig` stores callable, state, and saved execution context (frames with chunk/ip/vars/ref_bindings, stack values, exception handlers as relative offsets). `.fiber` variant in Value union, intercepted in `new_obj` (construction), `method_call` (instance methods), `static_call` (Fiber::suspend). suspension works by returning `error.RuntimeError` with `fiber_suspend_pending` flag - error propagates through all `try` calls in runLoop to `executeFiber`, which saves frames/stack/handlers to Fiber struct. `handler_floor` isolates fiber exception handlers from caller context. supports deep suspension (suspend from arbitrarily nested function calls), multiple suspend/resume cycles, and nested fibers.

## constructor property promotion

`__construct(public string $name, private int $age = 0)` syntax. parser stores visibility in param `data.rhs` bits 2-3 (0=none, 1=public, 2=protected, 3=private). `readonly` parsed but not enforced. compiler detects promoted params in `__construct`, emits `$this->prop = $prop` assignments before body, and adds them as class properties in the `class_decl` bytecode. constructor default params now properly filled when fewer args passed.

## examples

`examples/` directory. each subdirectory is a self-contained mini PHP application with a `main.php` entry point. `tests/examples_test` runs each against both zphp and PHP 8.4, diffs output. currently: autoloader (spl_autoload_register with __DIR__-based class loading), middleware (closure pipeline with auth/logging), oop-composition (interfaces, traits, inheritance, method chaining), pdo-models (CRUD with sqlite, repository pattern, transactions), router (URL pattern matching with array callable dispatch), service-container (DI container, singletons, bindings).

## local php

`./php` runs PHP 8.4 in a docker container (php:8.4-cli + php-cs-fixer). builds the image on first use. use for running php-compat tests locally and benchmarks. `./php php tests/arithmetic.php`, `./php php-cs-fixer fix file.php --rules=@PSR12 --dry-run`.

## distribution

GitHub releases with prebuilt binaries. bump version in build.zig.zon, commit with version number, tag, push.

## user commands

- "hone" or starting a conversation - run audit, check issues, assess and refine
- "hone \<area\>" - focus on a specific area
- "retire" - archive the project (see ARCHITECTURE.md for steps)
