<p align="center">
  <img src="logo.svg" width="140" style="border-radius: 12px;" />
</p>

<h1 align="center">zphp</h1>

<p align="center">A Zig-based PHP runtime. What bun is to Node, zphp is to PHP.</p>

---

zphp replaces the entire PHP toolchain with a single fast binary. Runtime, package manager, test runner, formatter, and binary compiler - all in one.

| Traditional PHP | zphp |
|---|---|
| `php script.php` | `zphp run script.php` |
| `composer install` | `zphp install` |
| `composer require pkg` | `zphp add pkg` |
| `phpunit` | `zphp test` |
| `php-cs-fixer fix` | `zphp fmt` |
| _(no equivalent)_ | `zphp build` |

## Installation

Coming soon. zphp will be distributed as prebuilt binaries via GitHub releases.

```sh
# future
curl -fsSL https://zphp.dev/install | bash
```

## Usage

```sh
# run a PHP script
zphp run server.php

# start a new project
zphp init myapp

# install dependencies from composer.json
zphp install

# add a package
zphp add monolog/monolog

# run tests
zphp test

# format code
zphp fmt

# compile to a standalone binary
zphp build -o myapp
```

## PHP 8.x Support

zphp targets the PHP 8.x language surface that real-world code actually uses:

- Variables, constants, type juggling
- Functions, closures, arrow functions
- Classes, interfaces, traits, abstract classes
- Enums (backed and unit)
- Union types, intersection types, nullable types
- Named arguments
- Match expressions
- Fibers
- Attributes
- Readonly properties and classes
- First-class callable syntax
- String interpolation
- Array destructuring
- Generators
- Try/catch/finally with typed exceptions
- Namespaces and autoloading

## Package Manager

zphp reads `composer.json` and resolves dependencies from Packagist, the standard PHP package repository. Existing PHP projects work with zphp without changes to their dependency configuration.

## Build to Binary

`zphp build` compiles a PHP project into a standalone executable. The bytecode and a minimal runtime are bundled into a single binary that runs without zphp installed.

## Known Divergences from Zend

zphp targets the 95% of PHP semantics that matter. Some obscure Zend behaviors are intentionally not replicated. Divergences are documented here as they are identified.

---

This project is an experiment in AI-maintained open source - autonomously built, tested, and refined by AI with human oversight. Regular audits, thorough test coverage, continuous refinement. The emphasis is on high quality, rigorously tested, production-grade code.
