# What Works Differently

zphp is not a drop-in replacement for every PHP program. There are places where behavior differs from PHP 8.4, either by design or as a current limitation. This page documents the ones you're most likely to notice.

## Copy-on-assign vs copy-on-write

PHP uses copy-on-write for arrays: assigning an array to a new variable shares the underlying data until one of them is modified. zphp uses copy-on-assign: the array is fully cloned at the point of assignment.

```php
$a = [1, 2, 3];
$b = $a;  // PHP: shared until modified. zphp: full copy now.
```

In practice, this rarely matters. The semantics are identical from your code's perspective - both produce independent copies. The difference is when the copy happens, which can affect memory usage if you're assigning very large arrays without modifying them.

## Global variables

The `global` keyword works for reading and writing:

```php
$counter = 0;

function increment() {
    global $counter;
    $counter++;  // this works in zphp
}

increment();
echo $counter; // 1
```

What doesn't work is creating a reference alias between a local and a global:

```php
$value = 10;

function modify() {
    global $value;
    $ref = &$value;  // reference aliasing - not supported in zphp
    $ref = 20;
}

modify();
echo $value; // PHP: 20. zphp: 10.
```

Direct reads and writes through the `global` keyword work. Indirect modification through reference aliases does not.

## Pass-by-reference

Pass-by-reference works for variables and single-level array element access, matching PHP. What doesn't work:

```php
function modify(&$val) { $val = 'changed'; }

modify($obj->prop);          // not supported - property access
modify($obj->items['key']);   // not supported - property + array access
modify($arr['a']['b']);       // not supported - nested array access
```

Note that passing an entire array by reference and modifying nested keys inside the function works fine:

```php
function set_nested(array &$arr) { $arr['a']['b'] = 99; } // works
```

The limitation is specifically about what you can pass as the ref argument, not what you can do inside the function.

## Type hint enforcement

Type hints on function parameters and return values are enforced, matching PHP's behavior. One difference: zphp's fast execution path skips type checking for performance. If your code relies on type errors being thrown in deeply nested hot loops, the behavior may differ.

## Auto-vivification

In PHP 8.4, assigning to an index on a scalar value throws a TypeError:

```php
$x = "hello";
$x[] = 1; // PHP 8.4: TypeError
```

In zphp, this silently fails - the assignment is a no-op. Nested auto-vivification of missing keys (creating intermediate arrays) works correctly.

## require and include scope

In PHP, `require` shares the calling scope. Variables defined in the required file are visible in the caller, and vice versa:

```php
// config.php
$db_host = 'localhost';

// app.php
require 'config.php';
echo $db_host; // PHP: 'localhost'
```

In zphp, `require` executes in an isolated scope. Functions and classes are registered globally (as in PHP), but local variables don't cross the boundary. The example above would not work - `$db_host` would be undefined in `app.php`.

**What still works:**

```php
// config.php
return ['host' => 'localhost', 'port' => 3306];

// app.php
$config = require 'config.php'; // return values work fine
```

```php
// helpers.php
function formatDate($ts) { return date('Y-m-d', $ts); }

// app.php
require 'helpers.php';
echo formatDate(time()); // globally registered functions work
```

Most modern PHP frameworks (Laravel, Symfony, etc.) use return-based config files and autoloaded classes, both of which work correctly.

## strtotime

`strtotime()` supports common formats, relative modifiers ("next Thursday", "+2 days"), ordinal modifiers, and timezone suffixes (UTC, GMT, EST, PST, numeric offsets, RFC 2822). Timezone parsing is recognition only - internal timestamps are always UTC.

## Named arguments

Named arguments work for user-defined functions and approximately 80 common built-in functions. Built-in functions not on this list fall back to positional argument passing.
