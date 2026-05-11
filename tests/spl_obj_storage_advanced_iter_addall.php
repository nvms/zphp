<?php
$s = new SplObjectStorage;
$a = new stdClass; $a->n = 1;
$b = new stdClass; $b->n = 2;
$c = new stdClass; $c->n = 3;

$s[$a] = "data-a";
$s[$b] = "data-b";
$s[$c] = "data-c";

$s->rewind();
$keys = [];
while ($s->valid()) {
    $keys[] = $s->key() . ":" . $s->getInfo() . ":" . $s->current()->n;
    $s->next();
}
print_r($keys);

$s->rewind();
echo $s->key(), "\n";
echo $s->getInfo(), "\n";
echo $s->current()->n, "\n";
$s->next();
echo $s->key(), "\n";

$s->rewind();
$out = [];
foreach ($s as $k => $obj) {
    $out[] = "$k:" . $obj->n . "=" . $s[$obj];
}
print_r($out);

$s->rewind();
$total = 0;
foreach ($s as $obj) $total += $obj->n;
echo $total, "\n";

$s = new SplObjectStorage;
$x = new stdClass; $x->id = "x";
$y = new stdClass; $y->id = "y";

$s[$x] = "data-x";
$s[$y] = "data-y";

echo $s[$x], "\n";
echo $s[$y], "\n";

$s2 = new SplObjectStorage;
$z = new stdClass; $z->id = "z";
$s2[$z] = "data-z";

$s->addAll($s2);
echo count($s), "\n";
echo $s[$z], "\n";

$s->removeAll($s2);
echo count($s), "\n";
echo isset($s[$z]) ? "y" : "n", "\n";
echo isset($s[$x]) ? "y" : "n", "\n";

$all = new SplObjectStorage;
$objs = [];
for ($i = 0; $i < 5; $i++) {
    $o = new stdClass; $o->idx = $i;
    $objs[] = $o;
    $all[$o] = "item-$i";
}

$subset = new SplObjectStorage;
$subset[$objs[1]] = "x";
$subset[$objs[3]] = "y";

$all->removeAll($subset);
$ids = [];
foreach ($all as $obj) $ids[] = $obj->idx;
sort($ids);
print_r($ids);

$all = new SplObjectStorage;
for ($i = 0; $i < 5; $i++) {
    $o = new stdClass; $o->idx = $i;
    $objs[$i] = $o;
    $all[$o] = "item-$i";
}
$keep = new SplObjectStorage;
$keep[$objs[1]] = "k";
$keep[$objs[3]] = "k";

$all->removeAllExcept($keep);
$ids = [];
foreach ($all as $obj) $ids[] = $obj->idx;
sort($ids);
print_r($ids);

$s = new SplObjectStorage;
$a = new stdClass;
$s[$a] = "init";
$s->setInfo("modified");

$s->rewind();
echo $s->getInfo(), "\n";

$s = new SplObjectStorage;
$a = new stdClass; $a->v = 1;
$b = new stdClass; $b->v = 2;
$s[$a] = "x";
$s[$b] = "y";

$found = null;
foreach ($s as $obj) {
    if ($obj->v === 2) $found = $obj;
}
echo $found !== null ? $found->v : "none", "\n";

$s = new SplObjectStorage;
$a = new stdClass; $a->n = 1;
$b = new stdClass; $b->n = 2;
$s[$a] = "X";
$s[$b] = "Y";
echo $s->offsetGet($a), " ", $s->offsetGet($b), "\n";
echo $s->offsetExists($a) ? "y" : "n", "\n";
$s->offsetSet($a, "Z");
echo $s[$a], "\n";
$s->offsetUnset($a);
echo isset($s[$a]) ? "y" : "n", "\n";

$s = new SplObjectStorage;
echo count($s), "\n";
echo count($s) === 0 ? "empty" : "not", "\n";
$s[new stdClass] = "test";
echo count($s), "\n";

$s = new SplObjectStorage;
$os = [new stdClass, new stdClass, new stdClass];
foreach ($os as $i => $o) $s[$o] = "n-$i";

$snapshot = serialize($s);
echo strlen($snapshot) > 0 ? "y" : "n", "\n";

$s->rewind();
$collected = [];
while ($s->valid()) {
    $obj = $s->current();
    $collected[] = ($s[$obj] ?? "");
    $s->next();
}
sort($collected);
print_r($collected);

$s = new SplObjectStorage;
$alpha = new stdClass; $alpha->tag = "alpha";
$beta = new stdClass; $beta->tag = "beta";

$s[$alpha] = ["priority" => 10];
$s[$beta] = ["priority" => 5];

$tags = [];
foreach ($s as $obj) {
    $info = $s[$obj];
    $tags[$obj->tag] = $info["priority"];
}
print_r($tags);

$s = new SplObjectStorage;
$one = new stdClass; $one->key = "1";
$two = new stdClass; $two->key = "2";

$s[$one] = "v1";
$s[$two] = "v2";
$s->rewind();
$count = 0;
while ($s->valid()) {
    $count++;
    $s->next();
}
echo $count, "\n";
