<?php
// a by-reference foreach over a variable iterates what the variable holds at
// each step (FE_FETCH_RW): another object put there is iterated from its
// start, a lazy one initializing first, an array or a scalar likewise

class P {
    public $a = 1;
    public $b = 2;
}
class Q {
    public $x = 'x';
    public $y = 'y';
}

$obj = new P;
$n = 0;
foreach ($obj as $k => &$v) {
    echo "$k\n";
    if ($n++ === 0) $obj = new Q;
}
unset($v);
var_dump($obj);

$obj = new P;
$n = 0;
foreach ($obj as $k => &$v) {
    echo "$k\n";
    if ($n++ === 0) $obj = [10, 20, 30];
}
unset($v);

$obj = new P;
foreach ($obj as $k => &$v) {
    echo "$k\n";
    $obj = 5;
}
unset($v);

$arr = [1, 2];
$n = 0;
foreach ($arr as $k => &$v) {
    echo "$k\n";
    if ($n++ === 0) $arr = new Q;
}
unset($v);

$rc = new ReflectionClass(Q::class);
$obj = new P;
$n = 0;
foreach ($obj as $k => &$v) {
    echo "$k\n";
    if ($n++ === 0) $obj = $rc->newLazyGhost(function ($o) {
        echo "init\n";
        $o->x = 'gx';
    });
}
unset($v);
var_dump($obj);

$obj = new P;
try {
    foreach ($obj as &$v) {
        $obj = $rc->newLazyGhost(function ($o) {
            throw new Exception("failed");
        });
    }
} catch (Exception $e) {
    echo $e->getMessage(), "\n";
}
unset($v);
var_dump($rc->isUninitializedLazyObject($obj));
