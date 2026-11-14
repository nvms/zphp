<?php
// ErrorException's filename without a line puts the line at 0
$cases = [
    [],
    ["a", 0, E_ERROR, null],
    ["b", 0, E_ERROR, null, null],
    ["c", 0, E_ERROR, null, 123],
    ["d", 0, E_ERROR, "abc.php"],
    ["e", 0, E_ERROR, "abc.php", null],
    ["f", 0, E_ERROR, "abc.php", 123],
];
foreach ($cases as $args) {
    $e = new ErrorException(...$args);
    var_dump($e->getMessage(), basename($e->getFile()), $e->getLine() > 0 ? ($e->getLine() === 123 ? 123 : 'here') : $e->getLine());
}
