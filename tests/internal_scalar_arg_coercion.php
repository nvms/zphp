<?php
// an internal function's int, float, bool and string parameters take their
// arguments as php's argument parsing does: weak-mode coercion, the null
// deprecation, lossy-float deprecation and TypeErrors, in parameter order
error_reporting(E_ALL);
set_error_handler(function ($no, $msg) {
    echo "  [$no] $msg\n";
    return true;
});

class S { function __toString(): string { return "str"; } }

$calls = [
    fn() => escapeshellarg(12),
    fn() => escapeshellarg(1.5),
    fn() => escapeshellarg(true),
    fn() => escapeshellarg(new S),
    fn() => str_repeat("ab", "3"),
    fn() => str_repeat("ab", 2.0),
    fn() => str_repeat("ab", 2.5),
    fn() => str_repeat("ab", "2.5"),
    fn() => str_repeat("ab", "x"),
    fn() => str_repeat("ab", null),
    fn() => str_repeat([], 2),
    fn() => str_pad("a", 3, null),
    fn() => substr("abcdef", "1", 2.0),
    fn() => substr("abcdef", 1, null),
    fn() => in_array(1, [1], "yes"),
    fn() => uniqid(99999) !== "",
    fn() => strlen(1.0E+25),
    fn() => ucfirst(NAN),
    fn() => wordwrap("a b c", "2", "\n", 1),
    fn() => str_contains(123, 2),
    fn() => strrev(new stdClass),
    fn() => nl2br("a\nb", "0"),
    fn() => chunk_split("abcd", 2, 9),
    fn() => array_fill(0, "2", 1),
    fn() => range(1, 3, null),
    fn() => base64_encode(false),
    fn() => md5(123, 1),
    fn() => abs(PHP_INT_MAX + 1),
];
foreach ($calls as $i => $call) {
    try {
        echo "$i: ", var_export($call(), true), "\n";
    } catch (Throwable $e) {
        echo "$i: ", get_class($e), ": ", $e->getMessage(), "\n";
    }
}

// a native called by call_user_func is called by an internal function,
// which is never strict, whatever the calling file declares
var_dump(call_user_func('strlen', false), call_user_func_array('str_repeat', ["a", "2"]));
