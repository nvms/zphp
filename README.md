# zphp

A PHP 8.4 runtime written in Zig, with a built-in HTTP server, worker threads, a native extension API, and standalone executables.

```sh
zphp run script.php
zphp serve public/index.php --port 8080
zphp build --compile app.php
```

Read the [documentation](https://nvms.github.io/zphp/) for everything else.

## Compatibility

Every compatibility test runs under both zphp and PHP and must produce the same output. Laravel, WordPress, PHPUnit, and Composer run under their own harnesses. The extensions most applications need are built in, including PDO for SQLite, MySQL, and PostgreSQL, cURL, and GD, but being loaded does not make an extension complete: the [extension compatibility matrix](https://nvms.github.io/zphp/compatibility/extensions.html) records the status of each extension and API. PHP's C extensions do not load; see [what works differently](https://nvms.github.io/zphp/compatibility/different.html).

## Threads

`Zphp\Pool` runs PHP on several OS threads in one process, each with its own interpreter. PHP needs a thread-safe build and [ext-parallel](https://github.com/krakjoe/parallel) for this; zphp has it built in.

```php
$pool = new Zphp\Pool(workers: 8);
$jobs = [];

foreach (glob('photos/*.jpg') as $path) {
    $jobs[] = $pool->submit(function (string $path) {
        $thumb = imagescale(imagecreatefromjpeg($path), 320);
        imagejpeg($thumb, 'thumbs/' . basename($path));
    }, [$path]);
}

foreach ($jobs as $job) {
    $job->await();
}
```

A `Zphp\Channel` streams values between threads while a task runs. Here a worker parses a large CSV while the main thread saves each row:

```php
$rows = new Zphp\Channel(capacity: 100);

$parse = $pool->submit(function (string $path, Zphp\Channel $rows) {
    $file = fopen($path, 'r');

    while (($row = fgetcsv($file)) !== false) {
        $rows->send($row);
    }

    $rows->close();
}, ['orders.csv', $rows]);

foreach ($rows as $row) {
    save_order($row);
}

$parse->await();
```

`Zphp\select` waits on several channels or futures and returns the first one ready:

```php
$fetch = fn($url) => file_get_contents($url);

[$region, $response] = Zphp\select([
    'eu' => $pool->submit($fetch, ['https://eu.api.example.com/rates']),
    'us' => $pool->submit($fetch, ['https://us.api.example.com/rates']),
]);

$rates = json_decode($response->await(), true);
```

[`Zphp\Buffer`](https://nvms.github.io/zphp/parallelism/buffers.html) moves binary data between threads without copying it, where ext-parallel copies every value.

## Server

`zphp serve` runs an application without nginx or PHP-FPM. It handles TLS, HTTP/2, WebSockets, gzip, and static files itself, and its workers keep compiled bytecode between requests.

```sh
zphp serve public/index.php --workers 8 --tls-cert cert.pem --tls-key key.pem
```

## Standalone executables

`zphp build --compile app.php` turns a script into an executable that runs on machines without PHP installed.

## Extensions

Extensions use the C ABI in [`include/zphp_extension.h`](include/zphp_extension.h), and the same source builds as a shared library or compiles into zphp.

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
zphp --extension=hello.so run app.php
```

[`tests/extensions/demo.c`](tests/extensions/demo.c) covers the rest of the API. [zphp-bindings](https://github.com/nexxii04/zphp-bindings) wraps it for Zig.

## Tooling

Composer and PHPUnit run under zphp. It also ships its own tools:

| Command | |
|---|---|
| `zphp install` | Installs packages from Packagist using `composer.json` |
| `zphp test` | Built-in test runner |
| `zphp fmt src/*.php` | Opinionated formatter with no configuration, like `gofmt` |

## Installation

Download a binary from [releases](https://github.com/nvms/zphp/releases). The `-musl` Linux builds are a single static file that runs on any distribution, so copying it to a server is the whole install. To build from source, see [installation](https://nvms.github.io/zphp/getting-started/installation.html).

## Status

zphp is pre-1.0 and its APIs may still change. Run your application's test suite under zphp before deploying it.

## Development

zphp's implementation is largely AI-written. Its direction, priorities, and releases are set by a human.
