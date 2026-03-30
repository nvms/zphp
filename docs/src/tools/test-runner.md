# Test Runner

`zphp test` is a built-in test runner. It discovers test files, runs them, and reports results.

## Usage

```
$ zphp test
```

This discovers and runs all test files in `tests/` and `test/` directories. Files must be named `*_test.php` or `*Test.php`.

To run a specific file:

```
$ zphp test tests/math_test.php
```

## Writing tests

Define functions prefixed with `test_`. Each function is run independently. If the function completes without error, it passes. If it throws an exception, it fails.

```php
<?php

function test_addition() {
    assert(1 + 1 === 2);
}

function test_string_concat() {
    $result = "hello" . " " . "world";
    assert($result === "hello world");
}

function test_array_push() {
    $arr = [1, 2, 3];
    $arr[] = 4;
    assert(count($arr) === 4);
    assert($arr[3] === 4);
}

function test_exception_handling() {
    $caught = false;
    try {
        throw new RuntimeException("test");
    } catch (RuntimeException $e) {
        $caught = true;
    }
    assert($caught);
}
```

```
$ zphp test tests/math_test.php
  pass  test_addition
  pass  test_string_concat
  pass  test_array_push
  pass  test_exception_handling

4 passed, 0 failed
```

## File-level tests

If a test file has no `test_` functions, the entire file is executed as a single test. It passes if it completes without error.

```php
<?php
// tests/smoke_test.php

require __DIR__ . '/../src/app.php';

$result = process_data([1, 2, 3]);
assert($result === 6, "Expected 6, got $result");
```
