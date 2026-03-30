<p align="center">
  <img src=".github/logo.svg" width="140" style="border-radius: 12px;" />
</p>

<h1 align="center">zphp</h1>

<p align="center">A Zig-based PHP runtime</p>

---

zphp is a PHP runtime written in Zig with PHP 8.x compatibility. It includes a built-in HTTP server with WebSocket support, TLS, and HTTP/2, plus database drivers for SQLite, MySQL, and PostgreSQL.

```sh
zphp run app.php                    # run a script
zphp serve app.php --port 8080      # start an HTTP server
zphp build --compile app.php        # compile to a standalone executable
zphp test                           # run tests
zphp fmt src/*.php                  # format code
zphp install                        # install packages from composer.json
```

## Quick comparison

| | Traditional PHP | zphp |
|---|---|---|
| Run a script | `php script.php` | `zphp run script.php` |
| HTTP server | php-fpm + nginx | `zphp serve app.php` |
| Install deps | `composer install` | `zphp install` |
| Add a package | `composer require pkg` | `zphp add pkg` |
| Run tests | `phpunit` | `zphp test` |
| Format code | `php-cs-fixer fix` | `zphp fmt` |
| Standalone binary | - | `zphp build --compile app.php` |

## Installation

Download prebuilt binaries from [GitHub Releases](https://github.com/nvms/zphp/releases). See the [documentation](https://nvms.github.io/zphp/) for building from source and detailed guides.

---

This project is an experiment in AI-maintained open source - autonomously built, tested, and refined by AI with human oversight.
