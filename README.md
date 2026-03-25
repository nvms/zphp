<p align="center">
  <img src="logo.svg" width="140" style="border-radius: 12px;" />
</p>

<h1 align="center">zphp</h1>

<p align="center">A PHP runtime written in Zig. Single binary. No dependencies.</p>

---

zphp is a from-scratch PHP runtime with near-complete PHP 8.x feature parity. It ships as a single binary under 5MB with no external dependencies - no php-fpm, no nginx, no extensions to install. The runtime includes a built-in HTTP server, WebSocket support, and database drivers for SQLite, MySQL, and PostgreSQL.

```sh
# run PHP
zphp run app.php

# start an HTTP server with worker pooling
zphp serve app.php --workers 4

# compile to pre-built bytecode (skips parse/compile on subsequent runs)
zphp build app.php

# compile to a standalone executable - runtime, C libs, and bytecode in one file
zphp build --compile app.php
```

## Features

**Runtime** - classes, interfaces, traits, abstract classes, enums (pure and backed), generators, fibers, closures, arrow functions, match expressions, named arguments, union/intersection/nullable types, readonly properties, constructor promotion, first-class callable syntax, array destructuring, spread operator, try/catch/finally, namespaces, autoloading.

**HTTP Server** - pre-compiled bytecode, VM pooling across requests, keep-alive connections, gzip compression, static file serving with ETag/304, multipart form data and file uploads, chunked transfer encoding, graceful shutdown.

**WebSocket** - RFC 6455, convention-based routing (`ws_onOpen`, `ws_onMessage`, `ws_onClose`), persistent VM state across messages, poll-based event loop multiplexing HTTP and WebSocket connections concurrently.

**Database** - PDO with SQLite, MySQL, and PostgreSQL drivers. Prepared statements, named and positional parameters, transactions, FETCH_ASSOC/NUM/BOTH.

**Tooling** - package manager (reads `composer.json`, resolves from Packagist), test runner, opinionated code formatter, AOT bytecode compiler, standalone binary compiler.

## Quick comparison

| | Traditional PHP | zphp |
|---|---|---|
| Run a script | `php script.php` | `zphp run script.php` |
| HTTP server | php-fpm + nginx | `zphp serve app.php` |
| Install deps | `composer install` | `zphp install` |
| Add a package | `composer require pkg` | `zphp add pkg` |
| Run tests | `phpunit` | `zphp test` |
| Format code | `php-cs-fixer fix` | `zphp fmt` |
| Compile to bytecode | opcache (runtime) | `zphp build app.php` |
| Standalone binary | - | `zphp build --compile app.php` |

## Standalone executables

`zphp build --compile` produces a self-contained binary that bundles the runtime, all linked C libraries (pcre2, sqlite3, zlib, mysql, postgres), and your application bytecode into a single file. The result runs without zphp or any system dependencies installed on the target machine.

```sh
zphp build --compile server.php   # produces ./server (4-5MB)
./server                           # run - no zphp needed
```

## Installation

Prebuilt binaries for Linux and macOS will be available via GitHub releases.

## Building from source

Requires Zig 0.15.x and system libraries for pcre2, sqlite3, zlib, and optionally mysql-client and libpq.

```sh
# Ubuntu/Debian
apt install libpcre2-dev libsqlite3-dev zlib1g-dev libmysqlclient-dev libpq-dev

# macOS
brew install pcre2 mysql-client libpq

make build    # build
make test     # run tests
```

---

This project is an experiment in AI-maintained open source - autonomously built, tested, and refined by AI with human oversight. Regular audits, thorough test coverage, continuous refinement. The emphasis is on high quality, rigorously tested, production-grade code.
