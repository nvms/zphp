# Serving an Application

`zphp serve` runs the built-in HTTP server:

```sh
zphp serve app.php --port 3000 --workers 8
```

The entry point is compiled at startup. Each worker keeps a persistent VM, with request state reset before each PHP request. Values are reclaimed during execution, not only at request boundaries. Compiled bytecode is retained across requests, including cached includes and directly requested PHP scripts.

## Options

| Flag | Default | Description |
|---|---|---|
| `--port <N>` | 8080 | Port to listen on |
| `--workers <N>` | CPU count | Number of worker threads |
| `--tls-cert <file>` | None | TLS certificate |
| `--tls-key <file>` | None | TLS private key |
| `--watch` | Off | Restart workers when PHP file changes are detected under the document root |
| `--admin-port <N>` | Off | Serve `/health`, `/ready` and `/metrics` on a separate loopback listener |
| `--access-log` | Off | Write a JSON line per request |

Logging, request IDs and metrics have more options; see [Observability](./observability.md).

The server binds to all IPv4 interfaces. Use firewall rules or a reverse proxy to control access. Provide both TLS flags to enable HTTPS.

## Request handling

Existing `.php` files under the document root execute directly. Other dynamic paths run the entry point from the top. Non-PHP files can be served without executing PHP; see [Static Files](./static-files.md).

The server populates request superglobals, including `$_SERVER` and `$_GET`. Form bodies populate `$_POST`, and multipart uploads populate `$_FILES`. Read a raw request body through `php://input`.

```php
<?php
header('Content-Type: application/json');

if ($_SERVER['REQUEST_URI'] === '/health') {
    echo json_encode(['status' => 'ok']);
} else {
    http_response_code(404);
    echo json_encode(['error' => 'not found']);
}
```

For HTTP/1.1 responses, use `header()` and `header_remove()` to manage headers, `http_response_code()` for status, and `setcookie()` for cookies. Keep-alive is supported. Compressible responses are gzip-compressed when the client advertises gzip support.

The HTTP/2 response path currently sends the status and content type, but does not forward custom response headers or cookies. It also does not apply gzip compression. See [TLS and HTTP/2](./tls.md).

At startup, a `.env` file in the working directory is loaded into the environment and exposed through `$_ENV`. Use `--watch` during development, or restart the server after deploying changed PHP code.
