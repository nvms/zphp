<?php
$os = new SplObjectStorage;
$a = new stdClass;
$os[$a] = "attached";

echo $os[$a], "\n";

$b = new stdClass;
echo isset($os[$b]) ? "y" : "n", "\n";
try {
    $x = $os[$b];
    echo var_export($x, true), "\n";
} catch (\Throwable $e) {
    echo "ex:", get_class($e), "\n";
}

$os = new SplObjectStorage;
echo isset($os[new stdClass]) ? "y" : "n", "\n";

$ao = new ArrayObject(["a" => 1, "b" => 2]);
echo $ao["a"], "\n";
echo $ao->a ?? "null", "\n";

$ao->setFlags(ArrayObject::ARRAY_AS_PROPS);
echo $ao->a ?? "null", "\n";
echo $ao->b ?? "null", "\n";

$ao->c = 3;
echo $ao["c"], "\n";
echo $ao->c, "\n";

$ao = new ArrayObject(["a" => 1, "b" => 2], ArrayObject::ARRAY_AS_PROPS);
echo $ao->a, " ", $ao->b, "\n";

$ao = new ArrayObject(["k" => "v"], ArrayObject::STD_PROP_LIST);
echo $ao->getFlags(), "\n";
$ao->setFlags(ArrayObject::ARRAY_AS_PROPS);
echo $ao->getFlags(), "\n";

$ao = new ArrayObject();
$ao->setFlags(ArrayObject::ARRAY_AS_PROPS);
$ao["x"] = 10;
echo $ao->x, "\n";
$ao->y = 20;
echo $ao["y"], "\n";

$std = new ArrayObject([], ArrayObject::STD_PROP_LIST);
echo $std->getFlags(), "\n";

$ap = new ArrayObject([], ArrayObject::ARRAY_AS_PROPS);
echo $ap->getFlags(), "\n";

$both = new ArrayObject([], ArrayObject::STD_PROP_LIST | ArrayObject::ARRAY_AS_PROPS);
echo $both->getFlags(), "\n";

$ao = new ArrayObject(["a" => 1, "b" => 2], ArrayObject::ARRAY_AS_PROPS);
$ao->c = 3;
foreach ($ao as $k => $v) echo "$k=$v ";
echo "\n";

echo isset($ao->a) ? "y" : "n", "\n";
echo isset($ao->z) ? "y" : "n", "\n";

$cl = clone $ao;
$cl->a = 99;
echo $ao->a, " ", $cl->a, "\n";

echo ArrayObject::STD_PROP_LIST, "\n";
echo ArrayObject::ARRAY_AS_PROPS, "\n";

$os = new SplObjectStorage;
$x = new stdClass; $y = new stdClass; $z = new stdClass;
$os[$x] = 1;
$os[$y] = 2;
$os[$z] = 3;

$result = [];
foreach ($os as $key) {
    $result[] = $os[$key];
}
print_r($result);

echo count($os), "\n";

$total = 0;
foreach ($os as $k => $v) $total += $os[$v];
echo $total, "\n";

$os->offsetSet($x, "modified");
echo $os[$x], "\n";

$os->offsetSet($x, "again");
echo $os[$x], "\n";

$ao = new ArrayObject([1, 2, 3]);
echo count($ao), "\n";
foreach ($ao as $k => $v) echo "$k=$v ";
echo "\n";

$ao[] = 4;
$ao[] = 5;
echo count($ao), "\n";

$ao->append(6);
echo count($ao), "\n";

print_r($ao->getArrayCopy());

$flags = $ao->getFlags();
echo $flags, "\n";

class TaggedItem {
    public function __construct(public string $name) {}
}

$os = new SplObjectStorage;
$items = [];
for ($i = 0; $i < 5; $i++) {
    $t = new TaggedItem("item$i");
    $items[] = $t;
    $os[$t] = "tag$i";
}

foreach ($items as $i => $t) {
    echo $t->name, "->", $os[$t], " ";
}
echo "\n";

echo count($os), "\n";
$os->detach($items[0]);
echo count($os), "\n";

echo isset($os[$items[1]]) ? "y" : "n", "\n";
echo $os[$items[1]], "\n";
