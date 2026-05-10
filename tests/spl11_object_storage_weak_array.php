<?php
// SplObjectStorage iteration after attach/detach
$s = new SplObjectStorage;
$a = new stdClass; $a->n = "A";
$b = new stdClass; $b->n = "B";
$c = new stdClass; $c->n = "C";
$s[$a] = "data-a";
$s[$b] = "data-b";
$s[$c] = "data-c";

echo count($s), "\n"; // 3
foreach ($s as $obj) { echo $obj->n, ":", $s[$obj], " "; }
echo "\n";

unset($s[$b]);
echo count($s), "\n"; // 2
foreach ($s as $obj) { echo $obj->n, ":", $s[$obj], " "; }
echo "\n";

// re-attach b - goes to end
$s[$b] = "new-b";
foreach ($s as $obj) { echo $obj->n, ":", $s[$obj], " "; }
echo "\n";

// reattach existing - updates data, keeps position
$s[$a] = "updated-a";
foreach ($s as $obj) { echo $obj->n, ":", $s[$obj], " "; }
echo "\n";

// contains
var_dump(isset($s[$a]));
var_dump(isset($s[new stdClass]));

// offsetGet / offsetSet
$s[$a] = "via-array";
echo $s[$a], "\n";

// offsetUnset
unset($s[$a]);
echo count($s), "\n";

// addAll / removeAll
$s2 = new SplObjectStorage;
$d = new stdClass; $d->n = "D";
$e = new stdClass; $e->n = "E";
$s2[$d] = "dd";
$s2[$e] = "ee";
$s->addAll($s2);
echo count($s), "\n";

$s->removeAll($s2);
echo count($s), "\n";

// getInfo / setInfo (current iteration)
$s = new SplObjectStorage;
$s[$a] = "info-a";
$s[$b] = "info-b";
foreach ($s as $obj) {
    echo $s->getInfo(), " ";
}
echo "\n";

$s->rewind();
while ($s->valid()) {
    $s->setInfo($s->getInfo() . "!");
    $s->next();
}
foreach ($s as $obj) { echo $s->getInfo(), " "; }
echo "\n";

// WeakMap basic
$wm = new WeakMap;
$k1 = new stdClass;
$k2 = new stdClass;
$wm[$k1] = "val1";
$wm[$k2] = "val2";
echo count($wm), "\n";
echo $wm[$k1], " ", $wm[$k2], "\n";
var_dump(isset($wm[$k1]));

// WeakMap iteration
foreach ($wm as $k => $v) { echo $v, " "; }
echo "\n";

// WeakMap unset
unset($wm[$k1]);
echo count($wm), "\n";
var_dump(isset($wm[$k1]));

// WeakMap gc-eviction (architectural - simplified WeakMap)

// WeakReference
$obj = new stdClass; $obj->id = 99;
$ref = WeakReference::create($obj);
$got = $ref->get();
echo $got === $obj ? "same" : "diff", "\n";
echo $got->id, "\n";

// WeakReference gc-eviction (architectural)

// ArrayObject basic
$ao = new ArrayObject(["a" => 1, "b" => 2, "c" => 3]);
echo count($ao), "\n";
echo $ao["a"], "\n";

// getArrayCopy preserves keys
$copy = $ao->getArrayCopy();
print_r($copy);
var_dump(is_array($copy));

// ArrayObject with ARRAY_AS_PROPS flag
$ao2 = new ArrayObject(["x" => 10, "y" => 20], ArrayObject::ARRAY_AS_PROPS);
echo $ao2->x, "\n";
echo $ao2->y, "\n";
$ao2->z = 30;
echo $ao2["z"], "\n"; // also accessible as array
echo count($ao2), "\n";

// without ARRAY_AS_PROPS - dynamic prop on ArrayObject (architectural - PHP deprecates)

// getArrayCopy after modifications
$ao = new ArrayObject([1, 2, 3]);
$ao[] = 4;
$ao[10] = "x";
print_r($ao->getArrayCopy());

// ArrayObject keys preserved through getArrayCopy
$ao = new ArrayObject([5 => "a", 10 => "b", 20 => "c"]);
print_r($ao->getArrayCopy());
foreach ($ao as $k => $v) echo "$k=$v ";
echo "\n";
