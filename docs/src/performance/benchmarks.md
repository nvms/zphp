# Benchmarks

All benchmarks run on Apple M4 (14 cores), comparing zphp (ReleaseFast) against PHP 8.5 (no JIT). Benchmarks are in the `benchmarks/` directory and can be reproduced locally.

## Runtime

Six compute-heavy benchmarks. Best of 5 runs. Startup overhead is subtracted to measure pure execution time.

| Benchmark | PHP | zphp | Ratio |
|---|---|---|---|
| string_ops | 96 ms | 26 ms | 0.27x |
| array_ops | 87 ms | 29 ms | 0.33x |
| objects | 103 ms | 36 ms | 0.35x |
| closures | 96 ms | 80 ms | 0.83x |
| loops | 132 ms | 119 ms | 0.90x |
| fibonacci | 164 ms | 150 ms | 0.91x |

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

2.2x throughput, 45x lower latency compared to nginx + php-fpm.

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
