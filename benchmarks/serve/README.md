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

all servers running `echo "hello"`. php-fpm and swoole in Docker (linux/amd64 emulation on Apple Silicon). zphp native. load generated with Python `urllib` (50 threads) - this is a crude benchmark that measures the load generator as much as the server. results should be taken as directional, not absolute. a proper HTTP throughput comparison needs `wrk` or `hey`.

swoole outperforming zphp despite running in Docker emulation is notable. swoole's HTTP server is a mature C extension with years of optimization. zphp's VM is an unoptimized interpreter (no JIT, hash-map variable lookup per frame). for a trivial echo endpoint, the overhead is dominated by VM dispatch, not I/O - which is where swoole's C-level fastpath wins. for real-world PHP with more computation, the gap would narrow since both runtimes spend most time in PHP execution.

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
