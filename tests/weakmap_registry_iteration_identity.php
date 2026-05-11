<?php
$wm = new WeakMap;
$a = new stdClass;
$b = new stdClass;
$c = new stdClass;

$wm[$a] = "a-data";
$wm[$b] = "b-data";
$wm[$c] = "c-data";

echo $wm[$a], "\n";
echo $wm[$b], "\n";
echo $wm[$c], "\n";
echo count($wm), "\n";

echo isset($wm[$a]) ? "y" : "n", "\n";
echo isset($wm[new stdClass]) ? "y" : "n", "\n";

unset($wm[$a]);
echo isset($wm[$a]) ? "y" : "n", "\n";
echo count($wm), "\n";

class Tag {
    public function __construct(public string $name) {}
}

$tags = [];
$wm = new WeakMap;
for ($i = 0; $i < 5; $i++) {
    $t = new Tag("tag$i");
    $tags[] = $t;
    $wm[$t] = "data-$i";
}

foreach ($tags as $t) {
    echo $t->name, "=>", $wm[$t], " ";
}
echo "\n";
echo count($wm), "\n";

$wm = new WeakMap;
$key = new stdClass;
$wm[$key] = ["nested", "array"];
print_r($wm[$key]);

$wm = new WeakMap;
$a = new stdClass; $a->id = 1;
$b = new stdClass; $b->id = 1;
$wm[$a] = "a";
$wm[$b] = "b";
echo $wm[$a], " ", $wm[$b], "\n";
echo count($wm), "\n";

$wm = new WeakMap;
$o = new stdClass;
$wm[$o] = "original";
$wm[$o] = "updated";
echo $wm[$o], "\n";
echo count($wm), "\n";

$wm = new WeakMap;
echo count($wm), "\n";
foreach ($wm as $k => $v) echo "no\n";
echo "iter-done\n";

$wm = new WeakMap;
$o1 = new stdClass; $o1->n = 1;
$o2 = new stdClass; $o2->n = 2;
$o3 = new stdClass; $o3->n = 3;
$wm[$o1] = "x";
$wm[$o2] = "y";
$wm[$o3] = "z";

$keys = [];
foreach ($wm as $k => $v) $keys[] = $k->n . ":" . $v;
sort($keys);
print_r($keys);

$wm = new WeakMap;
$o = new stdClass;
$o->val = 42;
$wm[$o] = $o->val;
echo $wm[$o], "\n";

class Registry {
    public WeakMap $data;
    public function __construct() {
        $this->data = new WeakMap;
    }
    public function attach(object $key, $value): void {
        $this->data[$key] = $value;
    }
    public function get(object $key): mixed {
        return $this->data[$key] ?? null;
    }
}

$reg = new Registry;
$x = new stdClass;
$reg->attach($x, "hello");
echo $reg->get($x), "\n";

$y = new stdClass;
echo $reg->get($y) ?? "null", "\n";

$wm = new WeakMap;
$o = new stdClass;
echo $wm[$o] ?? "default", "\n";

$wm = new WeakMap;
$a = new stdClass;
$b = new stdClass;
$wm[$a] = ["count" => 1];
$wm[$b] = ["count" => 2];
echo $wm[$a]["count"] + $wm[$b]["count"], "\n";

$wm = new WeakMap;
$x = new stdClass;
$wm->offsetSet($x, "via-method");
echo $wm[$x], "\n";
echo $wm->offsetGet($x), "\n";
echo $wm->offsetExists($x) ? "y" : "n", "\n";
$wm->offsetUnset($x);
echo $wm->offsetExists($x) ? "y" : "n", "\n";

$wm = new WeakMap;
$o = new stdClass;
$wm[$o] = "x";
$ref = WeakReference::create($o);
echo $ref->get() === $o ? "y" : "n", "\n";
echo $wm[$ref->get()], "\n";

$wm = new WeakMap;
$objs = [new stdClass, new stdClass, new stdClass];
foreach ($objs as $i => $o) $wm[$o] = $i * 10;
$total = 0;
foreach ($wm as $obj => $val) $total += $val;
echo $total, "\n";

$wm = new WeakMap;
$a = new stdClass; $a->id = "alpha";
$wm[$a] = "data-alpha";
echo $wm[$a], "\n";

class Wrapped {
    public function __construct(public int $id) {}
}

$wm = new WeakMap;
$w1 = new Wrapped(1);
$w2 = new Wrapped(2);
$wm[$w1] = "w1-meta";
$wm[$w2] = "w2-meta";

echo $wm[$w1], " ", $wm[$w2], "\n";

$arr = [];
foreach ($wm as $w => $meta) $arr[] = $w->id . ":" . $meta;
sort($arr);
print_r($arr);

echo $wm instanceof WeakMap ? "y" : "n", "\n";
echo $wm instanceof Countable ? "y" : "n", "\n";
echo $wm instanceof ArrayAccess ? "y" : "n", "\n";
