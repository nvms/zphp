<?php
// serialize() numbers values as php's var_hash does: R: for a reference
// met again (an array element or a property), r: for an object, and
// unserialize() rebuilds those references; __sleep, __serialize and
// Serializable report php's warnings and errors
error_reporting(E_ALL & ~E_DEPRECATED);
set_error_handler(function ($no, $msg) {
    echo "  [$no] $msg\n";
    return true;
});

function show($v) {
    $s = serialize($v);
    echo $s, "\n";
    var_dump(unserialize($s));
}

$a = [1, 2];
$a[1] = &$a[0];
show($a);

$o = new stdClass;
$o->a = 1;
$o->b = &$o->a;
show($o);

$x = 5;
$o2 = new stdClass;
$o2->p = &$x;
show([&$x, $o2]);

$self = [1];
$self[1] = &$self;
show($self);

$obj = new stdClass;
show([$obj, $obj, [$obj]]);
$obj->me = $obj;
show($obj);

$r = unserialize('a:2:{i:0;O:8:"stdClass":0:{}i:1;R:2;}');
$r[1] = 5;
var_dump($r);

ini_set('serialize_precision', 17);
echo serialize([0.1, 1/3, 1e100]), "\n";
ini_set('serialize_precision', 100);
echo serialize([0.1, -1.123456789]), "\n";
ini_set('serialize_precision', -1);

class Sleepy {
    public $a = 1;
    protected $b = 2;
    private $c = 3;
    public int $typed;
    public $list;
    function __construct(public $names = []) {}
    function __sleep() { return $this->names; }
}
foreach ([['a', 'b', 'c'], ['a', 'a'], ['missing'], ['typed'], [1], ['list'], 'nope'] as $names) {
    echo serialize(new Sleepy($names)), "\n";
}

class BadSerialize { function __serialize() { return 5; } }
class NullSerializable implements Serializable {
    function serialize() { return null; }
    function unserialize($d) {}
}
class IntSerializable implements Serializable {
    function serialize() { return 5; }
    function unserialize($d) {}
}
foreach ([new BadSerialize, [new NullSerializable, 'x'], new IntSerializable] as $v) {
    try {
        echo serialize($v), "\n";
    } catch (Throwable $e) {
        echo get_class($e), ": ", $e->getMessage(), "\n";
    }
}
$ns = new NullSerializable;
echo serialize([$ns, $ns]), "\n";

// an object unserialize() could not resolve keeps its name and round trips
$inc = unserialize("O:7:\"Missing\":2:{s:1:\"a\";i:1;s:4:\"\0*\0b\";i:2;}");
var_dump(get_class($inc));
echo serialize($inc), "\n";
