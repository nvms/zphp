<?php
// regression: sort/rsort/array_sum throw the PHP-format TypeError
// ('Argument #1 ($array) must be of type array, <type> given') on a
// non-array first arg. previously they silently returned false/0 which
// masked caller bugs. array_map throws on every non-array argument past
// position 1 with the same format
foreach (["str", 42, 3.14, true, null, new stdClass()] as $v) {
    try { sort($v); echo "sort: no-throw\n"; }
    catch (\TypeError $e) { echo "sort: " . $e->getMessage() . "\n"; }
    try { rsort($v); echo "rsort: no-throw\n"; }
    catch (\TypeError $e) { echo "rsort: " . $e->getMessage() . "\n"; }
    try { array_sum($v); echo "asum: no-throw\n"; }
    catch (\TypeError $e) { echo "asum: " . $e->getMessage() . "\n"; }
    try { array_map('strtoupper', $v); echo "amap: no-throw\n"; }
    catch (\TypeError $e) { echo "amap: " . $e->getMessage() . "\n"; }
}

// array_map with multiple arrays - position reported should be the failing one
$ok = [1, 2];
try { array_map(null, $ok, 'nope', $ok); }
catch (\TypeError $e) { echo "amap-pos: " . $e->getMessage() . "\n"; }
