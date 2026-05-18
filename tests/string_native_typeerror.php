<?php
// regression: strlen/strtoupper/strtolower TypeError reports the actual
// class name ('stdClass given', 'Closure given') instead of generic 'object
// given'. previously zphp emitted 'object given' for any object without
// __toString, and silently returned 13 for closures (length of internal
// '__closure_*' tag). implode reports the rejected type with PHP's
// ?array-prefixed message
$obj = new stdClass();
try { strlen($obj); }
catch (\TypeError $e) { echo "strlen-obj: " . $e->getMessage() . "\n"; }

$cl = function(){};
try { strlen($cl); }
catch (\TypeError $e) { echo "strlen-cl: " . $e->getMessage() . "\n"; }

try { strtoupper($obj); }
catch (\TypeError $e) { echo "strtoupper-obj: " . $e->getMessage() . "\n"; }

try { strtoupper($cl); }
catch (\TypeError $e) { echo "strtoupper-cl: " . $e->getMessage() . "\n"; }

try { strtolower($obj); }
catch (\TypeError $e) { echo "strtolower-obj: " . $e->getMessage() . "\n"; }

// implode rejects non-array second arg with ?array-prefixed message
// null gets a longer 'If argument #1 is of type string...' message in PHP 8.5
// that diverges from the 8.4 baseline - exclude it from the cross-version test
foreach ([42, "str", $obj, $cl, true] as $v) {
    try { implode(",", $v); }
    catch (\TypeError $e) { echo "implode: " . $e->getMessage() . "\n"; }
}

// objects with __toString stringify normally - no throw
class S { public function __toString(): string { return "ok"; } }
echo "len: " . strlen(new S()) . "\n";
echo strtoupper(new S()) . "\n";
