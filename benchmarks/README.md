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

### Results (Apple M4, PHP 8.5.4 no JIT, zphp ReleaseFast)

| benchmark | php | zphp | ratio |
|---|---|---|---|
| string_ops | 97 ms | 31 ms | 0.32x |
| array_ops | 95 ms | 31 ms | 0.33x |
| objects | 99 ms | 41 ms | 0.41x |
| closures | 99 ms | 93 ms | 0.94x |
| fibonacci | 163 ms | 164 ms | 1.01x |
| loops | 130 ms | 130 ms | 1.00x |

zphp beats PHP on the compute-heavy benchmarks that exercise stdlib and object dispatch. Array operations are 3.1x faster thanks to O(1) integer key lookups on sequential arrays. String operations are 3.1x faster with concat (string+string, string+int, int+string) in fastLoop - the concat loop stays in the fast tier instead of bailing to runLoop on every iteration, and the growable concat_assign buffer avoids O(n) reallocation per append. Objects are 2.4x faster with property slot indices and IC-cached slot access. Closures are a small win via indexed capture lookup (HashMap by closure name instead of linear scan) and fastLoop handling of call_indirect for closures.

Fibonacci and loops are neck-and-neck with PHP - both runtimes are limited by call overhead and tight integer arithmetic, where PHP's JIT-less interpreter is already well-tuned. fastLoop is compiled as a separate object file (src/fast_loop.zig) so LLVM can optimize it independently of runLoop; without this the two functions compete for inlining decisions and regress unpredictably.

### Optimization targets

## serve

HTTP throughput benchmark comparing `zphp serve` against nginx + php-fpm (the standard production PHP deployment). Uses [wrk](https://github.com/wg/wrk) for load generation.

```
zig build -Doptimize=ReleaseFast
./benchmarks/serve/wrk_bench [duration] [threads] [connections]
```

Defaults: 10s duration, 4 threads, 100 connections. Requires wrk. Requires Docker for the nginx + php-fpm comparison. PHP's built-in server (`php -S`) is included as a baseline but is single-threaded and not a production server.

All servers run the same file: `echo "hello"`.

### Results (Apple M4, 14 cores, wrk -t4 -c100 -d10s)

| server | req/s | avg latency |
|---|---|---|
| zphp serve | 92,343 | 1.12 ms |
| nginx + php-fpm (128 workers) | 42,088 | 50.37 ms |
| php -S (dev only) | 3,652 | 2.91 ms |

zphp is 2.2x higher throughput and 45x lower latency than nginx + php-fpm on the same trivial endpoint.

### Caveats

- nginx + php-fpm runs in Docker with linux/amd64 emulation on Apple Silicon. native Linux performance would be significantly better for php-fpm. on a real Linux x86_64 server, expect the gap to narrow
- zphp runs natively. this is representative of real deployment - zphp is a single binary with a built-in production server
- `php -S` is PHP's built-in development server. single-threaded, not intended for production. included only as a baseline
- this benchmarks I/O and dispatch overhead on a trivial endpoint. real-world PHP with database queries, template rendering, etc. would shift the bottleneck from the server to the application layer

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
