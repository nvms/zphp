<?php
// a reference to a string offset is refused before anything is bound

function attempt(callable $f) {
    try {
        $f();
    } catch (Error $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}

attempt(function () {
    $a = "string";
    $b = 'old';
    $b = &$a[1];
});
attempt(function () {
    $a = "aaa";
    $x = [&$a[1]];
});
attempt(function () {
    $a = "aaa";
    $x = ['k' => &$a[0]];
});
attempt(function () {
    $str = "foo";
    $str[0] = &$str[1];
});
attempt(function () {
    $a = ['s' => 'text'];
    $r = &$a['s'][0];
});

$a = "string";
$b = 'kept';
try {
    $b = &$a[1];
} catch (Error $e) {
    var_dump($a, $b);
}
