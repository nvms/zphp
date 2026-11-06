<?php
// __debugInfo() returning null is an empty table; anything else but an array
// is a fatal error past any try/catch
class N { public $p = 1; public function __debugInfo() { return null; } }
var_dump(new N);
print_r(new N);
echo "\n";
class C { public function __debugInfo() { return 0; } }
try {
    var_dump(new C);
} catch (Throwable $e) {
    echo "not reached\n";
}
echo "not reached either\n";
