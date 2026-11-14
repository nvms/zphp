<?php
// foreach over an object reads its properties as the loop reaches them:
// writes, additions and removals during the loop show

$obj = (object) ['foo' => 1, 'bar' => 2];
foreach ($obj as $val) {
    var_dump($val);
    $obj->bar = 42;
}

$obj = (object) ['a' => 1, 'b' => 2, 'c' => 3];
foreach ($obj as $k => $v) {
    echo "$k=$v\n";
    if ($k === 'a') {
        unset($obj->b);
        $obj->d = 4;
    }
}

$obj = (object) ['x', 'y'];
$obj->{'7'} = 'z';
foreach ($obj as $k => $v) var_dump($k, $v);

class P {
    public $a = 1;
    protected $b = 2;
    private $c = 3;
    public function inside() {
        foreach ($this as $k => $v) echo "$k=$v\n";
        var_dump(get_object_vars($this));
    }
}
class Q extends P {
    private $c = 4;
    public $d = 5;
}
$q = new Q;
$q->inside();
foreach ($q as $k => $v) echo "$k=$v\n";
unset($q->a);
$q->a = 9;
foreach ($q as $k => $v) echo "$k=$v\n";

class Shadow {
    private $prop = 'private';
    public function run() {
        foreach ($this as $k => $v) echo "$k => $v\n";
        var_dump(get_object_vars($this));
    }
}
#[AllowDynamicProperties]
class Shadowed extends Shadow {}
$s = new Shadowed;
$s->prop = 'dynamic';
$s->run();
var_dump(get_object_vars($s));

class Hooked {
    public $plain = 'plain';
    public $virtual { get { echo "get virtual\n"; return 'v'; } }
    private $store = 1;
    public $ref { &get { echo "get ref\n"; return $this->store; } }
    public $byVal { get => 'by value'; }
}
$h = new Hooked;
foreach ($h as $k => $v) echo "$k => $v\n";
foreach ($h as $k => &$v) {
    if ($k === 'ref') {
        $v = 2;
        break;
    }
}
unset($v);
var_dump($h->ref);
try {
    foreach ($h as $k => &$v) {
        echo "$k\n";
    }
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}

$keys = (object) ["\0A\0b" => 42, "\0*\0c" => 24];
foreach ($keys as $k => $v) var_dump($k, $v);
