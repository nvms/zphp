<?php
// a readonly property can't be fetched for writing: references to it are
// refused, except for an object, which is handed out as a copy
class Test {
    public readonly int $prop;
    public readonly array $arr;
    public readonly object $obj;
    public function __construct() {
        $this->prop = 1;
        $this->arr = [];
        $this->obj = new stdClass;
    }
}
class Late {
    public readonly int $bar;
    public function __construct(int &$bar) {
        try {
            $this->bar = &$bar;
        } catch (Error $e) {
            echo $e->getMessage(), "\n";
        }
    }
}
function byRef(&$ref) { $ref = 'set'; }
$t = new Test;
$ref = 5;
foreach ([
    fn() => $t->prop =& $ref,
    fn() => byRef($t->prop),
    fn() => $t->obj =& $ref,
    fn() => byRef($t->arr),
] as $f) {
    try {
        $f();
        echo "no error\n";
    } catch (Error $e) {
        echo $e->getMessage(), "\n";
    }
}
byRef($t->obj);
var_dump($t->obj);
$i = 42;
new Late($i);
try {
    foreach ($t as $k => &$v) {}
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
class Empty_ {
    public readonly int $x;
    public function fill() { $this->x = 1; }
}
$e = new Empty_;
foreach ($e as &$v) {}
echo "uninitialized ones are skipped\n";
$e->fill();
try {
    foreach ($e as &$v) {}
} catch (Error $err) {
    echo $err->getMessage(), "\n";
}
