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
| string_ops | 94 ms | 27 ms | 0.29x |
| array_ops | 96 ms | 29 ms | 0.30x |
| objects | 93 ms | 39 ms | 0.42x |
| closures | 95 ms | 90 ms | 0.95x |
| fibonacci | 167 ms | 202 ms | 1.21x |
| loops | 128 ms | 226 ms | 1.77x |

zphp beats PHP on four of six benchmarks. Array operations are 3.3x faster thanks to O(1) integer key lookups on sequential arrays. String operations are 3.5x faster after adding concat (string+string, string+int, int+string) to fastLoop - the concat loop stays in the fast tier instead of bailing to runLoop on every iteration, and the growable concat_assign buffer avoids O(n) reallocation per append. Objects are 2.4x faster with property slot indices and IC-cached slot access. Closures beat PHP via indexed capture lookup (HashMap by closure name instead of linear scan) and fastLoop handling of call_indirect for closures.

Fibonacci and loops are currently slower than PHP due to LLVM codegen perturbation. The interpreter's hot loop produces different machine code depending on the size and layout of surrounding functions in the same compilation unit - even when the hot loop itself hasn't changed. This is a known class of issue with large switch-based interpreters on LLVM backends. Splitting the VM into separate compilation units or applying profile-guided optimization are the most promising paths to recovering performance.

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
