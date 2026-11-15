<?php
// ++ and -- on an appended element step the null that is appended

$a = [];
var_dump(++$a[]);
var_dump($a[]++);
var_dump(--$a[]);
var_dump($a);

$nested = ['list' => [5 => 'x']];
$nested['list'][]++;
$nested['new'] = [];
++$nested['new'][];
var_dump($nested);

$full = [PHP_INT_MAX => 0];
foreach ([
    fn () => ++$full[],
    fn () => $full[]++,
    fn () => $full[] .= 'x',
] as $f) {
    try {
        var_dump($f());
    } catch (Error $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}

$s = 'str';
try {
    $s[]++;
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
