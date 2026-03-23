<?php

// basic construction from array
$ao = new ArrayObject(["a" => 1, "b" => 2, "c" => 3]);
echo $ao->count() . "\n";

// offsetGet/offsetSet
echo $ao->offsetGet("a") . "\n";
echo $ao->offsetGet("b") . "\n";
$ao->offsetSet("d", 4);
echo $ao->count() . "\n";

// offsetExists
echo var_export($ao->offsetExists("a"), true) . "\n";
echo var_export($ao->offsetExists("z"), true) . "\n";

// offsetUnset
$ao->offsetUnset("b");
echo $ao->count() . "\n";
echo var_export($ao->offsetExists("b"), true) . "\n";

// append
$ao2 = new ArrayObject([10, 20]);
$ao2->append(30);
echo $ao2->count() . "\n";
echo $ao2->offsetGet(2) . "\n";

// getArrayCopy
$copy = $ao2->getArrayCopy();
echo count($copy) . "\n";
echo $copy[0] . "\n";
echo $copy[1] . "\n";
echo $copy[2] . "\n";

// construct with no args
$ao3 = new ArrayObject();
echo $ao3->count() . "\n";
$ao3->offsetSet("key", "value");
echo $ao3->offsetGet("key") . "\n";

// instanceof Countable
echo var_export($ao3 instanceof Countable, true) . "\n";

// numeric keys via append
$ao4 = new ArrayObject();
$ao4->append("first");
$ao4->append("second");
$ao4->append("third");
echo $ao4->count() . "\n";
echo $ao4->offsetGet(0) . "\n";
echo $ao4->offsetGet(1) . "\n";
echo $ao4->offsetGet(2) . "\n";
