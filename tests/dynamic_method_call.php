<?php
// covers: dynamic method calls ($obj->{$method}()), __call fallback, spread args

class Greeter {
    public function hello($name) { return "hello $name"; }
    public function goodbye($name) { return "goodbye $name"; }
    public static function staticHello($name) { return "static hello $name"; }
}

// basic dynamic method call
$obj = new Greeter();
$m = 'hello';
echo $obj->{$m}('world') . "\n"; // hello world

$m = 'goodbye';
echo $obj->{$m}('world') . "\n"; // goodbye world

// dynamic method call with spread
class Proxy {
    private $target;
    public function __construct($target) { $this->target = $target; }
    public function __call($method, $parameters) {
        $this->target->{$method}(...$parameters);
        return $this->target;
    }
}

class Counter {
    public $count = 0;
    public function increment($by = 1) { $this->count += $by; }
    public function decrement($by = 1) { $this->count -= $by; }
}

$counter = new Counter();
$proxy = new Proxy($counter);
$proxy->increment(5);
echo $counter->count . "\n"; // 5
$proxy->decrement(2);
echo $counter->count . "\n"; // 3

// tap pattern (Laravel-style)
function tap($value) {
    return new class($value) {
        public $target;
        public function __construct($target) { $this->target = $target; }
        public function __call($method, $parameters) {
            $this->target->{$method}(...$parameters);
            return $this->target;
        }
    };
}

$result = tap(new Counter())->increment(10);
echo $result->count . "\n"; // 10

// dynamic call with expression
class Methods {
    public function getA() { return 'A'; }
    public function getB() { return 'B'; }
}
$methods = new Methods();
$prefix = 'get';
foreach (['A', 'B'] as $suffix) {
    $m = $prefix . $suffix;
    echo $methods->{$m}() . "\n"; // A, B
}

// __call fallback for dynamic method names
class MagicObj {
    public function __call($name, $args) {
        return "called $name with " . implode(',', $args);
    }
}
$magic = new MagicObj();
$m = 'anything';
echo $magic->{$m}('x', 'y') . "\n"; // called anything with x,y

// PHP 8 attributes (parsed and skipped, not yet stored for reflection)
#[SomeAttribute]
class WithAttribute {
    #[PropertyAttr]
    public string $name = 'test';

    #[MethodAttr]
    public function getName(): string { return $this->name; }
}
$wa = new WithAttribute();
echo $wa->getName() . "\n"; // test

function attrParam(#[SensitiveParameter] string $secret): string {
    return str_repeat('*', strlen($secret));
}
echo attrParam('password') . "\n"; // ********
