# Standalone Executables

`zphp build --compile` produces a single executable that contains both the zphp runtime and your compiled PHP bytecode. The result is a binary that runs without needing zphp or PHP installed on the target machine.

## Usage

```
$ zphp build --compile app.php
```

This produces an executable called `app` (the input filename without the extension):

```
$ ./app
Hello from my PHP application
```

## What this means for deployment

The target machine doesn't need PHP or zphp installed. Copy the binary, run it.

```
$ scp app server:/usr/local/bin/
$ ssh server '/usr/local/bin/app'
```

This works for both scripts (`zphp run` style) and servers (`zphp serve` style). A compiled server binary includes the full HTTP server, TLS support, and everything else `zphp serve` provides.

## Dependencies

Most of zphp's dependencies are statically linked into the binary. A few remain dynamic:

| Library | Linked | Notes |
|---|---|---|
| pcre2, OpenSSL, nghttp2 | Static | Built into the binary |
| sqlite3, zlib | Dynamic | Present on all Linux and macOS systems |
| libmysqlclient | Dynamic | Only needed if using PDO with MySQL |
| libpq | Dynamic | Only needed if using PDO with PostgreSQL |

If your application doesn't use MySQL or PostgreSQL, the binary runs with no additional libraries beyond what the OS provides. If it does, the respective client library needs to be installed on the target machine:

```
$ sudo apt-get install -y libmysqlclient21   # MySQL
$ sudo apt-get install -y libpq5              # PostgreSQL
```
