<?php
// regression: method calls + constructor invocations throw the same
// PHP-format ArgumentCountError as plain function calls. previously the
// method dispatch path and constructor dispatch path didn't check
// required_params, so missing args silently became null and downstream
// type checks (or worse, nothing) caught the bug late

class C {
    public function m(int $x, int $y) { return "$x,$y"; }
    public static function s(int $x, int $y) { return "$x,$y"; }
}

try { (new C)->m(1); }
catch (\ArgumentCountError $e) { echo "m: " . $e->getMessage() . "\n"; }

class E {
    public function __construct(int $x) { $this->x = $x; }
    public int $x = 0;
}

try { new E(); }
catch (\ArgumentCountError $e) { echo "ctor: " . $e->getMessage() . "\n"; }

class F {
    public function withDefault(int $a, int $b = 5, int $c = 10) {}
}

try { (new F)->withDefault(); }
catch (\ArgumentCountError $e) { echo "opt: " . $e->getMessage() . "\n"; }
