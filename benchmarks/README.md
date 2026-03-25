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
- **string_ops** - string building, substr_count, str_replace, explode/implode

### Results (Apple M4, PHP 8.5 no JIT, zphp ReleaseFast)

| benchmark | php | zphp | ratio |
|---|---|---|---|
| array_ops | 90 ms | 43 ms | 0.48x |
| string_ops | 96 ms | 110 ms | 1.15x |
| objects | 98 ms | 258 ms | 2.63x |
| closures | 100 ms | 551 ms | 5.51x |
| fibonacci | 158 ms | 1,154 ms | 7.30x |
| loops | 125 ms | 1,053 ms | 8.42x |

Array operations are 2x faster than PHP thanks to O(1) integer key lookups on sequential arrays. String and object operations are competitive. Pure computation (fibonacci, loops) is 7-8x slower - the gap between a switch-based bytecode interpreter and PHP's computed goto dispatch with 30 years of optimization. The main bottleneck is variable access: zphp uses HashMap lookups where PHP uses fixed-slot arrays.

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
