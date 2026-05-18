<?php
// regression: spl_object_id returns a unique monotonic identifier per
// object instance (not always 1). previously zphp left obj.id at 0 for
// any object not created via NativeContext.createObject, so all user-code
// 'new X' objects collapsed to the same id and SplObjectStorage / WeakMap
// keyed on id couldn't distinguish instances
$a = new stdClass();
$b = new stdClass();
$c = new stdClass();
$ids = [spl_object_id($a), spl_object_id($b), spl_object_id($c)];
echo "unique-3: " . (count(array_unique($ids)) === 3 ? 'y' : 'n') . "\n";
echo "monotonic: " . ($ids[0] < $ids[1] && $ids[1] < $ids[2] ? 'y' : 'n') . "\n";

// stable across reads
$o = new stdClass();
$id1 = spl_object_id($o);
$o->x = 1;
$o->y = 2;
$id2 = spl_object_id($o);
echo "stable: " . ($id1 === $id2 ? 'y' : 'n') . "\n";

// clone gets a new id
$d = new stdClass();
$e = clone $d;
echo "clone-differs: " . (spl_object_id($d) !== spl_object_id($e) ? 'y' : 'n') . "\n";

// user-defined class objects also get unique ids
class K {}
$arr = [];
for ($i = 0; $i < 5; $i++) $arr[] = new K();
$ids = array_map('spl_object_id', $arr);
echo "k-unique-5: " . (count(array_unique($ids)) === 5 ? 'y' : 'n') . "\n";

// SplObjectStorage keys on id; can store/retrieve distinct objects
$so = new SplObjectStorage();
$so[$a] = 'A';
$so[$b] = 'B';
$so[$c] = 'C';
echo "sos-count: " . count($so) . "\n";
echo "sos-a: " . $so[$a] . "\n";
echo "sos-b: " . $so[$b] . "\n";
