<?php
// memory_get_usage() counts arrays, strings and objects at the sizes php's
// allocator gives them, so scripts that budget memory see php's numbers
ini_set('memory_limit', '128M');

function measure(string $label, callable $make, int $low, int $high) {
    $before = memory_get_usage();
    $value = $make();
    $used = memory_get_usage() - $before;
    echo $label, ": ", ($used >= $low && $used <= $high) ? "ok" : "off", "\n";
    return $value;
}

// a packed array of 100000 ints is a table of 131072 16-byte slots
measure('range', fn () => range(1, 100000), 2000000, 2300000);
measure('array_fill', fn () => array_fill(0, 100000, 0), 2000000, 2300000);
measure('appended', function () {
    $a = [];
    for ($i = 0; $i < 100000; $i++) $a[] = $i;
    return $a;
}, 2000000, 2300000);
// a hash of 100000 string keys: 40 bytes a slot, plus the keys
measure('hash', function () {
    $a = [];
    for ($i = 0; $i < 100000; $i++) $a["k$i"] = $i;
    return $a;
}, 5000000, 11000000);
measure('string', fn () => str_repeat('x', 3 * 1024 * 1024), 3145728, 3200000);
measure('properties', function () {
    $o = new stdClass;
    for ($i = 0; $i < 100000; $i++) $o->{"p$i"} = $i;
    return $o;
}, 5000000, 11000000);

// a real size is whole 2MB chunks
var_dump(memory_get_usage(true) % (2 * 1024 * 1024));
