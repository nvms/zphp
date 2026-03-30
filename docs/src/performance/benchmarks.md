# Benchmarks

All benchmarks run on Apple M4 (14 cores), comparing zphp (ReleaseFast) against PHP 8.5 (no JIT). Benchmarks are in the `benchmarks/` directory and can be reproduced locally.

## Runtime

Six compute-heavy benchmarks. Best of 5 runs. Startup overhead is subtracted to measure pure execution time.

| Benchmark | PHP | zphp | Ratio |
|---|---|---|---|
| string_ops | 97 ms | 27 ms | 0.28x |
| array_ops | 98 ms | 29 ms | 0.30x |
| objects | 97 ms | 36 ms | 0.37x |
| closures | 98 ms | 83 ms | 0.85x |
| loops | 130 ms | 120 ms | 0.92x |
| fibonacci | 161 ms | 157 ms | 0.97x |

```
zig build -Doptimize=ReleaseFast
./benchmarks/runtime/run
```

## HTTP throughput

Measured with [wrk](https://github.com/wg/wrk): 4 threads, 100 connections, 10 seconds. All servers return `echo "hello"`.

| Server | req/s | Avg latency |
|---|---|---|
| zphp serve | 92,343 | 1.12 ms |
| nginx + php-fpm (128 workers) | 42,088 | 50.37 ms |

zphp serve delivers 2.2x higher throughput and 45x lower latency than the traditional nginx + php-fpm stack.

```
zig build -Doptimize=ReleaseFast
./benchmarks/serve/wrk_bench
```

**Note**: nginx + php-fpm numbers are from Docker with linux/amd64 emulation on Apple Silicon. Native Linux performance would be better for php-fpm. These numbers are directional, not absolute. Run the benchmarks on your own hardware for numbers relevant to your deployment.

## Formatter

Formatting a 416-line PHP file. Best of 10 runs.

| Tool | Time |
|---|---|
| zphp fmt | 5 ms |
| php-cs-fixer (PSR-12) | 92 ms |
| prettier @prettier/plugin-php | 95 ms |

```
./benchmarks/fmt
```
