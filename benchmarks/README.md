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
| array_ops | 94 ms | 28 ms | 0.30x |
| objects | 101 ms | 35 ms | 0.35x |
| closures | 96 ms | 90 ms | 0.94x |
| fibonacci | 164 ms | 153 ms | 0.93x |
| loops | 130 ms | 124 ms | 0.95x |
| string_ops | 97 ms | 104 ms | 1.07x |

zphp beats PHP on five of six benchmarks. Array operations are 3.3x faster thanks to O(1) integer key lookups on sequential arrays. Objects are 2.9x faster with property slot indices and IC-cached slot access. Closures beat PHP via indexed capture lookup (HashMap by closure name instead of linear scan) and fastLoop handling of call_indirect for closures. Fibonacci wins via stack-allocated locals and inline call/return. Loops beat PHP thanks to superinstructions (inc_local, add_local_to_local, less_local_local_jif) that fuse common opcode sequences in hot loops. String operations are within 1.1x thanks to growable concat_assign buffers on the InlineCache.

### Optimization targets

- **Computed goto dispatch**: replace switch-based opcode dispatch with computed goto (general improvement, especially string_ops)

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
