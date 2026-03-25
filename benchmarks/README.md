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
- **string_ops** - concatenation, substr_count, str_replace, explode/implode

### Results (Apple M4, PHP 8.5 no JIT, zphp ReleaseFast)

| benchmark | php | zphp | ratio |
|---|---|---|---|
| closures | 106 ms | 628 ms | 5.9x |
| fibonacci | 171 ms | 1,283 ms | 7.5x |
| loops | 133 ms | 1,086 ms | 8.2x |
| objects | 104 ms | 3,043 ms | 29x |
| array_ops | 103 ms | 3,374 ms | 33x |
| string_ops | 100 ms | 4,449 ms | 44x |

Pure computation (closures, fibonacci, loops) is 6-8x slower - expected for a young bytecode interpreter vs PHP's 30-year-optimized engine. Array/object/string operations are slower due to PhpArray's linear key lookup and string allocation patterns - clear optimization targets.

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
