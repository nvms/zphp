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
| array_ops | 95 ms | 43 ms | 0.45x |
| objects | 99 ms | 266 ms | 2.69x |
| closures | 103 ms | 535 ms | 5.19x |
| fibonacci | 159 ms | 1,207 ms | 7.59x |
| loops | 129 ms | 1,057 ms | 8.19x |
| string_ops | 93 ms | 2,948 ms | 31.7x |

Array operations are 2x faster than PHP thanks to O(1) integer key lookups on sequential arrays. Object operations are competitive at 2.7x. Pure computation (fibonacci, loops) is 7-8x slower due to variable access via HashMap (PHP uses fixed-slot arrays) and switch-based dispatch (PHP uses computed goto). String concatenation in loops (`$s .= expr`) is the worst at 31x due to O(n) allocation per append (PHP uses mutable string buffers with realloc).

### Optimization roadmap

- **Variable slots**: replace HashMap variable lookups with indexed array access (would improve fibonacci/loops/closures)
- **Mutable string buffers**: use growable buffers for `.=` instead of allocating a new string each time (would fix string_ops)
- **Computed goto dispatch**: replace switch-based opcode dispatch with computed goto (general ~2x improvement)

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
