<?php
// valid string function
$c = Closure::fromCallable('strtoupper');
echo $c('hello'), "\n";

// non-existent throws TypeError
try {
    Closure::fromCallable('zzz_nonexistent');
} catch (\TypeError $e) {
    echo "te-fn: caught\n";
}

// array callable [object, method]
class A {
    public function pub(): string { return 'pub'; }
    private function priv(): string { return 'priv'; }
}
$a = new A;
$cm = Closure::fromCallable([$a, 'pub']);
echo $cm(), "\n";

// invalid method on array callable
try {
    Closure::fromCallable([$a, 'nope']);
} catch (\TypeError $e) {
    echo "te-method: caught\n";
}

// static method via [class, method]
class S { public static function ps(): string { return 'static'; } }
$cs = Closure::fromCallable(['S', 'ps']);
echo $cs(), "\n";

// static method via "Class::method" string
$cs2 = Closure::fromCallable('S::ps');
echo $cs2(), "\n";

// __invoke object
class Inv { public function __invoke($x) { return "i$x"; } }
$ci = Closure::fromCallable(new Inv);
echo $ci(5), "\n";

// non-invokable object throws
class NoInv {}
try {
    Closure::fromCallable(new NoInv);
} catch (\TypeError $e) {
    echo "te-obj: caught\n";
}

// bad array shape throws
try {
    Closure::fromCallable(['only-one']);
} catch (\TypeError $e) {
    echo "te-arr: caught\n";
}

// get_class on closure
$f = function() {};
echo get_class($f), "\n";
$arrow = fn() => 1;
echo get_class($arrow), "\n";
var_dump($f instanceof Closure);
var_dump($arrow instanceof Closure);

// ArrayObject ArrayAccess + Iterator interaction
$ao = new ArrayObject(['a' => 1, 'b' => 2]);
$ao['c'] = 3;
echo count($ao), "\n";
foreach ($ao as $k => $v) echo "$k=$v\n";
unset($ao['a']);
echo count($ao), "\n";
var_dump(isset($ao['x']));
var_dump(isset($ao['b']));
print_r($ao->getArrayCopy());
