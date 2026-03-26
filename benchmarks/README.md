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
| array_ops | 95 ms | 27 ms | 0.28x |
| string_ops | 95 ms | 28 ms | 0.29x |
| objects | 102 ms | 34 ms | 0.33x |
| closures | 102 ms | 82 ms | 0.80x |
| loops | 132 ms | 122 ms | 0.92x |
| fibonacci | 160 ms | 152 ms | 0.95x |

zphp beats PHP on all six benchmarks. Array operations are 3.5x faster thanks to O(1) integer key lookups on sequential arrays. String operations are 3.4x faster after adding concat (string+string, string+int, int+string) to fastLoop - the concat loop stays in the fast tier instead of bailing to runLoop on every iteration, and the growable concat_assign buffer avoids O(n) reallocation per append. Objects are 3x faster with property slot indices and IC-cached slot access. Closures beat PHP via indexed capture lookup (HashMap by closure name instead of linear scan) and fastLoop handling of call_indirect for closures. Loops beat PHP thanks to superinstructions (inc_local, add_local_to_local, less_local_local_jif) that fuse common opcode sequences in hot loops. Fibonacci wins via stack-allocated locals and inline call/return.

### Optimization targets

- **Computed goto dispatch**: replace switch-based opcode dispatch with computed goto (general improvement across all benchmarks)

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
