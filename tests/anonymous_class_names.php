<?php
// php names an anonymous class `class@anonymous` (or after its parent or first
// interface), a NUL byte, then the file, line and a runtime declaration number.
// messages and dumps stop at the NUL; get_class and ::class give it whole

function show(string $name): string {
    return str_replace([__FILE__, "\0"], ['FILE', '\0'], $name);
}

interface Shape { public function area(): float; }
interface Named {}
class Base { public function who(): string { return static::class; } }

// a class with an interface is declared at runtime and takes a number too
class Square implements Shape { public function area(): float { return 4.0; } }

$plain = new class {
    private $secret = 1;
    protected $guarded = 2;
    public $open = 3;
    public function fail() { throw new RuntimeException('failed in ' . get_class($this)); }
    public function closure() { return function () { return static::class; }; }
};
$child = new class extends Base {};
$shape = new class implements Shape, Named { public function area(): float { return 1.5; } };

echo show(get_class($plain)), "\n";
echo show(get_class($child)), "\n";
echo show(get_class($shape)), "\n";
echo strlen(get_class($plain)) === strlen("class@anonymous\0" . __FILE__ . ':17$0') ? "length ok\n" : "length differs\n";
echo show($plain::class), "\n";
echo show($child->who()), "\n";
echo show(($plain->closure())()), "\n";

var_dump($plain);
print_r($plain);
echo "\n";
var_dump($child, $shape);
echo show(var_export($child, true)), "\n";
echo get_debug_type($plain), ' ', get_debug_type($child), ' ', get_debug_type($shape), "\n";

foreach ((array) $plain as $key => $value) echo show($key), " => $value\n";

var_dump($plain instanceof $plain, $child instanceof Base, $shape instanceof Named);

try {
    $plain->missing();
} catch (Error $e) {
    echo get_class($e), ': ', $e->getMessage(), "\n";
}
try {
    echo $plain;
} catch (Error $e) {
    echo $e->getMessage(), "\n";
}
try {
    $plain->fail();
} catch (RuntimeException $e) {
    echo show($e->getMessage()), "\n";
    echo show($e->getTraceAsString()), "\n";
}
try {
    serialize($plain);
} catch (Exception $e) {
    echo $e->getMessage(), "\n";
}
function takesInt(int $x) {}
try {
    takesInt($child);
} catch (TypeError $e) {
    echo show($e->getMessage()), "\n";
}
echo $plain->undefinedProperty ?? "undefined property\n";

$r = new ReflectionClass($shape);
echo show($r->getName()), "\n";
var_dump($r->isAnonymous(), (new ReflectionClass('Square'))->isAnonymous());

// the same declaration run again is the same class
$names = [];
for ($i = 0; $i < 3; $i++) {
    $names[] = get_class(new class {});
}
var_dump(count(array_unique($names)));

// a nested anonymous class and one declared inside a function
$outer = new class {
    public function inner() {
        return new class extends ArrayObject {};
    }
};
echo show(get_class($outer)), "\n";
echo show(get_class($outer->inner())), "\n";
function make() {
    return new class implements Countable { public function count(): int { return 7; } };
}
echo show(get_class(make())), ' ', count(make()), "\n";

enum Suit { case Hearts; }
echo show(get_class(new class {})), "\n";

$exception = new class('custom') extends Exception {};
echo show(get_class($exception)), ': ', $exception->getMessage(), "\n";
try {
    throw $exception;
} catch (Exception $e) {
    echo get_debug_type($e), "\n";
}

// a long interface name and the file path make a long class name; methods,
// static variables and callables are found under it all the same
eval('interface ' . str_repeat('VeryLongInterfaceName', 12) . ' { public function resolveName(string $n): string; }');
$long = new class implements VeryLongInterfaceNameVeryLongInterfaceNameVeryLongInterfaceNameVeryLongInterfaceNameVeryLongInterfaceNameVeryLongInterfaceNameVeryLongInterfaceNameVeryLongInterfaceNameVeryLongInterfaceNameVeryLongInterfaceNameVeryLongInterfaceNameVeryLongInterfaceName {
    public function resolveName(string $n): string {
        static $calls = 0;
        $calls++;
        return "$n:$calls";
    }
    public static function staticHelper(): string { return 'static'; }
    public function __invoke($x) { return $x * 2; }
};
echo $long->resolveName('a'), ' ', $long->resolveName('b'), ' ', $long::staticHelper(), ' ', $long(21), "\n";
var_dump(is_callable($long), method_exists($long, 'resolveName'), is_callable([$long, 'staticHelper']));
echo call_user_func([$long, 'resolveName'], 'c'), ' ', (new ReflectionMethod($long, 'resolveName'))->getName(), "\n";
echo strlen(get_class($long)) > 256 ? "long name\n" : "short name\n";
echo get_debug_type($long) === str_repeat('VeryLongInterfaceName', 12) . '@anonymous' ? "debug type ok\n" : "debug type differs\n";

$handler = set_error_handler(function ($no, $message) {
    echo "handler: ", show($message), "\n";
    return true;
});
trigger_error('about ' . get_class($plain), E_USER_WARNING);
echo $plain->nothing;
restore_error_handler();
