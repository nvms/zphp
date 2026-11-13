<?php
// a write that makes false an array is deprecated, and unset() of an offset
// refuses containers that can't have one

set_error_handler(function ($no, $msg, $file, $line) {
    echo "  [$no] $msg (line $line)\n";
    return true;
});

echo "local\n";
$false = false;
$false[] = 42;
$f2 = false;
$f2['k']['j'] = 1;
function f(bool $a) {
    $a[] = 1;
    return $a;
}
var_dump(f(false));

echo "element\n";
$arr = [0 => [0 => false]];
$arr[0][0][0][] = 42;
$arr2 = ['x' => false];
$arr2['x']['y'] = 1;

echo "by name\n";
$name = 'dyn';
$$name = false;
$$name[] = 1;
var_dump($dyn);

echo "property\n";
class C {
    public $p = false;
    private static $s = false;
    function go() {
        $this->p[] = 1;
        self::$s[] = 2;
        return [$this->p, self::$s];
    }
}
var_dump((new C)->go());

echo "unset\n";
unset($undefined[0]);
$values = [null, false, true, 1, 3.14, "str", new stdClass];
foreach ($values as $value) {
    foreach ([1, 2] as $depth) {
        $x = $value;
        try {
            if ($depth == 1) {
                unset($x[0]);
            } else {
                unset($x[0][0]);
            }
            echo "  ok ", gettype($x), "\n";
        } catch (Error $e) {
            echo "  ", get_class($e), ": ", $e->getMessage(), "\n";
        }
    }
}
