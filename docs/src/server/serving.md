# Serving an Application

`zphp serve` is a production HTTP server built into the runtime. It handles everything you'd normally need nginx + php-fpm for: keep-alive connections, gzip compression, static file serving, worker pooling, and graceful shutdown.

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

```
$ zphp serve app.php --port 3000 --workers 8
```

## Request handling

Each request executes your PHP file from the top. The standard `$_SERVER`, `$_GET`, `$_POST`, `$_COOKIE`, and `$_FILES` superglobals are populated from the incoming request, just like php-fpm.

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

## Features

**Gzip compression** is applied automatically to compressible responses (text, JSON, SVG) when the client sends `Accept-Encoding: gzip`.

**Keep-alive** connections are supported by default. Clients can reuse TCP connections across multiple requests.

**ETag and 304 responses** are handled automatically for static files. The server generates ETags and responds with `304 Not Modified` when the content hasn't changed.

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

One process, one command. TLS, static files, gzip, and HTTP/2 are all built in.
