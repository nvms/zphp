<?php
$s = new SplObjectStorage;
$a = new stdClass; $a->n = 1;
$b = new stdClass; $b->n = 2;
$c = new stdClass; $c->n = 3;

$s[$a] = "data-a";
$s[$b] = "data-b";
$s[$c] = "data-c";

echo count($s), "\n";
echo isset($s[$a]) ? "y" : "n", "\n";
echo $s[$a], "\n";
echo $s[$b], "\n";

foreach ($s as $key => $obj) {
    echo $key, ":", $obj->n, "=", $s[$obj], "\n";
}

unset($s[$a]);
echo count($s), "\n";
echo isset($s[$a]) ? "y" : "n", "\n";

$t = new SplObjectStorage;
$d = new stdClass; $d->n = 4;
$e = new stdClass; $e->n = 5;
$t[$d] = "d";
$t[$e] = "e";

$s->addAll($t);
echo count($s), "\n";
foreach ($s as $obj) {
    echo $obj->n, " ";
}
echo "\n";

$s->removeAll($t);
echo count($s), "\n";

$f = new stdClass; $f->n = 6;
$s[$f] = null;
echo isset($s[$f]) ? "y" : "n", "\n";
echo $s[$f] === null ? "null" : "x", "\n";

$g = new stdClass;
echo isset($s[$g]) ? "y" : "n", "\n";

$s->rewind();
while ($s->valid()) {
    echo $s->current()->n, "/", $s->getInfo() ?? "null", "\n";
    $s->next();
}

$h = new SplObjectStorage;
$o1 = new stdClass; $o1->id = 1;
$o2 = new stdClass; $o2->id = 2;
$h[$o1] = "x";
$h->attach($o2, "y");
echo count($h), "\n";
echo $h[$o2], "\n";
$h->detach($o1);
echo count($h), "\n";
echo isset($h[$o1]) ? "y" : "n", "\n";
