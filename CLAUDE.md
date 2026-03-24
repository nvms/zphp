# zphp

a zig-based PHP runtime. what bun is to node, zphp is to PHP.

you are the sole maintainer. read `ARCHITECTURE.md` for implementation details per subsystem. read `~/code/vigil/learnings.md` before technology decisions (don't commit/push to vigil repo).

## workflow

session start: `./audit`, `gh issue list` (be skeptical of issues)
session end: audit again, commit, push, update CLAUDE.md/ARCHITECTURE.md if needed

## standards

zig 0.15.x. `zig build test` must pass before pushing. short lowercase commits, no co-author. no emojis. casual comments only when code can't speak for itself. `gh` CLI for GitHub ops.

## known limitations

- arrays: reference semantics, not copy-on-write
- `global $var`: write-back works for simple cases, but no true reference semantics (arrays modified in-place via reference won't propagate)
- `require`: isolated scope (functions/classes global, variables don't leak)
- type hints: parsed, not enforced. heredoc/nowdoc: supported
- `strtotime`: YYYY-MM-DD and relative only, UTC
- trait conflict resolution (`insteadof`/`as`): not implemented
- pass-by-reference: works for simple variable args only, not expressions or nested access. bytecode scan approach is best-effort
- named arguments: works for user-defined functions, not native functions
- constructor property promotion: works, but `readonly` keyword is parsed and ignored (not enforced)

## gotchas

**runtime errors**: use `throwBuiltinException` + `continue` for catchable errors, NOT `return error.RuntimeError` (bypasses PHP exception handlers, causes hangs in try/catch). pattern: `if (try self.throwBuiltinException("Error", msg)) continue; return error.RuntimeError;`

**generators**: yield/generator_return opcodes must `return` from runLoop, not `continue` (continue re-enters the loop instead of exiting to the caller)

**fibers**: suspension uses `error.RuntimeError` + `fiber_suspend_pending` flag. the error propagates through all `try` calls in runLoop back to `executeFiber`. `handler_floor` prevents fiber exceptions from leaking into caller exception handlers. `Fiber.RefBinding` is the canonical definition - VM's `RefBinding` aliases it

**catch clauses**: must use `parseQualifiedName()` for types - `\Exception` starts with backslash, not identifier

**visibility**: `findPropertyVisibility`/`findMethodVisibility` return the defining class, not just visibility level. private checks against defining class, not object's runtime class

**stdlib conflicts**: functions registered later in registry.zig overwrite earlier ones. check existing stubs before adding implementations

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

7 jobs: `zig build test` (ubuntu + macos), serve integration (`tests/serve_test`, 42 assertions), test runner (`tests/test_runner_test`, 15 assertions), packages (`tests/pkg_test`, 10 assertions), fmt (`tests/fmt_test`, 29 assertions), PHP compat (`tests/run`, validated against PHP 8.4)

## sessions

`src/stdlib/session.zig`. file-based sessions in `/tmp/sess_<id>`. `session_start()` reads PHPSESSID cookie, loads session file, populates `$_SESSION` in frame 0 vars. `finalizeSession()` called from serve after PHP execution to persist `$_SESSION` back to file. simple null-delimited key/value serialization format. `session_id()`, `session_destroy()`, `session_regenerate_id()`, `session_name()`, `session_status()`, `session_write_close()`, `session_unset()` all implemented. Set-Cookie header emitted for new sessions via `__response_headers` pattern.

## roadmap

next: pdo_mysql driver

## websocket

`src/websocket.zig` (protocol) + `src/stdlib/websocket.zig` (PHP class). convention-based: if compiled script defines `ws_onMessage`, WebSocket upgrade is enabled. PHP API: `ws_onOpen($ws)`, `ws_onMessage($ws, $data)`, `ws_onClose($ws)`. `$ws` is a `WebSocketConnection` object with `send($data)` and `close()` methods. VM persists across connection lifetime - state survives between messages without external storage. poll-based event loop multiplexes many connections per worker (HTTP + WebSocket concurrently). all WS connections on a worker share one VM (Node.js model). `tryParseFrame()` provides buffer-based non-blocking frame parsing. protocol: RFC 6455 handshake (SHA-1 + base64 via zig std), frame codec (text/binary/ping/pong/close, client masking, variable-length payloads up to 1MB). message strings tracked in vm.strings for cleanup.

## gzip compression

`src/serve.zig`. uses zlib C FFI (`@cImport(@cInclude("zlib.h"))`) with `deflateInit2` in gzip mode (windowBits 15+16). compresses both static files and PHP output when client sends `Accept-Encoding: gzip`. only compresses text-based MIME types (text/*, application/javascript, application/json, application/xml, image/svg+xml). static files capped at 1MB for in-memory compression - larger files served uncompressed via streaming. adds `Content-Encoding: gzip` and `Vary: Accept-Encoding` headers. skips compression when result would be larger than original. `gzipCompress()` allocates with `compressBound`, resizes to actual compressed size before returning.

## PDO

`src/stdlib/pdo.zig`. SQLite driver via C FFI (extern declarations for sqlite3 API, opaque types for db/stmt handles). PDO and PDOStatement classes registered in vm.init(). C pointers stored as i64 in hidden properties (`__db_ptr`, `__stmt_ptr`) via `@intFromPtr`/`@ptrFromInt`. PDO methods: `__construct(dsn)`, `exec(sql)`, `query(sql)`, `prepare(sql)`, `lastInsertId()`, `beginTransaction()`, `commit()`, `rollBack()`, `errorInfo()`. PDOStatement methods: `execute(params?)`, `fetch(mode?)`, `fetchAll(mode?)`, `fetchColumn(col?)`, `rowCount()`, `columnCount()`, `closeCursor()`. supports FETCH_ASSOC, FETCH_NUM, FETCH_BOTH (default). parameter binding: positional (`?`) and named (`:name`). `cleanupResources()` called from vm.reset()/deinit() - finalizes statements before closing databases. DSN format: `sqlite:/path` or `sqlite::memory:`. null-terminated strings for C API via `allocator.dupeZ` tracked in ctx.strings. PDO constants (FETCH_ASSOC, FETCH_NUM, etc.) registered as static props on ClassDef. errors throw PDOException.

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

## local php

`./php` runs PHP 8.4 in a docker container (php:8.4-cli + php-cs-fixer). builds the image on first use. use for running php-compat tests locally and benchmarks. `./php php tests/arithmetic.php`, `./php php-cs-fixer fix file.php --rules=@PSR12 --dry-run`.

## distribution

GitHub releases with prebuilt binaries. bump version in build.zig.zon, commit with version number, tag, push.

## user commands

- "hone" or starting a conversation - run audit, check issues, assess and refine
- "hone \<area\>" - focus on a specific area
- "retire" - archive the project (see ARCHITECTURE.md for steps)
