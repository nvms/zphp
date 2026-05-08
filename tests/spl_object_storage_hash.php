<?php
// custom getHash override
class Keyed extends SplObjectStorage {
    public function getHash(object $obj): string {
        return $obj->id ?? 'def';
    }
}

$k = new Keyed;
$a = new stdClass; $a->id = 'one';
$b = new stdClass; $b->id = 'two';
$c = new stdClass; $c->id = 'one';

$k[$a] = 'A';
$k[$b] = 'B';
$k[$c] = 'C';

echo count($k), "\n"; // 2
echo $k[$a], "\n";    // C (a's slot got overwritten by c)
echo $k[$c], "\n";    // C
echo $k[$b], "\n";    // B

// iteration shows the latest object per slot
foreach ($k as $obj) echo $obj->id, "=", $k[$obj], "\n";

// detach via key collision
unset($k[$a]); // removes the 'one' slot
echo count($k), "\n"; // 1
var_dump(isset($k[$c])); // false (same hash as a)

// removeAll using subclass hash
$k2 = new Keyed;
$k2[$a] = 1; $k2[$b] = 2;
$rm = new Keyed;
$x = new stdClass; $x->id = 'one'; // collides with a
$rm[$x] = 'r';
$k2->removeAll($rm);
echo count($k2), "\n"; // 1
foreach ($k2 as $o) echo $o->id, "\n"; // two

// addAll with hash collision
$dst = new Keyed;
$dst[$a] = 'first';
$src = new Keyed;
$src[$c] = 'second'; // hash 'one' same as $a
$dst->addAll($src);
echo count($dst), "\n"; // 1
foreach ($dst as $o) echo $o->id, "=", $dst[$o], "\n"; // one=second

// default getHash: 32 hex chars, unique per object
$d = new SplObjectStorage;
echo strlen($d->getHash($a)), "\n"; // 32
echo $d->getHash($a) === $d->getHash($a) ? "stable\n" : "unstable\n";
echo $d->getHash($a) === $d->getHash($b) ? "same\n" : "diff\n";
