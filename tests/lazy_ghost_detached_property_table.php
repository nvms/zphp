<?php
// a ghost whose property table exists (a listing built it) shares that
// table with the initialization snapshot: the first dynamic property write
// in its initializer separates it, and the copy keeps the declared values
// of that moment, which every listing shows from then on

#[AllowDynamicProperties]
class C {
    public int $b = 1;
    public $c = 5;
    protected $p = 'p';
    private $q = 'q';
    public function __construct() {
        $this->a = 1;
        $this->b = 3;
        $this->c = 6;
        $this->p = 'P';
        $this->q = 'Q';
    }
}

function show(string $label, object $obj) {
    echo "-- $label\n";
    var_dump($obj);
    var_dump(get_object_vars($obj));
    var_dump((array) $obj);
    foreach ($obj as $k => $v) echo "$k=", json_encode($v), "\n";
    echo json_encode($obj), "\n";
    echo $obj->b, " ", $obj->c, "\n";
}

$rc = new ReflectionClass(C::class);

$obj = $rc->newLazyGhost(function ($o) { $o->__construct(); });
var_dump($obj);
$obj->a += 1;
show('assign-op after a listing', $obj);

$obj->b = 10;
unset($obj->c);
$obj->z = 'z';
show('writes after', $obj);

$copy = clone $obj;
$copy->b = 20;
show('clone', $copy);

// without a listing first the table follows the slots
$obj = $rc->newLazyGhost(function ($o) { $o->__construct(); });
$obj->a += 1;
show('no listing', $obj);

// a declared write alone doesn't separate
$obj = $rc->newLazyGhost(function ($o) { $o->b = 7; $o->c = 8; });
var_dump($obj);
var_dump($obj->b);
show('declared writes only', $obj);

// unsetting a declared property doesn't separate, unsetting a dynamic one
// does
$obj = $rc->newLazyGhost(function ($o) { unset($o->c); $o->b = 4; $o->c = 9; });
var_dump($obj);
var_dump($obj->b);
show('declared unset', $obj);
$obj = $rc->newLazyGhost(function ($o) { $o->b = 4; unset($o->nothing); $o->b = 5; });
var_dump($obj);
var_dump($obj->b);
show('dynamic unset', $obj);

// a failed initializer puts the shared table back
$obj = $rc->newLazyGhost(function ($o) {
    $o->__construct();
    throw new Exception('failed');
});
var_dump($obj);
try {
    $obj->a = 5;
} catch (Exception $e) {
    echo $e->getMessage(), "\n";
}
var_dump($obj);

// resetting a detached object leaves its table without the declared ones
$obj = $rc->newLazyGhost(function ($o) { $o->__construct(); });
var_dump($obj);
$obj->a = 1;
$rc->resetAsLazyGhost($obj, function ($o) { $o->d = 'd'; $o->b = 2; });
var_dump($obj->b);
show('reset', $obj);
