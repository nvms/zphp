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
| array_ops | 94 ms | 31 ms | 0.33x |
| objects | 103 ms | 39 ms | 0.38x |
| closures | 91 ms | 77 ms | 0.85x |
| fibonacci | 165 ms | 155 ms | 0.94x |
| loops | 134 ms | 189 ms | 1.41x |
| string_ops | 95 ms | 2,218 ms | 23.4x |

zphp beats PHP on four benchmarks. Array operations are 3x faster thanks to O(1) integer key lookups on sequential arrays. Objects are 2.6x faster with property slot indices and IC-cached slot access. Closures are 15% faster with capture-aware locals-only dispatch and inline closure calls in the fast interpreter. Fibonacci wins via stack-allocated locals and inline call/return. Loops are within 1.4x - the gap is raw dispatch overhead (PHP uses computed goto, zphp uses a switch-based fast interpreter). String concatenation remains the outlier at 23x due to O(n) allocation per append (PHP uses mutable string buffers with realloc).

### Optimization targets

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
