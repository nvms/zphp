# Installation

## Prebuilt binaries

Download the latest release for your platform from [GitHub Releases](https://github.com/nvms/zphp/releases).

| Platform | Binary |
|---|---|
| Linux x86_64 | `zphp-linux-x86_64` |
| Linux ARM64 | `zphp-linux-aarch64` |
| Linux x86_64 (musl) | `zphp-linux-x86_64-musl` |
| Linux ARM64 (musl) | `zphp-linux-aarch64-musl` |
| macOS Apple Silicon | `zphp-macos-aarch64` |


Move it somewhere in your PATH:

```
$ mv zphp-linux-x86_64 /usr/local/bin/zphp
$ chmod +x /usr/local/bin/zphp
```

## Building from source

Requires [Zig 0.17.1](https://ziglang.org/download/) and the system libraries below. Run build commands from the repository root.

**Ubuntu/Debian:**

```
$ sudo apt-get install -y libpcre2-dev libsqlite3-dev zlib1g-dev \
    libmysqlclient-dev libpq-dev libssl-dev libnghttp2-dev libcurl4-openssl-dev \
    libxml2-dev libicu-dev libgmp-dev libgd-dev libsodium-dev libldap2-dev
$ zig build -Doptimize=ReleaseFast
$ ./zig-out/bin/zphp --version
```

**macOS (Homebrew):**

```
$ brew install mysql-client libpq openssl@3 nghttp2 curl libxml2 icu4c gmp gd libsodium openldap
$ make release
$ ./zig-out/bin/zphp --version
```

Source builds put the executable at `zig-out/bin/zphp`. Add `zig-out/bin` to your PATH or use `./zig-out/bin/zphp` in the commands below. CI uses macOS 15; Zig 0.17.1 has known linking problems with the macOS 26 SDK.

## Verify it works

```
$ echo '<?php echo "hello from zphp\n";' > hello.php
$ zphp run hello.php
hello from zphp
```
