# serve benchmarks

compares zphp serve against PHP-FPM (nginx + php-fpm) and Swoole on HTTP throughput and WebSocket concurrency.

## run

```
./benchmarks/serve/bench
```

requires Docker for PHP-FPM and Swoole. zphp runs natively. first run builds Docker images.

## results (Apple M4, 14 cores)

### HTTP throughput (1000 requests, 50 concurrent)

| server | req/s |
|---|---|
| php-fpm (128 workers) | 2,957 |
| swoole (4 workers) | 6,033 |
| zphp (14 workers) | 5,193 |

all servers running echo "hello". php-fpm and swoole in Docker (linux/amd64 emulation). zphp native.

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

- php-fpm and swoole run in Docker with linux/amd64 emulation on Apple Silicon. native performance would be better for both.
- zphp runs natively. this gives it an advantage on raw throughput but is representative of real deployment (zphp is a single native binary).
- swoole's lower per-connection overhead at scale is expected: its C-level coroutine implementation is highly optimized for this workload.
- zphp's advantage is architectural: single binary, no Docker/nginx/FPM stack, 4.4x lower baseline memory, and the same event-loop concurrency model as Node.js.
