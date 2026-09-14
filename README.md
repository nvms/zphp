# zphp

**A high-performance PHP runtime built in Zig.**

zphp is an experimental PHP 8.x-compatible runtime focused on **speed, low memory usage, modern deployment, and native concurrency**. It combines a custom runtime with a built-in HTTP server, WebSocket support, TLS, HTTP/2, database drivers, cURL bindings, package management, testing, formatting, and standalone compilation.

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
| `zphp-windows-x86_64.zip` | Windows 10 or newer, x86_64 | `zphp.exe` with the mingw-w64 DLLs it needs in the same folder, listed in the matching `.libs.txt`. |

The glibc, macOS, and Windows builds run on the platform they were made for; the musl builds run on any Linux, and for anything else, build from source. Every release ships a `SHA256SUMS` file, a `.libs.txt` per binary naming the native libraries it was linked against, and a build provenance attestation you can check with `gh attestation verify zphp-<platform> --repo nvms/zphp`.

See the [documentation](https://nvms.github.io/zphp/) for build instructions and usage guides.

## Configuration

zphp reads a php.ini file at startup: `--ini=PATH`, then the `ZPHP_INI` environment variable, then `php.ini` in the working directory, whichever comes first. `-d name=value` overrides a directive from the command line, as with `php -d`.

```sh
zphp --ini=/etc/zphp/php.ini serve public/index.php
zphp -d date.timezone=Europe/Berlin -d memory_limit=512M run job.php
```

Values follow php.ini rules: quotes are stripped, `On`/`Off` become `1` and empty, `${VAR}` expands from the environment, and `error_reporting = E_ALL & ~E_DEPRECATED` is evaluated. `date.timezone`, `error_reporting`, and `max_execution_time` take effect at the start of every request, and `ini_set` only changes the current request; the next one starts from the file again. `extension=` lines load extensions, by path or by name inside `extension_dir`, and `php_ini_loaded_file()` reports what was read.

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

## Worker threads

`Zphp\Pool` runs PHP functions on a fixed set of OS threads, each with its own isolated interpreter. A pool takes a bootstrap script that every worker runs once, so functions, classes, and worker-local state are ready before the first task arrives.

```php
$pool = new Zphp\Pool(workers: 4, bootstrap: __DIR__ . '/worker.php');

$futures = [];
foreach ($pages as $page) {
    $futures[] = $pool->submit('render', [$page]);
}
foreach ($futures as $future) {
    echo $future->await();
}
$pool->shutdown();
```

A task is a closure or a named callable: a function name, `'Class::method'`, or `[$class, $method]`, defined by the bootstrap or built in. Arguments and results are copied between interpreters, so they must be null, bool, int, float, string, arrays of those, or objects of classes both sides define. Generators and handle-backed objects such as PDO connections are refused when submitted, with the offending path in the message.

A closure travels as its compiled code plus its captures: `use` variables, the variables an arrow function reads from the submitting scope, and `$this` when it has one. Each worker loads the code once and runs every later submit of the same closure against it. Captures follow the transfer rules above, and a closure that captures by reference is refused, since nothing can be shared between threads.

```php
$scale = 0.5;
$thumbnails = [];
foreach ($paths as $path) {
    $thumbnails[] = $pool->submit(function (string $path) use ($scale) {
        return resize($path, $scale);
    }, [$path]);
}
```

`await()` returns the result, or rethrows the task's exception as the same class when the caller has it. A queued task can be cancelled; a running one sees `Zphp\Task::cancelled()` and stops when it chooses, since nothing is ever killed. The queue is bounded: `submit()` blocks when it is full and `trySubmit()` returns null instead. `collect()` hands back completed futures in completion order, and `readiness()` is a stream that becomes readable when one is waiting, for use with `stream_select()`. `shutdown()` stops accepting work, cancels what is queued, and waits for running tasks; the pool's destructor does the same.

### Channels

`Zphp\Channel` is a bounded queue that workers and the main thread share. A channel passed to a task binds to the same queue on the other side, so a producer and its consumers can run on different threads without sharing PHP memory.

```php
$jobs = new Zphp\Channel(capacity: 16);
$results = new Zphp\Channel(capacity: 256);

$consumers = [];
for ($i = 0; $i < 4; $i++) {
    $consumers[] = $pool->submit('resize_images', [$jobs, $results]);
}
foreach (glob('uploads/*.jpg') as $path) {
    $jobs->send($path);
}
$jobs->close();
foreach ($consumers as $future) {
    $future->await();
}
$results->close();
foreach ($results as $thumbnail) {
    echo $thumbnail, "\n";
}
```

```php
// worker.php
function resize_images(Zphp\Channel $jobs, Zphp\Channel $results): void
{
    foreach ($jobs as $path) {
        $results->send(resize($path));
    }
}
```

`send()` blocks while the channel is full and `recv()` blocks while it is empty; both take an optional timeout in seconds and throw `Zphp\TimeoutException` when it passes. `trySend()` returns false instead of waiting. `close()` lets buffered values drain and then ends every `foreach`, while `send()` and `recv()` on a closed channel throw `Zphp\ChannelException`. Values follow the same transfer rules as task arguments, and a channel can carry other channels. A channel stays alive while any thread holds it or a value in flight names it.


## Related projects

- [zphp-bindings](https://github.com/nexxii04/zphp-bindings): Zig bindings for the extension ABI, so extensions can be written in Zig without C.

## Project Status

zphp was originally developed and maintained heavily through AI-assisted development.

The project is now being actively reviewed and hardened with a stronger focus on **security, correctness, memory safety, testing, performance validation, and production readiness**.

AI may still be used as a development tool, but critical runtime code is expected to be reviewed, tested, and independently verified.

zphp is still experimental and should be thoroughly tested before production use.

---

**PHP on the surface. Zig at the core. Built for speed.**
