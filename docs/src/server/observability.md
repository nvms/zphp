# Observability

`zphp serve` can report its health, export Prometheus metrics, write structured access logs, and tag every request with an ID. Every feature is opt-in. With none of the flags below, the server behaves and performs exactly as it does without them.

```sh
zphp serve app.php --workers 8 --admin-port 9090 --access-log
```

## Options

| Flag | Default | Description |
|---|---|---|
| `--admin-port <N>` | Off | Start the admin listener on port N. It serves `/health`, `/ready` and `/metrics`, and metrics are collected only while it is on. |
| `--admin-host <IP>` | `127.0.0.1` | Address the admin listener binds to. Requires `--admin-port`. |
| `--access-log` | Off | Write one JSON line per request. Implies `--log-format json` and `--request-id`. |
| `--log-format <text\|json>` | `text` | `text` keeps the human-readable messages on stderr. `json` writes server events as JSON Lines to stdout. |
| `--log-file <path>` | stdout | Append JSON lines to this file instead of stdout. Implies `--log-format json`. |
| `--request-id` | Off | Assign request IDs without enabling access logs. |

The server checks these options before it binds anything. An invalid port, a missing value, `--admin-port` equal to `--port`, an admin host that is not an IP address, `--log-format text` combined with `--access-log` or `--log-file`, or a log file that cannot be opened stops startup with an error and exit status 1. So does an admin port that is already in use.

## Admin listener

The admin listener is a separate socket served by its own thread. Probes and scrapes never reach application routes or run PHP, and they keep working while every worker is busy. `/health` on the application port is still your application's route.

| Path | Status | Body |
|---|---|---|
| `/health` | 200 while the process is running and its admin thread is responsive | `ok` |
| `/ready` | 200 once workers are serving, 503 during startup, `--watch` reloads and shutdown | `ready` or `not ready` |
| `/metrics` | 200 | Prometheus text format 0.0.4 |

Only `GET` and `HEAD` are accepted (`405` otherwise), and other paths answer `404`. Each response closes its connection. The listener comes up before the application compiles, so orchestrators see `/ready` return 503 until the server can accept application requests. Readiness drops to 503 as soon as a shutdown or reload starts.

A Kubernetes probe setup:

```yaml
livenessProbe:
  httpGet: { path: /health, port: 9090 }
readinessProbe:
  httpGet: { path: /ready, port: 9090 }
```

### Security

The admin listener binds to `127.0.0.1` by default and has no authentication. Metrics reveal traffic volume, error rates and memory use. Expose it beyond loopback only on a trusted network, for example `--admin-host 0.0.0.0` inside a container whose port is reachable only by the scraper, and keep it out of public load balancers. Clients are served one at a time with a two-second deadline, so a stalled admin client cannot hold the listener for long, and it never affects application workers.

## Prometheus metrics

```yaml
scrape_configs:
  - job_name: zphp
    static_configs:
      - targets: ['127.0.0.1:9090']
```

Every value covers the whole server. Each worker records into its own counters without locks or shared cache lines, and `/metrics` sums them when scraped. Labels are fixed: no URL, request ID or other client-supplied value ever becomes a label.

| Metric | Type | Meaning |
|---|---|---|
| `zphp_http_requests_total{code}` | counter | Requests answered, by status class `1xx` to `5xx`. Includes responses the server produced itself, such as 400 for a malformed body. |
| `zphp_http_request_duration_seconds` | histogram | Time from a complete request to its response being written. Buckets from 1 ms to 10 s. |
| `zphp_http_requests_active` | gauge | Requests being handled right now. A worker runs one request at a time, so this is also the number of busy workers. |
| `zphp_connections_active` | gauge | Client connections held by workers, including keep-alive, HTTP/2 and WebSocket connections. |
| `zphp_connections_accepted_total` | counter | Connections accepted. |
| `zphp_connections_dropped_total` | counter | Connections closed on arrival because a worker's connection table was full. |
| `zphp_workers` | gauge | Configured workers. |
| `zphp_workers_running` | gauge | Workers currently running. Lower than `zphp_workers` when some failed to start. |
| `zphp_worker_busy_seconds_total` | counter | Time spent handling requests. `rate(zphp_worker_busy_seconds_total[1m]) / zphp_workers_running` is worker utilization. |
| `zphp_worker_start_failures_total` | counter | Workers that failed to start. |
| `zphp_reloads_total` | counter | Restarts triggered by `--watch`. |
| `zphp_vm_memory_bytes` | gauge | PHP memory in use by the worker VMs at the end of their last request, before per-request state is reset. A rising floor points at memory retained across requests. |
| `process_resident_memory_bytes` | gauge | Current resident memory (Linux and Windows). |
| `process_resident_memory_max_bytes` | gauge | Peak resident memory. |
| `process_start_time_seconds` | gauge | Process start time, seconds since the Unix epoch. |
| `zphp_uptime_seconds` | gauge | Seconds since the server started. |
| `zphp_ready` | gauge | 1 when `/ready` answers 200. |
| `zphp_log_write_errors_total` | counter | Log lines that could not be written. |

Counters persist across `--watch` reloads and reset only when the process restarts. Requests are counted when their response is written, including requests that end in an uncaught exception. A connection that closes before sending a complete request is not counted as a request. WebSocket messages are not requests; the upgrade itself is counted with status 101.

Useful queries:

```promql
sum(rate(zphp_http_requests_total{code="5xx"}[5m])) / sum(rate(zphp_http_requests_total[5m]))
histogram_quantile(0.99, sum by (le) (rate(zphp_http_request_duration_seconds_bucket[5m])))
```

## Request IDs

With `--request-id` or `--access-log`, every request gets an ID:

- A valid incoming `X-Request-Id` header is kept. Valid means 1 to 64 characters from `A-Z a-z 0-9 - _ . :`.
- Anything else, including a missing header, gets a new random 32-character hex ID. A rejected header is never echoed back.
- The ID is sent back in the `X-Request-Id` response header on HTTP/1.1, HTTP/2, static files, server error responses and WebSocket upgrades.
- PHP sees it as `$_SERVER['REQUEST_ID']`.

```php
<?php
error_log("charging card, request " . $_SERVER['REQUEST_ID']);
```

If the application sets its own `X-Request-Id` header with `header()`, the application's value is sent instead. Each request on a keep-alive or HTTP/2 connection gets its own ID.

## JSON logs

`--log-format json` writes one JSON object per line. Every line has `ts` (UTC, RFC 3339 with milliseconds), `level`, `component` and `msg`. The `server` component reports startup, shutdown, worker start failures, TLS certificate reloads and `--watch` reloads.

```json
{"ts":"2026-11-14T17:45:56.803Z","level":"info","component":"server","msg":"server started","file":"app.php","port":8080,"tls":false,"workers":8,"watch":false,"admin":"127.0.0.1:9090","pid":4242}
```

`--access-log` adds a line per request:

```json
{"ts":"2026-11-14T17:45:56.917Z","level":"info","component":"access","msg":"request","request_id":"8c879700cf5676eda6f59cb811b470c2","worker":1,"method":"GET","path":"/orders","protocol":"HTTP/1.1","status":200,"bytes":2310,"duration_ms":4.213,"remote_addr":"10.0.0.7"}
```

`bytes` counts what was written to the connection for HTTP/1.1, headers included, and the response body for HTTP/2. `path` excludes the query string, and no header, cookie or body is ever logged, so credentials in query parameters or headers stay out of the logs.

Requests that fail with an uncaught exception, or fail inside the server, also produce an `error` line carrying the same `request_id`:

```json
{"ts":"2026-11-14T17:45:56.941Z","level":"error","component":"php","msg":"uncaught exception","request_id":"1f8735e29b84c7011c14a7b9436348e6","worker":2,"exception":"RuntimeException","message":"boom","file":"/srv/app.php","line":16}
```

These lines are for operators and leave PHP's error handling as it is. `display_errors`, `log_errors` and `error_log` behave as before, and clients still see only what the application and `display_errors` allow.

User-controlled values are escaped. Control characters are written as `\u` escapes, and invalid UTF-8 becomes U+FFFD, so a request cannot break or forge a log line. A line is at most 4 KiB; longer values are cut short.

### Delivery

Each line is formatted on the worker's stack and handed to the destination in a single write, with no lock. The log file is opened for append, so lines from concurrent workers never interleave in it. On stdout, a pipe keeps each write whole up to `PIPE_BUF` (4 KiB on Linux, 512 bytes on macOS); typical access lines are around 300 bytes. A write that fails is counted in `zphp_log_write_errors_total` and dropped. It never affects the response. Writes are blocking, so a log reader that stops consuming stdout eventually slows the workers down. Point `--log-file` at local disk, or make sure the stdout collector keeps up.

## Crashes

zphp does not install crash handlers that log from signal context, because that is not safe. A crash ends the process. Run zphp under a supervisor (systemd, a container runtime, Kubernetes) that restarts it, and use the exit status and `process_start_time_seconds` to spot restarts.
