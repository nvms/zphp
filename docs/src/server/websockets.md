# WebSockets

zphp has built-in WebSocket support. No extensions, no third-party libraries. Define three handler functions in your PHP file and you have a WebSocket server.

## Handler functions

zphp looks for three functions in your entry point:

```php
<?php

function ws_onOpen($conn) {
    // called when a client connects
    $conn->send("welcome");
}

function ws_onMessage($conn, $message) {
    // called when a client sends a message
    $conn->send("echo: " . $message);
}

function ws_onClose($conn) {
    // called when a client disconnects
}
```

That's it. Serve it:

```
$ zphp serve ws_app.php --port 8080
```

Clients connect via `ws://localhost:8080` (or `wss://` if TLS is enabled). Regular HTTP requests are still handled by your PHP code as normal. WebSocket and HTTP coexist on the same port.

## The connection object

Each handler receives a `WebSocketConnection` object:

| Method | Description |
|---|---|
| `$conn->send($message)` | Send a text message to the client |
| `$conn->close()` | Close the connection |

## Example: chat relay

```php
<?php

$clients = [];

function ws_onOpen($conn) {
    global $clients;
    $clients[] = $conn;
    $conn->send("connected (" . count($clients) . " online)");
}

function ws_onMessage($conn, $message) {
    global $clients;
    foreach ($clients as $client) {
        $client->send($message);
    }
}

function ws_onClose($conn) {
    global $clients;
    $clients = array_filter($clients, fn($c) => $c !== $conn);
}
```

## WebSocket with TLS

When TLS is enabled, WebSocket connections automatically upgrade to WSS:

```
$ zphp serve ws_app.php --tls-cert cert.pem --tls-key key.pem
```

Clients connect via `wss://localhost:8080`.

## Mixed HTTP and WebSocket

Your entry point handles both regular HTTP requests and WebSocket connections. The WebSocket handler functions are only called for WebSocket upgrade requests. Everything else goes through the normal request path.

```php
<?php

// HTTP requests execute this code
$path = $_SERVER['REQUEST_URI'];
if ($path === '/api/status') {
    echo json_encode(['status' => 'running']);
}

// WebSocket connections call these functions
function ws_onOpen($conn) {
    $conn->send("connected");
}

function ws_onMessage($conn, $msg) {
    $conn->send("got: " . $msg);
}

function ws_onClose($conn) {}
```
