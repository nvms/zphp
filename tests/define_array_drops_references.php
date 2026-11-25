<?php
// define() stores an array's values, not its references, at any depth, and
// refuses an array that contains itself
$x = 7;
$y = [&$x, 'in' => [&$x, 2]];
define('QUX', $y);
$y[0] = 3;
$y['in'][0] = 4;
var_dump($x, QUX);
$z = QUX;
$z[0] = 9;
var_dump(QUX[0]);

$shared = [1, 2];
define('TWICE', [$shared, $shared]);
var_dump(TWICE);

$recursive = [];
$recursive[0] = &$recursive;
try {
    define('RECURSION', $recursive);
} catch (Throwable $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n";
}
$deep = ['a' => []];
$deep['a']['b'] = &$deep;
try {
    define('DEEP', $deep);
} catch (Throwable $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n";
}
var_dump(defined('RECURSION'), defined('DEEP'));
try {
    define('QUX', $recursive);
} catch (Throwable $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n";
}
