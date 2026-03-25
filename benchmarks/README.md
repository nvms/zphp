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
| array_ops | 98 ms | 32 ms | 0.33x |
| objects | 102 ms | 40 ms | 0.39x |
| closures | 97 ms | 78 ms | 0.80x |
| fibonacci | 169 ms | 156 ms | 0.92x |
| string_ops | 95 ms | 115 ms | 1.21x |
| loops | 133 ms | 188 ms | 1.41x |

zphp beats PHP on four benchmarks. Array operations are 3x faster thanks to O(1) integer key lookups on sequential arrays. Objects are 2.6x faster with property slot indices and IC-cached slot access. Closures are 20% faster with capture-aware locals-only dispatch and inline closure calls in the fast interpreter. Fibonacci wins via stack-allocated locals and inline call/return. String operations are within 1.2x thanks to growable concat_assign buffers on the InlineCache (amortized O(1) append instead of O(n) realloc per iteration). Loops are within 1.4x - the gap is raw dispatch overhead (PHP uses computed goto, zphp uses a switch-based fast interpreter).

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
