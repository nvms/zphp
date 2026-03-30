# Package Manager

zphp includes a package manager that uses [Packagist](https://packagist.org/), the same registry that Composer uses. Your existing Composer packages work with zphp.

## Quick start

```
$ zphp add slim/slim
$ zphp install
```

This creates a `composer.json`, resolves dependencies, downloads packages, and generates a `vendor/autoload.php` that works with zphp's autoloader.

## Commands

| Command | Description |
|---|---|
| `zphp install` | Install all packages from `composer.json` |
| `zphp add <package>` | Add a package and install it |
| `zphp remove <package>` | Remove a package |
| `zphp packages` | List installed packages |

## composer.json

zphp reads the same `composer.json` format you're used to:

```json
{
    "require": {
        "slim/slim": "^4.0",
        "slim/psr7": "^1.0"
    },
    "autoload": {
        "psr-4": {
            "App\\": "src/"
        }
    }
}
```

## Version constraints

| Constraint | Meaning |
|---|---|
| `^1.2.3` | >=1.2.3, <2.0.0 |
| `~1.2.3` | >=1.2.3, <1.3.0 |
| `>=1.0` | 1.0 or higher |
| `*` | Any version |
| `1.2.3` | Exact version |

## Lock file

`zphp install` generates a `zphp.lock` file that pins exact versions. Commit this to version control for reproducible installs.

## Autoloading

The generated `vendor/autoload.php` supports PSR-4 namespace mapping. Use it the same way you would with Composer:

```php
<?php

require 'vendor/autoload.php';

$app = Slim\Factory\AppFactory::create();
$app->get('/', function ($request, $response) {
    $response->getBody()->write("Hello");
    return $response;
});
$app->run();
```
