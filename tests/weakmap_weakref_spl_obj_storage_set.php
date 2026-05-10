<?php
$wm = new WeakMap;
$a = new stdClass;
$a->n = 1;
$b = new stdClass;
$b->n = 2;
$c = new stdClass;
$c->n = 3;

$wm[$a] = "value-a";
$wm[$b] = "value-b";
$wm[$c] = "value-c";

echo count($wm), "\n";
echo $wm[$a], "\n";
echo $wm[$b], "\n";
echo isset($wm[$a]) ? "y" : "n", "\n";
echo isset($wm[new stdClass]) ? "y" : "n", "\n";

unset($wm[$a]);
echo count($wm), "\n";
echo isset($wm[$a]) ? "y" : "n", "\n";

foreach ($wm as $key => $value) {
    echo $key->n, "=>", $value, "\n";
}

$wm = new WeakMap;
$o1 = new stdClass;
$o2 = new stdClass;
$wm[$o1] = "x";
$wm[$o2] = "y";
$wm[$o1] = "x-updated";
echo $wm[$o1], "\n";
echo count($wm), "\n";

$wm = new WeakMap;
echo count($wm), "\n";
foreach ($wm as $k => $v) echo "no\n";
echo isset($wm[new stdClass]) ? "y" : "n", "\n";

$o = new stdClass;
$o->id = 42;
$ref = WeakReference::create($o);
$got = $ref->get();
echo $got === $o ? "same" : "diff", "\n";
echo $got->id, "\n";

$obj = new stdClass;
$obj->v = "hello";
$ref = WeakReference::create($obj);
echo $ref->get()->v, "\n";

$ref2 = WeakReference::create($obj);
echo $ref2->get() === $obj ? "y" : "n", "\n";

$s = new SplObjectStorage;
$x = new stdClass; $x->n = 1;
$y = new stdClass; $y->n = 2;
$z = new stdClass; $z->n = 3;

$s->attach($x);
$s->attach($y);
$s->attach($z);
echo count($s), "\n";
echo $s->contains($x) ? "y" : "n", "\n";
echo $s->contains(new stdClass) ? "y" : "n", "\n";

$s->detach($x);
echo count($s), "\n";
echo $s->contains($x) ? "y" : "n", "\n";

$s = new SplObjectStorage;
$o = new stdClass;
$s[$o] = "metadata";
echo $s[$o], "\n";
echo $s->count(), "\n";

foreach ($s as $obj) echo "iter\n";

$a = new SplObjectStorage;
$b = new SplObjectStorage;
$o1 = new stdClass; $o1->n = 1;
$o2 = new stdClass; $o2->n = 2;
$o3 = new stdClass; $o3->n = 3;

$a->attach($o1);
$a->attach($o2);
$b->attach($o2);
$b->attach($o3);

$diff = clone $a;
$diff->removeAll($b);
foreach ($diff as $o) echo $o->n, " ";
echo "\n";

$intersect = clone $a;
$intersect->removeAllExcept($b);
foreach ($intersect as $o) echo $o->n, " ";
echo "\n";

$wm = new WeakMap;
class Tag {
    public function __construct(public string $name) {}
}
$t1 = new Tag("alpha");
$t2 = new Tag("beta");
$wm[$t1] = ["count" => 5];
$wm[$t2] = ["count" => 10];
echo $wm[$t1]["count"], "\n";
echo $wm[$t2]["count"], "\n";
echo count($wm), "\n";


$wm = new WeakMap;
$keep = new stdClass;
$wm[$keep] = "data";
echo $wm[$keep], "\n";

class HasCtor {
    public function __construct(public int $id) {}
}
$h1 = new HasCtor(1);
$h2 = new HasCtor(2);
$wm = new WeakMap;
$wm[$h1] = "first";
$wm[$h2] = "second";
echo $wm[$h1], " ", $wm[$h2], "\n";
echo count($wm), "\n";
