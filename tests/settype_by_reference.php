<?php
// settype converts any by-reference place, and a typed property keeps its
// type: a value it can't take is php's TypeError for the reference

class Test {
    public int $x = 42;
    public ?string $s = null;
    public $plain = '7';
}

$test = new Test;
settype($test->x, 'string');
var_dump($test->x);
try {
    settype($test->x, 'array');
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
var_dump($test->x);
settype($test->plain, 'int');
var_dump($test->plain);
settype($test->s, 'bool');
var_dump($test->s);

$a = [1, '2.5', 'x' => null];
settype($a[0], 'string');
settype($a[1], 'float');
settype($a['x'], 'array');
settype($a['new'], 'int');
var_dump($a);

$v = '12abc';
var_dump(settype($v, 'integer'), $v);
settype($undefined, 'array');
var_dump($undefined);

function local() {
    $f = 3.9;
    settype($f, 'int');
    var_dump($f);
    $r = &$f;
    settype($r, 'string');
    var_dump($f);
}
local();

try {
    settype($v, 'nope');
} catch (ValueError $e) {
    echo $e->getMessage(), "\n";
}
