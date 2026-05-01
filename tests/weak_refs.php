<?php

// WeakReference::create + get
class Node { public string $name = ""; }
$n = new Node();
$n->name = "alice";
$ref = WeakReference::create($n);
echo $ref->get()->name . "\n";

// non-object passed: returns null
$bad = WeakReference::create($n);
$same = WeakReference::create($n);
// both refs point at same target
echo ($bad->get() === $same->get() ? "same" : "diff") . "\n";

// WeakMap basic operations
$map = new WeakMap();
$a = new Node(); $a->name = "a";
$b = new Node(); $b->name = "b";
$c = new Node(); $c->name = "c";

$map[$a] = "data-a";
$map[$b] = "data-b";
$map[$c] = "data-c";

echo count($map) . "\n";
echo $map[$a] . " | " . $map[$b] . " | " . $map[$c] . "\n";
echo (isset($map[$a]) ? "yes" : "no") . "\n";

unset($map[$b]);
echo count($map) . "\n";
echo (isset($map[$b]) ? "yes" : "no") . "\n";

// iteration: keys are objects, values are stored data
foreach ($map as $key => $value) {
    echo $key->name . "=" . $value . "\n";
}

// WeakMap with classes that have hooks (regression test)
class Tracked {
    public int $id;
    public function __construct(int $id) { $this->id = $id; }
}
$wm = new WeakMap();
$objs = [];
for ($i = 0; $i < 3; $i++) {
    $obj = new Tracked($i);
    $objs[] = $obj;
    $wm[$obj] = "value-" . $i;
}
echo count($wm) . "\n";
foreach ($wm as $k => $v) echo $k->id . "->" . $v . " ";
echo "\n";
