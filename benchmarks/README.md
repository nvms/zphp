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
| string_ops | 97 ms | 27 ms | 0.28x |
| array_ops | 98 ms | 29 ms | 0.30x |
| objects | 97 ms | 36 ms | 0.37x |
| closures | 98 ms | 83 ms | 0.85x |
| fibonacci | 161 ms | 157 ms | 0.97x |
| loops | 130 ms | 120 ms | 0.92x |

zphp beats PHP on all six benchmarks. Array operations are 3.4x faster thanks to O(1) integer key lookups on sequential arrays. String operations are 3.6x faster with concat (string+string, string+int, int+string) in fastLoop - the concat loop stays in the fast tier instead of bailing to runLoop on every iteration, and the growable concat_assign buffer avoids O(n) reallocation per append. Objects are 2.7x faster with property slot indices and IC-cached slot access. Closures beat PHP via indexed capture lookup (HashMap by closure name instead of linear scan) and fastLoop handling of call_indirect for closures.

Fibonacci and loops recovered from a previous LLVM codegen perturbation regression by compiling fastLoop as a separate object file (src/fast_loop.zig). When fastLoop lived in the same compilation unit as runLoop (~2300 lines, ~100 opcodes), LLVM's optimizer made suboptimal codegen decisions for fastLoop's hot path. Separate compilation units isolate the two functions so LLVM optimizes each independently.

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
