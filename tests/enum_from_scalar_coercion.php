<?php
// regression: Enum::from()/tryFrom() coerce bool/null/float per PHP's loose-typing
// rules. only array/object are TypeErrors. the error type label is 'int' for
// int-backed enums and 'string|int' for string-backed. value rendering uses the
// coerced lookup (bool true -> "1"/1, false -> "0"/0, null -> "0"/0, float
// truncates to int)
enum S: string { case A = 'a'; case One = '1'; }
enum I: int { case One = 1; }

$cases = [
    ['S::from(true)',          fn() => S::from(true)],
    ['S::from(false)',         fn() => S::from(false)],
    ['I::from(true)',          fn() => I::from(true)],
    ['I::from(false)',         fn() => I::from(false)],
    ['I::from(1.5)',           fn() => I::from(1.5)],
    ['I::from(null)',          fn() => I::from(null)],
    ['S::from(null)',          fn() => S::from(null)],
    ['S::from(99)',            fn() => S::from(99)],
    ['S::from(2.5)',           fn() => S::from(2.5)],
    ['S::from([])',            fn() => S::from([])],
    ['I::from([])',            fn() => I::from([])],
    ['S::from(new stdClass)',  fn() => S::from(new stdClass)],
    ['I::from("abc")',         fn() => I::from("abc")],
    ['I::tryFrom(true)',       fn() => I::tryFrom(true)],
    ['I::tryFrom(99)',         fn() => I::tryFrom(99) ?? 'null'],
];
foreach ($cases as [$l, $f]) {
    try {
        $v = $f();
        echo "$l => " . (is_object($v) ? $v->name : (string)$v) . "\n";
    } catch (\Throwable $e) {
        echo "$l => " . get_class($e) . ": " . $e->getMessage() . "\n";
    }
}
