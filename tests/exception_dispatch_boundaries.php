<?php
// an exception reaches the nearest enclosing catch whichever operation raised
// it: an autoloader run by `new` or a static access, a callback run by a
// native, a constructor, a destructor or a generator

spl_autoload_register(function ($class) {
    if ($class === 'Present') {
        eval('class Present { const C = 1; public static $s = 2; public function __construct() {} }');
        return;
    }
    throw new RuntimeException("cannot load $class");
});

function attempt(string $label, callable $f): void
{
    try {
        $f();
        echo "$label: no exception\n";
    } catch (Throwable $e) {
        echo "$label: ", get_class($e), ': ', $e->getMessage(), "\n";
    }
}

attempt('new', fn() => new Missing1);
attempt('static call', fn() => Missing2::run());
attempt('static property', fn() => Missing3::$x);
attempt('class constant', fn() => Missing4::C);
attempt('instanceof keeps quiet', fn() => var_dump(new stdClass instanceof Missing5));
attempt('class_exists', fn() => class_exists('Missing6'));
attempt('loaded', fn() => var_dump(get_class(new Present), Present::C, Present::$s));

// top level, no function in between
try {
    new Missing7;
} catch (RuntimeException $e) {
    echo "top level: ", $e->getMessage(), "\n";
}

// inside a callback a native runs: caught inside, or outside the native
echo json_encode(array_map(function ($i) {
    try {
        return new Missing8;
    } catch (RuntimeException $e) {
        return "inner $i";
    }
}, [1, 2])), "\n";
attempt('through array_map', fn() => array_map(fn($i) => new Missing9, [1]));
attempt('through usort', function () {
    $a = [3, 1, 2];
    usort($a, function ($x, $y) {
        throw new LogicException('in comparator');
    });
});

// constructors, destructors and generators
class Builds { public function __construct() { new Missing10; } }
attempt('constructor', fn() => new Builds);
class Nested { public function __construct() { try { new Missing11; } catch (RuntimeException $e) { echo "caught in constructor\n"; } } }
new Nested;
function gen() { yield 1; new Missing12; yield 2; }
attempt('generator', function () { foreach (gen() as $v) echo "yielded $v\n"; });
function genCatches() { try { yield new Missing13; } catch (RuntimeException $e) { yield 'caught in generator'; } }
foreach (genCatches() as $v) echo "$v\n";

// a fiber catches what its own frames throw
$fiber = new Fiber(function () {
    try {
        new Missing14;
    } catch (RuntimeException $e) {
        Fiber::suspend('caught in fiber');
    }
});
echo $fiber->start(), "\n";

// the handler still runs finally blocks on the way out
function withFinally() {
    try {
        new Missing15;
    } finally {
        echo "finally ran\n";
    }
}
attempt('finally', 'withFinally');
echo "done\n";
