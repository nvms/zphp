# Installation

## Prebuilt binaries

Download the latest release for your platform from [GitHub Releases](https://github.com/nvms/zphp/releases).

| Platform | Binary |
|---|---|
| Linux x86_64 | `zphp-linux-x86_64` |
| Linux ARM64 | `zphp-linux-aarch64` |
| macOS Apple Silicon | `zphp-macos-aarch64` |


Move it somewhere in your PATH:

```
$ mv zphp-linux-x86_64 /usr/local/bin/zphp
$ chmod +x /usr/local/bin/zphp
```

## Building from source

Requires [Zig 0.15.x](https://ziglang.org/download/) and a few system libraries.

**Ubuntu/Debian:**

```
$ sudo apt-get install -y libpcre2-dev libsqlite3-dev zlib1g-dev \
    libmysqlclient-dev libpq-dev libssl-dev libnghttp2-dev
$ zig build -Doptimize=ReleaseFast
$ ./zig-out/bin/zphp --version
```

**macOS (Homebrew):**

```
$ brew install mysql-client libpq openssl@3 nghttp2
$ make build
$ ./zig-out/bin/zphp --version
```

## Verify it works

```
$ echo '<?php echo "hello from zphp\n";' > hello.php
$ zphp run hello.php
hello from zphp
```
