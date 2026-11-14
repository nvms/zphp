<?php
// an array or object key is refused by quiet element reads too: `??`,
// isset(), empty() and unset() of a nested element

$a = ['x' => [1]];
$tests = [
    'isset' => fn() => isset($a[[]]),
    'isset nested' => fn() => isset($a[[]][1]),
    'empty' => fn() => empty($a[[]]),
    'empty object key' => fn() => empty($a[new stdClass]),
    'empty nested' => fn() => empty($a[[]][1]),
    'empty under missing' => fn() => empty($a['missing'][[]]),
    'coalesce' => fn() => $a[[]] ?? 'default',
    'coalesce nested' => fn() => $a['x'][[]] ?? 'default',
];
foreach ($tests as $name => $test) {
    try {
        var_dump($test());
    } catch (Error $e) {
        echo $name, ": ", get_class($e), ": ", $e->getMessage(), "\n";
    }
}
try {
    unset($a[[]][1]);
} catch (Error $e) {
    echo get_class($e), ": ", $e->getMessage(), "\n";
}
var_dump(empty($a['x'][0]), empty($a['x'][5]), $a['x'][0] ?? 'none');
