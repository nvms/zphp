<?php
// spl_autoload_register chain
spl_autoload_register(function ($cls) { echo "loader1:$cls "; });
spl_autoload_register(function ($cls) { echo "loader2:$cls "; });
$ok = class_exists("NeverDefined", true); // triggers loaders
echo "|", $ok ? "y" : "n", "\n";

$fns = spl_autoload_functions();
echo count($fns), "\n"; // 2

spl_autoload_unregister($fns[0]);
echo count(spl_autoload_functions()), "\n"; // 1

// closure binding to enum (cannot bind $this; static-only is OK)
enum Color: string { case Red = "red"; case Blue = "blue"; }
$cl = function () { return self::class; };
$bound = Closure::bind($cl, null, Color::class);
echo $bound(), "\n"; // Color

// SplObjectStorage iteration order
$s = new SplObjectStorage();
for ($i = 0; $i < 5; $i++) {
    $o = new stdClass; $o->n = $i;
    $s[$o] = "info$i";
}
foreach ($s as $obj) echo $obj->n, ":", $s->getInfo(), "|";
echo "\n";

// ReflectionClass::implementsInterface
interface IA1 {} interface IB1 extends IA1 {} class CI1 implements IB1 {}
$rc = new ReflectionClass(CI1::class);
var_dump($rc->implementsInterface(IA1::class));
var_dump($rc->implementsInterface(IB1::class));
var_dump($rc->implementsInterface(IteratorAggregate::class));

// ReflectionEnum::getBackingType
enum Stat: int { case On = 1; case Off = 0; }
$re = new ReflectionEnum(Stat::class);
echo $re->isBacked() ? "backed:" : "no:";
$bt = $re->getBackingType();
echo $bt ? $bt->getName() : "null", "\n";

enum Mode { case A; case B; }
$re = new ReflectionEnum(Mode::class);
echo $re->isBacked() ? "backed:" : "no:";
echo $re->getBackingType() === null ? "null" : "type", "\n";

// ReflectionProperty::getDefaultValue
class Cfg {
    public int $a = 42;
    public string $b = "hi";
    public ?array $c = null;
    public array $d = [1, 2, 3];
    public int $e; // no default
}
$rc = new ReflectionClass(Cfg::class);
foreach ($rc->getProperties() as $p) {
    echo $p->getName();
    if ($p->hasDefaultValue()) {
        echo "=";
        var_export($p->getDefaultValue());
    } else {
        echo "<no-default>";
    }
    echo "\n";
}

// traits using other traits
trait Logger { public function log(string $m): string { return "LOG:$m"; } }
trait Verbose { use Logger; public function shout(string $m): string { return strtoupper($this->log($m)); } }
class App { use Verbose; }
echo (new App)->shout("hi"), "\n";

// anonymous function in static context
class Math {
    public static function build(): callable {
        return function ($x, $y) { return $x + $y; };
    }
}
$add = Math::build();
echo $add(3, 4), "\n";

// nullable type with default null
function findUser(?int $id = null): ?array {
    return $id ? ["id" => $id] : null;
}
print_r(findUser(5));
print_r(findUser());

// arrow functions returning array
$f = fn($n) => array_fill(0, $n, "x");
print_r($f(3));

// callable param
function call_it(callable $fn): mixed { return $fn(); }
echo call_it(fn() => 42), "\n";
function noArg() { return "ok"; }
echo call_it("noArg"), "\n";

// array of callables
$ops = ['add' => fn($a,$b) => $a+$b, 'sub' => fn($a,$b) => $a-$b];
echo $ops['add'](5, 3), "|", $ops['sub'](5, 3), "\n";

// closure with __invoke
class CallableObj {
    public function __invoke(int $x): int { return $x * 2; }
}
$co = new CallableObj;
echo $co(7), "\n";
echo call_user_func($co, 5), "\n";

// is_callable
var_dump(is_callable("strlen"));
var_dump(is_callable("noArg"));
var_dump(is_callable("nonexistent"));
var_dump(is_callable(fn() => 1));
var_dump(is_callable([new CallableObj, '__invoke']));
var_dump(is_callable(new CallableObj)); // true (has __invoke)

// nested closure capture by ref
function makeCounter() {
    $n = 0;
    return [
        'inc' => function () use (&$n) { return ++$n; },
        'get' => function () use (&$n) { return $n; },
    ];
}
$c = makeCounter();
$c['inc']();
$c['inc']();
$c['inc']();
echo $c['get'](), "\n"; // 3
