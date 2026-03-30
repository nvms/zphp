# zphp

zphp is a PHP runtime written in Zig. It can run PHP scripts, serve HTTP, manage packages, run tests, and format code.

```
$ zphp serve app.php --port 8080
listening on http://0.0.0.0:8080 (14 workers)
```

## What's in the box

| Command | What it does |
|---|---|
| `zphp run <file>` | Execute a PHP script |
| `zphp serve <file>` | Production HTTP server with TLS, HTTP/2, WebSocket, gzip |
| `zphp test [file]` | Test runner with built-in assertions |
| `zphp fmt <file>...` | Code formatter |
| `zphp build <file>` | Compile to bytecode |
| `zphp build --compile <file>` | Compile to a standalone executable |
| `zphp install` | Install packages from composer.json |
| `zphp add <pkg>` | Add a package |

## How it relates to PHP

zphp runs standard PHP code. Existing `.php` files, classes, closures, generators, and standard library functions all work. The [compatibility](compatibility/same.md) section covers what's supported in detail.

The difference is in the tooling around it. Instead of assembling nginx, php-fpm, composer, phpunit, and php-cs-fixer separately, zphp bundles all of that into one binary.
