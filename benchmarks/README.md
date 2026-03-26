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
| array_ops | 103 ms | 30 ms | 0.29x |
| objects | 102 ms | 36 ms | 0.35x |
| fibonacci | 162 ms | 149 ms | 0.92x |
| string_ops | 99 ms | 104 ms | 1.05x |
| closures | 99 ms | 131 ms | 1.32x |
| loops | 132 ms | 187 ms | 1.42x |

zphp beats PHP on two benchmarks. Array operations are 3.3x faster thanks to O(1) integer key lookups on sequential arrays. Objects are 2.7x faster with property slot indices and IC-cached slot access. Fibonacci wins via stack-allocated locals and inline call/return. String operations are within 1.1x thanks to growable concat_assign buffers on the InlineCache (amortized O(1) append instead of O(n) realloc per iteration). Closures are within 1.4x - closure calls go through runLoop (not the fast interpreter) due to captures and call_indirect dispatch. Loops are within 1.4x - the gap is raw dispatch overhead (PHP uses computed goto, zphp uses a switch-based fast interpreter).

### Optimization targets

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
