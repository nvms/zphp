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
| string_ops | 97 ms | 24 ms | 0.25x |
| array_ops | 95 ms | 29 ms | 0.31x |
| objects | 99 ms | 34 ms | 0.34x |
| closures | 100 ms | 89 ms | 0.89x |
| fibonacci | 162 ms | 148 ms | 0.91x |
| loops | 129 ms | 127 ms | 0.98x |

zphp beats PHP on all six benchmarks. Array operations are 3.3x faster thanks to O(1) integer key lookups on sequential arrays. String operations are 4x faster after adding concat (string+string, string+int, int+string) to fastLoop - the concat loop stays in the fast tier instead of bailing to runLoop on every iteration, and the growable concat_assign buffer avoids O(n) reallocation per append. Objects are 3x faster with property slot indices and IC-cached slot access. Closures beat PHP via indexed capture lookup (HashMap by closure name instead of linear scan) and fastLoop handling of call_indirect for closures. Loops and fibonacci benefit from labeled switch dispatch in fastLoop - each opcode handler jumps directly to the next via `continue :dispatch`, eliminating the while loop overhead and giving the CPU branch predictor per-handler context. Superinstructions (inc_local, add_local_to_local, less_local_local_jif) fuse common opcode sequences in hot loops.

### Optimization targets

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
