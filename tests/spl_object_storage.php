<?php
// covers: SplObjectStorage - attach, detach, contains, count, iteration,
//         getInfo, setInfo, offsetGet/Set/Exists/Unset, addAll, removeAll
error_reporting(E_ALL & ~E_DEPRECATED);

$storage = new SplObjectStorage();
$obj1 = new stdClass();
$obj1->name = "one";
$obj2 = new stdClass();
$obj2->name = "two";
$obj3 = new stdClass();
$obj3->name = "three";

// attach and contains
$storage->attach($obj1, "data1");
$storage->attach($obj2, "data2");
echo $storage->count() . "\n"; // 2
echo ($storage->contains($obj1) ? "true" : "false") . "\n"; // true
echo ($storage->contains($obj3) ? "true" : "false") . "\n"; // false

// detach
$storage->detach($obj1);
echo $storage->count() . "\n"; // 1
echo ($storage->contains($obj1) ? "true" : "false") . "\n"; // false

// re-attach with new data
$storage->attach($obj1, "new_data1");
echo $storage->count() . "\n"; // 2

// iteration
$names = [];
$storage->rewind();
while ($storage->valid()) {
    $cur = $storage->current();
    $names[] = $cur->name;
    $storage->next();
}
echo implode(",", $names) . "\n"; // two,one

// offsetGet (associated data)
$storage->rewind();
echo $storage[$storage->current()] . "\n"; // data2
echo $storage[$obj1] . "\n"; // new_data1
echo $storage[$obj2] . "\n"; // data2

// offsetExists / offsetUnset
echo (isset($storage[$obj1]) ? "true" : "false") . "\n"; // true
unset($storage[$obj1]);
echo (isset($storage[$obj1]) ? "true" : "false") . "\n"; // false
echo $storage->count() . "\n"; // 1

// offsetSet (alias for attach)
$storage[$obj3] = "data3";
echo $storage->count() . "\n"; // 2
echo ($storage->contains($obj3) ? "true" : "false") . "\n"; // true

// addAll
$storage2 = new SplObjectStorage();
$obj4 = new stdClass();
$obj4->name = "four";
$storage2->attach($obj4, "data4");
$storage2->attach($obj1, "data1_from_s2");
$storage->addAll($storage2);
echo $storage->count() . "\n"; // 4

// removeAll
$toRemove = new SplObjectStorage();
$toRemove->attach($obj2);
$toRemove->attach($obj3);
$storage->removeAll($toRemove);
echo $storage->count() . "\n"; // 2

// removeAllExcept
$storage->attach($obj2, "d2");
$storage->attach($obj3, "d3");
$keep = new SplObjectStorage();
$keep->attach($obj1);
$storage->removeAllExcept($keep);
echo $storage->count() . "\n"; // 1
echo ($storage->contains($obj1) ? "true" : "false") . "\n"; // true

echo "DONE\n";
