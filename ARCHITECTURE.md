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
- heredocs/nowdocs not yet supported (will produce invalid token)
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
- visibility modifiers parsed and skipped - not enforced yet

### exception handling
- handler stack of 32 `ExceptionHandler` structs (catch_ip, frame_count, sp, chunk)
- `throw`: unwinds frames, restores sp, pushes exception, jumps to catch_ip
- catch uses `instance_check` which walks parent chain
- `throwBuiltinException(class_name, message)` helper creates and throws from opcode handlers
- exception hierarchy: Exception, RuntimeException, InvalidArgumentException, LogicException, BadMethodCallException, OverflowException, TypeError, ArithmeticError, DivisionByZeroError, and more

### file loading (require/include)
- `FileLoader` function pointer on VM: `fn(path, allocator) ?*CompileResult`
- `require` opcode: pops path, calls loader, registers functions/classes, executes via `runUntilFrame`
- source buffers transferred to CompileResult's `string_allocs` (bytecode references source slices)
- `loaded_files` hashmap for `_once` dedup
- loaded files execute in isolated scope (known limitation: variables don't leak to caller)

### scoping
- `global $var`: `get_global` copies from frame 0. no write-back yet
- `static $var = default`: `get_static`/`set_static` with `func_name::var_name` keyed storage. `writebackStatics()` on frame return

## gotchas

- **dangling pointers in constant pool**: any string stored in the constant pool must be either a source slice or a heap allocation tracked by string_allocs. stack-allocated bufPrint strings cause use-after-free
- **loaded file source lifetime**: source buffers for required files must stay alive because compiled bytecode references slices into them. transfer ownership via string_allocs
- **float precision**: PHP uses 14 significant digits. zig's `{d}` prints full precision (~17). compute precision as `14 - digits_before_decimal`, use comptime dispatch table

## competitive positioning

every existing PHP performance project (PHP-FPM, Swoole, Workerman, FrankenPHP, RoadRunner) orbits the Zend engine. none replace it. zphp is the only project that replaces Zend entirely - the bun analogy.

unique differentiators:
- toolchain unification (run/install/test/fmt/build/serve in one binary)
- compile to standalone binary (`zphp build`)
- zero C dependencies in distributed binary
- `zphp serve` with pre-loaded VM (no IPC/serialization overhead)
- fresh memory model (zig allocators, tagged union values)

## zphp serve architecture (future)

two layers: zig HTTP layer (async, epoll/kqueue/io_uring) + PHP VM layer (synchronous per-request). compile once, spawn N worker threads sharing bytecode. each request gets clean scope. no re-parsing, no bootstrap cost. worker count configurable (default: CPU cores).
