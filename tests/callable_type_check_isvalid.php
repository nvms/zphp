<?php
// regression: 'callable' parameter type-check validates that the value is
// actually invokable (function name resolves, [obj,method] real, etc.)
// and throws TypeError at the call site if not. previously zphp accepted
// any string/array/object then crashed inside the call with 'undefined
// function'. also is_callable's 3rd by-ref param receives the resolved
// callable name
function take_cb(callable $cb): mixed { return $cb(5); }

echo take_cb('intval') . "\n";
echo take_cb(fn($x) => $x * 2) . "\n";

try { take_cb('nope_fn'); }
catch (\TypeError $e) { echo "te: " . $e->getMessage() . "\n"; }

class C {
    public function m($x) { return $x * 3; }
    public static function s($x) { return $x * 4; }
}
echo take_cb([new C, 'm']) . "\n";
echo take_cb([C::class, 's']) . "\n";

try { take_cb([new C, 'noMethod']); }
catch (\TypeError $e) { echo "te2: " . $e->getMessage() . "\n"; }

// is_callable 3rd arg gets the resolved name
$valid = is_callable('strlen', false, $name);
echo "$valid:$name\n";

$valid = is_callable('nope_fn', false, $name);
echo "$valid:$name\n";   // still populated, but invalid
