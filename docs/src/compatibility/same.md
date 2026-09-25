# What Works the Same

zphp implements PHP language features including classes, namespaces, closures, exceptions, generators, enums, attributes, and fibers. It supports array copy-on-write, references, and parameter and return type declarations. Support for a feature does not imply parity in every edge case.

The standard library includes string and array functions, JSON, date/time, file I/O, PCRE2 regular expressions, HTTP functions, sessions, cURL, and PDO drivers for SQLite, MySQL, and PostgreSQL. Check the functions and extensions your application uses before switching runtimes.

## References and include scope

References can alias global variables:

```php
<?php
$value = 10;

function modify() {
    global $value;
    $ref =& $value;
    $ref = 20;
}

modify();
echo $value; // 20
```

`require` and `include` execute in the caller's scope. An included file can read and update caller variables, and return a value:

```php
// config.php
<?php
$host = 'localhost';
return ['port' => 3306];
```

```php
// app.php
<?php
$config = require __DIR__ . '/config.php';
echo $host; // localhost
```

## Memory management

Strings, arrays, objects, generators, fibers, and reference cells use reference counting. A cycle collector reclaims unreachable cycles. This applies within a running script, not only when a request ends.

## Test coverage

CI compares PHP script output with PHP 8.5 and runs multi-file examples. Separate jobs exercise Laravel, WordPress, Symfony, Doctrine, Composer, and PHPUnit, along with server behavior and standalone compilation. These harnesses cover specific scenarios, not full framework or package compatibility. The status of each built-in extension and its APIs is tracked in [Extension Compatibility](extensions.md).

Runtime CI runs on pushes and pull requests to `main`, excluding changes confined to `docs/`. See [What Works Differently](different.md) for compatibility cautions.
