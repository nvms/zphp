# serve benchmarks

compares zphp serve against nginx + php-fpm and Swoole on HTTP throughput and WebSocket concurrency.

## HTTP benchmark (wrk)

```
./benchmarks/serve/wrk_bench [duration] [threads] [connections]
```

requires wrk (`brew install wrk` or `apt install wrk`). requires Docker for nginx + php-fpm comparison.

### results (Apple M4, 14 cores, wrk -t4 -c100 -d10s)

| server | req/s | avg latency |
|---|---|---|
| zphp serve | 92,343 | 1.12 ms |
| nginx + php-fpm (128 workers) | 42,088 | 50.37 ms |
| php -S (dev only) | 3,652 | 2.91 ms |

all servers running `echo "hello"`. nginx + php-fpm in Docker (linux/amd64 emulation on Apple Silicon). zphp native. php -S is single-threaded and not a production server - included as a baseline only.

the Docker emulation penalty is real - native Linux php-fpm numbers would be higher. but even accounting for that, zphp's built-in server is competitive with the traditional nginx + php-fpm stack while being a single binary with zero configuration.

### WebSocket concurrent connections

| connections | zphp memory | zphp per-conn | swoole memory | swoole per-conn |
|---|---|---|---|---|
| 0 (baseline) | 6.9 MB | - | 30.6 MB | - |
| 10 | 6.9 MB | 93 KB | 30.6 MB | 302 KB |
| 100 | 12.9 MB | 70 KB | 34.6 MB | 71 KB |
| 500 | 39.0 MB | 68 KB | 45.7 MB | 37 KB |
| 1000 | 72.3 MB | 68 KB | 64.3 MB | 38 KB |

zphp baseline is 4.4x lower (7 MB vs 31 MB). at scale, swoole's per-connection overhead is lower (~38 KB vs ~68 KB) due to zphp's 65 KB per-connection read buffer. the crossover point is around 800 connections.

the comparison to PHP-FPM is more dramatic: FPM has no native WebSocket support and each concurrent connection requires a full PHP process (~20-40 MB). 1000 concurrent connections would require 20-40 GB of RAM.

### notes

- php-fpm and swoole run in Docker with linux/amd64 emulation on Apple Silicon. native Linux performance would be better for both.
- zphp runs natively. this is representative of real deployment (zphp is a single native binary, no container needed).
- swoole's lower per-connection overhead at scale is expected: its C-level coroutine implementation is purpose-built and highly optimized for this workload.
- zphp's 65 KB per-connection read buffer is the dominant per-connection cost. see PERFORMANCE.md for optimization avenues.
- zphp's advantage is architectural: single binary, no Docker/nginx/FPM stack, 4.4x lower baseline memory, and the same event-loop concurrency model as Node.js.
- PHP-FPM has no native WebSocket support. each concurrent HTTP connection requires a full PHP process (~20-40 MB). 1000 concurrent connections would need 20-40 GB of RAM.
