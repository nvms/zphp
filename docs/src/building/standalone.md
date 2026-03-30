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

Your PHP application becomes a single file you can copy to a server and run. No PHP installation, no dependency management on the target machine, no configuration.

```
$ scp app server:/usr/local/bin/
$ ssh server '/usr/local/bin/app'
```

This works for both scripts (`zphp run` style) and servers (`zphp serve` style). A compiled server binary includes the full HTTP server, TLS support, and everything else `zphp serve` provides.

## System libraries

The standalone binary dynamically links against a few system libraries: pcre2, sqlite3, zlib, OpenSSL, and nghttp2. On most Linux servers, these are already installed. The MySQL and PostgreSQL client libraries are also linked if your application uses PDO with those drivers.

On Ubuntu/Debian, if you need to install them:

```
$ sudo apt-get install -y libpcre2-8-0 libsqlite3-0 zlib1g libssl3 libnghttp2-14
```

The binary itself is self-contained in terms of PHP code and the zphp runtime. The system library requirement is the same as deploying the zphp binary directly - the standalone executable is effectively the zphp binary with your bytecode appended.
