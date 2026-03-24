# zphp architecture reference

detailed implementation notes for each subsystem. read the relevant section when working on that area. this file supplements CLAUDE.md which has the high-level overview.

## layering model

strict downward-only dependency between layers. no layer reaches up.

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
- **tools <-> runtime**: tools are independent consumers. the package manager doesn't know about the formatter

## design principles

**module boundaries are load-bearing.** every directory boundary represents a real abstraction boundary. files within a directory may freely import each other. files across directories import only through the directory's public interface.

**data flows down, never up.** the lexer produces tokens. the parser consumes tokens and produces AST. the compiler consumes AST and produces bytecode. the VM consumes bytecode and produces side effects. no step reaches back.

**runtime types are value types, not objects.** PHP Value, String, Array, Object - these are zig structs with well-defined memory layouts. no inheritance, no vtables. polymorphism happens at the Value level (tagged union dispatch).

**stdlib functions are registered, not hardcoded.** the VM has a function registry. stdlib modules register themselves during initialization. a stdlib function receives a slice of Value args and returns a Value - it never touches VM internals.

## key type decisions

**value representation:** tagged union. PHP values are dynamically typed. the zig implementation uses a compact tagged union that fits in 16 bytes for small values (null, bool, int, float, short strings) and heap-allocates for larger ones.

**arrays:** PHP arrays are ordered hashmaps that preserve insertion order and support both integer and string keys. currently linear scan for lookups (O(n), correct for small arrays, optimize later). arrays are reference-semantics (pointer-based) - this diverges from PHP's copy-on-write semantics but is correct for most code.

**strings:** binary-safe (can contain null bytes). PHP strings are not UTF-8 - they're byte sequences. zphp matches this behavior.

**parser strategy:** recursive descent, hand-written for speed and error quality. Pratt parser for expressions with infixPrec() mapping token tags to precedence levels 1-19.

## lexer details

- tokens reference byte offsets into source (zero-copy, no allocations)
- PHP keywords are case-insensitive (lowercased before lookup)
- strings are lexed as single tokens (interpolation handled later by compiler)
- heredoc (`<<<EOT`) and nowdoc (`<<<'EOT'`) supported. lexer produces `.heredoc`/`.nowdoc` token tags spanning full delimiter block
- the lexer never errors - invalid input produces `.invalid` tokens
- HTML mode scans for `<?php` (with trailing whitespace) and `<?=` only, no short open tags

## parser details

- flat AST: nodes in a contiguous array, children referenced by u32 index. extra_data array for variable-length children
- root node always at index 0. lhs/rhs = 0 means "no child" for optional fields
- short-circuit ops (&&, ||, ??, and, or) get dedicated AST tags for distinct codegen. regular binary ops share a single binary_op tag
- `elseif` is parsed as nested if_else in the else branch
- function params support type hints (skipped via `skipTypeHint()`), default values (lhs), and variadic (rhs=1)
- `skipTypeHint()` handles: simple, nullable, union, intersection, DNF types
- `parseQualifiedName()` consumes `identifier(\identifier)*` for namespace paths
- error recovery: on parse error, skip to next `;`, `}`, or statement keyword and continue
- S-expression renderer in parser_tests.zig makes tests compact and readable

## compiler details

- single-pass AST walk: compileNode() dispatches on node tag, emits bytecodes
- variables use `get_var`/`set_var` with string name constants (hash map lookup at runtime, not stack slots)
- jump patching: emit placeholder u16, record offset, patch when target is known
- control flow: `jump_if_false`/`jump_if_true` peek (don't pop) the condition. explicit `pop` on each path
- functions: compiled as separate Chunks via sub-compiler. VM pre-registers all functions before execution (implicit hoisting)
- string interpolation: double-quoted strings split into segments at compile time, joined with concat ops
- numeric literals: custom parser handles hex (0x), binary (0b), octal (0o), and underscore separators
- `evalConstExpr()` evaluates literal defaults at compile time (int, float, string, bool, null, negated literals)
- namespace tracking: `self.namespace` and `use_aliases` hashmap. `resolveClassName` checks fully-qualified, aliases, then namespace prefix
- `__DIR__`/`__FILE__` resolved at compile time in `compileGetVar`
- `compileWithPath(ast, allocator, file_path)` passes file path for magic constants

### switch/match compilation
- switch uses a hidden temp variable (`__switch_N`) to store the subject
- two-phase layout: phase 1 emits comparison chain, phase 2 emits all bodies sequentially (enables fallthrough)
- match uses same temp var approach but with strict comparison. no fallthrough. match is an expression

### closure architecture
- closures compiled as named functions with generated names (`__closure_0`, etc.)
- `call_indirect` opcode: pops function name string from stack, looks up and calls
- `callByName` re-enters the execution loop via `runUntilFrame(base_frame)`
- `runLoop(base_frame)` is the single execution loop
- arrow functions desugared to `closure_expr` with a synthetic block
- `use` clause captures by value. `closure_bind` opcode stores captures keyed by closure name
- string function names also work as callbacks via `callByName`

### for loop compilation
- multi-expression init/update: `parseForExprList()` returns `expr_list` node or single expression
- `continue` uses forward-jump patching (`continue_jumps` list) to land at update expression
- `break N`/`continue N`: `loop_depth` counter, `patchBreaks()`/`patchContinues()` only patch matching depth, propagate outer jumps

## VM details

- stack-based: 256-slot value stack, 64 call frames
- per-frame variable scoping via StringHashMapUnmanaged
- output captured in ArrayListUnmanaged(u8) for testing
- PHP-correct value formatting: true->"1", false->"", null->"", floats use 14 significant digits
- string comparison: lexicographic when both strings, float comparison otherwise

### class system
- `PhpObject`: class_name + property hashmap. pointer semantics
- `ClassDef`: name, methods hashmap, instance properties list with defaults, static_props hashmap, optional parent
- methods (both static and instance) compiled as `ClassName::methodName` functions in global table
- instance property defaults compile BEFORE static property defaults, both before `class_decl` opcode (on stack)
- `new_obj`: creates PhpObject, walks parent chain for defaults, calls `__construct` via `runUntilFrame`
- `method_call`: resolveMethod walks parent chain. `$this` bound in frame vars
- `parent::` resolves relative to defining class via `currentDefiningClass()`
- `self::` resolves to defining class for both method calls and property access
- static properties stored per-class in `ClassDef.static_props`, accessed via `get_static_prop`/`set_static_prop` opcodes
- `instanceof` compiles to `instance_check` opcode which walks parent chain
- function redeclaration (via require/include) produces a PHP-compatible fatal error
- visibility enforced at runtime: private (defining class only), protected (defining class + subclasses), public (anywhere). violations throw catchable `\Error` exceptions
- interfaces: `interface_decl` opcode stores method signatures. `instanceof` checks interface chain. classes store their implements list
- traits: compiled as `TraitName::method` functions. class_decl copies trait methods to `ClassName::method`. class-defined methods take precedence over trait methods
- catch clauses support qualified names (`\Exception`), multi-catch parsed but only first type used

### generators
- generator functions detected by `containsYield` scan of the AST subtree before compilation
- `ObjFunction.is_generator` flag set at compile time. calling a generator function creates a `Generator` object instead of executing
- `Generator` struct: state (created/suspended/running/completed), func pointer, ip, vars, current_value, current_key, return_value, implicit_key
- generator is a first-class `Value` variant, not a PhpObject
- `resumeGenerator(gen, sent_value)`: saves sp, pushes frame with generator's chunk/ip/vars, runs via `runUntilFrame`, restores sp on return
- yield_value/yield_pair/generator_return opcodes `return` from runLoop (not `continue`) to properly exit the nested execution
- method_call dispatches generator methods (current, key, valid, next, send, rewind, getReturn) before the object check
- foreach iter_begin/iter_check/iter_advance detect generators via sentinel index value (-1)

### fibers
- PHP 8.1 fibers. `Fiber` struct in value.zig with state, callable, saved execution context (frames, stack, exception handlers)
- `.fiber` variant in Value union, intercepted in `new_obj`, `method_call`, `static_call`
- suspension: `Fiber::suspend()` sets `fiber_suspend_pending` flag, returns `error.RuntimeError`. error propagates through all `try` in runLoop to `executeFiber`
- `executeFiber` catches error, checks flag, calls `saveFiberState` (copies frames/stack/handlers to Fiber struct with relative offsets)
- `restoreFiberState` copies saved data back to VM, adjusts handler offsets to absolute positions
- `handler_floor` field prevents fiber exceptions from leaking into caller exception handlers
- supports deep suspension (from nested calls), multiple suspend/resume cycles, nested fibers

### exception handling
- handler stack of 32 `ExceptionHandler` structs (catch_ip, frame_count, sp, chunk)
- `handler_floor`: prevents fiber/nested exception handlers from leaking across boundaries
- `throw`: unwinds frames to handler, restores sp, pushes exception, jumps to catch_ip
- catch uses `instance_check` which walks parent chain
- `throwBuiltinException(class_name, message)` helper creates and throws from opcode handlers
- exception hierarchy: Exception, RuntimeException, InvalidArgumentException, LogicException, BadMethodCallException, OverflowException, TypeError, ArithmeticError, DivisionByZeroError, FiberError, PDOException, and more

### file loading (require/include)
- `FileLoader` function pointer on VM: `fn(path, allocator) ?*CompileResult`
- `require` opcode: pops path, calls loader, registers functions/classes, executes via `runUntilFrame`
- source buffers transferred to CompileResult's `string_allocs` (bytecode references source slices)
- `loaded_files` hashmap for `_once` dedup
- loaded files execute in isolated scope (known limitation: variables don't leak to caller)

### scoping
- `global $var`: `get_global` copies from frame 0. no write-back yet
- `static $var = default`: `get_static`/`set_static` with `func_name::var_name` keyed storage. `writebackStatics()` on frame return

### SPL classes (src/stdlib/spl.zig)
- `SplStack`: LIFO stack backed by PhpArray in hidden `__data` property. push/pop operate on end of array. iterator goes top-to-bottom (cursor starts at len-1, decrements). implements Countable
- `ArrayObject`: object wrapper around PhpArray. stores data in `__data`, flags in `__flags`. implements Countable. offsetGet/offsetSet/offsetExists/offsetUnset for explicit access. getArrayCopy returns a shallow copy. bracket syntax (`$ao["key"]`) not yet supported (requires VM-level ArrayAccess dispatch)
- both registered during VM init alongside builtins and datetime

### PDO (src/stdlib/pdo.zig)
- SQLite driver via C FFI (opaque types for `sqlite3*` and `sqlite3_stmt*`, extern declarations for ~20 sqlite3 functions)
- PDO and PDOStatement classes registered in vm.init(). C pointers stored as i64 in hidden properties (`__db_ptr`, `__stmt_ptr`) via `@intFromPtr`/`@ptrFromInt`
- null-terminated strings for C API via `allocator.dupeZ` tracked in ctx.strings
- parameter binding: positional (`?`, 1-indexed in SQLite) and named (`:name`). int keys map to position+1, string keys resolved via `sqlite3_bind_parameter_index`
- column type mapping: per-cell via `sqlite3_column_type`. TEXT/BLOB copied immediately via `ctx.createString` (C strings only valid until next step/finalize)
- fetch modes: FETCH_BOTH (default, both numeric and string keys), FETCH_ASSOC, FETCH_NUM. mode parameter on fetch/fetchAll
- `cleanupResources()` called from vm.reset()/deinit() - finalizes all statements before closing databases (order matters)
- PDO constants registered as static properties on ClassDef

## gotchas

- **dangling pointers in constant pool**: any string stored in the constant pool must be either a source slice or a heap allocation tracked by string_allocs. stack-allocated bufPrint strings cause use-after-free
- **loaded file source lifetime**: source buffers for required files must stay alive because compiled bytecode references slices into them. transfer ownership via string_allocs
- **float precision**: PHP uses 14 significant digits. zig's `{d}` prints full precision (~17). compute precision as `14 - digits_before_decimal`, use comptime dispatch table

## competitive positioning

every existing PHP performance project (PHP-FPM, Swoole, Workerman, FrankenPHP, RoadRunner) orbits the Zend engine. none replace it. zphp is the only project that replaces Zend entirely - the bun analogy.

unique differentiators:
- toolchain unification (run/install/test/fmt/build/serve in one binary)
- compile to standalone binary (`zphp build`)
- minimal C dependencies (PCRE2 for regex, SQLite3 for PDO, zlib for gzip compression)
- `zphp serve` with pre-loaded VM (no IPC/serialization overhead)
- fresh memory model (zig allocators, tagged union values)

## zphp serve

`zphp serve <file> [--port 8080] [--workers N]`

two layers: zig HTTP layer (TCP + raw HTTP parsing) + PHP VM layer (synchronous per-request).

### how it works
1. compile the PHP script once at startup (parse -> AST -> bytecode)
2. bind TCP socket, spawn N worker threads (default: CPU core count)
3. main thread accepts connections, pushes to bounded work queue (mutex + condition variable)
4. worker threads pop connections, parse HTTP, create fresh VM, execute shared bytecode, write response

### key design decisions
- **shared bytecode**: all workers reference the same `CompileResult`. bytecode is read-only during execution, safe with no synchronization
- **VM pooling**: one VM per worker thread, created once at startup. `vm.reset()` between requests clears per-request state (output, strings, arrays, objects, generators, statics, frames) while preserving stdlib registrations, constants, class definitions
- **keep-alive**: HTTP/1.1 persistent connections. buffer tracks consumed bytes across requests. proper Content-Length-based request boundary detection for pipelined requests
- **request_vars**: superglobals populated into `vm.request_vars` before interpret. interpret copies them into frame 0
- **response headers**: `header()` stores in `__response_headers`, `http_response_code()` stores in `__response_code`
- **work queue**: bounded ring buffer (1024) with mutex + condition

### static files
- `tryServeStatic`: serves non-PHP files from document root. path traversal prevention (`..` check). ETag based on `{size_hex}-{mtime_hex}`, 304 Not Modified support. MIME type detection by extension
- gzip compression via zlib C FFI (`deflateInit2` with windowBits 15+16 for gzip format). compresses text-based MIME types (text/*, JS, JSON, XML, SVG) when client sends `Accept-Encoding: gzip`. static files up to 1MB compressed in-memory; larger files served uncompressed via 32KB streaming chunks. adds `Content-Encoding: gzip` and `Vary: Accept-Encoding`. PHP output also compressed when client accepts gzip
- `gzipCompress()` allocates with `compressBound()`, resizes to actual size, skips if compressed >= original

### websocket (src/websocket.zig + src/stdlib/websocket.zig)
- protocol layer in `src/websocket.zig`: frame codec (readFrame/writeFrame/writeCloseFrame), handshake (computeAcceptKey using `std.crypto.hash.Sha1` + `std.base64`, writeHandshakeResponse). no VM dependency - pure protocol
- PHP class in `src/stdlib/websocket.zig`: `WebSocketConnection` with `send($data)` and `close()` native methods. stream fd stored as i64 in hidden `__ws_fd` property. `__ws_closed` flag prevents double-close
- convention-based detection: after compile, scan `result.functions` for `ws_onMessage`. if found, enable upgrade handling
- connection model: worker thread per WebSocket connection. on `Upgrade: websocket`, worker enters `handleWebSocket` frame loop instead of HTTP request/response path. dedicated until connection closes
- VM lifecycle: `vm.interpret(result)` runs script once (registers functions, executes top-level code), then `ws_onOpen`/`ws_onMessage`/`ws_onClose` called via `vm.callByName`. VM NOT reset between messages - state persists across connection lifetime
- message strings allocated via `allocator.dupe`, tracked in `vm.strings` for cleanup at connection end
- frame loop handles: text/binary (dispatch to `ws_onMessage`), ping (auto-pong), close (echo close + break), pong/continuation (ignore)

### what's not yet implemented
- graceful shutdown (SIGTERM handling)
- chunked transfer encoding
- multipart form data parsing
- WebSocket protocol upgrade and frame handling

## formatter (src/fmt.zig)

opinionated PHP code formatter. parse -> AST -> pretty-print. no configuration.

### how it works
1. parse PHP source using existing parser (reuses full lexer + parser pipeline)
2. extract trivia (comments) from source gaps between tokens - the lexer strips whitespace and comments, so we recover them by scanning the byte ranges between consecutive token end/start positions
3. walk the AST recursively, emitting formatted output with proper indentation and spacing
4. insert preserved comments at their original structural positions

### style rules (opinionated, no config)
- 4 spaces indentation
- K&R brace placement (opening brace on same line)
- single space around binary/assignment operators
- single space after commas
- blank lines between top-level declarations (functions, classes)
- blank lines between class methods
- no trailing whitespace, single trailing newline
- closures and arrow functions formatted inline

### key design decisions
- **trivia extraction**: builds a trivia array parallel to the token array. for each token index, stores any comments found in the source gap before it. line comments (`//`, `#`) and block comments (`/* */`) both preserved
- **AST-driven formatting**: indentation determined by AST nesting depth, not original source. ensures consistent output regardless of input formatting
- **type hint recovery**: scans backwards from variable tokens to find type hint tokens (the parser consumes type hints but doesn't store them as AST nodes). stops at delimiter tokens (comma, l_paren) to avoid false matches
- **visibility from encoded bits**: class method visibility is packed into rhs high bits by the parser. formatter extracts and emits the correct keyword
- **idempotent**: formatting already-formatted code produces identical output. verified across all test files
