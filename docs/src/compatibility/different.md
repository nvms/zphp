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

The `global $var` keyword works for simple cases: reading and writing global variables from inside functions. However, zphp doesn't support full reference semantics for globals. Changes to a global inside a function are written back, but creating a reference alias between a local and a global isn't supported.

## Pass-by-reference

Pass-by-reference works for simple variable arguments:

```php
function increment(&$val) {
    $val++;
}

$x = 5;
increment($x);
echo $x; // 6
```

Passing expressions or nested access paths by reference (e.g., `foo($arr['key'])` with a `&$param`) is not supported.

## Type hint enforcement

Type hints on function parameters and return values are enforced, matching PHP's behavior. One difference: zphp's fast execution path skips type checking for performance. If your code relies on type errors being thrown in deeply nested hot loops, the behavior may differ.

## Auto-vivification

In PHP 8.4, assigning to an index on a scalar value throws a TypeError:

```php
$x = "hello";
$x[] = 1; // PHP 8.4: TypeError
```

In zphp, this silently fails - the assignment is a no-op. Nested auto-vivification of missing keys (creating intermediate arrays) works correctly.

## require scope

`require` and `include` execute the included file in an isolated scope. Functions and classes defined in the included file are registered globally (as in PHP), but local variables from the included file don't leak into the calling scope.

## strtotime

`strtotime()` supports common formats, relative modifiers ("next Thursday", "+2 days"), ordinal modifiers, and timezone suffixes (UTC, GMT, EST, PST, numeric offsets, RFC 2822). Timezone parsing is recognition only - internal timestamps are always UTC.

## Named arguments

Named arguments work for user-defined functions and approximately 80 common built-in functions. Built-in functions not on this list fall back to positional argument passing.
