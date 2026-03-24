<?php
// 1. method call with spread
class Math {
    public function multiply($a, $b) { return $a * $b; }
    public function sum(...$nums) {
        $total = 0;
        foreach ($nums as $n) $total += $n;
        return $total;
    }
}
$m = new Math();
$args = [4, 5];
echo $m->multiply(...$args) . "\n";
echo $m->sum(...[1, 2, 3, 4]) . "\n";

// 2. static call with spread
class Util {
    public static function add($a, $b) { return $a + $b; }
}
$args2 = [5, 6];
echo Util::add(...$args2) . "\n";

// 3. argument forwarding through wrapper
function add($a, $b) { return $a + $b; }
function wrapper(...$args) {
    return add(...$args);
}
echo wrapper(10, 20) . "\n";

// 4. method forwarding
class Proxy {
    private $target;
    public function __construct($target) { $this->target = $target; }
    public function call($method, ...$args) {
        return $this->target->$method(...$args);
    }
}

// 5. mixed regular args + spread in method call
echo $m->multiply(3, ...[7]) . "\n";

// 6. multiple spreads in method call
$a = [2];
$b = [3];
echo $m->multiply(...$a, ...$b) . "\n";

// 7. nullsafe + spread
$nullObj = null;
echo var_export($nullObj?->multiply(...$args), true) . "\n";

echo "done\n";
