# Serving an Application

`zphp serve` is a production HTTP server built into the runtime. It replaces the nginx + php-fpm stack with a single process that handles keep-alive, gzip, static files, worker pooling, and graceful shutdown.

## Basic usage

```
$ zphp serve app.php
listening on http://0.0.0.0:8080 (14 workers)
```

Your `app.php` is compiled to bytecode once at startup. Each worker runs its own VM instance with a pooled copy of the bytecode, so there's no per-request compilation overhead.

## Options

| Flag | Default | Description |
|---|---|---|
| `--port <N>` | 8080 | Port to listen on |
| `--workers <N>` | CPU count | Number of worker threads |
| `--tls-cert <file>` | - | Path to TLS certificate (enables HTTPS) |
| `--tls-key <file>` | - | Path to TLS private key |
| `--watch` | off | Watch PHP files for changes and automatically reload workers |

```
$ zphp serve app.php --port 3000 --workers 8
```

## Request handling

Each request executes your PHP file from the top. The standard `$_SERVER`, `$_GET`, `$_POST`, `$_COOKIE`, and `$_FILES` superglobals are populated from the incoming request, just like PHP.

```php
<?php

$method = $_SERVER['REQUEST_METHOD'];
$path = $_SERVER['REQUEST_URI'];

if ($method === 'GET' && $path === '/health') {
    echo json_encode(['status' => 'ok']);
} else if ($method === 'POST' && $path === '/api/data') {
    $body = file_get_contents('php://input');
    $data = json_decode($body, true);
    echo json_encode(['received' => $data]);
} else {
    http_response_code(404);
    echo json_encode(['error' => 'not found']);
}
```

## Response headers and status codes

The standard PHP header functions work in serve mode:

```php
<?php
header("Content-Type: application/json");
header("X-Custom: value");
header("X-Multi: one");
header("X-Multi: two", false);  // append instead of replace
header("Location: /other", true, 302);  // set status code as third arg
http_response_code(201);
setcookie("session", "abc123", ["path" => "/", "httponly" => true]);
header_remove("X-Custom");  // remove a specific header
header_remove();  // remove all custom headers
headers_list();  // get array of all set headers
```

These functions work from any call depth - inside functions, methods, closures, included files.

## Features

**Gzip compression** is applied automatically to compressible responses (text, JSON, SVG) when the client sends `Accept-Encoding: gzip`.

**Keep-alive** connections are supported by default. Clients can reuse TCP connections across multiple requests.

**ETag and 304 responses** are handled automatically for static files. The server generates ETags and responds with `304 Not Modified` when the content hasn't changed.

**`.env` auto-loading** at startup. If a `.env` file exists in the working directory, it's loaded automatically and the values are available via `$_ENV`.

**File watching** with `--watch` reloads workers when PHP files change. Useful during development.

**Graceful shutdown** on SIGTERM/SIGINT. Active requests complete before the server exits.

## Comparison to nginx + php-fpm

The traditional PHP deployment requires configuring and running multiple processes:

```
nginx (reverse proxy, static files, TLS termination)
  -> php-fpm (process manager, spawns PHP workers)
    -> your PHP code
```

With zphp:

```
zphp serve app.php --tls-cert cert.pem --tls-key key.pem
```

TLS, static files, gzip, and HTTP/2 are all handled by the same process.
