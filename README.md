# zphp

**A high-performance PHP runtime built in Zig.**

zphp is an experimental PHP 8.x-compatible runtime focused on **speed, low memory usage, and modern deployment**. It combines a custom runtime with a built-in HTTP server, WebSocket support, TLS, HTTP/2, database drivers, cURL bindings, package management, testing, formatting, and standalone compilation.

Built with **Zig**, zphp is designed to give PHP workloads lower-level control, reduced overhead, and a more performance-oriented runtime architecture.

```sh
zphp run app.php
zphp serve app.php --port 8080
zphp build --compile app.php
zphp test
zphp fmt src/*.php
zphp install
```

## Features

* PHP 8.x compatibility
* Runtime written in Zig
* Built-in HTTP server
* HTTP/2, TLS, and WebSockets
* SQLite, MySQL, and PostgreSQL
* cURL bindings
* Composer package support
* Standalone executable compilation
* Performance and low-memory focused architecture

## Comparison

| Task              | PHP                | zphp                   |
| ----------------- | ------------------ | ---------------------- |
| Run script        | `php app.php`      | `zphp run app.php`     |
| HTTP server       | PHP-FPM + nginx    | `zphp serve app.php`   |
| Dependencies      | `composer install` | `zphp install`         |
| Tests             | PHPUnit            | `zphp test`            |
| Formatting        | PHP-CS-Fixer       | `zphp fmt`             |
| Standalone binary | External tooling   | `zphp build --compile` |

## Installation

Download builds from [GitHub Releases](https://github.com/nvms/zphp/releases).

| Asset | Platform | Notes |
|---|---|---|
| `zphp-linux-x86_64-musl` | Any Linux distribution, x86_64 | Static. The matching `.libs.txt` lists the archives built in. |
| `zphp-linux-aarch64-musl` | Any Linux distribution, aarch64 | Static. The matching `.libs.txt` lists the archives built in. |
| `zphp-linux-x86_64` | Ubuntu 24.04 x86_64 | Links the system libraries listed in the matching `.libs.txt`. |
| `zphp-linux-aarch64` | Ubuntu 24.04 aarch64 | Links the system libraries listed in the matching `.libs.txt`. |
| `zphp-macos-aarch64` | macOS 15 or newer, Apple Silicon | Links Homebrew libraries listed in the matching `.libs.txt`. |

The glibc and macOS builds run on the platform they were made for; the musl builds run anywhere, and for anything else, build from source. Every release ships a `SHA256SUMS` file, a `.libs.txt` per binary naming the native libraries it was linked against, and a build provenance attestation you can check with `gh attestation verify zphp-<platform> --repo nvms/zphp`.

See the [documentation](https://nvms.github.io/zphp/) for build instructions and usage guides.

## Extensions

zphp loads native extensions written against a C ABI. An extension registers functions, classes, constants, ini defaults, and resource types once at load time, and every PHP call into it goes straight to a resolved function pointer. The header is `include/zphp_extension.h`; the same source builds as a shared library or gets compiled into zphp.

```c
#include "zphp_extension.h"

static void hello_add(zphp_ctx *ctx) {
    zphp_return_int(ctx, zphp_get_int(zphp_arg(ctx, 0)) + zphp_get_int(zphp_arg(ctx, 1)));
}

static int module_init(zphp_module *m) {
    return zphp_register_function(m, "hello_add", hello_add);
}

static const zphp_extension hello = {
    .abi = ZPHP_EXTENSION_ABI, .name = "hello", .version = "1.0.0", .module_init = module_init,
};

ZPHP_EXTENSION(hello, &hello)
```

```sh
zig cc -shared -O2 -I include -o hello.so hello.c
zphp --extension=hello.so run app.php          # dynamic
zig build -Doptimize=ReleaseFast -Dextension=hello.c   # static, compiled into zphp
```

`ZPHP_EXTENSION_DIR` names a directory whose libraries load automatically. Extensions get module, worker, and request lifecycle hooks, a request-local and a worker-local data slot, and a destructor per resource type that runs when the PHP value is unset, goes out of scope, unwinds through an exception, or the request ends. Values cross the boundary as opaque handles, so the runtime's internals can change without breaking compiled extensions; an ABI version in the descriptor rejects mismatches at load time. The static musl release binaries cannot load shared libraries and take static extensions only. `tests/extensions/demo.c` exercises the whole API.

## Project Status

zphp was originally developed and maintained heavily through AI-assisted development.

The project is now being actively reviewed and hardened with a stronger focus on **security, correctness, memory safety, testing, performance validation, and production readiness**.

AI may still be used as a development tool, but critical runtime code is expected to be reviewed, tested, and independently verified.

zphp is still experimental and should be thoroughly tested before production use.

---

**PHP on the surface. Zig at the core. Built for speed.**
