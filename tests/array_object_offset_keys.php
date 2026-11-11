<?php
// ArrayObject and ArrayIterator turn an offset into a key as php's
// get_hash_key does: null is "" (deprecated), a resource its id (with a
// warning), a float its integer, a bool 0 or 1, and anything else a TypeError
// naming the access
set_error_handler(function ($no, $msg) {
    echo "[$no] $msg\n";
    return true;
});

$ao = new ArrayObject([1, 2, 3]);
foreach (['read' => fn() => $ao[[]], 'write' => function () use ($ao) { $ao[[]] = 1; },
    'ref' => function () use ($ao) { $r =& $ao[new stdClass]; }, 'isset' => fn() => isset($ao[[]]),
    'empty' => fn() => empty($ao[new stdClass]), 'unset' => function () use ($ao) { unset($ao[[]]); },
    'offsetGet' => fn() => $ao->offsetGet([]), 'offsetSet' => fn() => $ao->offsetSet([], 1),
    'offsetExists' => fn() => $ao->offsetExists([]), 'offsetUnset' => fn() => $ao->offsetUnset([])] as $what => $f) {
    try {
        var_dump($f());
    } catch (TypeError $e) {
        echo "$what: ", $e->getMessage(), "\n";
    }
}

class Sub extends ArrayIterator {}
$it = new Sub(['' => 'empty', 1 => 'one', 0 => 'zero', 5 => 'five']);
try {
    $it[[]];
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
try {
    unset($it[[]]);
} catch (TypeError $e) {
    echo $e->getMessage(), "\n";
}
var_dump($it[null], $it[true], $it[false], $it[5.0], $it[5.5], isset($it[null]));
$fp = fopen(__FILE__, 'r');
var_dump($it[$fp] ?? 'none', isset($it[$fp]));
$it[$fp] = 'res';
var_dump($it->getArrayCopy());
fclose($fp);

$n = new ArrayObject();
$n[null]['x'] = 'y';
$n[null] = 'z';
unset($n[null]);
var_dump($n->getArrayCopy());

// a reference to an element is a reference into the storage
$ao = new ArrayObject(['x' => 1]);
$r =& $ao['x'];
$r = 5;
$q =& $ao['new'];
$q = 7;
var_dump($ao['x'], $ao->getArrayCopy());
