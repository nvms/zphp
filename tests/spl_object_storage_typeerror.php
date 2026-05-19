<?php
// regression: SplObjectStorage::offsetExists/offsetGet/offsetSet/offsetUnset
// strictly require object keys and throw TypeError on any other type. zphp
// previously returned null/false silently which let bugs slip past
$so = new SplObjectStorage();
$o = new stdClass();
$so[$o] = 'v';

// offsetExists with non-object
try { isset($so['k']); }
catch (\TypeError $e) { echo "e: " . $e->getMessage() . "\n"; }

try { isset($so[42]); }
catch (\TypeError $e) { echo "e2: " . $e->getMessage() . "\n"; }

// offsetGet with non-object
try { $so['k']; }
catch (\TypeError $e) { echo "g: " . $e->getMessage() . "\n"; }

// offsetSet with non-object key
try { $so['k'] = 'v'; }
catch (\TypeError $e) { echo "s: " . $e->getMessage() . "\n"; }

// offsetUnset with non-object key
try { unset($so['k']); }
catch (\TypeError $e) { echo "u: " . $e->getMessage() . "\n"; }

// object key still works normally
echo $so[$o] . "\n";
var_dump(isset($so[$o]));
