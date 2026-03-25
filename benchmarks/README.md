# benchmarks

## runtime

Six benchmarks comparing zphp vs PHP on compute-heavy tasks. Each runs both runtimes and reports best of 5.

```
zig build -Doptimize=ReleaseFast
./benchmarks/runtime/run
```

Requires PHP installed locally. zphp must be built with ReleaseFast - debug builds are 30-50x slower due to safety checks.

- **fibonacci** - recursive fib(32), tests function call overhead
- **loops** - tight integer arithmetic, nested loops with conditionals
- **closures** - closure creation, captures, higher-order composition
- **objects** - class instantiation, method calls, property access
- **array_ops** - array building, filtering, mapping via loops
- **string_ops** - string concatenation in loop, substr_count, str_replace, explode/implode

### Results (Apple M4, PHP 8.5 no JIT, zphp ReleaseFast)

| benchmark | php | zphp | ratio |
|---|---|---|---|
| array_ops | 98 ms | 34 ms | 0.35x |
| objects | 100 ms | 39 ms | 0.39x |
| fibonacci | 167 ms | 152 ms | 0.91x |
| closures | 100 ms | 135 ms | 1.35x |
| loops | 130 ms | 190 ms | 1.46x |
| string_ops | 97 ms | 2,382 ms | 24.6x |

zphp beats PHP on three benchmarks. Array operations are 3x faster thanks to O(1) integer key lookups on sequential arrays. Objects are 2.5x faster with property slot indices and IC-cached slot access. Fibonacci wins via stack-allocated locals and inline call/return in the fast interpreter. Closures and loops are within 1.5x. String concatenation remains the outlier at 25x due to O(n) allocation per append (PHP uses mutable string buffers with realloc).

### Optimization history

The object benchmark went through several optimization stages:

1. **Baseline** (hashmap vars, switch dispatch): ~7.6x slower than PHP
2. **Stack-allocated locals** (locals_buf on InlineCache): eliminated heap alloc/free per call
3. **Inline call/return in fastLoop**: kept recursion trees in one zig function
4. **Closure locals-only**: bypassed vars hashmap for closures (535ms -> 124ms for closures benchmark)
5. **Method locals-only + IC method cache**: stack-allocated locals for methods with $this in slot 0
6. **Property slot indices**: replaced hashmap property access with flat array indexed by slot position. ClassDef builds a SlotLayout at declaration time (ordered property names + defaults). PhpObject stores a `slots: []Value` array. PropIC caches the slot index - after first access, get_prop/set_prop become `obj.slots[cached_index]` (one array access, zero hashmap lookups)
7. **FastLoop get_prop/set_prop/method_call/new_obj**: added property access, method dispatch, and object creation to the fast interpreter so method bodies stay in the tight dispatch loop instead of bouncing back to runLoop
8. **FastLoop constructor execution**: new_obj uses fastLoop for locals-only constructors, avoiding hashmap allocation for $this and params
9. **Slot-based object initialization**: initObjectProperties uses memcpy of defaults into the slots array instead of N hashmap puts

The key insight: the IC key alignment between runLoop and fastLoop was critical. Both must use the same IP-based key (position after opcode byte) for IC entries to be shared. Without this, the IC populated by runLoop's set_prop (in the constructor) would never be hit by fastLoop's get_prop (in method bodies), negating the entire slot optimization.

### Remaining optimization targets

- **Mutable string buffers**: use growable buffers for `.=` instead of allocating a new string each time (would fix string_ops)
- **Computed goto dispatch**: replace switch-based opcode dispatch with computed goto (general improvement for loops)

## fmt

Formats `sample.php` (416 lines) with each tool, reports best of 10 runs.

```
./benchmarks/fmt
```

Requires `zig build` first. Installs prettier locally if node/npm is available. Skips php-cs-fixer if php is not installed (use `./php` docker wrapper to run it manually).

### Results (Apple M4)

| tool | best of 10 |
|---|---|
| zphp fmt | 5 ms |
| php-cs-fixer (PSR-12) | 92 ms |
| prettier @prettier/plugin-php | 95 ms |
