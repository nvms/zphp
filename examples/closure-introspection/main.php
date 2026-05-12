<?php
// covers: Closure inspection via ReflectionFunction, getClosureScopeClass,
//   getClosureThis, getClosureUsedVariables, static-closure detection,
//   binding round-trips

class Counter {
    private int $n = 0;
    public function makeIncrementer(): Closure {
        return function (int $step = 1) {
            $this->n += $step;
            return $this->n;
        };
    }
}

echo "=== closure has bound \$this when produced inside a method ===\n";
$c = new Counter();
$inc = $c->makeIncrementer();
echo $inc() . "\n";
echo $inc(5) . "\n";
echo $inc(2) . "\n";

$rf = new ReflectionFunction($inc);
$scope = $rf->getClosureScopeClass();
echo "scope class: " . ($scope ? $scope->getName() : "none") . "\n";
$bound = $rf->getClosureThis();
echo "bound \$this is Counter: " . ($bound instanceof Counter ? "yes" : "no") . "\n";

echo "\n=== captured variables ===\n";
$base = 100;
$tax = 0.10;
$with_extras = function (int $n) use ($base, $tax) {
    return $base + $n + (int)round($n * $tax);
};
$rf = new ReflectionFunction($with_extras);
$used = $rf->getClosureUsedVariables();
ksort($used);
foreach ($used as $k => $v) echo "  $k = $v\n";

echo "\n=== static closure has no \$this ===\n";
$static = static function () { return 'no this'; };
$rf = new ReflectionFunction($static);
$bound = $rf->getClosureThis();
echo "bound \$this: " . var_export($bound, true) . "\n";
echo "result: " . $static() . "\n";

echo "\n=== binding adds a scope ===\n";
class Vault {
    private string $secret = 'shh';
}
$reader = static fn(Vault $v) => $v->secret;
// static + binding to null scope and class for private access
$bound = Closure::bind($reader, null, Vault::class);
echo "private read: " . $bound(new Vault()) . "\n";

echo "\n=== first-class callable from method invokes correctly ===\n";
class Stringify {
    public function wrap(string $s): string { return "<{$s}>"; }
}
$s = new Stringify();
$w = $s->wrap(...);
echo $w("hello") . "\n";

echo "\n=== timezone_identifiers_list now lists tz ids ===\n";
$ids = timezone_identifiers_list();
echo "non-empty: " . (count($ids) > 0 ? "yes" : "no") . "\n";
echo "includes UTC: " . (in_array('UTC', $ids) ? "yes" : "no") . "\n";
echo "includes Asia/Tokyo: " . (in_array('Asia/Tokyo', $ids) ? "yes" : "no") . "\n";

echo "\ndone\n";
