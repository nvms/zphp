<?php

// closure returned from function preserves use bindings
function makeAdder($n) {
    return function($x) use ($n) {
        return $x + $n;
    };
}

$add5 = makeAdder(5);
$add10 = makeAdder(10);
echo $add5(3) . "\n";
echo $add10(3) . "\n";

// closure in method context ($this binding)
class Greeter {
    public $prefix;

    public function __construct($prefix) {
        $this->prefix = $prefix;
    }

    public function getGreeter() {
        return function($name) {
            return $this->prefix . " " . $name;
        };
    }
}

$g = new Greeter("Hello");
$fn = $g->getGreeter();
echo $fn("world") . "\n";

// closure as array value
$ops = [
    "add" => function($a, $b) { return $a + $b; },
    "mul" => function($a, $b) { return $a * $b; },
];
echo $ops["add"](3, 4) . "\n";
echo $ops["mul"](3, 4) . "\n";

// nested closures
$outer = function($x) {
    return function($y) use ($x) {
        return $x * $y;
    };
};
$inner = $outer(5);
echo $inner(6) . "\n";

// arrow function captures outer scope automatically
$multiplier = 3;
$fn2 = fn($x) => $x * $multiplier;
echo $fn2(7) . "\n";

// immediately invoked closure with use
$base = 100;
$result = (function() use ($base) {
    return $base + 50;
})();
echo $result . "\n";
