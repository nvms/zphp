# zphp

zphp is a PHP runtime built from scratch in Zig. It runs your PHP code, serves your application, manages your packages, runs your tests, and formats your code. One binary, no dependencies.

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

zphp runs standard PHP code. Your existing `.php` files, your classes, your closures, your generators - they work. The standard library functions you rely on are there. If you've written PHP before, you already know how to use zphp.

Where zphp differs is in what surrounds your code. Instead of assembling a stack of nginx, php-fpm, composer, phpunit, and php-cs-fixer, you have a single binary that handles all of it. Your deployment is one file. Your dev setup is one command.

This isn't about replacing the tools you know. Composer, PHPUnit, and php-cs-fixer are excellent. zphp just offers a different approach: everything in one place, nothing to configure, nothing to install separately.
